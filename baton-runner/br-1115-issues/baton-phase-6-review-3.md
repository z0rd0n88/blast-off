---
source: runner
scope: br-1115-issues
parent_session: ""
---
# Pass-Baton: phase 6 review round 3 (issue 14, final allowed round), VERDICT CLEAN: 0 CRITICAL, 0 HIGH, 1 MEDIUM, 13 LOW

**Date:** 2026-11-18
**Scope:** br-1115-issues
**Branch:** feat/br-1115-issues/phase-6
**Worktree:** /home/alex/blast-off/.claude/worktrees/pending-items-53932d
**HEAD:** b917cec fix(chain,units): the runner records the end it accepts in runner-end (#14)

## Where things stand

VERDICT: CLEAN. The gate exited 0, the report has no CRITICAL or HIGH finding, and every issue-14 criterion has a
passing test (table in the report). CLEAN does not mean nothing is left: 1 MEDIUM and 13 LOW are open. This was the
last allowed round, so they go to a follow-up issue.

Both reviewers confirm the rulings in the code:
- `runner-end` is written only after every gate, at `lib/chain.sh:199-200`. No refusal reaches it.
- A failed write aborts under set -e.
- The clear at `:166` comes after the lock.

Read P6R3-1 first. A re-run of an accepted done or blocked job keeps the old file until it passes the lock, so a
`wait` in that startup window reads `final` for a done the new run may refuse. A re-run that dies before the lock
keeps the file for good. The fixer chose the second half; the start race is new to this review.

- **Gate.** `scripts/gate.sh baton-runner/br-1115-issues/gate-phase-6-iter-3` ran once, alone, before any reviewer.
  Exit 0; last line `GATE: PASS passed=19 failed=0 shellcheck=ok`. Log: `gate-phase-6-iter-3/tests-run.log`.
- **ExecStart.** `ExecStart=/home/alex/blast-off/.worktrees/blast-off-build/bin/blast-off run %f` before the gate,
  after it, and at the end. It never changed.
- **Review.** code-reviewer and silent-failure-hunter, each a `general-purpose` agent reading its parked definition
  read-only, static only. Both returned (2/2). Report: `review-phase-6-iter-3.md`. Outputs:
  `review-phase-6-iter-3/{code-reviewer,silent-failure-hunter}.md`.
- **My checks.**
  - A probe: `mv -f` onto a directory named `runner-end` returns 0 and moves the tmp inside, and `cut` then fails
    (P6R3-3). The probe dir is deleted.
  - A grep: `tests/23-runner-lock.sh` never mentions `runner-end` (P6R3-5).
  - Doc greps for P6R3-11 and P6R3-12.
  - No test runs besides the gate.
- **Side effects.** No tracked file changed, no git operation, and `STATE.md` and `log.md` are untouched. The
  code-reviewer subagent wrote three scratch files into the session scratchpad root (`chain_tail.txt`, `t13a.txt`,
  `t13b.txt`), against its brief. They are outside this unit's subfolder and were left in place. The advisor was
  rate-limited.
- **New dependencies.** None.

## Findings

Every finding, unfiltered. The full rows are in the report.

| ID | Sev | Title | Location |
|---|---|---|---|
| P6R3-1 | MEDIUM (silent-failure-hunter: LOW) | Stale `runner-end` reads `final` while a re-run starts, and for good if it dies before the lock | `lib/chain.sh:144-166`; `lib/units.sh:112`, `:28-46` |
| P6R3-2 | LOW | A child can write `runner-end`; a refused run never clears it | `lib/chain.sh:10`, `:166`; `lib/units.sh:112` |
| P6R3-3 | LOW | Non-regular `runner-end`: a dir mid-run means silent stuck, a dir at start means every run exits 1, a FIFO blocks wait forever (dir case reproduced) | `lib/chain.sh:10`, `:166`; `lib/units.sh:112` |
| P6R3-4 | LOW | The 10 s and 60 s limits use the wall clock; a step delays them or reads stuck early | `lib/units.sh:117`, `:120`, `:131-132` |
| P6R3-5 | LOW | The clear's placement is untested both ways (rm above the lock, or later than early refusals) | `lib/chain.sh:166`; `tests/23-runner-lock.sh`; `tests/10-chain-done.sh:46-56` |
| P6R3-6 | LOW | The 10 s and 60 s values are not pinned; wide ranges survive | `tests/13-wait.sh:57-67`, `:172-179`, `:210-239` |
| P6R3-7 | LOW | The retry test has about 0.5 s of margin and may flake | `tests/13-wait.sh:221-227` |
| P6R3-8 | LOW | No test for odd `runner-end` content; a prefix-match mutant survives | `tests/13-wait.sh:100-124` |
| P6R3-9 | LOW | TERM between accept and `chain_end`: the file exists with no `job done` line; the spec implies the line always follows | `lib/chain.sh:199-200`; `docs/spec.md:46-47` |
| P6R3-10 | LOW | An end from a runner older than this change has no `runner-end` and reads stuck | `lib/units.sh:112`; README Watch |
| P6R3-11 | LOW | Spec and README overstate when `runner-end` is absent (pre-lock exits, exit 1 or signal refusals) | `docs/spec.md:45-49`; `README.md:109`, `:112` |
| P6R3-12 | LOW | Doc details: `until` is up to 47 characters, not 40; `·` becomes `-`, not lost; the 13-wait row's ` · `; "not at once" unasserted | `README.md:104`; `docs/spec.md:59`, `:239`; `tests/13-wait.sh:132` |
| P6R3-13 | LOW | A failed `date` mid-watch exits 1 with no line | `lib/units.sh:117`, `:131` |
| P6R3-14 | LOW | Docs give the limits in seconds; a large poll stretches the 60 s limit | `README.md:112-113`; `docs/spec.md:59`, `:112-115`; `bin/blast-off:44-47` |

## Open owner questions

1. P6R3-1: should a re-run hide the old end from the moment the unit starts? The options are an `rm` in `unit_start`
   when the unit is down, an InvocationID match, or an mtime check against `ExecMainStartTimestamp`. Or does
   "the job is unchanged, the end still holds" stand, with the docs fixed?
2. P6R3-2: is a child writing `runner-end` inside the threat model?
3. P6R3-3: should a non-regular `runner-end` count as "no end", with the stuck line naming it?
4. P6R3-4: clamp the clock, move to a monotonic clock, or add a `ponytail:` note?
5. P6R3-10: document how an end from an older runner reads, or accept it as a one-time migration?

## Next

This was the last allowed round. The manager delivers phase 6 and files a follow-up issue with:
- P6R3-1 through P6R3-14 (P6R3-13 optional)
- the carried-over P6R2-6, -7, -12..-18, P6R2-S1..S3, P6R1-9, -12, -13, -14, -18, -19, and the earlier LOWs
