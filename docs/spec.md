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
| K8 | Explicit `--model` and `--effort` per child | `CLAUDE_FLAGS` passed through the unit by name; `lib/jev.sh` picks the level per phase with a static fallback; `preflight` prints the resolved flags | 1, 6 |
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
| F9 | Stale or duplicate work: open PRs on the target set, behind-base count, merge base before the gate | `blast-off preflight` lists open PRs and `git rev-list --count HEAD..origin/main`; child protocol repeats both at phase start | 5, 6 |
| F10 | Usage: limit pause with reset time, resume, per-phase usage record, per-commit plugin inventory; child limit exit; launch-time estimate and refusal | `lib/usage.sh`: `status: paused-limit` + reset time, exit 8, also on the child exit code the brief reserves for a limit error (a child code, separate from the runner codes in §3; phase 3 names it, phase 5 writes it into the child protocol); `blast-off resume` and a timer or transient unit after the reset; usage percent on each phase row; brief lists per-commit LLM plugins with the owner's opt-in or opt-out; `blast-off preflight` estimates the job's usage from a previous job's checkpoint phase rows and exits 1 when the estimate exceeds what is left of the `seven_day` window (the `five_hour` window is bridged by `paused-limit` and `resume`, never refused); no prior record prints `no estimate` and does not refuse | 3, 5, 6 |
| F11 | Codex lanes off by default; enabled per phase with the owner's quoted override | `templates/brief.md` lanes row defaults to off | 5 |

## 2. CLI

One entry point, `bin/blast-off`, subcommand dispatch, `set -euo pipefail`, functions in `lib/*.sh`
sourced relative to the script. A job dir holds `brief.md` and `checkpoint.md`; the workdir defaults
to the job dir's parent (as in `run-job`).

| Command | What it does | Phase |
|---|---|---|
| `run` | `blast-off run <job-dir> [workdir]`: the chain loop in the foreground; what the unit's `ExecStart` calls; exits 1 before the first child when `CLAUDE_FLAGS` is unset or empty, so every entry point refuses a child with no `--model` or `--effort` (K8, D8) | 1 |
| `start` | `blast-off start <job-dir>`: `systemd-run --user --collect --slice=blast-off.slice --unit=blast-off-<name> --working-directory=<workdir> --setenv=PATH --setenv=GH_TOKEN --setenv=CLAUDE_FLAGS`, a `--setenv=` per set `JOB_*` name and `BLAST_OFF_TRUST_SECONDS`, the template's directives as `-p` properties, then `<repo>/bin/blast-off run <job-dir>` (the shape of the MoonPay launch line, which passed `HOME`, `PATH`, `CLAUDE_FLAGS` and `JOB_MAX_CHILDREN`; `HOME` is left out because the user manager already holds it, and `GH_TOKEN` through the unit is new); names only, never values; exits 1 before launching when `GH_TOKEN` or `CLAUDE_FLAGS` is unset or empty in the caller, because `--setenv=NAME` turns an unset name into an empty value in the unit; prints the resolved launch first | 1 |
| `status` | `blast-off status <job-dir>`: checkpoint header plus the `ActiveState` of `blast-off-<name>.service` | 1 |
| `stop` | `blast-off stop <job-dir>`: `systemctl --user stop blast-off-<name>.service`; the next child resumes from the checkpoint | 1 |
| `logs` | `blast-off logs <job-dir>`: `run.log` tail and `journalctl --user -u blast-off-<name>.service` | 1 |
| `resume` | `blast-off resume <job-dir>`: clears `paused-cap` or `paused-limit` to `running` and starts the unit again | 2, 3 |
| `install` | `blast-off install`: writes `blast-off@.service`, `blast-off.slice` (and the resume timer if used) to `~/.config/systemd/user/`, `daemon-reload`; never `enable` | 1 |
| `preflight` | `blast-off preflight <job-dir>`: resolved model, effort, flags, cap, timeout, account, usage percent, usage estimate from a previous job's phase rows (refuses with exit 1 when the `seven_day` window left cannot cover it; see F10), open PRs on the target set, behind-base count | 6 |
| `receipt` | `blast-off receipt <job-dir> <phase>`: writes `gate-logs/phase-<n>.json` | 4 |
| `ci-wait` | `blast-off ci-wait <job-dir> <pr>`: one blocking `gh run watch <id> --exit-status` per run of the PR head, conclusions recorded | 4 |

