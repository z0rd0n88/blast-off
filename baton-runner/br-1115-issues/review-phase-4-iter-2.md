# Multi-Agent Review, round 2 (narrow): fix commit 43c5dd8 (phase 4, issue 22): lib/chain.sh + tests/10-chain-done.sh + tests/11-unit-smoke.sh + tests/21-soft-cap.sh + docs/spec.md (fix diff e766e00..43c5dd8, phase base 7867255)

## Executive Summary

Two reviewers (code-reviewer, tdd-guide) reviewed the round-1 fix diff `e766e00..43c5dd8` by static work only, in the context of the whole phase diff `7867255...43c5dd8`. The fix addressed P4R1-1, -6, -8, -9, -10 and -11 under owner ruling P4-22a. After dedupe there are **0 CRITICAL, 0 HIGH, 2 MEDIUM and 11 LOW**. Refutation did not run. The review unit reproduced four of the claims with single-scenario mutant runs (see Notes).

**Headline.** Both reviewers find the code fix correct. The soft-only guard on the paused-cap branch (`lib/chain.sh:164`) and the cap test `$((n - (CAP_SOFT ? BASE : 0)))` (`:186`) shut every route by which `base` or a `paused-cap` status could reset the hard cap. Each half is killed by its own conjunct (`tests/10-chain-done.sh:93` `"2 0"`, `:110` marker and `"5 5"`). Neither reviewer found a runtime regression, and neither found a new hard-cap reset path. The paths that remain are round-1 findings left open (P4R1-4, -5, -12, -18, -23) and the `chain_nums` overflow (P4R2-9). Soft-cap behaviour matches P4-22a.

The two MEDIUMs are test gaps, not code defects:

- **P4R2-1.** Reading `base` back from the file is still unpinned. `BASE=0` on read passes the whole suite. The review unit reproduced this on tests 10 and 21.
- **P4R2-2.** The fix weakened test 21. Its new cap-0 run writes `2 2`, so a mutant that writes the file but does not move the in-memory `BASE` now passes. The same mutant failed test 21 before the fix. The review unit reproduced both results.

**Acceptance criteria.** Both reviewers find all three criteria of issue 22 covered by passing tests:

- **Criterion 1** (a cap reached across two runner runs stops the job, exit 4): `tests/10-chain-done.sh:81-89`, `:90-93` and `:142-144`.
- **Criterion 2** (child numbers continue after a relaunch): `10:86-87` and `tests/21-soft-cap.sh:40`.
- **Criterion 3** (a fresh job starts at child 1): `10:16` and `10:77`, plus `10:124` (tdd-guide).

The gate passes: `GATE: PASS passed=18 failed=0 shellcheck=ok`, exit 0.

**Recommended action: merge-with-fixes (optional).** No finding blocks. P4R2-1 and P4R2-2 are each one small test job in test 21.

## Critical Findings

None.

## High Findings

None. Both reviewers list CRITICAL and HIGH as none.

## Medium and Low Findings

"cr" is code-reviewer and "tg" is tdd-guide. "Reproduced" means the review unit ran it. Every other row was traced by reading only (UNREPRODUCED).

