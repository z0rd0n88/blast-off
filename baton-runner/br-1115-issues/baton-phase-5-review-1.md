---
source: runner
scope: br-1115-issues
parent_session: ""
---
# Pass-Baton: phase 5 review round 1 (issue 39), VERDICT CLEAN, 0 CRITICAL, 0 HIGH, 7 MEDIUM, 24 LOW

**Date:** 2026-11-17
**Scope:** br-1115-issues
**Branch:** feat/br-1115-issues/phase-5
**Worktree:** /home/alex/blast-off/.claude/worktrees/pending-items-53932d
**HEAD:** dcee737 feat(chain): child-count follow-ups from #22 (#39)

## Where things stand

VERDICT: CLEAN by the contract's rule: gate exit 0, zero CRITICAL or HIGH in the synthesized report, and every issue 39 checkbox with behaviour has a passing test (cited below). CLEAN does not mean nothing to fix: 7 MEDIUM and 24 LOW are open, and they are the manager's to triage. Read P5R1-4 first: it is new in this commit and confirmed. preflight's new `left` arithmetic reads a leading-zero `JOB_MAX_CHILDREN` as octal, so `08` aborts preflight with a bash error and no verdict line, and `010` reports 8 left where `run` allows 10. The work baton's "leading zeros keep their old behaviour" is false for this variable. The fix is one regex in `chain_nums`.

- Gate: `scripts/gate.sh` ran once, alone, before any reviewer: exit 0, `GATE: PASS passed=18 failed=0 shellcheck=ok`. The log holds 18 `PASS NN-` lines for 18 scenario files. No `BLAST_OFF_*` variable was set in the environment, and the tree outside `baton-runner/` was clean at dcee737. Log: `baton-runner/br-1115-issues/gate-phase-5-iter-1/tests-run.log`.
- ExecStart check: it read `ExecStart=/home/alex/blast-off/.worktrees/blast-off-build/bin/blast-off run %f` before the gate, after the gate, after the reviewers, after my probe run, and at the end. It never changed.
- Multi-agent review: ran. Report: `baton-runner/br-1115-issues/review-phase-5-iter-1.md`. All 6 of 6 reviewers returned. Reviewer outputs: `baton-runner/br-1115-issues/review-phase-5-iter-1/<reviewer>.md`. Deviations, all in the report's `## Notes`:
  - The review ran inline from this unit, `--high-cap off`.
  - The six reviewers are parked agents, so each ran as a `general-purpose` agent reading its parked definition read-only.
  - Reviewers were held to static work only (print-only `bash -c` one-liners at most). I ran their claims myself afterwards, one scenario run on a `git archive` copy.
  - No synthesizer or auditor agent: I deduplicated and wrote the report myself, so it has no Report Audit section.
- Reviewer side effects: none. After the reviewers returned, `git status` outside `baton-runner/` was empty, HEAD was still dcee737, and the review dir held exactly the six files.
- New dependencies: none.
- Tracked files: this unit changed none. `STATE.md` and `log.md` untouched. My scratch copy and its kept work dir are deleted.

## Intent check (issue 39)

| Item | Evidence | Test real? |
|---|---|---|
| P4R2-1 base read back | `tests/21-soft-cap.sh:45-52`: soft job, status running, `2 2` at cap 2 launches 3 and 4, exits 6 at `4 2` | Yes: kills MA (`BASE=0`) and `-le`->`-lt` |
| P4R2-2 in-memory BASE | `tests/21-soft-cap.sh:33` re-seeds `2 0` before the resume that must reach `child 3` | Yes: kills MB |
| P4R1-2 refusal in run.log | `tests/10-chain-done.sh:107` (each garbled value), `:110-113` (dangling link) | Yes for run.log; the stderr half is unpinned (P5R1-14) |
| P4R1-3 preflight/status show the count | `tests/60-preflight.sh:57,115,119,123-125`; `tests/11-unit-smoke.sh:42` | Yes for showing it and for refusing a garbled file. The "capped job passes" half stays (P5R1-2, owner Q1); hard-cap and base>0 `left` unpinned (P5R1-1) |
| P4R1-4 / P4-22b README remedy | `README.md:136` | Docs only, as asked |
| P4R1-5 missing/dangling; count logged | `tests/10-chain-done.sh:76,85`, `:110-113` | Yes (RED on old code) |
| P4R1-7 save before launch, SIGKILL | `tests/10-chain-done.sh:156-166` | Yes: kills MT and MT2; save-after-launch survives (P5R1-17) |
| P4R2-9 digit bound | `tests/21-soft-cap.sh:86` | Yes from above; `{1,8}` survives (P5R1-16) |
| P4R2-10 pid guard | `tests/11-unit-smoke.sh:63` | Yes: kills MG |
| Rulings P4R2-4, P4R2-11 | spec, README, `lib/chain.sh` comments, test 21 header; `tests/10-chain-done.sh:97` | Docs; `:97` documents existing behaviour by design |

