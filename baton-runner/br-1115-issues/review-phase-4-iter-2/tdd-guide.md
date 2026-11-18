# tdd-guide review: phase 4 fix round 1 (issue 22), `e766e00..43c5dd8`

Read-only and static. Nothing was run: no `tests/run`, no gate, no `bin/blast-off`. Every finding is traced by reading and marked UNREPRODUCED. The only probes were stdout-only bash and sed one-liners:
- `$((9223372036854775807+1))` gives `-9223372036854775808`.
- `$((7 - (CAP_SOFT ? BASE : 0)))` gives 7 with `CAP_SOFT=` and 2 with `CAP_SOFT=1`, for `BASE=5`.
- The fixed regex accepts `999999999 999999999` and rejects `1000000000 0`.
- `sed -n "-9223372036854775808p"` exits 1 ("invalid option").
- `if [ 3 -gt 99999999999999999999 ]` prints "integer expression expected" and takes the else branch.

## Summary

| Severity | Count |
|---|---|
| CRITICAL | 0 |
| HIGH | 0 |
| MEDIUM | 2 |
| LOW | 6 |

Code:
- The fix is correct for the hard cap. The guard and the ternary close every code path that let `base` reset the hard cap, and each of the two halves is pinned by its own conjunct.
- No code regression found.

Tests:
- One test was weakened. The new cap-0 run in test 21 now runs before the re-run. So the re-run starts from `2 2`, not `2 0`, and that masks a mutant the old re-run killed (TG2-2).
- The read side of the persisted `base` is still unpinned anywhere in the suite (TG2-1). So P4-22a's allotment surviving a plain relaunch is untested.

## Findings

### TG2-1: MEDIUM: the persisted `base` is never read in a way that matters, so a relaunch that loses the soft allotment passes every test (P4R1-8 left partly open)

- **Location:** `lib/chain.sh:123` (`BASE="${BASH_REMATCH[2]}"`); `tests/21-soft-cap.sh:26-40`; `tests/10-chain-done.sh:107-110`.
- **Failure path:** the mutant `BASE="${BASH_REMATCH[2]}"` -> `BASE=0`. The fixer ran it on test 21 and it passed; my trace says no other test kills it. These are the only runs that start on a file with `base` > 0:
  - test 10 `basehard` (`5 5`): the hard cap ignores `BASE` (`:186`), and the run exits before any save.
  - test 21's zero run (`:28`): it reads `2 0`, so `base` is 0 anyway.
  - test 21's re-run (`:34`): it reads `2 2`, but the status is `paused-cap` again (the zero run re-paused), so `:164` sets `BASE="$LAUNCHED"` before `:186` uses it.

  No test relaunches a soft-capped job whose status is `running` and whose file has `base` > 0. That state is real: a paused-cap resume run that ends by exit 5, 7, 8, a signal or a reboot, and is then started again. Under the mutant, such a job gets 0 children of its fresh allotment and exits 6 at once with a false "soft cap reached". That is P4-22a behaviour left untested.
- **Suggested fix:** use a separate job, so the main soft job is left alone (see TG2-2):
  1. `new_job softkeep step`, `plan 2`.
  2. `printf '2 2\n' > "$JOB/child-count"`, with status `running`.
  3. Run `JOB_CAP_FACTOR=1 "$bo" run`.
  4. Assert exit 6 with `child 3 launched`, `child 4 launched` and no `child 5 launched`, and `child-count` = `4 2`.

  Under the mutant, the run exits 6 with no child.
- UNREPRODUCED by me. The fixer's own run of this mutant on test 21 is quoted in `baton-phase-4-fix-1.md` "Open questions / risks".

### TG2-2: MEDIUM: the new cap-0 run weakens test 21's re-run, which no longer pins the in-memory `base` move

