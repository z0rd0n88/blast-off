---
source: runner
scope: br-1115-issues
parent_session: ""
---
# Pass-Baton: phase 3 work unit, issue 26 and P2R1-1 (absent CI, Status-cell PRs, dispatch runs) implemented

**Date:** 2026-11-15
**Scope:** br-1115-issues
**Branch:** feat/br-1115-issues/phase-3
**Worktree:** /home/alex/blast-off/.claude/worktrees/pending-items-53932d
**HEAD:** 30e85b2 chore(phase-2): zord-baton-runner STATE + log update (changes uncommitted; the manager owns git)

## Where things stand

Criteria 1 to 5 are implemented, each test written first and seen red. `BLAST_OFF_TEST_ONLY=41-ci-wait,70-docs tests/run` passes with `shellcheck=ok`. The one full `tests/run` passed (`GATE: PASS passed=18 failed=0 shellcheck=ok`, exit 0). No new dependency. Nothing committed or pushed.

Files changed (tracked, 4):
- `lib/ci.sh`
  - New `ci_runs <sha>`: `gh run list --commit <sha> --limit 100 --json databaseId,event`, ids of runs whose event is not `workflow_dispatch`. Both list calls in `ci_wait` use it, so a dispatch run is never watched, viewed or recorded (criterion 4).
  - `ci_check` reads PR numbers only from the Status cell (last cell) of digit-keyed `## Phase plan` rows, the rows `cp_plan_rows` reads (criterion 3). The accepted forms are unchanged: `PR #N` any case, `PR#N`, `/pull/N`, leading zeros dropped.
  - `ci_check`, `absent` record: `ci_head` first (stale-head and gh-failure messages unchanged), then `git -C "$TOP" ls-tree -r --name-only HEAD -- .github/workflows`. Any file there: exit 10, `PR #N CI absent: no runs, but HEAD has a workflow file (<first path>); ...; done refused, status unchanged` (criterion 1). None: `PR #N: no CI runs and no workflow file at HEAD (absent, not a pass)` and done goes on (criterion 2).
  - A workdir in no git repo (`TOP` empty, set in `lib/chain.sh:137-140`) counts as no workflow file. A failing `ls-tree` in a repo dies (exit 1) and does not read as "no workflow".
- `tests/41-ci-wait.sh`: PRs 14 and 15 in the ci-wait section; the `fin` job names its PRs in a Phase plan table, with PR #98 in another cell and PR #99 in prose; new `wf` job in a git workdir (absent record, first with no workflow file, then with one committed).
- `tests/fakes/gh`: `event-<id>` state file (default `pull_request`); `run list` prints `event` only when `--json` asks for it.
- `docs/spec.md`: F7 row (35), `ci-wait` row (58), exit 10 row (97), `41-ci-wait` row (228).

Untracked, planning only: `baton-runner/br-1115-issues/phase-3/{task_plan,findings,progress}.md`, `phase-3/full-gate.log`, this file.

## Evidence

Each RED is the tail of `BLAST_OFF_TEST_ONLY=41-ci-wait tests/run`, test written before the code.

