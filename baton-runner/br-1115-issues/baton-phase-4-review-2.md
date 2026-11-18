---
source: runner
scope: br-1115-issues
parent_session: ""
---
# Pass-Baton: phase 4 review round 2 (issue 22, narrow), VERDICT CLEAN: 0 CRITICAL, 0 HIGH, 2 MEDIUM, 11 LOW

**Date:** 2026-11-17
**Scope:** br-1115-issues
**Branch:** feat/br-1115-issues/phase-4
**Worktree:** /home/alex/blast-off/.claude/worktrees/pending-items-53932d
**HEAD:** 43c5dd8 fix(chain): the hard child cap never resets for a job (#22)

## Where things stand

VERDICT: CLEAN, by the contract's rule. The gate exited 0, the synthesized report has no CRITICAL or HIGH finding, and every acceptance criterion of issue 22 has a passing test (cited below). CLEAN does not mean there is nothing to fix. 2 MEDIUM and 11 LOW are open, and the manager triages them.

Both reviewers find the fix correct. Under the hard cap, `base` is now ignored and never moved, so neither `base` nor a `paused-cap` status can reset it. The soft cap still gets its fresh allotment on a paused-cap resume, per P4-22a. Both MEDIUMs are test gaps, and I reproduced both:

- **P4R2-1.** `BASE=0` on read passes the whole suite.
- **P4R2-2.** The fix's own cap-0 run in test 21 made the re-run read `2 2` from disk. A mutant that writes the file but does not move the in-memory `BASE` now passes. The same mutant failed test 21 before the fix.

Read P4R2-2 first. The fix introduced it, and it closes with one job split.

- **Gate.** `scripts/gate.sh` ran once, alone, before any reviewer. It exited 0, and the last line was `GATE: PASS passed=18 failed=0 shellcheck=ok`. Log: `baton-runner/br-1115-issues/gate-phase-4-iter-2/tests-run.log`.
- **ExecStart.** It read `ExecStart=/home/alex/blast-off/.worktrees/blast-off-build/bin/blast-off run %f` before the gate, after the gate, and after each of my five mutant runs. It never changed.
- **Review.** Two reviewers, code-reviewer and tdd-guide. Each is parked, so each ran as a `general-purpose` agent that read its parked definition read-only. Both were held to static work only and both returned (2/2). Report: `baton-runner/br-1115-issues/review-phase-4-iter-2.md`. Outputs: `baton-runner/br-1115-issues/review-phase-4-iter-2/{code-reviewer,tdd-guide}.md`. No refutation and no audit agent ran.
- **Side effects.** After the reviewers and my runs, `git status` outside `baton-runner/` was empty and HEAD was still 43c5dd8. This unit changed no tracked file and made no git operation. It did not touch `STATE.md` or `log.md`.
- **New dependencies.** None.

## Intent check (issue 22)

| Criterion | Evidence | Test real? |
|---|---|---|
| 1. A cap reached across two runner runs stops the job (exit 4) | `tests/10-chain-done.sh:81-89`: re-runs at cap 1 and cap 2. `:90-93`: a `paused-cap` gives the hard cap no fresh allotment, and the file stays `2 0`. `:108-110`: `5 5` at cap 1 exits 4 with no child. `:142-144`: after SIGHUP, a re-run at cap 1 exits 4 | Yes. M1a is killed at `:93` and M1b at `:110` (fixer's runs; both reviewers agree by reading) |
| 2. Child numbers in run.log continue after a relaunch | `tests/10-chain-done.sh:86-87`; `tests/21-soft-cap.sh:40` | Yes |
| 3. A fresh job starts at child 1 | `tests/10-chain-done.sh:16`, `:77` (and `:124`, tg) | Yes |

## My runs

Each mutant was one scenario on its own `git archive` copy under the scratchpad, run sequentially, never two at once. ExecStart was checked after each one. Script: `$S/mut.sh` (and `mut2.sh`, which takes `REV`), with `S=/tmp/claude-1000/-home-alex-blast-off--claude-worktrees-pending-items-53932d/60b15296-819e-491a-8ffe-34b3bd988f86/scratchpad/p4rev2`.

- **MA** (`lib/chain.sh:123`: `BASE="${BASH_REMATCH[2]}"` -> `BASE=0`). On `10-chain-done`: `GATE-ONLY: PASS passed=1 failed=0 shellcheck=ok only=10-chain-done`. On `21-soft-cap`: `GATE-ONLY: PASS passed=1 failed=0 shellcheck=ok only=21-soft-cap`. Only tests 10, 11, 21, 31 and 51 mention `child-count` or `paused-cap`. Test 11 deletes the file, the `cap` job in 31 is fresh, and 51 only quotes wording. So the mutant survives the suite. **P4R2-1 confirmed.**
- **MB** (`:164`: `{ BASE="$LAUNCHED"; chain_count_set; }` -> `{ echo "$LAUNCHED $LAUNCHED" > "$JOB/child-count"; }`). At 43c5dd8, `21-soft-cap` gave `GATE-ONLY: PASS`. At e766e00, the same edit on line 163 gave `FAIL: re-run after paused-cap exit 6: ... child cap 2 (soft: 2 Phase plan rows x JOB_CAP_FACTOR 1)` and `GATE-ONLY: FAIL passed=0 failed=1`. **P4R2-2 confirmed: the fix weakened test 21.**
- **MC** (`:121` group 1: `{0,8}` -> `{0,17}`). On `10-chain-done`: `GATE-ONLY: PASS`. **P4R2-5 confirmed.**

## Findings

Every finding, unfiltered. The full rows are in the report.

| ID | Sev | Title | Location |
|---|---|---|---|
| P4R2-1 | MEDIUM | Reading `base` back from the file is unpinned; `BASE=0` on read passes the whole suite (rest of P4R1-8). Reproduced | `lib/chain.sh:123`; `tests/21-soft-cap.sh:28-40` |
| P4R2-2 | MEDIUM | The fix weakened test 21: the re-run reads `2 2` from disk, so the in-memory `BASE` move at a resume is unpinned. Reproduced: passes at 43c5dd8, failed at e766e00 | `tests/21-soft-cap.sh:26-35`; `lib/chain.sh:164` |
| P4R2-3 | LOW | The resume-log grep at `21:36` is now also satisfied by the cap-0 run's line (introduced by the fix) | `tests/21-soft-cap.sh:36` |
| P4R2-4 | LOW | Under the hard cap, `paused-cap` becomes `running` and the log says "the chain continues", then exit 4. That contradicts the exit-4 "status unchanged" column, the `chain.sh:97` comment and test 21's header, and it is unpinned. Test 31 relies on the transition | `lib/chain.sh:164-165`; `docs/spec.md:91`; `tests/10-chain-done.sh:90-93` |
| P4R2-5 | LOW | The 9-digit bound is untested at its edge: group 1 `{0,9..17}` or tighter, and group 2 `{0,0}`, survive. Reproduced for `{0,17}` | `lib/chain.sh:121`; `tests/10-chain-done.sh:96` |
| P4R2-6 | LOW | The zero-byte case checks less than the loop: there is no grep for the path, and `! -s` also passes if the file is deleted | `tests/10-chain-done.sh:104-106` |
| P4R2-7 | LOW | Zeroing `base` under the hard cap is unpinned (`basehard` exits before any save) | `lib/chain.sh:152-165`; `tests/10-chain-done.sh:108-110` |
| P4R2-8 | LOW | The comment justifying `step` -> `noop` in the garbled loop gives the wrong reason. Nothing is weakened | `tests/10-chain-done.sh:94-96` |
| P4R2-9 | LOW | `chain_nums` is still unbounded: a 20-digit `JOB_MAX_CHILDREN` makes `-gt` error, so the cap is off for that run (rest of P4R1-6; pre-existing) | `lib/chain.sh:90,186` |
| P4R2-10 | LOW | Test 11 `start_hang` still has no `[ -n "$pid" ]` guard, so without the `rm` the test goes vacuous (rest of P4R1-10) | `tests/11-unit-smoke.sh:58-62` |
| P4R2-11 | LOW | "Never resets for a job" is stronger than the code: the die message says to delete the file, and P4R1-5, -12 and -18 are open reset paths | `docs/spec.md:61`; `lib/chain.sh:185,122` |
| P4R2-12 | LOW | The `cannot read` die is untested (rest of P4R1-11) | `lib/chain.sh:120` |
| P4R2-13 | LOW | At child 1,000,000,000 the count passes the 9-digit bound, and every later run refuses the file. Unreachable in practice | `lib/chain.sh:121,196` |

Round-1 closure:

- **Closed:** P4R1-1, P4R1-9 and P4R1-11.
- **Partly closed:** P4R1-6 (P4R2-9 and P4R2-5 remain), P4R1-8 (P4R2-1 remains, plus the save/`cp_set_status` swap, a crash window, which still survives), and P4R1-10 (P4R2-10 remains).

No open round-1 finding got worse. P4R1-23 is now harmless under the hard cap.

## Next steps

1. Manager: triage P4R2-1 to -13. The cheapest useful fix round:
   - P4R2-2: give test 21's cap-0 check its own job, so the main re-run reads `2 0` again.
   - P4R2-1: add a soft job that starts from `2 2` with status `running` at cap 2 and must launch child 3.
   - P4R2-3: count the resume line.
2. Owner: answer the open questions below.
3. Manager: commit this baton, the report and the reviewer outputs.

## Open questions

- Under the hard cap, should a `paused-cap` status stay `paused-cap` at exit 4, or keep turning into `running`, with the docs reworded? (P4R2-4; cr leans towards rewording the docs because test 31 relies on the transition.) PENDING
- Is deleting `child-count` the one intended reset of a job's hard cap, and should the spec's "never resets for a job" say so? (P4R2-11) PENDING
- Still PENDING from round 1:
  - P4-22b: the README exit-4 remedy needs a second start.
  - Reusing a job dir.
  - Whether the cap must hold against a child that deletes `child-count`.
  - "Launched" vs "attempted".

## References

- Issue: z0rd0n88/blast-off issue 22
- Docs:
  - `baton-runner/br-1115-issues/review-phase-4-iter-2.md`
  - `baton-runner/br-1115-issues/review-phase-4-iter-2/`
  - `baton-runner/br-1115-issues/baton-phase-4-fix-1.md`
  - `baton-runner/br-1115-issues/review-phase-4-iter-1.md`
  - `baton-runner/br-1115-issues/gate-phase-4-iter-2/tests-run.log`
- Code:
  - `lib/chain.sh:121-123` (`chain_count`), `:164` (paused-cap branch), `:186` (cap test)
  - `tests/10-chain-done.sh:90-110`, `tests/21-soft-cap.sh:26-40`