- **Location:** `tests/21-soft-cap.sh:28-30` (added), `:34-35` (weakened); `lib/chain.sh:164`.
- **Failure path:** before this fix, the re-run at `:34` read `2 0`. It needed the paused-cap branch to set the in-memory `BASE=2`, or `3 - 0 > 2` paused it and `:35` failed.

  Now the zero run writes `2 2` first, so the re-run's read path already sets `BASE=2`. Take the mutant `{ BASE="$LAUNCHED"; chain_count_set; }` -> `{ echo "$LAUNCHED $LAUNCHED" > "$JOB/child-count"; }`, which writes the file but leaves the in-memory `BASE` stale:
  - Zero run: the file is `2 2`, the run exits 6 and 2 children launched, so `:29` passes.
  - Re-run: it reads `2 2`, launches child 3 and reaches done, so `:35`, `:37` and `:40` pass.

  Pre-fix, that mutant failed `:35`. In real use, every paused-cap resume would need two runs. The first exits 6 again with "soft cap reached" and no child. That is the exact P4-22a allotment, broken.
- **Suggested fix:** run the cap-0 check on its own job:
  1. `new_job softzero step`, `plan 2`.
  2. `printf '2 0\n' > child-count`, and `sed` the status to `paused-cap`.
  3. Run `JOB_MAX_CHILDREN=0`, and assert exit 6 and `2 2`.

  This leaves the main soft job's re-run reading `2 0` as before. Alternatively, after `:30`, write `printf '2 0\n' > "$JOB/child-count"` back before `:34`. That restores the old coverage, but the re-run then no longer reads `k k` (P4R1-9). Keep the separate job instead.
- UNREPRODUCED.

### TG2-3: LOW: `tests/21-soft-cap.sh:36` is now satisfied by the zero run's log line

- **Location:** `tests/21-soft-cap.sh:36`.
- **Failure path:** `grep -q 'status paused-cap -> running; the chain continues' "$log"` searches the whole `run.log`. The zero run at `:28` now writes that line itself (it resumes from paused-cap). So the assertion, whose message is "re-run did not log the resume", can no longer see the re-run's own line missing. `:37` (`status_at_start` = running) still covers the status side.
- **Suggested fix:** `[ "$(grep -c 'status paused-cap -> running' "$log")" -eq 2 ]`, or move the zero run to its own job (TG2-2), which fixes both.
- UNREPRODUCED.

### TG2-4: LOW: under the hard cap, a `paused-cap` status is still turned into `running`, with "the chain continues" logged, right before exit 4; the spec says "unchanged", and the new test does not pin either

- **Location:** `lib/chain.sh:164-165`; `tests/10-chain-done.sh:90-93`; `docs/spec.md:91` (exit 4, "Checkpoint status written: unchanged"); `chain_cap` comment `lib/chain.sh:97` ("exit 4, status kept").
- **Failure path:** the cap4 run starts at `status: paused-cap`. With `CAP_SOFT` empty, `:164` skips the `base` move, but `:165` still runs `cp_set_status running` and logs `status paused-cap -> running; the chain continues`. Then `:186-187` exits 4 at once.
  - Before this fix that log line was true under the hard cap (the chain did continue). After it, the line is false.
  - The exit 4 leaves the status as `running`, not the `paused-cap` the run found.
  - `10:93` asserts the rc, no child 3, and `2 0`, but not the status or the log line. So whichever behaviour the owner picks is unpinned.

  The fixer flagged this as an open risk.
- **Suggested fix:** pick one and pin it.
  - Option (a): under the hard cap, leave `paused-cap` alone and log `status paused-cap kept; the hard cap does not resume (P4-22a)`. Then assert `^status: paused-cap$` after `10:92`.
  - Option (b): keep the code, reword the log line for the hard cap, and say in spec row 4 that a `paused-cap` is set back to `running`. Then assert `^status: running$`.
- UNREPRODUCED.

### TG2-5: LOW: the 9-digit bound is pinned only from far above (19 digits), and no valid multi-digit count is read anywhere

- **Location:** `lib/chain.sh:121`; `tests/10-chain-done.sh:97`; `docs/spec.md:61` ("at most 9 digits").
- **Failure path:**
  - The only big test value is `9223372036854775807 0` (19 digits). So the group-1 mutants `{0,8}` -> `{0,9}` through `{0,17}` all survive.
  - In the other direction, `{0,8}` -> `{0,7}` or even `{0,0}` (single-digit `launched`) survive too. The largest `launched` any test reads is 5 (`basehard`). Under `{0,0}`, a job's 10th child would make every later run exit 1 "garbled".
  - The spec's exact "at most 9 digits" is not bound by any test.
