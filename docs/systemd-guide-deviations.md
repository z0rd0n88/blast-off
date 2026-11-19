# systemd guide deviations

Every directive of the batch-unit template in `~/.claude/docs/guides/system-d-guide.md` §5, as
blast-off builds it. The guide describes a system-scope batch job on a server; blast-off runs in the
owner's user manager on a WSL2 box (systemd 255, cgroup v2, `systemd-oomd` active, 20 cores, 23 GB
RAM, 12 GB swap, `Linger=yes`, no `sudo`). Dispositions: **adopted** (as the guide has it, written or
by an equal default), **changed** (kept with another value or place), **dropped** (not set).

Where the directive lives: `systemd/blast-off@.service` (the template `blast-off install` writes),
`systemd/blast-off.slice`, and `blast-off start`, which runs the same `[Service]` lines as
`systemd-run --user -p` properties of the transient unit `blast-off-<name>.service`
(`lib/units.sh`). Man page citations are the systemd 255 pages installed on this box (also at
<https://www.freedesktop.org/software/systemd/man/>).

**Verified on this box** (2026-11-06) means one of: `systemctl --user show` of the installed slice or
of a template instance (loaded, never started), a `blast-off-test-<pid>-*` transient unit run with
the directive, or a cgroup file read. The commands and their output are in the phase 7 ledger of the
build job. "Not verified" says so.

| Directive | Disposition | Why | Verified on this box |
|---|---|---|---|
| `Description=` | changed | `blast-off job %f`: names the absolute job dir, not a fixed job | yes: instance shows `Description=blast-off job /home/alex/.../.big-next-job` |
| `Documentation=` | dropped | the repo README is the documentation; no URL to point at | yes: `Documentation=` empty |
| `After=` | dropped | `network-online.target` and `time-sync.target` are system-scope units; user units get `After=basic.target` and their slice implicitly | yes: both targets `LoadState=not-found` in the user manager; instance shows `After=basic.target blast-off.slice` |
| `Wants=` | dropped | same as `After=` | yes: `Wants=` empty, targets not-found |
| `Type=` | adopted | `exec`: start fails if `bin/blast-off` cannot be executed (systemd.service(5)) | yes: `Type=exec` |
| `User=` | dropped | a user manager cannot switch identity; "the only valid setting is the same user" (systemd.exec(5)); `claude` needs the owner's auth | yes: `User=` empty, runner cgroup under `user@1000.service` |
| `Group=` | dropped | same as `User=` | yes: `Group=` empty |
| `NoNewPrivileges=` | dropped | not built; brief §3.3 expected it to break `claude`, but on this box `claude --version` and `git` run under it; adoption is open (owner question P7Q1): it blocks any setuid tool a child calls | partly: probe unit shows `NoNewPrivs: 1`, `2.1.316 (Claude Code)`, `git version 2.43.0`; a full child under it not run |
| `WorkingDirectory=` | changed | `start` passes `--working-directory=<workdir>`; the template leaves the manager default, harmless because `run` gets the absolute job dir and takes its parent as workdir | partly: instance shows the manager default (`$HOME`); `start` passes `--working-directory` (`lib/units.sh`), no test asserts the runner's cwd |
| `EnvironmentFile=` | dropped | no secrets in files (D14); `start` passes names with `--setenv=NAME`; systemd's stored copy of `GH_TOKEN` and `OPENROUTER_API_KEY` in the transient unit file is accepted (D21; the key by the owner's issue 27 sign-off) | yes: instance has no environment file |
| `ExecStart=` | changed | absolute path of the checkout's `bin/blast-off run %f`; `%f` restores the leading `/` the path escaping drops | yes: instance shows `argv[]=/home/alex/.../bin/blast-off run /home/alex/.../.big-next-job` |
| `Restart=` | dropped | exits 3 to 10 are states (blocked, capped, paused, refused), not failures; a restart would relaunch them. Resume is explicit: `blast-off resume` or the usage timer | yes: `Restart=no` |
| `RestartSec=` | dropped | no `Restart=` | yes: unused default `RestartUSec=100ms` |
| `StartLimitIntervalSec=` | dropped | no `Restart=`; starts are by hand or one timer | yes: manager default `10s` in effect |
| `StartLimitBurst=` | dropped | same as `StartLimitIntervalSec=` | yes: manager default `5` in effect |
| `TimeoutStartSec=` | dropped | `Type=exec` is started once `execve()` succeeds; the default is ample | yes: default `TimeoutStartUSec=1min 30s` |
| `TimeoutStopSec=` | changed | `60` not `120`: bounds the stop while the runner's EXIT trap stops child scopes and its tmux server | yes: `TimeoutStopUSec=1min` |
| `CPUQuota=` | changed | on the slice, `1600%` of 20 cores (leaves 4 to the owner), not `400%` per service; every job shares it | yes: slice `cpu.max` = `1600000 100000` |
| `CPUSchedulingPolicy=` | dropped | `other` is the default | yes: `CPUSchedulingPolicy=0` (other) |
| `Nice=` | dropped | not built (spec §5 planned `5`); the slice's `CPUQuota` already leaves 4 cores; one line to add (owner question P7Q2) | yes: probe unit reads nice `0` |
| `MemoryHigh=` | changed | on the slice, `14G`, sized to this box, not `28G` per service | yes: slice `memory.high` = 15032385536 (14 GiB) |
| `MemoryMax=` | changed | on the slice, `18G`, not `30G` | yes: slice `memory.max` = 19327352832 (18 GiB) |
| `MemorySwapMax=` | dropped | `0B` would OOM-kill a child on a build spike that swap absorbs | yes: `memory.swap.max` = `max`; swap `/dev/sdc` 12 GiB |
| `TasksMax=` | changed | on the slice, `4096`; children run gradle and subagents | yes: slice `pids.max` = 4096 (unit default 28823) |
| `LimitNOFILE=` | dropped | user-manager default kept; children inherit it, and a tool that needs more can raise its soft limit up to the hard one | partly: hard 1048576, soft 1024 (default); a heavy real child (gradle) under it not run |
| `PrivateTmp=` | dropped | the runner's tmux socket lives in `/tmp/tmux-1000/`; a private `/tmp` hides it from the owner's `tmux -L <unit> attach` | yes: under `PrivateTmp=yes` `/tmp/tmux-1000` is not visible; without it, it is |
| `ProtectSystem=` | dropped | `strict` makes `/tmp` read-only: tmux cannot create the job's socket and `claude` loses `/tmp/claude-1000`. `/home` stayed writable in the probe, so the worktree and `~/.gradle` are not the conflict | yes: under `strict` `/` and `/tmp` mount `ro`, `/home` `rw`; tmux: `error creating /tmp/tmux-1000/... (Read-only file system)` |
| `ProtectHome=` | dropped | `claude` reads `~/.claude` and writes under it (usage records, sessions) | yes: `read-only` refuses `touch ~/.claude/state/...` (`Read-only file system`); `yes` hides `~/.claude/settings.json` |
| `ReadWritePaths=` | dropped | only meaningful with `ProtectSystem=` | n/a: no `ProtectSystem=` (`ReadWritePaths=/tmp` with `strict` not tried) |
| `StandardOutput=` | adopted | `journal`, the default; `run.log` stays the chain's own record | yes: `StandardOutput=journal` |
| `StandardError=` | adopted | `inherit`, the default, sends it to the same journal stream | yes: `StandardError=inherit` |
| `SyslogIdentifier=` | dropped | the default is the process name, already `blast-off` | yes: journal lines of a `blast-off-test-*-job.service` runner carry `SYSLOG_IDENTIFIER=blast-off` |
| `KillMode=` | adopted | `control-group`: a stop kills the runner and its tmux calls; children sit in their own `<unit>-child-<n>.scope`, which the runner's trap and `blast-off stop` stop | yes: `KillMode=control-group`; child scopes covered by test 11 |
| `KillSignal=` | adopted | `SIGTERM`, the default; the runner's trap logs and cleans up | yes: `KillSignal=15` |
| `FinalKillSignal=` | adopted | `SIGKILL`, the default, after `TimeoutStopSec=` | yes: `FinalKillSignal=9` |
| `WantedBy=` | dropped | no `[Install]`: a job runner is not a boot-time service and nothing is enabled (D6); `multi-user.target` does not exist in user scope | yes: `WantedBy=` empty; `multi-user.target` not-found |

