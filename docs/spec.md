# blast-off spec

blast-off runs one large multi-phase coding job as a chain of checkpointed Claude Code sessions,
under a systemd user unit, with no Claude session open to drive it. It ports the chain mechanics of
`big-next-job`'s `run-job` and adds what the MoonPay, vista-sign-in and MoonPay Step 1 runs lacked:
child liveness, a soft derived cap, dirty-tree refusal, usage pause and resume, receipts and a CI read.

Source of the keep and fix lists: `VistaMobileBE/docs/handoff/2026-11-04-large-job-launcher-prompt.md`
§4 and §5 (commit `afc647e0`). Source of the directive table: `~/.claude/docs/guides/system-d-guide.md`
§5 (commit `ad995d4`). blast-off never reads or writes the installed `big-next-job` skill at runtime (D1).

## 1. Keep and fix map

Every prompt §4 keep item (K) and §5 fix item (F), where it lands in blast-off, and the phase that
builds it.

| ID | Item | blast-off file or rule | Phase |
|---|---|---|---|
| K1 | Settle every decision before launch; children quote numbered rows | `templates/brief.md` §2 decision table; child protocol "never ask the owner, block and record" | 5 |
| K2 | Context pack: project map, per-phase file lists, gotchas, conflicts | `templates/brief.md` §3 sections 3.0 to 3.4 | 5 |
| K3 | One stacked draft PR per phase, pushed when the phase closes | `templates/brief.md` delivery section; `templates/checkpoint.md` phase row carries PR number | 5 |
| K4 | Chain mechanics: tmux window per child, Stop-hook `done.json`, resume from `Next action`, idempotent re-run | `lib/chain.sh` (loop, stall fingerprint), `lib/child.sh` (launch, trust-dialog scrape, wait), `templates/settings.child.json` (Stop hook); ported from `run-job` lines 38 to 94 | 1 |
| K5 | Doubt review and mutation probes inside each phase | `templates/brief.md` review section: doubt pass before round 1, probe set over status and exit logic, trap restores the file | 5 |
| K6 | One gate script with one verdict line, logs per phase | `tests/run` prints `GATE: PASS` or `GATE: FAIL` plus `passed=`, `failed=` and `shellcheck=` tallies; `gate-logs/phase-<n>.log`; `blast-off receipt` reads the verdict line | 0, 4 |
| K7 | Per-phase ledgers with stable finding IDs, sourced decisions | `templates/checkpoint.md` pointers to `phases/phase-<n>.md`; finding IDs `P<n>R<r>-<k>`; `decisions.tsv` | 5 |
| K8 | Explicit `--model` and `--effort` per child | `CLAUDE_FLAGS` passed through the unit by name; `lib/jev.sh` picks the level per phase with a static fallback: before a child, one Jev choice question (light, standard, deep, other) per first open Phase plan row, the row on stdin, through OpenRouter only (`jev` run with `TYPESAFE_API_KEY` and `JEV_BASE_URL` dropped, and only when `OPENROUTER_API_KEY` starts `sk-or-`); light = `--model sonnet --effort medium`, standard = `--model opus --effort high`, deep = `--model opus --effort xhigh` replace `CLAUDE_FLAGS`'s own `--model`/`--effort`, other flags kept; `JOB_JEV=0`, no OpenRouter key, `jev` missing or failing, an answer that is not a level, or no open row leave `CLAUDE_FLAGS` as given; each pick, with its source or fallback reason, goes to `run.log` and the job's `decisions.tsv`; `preflight` prints the flags and level `start` gives: `CLAUDE_FLAGS` as given, with no Jev call, since `start` passes no `OPENROUTER_API_KEY` (owner question P6Q1) | 1, 6 |
| K9 | Blocked parts do not stop the job | child protocol: record under "Open or blocked", leave the patch in `phases/`, continue; runner exits 3 only on `status: blocked` | 1, 5 |
| K10 | Usage hook inside children (90% warning obeyed) | child protocol obeys `usage-checkpoint.py`; `lib/usage.sh` reads the same `usage-limits-<session>.json` at child end | 3, 5 |
| F1 | Target-set construction from wiring, tests, build and gate-read files; confirmed as its own question; may-widen list | `templates/brief.md` target-set checklist and "may widen to" list; `skills/blast-off/SKILL.md` asks for the target set as its own confirmation | 5, 7 |
| F2 | Tool owns the launch as a user unit; prints model, effort, flags, cap, timeout, account; soft derived cap; child liveness; hand-over lines; documented permission rule | `systemd/blast-off@.service`, `blast-off start`, `blast-off preflight`; cap = phases × factor, exit 6 `paused-cap`; `lib/child.sh` polls the child's pane every second (`#{pane_dead}`, `remain-on-exit on` on the job's server), exit seen in under 10 s and its last screen logged; `skills/blast-off/SKILL.md` and `README.md` hand the owner one start line plus the status and stop commands, and state the permission rule a session needs to run that start line (the owner adds it; blast-off never writes settings and never works around the classifier) | 1, 2, 6, 7 |
| F3 | Hand back at step boundaries, not on an estimate; checkpoint stays small | `templates/brief.md` step-boundary rule; `lib/checkpoint.sh` warns in `run.log` past 150 lines; final report counts children per phase and hand-back reasons | 5 |
| F4 | Review shape: LOW recorded not fixed, lenses change each round, at most 3 reviewers, clean round closes | `templates/brief.md` review section (D12 shape); final report counts clean-round versus cap closes | 5 |
| F5 | Background work dies with the window; dirty tree after a child | child protocol bans ending a turn with background work running; probes restore in a trap on EXIT, TERM, INT; `lib/chain.sh` checks `git status --porcelain` before child 1 and at each child end, logs uncommitted paths the checkpoint names, and exits 7 on a dirty tree the checkpoint does not name. The child env also sets `CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS=0` (brief §3.3), but it acts only after the final turn of a `claude -p` child, where 0 means wait for background work with no ceiling until `JOB_CHILD_TIMEOUT`; it does nothing for the interactive tmux children and is not one of F5's controls | 2, 5 |
| F6 | Reviewers read-only by explicit tool allowlist; no servers or ports | `templates/brief.md` reviewer dispatch text: "no Edit, no Write, no process-starting Bash, no servers, no ports; read and grep only" | 5 |
| F7 | Done without reading CI | `blast-off ci-wait <pr>`: one blocking `gh run watch <id> --exit-status` per run; `lib/chain.sh` refuses `status: done` while a PR lacks recorded conclusions (exit 10); absent checks are not a pass | 4 |
| F8 | Receipts: machine-written gate evidence the next child checks | `blast-off receipt <job-dir> <phase>` writes `gate-logs/phase-<n>.json` from `templates/receipt.json`; runner refuses a done phase row whose receipt sha differs from the phase commit (exit 9) | 4 |
| F9 | Stale or duplicate work: open PRs on the target set, behind-base count, merge base before the gate | `blast-off preflight` lists open PRs touching the brief's Target set and `git rev-list --count HEAD..origin/<JOB_BASE, default main>` after `git fetch origin <base>`; child protocol repeats both at phase start | 5, 6 |
| F10 | Usage: limit pause with reset time, resume, per-phase usage record, per-commit plugin inventory; child limit exit; launch-time estimate and refusal | `lib/usage.sh`: `status: paused-limit` + reset time, exit 8, also on a StopFailure `rate_limit` and on child exit 75, the code reserved for a limit error (a child code, separate from the runner codes in §3; named in §4 Usage pause; an interactive child cannot produce it, so `templates/brief.md` tells children to checkpoint and end the turn on a limit and leaves the pause to the runner); `blast-off resume` and a timer or transient unit after the reset; usage percent on each phase row; brief lists per-commit LLM plugins with the owner's opt-in or opt-out; `blast-off preflight` estimates the job's usage from a previous job's checkpoint phase rows and exits 1 when the estimate exceeds what is left of the `seven_day` window (the `five_hour` window is bridged by `paused-limit` and `resume`, never refused); no prior record prints `no estimate` and does not refuse | 3, 5, 6 |
| F11 | Codex lanes off by default; enabled per phase with the owner's quoted override | `templates/brief.md` lanes row defaults to off | 5 |

