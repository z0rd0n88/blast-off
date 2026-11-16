# blast-off

blast-off runs one large multi-phase coding job as a chain of checkpointed Claude Code sessions under
a systemd user unit, with no Claude session open to drive it. Each child session reads the job's
`checkpoint.md`, works one step or phase, rewrites the checkpoint and ends its turn; the runner starts
the next child until the checkpoint says `done` or `blocked`. Around that loop the runner checks child
liveness, a soft child cap, the git tree, usage limits, gate receipts and CI before it accepts a phase
or the job as done.

Design and the full behaviour of every command: [`docs/spec.md`](docs/spec.md). How the units differ
from the systemd guide's template, verified on the build box: [`docs/systemd-guide-deviations.md`](docs/systemd-guide-deviations.md).
Every option and environment variable: the header of [`bin/blast-off`](bin/blast-off).

## Requirements

bash, tmux 3.2 or later, jq, python3, systemd (user manager), `claude`, `gh`; `shellcheck` for the
tests. Optional: `jev` with an OpenRouter key (`OPENROUTER_API_KEY`, `sk-or-`) to pick each phase's
model level. Linux with a user systemd instance; on WSL2, `loginctl enable-linger` keeps it up.

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
2. Copy `templates/checkpoint.md`: `status: running`, one Phase plan row per phase (first cell a
   digit), the first `Next action`. Keep the HTML comment: it lists the rules the runner enforces.
3. The workdir's name (letters, digits, `-`, `_`) names the unit `blast-off-<name>.service` and the
   tmux server `blast-off-<name>`.

The skill [`skills/blast-off/SKILL.md`](skills/blast-off/SKILL.md) walks a Claude session through
scoping, writing both files and handing over the start line.

## Check, then start

```bash
export GH_TOKEN CLAUDE_FLAGS="--model opus --effort high"   # plus any flags the owner allows
blast-off preflight <worktree>/.big-next-job   # prints flags, model level, cap, timeout, account, usage, estimate, open PRs, behind count
blast-off start <worktree>/.big-next-job       # transient unit blast-off-<name>.service in blast-off.slice
```

`preflight` exits 1 and says why when `CLAUDE_FLAGS` is empty, a dependency is missing, or the
estimated usage is more than the 7-day window has left. `start` passes `PATH`, `GH_TOKEN`,
`CLAUDE_FLAGS` and every set `JOB_*` name to the unit by name (`systemd-run --setenv=NAME`), never by
value; it refuses to start with `GH_TOKEN` or `CLAUDE_FLAGS` unset or empty. systemd keeps the
resolved values in the transient unit's file under `$XDG_RUNTIME_DIR` until the unit is collected.

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
blast-off status <job-dir>    # checkpoint header, unit state, resume timer
blast-off logs <job-dir>      # run.log tail and the unit's journal
tail -f <job-dir>/run.log     # the chain's own log: children, picks, pauses, refusals
tmux -L blast-off-<name> attach -t job-<name>   # watch the live child (detach: C-b d)
blast-off stop <job-dir>      # stops the runner, its children and any resume timer
blast-off resume <job-dir>    # a paused-cap job, or a paused-limit one after its reset
blast-off run <job-dir>       # the same chain in the foreground (what the unit runs)
```

Re-running is always safe: the next child resumes from the checkpoint's `Next action`; nothing is redone.

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

and finally the row's Status cell `done (<sha>) · PR #<pr>`. The runner refuses a done row without a
PASS receipt for its sha (exit 9) and `status: done` while the CI of a PR named in a Phase plan Status
cell is red, unread, or absent (no runs) with a workflow file at HEAD (exit 10). With no PR in any
Status cell it reads every PR `checkpoint.md` names instead; `run.log` says which PRs were read.

## Exit codes

| Code | Meaning | What to do |
|---|---|---|
| 0 | job done | read the final report in `checkpoint.md` |
| 1 | usage, dependency or runner error; `preflight` refused | read the message or the last `run.log` line, fix, run again |
| 3 | blocked: the job needs the owner | answer what `Open or blocked` asks, set `status: running`, `start` again |
| 4 | hard child cap (no Phase plan table) | add a Phase plan table, or raise `JOB_MAX_CHILDREN`, and start again |
| 5 | two children in a row left `checkpoint.md` unchanged | read the children's closing summaries in `run.log`; fix the brief or `Next action` |
| 6 | soft cap reached, `status: paused-cap` | `blast-off resume <job-dir>` (fresh child count) |
| 7 | uncommitted paths the checkpoint does not name | commit, remove, or name them in the checkpoint; start again |
| 8 | usage limit, `status: paused-limit until <time>` | nothing while `status` shows the resume timer active; else `blast-off resume <job-dir>` after `<time>` |
| 9 | a done Phase plan row lacks its commit or a PASS receipt for it | run the gate, `blast-off receipt`, fix the row's sha |
| 10 | done refused: the CI of a PR named in a Phase plan Status cell is red, unread, or absent (no runs) while HEAD has a workflow file | the last `run.log` line names the PR and the case. Red: fix CI and push. Then `blast-off ci-wait <job-dir> <pr>` after the last push. Absent: push to the PR branch so a run starts, then `ci-wait`; there is no override for a PR its workflows never run on |

Every non-zero code except 1 is a state, not a failure: the unit has no `Restart=`, and the runner is
safe to run again.

## Calling blast-off from big-next-job

`big-next-job`'s Run mode launches its own `run-job` with `nohup`. To run the job under blast-off
instead, the skill writes the brief and checkpoint from **blast-off's** templates (they carry the rules
the runner enforces: digit row keys, `done (<sha>)` cells, receipts, `ci-wait`; a checkpoint from
big-next-job's template ends in exit 9 at its first done row) into `<worktree>/.big-next-job/`, then
replaces its launch line with the [Check, then start](#check-then-start) block (`export GH_TOKEN
CLAUDE_FLAGS=...`, `blast-off preflight <job-dir>`, `blast-off start <job-dir>`)
for the owner. blast-off never reads or writes big-next-job's files.

## Tests

```bash
tests/run    # every tests/NN-*.sh with fake claude, gh and jev; shellcheck; ends GATE: PASS or GATE: FAIL
```

Scenarios start real `blast-off-test-<pid>-*` units, child scopes and tmux servers in the user manager and stop them; they need a live user systemd instance.