- **Suggested fix:**
  - Add `1000000000 0` to the garbled loop. This kills `{0,9}` and up.
  - Add one valid multi-digit read: for example, `printf '12 10\n'` on a hard-cap job at `JOB_MAX_CHILDREN=12`, asserting exit 4, no child, and the message naming `12 children`. This kills the narrow-bound mutants.
  - Optionally, read `999999999 0` at a huge cap for the top edge.
- UNREPRODUCED.

### TG2-6: LOW: the zero-byte case checks less than the loop it extends

- **Location:** `tests/10-chain-done.sh:104-106`.
- **Failure path:**
  - Unlike `:100`, it does not grep `badcount.out` for `$JOB/child-count`. An exit 1 for another reason passes. Before the lock, that could be a missing brief, a bad `JOB_*` value, or `cat` failing.
  - `[ ! -s "$JOB/child-count" ]` is also true when the file is gone, so "left as it was" is not pinned. A mutant that `rm`s a garbled file before dying would pass.
  - The `-e` -> `-s` mutant is still killed (by the marker and rc conjuncts), so P4R1-11 itself is closed.
- **Suggested fix:** `[ -e "$JOB/child-count" ] && [ ! -s "$JOB/child-count" ] && grep -q "$JOB/child-count" badcount.out`. Or fold `: >` into the loop with a special case for the read-back.
- UNREPRODUCED.

### TG2-7: LOW: zeroing `base` under the hard cap is not pinned, though the fix and spec say `base` moves only on a soft paused-cap resume

- **Location:** `lib/chain.sh:185,196`; `docs/spec.md:61` ("`base` is the soft cap's alone and moves to `launched` only when a re-run under the soft cap..."); the fix baton's design note ("`BASE` is not zeroed under the hard cap, so the save before launch keeps the soft allotment if the Phase plan comes back").
- **Failure path:** the mutant `[ -n "$CAP_SOFT" ] || BASE=0` after `chain_cap` survives:
  - `basehard` (`5 5` at cap 1) exits before any save, so its `5 5` read-back never sees a write.
  - cap4's `base` is already 0.

  Real effect: a soft job that loses its rows for one run (route (b) of P4R1-1) comes back with `base` 0. Its next soft run then pauses at once.
- **Suggested fix:** a hard-cap run that launches one child from a `base` > 0 file. For example, `basehard` at `JOB_MAX_CHILDREN=6`: assert child 6 launched, exit 4, and `child-count` = `6 5`.
- UNREPRODUCED.

### TG2-8: LOW: the stated reason for switching the garbled loop from `step` to `noop` does not hold

- **Location:** `tests/10-chain-done.sh:95-96` comment ("noop children so a wrapped count ends on two stalls, not on the harness timeout"); `tests/fakes/claude:22,44`.
- **Failure path:** with a wrapped count, the child's `JOB_CHILD` is negative (`lib/child.sh:48` passes `$n`). The fake's `mode="$(sed -n "${JOB_CHILD}p" ...)"` then exits 1 (the probe gives `sed: invalid option -- '9'`, rc 1). Under `set -euo pipefail`, the fake exits at `:44`, before its marker (`:47`) and before acting on any mode. So `step` and `noop` behave the same for that value, and both end on two stalls.

  Nothing is weakened. On the fixed code no loop value launches a child. Under a mutant that accepts one, any launch writes a marker (non-negative numbers) or changes the rc (negative numbers). The only problem is that the comment gives a wrong reason.
- **Suggested fix:** reword the comment ("a wrapped count's negative child number makes the fake exit before acting"), or revert to `step`. Either is fine.
- UNREPRODUCED. I did not run the wrapped case under `step`.

## Round-1 closure

