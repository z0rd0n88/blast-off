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
  0 `final` (status `done` or `blocked` the runner logged as the job's end; fix round 1, P6R1-1); 11 `changed` (run wait again); 12 `stuck`; 1 no job dir
  (job_init's `no job dir <path>`), no argument (`missing <job-dir>`) or no/empty `checkpoint.md`.
- **Unit gone (devil's advocate):** `stuck` = runner unit `inactive`, `failed` or `deactivating` and resume timer not
  `active`, while the status is not final. Covers stop, crash, reboot, a runner exit 1/4/5/7 (status stays
  running), 9/10 (done refused: status stays `done`, which fix round 1 no longer reads as final), `paused-cap` (owner runs resume) and a `paused-limit` with no timer. `paused-limit` with an active timer is
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

## Fix round 1 (review round 1: P6R1-1 HIGH, owner ruling; manager defaults for the rest)

- **P6R1-1 (owner ruling):** `final` only when run.log's last runner line, a line that starts with `log`'s
  `YYYY-MM-DDTHH:MM:SSZ ` timestamp, is `job done` (status `done`) or `job blocked; see ...` (status `blocked`), the
  exact text of `chain_end 0`/`chain_end 3` (lib/chain.sh:194-195). The pair must match. An unlogged `done`/`blocked`
  is no change and no `final`: wait keeps polling while the unit is up; once the unit and timer are down it is
  `stuck` (12). Anchor: a child's text in run.log (child_report, child_screen) is always followed by the runner's
  `child <n> usage` line before the status is read, so only a runner killed between the two leaves a child line last.
  run.log is read only while the status is `done`/`blocked`.
- The earlier claim here that exits 9 and 10 leave the status `running` was wrong: both leave it `done` ("status
  unchanged", lib/ci.sh, lib/receipt.sh). Corrected above.
- **P6R1-2 (Q1 default):** paused-cap stays 12; its line ends `; paused-cap: run blast-off resume <job-dir>`, every
  other stuck line `; see blast-off status <job-dir>`. README has a row for each.
- **P6R1-3:** `stuck` only on two polls in a row with unit and timer down; the first such poll reports nothing (no
  `changed` either), so a unit that just died reads `stuck`, not `changed`. Fixed at 2, no env (not trivial to
  validate twice). It covers the timer-to-unit handoff of a few seconds; a resume.service that waits out an old runner
  still `deactivating` (up to 60 s) is longer than 2 polls at 5 s, but at a usage reset the old runner exited hours ago.
- **P6R1-5:** at start every read must succeed (else exit 1 with the reason: `missing <job>/checkpoint.md`,
  `systemctl --user show ... failed (no user bus?)`); mid-watch a failed read is retried at the next poll, with
  systemctl's stderr dropped. A job dir deleted mid-watch is retried forever (it never reads as stuck).
- **P6R1-6:** `BLAST_OFF_WAIT_POLL` must match `^[0-9]{1,4}(\.[0-9]{1,3})?$` and be 0.1 to 3600 s (pure bash, in
  milliseconds); else exit 1 `BLAST_OFF_WAIT_POLL='<v>' is not a number of seconds from 0.1 to 3600` before any read.
- **P6R1-7:** status field = the status word plus, when present, `until <[0-9TZ:.+-]{1,40}>`; phase field = the
  phase line with control characters removed and `·` replaced by `-`; each cut to 80 characters (`${x:0:80}`,
  characters under a UTF-8 locale, bytes under C). The snapshot compares these cleaned fields, so free text after
  the status word, or a phase change past character 80, is no change.
- **P6R1-11:** the fake systemctl logs each `show`; `blocks` waits for three more snapshots (the timer is read last
  in each) instead of sleeping 1 s.
