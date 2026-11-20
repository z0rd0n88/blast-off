# blast-off

blast-off runs one large multi-phase coding job as a chain of checkpointed Claude Code sessions under
a systemd user unit, with no Claude session open to drive it. Each child session reads the job's
`checkpoint.md`, works one step or phase, rewrites the checkpoint and ends its turn; the runner starts
the next child until the checkpoint says `done` or `blocked`. Around that loop the runner checks child
liveness, a soft child cap, the git tree, usage limits, gate receipts and CI before it accepts a phase
or the job as done.

Design and the full behaviour of every command: [`docs/spec.md`](docs/spec.md). How the units differ
from the systemd guide's template, verified on the build box: [`docs/systemd-guide-deviations.md`](docs/systemd-guide-deviations.md).
Every command and environment variable: the [Options guide](#options-guide); how it works inside:
[Technical details](#technical-details).
The original spec blast-off was built from: [`docs/2026-11-04-large-job-launcher-prompt.md`](docs/2026-11-04-large-job-launcher-prompt.md).
What changed on each day worked: [`CHANGELOG.md`](CHANGELOG.md).

## Requirements

bash, tmux 3.2 or later, jq, python3, git, coreutils `realpath`, systemd (user manager), `claude`,
`gh`; `shellcheck` for the tests. Optional: `jev` with an OpenRouter key (`OPENROUTER_API_KEY`,
`sk-or-`) to pick each phase's
model level ([Options guide](#options-guide)). Linux with a user systemd instance; on WSL2,
`loginctl enable-linger` keeps it up.

## Install

```bash
git clone git@github.com:z0rd0n88/blast-off.git ~/blast-off
~/blast-off/bin/blast-off install          # writes blast-off@.service and blast-off.slice, daemon-reload
ln -s ~/blast-off/bin/blast-off ~/.local/bin/blast-off   # optional
ln -s ~/blast-off/skills/blast-off ~/.claude/skills/blast-off   # optional: the Claude Code skill
```

`install` writes only `~/.config/systemd/user/blast-off@.service` and `blast-off.slice` and reloads the
user manager. It never runs `enable`: a job runner is not a boot-time service. The slice limits
(`MemoryHigh=14G`, `MemoryMax=18G`, `CPUQuota=1600%`, `TasksMax=4096`, oomd at 65% memory pressure) are
sized for a 20-core, 23 GB box; change them with a drop-in.

## Write a job

A job is a directory, by convention `<worktree>/.big-next-job/`, holding `brief.md` and
`checkpoint.md`. The workdir is the job dir's parent: a dedicated git worktree on a feature branch.
Keep the job dir out of git (from inside the worktree, where `.git` is a file):
`echo .big-next-job/ >> "$(git rev-parse --git-common-dir)/info/exclude"`.

1. Copy `templates/brief.md` and fill every section. §4's **Target set** is the exact list of tracked
   paths the job may change, plus a "may widen to" list; the owner confirms it as its own question
   before launch. §9, the child protocol, stays verbatim.
2. Copy `templates/checkpoint.md`: `status: running`, one Phase plan row per phase (from the left
   margin, first cell its key, Status cell last), the first `Next action`. Keep the HTML comment: it lists the rules the runner enforces.
3. The workdir's name (letters, digits, `-`, `_`) names the unit `blast-off-<name>.service` and the
   tmux server `blast-off-<name>`.

The skill [`skills/blast-off/SKILL.md`](skills/blast-off/SKILL.md) walks a Claude session through
scoping, writing both files and handing over the start line. Start that session inside the target repo
(the repo the job changes), not in another project's checkout or worktree: a session loads that
directory's `AGENTS.md`/`CLAUDE.md` and hooks on every turn.

## Check, then start

```bash
export GH_TOKEN CLAUDE_FLAGS="--model opus --effort high"   # plus any flags the owner allows
blast-off preflight <worktree>/.big-next-job   # prints flags, model level, cap, child count, timeout, account, usage, estimate, open PRs, behind count
blast-off start <worktree>/.big-next-job       # transient unit blast-off-<name>.service in blast-off.slice
```

`preflight` exits 1 and says why when `CLAUDE_FLAGS` is empty, a dependency is missing, `brief.md` is
missing, `child-count` is garbled, a `JOB_*` number is bad, or the
estimated usage is more than the 7-day window has left. `start` passes `PATH`, `GH_TOKEN`,
`CLAUDE_FLAGS` and every set `JOB_*` and `BLAST_OFF_*` name the runner or its children read (not
`JOB_BASE` or `BLAST_OFF_ESTIMATE_FROM`, which only `preflight` reads, nor `BLAST_OFF_WAIT_POLL`,
which only `wait` reads) to the unit by name (`systemd-run --setenv=NAME`), never by value; it
refuses to start with `GH_TOKEN` or `CLAUDE_FLAGS` unset or empty, or a bad `JOB_*` number.
With `OPENROUTER_API_KEY`
set to an `sk-or-` key and `JOB_JEV` not `0`, it passes that name too, so Jev picks each phase's
model level under the unit; otherwise every child
gets `CLAUDE_FLAGS` as given. Each pick or fallback is a `run.log` line (`model level for phase 2: light
(jev, confidence 0.87, threshold 0.7): ...`), never with the key. The resume timer passes the same names,
with the values they had when it was armed: a key exported or rotated later never reaches it.
systemd keeps the resolved values, the secrets too, in the transient unit's file under
`$XDG_RUNTIME_DIR` until the unit is collected. Children never get `OPENROUTER_API_KEY`: only the runner
calls Jev.

A hand-started template instance (`systemctl --user start blast-off@<escaped job dir>.service`) sees
only the user manager's environment, which has no `CLAUDE_FLAGS` and no `claude` on `PATH`, so it
exits 1. Use `blast-off start`.

**Permission rule.** A Claude session that hands over a job runs nothing: the owner runs the start
line. For a session that should run it, the owner adds an allow rule for that command text to
`permissions.allow` in the project's `.claude/settings.json`: `"Bash(blast-off start:*)"`. The rule
matches the command as written, so `/abs/path/bin/blast-off start ...` needs its own rule
(`"Bash(/abs/path/bin/blast-off start:*)"`). It does not match past a leading `CLAUDE_FLAGS=...` (an
allow rule stops at an assignment of a variable not on Claude Code's known-safe list), so the session
types the bare line, with `GH_TOKEN` and `CLAUDE_FLAGS` already in its environment: exported before
`claude` starts, or `CLAUDE_FLAGS` (never `GH_TOKEN`) in that settings file's `env`. In auto mode a matching narrow allow rule resolves before
the classifier; with no rule the classifier decides, and its denial is final: the owner runs the line
(`! CLAUDE_FLAGS='<flags>' blast-off start <job-dir>` in the prompt with `GH_TOKEN` exported, or the
block above in a terminal). blast-off never writes settings and never works around
the classifier.

## Watch, stop, resume

```bash
blast-off wait <job-dir>      # blocks until the status, phase, child or unit changes; prints one line
blast-off status <job-dir>    # checkpoint header, unit state, child count, resume timer
blast-off logs <job-dir>      # run.log tail and the unit's journal
tail -f <job-dir>/run.log     # the chain's own log: children, picks, pauses, refusals
tmux -L blast-off-<name> attach -t job-<name>   # watch the live child (detach: C-b d)
blast-off stop <job-dir>      # stops the runner, its children and any resume timer
blast-off resume <job-dir>    # a paused-cap job, or a paused-limit one after its reset
blast-off run <job-dir>       # the same chain in the foreground (what the unit runs)
```

Re-running is always safe: the next child resumes from the checkpoint's `Next action`; nothing is redone.

**Watching from a Claude session.** Run `blast-off wait <job-dir>` as a background command, not a
recurring loop or cron: the session wakes only when it returns. It reads the checkpoint's `status:` and
`phase:` lines, the last child's number and the runner unit's and resume timer's state every 5 s
(`BLAST_OFF_WAIT_POLL`), and, at `done` or `blocked`, the job dir's `runner-end`, which the runner writes only when
it accepts that end. It never reads `run.log`, which holds child text. A change is state, never the clock, so a machine
sleep is not an event. It prints one line, `wait: <final|changed|stuck> · status: ... · phase: ... · child <n> · unit <state> · timer <state>`
(the status word, at most 80 characters, and a `paused-limit`'s `until <time>`, the time at most 40 characters; the phase line
without control characters and with each `·` turned into `-`, at most 80 characters):

| Line | Exit | What to do |
|---|---|---|
| `final`: status `done` or `blocked` and `runner-end` holds the same word: the runner accepted it (at once when already there). A `done` or `blocked` with no matching `runner-end` keeps `wait` waiting while the unit runs: the runner may still refuse it (receipts, CI, dirty tree) | 0 | stop watching; read `checkpoint.md` |
| `changed`: a child launched, the phase or status moved, or the unit's or timer's state changed, and the job still runs or is scheduled | 11 | run `blast-off wait <job-dir>` again |
| `stuck · status: paused-cap ...; paused-cap: run blast-off resume <job-dir>`: the soft cap paused the job and nothing runs | 12 | `blast-off resume <job-dir>`, then `wait` again |
| `stuck ...; see blast-off status <job-dir>`: for 10 s (at least two polls) neither the runner unit nor a resume timer runs, and no `runner-end` matches the status (stopped, crashed, a reboot, a refused `done` or `blocked`, `paused-limit` with no timer); it never changes on its own | 12 | `blast-off status` and `logs`; fix what the runner refused, then `start`; `resume` for a `paused-limit` past its reset |
| `stuck · no read for 60 s: <reason>; see blast-off status <job-dir>`: every read failed for 60 s or more (at least one retry, so a long `BLAST_OFF_WAIT_POLL` stretches it; job dir deleted or moved, `checkpoint.md` left empty, the user bus gone); a shorter spell is retried at each poll | 12 | fix the reason, then `wait` again |
| no `<job-dir>` argument, no job dir, a workdir name that is not letters, digits, `-` or `_`, a missing or empty `checkpoint.md`, a `BLAST_OFF_WAIT_POLL` outside 0.1 to 3600, or `systemctl --user` failing, at its start (the reason is on stderr) | 1 | fix the cause, then `wait` again; an empty `checkpoint.md` mid-rewrite or a bus hiccup clears on its own, so one plain rerun is fine |

`wait` watches the unit, so run it after `start`; a foreground `blast-off run` reads as `stuck`.

**Usage limits.** At each child's end the runner reads that session's usage record,
`~/.claude/state/usage-limits-<session>.json`, which a status-line hook (`usage-limit-tee.sh`, not part
of blast-off) writes; with no such hook there is no record and only the rate-limit and exit-75 pauses work. A window at or above 95%
(`JOB_USAGE_PAUSE`), a rate-limit StopFailure or child exit 75 writes `status: paused-limit until
<time>` and exits 8; a transient timer `blast-off-<name>.resume.timer` runs `blast-off resume` 60 s after
the reset. The timer lives on tmpfs: after a reboot `status` prints the `resume` line to run by hand.

## Closing a phase: receipts and CI

A child closes a phase in this order: commit; save the gate output to
`<job-dir>/gate-logs/phase-<n>.log` (its last line `GATE: PASS` or `GATE: FAIL`); then

```bash
blast-off receipt <job-dir> <n>     # gate-logs/phase-<n>.json: verdict, tally, HEAD sha, UTC time
blast-off ci-wait <job-dir> <pr>    # one blocking gh run watch per CI run of the PR head
```

and finally the row's Status cell `done (<sha>) · PR #<pr>`, or `done (<sha>) · no PR` for a phase
the brief says opens no PR (a PR that could not be opened is a blocked part, not `no PR`). The runner refuses a done row without a PASS receipt for its sha (exit 9). It
refuses `status: done` (exit 10) while a done row's Status cell says neither `PR #<pr>` nor `no PR`,
while the Phase plan has no row the runner reads, while the Phase plan section is not one table (its header
ending in Status, the separator, one row per phase from the left margin with the header's cells) and
plain notes under it, or the file has a second Phase plan heading, and while the CI of a PR named in such a cell is red, unread,
or absent (no runs) where the PR's head commit has a workflow file. PRs are read only from those
cells, never from prose; `run.log` says which were read.

The done gate defends against a child that is lazy or confused, not one that crafts Markdown or HTML to
hide a PR from it: children run as the owner's user with bypass permissions and could edit the runner
itself, so a malicious child is out of scope (owner ruling 3 of phase 3). A checkpoint written by
following `templates/checkpoint.md` and `templates/brief.md` is never refused for its format and never
slips the gate.

## Options guide

`<name>` is the workdir's basename. The workdir is the job dir's parent, except for the commands
that take a `[workdir]`. Every command that takes `<job-dir>` exits 1 when it is missing or not a
directory, or when the workdir's name is not letters, digits, `-` or `_`; an unknown command exits
1.

| Command | What it does | Exit |
|---|---|---|
| `run <job-dir> [workdir]` | The chain in the foreground; the unit's `ExecStart` | [Exit codes](#exit-codes); 129, 130 or 143 when HUP, INT or TERM stops it |
| `start <job-dir>` | Refuses an unset or empty `CLAUDE_FLAGS` or `GH_TOKEN`, a missing or empty `brief.md` or `checkpoint.md`, or a bad `JOB_*` number, then runs `run` as the transient unit `blast-off-<name>.service` and prints its `systemd-run` line | 0 started; 1 refused; `systemd-run`'s code when it fails |
| `status <job-dir>` | Prints `checkpoint.md` down to its first `## ` heading, the unit's `ActiveState`, the child count, the resume timer's state and, for a `paused-limit` with no timer, the `resume` line to run | 0; 2 with no `checkpoint.md` |
| `stop <job-dir>` | Stops the runner unit, every child scope and the resume timer | 0; 1 when the unit is still active |
| `logs <job-dir>` | The last 40 lines of `run.log` and of the unit's journal | 0 |
| `resume <job-dir>` | For `paused-cap`, or `paused-limit` once its time has passed: the checks of `start`, up to 90 s for the old unit to stop, then a start; then stops the resume timer | 0 started; 8 before the `paused-limit` time; 1 any other status, or a refused or failed start; 2 with no `checkpoint.md` |
| `wait <job-dir>` | Blocks until the job changes, prints one line | 0, 11, 12 or 1: [Watch, stop, resume](#watch-stop-resume) |
| `install` | Writes the unit template and the slice, reloads the user manager; never enables | 0 |
| `preflight <job-dir> [workdir]` | Prints what a start would use and meet; writes nothing to the job dir (`behind` runs `git fetch origin <JOB_BASE>`) | 0 `preflight: ok`; 1 `preflight: refused: <why>` |
| `receipt <job-dir> <phase> [workdir]` | `gate-logs/phase-<phase>.json` from the last line of `gate-logs/phase-<phase>.log` and `HEAD`; refused while the tree has uncommitted paths outside the job dir | 0 PASS; 1 FAIL or refused |
| `ci-wait <job-dir> <pr> [workdir]` | Watches each CI run of the PR's head, records the runs and a verdict in `gate-logs/ci-pr-<pr>.json` | 0 green; 10 red, unfinished or no runs; 1 a bad PR number or a failed `gh pr view`, `gh run list` or `gh run view` |
| `--help`, `-h` or no command | Prints the header of `bin/blast-off` | 0 |

Environment. A count is a whole number of at most 9 digits with no leading zero; `run`, `start`,
`resume` and `preflight` refuse a count or a `JOB_JEV_MIN_CONF` outside its values. "Read by" names
the commands; [Check, then start](#check-then-start) says which names `start` passes to the unit
(children inherit the unit's environment, less every `CLAUDE*` name and `OPENROUTER_API_KEY`,
through the job's tmux server).

| Variable | Default | Values | Effect | Read by |
|---|---|---|---|---|
| `CLAUDE_FLAGS` | none; required | `claude` flags | Every child's flags; a Jev pick replaces only `--model` and `--effort` | `run`, `start`, `resume`, `preflight` |
| `GH_TOKEN` | none | a GitHub token | `start` and `resume` refuse without it; through the unit it reaches the runner, its children and their `gh` calls; unset, the runner arms no resume timer | `start`, `resume`, `run`, `preflight` |
| `OPENROUTER_API_KEY` | none | an `sk-or-` key | Jev's key; none or another kind keeps `CLAUDE_FLAGS`. Passed to the unit only when it is `sk-or-` and `JOB_JEV` is not `0`; never given to a child | `run`, `start`, `resume`, `preflight` |
| `JOB_JEV` | on | `0`, or anything else for on | `0`: no Jev | `run`, `start`, `resume`, `preflight` |
| `JOB_JEV_MIN_CONF` | `0.7` | 0 to 1, at most 3 decimals | A Jev pick below this confidence keeps `CLAUDE_FLAGS` | `run`, `preflight` |
| `JOB_CHILD_TIMEOUT` | `7200` | count | Seconds a child may run before it is stopped and the next child starts | `run`, `preflight` |
| `JOB_CAP_FACTOR` | `3` | count | Soft cap = Phase plan rows times this | `run`, `preflight` |
| `JOB_MAX_CHILDREN` | unset | count | With Phase plan rows: the soft cap instead; with none: the hard cap (default 12) | `run`, `preflight` |
| `JOB_USAGE_PAUSE` | `95` | count | Pause when a usage window is at or above this percent at a child's end | `run` |
| `JOB_RESUME_MARGIN` | `60` | count | Seconds after the usage reset that the resume timer fires | `run` |
| `JOB_API_BACKOFF` | `600` | count | Seconds before the next child after an `overloaded`, `server_error` or `unknown` API error | `run` |
| `JOB_SESSION` | `job-<name>` | a tmux session name | The session on the job's tmux server `blast-off-<name>` | `run`, `start` |
| `JOB_KEEP_WINDOWS` | unset | any non-empty value, `0` too | Keeps a finished child's window, scope and settings dir, and the tmux server and scopes when the runner exits; a timed-out or failed child is still stopped | `run` |
| `JOB_BASE` | `main` | a branch | `preflight`'s behind count, `git rev-list --count HEAD..origin/<JOB_BASE>`, after fetching it | `preflight` |
| `BLAST_OFF_TRUST_SECONDS` | `60` | whole seconds | How long after a child starts its trust dialog is answered | `run` |
| `BLAST_OFF_STATE_DIR` | `~/.claude/state` | a directory | Where the `usage-limits-<session>.json` records are read | `run`, `preflight` |
| `BLAST_OFF_ESTIMATE_FROM` | this job's `checkpoint.md` | a `checkpoint.md` path | Whose Phase plan rows give `preflight`'s usage estimate | `preflight` |
| `BLAST_OFF_CI_APPEAR` | `60` | whole seconds | How long `ci-wait` waits for the PR head's runs to be listed (not to finish) | `ci-wait` |
| `BLAST_OFF_CI_WATCH` | `3600` | seconds | How long `ci-wait` watches one run; past it the run is recorded as it stands | `ci-wait` |
| `BLAST_OFF_CI_HEAD` | `60` | seconds | How long the runner's `gh pr view` of a PR head may take at `done`; past it the CI is unread (exit 10) | `run` |
| `BLAST_OFF_WAIT_POLL` | `5` | 0.1 to 3600, at most 3 decimals | Seconds between `wait`'s reads | `wait` |
| `PATH` | | | Must hold `claude`, `tmux`, `python3`, `jq`, `systemd-run`, `systemctl`, `git`, `realpath` (and `gh` for `preflight`); children get this checkout's `bin/` first | `run`, `start`, `preflight` |
| `XDG_CONFIG_HOME` | `~/.config` | a directory | `install` writes to its `systemd/user` | `install` |
| `XDG_RUNTIME_DIR` | `/tmp` | a directory | Holds the runner's lock, each child's settings dir and temp files | `run`, `preflight` |
| `BLAST_OFF_TEST_*`, `BLAST_OFF_NO_SHELLCHECK` | | | Tests only: `_ONLY` and `_KEEP` in [Tests](#tests), all of them in the header of `tests/run` | `tests/run` |

## Exit codes

| Code | Meaning | What to do |
|---|---|---|
| 0 | job done | read the final report in `checkpoint.md` |
| 1 | usage, dependency or runner error; `preflight` refused | read the message or the last `run.log` line, fix, run again |
| 3 | blocked: the job needs the owner | answer what `Open or blocked` asks, set `status: running`, `start` again |
| 4 | hard child cap, counted over every run of the job in its `child-count` (no Phase plan row the runner reads; such a job ends `done` only once its Phase plan table has its rows, else exit 10) | add a Phase plan table with a row per phase and start again; that start can pause at `paused-cap` before any child, since the children already launched count against the first soft allotment, so `blast-off resume <job-dir>` then; raising `JOB_MAX_CHILDREN` alone gives more children, not a way to `done`; deleting `child-count` is the one reset of the count |
| 5 | two children in a row left `checkpoint.md` unchanged | read the children's closing summaries in `run.log`; fix the brief or `Next action` |
| 6 | soft cap reached, `status: paused-cap` | `blast-off resume <job-dir>` (a fresh allotment of the cap; child numbers go on) |
| 7 | uncommitted paths the checkpoint does not name | commit, remove, or name them in the checkpoint; start again |
| 8 | usage limit, `status: paused-limit until <time>` | nothing while `status` shows the resume timer active; else `blast-off resume <job-dir>` after `<time>` |
| 9 | a done Phase plan row lacks its commit or a PASS receipt for it | run the gate, `blast-off receipt`, fix the row's sha |
| 10 | done refused: a done Phase plan row's Status cell says neither `PR #<pr>` nor `no PR` (or the Phase plan has no row the runner reads, or holds a line that is neither part of its one table nor a plain note under it, or there is a second Phase plan heading); or the CI of a PR named in such a cell is red, unread, or absent (no runs) while the PR's head commit has a workflow file or cannot be read in the workdir's repo | the last `run.log` line names the row or the PR, the case, and what to write or run. Row: add `PR #<pr>`, or `no PR` if the brief says the phase opens none; a Phase plan line named: rewrite it as a row of the one table (from the left margin, the header's cells, Status last) or delete it; a second Phase plan heading: rename or delete it. Red: fix CI and push. Then `blast-off ci-wait <job-dir> <pr>` after the last push. Absent: push to the PR branch so a run starts, then `ci-wait`; fetch the PR's head first if the line says it cannot be read. There is no override for a PR no workflow can start on (a branch or path filter): ask the owner, who can change the PR base or the trigger filter; `no PR` is no way out. Never add, remove or edit a workflow file to change a CI result |

Every non-zero code except 1 is a state, not a failure: the unit has no `Restart=`, and the runner is
safe to run again.

## Calling blast-off from big-next-job

`big-next-job`'s Run mode launches its own `run-job` with `nohup`. To run the job under blast-off
instead, the skill writes the brief and checkpoint from **blast-off's** templates (they carry the rules
the runner enforces: row keys (0, 1, 2a), `done (<sha>)` cells, receipts, `ci-wait`; a checkpoint from
big-next-job's template ends in exit 9 at its first done row) into `<worktree>/.big-next-job/`, then
replaces its launch line with the [Check, then start](#check-then-start) block (`export GH_TOKEN
CLAUDE_FLAGS=...`, `blast-off preflight <job-dir>`, `blast-off start <job-dir>`)
for the owner. blast-off never reads or writes big-next-job's files.

## Tests

```bash
tests/run    # every tests/NN-*.sh with fake claude, gh and jev; shellcheck; ends GATE: PASS or GATE: FAIL
```

Scenarios start real `blast-off-test-<pid>-*` units, child scopes and tmux servers in the user manager and stop them; they need a live user systemd instance.

`BLAST_OFF_TEST_ONLY="30-paused-limit 41-ci-wait"` (spaces or commas) runs only those scenarios, for a
diagnosis: the verdict line is then `GATE-ONLY: PASS|FAIL ... only=<names>`, which `blast-off receipt`
refuses, and a name that is no scenario fails. `BLAST_OFF_TEST_KEEP=<dir>` keeps each scenario's work
dir as `<dir>/<name>` instead of removing it (not under `bin/`, `lib/` or `tests/`). `scripts/gate.sh
<log-dir>` runs `tests/run`, tees its output to `<log-dir>/tests-run.log` and exits with its status.
CI (`.github/workflows/ci.yml`) runs `tests/run` on every pull request, the job capped at 30 minutes
and the gate step at 25; a red run uploads the kept work dirs as the artifact `blast-off-tests`
(`blast-off-tests.tgz`). A manual dispatch takes an `only` input, passed to `BLAST_OFF_TEST_ONLY`.

## Technical details

```text
blast-off start <job-dir>
  | systemd-run --user --unit=blast-off-<name>, the template's [Service] lines as -p
  v
blast-off-<name>.service in blast-off.slice: blast-off run <job-dir>, the runner
  | per child: a window on tmux server blast-off-<name>, session job-<name>
  v
blast-off-<name>-child-<n>.scope: claude <flags> --settings <child dir>/settings.json '<prompt>'
  | reads checkpoint.md and brief.md, works, rewrites checkpoint.md, ends its turn
  v
Stop hook writes <child dir>/done.json; the runner stops the scope, checks, launches the next child
```

### systemd

`install` writes `systemd/blast-off@.service` to `${XDG_CONFIG_HOME:-~/.config}/systemd/user/` with
`@BLAST_OFF@` replaced by this checkout's `bin/blast-off`, copies `blast-off.slice` beside it and
runs `systemctl --user daemon-reload`. The template's `[Service]` lines are `Type=exec`,
`ExecStart=<bin/blast-off> run %f`, `Slice=blast-off.slice`, `KillMode=control-group`,
`ManagedOOMPreference=avoid` and `TimeoutStopSec=60`; it has no `Restart=` and no `[Install]`. Its
instance name is the path-escaped job dir, which `%f` turns back into the absolute path.

`start` and `resume` never start the template. They run `systemd-run --user --collect
--unit=blast-off-<name> --working-directory=<workdir>`, a `--setenv=NAME` with no value for each
name [Check, then start](#check-then-start) lists (systemd-run copies the value from its own
environment), and a `-p` for each `[Service]` line of the template except `ExecStart`, then
`<bin/blast-off> run <job-dir>`. Each child runs in `blast-off-<name>-child-<n>.scope`, made by
`systemd-run --user --scope --slice=blast-off.slice`. Scopes sit outside the runner's cgroup, so the
runner and `stop` stop them by name: `stop` runs `systemctl --user stop` on the runner unit,
`blast-off-<name>-child-*.scope` and `blast-off-<name>.resume.timer`.

The resume timer. At a usage pause (**Usage limits** in [Watch, stop, resume](#watch-stop-resume);
the record is read by the session id of the child's Stop payload) the runner stops any earlier
`blast-off-<name>.resume.timer` and `.resume.service`, then runs `systemd-run --user --quiet
--collect --unit=blast-off-<name>.resume --on-calendar='<date> <time> UTC'
--timer-property=AccuracySec=1s`, the same `--setenv` names, and `<bin/blast-off> resume <job-dir>`.
The time is the latest reset among the windows at or over `JOB_USAGE_PAUSE`, else the five-hour
window's reset, else five hours from now; plus `JOB_RESUME_MARGIN`, and at least 5 s ahead. A
calendar timer that elapses while the machine sleeps fires on wake. When it fires, `resume` waits up
to 90 s for the old runner unit to go inactive, starts the runner as `start` does and stops the
timer. The runner arms no timer, and logs the line to type instead, when `GH_TOKEN` is unset or the
workdir is not the job dir's parent (`resume` takes only the job dir).

Every call is `systemctl --user` or `systemd-run --user`, so the jobs live in the user manager and
need its bus; blast-off never calls `loginctl`, so lingering ([Requirements](#requirements)) is the
owner's to set. Under the unit, the runner's stdout and stderr go to its journal: each line it logs
to `run.log` is printed there too, and some errors that stop it (an empty `CLAUDE_FLAGS`, a command
not on `PATH`) are only there.

### The runner

`blast-off run` checks `CLAUDE_FLAGS`, the commands it needs, `brief.md`, `checkpoint.md`, the
`JOB_*` values and `child-count`, and exits 1 when one fails. Then:

1. **Lock.** `$XDG_RUNTIME_DIR/blast-off-<name>.lock`, created with `noclobber`, holds the runner's
   pid and that pid's start time from `/proc/<pid>/stat`. A live holder refuses the run (exit 1); a
   dead or reused pid is stale and taken over.
2. **Traps.** On any exit the runner ignores further `HUP`, `INT` and `TERM`, stops every child
   scope, the tmux server and the child dirs (not with `JOB_KEEP_WINDOWS`), removes its lock, and
   turns an exit that is not a state or a signal into 1. `TERM` logs and exits 143, `HUP` 129, `INT`
   130.
3. **Setup.** It deletes `runner-end`, starts the tmux server, logs the cap and the child count, and
   finds the workdir's git top level (outside git the dirty-tree and receipt checks are off). A
   `paused-cap` becomes `running` (under the soft cap with a fresh allotment); a `paused-limit`
   whose time has passed becomes `running`, one still ahead exits 8. Then the dirty-tree check (exit
   7).
4. **Loop.** The receipt check (exit 9). At `done`: the Phase plan, open-row and CI checks (exit 9
   or 10), then `runner-end` and exit 0. At `blocked`: `runner-end` and exit 3. The cap (exit 4
   hard; soft: `paused-cap`, exit 6). A due API back-off sleep. The checkpoint's fingerprint (the
   first 16 hex digits of its sha256) and a warning when it is over 150 lines. The flags.
   `child-count` updated, then the launch, the wait, the report, the stop. Usage read, and ` · usage
   <figures>` appended to the Status cell of each row done by this child. The dirty-tree check. A
   usage pause (exit 8) unless the child set `done` or `blocked`. A stall when the fingerprint did
   not change; the second in a row exits 5.

Status words: children write only `running`, `done` or `blocked` (`templates/brief.md` §9). The
runner writes only `paused-cap`, `paused-limit until <time>` and `running` when it takes up a paused
job; `done` and `blocked` it only accepts. What each exit means: [Exit codes](#exit-codes).

### The child

The job's tmux server, `tmux -f /dev/null -L blast-off-<name>`, holds one session, `JOB_SESSION`
(default `job-<name>`), in the workdir. `-f /dev/null` keeps the owner's `tmux.conf` out. Its global
environment, which every window inherits, is the runner's less every `CLAUDE*` name and
`OPENROUTER_API_KEY`, with this checkout's `bin/` first on `PATH` and `BLAST_OFF` set to its
`bin/blast-off`. `remain-on-exit` is on, so a dead child's pane and last screen stay. A run first
stops whatever an earlier run left: the server, the child scopes and the child dirs.

Flags. Before a child, when the first open Phase plan row differs from the last pick's, the runner
asks Jev (when `JOB_JEV`, `OPENROUTER_API_KEY` and `jev` allow): the row's text goes to `jev` on
stdin, with `TYPESAFE_API_KEY` and `JEV_BASE_URL` removed and a 60 s timeout, as a choice of `light`
(`--model sonnet --effort medium`), `standard` (`--model opus --effort high`) or `deep` (`--model
opus --effort xhigh`), which replaces `--model` and `--effort` in `CLAUDE_FLAGS`. Any other answer,
a failure or a low confidence keeps `CLAUDE_FLAGS`. Each pick is a `run.log` line and a
`decisions.tsv` row.

Launch. Each child gets a dir `$XDG_RUNTIME_DIR/blast-off-<name>-child.XXXXXX` holding
`settings.json` from `templates/settings.child.json`: a `Stop` hook that writes its JSON payload to
`done.json` and a `StopFailure` hook that writes `failed.json`. A new window, with `JOB_DIR` and
`JOB_CHILD` set, runs `systemd-run --user --scope ... claude <flags> --settings <dir>/settings.json
'<prompt>'` and then writes claude's exit status to `<dir>/exit`. The prompt is fixed: continue the
job, read `checkpoint.md`, then `brief.md`, then follow the brief's Child protocol, working from the
workdir.

Wait. Once a second the runner checks, in this order: `done.json` (the turn ended), `failed.json`
(an API error ended it), the pane dead, or unreadable twice in a row (claude exited), the age past
`JOB_CHILD_TIMEOUT` (a hang). For the first `BLAST_OFF_TRUST_SECONDS` it also reads the screen and,
when it shows `Yes, I trust this folder`, sends `Down Enter`.

End. On `done.json` the runner writes the payload's `session_id`, `transcript_path` and
`last_assistant_message` to `run.log` (its tail to the journal), then stops the scope and closes the
window. On `failed.json` it logs the same and the error, and stops the child: `rate_limit` pauses
the job, `overloaded`, `server_error` and `unknown` wait `JOB_API_BACKOFF` before the next child. A
timed out child is logged and stopped. A child that exited first has its exit status and its last 40
screen lines logged and is stopped; exit 75 pauses the job. Then the child dir is removed.
`JOB_KEEP_WINDOWS` keeps the window, scope and dir of a child that ended its turn, and the dir of
every child.

### Job-dir state

| File | Written by | Holds |
|---|---|---|
| `brief.md` | the owner | the job; `run` and `start` check it is not empty, `preflight` reads its Target set |
| `checkpoint.md` | children; the runner rewrites only the first `status:` line and appends ` · usage ...` to rows done | status, phase, Phase plan, `Next action` |
| `run.log` | the runner, `resume`, `receipt`, `ci-wait` | UTC-stamped lines: picks, launches, child reports and screens, refusals, pauses |
| `child-count` | the runner, before each launch, by rename | `<launched> <base>`: the last child's number and the soft cap's base; deleting it resets the count |
| `runner-end` | the runner, by rename, when it accepts `done` or `blocked`; deleted by each run once it holds the lock | `<word> <UTC time>`, which `wait` reads |
| `decisions.tsv` | the runner, at each pick | tab-separated rows under the header `ts phase decision why evidence result` |
| `gate-logs/phase-<n>.log` | the child | its gate output, last line `GATE: PASS` or `GATE: FAIL` |
| `gate-logs/phase-<n>.json` | `receipt` | phase, verdict, verdict line, tally, gate log, `HEAD` sha, UTC time |
| `gate-logs/ci-pr-<pr>.json` | `ci-wait` | PR, head sha, UTC time, each run's id, name and conclusion, verdict `success`, `failure` or `absent` |

`phases/` is never written by blast-off: the over-150-lines warning suggests it for a child's
ledgers. The usage records are read from `BLAST_OFF_STATE_DIR`, written by a status-line hook
([Watch, stop, resume](#watch-stop-resume)).

Receipts and CI. `receipt` takes the gate log's last non-empty line, which must start `GATE: `, and
refuses while the workdir's repo has uncommitted paths outside the job dir. `ci-wait` reads the PR's
head sha with `gh pr view`, lists that commit's runs (not `workflow_dispatch`), re-reading an empty
list every 5 s for up to `BLAST_OFF_CI_APPEAR`, runs `gh run watch <id> --exit-status` under
`BLAST_OFF_CI_WATCH` for each, lists again for runs that appeared since (at most 3 rounds), and
records them; the verdict is `success` when every conclusion is `success`, `skipped` or `neutral`.
Each loop pass the runner checks every done row: its sha is in `HEAD`'s history, its receipt is a
PASS for that sha that still matches its gate log, and, for a row done by the last child, `git diff
<sha> HEAD` is empty outside the job dir. At `done` it reads each PR's record and checks its head
sha against a fresh `gh pr view` (under `BLAST_OFF_CI_HEAD`); the rules are in [Closing a
phase](#closing-a-phase-receipts-and-ci).
