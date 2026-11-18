# Phase 6 findings

- No `inotifywait` (not on this box, not in `DEPS` in lib/chain.sh:84 or preflight's list), no `faketime`.
- Child number: `child-count`'s `<launched>`, written by `chain_count_set` before each `child_launch` (lib/chain.sh:210);
  read through the existing `chain_count` (garbled -> `?`). Status and phase: the checkpoint's first `status:` and
  `phase:` lines (templates/checkpoint.md:3-4). Unit: `systemctl --user show <unit> -p ActiveState --value`, as
  `unit_status` does; a `--collect` unit that is gone reads `inactive`.
- usage_pause writes `paused-limit` before it arms the timer (lib/usage.sh:47-48), so a poll can see paused-limit with
  the unit still active: that is a change (11), and the next `wait` blocks on the armed timer.
- tests/lib.sh has no systemctl stub; scenarios use real systemd. 13-wait puts its own fake `systemctl` first on PATH
  (as 10-chain-done does for `slowctl`), so it never touches a real unit or the installed template.
- tests/70-docs.sh pins README's command list and SKILL.md's hand-over lines: `wait` added to both. Its exit-code row
  check (`^| *N *|`) would be satisfied by a second table's rows, so README's wait table puts the Line column first.

## Decisions

- **Poll, not inotify.** One process reads a snapshot every `BLAST_OFF_WAIT_POLL` (default 5 s): status line, phase
  line, child number, runner unit ActiveState, resume timer ActiveState. Tokens are the cost the issue names, and a
  polling process spends none. No new dependency.
- **State, never the clock.** `wait` calls no `date` and keeps no timestamps; a long gap between polls (machine sleep)
  is one more poll. No timeout env (`BLAST_OFF_WAIT_MAX` skipped): it would bring the clock back in, and the caller's
  background command has its own timeout.
- **One line on stdout:** `wait: <final|changed|stuck> · status: <...> · phase: <...> · child <n> · unit <state> ·
  timer <state>`; `stuck` appends `; see blast-off status <job-dir>`.
- **Exit codes**, outside the runner's 0-10 so a watcher never reads one as the runner's:
  0 `final` (status `done` or `blocked`, whatever the unit); 11 `changed` (run wait again); 12 `stuck`; 1 no job dir
  (job_init's `no job dir <path>`), no argument (`missing <job-dir>`) or no/empty `checkpoint.md`.
- **Unit gone (devil's advocate):** `stuck` = runner unit `inactive`, `failed` or `deactivating` and resume timer not
  `active`, while the status is not final. Covers stop, crash, reboot, a runner exit 1/4/5/7/9/10 (status stays
  running), `paused-cap` (owner runs resume) and a `paused-limit` with no timer. `paused-limit` with an active timer is
  not stuck: wait blocks until the timer starts the unit (11).
- **Already final or stuck at start:** returns at once, same line and code; it never blocks on a job that cannot move.
- **Order per poll:** final, then stuck, then changed, all on one snapshot (status word taken from the same read of
  checkpoint.md as the line; an early version re-read cp_status and printed a stale line, caught by the test).
- **Home:** `unit_wait`/`wait_snap` in lib/units.sh beside `unit_status`; dispatched with start/status/stop/logs/resume.
- **Test number 13** (the units group: 11-unit-smoke, 12-start-env), Phase column `issue 14`.

## Open questions (default applied)

- Q1: should `paused-cap` be `final` (0) rather than `stuck` (12)? Default: stuck, since it needs the owner's `resume`
  and does not move on its own; 0 stays exactly the issue's "terminal status" (done, blocked).
- Q2: a foreground `blast-off run` (no unit) reads as `stuck`. Default: documented; `wait` watches the unit, as the
  issue says. Reading the runner lock instead would cover it, at more code.