| ID | Severity | Title | Location | Reviewer(s) | One-line description |
|---|---|---|---|---|---|
| P4R2-1 | MEDIUM | Reading `base` back from `child-count` is unpinned: `BASE="${BASH_REMATCH[2]}"` -> `BASE=0` passes the whole suite (rest of P4R1-8) | `lib/chain.sh:123`; `tests/21-soft-cap.sh:28-40` | cr (F1), tg (TG2-1): MEDIUM | Only two kinds of run read a file with `base` > 0. A hard-cap run ignores `base`, and a paused-cap resume overwrites it. A soft job relaunched with status `running` from `L B` is therefore untested. Such a relaunch follows a resumed run that ended on exit 5, 7 or 8, a `stop`, or a reboot. If the read regresses, that relaunch pauses at once with a false "soft cap reached", and P4-22a's allotment is lost. Fix: add a separate soft job that starts from `2 2` with status `running` at cap 2, and require it to launch child 3. **Reproduced:** mutant MA passes `10-chain-done` and `21-soft-cap`. No other scenario reads a nonzero `base`: 11 deletes the file, the `cap` job in 31 is fresh, and 51 only quotes wording. |
| P4R2-2 | MEDIUM | The fix weakened test 21: its re-run no longer pins the in-memory `BASE` move at a paused-cap resume | `tests/21-soft-cap.sh:26-30,34-35`; `lib/chain.sh:164` | tg (TG2-2) | The new cap-0 run leaves the file at `2 2`, so the re-run reads `BASE=2` from disk. A mutant that writes `L L` to the file but leaves the in-memory `BASE` alone now passes. In real use every resume would then need two runs: the first pauses again with no child. Fix: give the cap-0 check its own job, or re-seed `2 0` before the re-run. **Reproduced:** mutant MB, `{ echo "$LAUNCHED $LAUNCHED" > "$JOB/child-count"; }`, gives `GATE-ONLY: PASS` at 43c5dd8. The equivalent mutant at e766e00 gives `FAIL: re-run after paused-cap exit 6`. |
| P4R2-3 | LOW | Test 21's resume-log grep is now also satisfied by the cap-0 run's own log line | `tests/21-soft-cap.sh:36` | cr (F6), tg (TG2-3) | `run.log` accumulates across runs, and the zero run also logs `status paused-cap -> running; the chain continues`. Line 37 (`status_at_start`) still catches a skipped branch, so coverage is only partly lost. Fix: require `grep -c` = 2. Introduced by this fix. |
| P4R2-4 | LOW | Under the hard cap, a `paused-cap` status is still set to `running` and logged as "the chain continues", then the runner exits 4 with no child | `lib/chain.sh:164-165`; `docs/spec.md:91` (exit-4 status column "unchanged"); `lib/chain.sh:97` comment; `tests/21-soft-cap.sh:4` header; `tests/10-chain-done.sh:90-93` | cr (F4), tg (TG2-4) | This contradicts "status unchanged" in the exit-4 row, and the new test at `10:90-93` pins neither behaviour. cr: fix the docs, not the code, because `tests/31-resume-after-reset.sh:58-61` relies on the transition (its fresh hard-cap `cap` job resumes from paused-cap). tg: the owner should pick one behaviour and assert it. The fix baton raised the same point as an open risk. |
| P4R2-5 | LOW | The 9-digit bound is not tested at its edge | `lib/chain.sh:121`; `tests/10-chain-done.sh:96` | cr (F3), tg (TG2-5) | The bound is pinned only by a 19-digit value, and the largest valid count any test reads is 5. Group 1 `{0,9}` to `{0,17}` survives, and so does a tighter `{0,7}` or `{0,0}`. Group 2 `{0,0}` survives too. The spec's "at most 9 digits" is untested. Fix: add `1000000000 0` to the garbled list and read one valid multi-digit count. **Reproduced:** mutant MC (group 1 `{0,17}`) gives `GATE-ONLY: PASS` on `10-chain-done`. |
| P4R2-6 | LOW | The zero-byte case asserts less than the garbled loop it extends | `tests/10-chain-done.sh:104-106` | cr (F8), tg (TG2-6) | It does not grep `badcount.out` for the `child-count` path, so any exit 1 passes. Its `[ ! -s ]` check would also pass if the file had been deleted. Fix: add `grep -q "$JOB/child-count" badcount.out` and `[ -e "$JOB/child-count" ]`. |
| P4R2-7 | LOW | Zeroing `base` under the hard cap is unpinned | `lib/chain.sh:152-165`; `tests/10-chain-done.sh:108-110` | tg (TG2-7) | The spec and the fix say `base` moves only on a soft paused-cap resume. A mutant `[ -n "$CAP_SOFT" ] \|\| BASE=0` after `chain_cap` survives, because `basehard` exits before any save. The cost: a job whose Phase plan comes back loses its soft allotment. Fix: a hard-cap run from `L B` with B > 0 that launches one child, then assert the file holds `L+1 B`. |
| P4R2-8 | LOW | The comment justifying `step` -> `noop` in test 10's garbled loop gives the wrong reason | `tests/10-chain-done.sh:94-96` | tg (TG2-8); cr agrees nothing is weakened | With a wrapped negative child number, the fake claude stops at its `sed` line before it reads the mode, so the mode makes no difference. cr: the fake writes `fake-marker` before it reads its mode, so the `! -e fake-marker` checks still hold. Fix: correct or drop the comment. Nothing is weakened. |
| P4R2-9 | LOW | `chain_nums` still accepts any length: a 20-digit `JOB_MAX_CHILDREN` turns the cap off for that run (rest of P4R1-6) | `lib/chain.sh:90,186` | cr (F2); tg (closure table) | The `-gt` test errors on an out-of-range value, and an error reads as false inside the `if`, so no cap fires. Both reviewers confirmed this with a stdout-only probe. The value comes from the owner's environment, and the behaviour predates this phase. A huge `JOB_CAP_FACTOR` overflowing `phases * factor` is the fix baton's sibling note. Fix: the same `{0,8}` bound in `chain_nums`. The round-1 row filed this as security-reviewer's suggestion. |
| P4R2-10 | LOW | Test 11 `start_hang` still has no `[ -n "$pid" ]` guard (rest of P4R1-10) | `tests/11-unit-smoke.sh:58-62` | cr (F5); tg (closure table and mutant table) | The duplicate line is gone. If the `rm` were dropped, `pid` would be empty, `gone ""` would be true, and the test would pass vacuously. Fix: add `[ -n "$pid" ] \|\| fail ...` after the `sed`. |
| P4R2-11 | LOW | The new doc claim "so it never resets for a job" is stronger than the code | `docs/spec.md:61`; `lib/chain.sh:185` comment; the die message at `:122` | cr (F7); tg mentions it without filing | The runner's own garbled-file message tells the owner to delete `child-count` to count from 0 again, and round-1's open P4R1-5, -12 and -18 are reset paths. Fix: "never resets through `base` or `paused-cap`", or name deleting the file as the one deliberate reset. tg traces the clash to P4R1-18 and did not re-file it. |
| P4R2-12 | LOW | The `cat`-failure die (`cannot read`) is untested (rest of P4R1-11) | `lib/chain.sh:120` | cr (F9) | Round-1's P4R1-11 row named it "near-equivalent". It is still unbound: an unreadable file (mode 000, or a directory) has no case. |
| P4R2-13 | LOW | At child 1,000,000,000 the count rolls past the 9-digit bound | `lib/chain.sh:121,196` | cr (F10); also the fix baton's open risks | The save writes `1000000000 B`, and every later run refuses the file as garbled. Unreachable in practice. |