Environment (non-secret, passed by name through the unit): `PATH`, `CLAUDE_FLAGS`, `JOB_MAX_CHILDREN`
(override of the derived cap; with no Phase plan table, the hard cap, default 12), `JOB_CAP_FACTOR` (default 3; the soft cap is the number of `## Phase plan` table rows whose first cell is a number, times this factor; checkpoints number phases from 0, so `phase: N of M` is not used), `JOB_CHILD_TIMEOUT` (default 7200),
`JOB_SESSION`, `JOB_KEEP_WINDOWS` (leave finished children and, at exit, the server and scopes for inspection), `BLAST_OFF_TRUST_SECONDS` (default 60: the trust-dialog scrape runs only while a child starts). D14 reads "No secrets in any file;
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
| 1 | usage or dependency error (missing tool, missing brief or checkpoint, `start` with `GH_TOKEN` or `CLAUDE_FLAGS` unset or empty, `run` with `CLAUDE_FLAGS` unset or empty, `run` while another live runner holds the job's lock, a `JOB_*` count that is not a whole number), a runner abort (a command failing under `set -e`: `run.log` ends with `runner exit <n> without a state` and the failing command's own status becomes 1, so it never reads as a state; a signal's 128+n stands), or `preflight` refusing a job the `seven_day` window left cannot cover | unchanged | 1, 6 |
| 3 | blocked, needs the owner | `blocked` (by the child) | 1 |
| 4 | hard child cap reached (only when the soft cap is disabled: `checkpoint.md` has no `## Phase plan` table, so no phase count) | unchanged | 1, 2 |
| 5 | two children in a row left the checkpoint unchanged | unchanged | 1 |
| 6 | soft cap reached; resumable: a re-run of `run` sets `paused-cap` back to `running` and continues with a fresh child count | `paused-cap` | 2 |
| 7 | dirty tree the checkpoint does not name, after a child or before child 1 (the job dir's own files excepted; a workdir outside git is not checked); `git status --porcelain -uall` in `run.log` | unchanged | 2 |
| 8 | paused on a usage limit; reset time recorded | `paused-limit` | 3 |
| 9 | a done phase row has no receipt, or its sha differs from the phase commit | unchanged | 4 |
| 10 | `done` refused while a PR's CI is red or unread | unchanged | 4 |

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

**Resume after a usage limit**: phase 3 picks between a `blast-off-resume@.timer` and a transient
`systemd-run --user --on-active=<seconds> --unit=blast-off-resume-<name>` call from `lib/usage.sh`,
and records the choice and why.

## 5. systemd guide §5 directives

Every directive of the guide's §5 template. Disposition and why are the phase 0 design; phase 7
completes `docs/systemd-guide-deviations.md` from this table and fills the verified column on this box.

| Directive | Disposition | Why | Verified on this box |
|---|---|---|---|
| `Description=` | adopted | names the job instance (`blast-off job %i`) | pending |
| `Documentation=` | changed | points at the repo README, not an internal URL | pending |
| `After=` | changed | `network-online.target` is a system-scope unit; user scope has no ordering need beyond `default.target`, dropped unless phase 1 shows one | pending |
| `Wants=` | dropped | same reason as `After=`; `time-sync.target` is system scope | pending |
| `Type=` | adopted | `exec`: start fails if `bin/blast-off` cannot be executed | pending |
| `User=` | dropped | user-scope manager runs as the owner already; `claude` needs the owner's auth | pending |
| `Group=` | dropped | same as `User=` | pending |
| `NoNewPrivileges=` | dropped | prompt §8: conflicts with `claude` and its tools; test before claiming otherwise | pending |
| `WorkingDirectory=` | adopted | the job's workdir (worktree) | pending |
| `EnvironmentFile=` | dropped | no secrets in files (D14); non-secrets use `Environment=`, secrets pass by name; systemd's stored copy of a `--setenv` value is open (§2) | pending |
| `ExecStart=` | changed | absolute path of the checkout's `bin/blast-off run <job-dir>` | pending |
| `Restart=` | dropped | non-zero exits 3 to 10 are states; a restart would relaunch a blocked, capped or paused chain; resume is explicit (`blast-off resume` or the phase 3 timer) | pending |
| `RestartSec=` | dropped | no `Restart=` | pending |
| `StartLimitIntervalSec=` | dropped | no `Restart=`; manual starts need no rate limit | pending |
| `StartLimitBurst=` | dropped | same as `StartLimitIntervalSec=` | pending |
| `TimeoutStartSec=` | changed | `Type=exec` start is immediate; systemd default kept | pending |
| `TimeoutStopSec=` | adopted | bounds the stop so the runner's trap can kill the tmux session and log | pending |
| `CPUQuota=` | changed | on the slice, `1600%` of 20 cores, not per service `400%` | pending |
| `CPUSchedulingPolicy=` | dropped | `other` is the default | pending |
| `Nice=` | adopted | `5`, so the owner's interactive work wins | pending |
| `MemoryHigh=` | changed | on the slice, `14G`, sized to this box not 28G | pending |
| `MemoryMax=` | changed | on the slice, `18G`, sized to this box not 30G | pending |
| `MemorySwapMax=` | dropped | WSL2 has 12 GB swap; `0B` would OOM-kill a child on a build spike instead of throttling | pending |
| `TasksMax=` | changed | on the slice, `4096`; children run gradle and subagents | pending |
| `LimitNOFILE=` | dropped | user-scope default is enough unless a phase shows otherwise | pending |
| `PrivateTmp=` | dropped | hides the tmux socket under `/tmp/tmux-1000/` from the owner's `tmux attach` | pending |
| `ProtectSystem=` | dropped | `strict` conflicts with `claude` writing the worktree, `~/.gradle`, the Docker socket; test before claiming otherwise | pending |
| `ProtectHome=` | dropped | `claude` reads `~/.claude` and writes under the home dir | pending |
| `ReadWritePaths=` | dropped | only meaningful with `ProtectSystem=strict` | pending |
| `StandardOutput=` | adopted | `journal`; `run.log` stays the chain's own record | pending |
| `StandardError=` | adopted | `journal` | pending |
| `SyslogIdentifier=` | adopted | `blast-off` | pending |
| `KillMode=` | adopted | `control-group`: a stop kills the runner and its tmux calls; children run in their own `<unit>-child-<n>` scopes (§4), which the runner's TERM trap stops, and `blast-off stop` stops any it left | pending |
| `KillSignal=` | adopted | `SIGTERM`; the runner's trap logs and kills its tmux session | pending |
| `FinalKillSignal=` | adopted | `SIGKILL` after `TimeoutStopSec=` | pending |
| `WantedBy=` | dropped | no `[Install]`; a job runner is not a boot-time service and nothing is enabled (D6) | pending |

## 6. Tests

`tests/run` is the gate (one verdict line, zero scenarios fails, shellcheck included). One scenario
per behavior, fake `claude`, `gh` and `jev` first on `PATH`, tmux and unit names prefixed
`blast-off-test-<pid>`. The fakes reach a child only through the runner's own tmux server (§4). The
fake `claude` writes a marker file into the scenario's temp dir; every scenario that launches a child
asserts it, so the real `claude` can never produce a pass. Test 10 also sets a dummy `GH_TOKEN`, and
the marker records whether the child saw it set (the name, never a value):

| Scenario | Behavior | Phase |
|---|---|---|
| `00-harness` | gate verdicts; phase 0 scaffold and this spec's tables | 0 |
| `10-chain-done` | fake child drives `running` to `done` (exit 0) and `blocked` (exit 3); a fake child that hangs past `JOB_CHILD_TIMEOUT=2` is logged as timed out in `run.log` and the next child launches; two children in a row that leave `checkpoint.md` unchanged give exit 5 and `two stalls; stopping` in `run.log`, and progress resets that count; `JOB_MAX_CHILDREN=1` gives exit 4 (the phase 1 hard cap; phase 2 decides its fate beside the soft cap); the runner's tmux server and child scopes end on every exit and on SIGHUP; a stale scope of the same job is stopped before child 1; a slowly written Stop payload is read whole; the trust dialog is answered only in a child's first `BLAST_OFF_TRUST_SECONDS`; SIGHUP is logged as `runner exit 129 without a state`; a second signal while the runner stops its child scopes is ignored (exit stays 129, tmux server still ends); a runner abort (a `python3` that exits 4) exits 1 with `runner exit 4 without a state` last in `run.log` | 1 |
| `11-unit-smoke` | `start` runs the same job from a workdir named `test-<pid>-job` (`<pid>` as in `$TEST_ID`), so the runner unit is `blast-off-test-<pid>-job.service`, in `blast-off.slice` by `systemctl --user show -p Slice,MemoryCurrent`; the template instance for the escaped absolute path of the temp job dir is only loaded by `systemctl --user show -p ExecStart`, never started, and shows that absolute path; the child's `/proc/<pid>/cgroup` names `blast-off.slice` and its `-child-<n>` scope, and its parent is its pane's shell (a `#{pane_pid}`), so tmux's pane move never lands on it; after a second run whose fake child blocks, `blast-off stop` leaves the runner unit and its `-child-<n>` scope inactive or not-found by `systemctl --user show -p ActiveState`, and the fake child's pid gone | 1 |
| `12-start-env` | `start` with `CLAUDE_FLAGS` unset, then with `GH_TOKEN` empty, exits 1 and creates no unit; `run` with `CLAUDE_FLAGS` unset exits 1 and launches no child (every other scenario that drives `run` exports a dummy `CLAUDE_FLAGS`) | 1 |
| `20-dead-child` | child exits without the Stop hook; seen within 10 s, not at `JOB_CHILD_TIMEOUT`, its last screen in `run.log`, next child launches; a child that exits right after its Stop hook is finished, not dead; a non-JSON Stop payload is logged and the chain goes on (Q3) | 2 |
| `21-soft-cap` | derived cap (Phase plan rows x `JOB_CAP_FACTOR`, default 3, other tables' rows not counted) reached; `paused-cap`, exit 6, the cap and its source in `run.log`; re-run continues to `done`; `JOB_MAX_CHILDREN` overrides and stays soft; a non-numeric factor exits 1 before any child; test 10 keeps the hard cap (no table, exit 4, status unchanged) | 2 |
| `22-dirty-tree` | a child leaves an untracked file `checkpoint.md` does not name: exit 7, the unnamed paths and `git status --porcelain -uall` in `run.log`, status unchanged, no next child; a re-run on that tree refuses before child 1; a named path passes; the untracked job dir never counts; a workdir outside git is not checked (logged once) | 2 |
| `23-runner-lock` | a second `run` of a job whose runner is alive exits 1 before it starts anything (the first runner's child lives on); the lock `$XDG_RUNTIME_DIR/blast-off-<name>.lock` holds the runner pid and is gone after exit; a lock naming a dead pid or a pid that is no `blast-off run` is taken over (D1-6) | 2 |
| `30-paused-limit` | usage at threshold; `paused-limit`, exit 8, reset time | 3 |
| `31-resume-after-reset` | resume after a fake reset | 3 |
| `32-usage-per-phase` | usage percent on each phase row | 3 |
| `40-receipt-required` | done phase without a matching receipt; exit 9 | 4 |
| `41-ci-wait` | `done` refused while a PR's CI is unread; exit 10 | 4 |
| `50-checkpoint-size` | warning past 150 lines | 5 |
| `60-preflight` | preflight output; Jev pick and fallback | 6 |
