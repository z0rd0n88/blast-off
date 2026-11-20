---
source: runner
scope: br-1115-issues
parent_session: ""
---
# Pass-Baton: phase 8 review round 2 (narrow, issue 16), VERDICT CLEAN, 0 CRITICAL, 0 HIGH, 1 MEDIUM, 4 LOW

**Date:** 2026-11-19
**Scope:** br-1115-issues
**Branch:** feat/br-1115-issues/phase-8
**Worktree:** /home/alex/blast-off/.claude/worktrees/pending-items-53932d
**HEAD:** f4baca5 fix(templates): denial wording in the child protocol (#16, review round 1)

## Where things stand

VERDICT: CLEAN. Gate passes; no CRITICAL or HIGH. Read `review-phase-8-iter-2.md` first.

- Gate: `scripts/gate.sh baton-runner/br-1115-issues/gate-phase-8-iter-2`, run once, alone. Exit 0, last line `GATE: PASS passed=19 failed=0 shellcheck=ok`.
- ExecStart before and after: `ExecStart=/home/alex/blast-off/.worktrees/blast-off-build/bin/blast-off run %f` (unchanged).
- Round 1: all 9 closed. P8R1-4 is closed for the section, not the step (P8R2-3). P8R1-7 holds only while no owner answers a prompt in a child's window (round 1 owner question 2, still open).
- One probe, on a `git archive HEAD` copy, 51-templates only: both sentences moved from step 9 to step 14 still pass.
- No tracked file touched; nothing committed.

## Findings
- P8R2-1 MEDIUM: "do not ... ask the owner about it" reads against "Record each ... with the question" ("Open or blocked" is how a child asks the owner). Fix: "...so do not stop the job for it or ask the owner about it in chat." and the same string in tests/51-templates.sh:98.
- P8R2-2 LOW: "do not stop the job" is unconditional, two sentences before "Set `status: blocked` only when nothing independent is left". Same fix ("for it").
- P8R2-3 LOW: spec row 51 says "section 9 step 9"; the test checks all of section 9 (probe passed with the text in step 14).
- P8R2-4 LOW: fix hand-back ledger says section 4 Stop condition is lines 69-70; it is 69-71.
- P8R2-5 LOW: "comes from the harness" is false if a child counts a remote refusal (push rejected, gh 403) as a refused tool call. Effect nil; no fix needed.

## Owner questions
1. P8R2-1: may a refused tool call carry a question for the owner under "Open or blocked"? Recommendation: yes, add "in chat".
2. Carried from round 1: "watch only; never answer a prompt in a child's window" in README.md:97 and skills/blast-off/SKILL.md:73. Recommendation: yes, follow-up issue (out of set).

## Next
If the owner takes P8R2-1: one finding-fixer pass (brief.md:173-174, tests/51-templates.sh:98, optionally docs/spec.md:253 for P8R2-3), then a narrow round 3. Otherwise the phase can close clean.