## Added directives (not in the guide's §5)

| Directive | Where | Why | Verified on this box |
|---|---|---|---|
| `Slice=blast-off.slice` | template, `start` | every runner and child scope shares the slice's limits | yes: runner cgroup `.../user@1000.service/blast.slice/blast-off.slice/...` |
| `ManagedOOMPreference=avoid` | template, `start` | under memory pressure oomd picks a child before the runner | yes: runner cgroup xattr `user.oomd_avoid=1`; systemd.resource-control(5): honoured when the cgroup and the monitored ancestor share an owner (both uid 1000 here) |
| `MemoryAccounting=yes`, `CPUAccounting=yes` | slice | the limits and `MemoryCurrent` need them | yes: both `yes` |
| `ManagedOOMMemoryPressure=kill`, `ManagedOOMMemoryPressureLimit=65%` | slice | oomd kills the heaviest child when the slice stalls on memory (guide §3, §4) | yes: `oomctl dump` lists `.../blast-off.slice` under Memory Pressure Monitored, limit 65.00% |
| `--collect`, `--setenv=NAME` | `start` (transient unit) | a failed unit is unloaded, not left `failed`; values come from the caller's environment, never the command line (D14) | yes: the `blast-off-test-<pid>-*` probe units, run with `--collect`, were gone from `systemctl --user list-units --all` afterwards |

The cgroup path shows `blast.slice` above `blast-off.slice`: a `-` in a slice name nests it
(systemd.slice(5)). `blast.slice` is implicit and carries no limits, so it changes nothing.

## Not verified on this box

- oomd actually killing a child under memory pressure (no pressure was produced).
- A full `claude` child under `NoNewPrivileges=yes`, and `ProtectSystem=strict` with `ReadWritePaths=/tmp`.
- A real job (real `claude`) through the installed unit: phase 8's smoke job.
