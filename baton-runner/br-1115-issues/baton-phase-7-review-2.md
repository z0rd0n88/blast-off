---
source: runner
scope: br-1115-issues
parent_session: ""
---
# Pass-Baton: phase 7 review round 2 (narrow, issue 27), VERDICT CLEAN, 0 CRITICAL, 0 HIGH, 1 MEDIUM, 16 LOW

**Date:** 2026-11-19
**Scope:** br-1115-issues
**Branch:** feat/br-1115-issues/phase-7
**Worktree:** /home/alex/blast-off/.claude/worktrees/pending-items-53932d
**HEAD:** a48a93f (fixes under review: 096062b fix(jev): phase 7 review round 1 findings (#27))

## Where things stand

VERDICT: CLEAN. The gate passes, and no lens raised a CRITICAL or HIGH. I found none.

- Round 1 closure: 21 closed, 4 partly closed (P7R1-4, -9, -16, -23), 2 refutations accepted (P7R1-24, -28),
  P7R1-12 needed no edit, 2 deferred by the owner (P7R1-22, -27).
- Every leftover is now a P7R2 finding.
- Read `review-phase-7-iter-2.md` first.

The MEDIUM:
- P7R2-1: under `start`, unit_env drops a key that is not sk-or-, and the runner logs "no OPENROUTER_API_KEY in the
  runner environment", while preflight says "not an sk-or- key". Reproduced. Owner question 1.

What was done:
- Gate: `scripts/gate.sh baton-runner/br-1115-issues/gate-phase-7-iter-2` ran once, alone, before any reviewer.
  - Exit 0, last line `GATE: PASS passed=19 failed=0 shellcheck=ok`. Log: `gate-phase-7-iter-2/tests-run.log`.
  - The brief's command had no `<log-dir>` argument. It exited at gate.sh's usage line before any scenario ran, so I
    re-ran it the way round 1 did.
- ExecStart was `ExecStart=/home/alex/blast-off/.worktrees/blast-off-build/bin/blast-off run %f` before the gate,
  after it, after each reproduction run, and at the end. It never changed.
- Two lenses, code-reviewer and silent-failure-hunter.
  - Each ran as a read-only `general-purpose` agent that read its parked body. They were banned from edits, tests
    and jev.
  - Reports were saved verbatim in `review-phase-7-iter-2/{code-reviewer,silent-failure-hunter}.md`. I deduplicated
    the findings myself.
- Reproduced on a `git archive 096062b` copy, one named scenario per run:
  - One copy-only probe scenario (`98-p7r2probe`) reproduced P7R2-1, -2, -6, -7, -8, -9, -14 and -15.
  - One mutant run of `61-jev-pick` showed the 40-character cut is unpinned (P7R2-11).
  - jq literal checks reproduced P7R2-11 and -12.
- Side effects: none.
  - No tracked file edited and no git operations. STATE.md was already modified by the manager before I started,
    and I did not touch it.
  - No runner unit or timer was created by me, beyond the gate's own scenarios. The real Jev was never called.
  - New untracked files: `gate-phase-7-iter-2/`, `review-phase-7-iter-2/` (2 files), `review-phase-7-iter-2.md`,
    this baton.
  - Scratch dir `p7r2/` deleted.

## What the next unit needs

- The verdict is CLEAN, so per the run plan the next unit is delivery (a draft PR), then a wait for the owner's merge.
- The 17 findings are all MEDIUM or LOW. Whether to fix any before delivery is the manager's call.
- Four owner questions are open in `review-phase-7-iter-2.md`:
  1. The reason under `start` for a non-sk-or- key (P7R2-1).
  2. Whether to validate `JOB_JEV` (P7R2-15; phase 5 Q8).
  3. The jev stderr temp file against spec:68 (P7R2-6).
  4. The wording of brief.md D1 (P7R2-5).
- If a finding-fixer runs, these are the cheapest:
  - P7R2-1(b): one string in jev.sh.
  - P7R2-2: the preflight suffix predicate plus two comments.
  - P7R2-7: `2>/dev/null` on mktemp.
  - P7R2-8: cut and mask `level`.
  - P7R2-9: `rc` in the jev-failed reason.
  - P7R2-11: a confidence over 40 characters.
  - P7R2-4 and P7R2-5: the SKILL.md and D1 wording.
- P7R1-22 and P7R1-27 still need their follow-up issue.
