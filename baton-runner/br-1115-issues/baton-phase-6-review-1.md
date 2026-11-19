---
source: runner
scope: br-1115-issues
parent_session: ""
---
# Pass-Baton: phase 6 review round 1 (issue 14), VERDICT ISSUES, 0 CRITICAL, 1 HIGH, 13 MEDIUM, 21 LOW

**Date:** 2026-11-17
**Scope:** br-1115-issues
**Branch:** feat/br-1115-issues/phase-6
**Worktree:** /home/alex/blast-off/.claude/worktrees/pending-items-53932d
**HEAD:** b010b90 feat(units): blast-off wait blocks until the job changes (#14)

## Where things stand

VERDICT: ISSUES. The gate passes and every issue-14 criterion has a passing test, but one HIGH stands. P6R1-1:
`wait` exits 0 `final` the moment a child writes `status: done`, while the runner is still up and can still refuse
that done (receipt exit 9, CI exit 10, status left at `done`). After a refusal every later `wait` also returns 0, so
the watching session reports done and stops on a job that is not done. Five of six reviewers raised it; reproduced.
`tests/13-wait.sh:65` asserts this behaviour, so the fix changes that test too. Read P6R1-1 first.

The fired-timer HIGH that four reviewers raised (a one-shot timer stays `active`/`elapsed`, so `wait` blocks forever)
is refuted on this box. A real systemd 255 probe of the exact `systemd-run --collect --on-calendar` form shows
`RemainAfterElapse=no`, and after it fires the timer reads `not-found`/`inactive`. The reverse is a MEDIUM:
between the timer firing and `unit_start`, unit and timer both read down, so `wait` can say a false `stuck` (P6R1-3).

- Gate: `scripts/gate.sh` ran once, alone, before any reviewer: exit 0, `GATE: PASS passed=19 failed=0 shellcheck=ok`.
  Log: `baton-runner/br-1115-issues/gate-phase-6-iter-1/tests-run.log`. An earlier call omitted the `<log-dir>`
  argument and stopped at the usage check (exit 1) before any scenario ran.
- ExecStart: `ExecStart=/home/alex/blast-off/.worktrees/blast-off-build/bin/blast-off run %f` before the gate, after
  it, after the systemd probe, after each mutant run, and at the end. Never changed.
- Multi-agent review: ran inline, `--high-cap off`, six parked reviewers each as a `general-purpose` agent reading its
  definition read-only, held to static work. All six returned; outputs in `review-phase-6-iter-1/<reviewer>.md`.
  Report: `review-phase-6-iter-1.md` (no synthesizer or auditor agent; I deduplicated it myself).
- Reproduced by me, one at a time on a `git archive b010b90` copy: P6R1-1 (done with unit active -> rc 0), mutant A
  (status dropped from the compare) survives 13-wait, mutant B (`activating` counted as stuck) survives, checkpoint
  emptied mid-watch -> rc 1 "missing", systemctl bus failure -> rc 1 and no line, `BLAST_OFF_WAIT_POLL` 0/inf/abc/--help,
  a forged field echoed in the line. One systemd probe (a throwaway `p6probe-*` transient timer running `/bin/false`);
  a second probe was denied by the auto-mode classifier and not retried.
- Side effects: none. `git status` outside `baton-runner/` is empty, HEAD b010b90, the review dir holds exactly the six
  files, no `p6probe*` unit is left. My scratch copies are deleted. STATE.md and log.md untouched. No new dependencies.

## Intent check (issue 14)

| Criterion | Test | Real? |
|---|---|---|
| Child launch | `tests/13-wait.sh:51` | Yes (work unit's M1 killed) |
| Phase change | `:59` | Yes (M2 killed) |
| done / blocked | `:65`, `:67`, `:69` | done yes, but it pins P6R1-1; blocked only at start (P6R1-27) |
| paused | `:85-86` paused-cap 12, `:87-92` paused-limit | Yes; status-only change untested, mutant A survives (P6R1-4) |
| Unit inactive / devil's advocate | `:75-79` | Yes vs the fake; `activating` mutant B survives (P6R1-8) |
| Missing job dir with a reason | `:95-108` | Yes |
| Machine sleep not a change | `:110-129` | Weak: kills only `date` clocks (P6R1-12) |

## Next step for the fix unit

1. P6R1-1 (HIGH), after the owner picks the rule (Q1 below): make `final` wait for the runner's verdict, and change
   test 65 to expect blocking while the unit is up.
2. MEDIUMs worth taking in the same pass, each small: P6R1-3 (count `$UNIT.resume.service` as scheduled, or confirm
   stuck on a second poll), P6R1-4 and P6R1-8 (a status-only change test; an `activating` test), P6R1-5 (retry a
   failed read rather than exit 1 mid-watch), P6R1-6 (validate the poll value like `chain_nums`), P6R1-10 (SKILL.md:
   "after start", meaning of 1). P6R1-2, -7, -9 need owner answers first.

## Open owner questions

1. P6R1-1: final only once the unit is down and run.log ends `job done`/`job blocked`, or the runner rewrites the
   status when it refuses done?
2. Q1 / P6R1-2: keep paused-cap at 12, or its own code?
3. Q2 / P6R1-9: accept "started with `start`, under the job dir's parent" as the documented limit; drop `start` from
   README's 12 advice, or key lock and unit on the physical path?
4. P6R1-7: child-written text in the line, or only derived values?
5. P6R1-6 bounds; P6R1-5 retry vs own exit code; P6R1-19 an optional upper bound; P6R1-13 one real-systemd check in
   11-unit-smoke; P6R1-12 a static clock-read grep; P6R1-35 (outside the diff) the runner's wall-clock child timeout.
