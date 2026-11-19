---
source: runner
scope: br-1115-issues
parent_session: ""
---
# Pass-Baton: phase 5 review round 2 (issue 39, narrow), VERDICT CLEAN: 0 CRITICAL, 0 HIGH, 0 MEDIUM, 17 LOW

**Date:** 2026-11-17
**Scope:** br-1115-issues
**Branch:** feat/br-1115-issues/phase-5
**Worktree:** /home/alex/blast-off/.claude/worktrees/pending-items-53932d
**HEAD:** d059301 fix(chain): refuse leading-zero JOB_* numbers; refusals never echo child-count (#39)

## Where things stand

VERDICT: CLEAN, by the contract's rule. The gate exited 0, the report has no CRITICAL or HIGH finding, and every issue 39 checkbox with behaviour has a passing test (cited in the report's checklist). CLEAN does not mean there is nothing to fix: 17 LOW are open, and the manager triages them.

Both reviewers find P5R1-1, -4, -5 and -9 closed. No path in `lib/` or `bin/` puts `child-count` content into run.log, status, preflight or the journal, and every arithmetic use of a JOB_* value comes after `chain_nums`. Nothing in the repo passes a leading-zero JOB_* value except the new negative tests.

Read P5R2-1 first. It is the one thing this fix made worse: a leading-zero JOB_* the old runner accepted is now refused, and under `start` or the resume timer only the journal shows why (round-1 P5R1-6, owner Q2).

- **Gate.** `scripts/gate.sh` ran once, alone, before any reviewer. It exited 0, and the last line was `GATE: PASS passed=18 failed=0 shellcheck=ok`. Log: `baton-runner/br-1115-issues/gate-phase-5-iter-2/tests-run.log`.
- **ExecStart.** It read `ExecStart=/home/alex/blast-off/.worktrees/blast-off-build/bin/blast-off run %f` before the gate, after the gate, after the reviewers and at the end. It never changed.
- **Review.** Two reviewers, code-reviewer and security-reviewer. Each is parked, so each ran as a `general-purpose` agent that read its parked definition read-only. Both were held to static work only and both returned (2/2). Report: `baton-runner/br-1115-issues/review-phase-5-iter-2.md`. Outputs: `baton-runner/br-1115-issues/review-phase-5-iter-2/{code-reviewer,security-reviewer}.md`. No refutation and no audit agent ran.
- **My checks.** By grep and reading only; no scenario or mutant run besides the gate. Confirmed P5R2-3, -4, -5, -6 (the § placement) and -7.
- **Side effects.** After the reviewers, `git status` outside `baton-runner/` was empty and HEAD was still d059301. This unit changed no tracked file and made no git operation. It did not touch `STATE.md` or `log.md`. Scratch files only under the session scratchpad.
- **New dependencies.** None.

## Findings

Every finding, unfiltered. The full rows are in the report.

| ID | Sev | Title | Location |
|---|---|---|---|
| P5R2-1 | LOW | Fix makes P5R1-6 a little worse: a leading-zero JOB_* is now refused, and under `start`/resume timer only the journal says why; a paused job could stop resuming | `lib/chain.sh:146`; `lib/units.sh:28-32` |
| P5R2-2 | LOW | "Never show the content" is pinned by one word (`job done`); echoing only the first line, or a one-line file, passes | `tests/10-chain-done.sh:125`; `tests/60-preflight.sh:143` |
| P5R2-3 | LOW | Test 60's leading-zero case does not pin "before any other line" | `tests/60-preflight.sh:146-150` |
| P5R2-4 | LOW | The new cannot-read refusal wording is untested; reverting to `cat 2>&1` passes. Confirmed | `lib/chain.sh:127-129` |
| P5R2-5 | LOW | No test refuses a leading-zero `JOB_RESUME_MARGIN` or a bad `JOB_API_BACKOFF`. Confirmed | `lib/chain.sh:91`; `tests/21-soft-cap.sh:86` |
| P5R2-6 | LOW | Spec "exit 1 above" points to a table that is below (§3); the "byte size and shape" promise does not cover the cannot-read branch, whose cause list is incomplete | `docs/spec.md:56,61`; `lib/chain.sh:121` |
| P5R2-7 | LOW | Test 60's header says every line is printed on exit 1; false for a bad JOB_* count. Confirmed | `tests/60-preflight.sh:7-8` |
| P5R2-8 | LOW | README and `--help` do not mention the no-leading-zero rule or the early refusal | `README.md`; `bin/blast-off` |
| P5R2-9 | LOW | `NUMS_ERR` prints the raw value; a newline can put a bare `preflight: ok` line on stdout (exit stays 1) | `lib/chain.sh:93`; `lib/preflight.sh:15` |
| P5R2-10 | LOW | The byte size follows a symlink and shows the target's length; within Q5, informational | `lib/chain.sh:131` |
| P5R2-11 | LOW | The byte size is a second read: 0 for `/proc`, racy against a swap, `( bytes;` if stat fails | `lib/chain.sh:131` |
| P5R2-12 | LOW | Owner-enabled xtrace still prints the content; informational | `lib/chain.sh:127-130` |
| P5R2-13 | LOW | Pre-existing: run.log is still forgeable by other child-written text (last message, non-JSON Stop payload) | `lib/chain.sh` |
| P5R2-14 | LOW | Pre-existing: `JOB_JEV` unvalidated; `00`/`false` turn Jev on | `lib/` (`JOB_JEV`) |
| P5R2-15 | LOW | Pre-existing: numeric `BLAST_OFF_*` settings unvalidated; a garbled `BLAST_OFF_TRUST_SECONDS` hangs each child | `lib/` |
| P5R2-16 | LOW | Pre-existing, unverified: `JOB_BASE` with a leading `-` reaches `git fetch` as an option | `git fetch origin "$JOB_BASE"` call sites |
| P5R2-17 | LOW | `1 0` plus a NUL byte is accepted (bash drops the NUL); no leak, informational | `lib/chain.sh:127` |

## Open questions for the owner

- Q2 (still open, sharpened by P5R2-1): route a bad JOB_* refusal to run.log, or refuse it in `start`/`resume` before `systemd-run`?
- Q8 (P5R2-14, -15): does Q3 extend to `JOB_JEV` and the numeric `BLAST_OFF_*` settings?
- Q9 (P5R2-9): escape or truncate the value in `NUMS_ERR`?
- Q10 (P5R2-16): guard `JOB_BASE` against a leading `-`?

## Next steps

1. Manager: triage the 17 LOW. The cheap ones are tests and doc lines: P5R2-2, -3, -4, -5, -6, -7, -8.
2. Owner: Q2, Q8, Q9, Q10.

## References

- Report: `baton-runner/br-1115-issues/review-phase-5-iter-2.md`
- Reviewer outputs: `baton-runner/br-1115-issues/review-phase-5-iter-2/`
- Gate log: `baton-runner/br-1115-issues/gate-phase-5-iter-2/tests-run.log`
- Round 1: `baton-runner/br-1115-issues/review-phase-5-iter-1.md`, `baton-phase-5-fix-1.md`