| ID | Verdict | Evidence |
|---|---|---|
| P4R1-1 | Closed | Code: guard at `chain.sh:164`, ternary at `:186`. Route (a), a forged/left-over `paused-cap` under the hard cap, is pinned by `10:93`; the `"2 0"` conjunct kills guard removal (M1a). Route (c), a `5 5` file, is pinned by `10:110`; the `! -e fake-marker` and `"5 5"` conjuncts kill `n - BASE` (M1b), because rc 4 alone would also pass under M1b (child 6 launches, then exit 4). Route (b), rows lost after a soft resume, is covered as a state by `basehard`, not end to end. README row 4 and spec row 4 are now true. Residual: TG2-4 (status flip and a false log line under the hard cap). |
| P4R1-6 | Partly closed | `chain_count`'s regex is bounded (`chain.sh:121`), and `9223372036854775807 0` is in the loop (`10:97`); the old unbounded regex is killed at `10:100`. Not done, though the round-1 fix line filed it: the same bound in `chain_nums` (`chain.sh:90`). Probe: `[ 3 -gt 99999999999999999999 ]` errors and reads false inside the `if`, so a 20-digit `JOB_MAX_CHILDREN` still turns off the cap (hard and soft) for a run. The fixer lists it as an open risk. The bound's edges are unpinned (TG2-5). |
| P4R1-8 | Partly closed | The save-drop mutant (M8) is killed at `21:29` (`"2 2"` conjunct). Still surviving: the read-side `BASE=0` (TG2-1) and the swap of the branch's save and `cp_set_status running` (crash window only, as in round 1). New masking: TG2-2. |
| P4R1-9 | Closed | `-le` -> `-lt` is killed at `21:35`: the re-run reads `2 2`, and the mutant dies with exit 1. That is the fixer's M9 output, and it matches my trace. |
| P4R1-10 | Partly closed | The duplicate `rm` is deleted (`11:58` remains, comment accurate). The baton correction is written in `baton-phase-4-fix-1.md`. The `[ -n "$pid" ] \|\| fail` guard after `11:61`, filed as part of the fix, was not added. So the round-1 mutant "delete the `rm`" still makes test 11 pass vacuously (empty `pid`, `gone ""` true). |
| P4R1-11 | Closed | `: >` case at `10:104-106`. `-e` -> `-s` is killed there: a fresh job, child 1 launches, the `! -e fake-marker` and rc conjuncts fail (fixer M11, matches trace). The weaker checks are TG2-6. The `cat`-failure die (`chain.sh:120`) is still untested (near-equivalent, as in round 1). |

## Mutant table

All traced, none run by me. "Fixer" marks the ones `baton-phase-4-fix-1.md` reports running.

