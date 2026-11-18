# Multi-Agent Review: commit dcee737 (phase 5, issue 39): lib/chain.sh + lib/preflight.sh + lib/units.sh + tests/10-chain-done.sh + tests/11-unit-smoke.sh + tests/21-soft-cap.sh + tests/60-preflight.sh + docs/spec.md + README.md (base c4e2a41)

## Executive Summary

Six reviewers (critical-thinking, code-reviewer, penetration-tester, security-reviewer, silent-failure-hunter, tdd-guide) reviewed commit dcee737, the issue 39 follow-ups to issue 22's `child-count`, by static work only. No reviewer filed a CRITICAL or HIGH. After dedupe there are **0 CRITICAL, 0 HIGH, 7 MEDIUM and 24 LOW**. Severity is the highest any reviewer filed. These are raw reviewer findings: no refutation round ran. Where I (the review unit) reproduced a claim, the row says "Confirmed".

**Issue 39.** All six reviewers find every item done in code or docs, and the three owner rulings (P4-22a, P4R2-11, P4R2-4) worded as ordered with no contradiction. Each behaviour item has a test that kills its main mutant (checklist below). P4R1-3 is the one item five reviewers call "partly" done: preflight and status now show the count, and a garbled file refuses, but a job at its cap still gets `preflight: ok` (the work unit's recorded decision; owner question Q1).

**preflight's `left` vs `chain_run`'s cap test.** All six agree it matches for a soft `paused-cap` job (fresh allotment, `MAXC`), a hard-cap job with base > 0 (`5 5` at cap 12 gives 7, base ignored), a hard-cap job at `paused-cap` (no fresh allotment) and `JOB_MAX_CHILDREN=0`. I confirmed the hard `5 5` case and the hard `5 5` + `paused-cap` case (both `7 left under cap 12`). Two exceptions: a leading-zero `JOB_MAX_CHILDREN` (P5R1-4, confirmed) and done / blocked / paused-limit jobs, where the run launches nothing (P5R1-11).

**Blast radius.** No existing scenario matches the new run.log line `child-count: ...; next child N` today. Every other `child N` grep is followed by `launched`, `usage`, `timed out` and the like, or is anchored, and `grep -c 'child [0-9]* launched'` does not match `child-count:`. The one loose grep is `tests/50-checkpoint-size.sh:37` (P5R1-9), latent only. `resume` and `start` do not call `chain_count`; only `run`, `status` and `preflight` do (critical-thinking).

**The seven MEDIUMs:**

- P5R1-1: preflight's `left` is unpinned under the hard cap and for base > 0; two mutants survive.
- P5R1-2: a job at its cap still passes preflight (half of P4R1-3).
- P5R1-3: `start`/`resume` still launch a unit that the runner refuses at once (garbled count).
- P5R1-4: preflight's new arithmetic reads a leading-zero `JOB_MAX_CHILDREN` as octal: `08` aborts preflight with no verdict line, `010` prints 8 left where `run` allows 10. Confirmed.
- P5R1-5: the refusal copies the raw `child-count` content (through any symlink, unbounded, unescaped) into run.log, status and preflight; a multi-line file forges timestamped run.log lines. Confirmed.
- P5R1-6: P4R1-2 is fixed for the count only; `chain_nums` (now stricter after P4R2-9) and the other pre-lock refusals still reach only the journal under `start` or the resume timer.
- P5R1-7: a child that deletes or rewrites `child-count` during the last child of a run resets the hard cap at the next relaunch (possibly the resume timer); the new log line records it but does not stop it.
**Recommended action: merge-with-fixes, or merge with owner rulings.** None of the MEDIUMs breaks an issue 39 checkbox. P5R1-4 is a one-regex fix (`^(0|[1-9][0-9]{0,8})$` in `chain_nums`) on arithmetic this commit introduced. P5R1-1 is two assertions in test 60. The rest are owner questions or pre-existing.

## Critical Findings

None.

## High Findings

None.

## Medium Findings

| ID | Where | Failure path | Suggested fix | Filed by |
|---|---|---|---|---|
| P5R1-1 | `lib/preflight.sh:31-32`; `tests/60-preflight.sh:57,115,119` | Every `left` assertion is under the soft cap with base 0. Mutants that survive: `local b="$BASE"` -> `local b=0` (a soft running `4 2` job at cap 2 would show 0 left where `run` launches 2), and `(CAP_SOFT ? b : 0)` -> `b` (a hard `5 5` job at cap 12 would show 12 left, not 7). | Add a hard `5 5` case (want `7 left under cap 12`, also at `paused-cap`) and a soft running `4 2` case | critical-thinking M1, silent-failure-hunter MEDIUM-3, tdd-guide MEDIUM; code-reviewer L1, security-reviewer L4, penetration-tester PT5-7 (LOW) |
| P5R1-2 | `lib/preflight.sh:30-36,46`; `tests/60-preflight.sh:112-115` | A job at its cap prints `0 left under cap M` and still `preflight: ok`; `start` then exits 4 or 6 at once with no child. Test 60 now pins that pass. This is the issue's "a ... capped job passes preflight and exits at once", left as display only by the work unit's decision. | Owner ruling (Q1): refuse at `0 left`, at least under the hard cap, or keep display only and say so in the spec | critical-thinking M2, code-reviewer M2, silent-failure-hunter MEDIUM-2, tdd-guide MEDIUM; security-reviewer L4, penetration-tester PT5-12 (LOW) |
| P5R1-3 | `lib/units.sh:28-32` (`unit_check`), `:54-68`; refusal at `lib/chain.sh:142` | `start` and `resume` do not read `child-count`, so for a garbled file `start` exits 0 and the unit dies at once (exit 1, reason in run.log since this commit); `resume` then stops the pending resume timer. | Owner ruling (Q2): have `start`/`resume` run `chain_count` (and `chain_nums`) before `systemd-run` | silent-failure-hunter MEDIUM-1, critical-thinking M2 (part) |
| P5R1-4 | `lib/preflight.sh:32`; `lib/chain.sh:91` (`chain_nums` accepts `0[0-9]+`); compare `lib/chain.sh:194` (`[ -gt ]`, decimal) | `$((MAXC - LAUNCHED ...))` is new arithmetic on `MAXC`. **Confirmed** (probe A, archive copy): `JOB_MAX_CHILDREN=08 preflight` exits 1 with `preflight.sh: line 32: 08: value too great for base`, and no `child-count`, `preflight: ok` or `preflight: refused` line; `010` prints `8 left under cap 010` and `preflight: ok`, while `run`'s `[ -gt ]` reads 10. The work baton's "leading zeros keep their old behaviour" is false for this variable. | `^(0|[1-9][0-9]{0,8})$` in `chain_nums` (also ends the old `JOB_CAP_FACTOR=08` octal case), or `10#` at each arithmetic use | code-reviewer M1, security-reviewer M2, penetration-tester PT5-1 (MEDIUM); silent-failure-hunter LOW-4, tdd-guide LOW; critical-thinking L17 (leading zeros, carried over) |
| P5R1-5 | `lib/chain.sh:123-125,142`; `lib/preflight.sh:35`; `lib/units.sh:74` | `COUNT_ERR` embeds the file's whole content, read through any symlink, unbounded and unescaped. It now reaches run.log (new in this commit), status and preflight stdout, and the preflight `refused:` line. **Confirmed** (probe C): a `child-count` of `x\n2099-01-01T00:00:00Z job done` writes a run.log line that reads `2099-01-01T00:00:00Z job done`. security-reviewer: a link to a secrets file puts the secret in run.log, which removes the premise that kept phase 4's P4R1-16 LOW ("It cannot reach run.log"). | Name only the shape, or `head -c 64 | tr -c '[:print:]' '?'` (the `lib/usage.sh:33` pattern) | security-reviewer M1 (MEDIUM); critical-thinking L5, code-reviewer L6, silent-failure-hunter LOW-2, penetration-tester PT5-3 (LOW) |
| P5R1-6 | `lib/chain.sh:88-93,134-140`; `lib/units.sh:28-32` | P4R1-2's reasoning applies to every refusal before the lock: `chain_nums`, `CLAUDE_FLAGS`, missing deps, brief or checkpoint still go to stderr only. P4R2-9's 9-digit bound adds a new way in: `start` with a 10-digit `JOB_MAX_CHILDREN` reports success, the unit fails, and run.log's last line is the previous run's. The count refusal also lacks the `blast-off:` prefix the other exit-1 messages carry. | `log` each pre-lock `die`, or validate in `unit_check` | critical-thinking M3, silent-failure-hunter MEDIUM-4 (MEDIUM); code-reviewer L14, penetration-tester PT5-10 (LOW); prefix: critical-thinking L15, tdd-guide |
| P5R1-7 | `lib/chain.sh:204` (only save point), `:121-122` | `child-count` is saved only before a launch. If the last child of a run deletes it or writes a smaller valid count (`0 0`), the next relaunch, which can be the resume timer with no owner present, starts from that count and resets the hard cap. The new `child-count:` line records the reset after the fact. Phase 4 filed the child-writes-the-file route as P4R1-12 (LOW). | Re-save (`chain_count_set`) after each child, or keep the runner's copy outside the job dir; owner question Q4 | penetration-tester PT5-2 (MEDIUM) |

## Medium/Low Findings (LOW)

| ID | Sev | Where | Finding | Filed by |
|---|---|---|---|---|
| P5R1-8 | LOW | `lib/chain.sh:142` vs `:151`; `docs/spec.md:49` | The count refusal is logged before `chain_lock` and the EXIT trap. Beside a live runner it lands in that runner's run.log with no `runner exit` line and no "refused" marker, and the second process reports "garbled" instead of "lock held"; the live runner then overwrites the file at its next save. The spec's `run` row order no longer matches. critical-thinking judges it acceptable: `LOG` is always set, a missing job dir dies earlier in `job_init`. | code-reviewer L2, security-reviewer L2, silent-failure-hunter LOW-5, tdd-guide, penetration-tester PT5-5 |
| P5R1-9 | LOW | `tests/50-checkpoint-size.sh:37` | `grep -n 'child 2' run.log | head -n 1` would match `child-count: 1 launched, base 0; next child 2` on a non-fresh job and fail falsely (not pass falsely). Today's `grow` job is fresh, so it passes. | all six |
| P5R1-10 | LOW | `lib/chain.sh:160` vs `:171` | On a soft paused-cap resume the logged starting count shows the old `base`; the moved base is never logged. | critical-thinking L6, code-reviewer L3, silent-failure-hunter LOW-1, tdd-guide |
| P5R1-11 | LOW | `lib/preflight.sh:30-33`; `lib/units.sh:74`; spec preflight row | preflight's `N left` (and status's `next child N`) for a done, blocked or still-paused-limit job, where the run launches nothing; the spec says "what the next run may launch". | code-reviewer L12, security-reviewer L3, silent-failure-hunter LOW-11, tdd-guide, penetration-tester PT5-12 |
| P5R1-12 | LOW | `lib/chain.sh:122-123` | A FIFO, a device symlink (`/dev/zero`) or a huge file at `child-count` blocks or grows memory in `cat`; `run` already did (P4R1-15), now `status` and `preflight` do too. | critical-thinking L4, code-reviewer L5, security-reviewer L1, silent-failure-hunter LOW-3, tdd-guide, penetration-tester PT5-4 |
| P5R1-13 | LOW | `lib/units.sh:74` | status's garbled branch is untested: `chain_count; echo "$COUNT_SAY"` (exits 1 under set -e) or a branch printing "none, a fresh job" survives. | critical-thinking L2, code-reviewer L10, silent-failure-hunter LOW-8, tdd-guide, penetration-tester PT5-8 |
| P5R1-14 | LOW | `lib/chain.sh:123,142`; `tests/10-chain-done.sh:103-117` | Refusal pinning gaps: dropping `>&2` survives (tests capture `2>&1`); dropping `2>&1` from `cat` (the dangling-link reason) survives; the zero-byte case does not check run.log; no directory or unreadable-file case. | critical-thinking L1, silent-failure-hunter LOW-7, tdd-guide (2), security-reviewer L6, penetration-tester PT5-9 |
| P5R1-15 | LOW | `tests/60-preflight.sh:118-119`; `lib/preflight.sh:33` | The p8 (`paused-cap`) run never checks its exit code; the `left > 0` clamp is unpinned (`$left` survives). | critical-thinking L16, code-reviewer L1, silent-failure-hunter LOW-9, tdd-guide (2), security-reviewer L4 |
| P5R1-16 | LOW | `lib/chain.sh:91`; `tests/21-soft-cap.sh:86` | The 9-digit bound is tested from above only: `{1,8}` (or `{1,4}`) survives. The writer could in principle produce a 10-digit count the reader refuses (not reachable in practice). | critical-thinking L3, tdd-guide, penetration-tester PT5-13 |
| P5R1-17 | LOW | `lib/chain.sh:204-205` | Moving the save to just after `child_launch` (before `child_wait`) survives the SIGKILL test; the window is up to the ~60 s trust scrape. | tdd-guide, silent-failure-hunter LOW-10, penetration-tester PT5-13 |
| P5R1-18 | LOW | `tests/10-chain-done.sh:156-166` | The SIGKILL case's comment says the re-run clears what the dead runner left, but nothing asserts the hang child, grandchild, tmux server or child dir are gone. | code-reviewer L9, silent-failure-hunter LOW-10, tdd-guide |
| P5R1-19 | LOW | `lib/preflight.sh:31` | `[ -z "$CAP_SOFT" ] ||` is redundant: the ternary on line 32 already ignores `b` under the hard cap (its removal survives). | critical-thinking L8, silent-failure-hunter MEDIUM-3 (mutant) |
| P5R1-20 | LOW | `docs/spec.md:229` (test 21 row); `docs/spec.md:51` (status row) | "a `JOB_CAP_FACTOR` of 10" reads as the value 10, meaning 10 digits; the status row's "no children left" reads as "the job has none left", meaning no `left` figure is shown. | critical-thinking L9, L10, code-reviewer L7, silent-failure-hunter LOW-12, tdd-guide |
| P5R1-21 | LOW | `README.md:136`; `docs/spec.md:61`; `lib/chain.sh:125` | The docs call deleting `child-count` "the one reset", but writing `0 0` or any smaller valid count (which the refusal's "fix it" invites) resets too; the README drops the ruling's word "deliberate". | critical-thinking L11, penetration-tester PT5-11 |
| P5R1-22 | LOW | `lib/chain.sh:195` vs `README.md:136` | The exit-4 message says "a larger JOB_MAX_CHILDREN goes on"; the README remedy is to add a Phase plan. The README remedy also does not warn that Phase plan rows marked done need receipts and PR cells (exit 9 or 10). No scenario walks the remedy end to end (hard cap, add plan, pause, resume). | critical-thinking L12, L13, security-reviewer L7 |
| P5R1-23 | LOW | `bin/blast-off:9,12`; `docs/spec.md:49` (run row); `tests/60-preflight.sh:2-8` | Doc drift: the `--help` status and preflight lines, the spec's `run` row (new count line, refusal before the lock) and test 60's header do not mention the child count. | code-reviewer L8, L11, silent-failure-hunter LOW-12, security-reviewer L7, tdd-guide, penetration-tester PT5-14 |
| P5R1-24 | LOW | `lib/chain.sh:123` | The "cannot read" refusal gives no remedy, unlike the garbled one. | penetration-tester PT5-14 |
| P5R1-25 | LOW | `lib/chain.sh:121-122,160` | A missing `child-count` when run.log already shows launches is still, in effect, a silent reset (allowed by P4R2-11; the new line logs it). Suggests a warning only. | silent-failure-hunter LOW-6 |
| P5R1-26 | LOW | `lib/chain.sh:131` | Pre-existing: a `child-count` symlink to a real file is read, then replaced by a plain file at the next save; undocumented. security-reviewer asks whether it should be refused (Q5). | code-reviewer L13, security-reviewer (question) |
| P5R1-27 | LOW | `lib/chain.sh:142` vs `:151` | Pre-existing (P4R1-17): the count is read before the lock, so a runner taking over a just-released lock can start from a stale count. | critical-thinking L14, silent-failure-hunter LOW-14, tdd-guide |
| P5R1-28 | LOW | `tests/21-soft-cap.sh:39` | Carried over, still open: P4R2-3, the resume-log grep is also satisfied by the cap-0 run's line. | critical-thinking L17, tdd-guide (note) |
| P5R1-29 | LOW | `lib/chain.sh` (run.log, `child-count.tmp` writes) | Pre-existing, recorded only: run.log and `child-count.tmp` are opened through symlinks a child can plant, so a malicious child could make the runner truncate or append to the owner's files (P4R1-14). | penetration-tester PT5-15 |
| P5R1-30 | LOW | `lib/preflight.sh:31` | `local b` re-declares the function's `b` (the deps loop variable); harmless today since `b` is not read after line 16, noted by reading only. | review unit (mine), not a reviewer |
| P5R1-31 | LOW | `tests/10-chain-done.sh:97` | The P4R2-4 assertion (`status: running` after exit 4 from paused-cap) passes on old code by design: it documents existing behaviour, as the work baton says. Informational. | tdd-guide (checklist note) |

## Issue 39 checklist (consensus; tests cited from tdd-guide and checked against the diff)

| Item | Done? | Pinning test | Mutant killed |
|---|---|---|---|
| P4R2-1 base read back | Yes | `tests/21-soft-cap.sh:45-52` (`2 2` running at cap 2: children 3, 4, `4 2`, exit 6) | MA `BASE=0` (work baton RED); also `-le`->`-lt` |
| P4R2-2 in-memory BASE at resume | Yes | `tests/21-soft-cap.sh:33,37-43` (re-seed `2 0`) | MB (file-only save) |
| P4R1-2 refusal in run.log | Yes | `tests/10-chain-done.sh:107` (loop), `:110-113` (link) | probe 90-red-runlog on old code; stderr half unpinned (P5R1-14) |
| P4R1-3 preflight/status show the count | Partly | `tests/60-preflight.sh:57,115,119,123-125`; `tests/11-unit-smoke.sh:42` | 60/11 RED on old code; capped job still passes (P5R1-2); hard/base>0 unpinned (P5R1-1) |
| P4R1-4 / P4-22b README exit-4 remedy | Yes (docs only) | none (doc wording) | n/a |
| P4R1-5 missing/dangling; count logged | Yes | `tests/10-chain-done.sh:76,85` (count lines), `:110-113` (dangling link) | 10 RED on old code; probe 91-red-link |
| P4R1-7 save before launch, no EXIT trap | Yes | `tests/10-chain-done.sh:156-166` (SIGKILL; `1 0` while child 1 runs) | MT, MT2; save-after-launch survives (P5R1-17) |
| P4R2-9 digit bound | Yes | `tests/21-soft-cap.sh:86` | 21 RED on old code; `{1,8}` survives (P5R1-16) |
| P4R2-10 start_hang pid guard | Yes | `tests/11-unit-smoke.sh:63` | MG |
| Ruling P4R2-4 (docs) | Yes | `tests/10-chain-done.sh:97` (documents existing behaviour) | n/a by design |
| Ruling P4R2-11 (docs) | Yes | docs only | n/a |
| Ruling P4-22a (unchanged) | Held | `tests/10-chain-done.sh:93-96`; `tests/21-soft-cap.sh` | preflight's hard twin unpinned (P5R1-1) |

All cited scenarios passed in the gate (`GATE: PASS passed=18 failed=0 shellcheck=ok`, exit 0).

## Open Questions for the Owner

- Q1 (P5R1-2): should `preflight` refuse at `0 left`, at least under the hard cap, or stay display only? (critical-thinking, code-reviewer, security-reviewer, tdd-guide, penetration-tester)
- Q2 (P5R1-3, P5R1-6): should `start` and `resume` refuse a garbled count or an out-of-range `JOB_*` value before `systemd-run`? (critical-thinking, silent-failure-hunter)
- Q3 (P5R1-4): reject leading zeros in every `JOB_*` number, or force base 10 at each arithmetic use? (code-reviewer, tdd-guide, penetration-tester)
- Q4 (P5R1-7, P5R1-21): is rewriting `child-count` by hand (or by a child) an allowed reset, or only deleting it? Should the runner re-save after each child or keep its own copy outside the job dir? (critical-thinking, penetration-tester)
- Q5 (P5R1-5, P5R1-26): should a `child-count` symlink to a regular file be refused, and may a refusal echo the file's content? This also settles P4R1-16. (security-reviewer)
- Q6 (P5R1-8): should the count refusal move after `chain_lock`? (code-reviewer, security-reviewer)
- Q7: is it deliberate that `status` omits `left` while `preflight` shows it? (critical-thinking; the work unit's decision says yes: status runs in the caller's environment, not the unit's)

## Notes

- The review ran inline from this unit, `--high-cap off`. The six reviewers are parked agents, so each ran as a `general-purpose` agent that read its definition from `~/.claude/agents-parked/<name>.md` read-only. They were held to static work only; some ran print-only `bash -c` arithmetic or regex one-liners. Outputs: `baton-runner/br-1115-issues/review-phase-5-iter-1/<reviewer>.md`, six files.
- No synthesizer or auditor agent: I deduplicated and wrote this report myself, so there is no Report Audit section. Severity is the highest any reviewer filed; attribution lists each reviewer's own ID where it had one.
- P5R1-30 is mine, not a reviewer's. P5R1-31 is informational.
- Reproductions, one run on a `git archive dcee737` copy with a scratch `tests/99-probe.sh` (test 60's fixture header), `BLAST_OFF_TEST_ONLY=99-probe tests/run`, ending `GATE-ONLY: PASS passed=1 failed=0 shellcheck=ok only=99-probe`: A (leading zeros; P5R1-4), B (hard `5 5`, also at `paused-cap`: `7 left under cap 12`, matching `run`), C (multi-line garbled content forges a run.log line; P5R1-5). The copy and its kept work dir were deleted afterwards.
- Reviewer side effects: none. After the reviewers returned, `git status` outside `baton-runner/` was empty, HEAD was still dcee737, and the review dir held exactly the six files.
