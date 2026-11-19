# Phase 6 task plan: issue 14 (`blast-off wait <job-dir>`)

Each step: test first (RED: `wait` does not exist yet, or a named mutant), then code (GREEN), scenario run alone
(`BLAST_OFF_TEST_ONLY=13-wait tests/run`). ExecStart of ~/.config/systemd/user/blast-off@.service checked before the
first run and after each run (the new scenario stubs systemctl, so it should never change).

1. Tracer: tests/13-wait.sh, fake `systemctl` local to the scenario; child-count `0 0` -> `1 0` makes `wait` return 11
   with `child 1`. → verify: RED (unknown command), GREEN.
2. Phase change -> 11; status `done` and `blocked` -> 0 (on change and already at start, no blocking). → verify: GREEN,
   mutant (terminal check removed / start check skipped) RED.
3. Unit inactive while status running (stop, crash, reboot) -> 12 at once and on change; paused-cap with nothing
   running -> 12; paused-limit with its resume timer active -> blocks, 11 when the timer starts the unit.
   → verify: GREEN, mutant (no stuck check) RED.
4. Missing job dir, missing checkpoint.md -> exit 1 with the reason. → verify: GREEN, mutant RED.
5. Machine sleep: fake `sleep` + `date` jumping 10 h per poll, state unchanged -> still blocking after 5 polls.
   → verify: GREEN, clock mutant (`date` gap over 600 s returns) RED.
6. Docs: bin/blast-off usage, spec §2 row + exit codes + §6 row, README watch block + exit codes, SKILL.md hand-over;
   tests/70-docs.sh command lists. → verify: 70-docs GREEN, shellcheck -S warning on changed scripts.