## 2. CLI

One entry point, `bin/blast-off`, subcommand dispatch, `set -euo pipefail`, functions in `lib/*.sh`
sourced relative to the script. A job dir holds `brief.md` and `checkpoint.md`; the workdir defaults
to the job dir's parent (as in `run-job`).

| Command | What it does | Phase |
|---|---|---|
| `run` | `blast-off run <job-dir> [workdir]`: the chain loop in the foreground; what the unit's `ExecStart` calls; exits 1 before the first child when `CLAUDE_FLAGS` is unset or empty, so every entry point refuses a child with no `--model` or `--effort` (K8, D8). Before child 1 it takes the job's runner lock (`$XDG_RUNTIME_DIR/<unit>.lock`, exit 1 while another live runner holds it), logs the child cap and its source, sets `paused-cap` back to `running`, and runs the dirty-tree check (exit 7); the same check runs after every child (§3) | 1, 2 |
| `start` | `blast-off start <job-dir>`: `systemd-run --user --collect --slice=blast-off.slice --unit=blast-off-<name> --working-directory=<workdir> --setenv=PATH --setenv=GH_TOKEN --setenv=CLAUDE_FLAGS`, a `--setenv=` per set `JOB_*` name and `BLAST_OFF_TRUST_SECONDS`, the template's directives as `-p` properties, then `<repo>/bin/blast-off run <job-dir>` (the shape of the MoonPay launch line, which passed `HOME`, `PATH`, `CLAUDE_FLAGS` and `JOB_MAX_CHILDREN`; `HOME` is left out because the user manager already holds it, and `GH_TOKEN` through the unit is new); names only, never values; exits 1 before launching when `GH_TOKEN` or `CLAUDE_FLAGS` is unset or empty in the caller, because `--setenv=NAME` turns an unset name into an empty value in the unit; prints the resolved launch first | 1 |
| `status` | `blast-off status <job-dir>`: checkpoint header plus the `ActiveState` of `blast-off-<name>.service`, then `resume timer: <ActiveState of <unit>.resume.timer>`; a `paused-limit` job whose timer is not active (lost to a reboot, never armed, or stopped) adds `no resume timer: run blast-off resume <job-dir> after <until> (a job run with its own workdir: blast-off run <job-dir> <workdir>)` (P3R2-4; status takes only the job dir, so it names both, P3R3-1) | 1, 3 |
| `stop` | `blast-off stop <job-dir>`: `systemctl --user stop blast-off-<name>.service`; the next child resumes from the checkpoint | 1 |
| `logs` | `blast-off logs <job-dir>`: `run.log` tail and `journalctl --user -u blast-off-<name>.service` | 1 |
| `resume` | `blast-off resume <job-dir>`: runs `start` for a `paused-cap` job, or a `paused-limit` one once its `until` time has passed; before that time it exits 8 and changes nothing; with `CLAUDE_FLAGS` or `GH_TOKEN` unset it exits 1. It never writes the status: the started runner clears the pause once it holds the job's lock, so a failed start leaves the job paused (D3-1). It first waits up to 90 s for a stopping `blast-off-<name>.service` (the timer can fire during the old runner's exit), and stops a pending `<unit>.resume.timer` after a successful start. What the resume timer runs; no timer is armed for a job run with a workdir other than the job dir's parent, since `resume` takes only the job dir (D3-2) | 3 |
| `install` | `blast-off install`: writes `blast-off@.service`, `blast-off.slice` (and the resume timer if used) to `~/.config/systemd/user/`, `daemon-reload`; never `enable` | 1 |
| `preflight` | `blast-off preflight <job-dir> [workdir]`: one `name: value` line each, writing nothing: `flags` (what `start` gives the first open Phase plan row, K8: `CLAUDE_FLAGS` as given, with no Jev call, since `start` and the resume timer pass no `OPENROUTER_API_KEY` until the owner decides P6Q1), `model`, `effort`, `level` (static and why; a foreground `run` with the key and `JOB_JEV` not 0 asks Jev), `cap` (as `run` derives it), `timeout`, `account` (`claude auth status --json`: email, subscription, org), `GH_TOKEN` set or unset, `usage` (the newest `usage-limits-*.json` in `BLAST_OFF_STATE_DIR`, the account's latest figure; none means `usage-limit-tee.sh` is not writing and the usage pause is off, P3Q3), `estimate` (F10: the mean positive step between consecutive ` · usage ... 7d N%` cells of the Phase plan rows of `BLAST_OFF_ESTIMATE_FROM`, a previous job's checkpoint, else this job's own, times this job's open rows; fewer than two figures prints `no estimate`), `slice` (`blast-off.slice`'s FragmentPath, or not installed: an implicit slice has no limits, D1-7), `scope stop timeout` (the user manager's `DefaultTimeoutStopUSec`, what a child scope that ignores TERM gets; owner question Q2), `open PRs on the target set` (`gh pr list --state open --json number,title,headRefName,files` whose files match the backticked entries of the brief's first `Target set` bullet: `dir/` a prefix, an entry with `*?[` a glob, any other the file or a directory; no bullet lists every open PR), `behind` (`git rev-list --count HEAD..origin/<JOB_BASE>` after `git fetch origin <JOB_BASE>`). Then `preflight: ok` (exit 0) or `preflight: refused: <why>` (exit 1, every line still printed): `CLAUDE_FLAGS` unset or empty, a runtime dependency or `gh` not on `PATH`, or an estimate over what is left of the `seven_day` window (all of it once its reset passed; unknown is not checked). The `five_hour` window is bridged by `paused-limit`, never refused | 6 |
| `receipt` | `blast-off receipt <job-dir> <phase> [workdir]`: the verdict of `gate-logs/phase-<n>.log` (the child saves the `tests/run` output there; its last non-empty line must be the `GATE:` line) and the workdir's HEAD into `gate-logs/phase-<n>.json` from `templates/receipt.json` (phase, verdict, verdict_line, tally, gate_log, head_sha, utc, written_by); refused while the tree has uncommitted paths outside the job dir; a FAIL verdict is written too; exit 0 PASS, 1 FAIL or no log, no final verdict line or a dirty tree (nothing written, an earlier receipt stays; the refusal and its reason are logged to run.log) | 4 |
| `ci-wait` | `blast-off ci-wait <job-dir> <pr> [workdir]`: one blocking `gh run watch <id> --exit-status` per run of the PR head (`gh run list --commit <head>`), conclusions recorded in `gate-logs/ci-pr-<pr>.json` (verdict success when every run is success, skipped or neutral; failure; absent when no runs); an empty run list is re-read every 5 s for up to `BLAST_OFF_CI_APPEAR` (60) s, a wait for runs to be listed after a push, not a poll for completion; after the watches the list is read again and new runs (late or chained workflows) are watched, at most 3 rounds; each watch ends after `BLAST_OFF_CI_WATCH` (3600) s, and a run still not complete then is logged (its id, watch timed out) and recorded as it stands, its empty conclusion a failure (P4R2-3); GitHub Actions runs only, external status checks are not read; exit 0 success, 10 failure or absent | 4 |

Environment (non-secret, passed by name through the unit): `PATH`, `CLAUDE_FLAGS`, `JOB_MAX_CHILDREN`
(override of the derived cap; with no Phase plan table, the hard cap, default 12), `JOB_CAP_FACTOR` (default 3; the soft cap is the number of `## Phase plan` table rows whose first cell is a number, times this factor; checkpoints number phases from 0, so `phase: N of M` is not used), `JOB_CHILD_TIMEOUT` (default 7200),
`JOB_SESSION`, `JOB_KEEP_WINDOWS` (leave finished children and, at exit, the server, scopes and child dirs for inspection), `BLAST_OFF_TRUST_SECONDS` (default 60: the trust-dialog scrape runs only while a child starts), `JOB_USAGE_PAUSE` (default 95: the percent at or above which a usage window pauses the job), `JOB_RESUME_MARGIN` (default 60: seconds after a reset that the resume timer fires), `JOB_API_BACKOFF` (default 600: seconds the runner waits before the next child after a StopFailure `overloaded`, `server_error` or `unknown`; section 4), `BLAST_OFF_STATE_DIR` (default `~/.claude/state`: where `usage-limit-tee.sh` writes each session's `usage-limits-<session_id>.json`), `BLAST_OFF_CI_APPEAR` (default 60: seconds `ci-wait` waits for a PR head's runs to be listed, not for them to finish), `BLAST_OFF_CI_WATCH` (default 3600, owner question P4Q7: seconds `ci-wait` watches one run before recording it as it stands, not success), `BLAST_OFF_CI_HEAD` (default 60: seconds the runner's `gh pr view` of a PR head may take at done; past it the PR's CI is unread, exit 10), `JOB_JEV` (default 1; `0` gives every child `CLAUDE_FLAGS` as given, K8), `JOB_BASE` (default `main`: the branch `preflight` counts HEAD behind), `BLAST_OFF_ESTIMATE_FROM` (a previous job's `checkpoint.md` for `preflight`'s estimate). `OPENROUTER_API_KEY` is Jev's key, read from the runner's environment (the runner reads no secret file, D21); `start` and the resume timer do not pass it, so under the unit Jev falls back to `CLAUDE_FLAGS` (logged) until the owner decides P6Q1 (passing it by name stores a second secret in the transient unit file). D14 reads "No secrets in any file;
launch lines pass env var names, never values." blast-off writes no secret (`GH_TOKEN`) to any file,
and the launch line names them without values: `start` passes each as `--setenv=NAME`, so
`systemd-run` reads the value from the caller's environment. systemd itself then stores the resolved
value, the token included, in the transient unit file under `$XDG_RUNTIME_DIR/systemd/transient/`
(tmpfs; the file is mode 0644 inside the owner-only 0700 `$XDG_RUNTIME_DIR`, so the same user and root
can read it) and in the unit's `Environment` property (`systemctl --user show`) until the unit is
collected. That stored copy is a file in D14's words.
The brief settles the mechanism (§3.1: `--setenv=NAME` for secrets; §3.3: `gh` in children gets
`GH_TOKEN` passed by name through the unit), so phase 1 builds `--setenv=GH_TOKEN` and `start`'s
refusal of an unset or empty `GH_TOKEN` as the default. Only the owner's acceptance of that stored copy
(or, instead, the runner reading the secret itself) stays open; phase 1 records it under Open or
blocked and does not settle it. The user manager's environment
holds none of the other names, and its `PATH` (system directories only, `/usr/local/sbin` through
`/snap/bin`) finds neither `claude` nor `jev`; `PassEnvironment=` has no effect in user scope
(systemd.exec(5)), so a hand-started template instance sees none of these names and only that `PATH`. Phase 1 decides whether `start` ever uses the
template; the candidate `systemctl --user import-environment GH_TOKEN CLAUDE_FLAGS` passes names only
but leaves the token in the manager for every later user unit, so it is undecided.

`install` writes `ExecStart=` with the absolute path of this checkout's `bin/blast-off`; it writes
nothing outside `~/.config/systemd/user/`. A `~/.local/bin/blast-off` symlink is an optional owner step.

## 3. Exit codes

| Code | Meaning | Checkpoint status written | Phase |
|---|---|---|---|
| 0 | job done | `done` (by the child) | 1 |
| 1 | usage or dependency error (missing tool, missing brief or checkpoint, `start` with `GH_TOKEN` or `CLAUDE_FLAGS` unset or empty, `run` with `CLAUDE_FLAGS` unset or empty, `run` while another live runner holds the job's lock, a `JOB_*` count that is not a whole number, `git rev-parse` failing for a reason other than "not a git repository", `git status` failing), a runner abort (a command failing under `set -e`: `run.log` ends with `runner exit <n> without a state` and the failing command's own status becomes 1, so it never reads as a state; a signal's 128+n stands), or `preflight` refusing a job the `seven_day` window left cannot cover | unchanged | 1, 6 |
| 3 | blocked, needs the owner | `blocked` (by the child) | 1 |
| 4 | hard child cap reached (only when the soft cap is disabled: `checkpoint.md` has no `## Phase plan` table, so no phase count) | unchanged | 1, 2 |
| 5 | two children in a row left the checkpoint unchanged | unchanged | 1 |
| 6 | soft cap reached; resumable: a re-run of `run` sets `paused-cap` back to `running` and continues with a fresh child count | `paused-cap` | 2 |
| 7 | dirty tree the checkpoint does not name, after a child or before child 1 (named = the path whole, spelled from the repo root or the workdir, and in backticks when it has no '/' and no '.', so `status: running` does not name a file `status`; the job dir's own files excepted; a workdir outside git is not checked); `git status --porcelain -uall` in `run.log` | unchanged | 2 |
| 8 | paused on a usage limit (§4, Usage pause): at a child's end a window of its usage record at or above `JOB_USAGE_PAUSE` with its reset ahead, a StopFailure `rate_limit`, or child exit 75; also `run` or `resume` of a `paused-limit` job before its `until` time (nothing starts) | `paused-limit until <ISO UTC>` | 3 |
| 9 | a done Phase plan row (Status starts `done`, any case; before child 1 and after every child) names no commit (the first 7 to 40 character hex word in its Status cell) or one outside HEAD's history, has no `gate-logs/phase-<row>.json`, or a receipt whose verdict is not PASS, whose `head_sha` does not start with that commit, or whose `verdict_line` is not the final `GATE:` line of its own `gate_log`; a row the last child closed whose commit differs from HEAD outside the job dir (code after the gated commit); off when the workdir is outside git. Also at `status: done` while any Phase plan row is not done | unchanged | 4 |
| 10 | `done` refused while a PR the checkpoint names (`PR #N` in any case, `PR#N`, or `/pull/N`; leading zeros dropped) has no `gate-logs/ci-pr-<N>.json` whose `pr` is N (unread) or a red one, or a `success` or `absent` record whose `head_sha` is not the PR's head now (one `gh pr view <N> --json headRefOid` in the workdir per such PR, ended after `BLAST_OFF_CI_HEAD` (60) s; a failing or timed-out call is unread too, so run `ci-wait` after the last push; the call needs gh's auth, `GH_TOKEN`, which `start` requires and a foreground `run` does not; P4R1-1, owner question P4Q4); a record of no runs (`absent`) of the current head lets done through, logged "absent, not a pass" (owner question P4Q1), while `ci-wait` itself exits 10 on absent: absent is never reported as green. `ci-wait` also exits 10 on red, and on a run whose watch timed out (recorded as it stands, not success) | unchanged | 4 |

Code 2 is unused (bash reserves it for builtin misuse). Every non-zero code except 1 is a state, not
a failure: the unit must not restart on it (see `Restart=` below).

## 4. Units

**Child environment.** A tmux pane gets its server's global environment merged with its session's,
not the environment of the client that ran `new-window` (tmux(1), GLOBAL AND SESSION ENVIRONMENT; the
default `update-environment` list carries no `PATH` and no secret). `run-job` uses the default server,
which here is the owner's and already running, so a straight port would give each child the owner's
`PATH` (the real `claude`, even when a test puts the fake first) and no `GH_TOKEN`. The runner
therefore starts its own server, `tmux -L <unit name>` (`blast-off-<name>`; `blast-off-test-<pid>` in
tests), from inside the runner after `run-job`'s `CLAUDE*` scrub. That server's global environment is
the runner's, so `PATH`, `GH_TOKEN` and the `JOB_*` names reach every child with no value on any
command line (D14). The brief names no mechanism; this one is chosen because the other,
`new-window -e NAME=value`, carries `PATH` but would put the token's value on a tmux command line. The
socket stays under `/tmp/tmux-1000/` (no `PrivateTmp=`); the owner watches with
`tmux -L <unit name> attach -t <session>`, and `run.log`'s watch line and the hand-over lines print
exactly that. Test cleanup kills only the test's own sessions, never `kill-server`. The runner owns its socket: at start it stops what an earlier run of the job left (`<unit>-child-*.scope`, `kill-server` on `-L <unit name>`), and an EXIT trap does the same on every exit, signals included, unless `JOB_KEEP_WINDOWS` is set. Panes on a private
server still land in `tmux-spawn` scopes, so the per-child scope below stays: `-L` fixes the
environment, the scope fixes the cgroup, and `systemd-run --scope` runs `claude` as its own child, so
the pane's environment flows through (systemd-run(1)). Phase 1 builds this in `lib/child.sh` and
verifies it in test 10 (§6).

**`systemd/blast-off.slice`** groups every job's runner and children under shared limits. tmux 3.4 here
links libsystemd and moves each new pane into its own `tmux-spawn-<uuid>.scope`, outside the runner's
unit, so the unit alone does not hold the children. Each child command therefore runs inside its tmux
window as `systemd-run --user --scope --slice=blast-off.slice --unit=<runner unit>-child-<n> claude ...; exit`.
tmux moves only the pane's own pid, from the server after fork and without waiting for the move (tmux
3.4 `spawn.c`, `systemd.c`), so the trailing `; exit` makes the pane shell fork `systemd-run` rather than
exec it: tmux's move lands on the shell, never on `claude`, which would otherwise end up in a
`tmux-spawn` scope the runner cannot name;
the runner's TERM trap and `blast-off stop` stop those scopes. Phase 1 builds it in `lib/child.sh` and
verifies it in test 11. Child scopes of the phase 8 smoke job (`blast-off-smoke-child-<n>`) are not
named in brief §4 and need the owner's nod first. Defaults
sized for this box (23 GB RAM, 20 cores; prompt §8), overridable with a drop-in:
`MemoryAccounting=yes`, `CPUAccounting=yes`, `MemoryHigh=14G`, `MemoryMax=18G`, `CPUQuota=1600%`,
`TasksMax=4096`, `ManagedOOMMemoryPressure=kill`, `ManagedOOMMemoryPressureLimit=65%` (guide §4).

**`systemd/blast-off@.service`**, template, the instance is the job dir escaped by
`systemd-escape --path`. `Type=exec`, `ExecStart=<repo>/bin/blast-off run %f` (`%f` undoes the path
escaping and prepends `/`, so `run` gets the absolute job dir and no per-instance file is written; `%I`
would drop the leading `/`, and `run` would resolve the relative path against the unit's working
directory, find no brief and exit 1; a drop-in would fall outside brief §4), `Slice=blast-off.slice`,
`KillMode=control-group`, `ManagedOOMPreference=avoid` on the runner, `TimeoutStopSec=`, journald
output, no `Restart=`, no `[Install]`. The workdir is the job dir's parent, as `run` already defaults.
`start` uses the transient form with the same directives (§2); one naming rule covers every job:
`<name>` is the workdir's basename (as `run-job`'s session name), the unit is `blast-off-<name>.service`,
and `status`, `stop` and `logs` act on that name. Phase 1 builds and verifies both.

