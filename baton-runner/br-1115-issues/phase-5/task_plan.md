# Phase 5 task plan: issue 39 (child-count follow-ups)

Each step: test first (RED on old code or a named mutant), then code (GREEN), scenario run alone.

1. P4R2-1: test 21 new soft job, status running, child-count `2 2`, cap 2 -> launches child 3. Kills MA (`BASE=0` on read). → verify: MA RED, GREEN 21.
2. P4R2-2: test 21 re-seeds `2 0` after the cap-0 run so the re-run pins the in-memory BASE move. Kills MB. → verify: MB RED, GREEN 21.
3. P4R1-2: garbled child-count reason reaches run.log (still exit 1, no child, file untouched). → verify: RED old, GREEN 10.
4. P4R1-5: dangling symlink child-count = garbled (exit 1); run.log logs the count each run starts from. → verify: RED old, GREEN 10.
5. P4R1-7: SIGKILL the runner during child 1 (no EXIT trap); child-count is `1 0`; a re-run at cap 1 exits 4 with no launch. Kills save-in-trap mutant. → verify: mutant RED, GREEN 10.
6. P4R1-3: preflight shows child-count (launched, base, next, left under cap) and refuses a garbled one; status shows it. → verify: RED old 60 / 11, GREEN.
7. P4R2-9: chain_nums bounds digits (1-9); a 20-digit JOB_MAX_CHILDREN and a 10-digit JOB_CAP_FACTOR exit 1. → verify: RED old, GREEN 21.
8. P4R2-10: test 11 start_hang `[ -n "$pid" ]` guard. → verify: mutant shows guard fires; GREEN 11.
9. Docs: P4R2-4 (status may read running at exit 4: spec exit-4 column, chain.sh:97 comment, test 21 header, assert at 10:93), P4R2-11 (delete child-count = the one reset: spec :61, README exit 4, chain.sh comment), P4R1-4/P4-22b (README exit-4 second start), spec test rows 10, 11, 21, 60, preflight/status rows. → verify: 70-docs GREEN, shellcheck.
