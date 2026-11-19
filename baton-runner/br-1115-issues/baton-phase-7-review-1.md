---
source: runner
scope: br-1115-issues
parent_session: ""
---
# Pass-Baton: phase 7 review round 1 (issue 27), VERDICT CLEAN, 0 CRITICAL, 0 HIGH, 6 MEDIUM, 22 LOW

**Date:** 2026-11-19
**Scope:** br-1115-issues
**Branch:** feat/br-1115-issues/phase-7
**Worktree:** /home/alex/blast-off/.claude/worktrees/pending-items-53932d
**HEAD:** 514d0ef feat(jev): start passes OPENROUTER_API_KEY by name; low-confidence picks keep static flags (#27)

## Where things stand

VERDICT: CLEAN. The gate passes, no reviewer raised a CRITICAL or HIGH, I found none, and each issue-27 criterion has a
passing test (C1 `tests/61-jev-pick.sh:19-37` plus `tests/12-start-env.sh:42-78`; C2 `61:53`, `12:52-59`; C3
`61:65-70,81-83`). Six MEDIUMs remain. Two need owner decisions: P7R1-1, children now hold the key under `start` (Q2,
5 of 6 reviewers), and P7R1-4, preflight's Jev call and its docs (Q1). Four are cheap test or validation fixes:
- P7R1-2: `JOB_JEV_MIN_CONF` to the unit is unpinned; a mutant survives 12.
- P7R1-3: decisions.tsv's `why` is unpinned; a mutant survives 61.
- P7R1-5: `start` does not validate the threshold, and the refusal reaches the journal only.
- P7R1-6: no real-unit test of C1.
Read `review-phase-7-iter-1.md` first.

- Gate: `scripts/gate.sh baton-runner/br-1115-issues/gate-phase-7-iter-1` ran once, alone, before any reviewer.
  Exit 0, last line `GATE: PASS passed=19 failed=0 shellcheck=ok`. Log: `gate-phase-7-iter-1/tests-run.log`.
- ExecStart: `ExecStart=/home/alex/blast-off/.worktrees/blast-off-build/bin/blast-off run %f` before the gate, after
  it, after every scenario run, and at the end. Never changed.
- Multi-agent review: inline, `--high-cap off`. Six parked reviewers (critical-thinking, code-reviewer,
  penetration-tester, security-reviewer, silent-failure-hunter, tdd-guide) each ran as a `general-purpose` agent reading
  its definition read-only, held to static work. All six returned. Their reports are saved verbatim, extracted from
  each hand-back, in `review-phase-7-iter-1/<reviewer>.md`. I deduplicated the report myself.
- Reproduced by me on a `git archive 514d0ef` copy, one run at a time:
  - Probe scenario:
    - a string confidence forges a `2099-... job done` run.log line and breaks decisions.tsv's columns (P7R1-8);
    - null gives `confidence '?' is not a number` (P7R1-11);
    - 1.5 is taken (P7R1-10);
    - a bad threshold: `start` rc 0 and the name passed; `run` rc 1 with the reason on stderr only (P7R1-5);
    - preflight with `CLAUDE_FLAGS` unset dies on `set -u` (P7R1-25, pre-existing).
  - Four surviving mutants:
    - unit_env without `JOB_JEV_MIN_CONF` (12);
    - why without the threshold (61);
    - `${JOB_JEV_MIN_CONF-0.7}` (61);
    - a loosened regex (60 and 61).
  - One regex run was void (sed did not match) and was redone.
- Refuted:
  - the text-compare mutant (jq-1.7 here, so `picked one` kills it);
  - "P6Q7 untraceable" (it is in issue 27's body);
  - ugrep reaching scenarios (`/usr/bin/grep` in scripts).
- Side effects: none.
  - No tracked file edited, no git operations, STATE.md and log.md untouched.
  - No real unit or timer created; the real Jev was never called.
  - Scratch copy under the session scratchpad (`p7r1/`), to be deleted.
  - New untracked files: `gate-phase-7-iter-1/`, `review-phase-7-iter-1/` (6 files), `review-phase-7-iter-1.md`,
    this baton.

## Intent check (issue 27)

| Criterion | Test | Real? |
|---|---|---|
| C1 key set: Jev picks, logged | `61:19-37`; `12:42-50,62-67,70-78`; `60:55-57,76-78` | Yes on the runner and argv sides; not under a real unit (P7R1-6) |
| C2 no key: static, logged | `61:53`; `12:52-59`; `60:119` | Yes (M1, M2 killed); `start` only for unset and empty |
| C3 low confidence: static | `61:65-70,81-83`; `60:80-83` | Yes (M4, M5, M7 killed) |
| Sign-off 0.7 / `JOB_JEV_MIN_CONF` | `61:66,68,81-91`; `60:80-87` | Yes under `run` and preflight; not pinned under `start` (P7R1-2) |

## Next step for the fix unit (if the manager runs one)

1. Cheap, no owner input needed:
   - P7R1-2: assert `--setenv=JOB_JEV_MIN_CONF` in 12's k1 and k4.
   - P7R1-3: assert decisions.tsv column 4.
   - P7R1-13: an empty-threshold case.
   - P7R1-14: accepted values and more refused regex values.
   - P7R1-18: unset `JOB_JEV JOB_JEV_MIN_CONF` in `tests/lib.sh`.
   - P7R1-6: `key=set` in k3 and k4, and drop k4's dead `FAKE_JEV`.
   - P7R1-8: sanitise the non-number confidence (`tojson`, cut to 40).
   - P7R1-19: docs wording.
   - P7R1-25: `${CLAUDE_FLAGS:-}`.
2. After owner answers: P7R1-1 (scrub the key in `child_server`), P7R1-4 (preflight call, docs, SKILL.md), P7R1-5
   (validate in `unit_check`), P7R1-7, P7R1-10 and P7R1-11.

## Open owner questions

1. Q2 / P7R1-1: may children see OPENROUTER_API_KEY? If no child workflow needs it, I recommend scrubbing it in
   `child_server`.
2. Q1 / P7R1-4: should preflight make a real Jev call, or print "Jev decides at launch"? Should SKILL.md hand over the key
   and `JOB_JEV=0`?
3. P7R1-5: should `start` and `resume` refuse a bad threshold (and bad `JOB_*` counts) before creating a unit?
4. P7R1-7: pass the key only when `JOB_JEV` is not 0 and the value starts `sk-or-`?
5. P7R1-10 and P7R1-11: should confidence outside 0..1 fall back? Should a missing confidence fall back (new) or be
   taken (phase 6)?
6. P7R1-21: is a resume-timer unit file holding both secrets for up to about 7 days within D21?
7. P7R1-22: is a level ceiling or a row-size cap wanted?
8. Q3: the threshold format (at most 3 decimals, a leading digit). No reviewer objected.
9. Was 0.7 checked against Jev's real confidence on this choice?