**Usage pause** (`lib/usage.sh`, F10). At each child's end the runner reads the child's
`usage-limits-<session_id>.json` (session id from the Stop or StopFailure payload; written by
`~/.claude/hooks/usage-limit-tee.sh` from the status line's `rate_limits`, shape
`{"five_hour":{"used_percentage":N,"resets_at":<epoch>},"seven_day":{...}}`, either key may be
absent), logs `child <n> usage: 5h N% 7d M%` (`unknown` with no record or an empty one; `unreadable` when
the record is there but no window reads, after a line with its first 200 bytes, logged too for a
`five_hour` or `seven_day` key in another shape; neither pauses) and pauses the job when any window is at
or above `JOB_USAGE_PAUSE` with its `resets_at` still ahead (a window past its reset has refilled), the
child's turn ended on a StopFailure with `error` `rate_limit`, or the child exited 75 (sysexits
`EX_TEMPFAIL`, the child code reserved for a limit error; read from the exit file the child's pane shell writes, else tmux `#{pane_dead_status}`;
an interactive child cannot produce it: the child protocol in `templates/brief.md` says checkpoint and end the turn, and children write only `running`, `done` or `blocked`). A child that set `done` or `blocked` is never paused. The
pause writes `status: paused-limit until <ISO>`: the latest reset of the windows over the threshold;
for a rate limit with none over it, the `five_hour` reset; with neither known, now plus five hours
(the `five_hour` window's length); plus `JOB_RESUME_MARGIN`, at least 5 s ahead. StopFailure "fires
instead of Stop when an API error (rate limit, auth failure, etc.) ended the turn", payload
`error`, `error_details`, `last_assistant_message` beside the common fields (claude 2.1.316 hook
registry, read from the installed binary; binary-verified, not doc-verified). Its hook in
`templates/settings.child.json` writes `failed.json`. An interactive child idles after one, so the
runner does not wait out its timeout. `overloaded`, `server_error` and `unknown` clear on their own:
logged, and the next child starts `JOB_API_BACKOFF` seconds (default 600) later, after every exit
check, so a short outage does not spend two children into exit 5 (phase 2, with no StopFailure hook,
waited such a child out to `JOB_CHILD_TIMEOUT`). A child with no progress still counts as a stall, so
an outage longer than the wait still ends in exit 5. Any other error (`authentication_failed`,
`billing_error`, `invalid_request`, `max_output_tokens`, the rest of the 2.1.316 list) is logged and
handled as a death at once. That split is a build choice (P3R2-3, the smallest reversible one), not
the owner's; owner question P3Q7 stays open.

**Resume after a usage limit**: a transient timer, `systemd-run --user --collect --unit=<unit>.resume
--on-calendar='<until> UTC' --timer-property=AccuracySec=1s` plus `start`'s `--setenv` names, running
`blast-off resume <job-dir>`, armed at exit 8. Its units are `<unit>.resume.timer` and `.service`: a
workdir name holds no `.`, so they never name another job's runner, as `<unit>-resume` did for a
job named `<name>-resume` (P3R2-2). Chosen over a `blast-off-resume@.timer` template (no
installed file, one per job) and over `--on-active=` (monotonic): systemd.timer(5) says a calendar
timer that elapses while the host sleeps fires on resume, while monotonic timers pause with it, so a
suspended WSL2 host resumes the job on wake (owner question P2Q3). `AccuracySec` defaults to 1 min.
The user manager has no `CLAUDE_FLAGS` or `GH_TOKEN`, so the timer's service carries the same names
as `start`, and systemd stores the token in that transient unit's file as D21 accepts for `start`.
With `GH_TOKEN` unset no timer is armed and `run.log` says when to run `resume`. The pause's last
`run.log` line says `(the timer does it)` only when the timer was armed; for a job run with its own
workdir it names `blast-off run <job-dir> <workdir>` (P3R3-2). `stop` stops the
timer. The timer is transient, its unit file on tmpfs: a reboot, `wsl --shutdown` or user-manager
exit before `until` deletes it and nothing resumes the job; `status` then prints `no resume timer:
run blast-off resume <job-dir> after <until> (a job run with its own workdir: blast-off run <job-dir>
<workdir>)` for the owner to run (P3R2-4, P3R3-1; a resume that survives a
reboot without the owner is owner question P3Q8, open).
Phase rows: when a child turns a `## Phase plan` row's Status cell to `done`, the runner
appends ` · usage <figure>` to that cell (rows done before the child are left alone); the stall
check uses the fingerprint taken before that edit.

## 5. systemd guide §5 directives

[`systemd-guide-deviations.md`](systemd-guide-deviations.md) lists every directive of the guide's §5
template as adopted, changed or dropped, why, and what was verified on the build box. It records the
units as built (phase 7); the phase 0 design table that stood here is retired so the dispositions live
in one place (test 70 pins one filled row per directive).

## 6. Tests

`tests/run` is the gate (one verdict line, zero scenarios fails, shellcheck included). One scenario
per behavior, fake `claude`, `gh` and `jev` first on `PATH`, tmux and unit names prefixed
`blast-off-test-<pid>`. The fakes reach a child only through the runner's own tmux server (§4). The
fake `claude` writes a marker file into the scenario's temp dir; every scenario that launches a child
asserts it, so the real `claude` can never produce a pass. Test 10 also sets a dummy `GH_TOKEN`, and
the marker records whether the child saw it set (the name, never a value):

| Scenario | Behavior | Phase |
|---|---|---|
| `00-harness` | gate verdicts; phase 0 scaffold and this spec's §1 to §3 tables | 0 |
| `10-chain-done` | fake child drives `running` to `done` (exit 0) and `blocked` (exit 3); a fake child that hangs past `JOB_CHILD_TIMEOUT=2` is logged as timed out in `run.log` and the next child launches; two children in a row that leave `checkpoint.md` unchanged give exit 5 and `two stalls; stopping` in `run.log`, and progress resets that count; `JOB_MAX_CHILDREN=1` gives exit 4 (the phase 1 hard cap; phase 2 decides its fate beside the soft cap); the runner's tmux server and child scopes end on every exit and on SIGHUP; a stale scope of the same job is stopped before child 1; a slowly written Stop payload is read whole; the trust dialog is answered only in a child's first `BLAST_OFF_TRUST_SECONDS`; SIGHUP is logged as `runner exit 129 without a state`; a second signal while the runner stops its child scopes is ignored (exit stays 129, tmux server still ends); a runner abort (a `python3` that exits 4) exits 1 with `runner exit 4 without a state` last in `run.log`; each child's dir `$XDG_RUNTIME_DIR/<unit>-child.XXXXXX` is gone after it ends and after SIGHUP, and a re-run removes one an earlier (SIGKILLed) run left (P2-L1, phase 3) | 1, 3 |
| `11-unit-smoke` | `start` runs the same job from a workdir named `test-<pid>-job` (`<pid>` as in `$TEST_ID`), so the runner unit is `blast-off-test-<pid>-job.service`, in `blast-off.slice` by `systemctl --user show -p Slice,MemoryCurrent`; the template instance for the escaped absolute path of the temp job dir is only loaded by `systemctl --user show -p ExecStart`, never started, and shows that absolute path; the child's `/proc/<pid>/cgroup` names `blast-off.slice` and its `-child-<n>` scope, and its parent is its pane's shell (a `#{pane_pid}`), so tmux's pane move never lands on it; after a second run whose fake child blocks, `blast-off stop` leaves the runner unit and its `-child-<n>` scope inactive or not-found by `systemctl --user show -p ActiveState`, and the fake child's pid gone | 1 |
| `12-start-env` | `start` with `CLAUDE_FLAGS` unset, then with `GH_TOKEN` empty, exits 1 and creates no unit; `run` with `CLAUDE_FLAGS` unset exits 1 and launches no child (every other scenario that drives `run` exports a dummy `CLAUDE_FLAGS`) | 1 |
| `20-dead-child` | child exits without the Stop hook; seen within 10 s, not at `JOB_CHILD_TIMEOUT`, its last screen in `run.log`, next child launches; a child that exits right after its Stop hook is finished, not dead; a non-JSON Stop payload is logged and the chain goes on (Q3) | 2 |
| `21-soft-cap` | derived cap (Phase plan rows x `JOB_CAP_FACTOR`, default 3, other tables' rows not counted) reached; `paused-cap`, exit 6, the cap and its source in `run.log`; re-run continues to `done`; `JOB_MAX_CHILDREN` overrides and stays soft; a non-numeric factor exits 1 before any child; test 10 keeps the hard cap (no table, exit 4, status unchanged) | 2 |
| `22-dirty-tree` | a child leaves an untracked file `checkpoint.md` does not name: exit 7, the unnamed paths and `git status --porcelain -uall` in `run.log`, status unchanged, no next child; a re-run on that tree refuses before child 1; a named path passes; a bare file `status` is not named by `status: running` (exit 7) but is by `` `status` `` (exit 0); the untracked job dir never counts; a workdir outside git is not checked (logged once) | 2 |
| `23-runner-lock` | a second `run` of a job whose runner is alive exits 1 before it starts anything (the first runner's child lives on); the lock `$XDG_RUNTIME_DIR/blast-off-<name>.lock` holds the runner pid and its start time and is gone after exit; a lock whose pid is dead, or alive with another start time (a reused pid), is taken over (D1-6, D2-3) | 2 |
| `30-paused-limit` | a five_hour or seven_day window at or above the threshold (`JOB_USAGE_PAUSE` moves it): `paused-limit until <reset + margin>`, exit 8, usage and reset in `run.log`, the resume timer's calendar, no next child; `run` before the reset exits 8 with no child; under the threshold, a reset already past, no record, or a child that set `done`: no pause; a record not JSON or with no window in a shape read here logs `usage: unreadable` and its first bytes, a renamed key beside a good window logs its bytes and keeps the good figure, `{}` stays `unknown`, none pauses; a StopFailure `rate_limit` pauses at once (not at the timeout) until the five_hour reset, or now + 5 h with none; a StopFailure `overloaded` is logged and the next child launches `JOB_API_BACKOFF` seconds later, an `authentication_failed` one is a logged death with no wait (P3R2-3); child exit 75 with no `GH_TOKEN` pauses with no timer and `status` prints `no resume timer`, while a pending timer shows `resume timer: active`; the pause leaves a running unit named `<unit>-resume` (job `<name>-resume`'s runner) up; a non-numeric `JOB_USAGE_PAUSE` exits 1 before any child. State files and reset times are fakes relative to the real clock (the timer runs on systemd's clock, which a fake `date` cannot move) | 3 |
| `31-resume-after-reset` | `resume` before the reset exits 8, nothing changed; of a running job exits 1; with `GH_TOKEN` unset exits 1, status kept; after the reset (and for `paused-cap`) sets running, starts the unit, which finishes the job; `run` after the reset continues; the timer armed at exit 8 fires for real 4 s later and its resume finishes the job; `stop` ends a pending timer | 3 |
| `32-usage-per-phase` | a row a child closes gets ` · usage 5h N% 7d M%` (floored) or `usage unknown`; a row done before the run and a child that closes none add nothing | 3 |
| `40-receipt-required` | done phase without a matching receipt; exit 9 | 4 |
| `41-ci-wait` | `done` refused while a PR's CI is unread; exit 10 | 4 |
| `50-checkpoint-size` | before each child launch, `checkpoint.md is N lines, over 150` in `run.log` when it is over 150 lines (at 150, none); a checkpoint a child grows past 150 is warned before the next child | 5 |
| `51-templates` | `templates/checkpoint.md` read by `lib/checkpoint.sh` as a fresh job: status `running`, every Phase plan row open with a digit key, no warning, a `done (<sha>) · PR #<n>` cell read back as done at that sha; `templates/brief.md` has a Child protocol section and one phrase per keep and fix item it carries (F1, F3 to F6, F9 to F11, the receipt and CI close order), and no hand-back on an estimate | 5 |
| `60-preflight` | every preflight line with fakes (flags, model, effort, level as `start` gives them: static `CLAUDE_FLAGS`, P6Q1, though the fake `jev` would pick deep; soft cap 9; timeout; account; usage from the newest of two records; estimate 40% from a previous job's 10, 30, 50 then reset rows, 50% left; slice; scope stop timeout; PRs #11 and #13 on the Target set by prefix and glob, #12 and the near misses #14 not; behind 1 after fetch), `preflight: ok`, no `jev` call, job dir unchanged; 7d at 70% refuses (exit 1, every line printed); a reset already past leaves 100%; no record, a missing state dir and no estimate source print and pass; static fallback, `GH_TOKEN` unset, empty `CLAUDE_FLAGS` refused, no Target set bullet lists every PR | 6 |
| `61-jev-pick` | Jev asked once per first open Phase plan row (4 children, 2 calls), row text on stdin not argv, `TYPESAFE_API_KEY` and `JEV_BASE_URL` dropped, OpenRouter key kept; the level's flags replace `--model`/`--effort` and keep the rest; a child with no open row gets static flags; picks in `run.log` and 6-column `decisions.tsv` rows; fallbacks with their logged reason and call count: `JOB_JEV=0`, no key, a non-`sk-or-` key, `jev` failing, `other`, `jev` not on `PATH` | 6 |
| `70-docs` | `skills/blast-off/SKILL.md` frontmatter (name, description at most 1024 chars) and its hand-over commands; README shows every subcommand and has a row per exit code `bin/blast-off`'s header lists; `systemd-guide-deviations.md` has one row per guide §5 directive with a disposition, a why and a verified cell that is not `pending` | 7 |