| Mutant (exact edit) | Killing assertion | Result |
|---|---|---|
| `chain.sh:164` guard removed: `{ BASE="$LAUNCHED"; chain_count_set; }` unconditional (M1a) | `10:93`, `"2 0"` conjunct only (rc 4 and no child 3 still hold) | killed (fixer) |
| `chain.sh:164` guard inverted: `[ -n "$CAP_SOFT" ] \|\|` | `21:29` `"2 2"` (soft skips the move); also `10:93` `"2 0"` | killed |
| `chain.sh:164` block never runs (delete `{ ... }` or `false &&`) | `21:29` | killed |
| `chain.sh:164` `BASE="$LAUNCHED"` -> `BASE=0` (saves `L 0`) | `21:29` | killed |
| `chain.sh:164` drop `chain_count_set` (M8) | `21:29` | killed (fixer) |
| `chain.sh:164` write the file but not the in-memory `BASE`: `{ echo "$LAUNCHED $LAUNCHED" > "$JOB/child-count"; }` | none. The re-run at `21:34` reads `2 2` since the zero run; pre-fix `21:35` killed it | survives (TG2-2) |
| `chain.sh:164-165` run `cp_set_status running` before the block | none (crash window only) | survives |
| `chain.sh:186` `(CAP_SOFT ? BASE : 0)` -> `BASE`, i.e. `n - BASE` (M1b) | `10:110`, the `! -e fake-marker` / `"5 5"` conjuncts (rc is 4 either way) | killed (fixer) |
| `chain.sh:186` -> `(CAP_SOFT ? 0 : BASE)` | `10:110` (hard: `6-5=1`, child 6 launches); `21:35` (soft: `3-0>2`, exit 6) | killed |
| `chain.sh:186` -> `0`, i.e. `n` under both caps | `21:35` (re-run exits 6, want 0) | killed |
| `chain.sh:186` `-gt` -> `-ge` | `10:77` (cap 1 must launch child 1) | killed (pre-existing assertion) |
| after `chain_cap`: `[ -n "$CAP_SOFT" ] \|\| BASE=0` (hard zeroes `base`) | none (`basehard` exits before any save) | survives (TG2-7) |
| `chain.sh:123` `BASE="${BASH_REMATCH[2]}"` -> `BASE=0` | none in the suite | survives (TG2-1; fixer ran it on 21) |
| `chain.sh:123` `LAUNCHED=...` -> `LAUNCHED=0` | `10:82-83`, `10:86` | killed (pre-existing) |
| `chain.sh:121` `-le` -> `-lt` (M9) | `21:35` | killed (fixer) |
| `chain.sh:119` `-e` -> `-s` (M11) | `10:106` | killed (fixer) |
| `chain.sh:121` group 1 `{0,8}` -> `*` (M6) | `10:100` rc conjunct (`9223372036854775807 0`) | killed (fixer) |
| `chain.sh:121` group 1 `{0,8}` -> `{0,18}` | `10:100` | killed |
| `chain.sh:121` group 1 `{0,8}` -> `{0,9}` ... `{0,17}` | none (no 10-18 digit value) | survives (TG2-5; no wrap below 19 digits, but the spec says 9) |
| `chain.sh:121` group 1 `{0,8}` -> `{0,7}` or `{0,0}` | none (largest `launched` read is 5) | survives (TG2-5) |
| `chain.sh:121` group 2 `{0,8}` -> `*` | n/a: `base <= launched <= 9 digits`, no leading zeros, so it is the same language | equivalent |
| `chain.sh:121` group 2 `{0,8}` -> `{0,0}` | none (largest `base` read is 5) | survives (TG2-5) |
| `chain.sh:121` group 2 drops `0\|` | `10:82` (re-run reads `1 0`) | killed |
| `chain.sh:122` die message without `$f` | `10:100` grep (not the zero-byte case) | killed |
| `tests/11-unit-smoke.sh:58` delete the `rm` | none (test goes vacuous) | survives (P4R1-10 partly open) |

## Acceptance criteria (issue 22)

1. **A cap reached across two runner runs stops the job (exit 4).** Covered, and it passes by reading.
   - `10:71-73`: run 1 at cap 1, child 1, exit 4.
   - `10:81-83`: a re-run at cap 1 exits 4 with exactly one launch.
   - `10:84-89`: a re-run at cap 2 launches child 2 and exits 4 with no child 3.
   - `10:142-144`: SIGHUP during child 1, then a re-run at cap 1 exits 4 with no child.
   - Soft analog: `21:44-49` (exit 6 on relaunch).
2. **Child numbers in `run.log` continue after a relaunch.** Covered.
   - `10:86-87`: `child 1 launched` once, `child 2 launched` on the re-run.
   - `21:40`: `child 3 launched` after paused-cap, `child 1 launched` once.
3. **A fresh job starts at child 1.** Covered.
   - `10:16`: a fresh `ok` job logs `child 1 launched`.
   - `10:77`: `^child=1 ` in the fresh `cap` job's marker.
   - `10:124`: the fresh `stray` job's `^child=1 .*mode=done`.

   A mutant that starts at 2 fails `10:16`. P4R1-24's "no new assertion against a leftover file" is round-1 and not re-filed.

## Answers to the focus questions, briefly