RED criterion 4 (green dispatch run alone on PR 14's head):

```
  |   "runs": [
  |     {
  |       "id": 61,
  |       "name": "ci-61",
  |       "conclusion": "success"
  |     }
  |   ],
  |   "verdict": "success"
  | }
  | 2026-11-16T02:56:09Z ci PR #14 at 9999999999999999999999999999999999999999: success (ci-61 success)
PASS shellcheck (33 files)
GATE-ONLY: FAIL passed=0 failed=1 shellcheck=ok only=41-ci-wait
```

Green after `ci_runs`: `PASS 41-ci-wait`. The scenario stops at its first `fail`, so only the green-dispatch half (PR 14) was seen red; the PR 15 half was written in the same step and first ran after the fix. That green run covers PR 15 (green `pull_request` run 71, red dispatch runs 72 in the first list and 73 in the later one: verdict success, runs `[71]`) and that no `run watch` or `run view` names 61, 72 or 73.

RED criterion 3 (the `d4` run, which was exit 0 before the fixture named PR #98 and #99 outside Status cells):

```
  | 2026-11-16T02:57:03Z PR #9: no CI runs (absent, not a pass)
  | 2026-11-16T02:57:03Z PR #98 CI unread: no readable record for PR 98 in gate-logs/ci-pr-98.json; blast-off ci-wait <job-dir> 98, then run again
PASS shellcheck (33 files)
GATE-ONLY: FAIL passed=0 failed=1 shellcheck=ok only=41-ci-wait
```

Green after the Status-cell read: `PASS 41-ci-wait`.

RED criterion 2. The behaviour (done allowed) held before the change; what was red is the log wording, which now names the missing workflow file. The scenario failed at "absent not logged":

```
  | 2026-11-16T02:58:03Z workdir /tmp/tmp.Obfq64KIrt/cwd/test-1410763-fin is not in a git repo; dirty-tree check off, receipt check off
  | 2026-11-16T02:58:03Z PR #9: no CI runs (absent, not a pass)
  | 2026-11-16T02:58:03Z job done
PASS shellcheck (33 files)
GATE-ONLY: FAIL passed=0 failed=1 shellcheck=ok only=41-ci-wait
```

RED criterion 1 (wording changed, workflow check not yet written; `wf` job, `.github/workflows/ci.yml` committed, run exits 0 where 10 is wanted):

```
  | 2026-11-16T02:58:28Z child cap 3 (soft: 1 Phase plan rows x JOB_CAP_FACTOR 3)
  | 2026-11-16T02:58:28Z PR #9: no CI runs and no workflow file at HEAD (absent, not a pass)
  | 2026-11-16T02:58:28Z job done
PASS shellcheck (33 files)
GATE-ONLY: FAIL passed=0 failed=1 shellcheck=ok only=41-ci-wait
```

Green after the `ls-tree` check, with the spec edits:

```
PASS 41-ci-wait
PASS 70-docs
PASS shellcheck (33 files)
GATE-ONLY: PASS passed=2 failed=0 shellcheck=ok only=41-ci-wait,70-docs
```

Full gate (one run, `BLAST_OFF_TEST_ONLY` unset): `env -u BLAST_OFF_TEST_ONLY tests/run > baton-runner/br-1115-issues/phase-3/full-gate.log 2>&1`, exit 0, no `FAIL` line, last lines:

```
PASS 61-jev-pick
PASS 70-docs
PASS shellcheck (33 files)
GATE: PASS passed=18 failed=0 shellcheck=ok
```

ExecStart check after the full run: `ExecStart=/home/alex/blast-off/.worktrees/blast-off-build/bin/blast-off run %f` (still the build worktree, as expected).

## Next steps

1. Manager: commit the four tracked files; review unit reads `git diff 30e85b2 -- lib/ci.sh tests/41-ci-wait.sh tests/fakes/gh docs/spec.md`.
2. Manager: decide the stale docs below (outside this unit's target set, not edited).

## Open questions / risks

- Stale docs outside the target set, left as they are:
  - `templates/checkpoint.md:29-30` says a `PR #<n>` or `/pull/<n>` "anywhere here" means this job's PR. Now only a Status cell counts. The advice there stays safe; the claim is no longer true.
  - `skills/blast-off/SKILL.md:34-35` says that with no CI the runner lets `done` through. True now only where HEAD has no workflow file.
  - `templates/brief.md:135` ("absent checks are not a pass") still holds.
- A PR named only outside a Status cell (for example in `Completed phases`) is no longer checked at done. The brief template tells children to put `PR #<n>` in the Status cell (`templates/brief.md:143`), and criterion 3 asks for this.
- A PR whose only runs are `workflow_dispatch` now records `absent`; in a repo with a workflow file `done` is refused until a non-dispatch run exists. `ci-wait` on such a head waits `BLAST_OFF_CI_APPEAR` (60 s) before it records absent, as it does for a head with no runs.
- A checkpoint with no Phase plan table (or no digit-keyed row) now has no PR read at all, so `done` is never held for CI there. Before, a `PR #N` anywhere in it was read. Follows from criterion 3.
- `README.md:114-115` says done is refused "while a named PR's CI is red or unread"; it does not name the absent case. Also outside the target set, not edited.
- Runs of other events (`push`, `schedule`, `workflow_run`) still count, as before. Only `workflow_dispatch` is left out.
- The workflow check reads HEAD of the workdir's repo, not the PR's head or base. A workflow file that never triggers on pull requests (say `on: schedule` only) still makes absent a refusal; the way out is a run on the head or removing the PR from the Status cell. Not tested.
- The `event` field of `gh run list --json` is read from the fake only; the real `gh` call has not been run by this unit (no gh beyond `issue view` allowed).

## References

- Issues: z0rd0n88/blast-off issue 26
- Finding: `baton-runner/br-1115-issues/baton-phase-2-review-1.md` row P2R1-1
- Docs: `docs/spec.md` rows F7, `ci-wait`, exit 10, `41-ci-wait`
- Code: `lib/ci.sh` (`ci_runs`, `ci_check`), `tests/41-ci-wait.sh`, `tests/fakes/gh`
- Plan: `baton-runner/br-1115-issues/phase-3/task_plan.md`