## Round-1 closure

| Round-1 ID | cr | tg | Synthesis |
|---|---|---|---|
| P4R1-1 (hard cap reset through `base`) | Closed: all three routes are shut. `10:90-93` and `10:108-110` kill each half of the fix, and the exit-4 message is now accurate | Closed: M1a is killed only by the `"2 0"` conjunct at `10:93`, and M1b only by the marker and `"5 5"` conjuncts at `10:110` | **Closed** |
| P4R1-6 (int64 wrap) | Partly closed: `chain_nums` is not bounded, and the edge is untested | Partly closed: same | **Partly closed.** The parser is closed (M6 and `{0,18}` killed). P4R2-9 and P4R2-5 remain |
| P4R1-8 (persisting `base` unpinned) | Partly closed: the save is tested, the read is not | Partly closed: the read is not tested, and the save/`cp_set_status` swap (crash window) still survives | **Partly closed.** P4R2-1 remains. P4R2-2 is a new hole opened by the fix |
| P4R1-9 (`-le` at equality) | Closed: the re-run reads `2 2` | Closed: `-lt` is killed at `21:35` | **Closed** |
| P4R1-10 (test 11 duplicate line and missing guard) | Partly closed: the line is deleted, the guard is not added | Partly closed: same | **Partly closed.** P4R2-10 remains, and the fix baton says the guard was not asked for |
| P4R1-11 (zero-byte file) | Closed, with weaker assertions | Closed: `-s` is killed at `10:106` | **Closed.** P4R2-6 and P4R2-12 are remainders |

Neither reviewer found a round-1 open finding made worse. cr notes that P4R1-23 (a forged `paused-cap`) is now harmless under the hard cap.

## Coverage Report

Reviewers: 2/2 returned
Reviewed at: 43c5dd8
Any commit after this one is unreviewed.

- **Confirmed:**
  - **The hard cap has no remaining reset through `base` or `paused-cap`** (cr, tg). The cap mode is fixed once per run (`chain_cap` at `:152`), so mode changes happen only between runs. cr walked these: hard to soft, soft to hard with `base` > 0, a forged `paused-cap`, and values written by children. Everything left is round-1 open (P4R1-4, -5, -12, -23) or P4R2-9.
  - **No runtime regression** (cr, tg). `CAP_SOFT` is always `1` or empty (`chain_cap` assigns it unconditionally), so `(CAP_SOFT ? BASE : 0)` evaluates safely. `set -e` still fires inside the guarded `{ ...; chain_count_set; }` (cr, probed). The regex behaves as intended.
  - **Soft cap matches P4-22a** (cr, tg). One behaviour change follows from the ruling: a soft job past 12 children that loses its Phase plan rows now exits 4 at once (cr).
  - **The docs are true as written** (cr, tg), except P4R2-4 and P4R2-11. This covers the spec §2 `JOB_MAX_CHILDREN` text, the `10-chain-done` and `21-soft-cap` rows, and README exit rows 4 and 6.
  - **The new tests are real** (cr, tg). tg's mutant table has 25 rows: 16 killed (6 of them by the fixer's runs), 8 survive and 1 is equivalent.
  - **Gate:** `GATE: PASS passed=18 failed=0 shellcheck=ok` at 43c5dd8. The review unit ran it.
