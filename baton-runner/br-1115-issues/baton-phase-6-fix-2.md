---
source: runner
scope: br-1115-issues
parent_session: ""
---
# Pass-Baton: phase 6 fix round 2 (issue 14): P6R2-1, -3 (owner ruling: runner-end), -2, -4, -5, -8, -9, -10, -11, -19 fixed

**Date:** 2026-11-18
**Scope:** br-1115-issues
**Branch:** feat/br-1115-issues/phase-6
**Worktree:** /home/alex/blast-off/.claude/worktrees/pending-items-53932d
**HEAD:** 06d9de1 chore(phase-6): review round 2 CLEAN (narrow); owner: one more fix round (changes uncommitted; the manager owns git)

## Where things stand

The owner ruling is in: the runner writes the end it accepts to its own file, `$JOB/runner-end`, and `wait` reads
that file instead of run.log. That closes P6R2-1 (child text in run.log can't fake an end) and P6R2-3 (a later
run.log line can't hide one). P6R2-2, -4, -5 and -8 are fixed test-first. P6R2-9, -10, -11 and -19 are doc fixes.
Nothing else was touched (notes below).

Scenarios run, each alone, one at a time (never the full gate): 10-chain-done (2 RED/shellcheck, 1 GREEN, 2 mutant
runs, 1 final), 13-wait (3 RED, 2 GREEN, 10 mutant runs, 1 final), 70-docs (1 final), and, since `lib/chain.sh`
feeds every runner scenario, one run each of 22-dirty-tree, 40-receipt-required, 41-ci-wait and 21-soft-cap. Final
results, on the final code:
- 13-wait: `GATE-ONLY: PASS passed=1 failed=0 shellcheck=ok only=13-wait`
- 10-chain-done: `GATE-ONLY: PASS passed=1 failed=0 shellcheck=ok only=10-chain-done`
- 70-docs: `GATE-ONLY: PASS passed=1 failed=0 shellcheck=ok only=70-docs`
- 22-dirty-tree, 40-receipt-required, 41-ci-wait, 21-soft-cap: each `GATE-ONLY: PASS passed=1 failed=0 shellcheck=ok`

`shellcheck -S warning` is clean on `lib/units.sh`, `lib/chain.sh`, `bin/blast-off`, `tests/13-wait.sh` and
`tests/10-chain-done.sh`. tests/run's own shellcheck pass (34 files) is ok on every run after the first two. Those
two failed on SC1010: a bare `done` argument in `chain_accept done` and in the test helper. Both are now quoted
(`'done'`).

`~/.config/systemd/user/blast-off@.service` read `ExecStart=/home/alex/blast-off/.worktrees/blast-off-build/bin/blast-off run %f`
five times: before the first run, after the first 10-chain-done run, after the chain mutants, after the final three
runs, and after the extra four scenarios. It never changed. 11 and 31 were not run. No real unit, timer or install
was used. 13-wait uses its own fake `systemctl` and `date`. 10-chain-done and the others use real transient child
scopes, as they always do. No `blast-off wait` process was left running.

Every mutant was applied to a copy and then restored from the GREEN copy, and `cmp` confirmed each restore was
identical (10 of 10 on `lib/units.sh`, 2 of 2 on `lib/chain.sh`). The test files changed after some mutant runs: the
retry block was rewritten to kill M2b, and `skewed` now stops once wait has returned. The final 13-wait run covers
them.

Files changed (tracked, 9):
- `lib/chain.sh`: new `chain_accept <done|blocked>` writes `<word> <utc>` to `$JOB/runner-end.tmp`, then
  `mv -f`s it to `$JOB/runner-end`. It is called right before `chain_end 0 "job done"` and `chain_end 3 "job blocked;
  see ..."`. `chain_run` runs `rm -f "$JOB/runner-end"` after `chain_lock` and the traps, before `child_server`.
- `lib/units.sh` (`unit_wait`; `wait_logged` deleted):
  - `final` happens only when the status is done/blocked and `cut -d' ' -f1 runner-end` is the same word. run.log is
    never read.
  - `down` now holds the `date +%s` time when the current spell of unit and timer both down began. Before, it was a
    poll count. Stuck needs `now - down >= 10`. While down, no `changed` is reported.
  - Failed reads mid-watch: a spell (`bad`) starts at the first failed read, and a good read resets it. At 60 s the
    exit is 12 with `wait: stuck · no read for 60 s: <WAIT_ERR>; see blast-off status <job>`.
- `tests/13-wait.sh`:
  - New fake `date`: `+%s` is the real clock plus `sd/skew`, and each read adds `sd/step` to the skew (default 5, and
    0 for the real clock).
  - The fin block was rewritten for runner-end, and a new blk block was added.
  - New cases: a `deactivating` unit (g4), a slow handoff (sl, six polls on the real clock), and a retry block of two
    35 s spells with a `skewed` helper.
  - New stuck cases: a job dir deleted mid-watch (dl) and systemctl failing for good (nb).
  - The header was updated.
- `tests/10-chain-done.sh`:
  - `runner-end` matches `^done <ts>$` after the done run and `^blocked <ts>$` after the blocked run.
  - The blocked job, re-opened as `done` with no Phase plan row, is refused with exit 10 and leaves no runner-end
    (clear-on-start).
  - A fresh job's refused done (exit 10) leaves no runner-end.
- `docs/spec.md`:
  - The job-dir paragraph names `run.log`, `child-count` and `runner-end`: what runner-end holds, when it is written
    and deleted, and that wait reads it. The dirty-tree check skips the job dir's files.
  - The wait row covers what wait reads, the refusal codes, the 10 s rule, no change while down, sleep, field
    lengths, every `·`, the owner's actions on 12, and the 60 s read limit.
  - The wait exit paragraph, and the 10-chain-done and 13-wait test rows. The 13-wait row no longer says "at once on
    an already stuck job" (P6R2-10).
- `README.md`: the wait paragraph (what it reads, field lengths, every `·`), the final row, and the stuck row
  (10 s, refused `done` or `blocked`, owner action fits a refused done). There is a new row for
  `stuck · no read for 60 s`. The exit-1 row now says missing or empty, the reason is on stderr, and one plain rerun
  is fine for a cause that clears on its own.
- `bin/blast-off`: wait's exit-code usage lines, and the `BLAST_OFF_WAIT_POLL` line ("a change is state, never the
  clock").
- `skills/blast-off/SKILL.md` step 8 (P6R2-11):
  - 0 means the runner accepted the end.
  - 12 also covers 60 s with no read, and the line says why.
  - 1 lists a missing or empty checkpoint.md. Rerun once unchanged only when the cause can clear on its own;
    otherwise fix it first.
- `baton-runner/br-1115-issues/phase-6/findings.md`: the fix-1 anchor claim is marked false (P6R2-19), and so is the
  "retried forever" decision. A new "Fix round 2" section records the decisions below.

## Evidence, per item

### P6R2-1 (owner ruling): a forged `<ts> job done` in run.log ended the watch `final`
RED 13-wait (HEAD code, new tests):
```
  | FAIL: wait returned before any change (a forged job done line in run.log, no runner-end): rc 0: wait: final · status: done · phase: 1 of 1 · child 0 · unit active · timer inactive
GATE-ONLY: FAIL passed=0 failed=1 shellcheck=ok only=13-wait
```
RED 10-chain-done (HEAD code, new tests):
```
FAIL 10-chain-done
  | cat: /tmp/tmp.G649F5sKav/cwd/test-1312463-ok/job/runner-end: No such file or directory
  | FAIL: runner-end after an accepted done: cat: /tmp/tmp.G649F5sKav/cwd/test-1312463-ok/job/runner-end: No such file or directory
GATE-ONLY: FAIL passed=0 failed=1 shellcheck=ok only=10-chain-done
```
(The stray `cat:` line is gone now that the test reads the file with `2>/dev/null`.)
GREEN: `PASS 13-wait` and `PASS 10-chain-done`, each followed by `GATE-ONLY: PASS passed=1 failed=0 shellcheck=ok`.
Mutant M1a (final on any done/blocked, no runner-end check):
```
  | FAIL: wait returned before any change (status done the runner has not accepted: it may still refuse it (receipts, CI)): rc 0: wait: final · status: done · phase: 1 of 1 · child 0 · unit active · timer inactive
restored: cmp lib/units.sh identical
```
Mutant M1b (any runner-end is final, word not compared):
```
  | FAIL: wait exit 0, want 12 (runner-end says blocked, the status done): wait: final · status: done · phase: 1 of 1 · child 0 · unit inactive · timer inactive
restored: cmp lib/units.sh identical
```

### P6R2-3: a later timestamped run.log line hid an accepted end
No separate RED at HEAD: the P6R2-1 test comes first in the file and fails first. The new test is d2 (runner-end
`done`, unit inactive, then a `receipt phase 1: ...` line after the end) and must be 0. At HEAD it would read 12,
because the last timestamped line is the receipt. Mutant M3 shows that: it keeps the runner-end check and also
requires run.log's last timestamped line to be the end, as HEAD did:
```
  | FAIL: wait exit 12, want 0 (already done at start, a receipt line in run.log after the end (P6R2-3)): wait: stuck · status: done · phase: 1 of 1 · child 0 · unit inactive · timer inactive; see blast-off status /tmp/tmp.q0bF7rJ7et/cwd/test-1339604-fin/job
restored: cmp lib/units.sh identical
```

### Runner side: refused done writes nothing; a re-run clears runner-end
These are the RED above, then GREEN. Mutant MC1 (no `rm -f runner-end` at start):
```
  | FAIL: re-run on a done the runner refuses: exit 10, want 10 and no runner-end: blocked 2026-11-18T13:19:27Z
restored: cmp lib/chain.sh identical
```
Mutant MC2 (`chain_accept 'done'` before `ci_plan; receipt_all_done; ci_check`, so a refused done writes it):
```
  | FAIL: re-run on a done the runner refuses: exit 10, want 10 and no runner-end: done 2026-11-18T13:19:36Z
restored: cmp lib/chain.sh identical
```
(MC2 is killed by the re-open test, which comes first. The separate fresh-job refusal test asserts the same thing.)

### P6R2-5: an unaccepted `blocked` must not be final
Gap test (the code was already right, so there is no RED by design). New blk block: blocked with no runner-end
blocks while the unit is up, and is 12 once it is down. With `runner-end` `blocked` it is 0. Mutant M5 ("blocked is
always final", the review's survivor):
```
  | FAIL: wait returned before any change (status blocked the runner has not accepted): rc 0: wait: final · status: blocked · phase: 1 of 1 · child 0 · unit active · timer inactive
restored: cmp lib/units.sh identical
```

### P6R2-8: `deactivating` counts as down
Gap test (no RED by design). g4: a `deactivating` unit with status running is 12. Mutant M8 (`deactivating` dropped
from the down pattern):
```
  | FAIL: wait did not return (a deactivating unit is going down (P6R2-8)): 
restored: cmp lib/units.sh identical
```

### P6R2-4: stuck is time-based, not two polls
RED (13-wait with the runner-end change in and HEAD's two-poll rule still there):
```
  | FAIL: wait returned before any change (timer gone, unit not up yet, 3 polls): rc 12: wait: stuck · status: paused-limit until 2099-01-01T00:00:00Z · phase: 1 of 1 · child 0 · unit inactive · timer inactive; see blast-off status /tmp/tmp.Qhvy0MubFc/cwd/test-1320891-slow/job
GATE-ONLY: FAIL passed=0 failed=1 shellcheck=ok only=13-wait
```
GREEN: `GATE-ONLY: PASS passed=1 failed=0 shellcheck=ok only=13-wait`.
Mutant M4 (the stuck test is "a second down poll" again):
```
  | FAIL: wait returned before any change (timer gone, unit not up yet, 3 polls): rc 12: wait: stuck · status: paused-limit until 2099-01-01T00:00:00Z · phase: 1 of 1 · child 0 · unit inactive · timer inactive; see blast-off status /tmp/tmp.tzDkZiVfjJ/cwd/test-1347080-slow/job
restored: cmp lib/units.sh identical
```
Mutant M6 (`changed` reported while down, as the old rule did from the second down poll):
```
  | FAIL: wait exit 11, want 12 (unit went inactive): wait: changed · status: running · phase: 1 of 1 · child 0 · unit inactive · timer inactive
restored: cmp lib/units.sh identical
```

### P6R2-2: a read that never clears mid-watch
This RED was not seen before the code, because the scenario stopped on the P6R2-4 RED, which comes earlier in the
file. It was shown afterwards as mutant M2 (HEAD's unbounded retry put back):
```
  | FAIL: wait did not return (job dir deleted mid-watch): 
GATE-ONLY: FAIL passed=0 failed=1 shellcheck=ok only=13-wait
restored: cmp lib/units.sh identical
```
GREEN: `GATE-ONLY: PASS passed=1 failed=0 shellcheck=ok only=13-wait`.
Mutant M2b (the spell is not reset after a good read). The first run SURVIVED, with
`PASS 13-wait` / `GATE-ONLY: PASS passed=1 failed=0 shellcheck=ok only=13-wait`. The retry test then used the real
clock and 1 s of failures. It was rewritten as two spells of 8 failed reads (35 s each on wait's clock) with good
reads between them. Rerun:
```
  | FAIL: systemctl failing mid-watch, a second spell under 60 s, ended wait: rc 12: wait: stuck · no read for 60 s: systemctl --user show blast-off-test-1372420-retry.service or .resume.timer failed (no user bus?); see blast-off status /tmp/tmp.uCmq0tBvCR/cwd/test-1372420-retry/job
restored: cmp lib/units.sh identical
```

### P6R2-9, -10, -11, -19 (docs)
There is no behaviour mutant for these. 70-docs passes. What changed is listed per file above.

## Decisions (also in phase-6/findings.md)

- **File name:** `$JOB/runner-end`, holding one line `done <utc>` or `blocked <utc>`. It is written as
  `runner-end.tmp` and then `mv -f`, the same way as `chain_count_set`.
- **Write order:** `chain_accept` runs before `chain_end` logs `job done` / `job blocked; see ...`. For done, it runs
  after `ci_plan`, `receipt_all_done` and `ci_check`.
  - If the write fails, set -e exits 1 before `CHAIN_END`, so the EXIT trap logs `runner exit 1 without a state`.
    The job then reads stuck, not final.
  - A TERM or a failed `tee` after the file is written leaves the file in place, so wait reads `final`. The runner
    did accept the end. This also defuses the effect of P6R2-6 and P6R2-7 on wait, though neither was a target.
- **Clear on start:** `rm -f "$JOB/runner-end"` runs in `chain_run` after `chain_lock` and the traps.
  - Why after the lock: a second runner refused by a live runner's lock must not delete that runner's end.
  - A run that dies before the lock (missing CLAUDE_FLAGS, a bad count) leaves the earlier end. The job is unchanged,
    so that end still holds.
  - A refused done or blocked (exit 7, 9 or 10) never calls `chain_accept`.
  - Re-opened job: while the owner has the status at running, wait ignores the file. The next run deletes it before
    any child.
- **Dirty-tree check:** `chain_dirty` already skips every path under the job dir (the `JOBREL` prefix), so
  `runner-end` and its `.tmp` needed no change.
- **Timeouts:** both come from `date +%s`, not `$SECONDS`, so 13-wait can fake the clock. There is no env knob.
  - Stuck: 10 s from the first poll with both down. On that first poll the elapsed time is 0, so stuck needs at
    least two polls by construction.
  - Failed reads: 60 s from the first failed read of a spell. A good read resets it.
- **No `changed` while down:** while unit and timer are both down and stuck is not reached yet, wait reports no
  change. This extends P6R1-3's one-poll hold to the whole spell. Otherwise a slow handoff would print `changed`
  with `unit inactive`.
- **Machine sleep:** a change is still a state compare only. A sleep with the job down on both sides of it reads
  stuck at the next poll, which it is. A sleep that ends with the job newly down needs another 10 s.
- The 60 s stuck line is `wait: stuck · no read for 60 s: <WAIT_ERR>; see blast-off status <job>`. It has no
  status or unit fields, because the failed read has none.

## Not fixed (as briefed), and other observations

- Not touched: P6R2-6, -7, -12, -13, -14, -15 (partly covered by the new tests anyway: forged line, line after the
  end, failure that never clears, gap longer than two polls), -16, -17, -18, the skill-sheriff gaps P6R2-S1..S3, the
  round-1 leftovers P6R1-9, -12, -13, -14, and every LOW.
- P6R2-17 is still there. The start-time message says `missing <job>/checkpoint.md` for an empty file too. I changed
  only the docs ("a missing or empty checkpoint.md"), not the message, because 13-wait greps it.
- P6R1-18 (spec: "outside this table's range") and P6R1-19 (the caller's background command "has" a timeout) are left
  alone. `wait` now has two internal limits (10 s, 60 s), but still no overall timeout.
- Not tested: clearing before the lock (a refused second runner deleting a live one's end). It is a placement choice
  with a comment, but no scenario covers it.
- 13-wait's runtime grew. Stuck cases now take about 3 polls at step 5, the dl/nb cases about 13, and the retry
  block 16 failed polls plus two `blocks`. It is still a few seconds per case at 0.1 s polls.
- The P6R2-2 RED was observed only as a mutant (M2), after the code, as noted above. M2b survived the first test and
  was killed after the test was strengthened.
- The advisor was rate-limited at the planning call. There was no second read.
- No git operation. `STATE.md` and `log.md` were not touched. The scratchpad `fix2/` folder (GREEN copies, mutant
  script) is deleted.