1. See the closure and mutant tables. P4R1-1, -9 and -11 are closed. P4R1-6, -8 and -10 are partly closed.
2. Regression: TG2-2 (masked mutant) and TG2-3 (log grep). Test 10's `step` -> `noop` does not weaken the loop (TG2-8). The zero-byte case checks less than the loop (TG2-6). The cap4 case's precondition (`2 0`, status forced to `paused-cap`) holds by reading after `10:84-89`, and its `"2 0"` read-back pins it. No new assertion is vacuous: the `basehard` rc conjunct alone would pass for the wrong reason under M1b, but the marker and read-back conjuncts carry it.
3. Every code path through which `base` could reset the hard cap is closed and pinned (`10:93`, `10:110`). Remaining ways to get more hard-cap children, all outside this round's code or already filed:
   - deleting or rewriting `child-count`, which the die message itself recommends (P4R1-5, P4R1-12, P4R1-18; not re-filed);
   - a 20-digit `JOB_MAX_CHILDREN` (P4R1-6's unfixed `chain_nums` sibling);
   - a child adding Phase plan rows, which moves the job to the soft cap by design.
4. Yes for the code. The paused-cap move is soft-only, and the soft cap subtracts `base`. Pinned in-run (`21:29`, `21:35`), but not across a plain relaunch (TG2-1), and the in-memory move is now masked (TG2-2).
5. These statements are true against the code and tests:
   - spec rows `10-chain-done` and `21-soft-cap`;
   - spec §2 `:61` on the hard cap, the soft cap and the 9-digit bound;
   - README exit-4 row ("counted over every run of the job").

   Two exceptions:
   - The exit-4 row's "status unchanged" is false when a run starts at `paused-cap` (TG2-4).
   - §2's new "so it never resets for a job" sits beside the die message's "delete it to count this job's children from 0 again". That is P4R1-18's point, now stated more strongly in the spec. It is not re-filed.

   Row 10's "a `child-count` that is empty (zero bytes ...) is left as it was" is asserted only as "not non-empty" (TG2-6).
6. Yes, see "Acceptance criteria".

## Validated

- `lib/chain.sh` `chain_cap`, `chain_count`, `chain_count_set` and `chain_run` read in full at HEAD 43c5dd8. `CAP_SOFT` is always set (`1` or empty) before `:186`. An empty value is 0 in arithmetic (probed), so the ternary is sound under `set -u`.
- The `[ -z "$CAP_SOFT" ] || { ...; }` block's failure is the last command of the `||` list, so a failed save still aborts under `set -e`, as before.
- `chain_count` runs before `chain_lock` and the EXIT trap, so every garbled-file case exits 1 with no lock left and no `run.log` line (as round 1 noted).
- Test 10 cap4 trace: `2 0`, hard, the `paused-cap` branch skips the move, `n=3 > 2`, exit 4, the file stays `2 0`.
- Test 10 basehard trace: `5 5`, hard, `n=6 > 1`, exit 4, no save. Under the round-1 code, child 6 would launch and exit 4 would follow with `6 5`; the fixer's RED 1 matches that.
- Test 21 zero-run trace: `2 0`, soft via `JOB_MAX_CHILDREN=0`, the move saves `2 2`, `3-2=1 > 0`, exit 6, status `paused-cap` again.
- Test 21 re-run trace: `2 2`, the move is a no-op, `3-2=1 <= 2`, child 3 (`done`), exit 0.
- `tests/fakes/claude` picks its mode by `JOB_CHILD` (last line repeats), so continued numbering does not change the modes the tests intend.
- Other tests touching `paused-cap`/`child-count`: test 31's `cap` job is fresh and hard, so its outcome is independent of this fix. Test 51 quotes only template text. Test 11's single `rm` and its comment are accurate.
- The README exit table (`README.md:132-139`) for codes 4 and 6 matches the fixed code.

## Not examined

- Nothing was executed: no scenario, gate, shellcheck or mutant run. Mutant results marked "fixer" come from `baton-phase-4-fix-1.md`; the rest are traced only.
- `lib/checkpoint.sh` (`cp_status`, `cp_set_status`, `cp_phases`, `cp_unread`), `lib/child.sh` beyond the `JOB_CHILD` line, and `lib/units.sh`: only their call sites were read.
- Route (b) of P4R1-1 end to end: a soft job resumed, then its rows made unreadable, then a hard run. It was checked only as the equivalent `5 5` state.
- The round-1 open items (P4R1-2 to -5, -7, -12 to -30) were not re-assessed, beyond noting that none got worse. The one exception is P4R1-18's "remedy resets the cap", which the new spec §2 wording ("never resets") now contradicts more directly (Q5).
- `chain_nums` overflow of `phases * JOB_CAP_FACTOR` (the fixer's open risk): not traced further.
