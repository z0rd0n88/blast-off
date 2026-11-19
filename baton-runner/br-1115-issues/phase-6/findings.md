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
  **Corrected in fix round 2 (P6R2-19):** the anchor claim above was false. The window between a child's text and the
  runner's `child <n> usage` line exists in normal operation (scope stop plus `usage_read`), so a forged timestamped
  `job done` in child text could end the watch `final` (P6R2-1), and any later timestamped line (`receipt`,
  `ci-wait`) hid a real end (P6R2-3). The run.log anchor is gone; see fix round 2.
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
  systemctl's stderr dropped. A job dir deleted mid-watch is retried forever (it never reads as stuck). Superseded in
  fix round 2 (P6R2-2): 60 s of failed reads in a row is 12.
- **P6R1-6:** `BLAST_OFF_WAIT_POLL` must match `^[0-9]{1,4}(\.[0-9]{1,3})?$` and be 0.1 to 3600 s (pure bash, in
  milliseconds); else exit 1 `BLAST_OFF_WAIT_POLL='<v>' is not a number of seconds from 0.1 to 3600` before any read.
- **P6R1-7:** status field = the status word plus, when present, `until <[0-9TZ:.+-]{1,40}>`; phase field = the
  phase line with control characters removed and `·` replaced by `-`; each cut to 80 characters (`${x:0:80}`,
  characters under a UTF-8 locale, bytes under C). The snapshot compares these cleaned fields, so free text after
  the status word, or a phase change past character 80, is no change.
- **P6R1-11:** the fake systemctl logs each `show`; `blocks` waits for three more snapshots (the timer is read last
  in each) instead of sleeping 1 s.

## Fix round 2 (review round 2: owner ruling on P6R2-1/-3; P6R2-2, -4, -5, -8..-11, -19)

- **P6R2-1, P6R2-3 (owner ruling):** the runner writes its accepted end to `$JOB/runner-end`, one line
  `done <utc>` or `blocked <utc>`, by temp file plus rename (`chain_accept`, as `chain_count_set`), just before
  `chain_end` logs `job done` / `job blocked; see ...`. A failed write exits 1 under set -e before the log line, with
  no state (`runner exit 1 without a state`), so the job reads stuck, not final. `chain_run` deletes the file after
  `chain_lock` and the traps, before anything else: after the lock, so a second runner refused by a live one's lock
  never deletes that runner's end. A refused done or blocked (exit 7, 9, 10) goes through `chain_end` without
  `chain_accept`, so it leaves no file; a job re-opened by the owner gets its stale end deleted by the next run, and
  until then its status is not done/blocked, so wait ignores the file. `wait` is `final` only when the status is
  done/blocked and the file's first word is the same; run.log is not read at all (`wait_logged` deleted). The
  dirty-tree check already skips every path under the job dir (JOBREL prefix), so `runner-end` and
  `runner-end.tmp` need nothing new there.
- **P6R2-4:** stuck is time-based: unit and timer both down for 10 s by `date +%s`, timed from the first down poll,
  so at least two polls by construction. While both are down no `changed` is reported until stuck or until one is up
  (extends P6R1-3 from one poll to the whole spell). The clock times only this spell; a long gap with the same state is
  still no change, and a sleep that ends with the job down on both sides of it may read stuck at once, which it is.
- **P6R2-2:** mid-watch failed reads are retried; once one spell of them reaches 60 s (`date +%s`), the exit is 12
  with `wait: stuck · no read for 60 s: <WAIT_ERR>; see blast-off status <job>`. A good read resets the spell.
- `date` (external) over `$SECONDS`/`$EPOCHSECONDS` so 13-wait can fake the clock (sd/bin/date: real clock plus a
  skew that grows by `sd/step` at each `+%s` read). No env knob for 10 s or 60 s.