- **Examined, inconclusive:**
  - The fixer's RED, GREEN and mutant outputs. Both reviewers read them as consistent with the code. Neither re-ran them.
- **Not examined:**
  - Scenarios outside 10, 11, 21 and 31 beyond greps. Neither reviewer ran anything; the review unit's runs are listed in Notes.

## Reviewer Disagreements

- **P4R2-4: fix the docs or the code.** cr: change the docs, because test 31 relies on the paused-cap -> running transition under the hard cap. tg: an owner decision, then assert the chosen behaviour.
- **Severity of the P4R1-6 remainder (`chain_nums`).** cr files it as LOW (F2). tg records it only in the closure table, with no severity. Rendered LOW.
- **P4R2-11.** cr files it (F7). tg sees the same clash but leaves it under round-1's P4R1-18. Rendered LOW as a new doc claim, because the sentence is new in this fix.

## Recommended Changes (Prioritized)

1. **P4R2-2, then P4R2-1.** Move test 21's cap-0 check to its own job, so the main re-run reads `2 0` again. Add a soft job that starts from `2 2` with status `running` at cap 2 and must launch child 3.
2. **P4R2-4.** Owner call: either keep `paused-cap` under the hard cap, or reword the exit-4 status column, the `chain.sh:97` comment and test 21's header. Then assert the choice at `10:93`.
3. **P4R2-11.** Reword "never resets for a job" so it names deleting the file as the deliberate reset.
4. **Test tightening:** count the resume line (P4R2-3); add `1000000000 0` and one valid multi-digit read (P4R2-5); tighten the zero-byte case (P4R2-6); add a hard-cap launch from `L B` (P4R2-7); fix the `noop` comment (P4R2-8); add the `[ -n "$pid" ]` guard (P4R2-10); add an unreadable-file case (P4R2-12).
5. **P4R2-9.** Bound `chain_nums` the same way.
6. **P4R2-13.** No change needed.

## Open Questions for the Author

- Under the hard cap, should a `paused-cap` status stay `paused-cap` at exit 4, or turn into `running` as it does now, with the docs reworded (P4R2-4)? Disposition: PENDING
- Is deleting `child-count` the one intended reset of a job's hard cap, and should "never resets for a job" say so (P4R2-11)? Disposition: PENDING
- Carried from round 1, still PENDING: P4-22b (README exit-4 remedy needs a second start), reusing a job dir, whether the cap must hold against a child that deletes `child-count`, and "launched" vs "attempted".

## Notes

- **Parked reviewers.** Both are parked agents (`~/.claude/agents-parked/code-reviewer.md` and `tdd-guide.md`). Each ran as a `general-purpose` agent told to read its parked definition and adopt it, read-only.
- **Roster.** Narrow round 2: two reviewers, as the brief named.
- **Static work only.** Neither reviewer ran a scenario, `tests/run`, `scripts/gate.sh` or `bin/blast-off`. Both report only stdout-only bash probes. Each reviewer wrote only its own output file.
- **Review-unit reproductions.** Each was one scenario on its own `git archive` copy, run sequentially, and ExecStart was checked after each one:
  - MA (`:123` `BASE=0`): `10-chain-done` gave `GATE-ONLY: PASS`, and `21-soft-cap` gave `GATE-ONLY: PASS`. P4R2-1 confirmed.
  - MB (`:164` writes `L L` to the file, in-memory `BASE` untouched): at 43c5dd8, `21-soft-cap` gave `GATE-ONLY: PASS`. At e766e00, the same edit on line 163 gave `FAIL: re-run after paused-cap exit 6` and `GATE-ONLY: FAIL`. P4R2-2 confirmed.
  - MC (`:121` group 1 `{0,8}` -> `{0,17}`): `10-chain-done` gave `GATE-ONLY: PASS`. P4R2-5 confirmed.
- **Reviewer outputs:** `baton-runner/br-1115-issues/review-phase-4-iter-2/code-reviewer.md` (1 MEDIUM, 9 LOW) and `tdd-guide.md` (2 MEDIUM, 6 LOW). After dedupe: 2 MEDIUM, 11 LOW. Every listed reviewer entry reaches a row.
- **Refutation did not run,** and no audit agent was used this round.