preflight's `left` vs `chain_run`'s cap test: all six reviewers find it matches for a soft `paused-cap` job, a hard job with base > 0, a hard job at `paused-cap` and `JOB_MAX_CHILDREN=0`. I confirmed the hard cases (probe B). Exceptions: leading zeros (P5R1-4) and done/blocked/paused-limit jobs (P5R1-11).

Probes ran as a scratch scenario (`tests/99-probe.sh`, test 60's fixture header) on a `git archive dcee737` copy, once, through `BLAST_OFF_TEST_ONLY=99-probe tests/run`, ending `GATE-ONLY: PASS passed=1 failed=0 shellcheck=ok only=99-probe`:

- A (P5R1-4): no Phase plan. `JOB_MAX_CHILDREN=08`: rc 1, `preflight.sh: line 32: 08: value too great for base (error token is "08")`, no `child-count`, `ok` or `refused` line. `010`: `child-count: none, a fresh job; first child 1; 8 left under cap 010`, `preflight: ok`. `10`: `10 left under cap 10`.
- B (preflight vs run): no plan, `5 5`, default cap 12: `child-count: 5 launched, base 5; next child 6; 7 left under cap 12`. The same at `status: paused-cap`: `7 left`. Matches `run` (no fresh allotment under the hard cap).
- C (P5R1-5): `child-count` holding `x` then `2099-01-01T00:00:00Z job done`. `run` exits 1, and run.log's second line reads `2099-01-01T00:00:00Z job done', not '<launched> <base>' ...`: a forged timestamped line.

No mutants run by this unit: the reviewers' surviving mutants (P5R1-1, -13 to -17) are by reading.

## Findings

Severity is the report's: the highest any reviewer filed. "Confirmed" means I ran it.

| ID | Sev | Where | One line |
|---|---|---|---|
| P5R1-1 | MEDIUM | `lib/preflight.sh:31-32`; `tests/60-preflight.sh` | `left` untested under the hard cap and for base>0; `b=0` and `(CAP_SOFT ? b : 0)`->`b` survive |
| P5R1-2 | MEDIUM | `lib/preflight.sh:30-36` | a job at its cap still gets `preflight: ok` (half of P4R1-3; owner Q1) |
| P5R1-3 | MEDIUM | `lib/units.sh:28-32,54-68` | `start`/`resume` launch a unit the runner refuses at once; resume also stops the timer |
| P5R1-4 | MEDIUM | `lib/preflight.sh:32`; `lib/chain.sh:91` | leading-zero `JOB_MAX_CHILDREN` read as octal in preflight: `08` aborts, `010` says 8 left. Confirmed |
| P5R1-5 | MEDIUM | `lib/chain.sh:123-125,142` | raw, unbounded, unescaped file content in the refusal reaches run.log/status/preflight; forges log lines. Confirmed |
| P5R1-6 | MEDIUM | `lib/chain.sh:88-93,134-140` | other pre-lock refusals (`chain_nums` etc.) still stderr only; P4R2-9 adds a way in; no `blast-off:` prefix |
| P5R1-7 | MEDIUM | `lib/chain.sh:204` | a child deleting/rewriting `child-count` in a run's last child resets the hard cap at the next relaunch |
| P5R1-8 | LOW | `lib/chain.sh:142` vs `:151` | refusal logged before the lock lands in a live runner's run.log and hides "lock held" |
| P5R1-9 | LOW | `tests/50-checkpoint-size.sh:37` | loose `grep 'child 2' | head -1` would match the new line on a non-fresh job (latent) |
| P5R1-10 | LOW | `lib/chain.sh:160,171` | soft paused-cap resume logs the old base; the moved base is never logged |
| P5R1-11 | LOW | `lib/preflight.sh:30-33` | `N left` shown for done/blocked/paused-limit jobs that launch nothing |
| P5R1-12 | LOW | `lib/chain.sh:122-123` | FIFO/device/huge `child-count` now hangs status and preflight too |
| P5R1-13 | LOW | `lib/units.sh:74` | status's garbled branch untested |
| P5R1-14 | LOW | `lib/chain.sh:123,142`; `tests/10-chain-done.sh:103-117` | stderr half, cat's reason, zero-byte run.log check, dir/unreadable cases unpinned |
| P5R1-15 | LOW | `tests/60-preflight.sh:118-119` | p8 exit code unchecked; the `left > 0` clamp unpinned |
| P5R1-16 | LOW | `lib/chain.sh:91` | 9-digit bound tested from above only (`{1,8}` survives) |
| P5R1-17 | LOW | `lib/chain.sh:204-205` | save moved to just after `child_launch` survives |
| P5R1-18 | LOW | `tests/10-chain-done.sh:156-166` | SIGKILL case does not assert the dead runner's leftovers are cleaned |
| P5R1-19 | LOW | `lib/preflight.sh:31` | `[ -z "$CAP_SOFT" ] ||` redundant with the ternary |
| P5R1-20 | LOW | `docs/spec.md:229,51` | "a JOB_CAP_FACTOR of 10" and "no children left" read wrongly |
| P5R1-21 | LOW | `README.md:136`; `docs/spec.md:61` | "the one reset" ignores rewriting to a smaller count; "deliberate" dropped |
| P5R1-22 | LOW | `lib/chain.sh:195`; `README.md:136` | exit-4 message vs README remedy; remedy omits receipts/PR cells; no end-to-end scenario |
| P5R1-23 | LOW | `bin/blast-off:9,12`; spec run row; test 60 header | doc drift: count line and refusal not mentioned |
| P5R1-24 | LOW | `lib/chain.sh:123` | "cannot read" refusal gives no remedy |
| P5R1-25 | LOW | `lib/chain.sh:121-122,160` | missing file with run.log history is still an effective silent reset (ruling allows; warn?) |
| P5R1-26 | LOW | `lib/chain.sh:131` | pre-existing: symlink to a real file replaced by a plain file, undocumented |
| P5R1-27 | LOW | `lib/chain.sh:142,151` | pre-existing: count read before the lock (stale-count race) |
| P5R1-28 | LOW | `tests/21-soft-cap.sh:39` | carried over: P4R2-3 resume-log grep still satisfied by the cap-0 run |
| P5R1-29 | LOW | `lib/chain.sh` | pre-existing: run.log / `child-count.tmp` opened through child-plantable symlinks |
| P5R1-30 | LOW | `lib/preflight.sh:31` | `local b` re-declares the deps loop variable; harmless today (mine) |
| P5R1-31 | LOW | `tests/10-chain-done.sh:97` | P4R2-4 assertion passes on old code by design (informational) |

## Open owner questions

Q1 preflight refuse at `0 left`? Q2 `start`/`resume` pre-check the count and `JOB_*` values? Q3 reject leading zeros or force base 10? Q4 is a hand or child rewrite of `child-count` an allowed reset; re-save after each child? Q5 refuse a symlink to a regular file, and may the refusal echo content? Q6 move the count refusal after `chain_lock`? Q7 status omits `left` on purpose (work unit: yes)? Detail in the report's `## Open Questions for the Owner`.

## Next step for the manager

Triage the 7 MEDIUMs. Smallest fixes with the most value: P5R1-4 (one regex in `chain_nums`, plus a `JOB_MAX_CHILDREN=08` case in test 21's bad-number loop or test 60), P5R1-1 (two preflight cases in test 60), P5R1-5 (bound and escape the echoed content). P5R1-2, -3, -6, -7 wait on owner answers Q1, Q2, Q4.
