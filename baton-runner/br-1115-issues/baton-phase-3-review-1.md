---
source: runner
scope: br-1115-issues
parent_session: ""
---
# Pass-Baton: phase 3 review 1 (issue 26, P2R1-1): ISSUES, one HIGH (zero PRs read lets done through, silent)

**Date:** 2026-11-15
**Scope:** br-1115-issues
**Branch:** feat/br-1115-issues/phase-3
**Worktree:** /home/alex/blast-off/.claude/worktrees/pending-items-53932d
**HEAD:** b9c39ad feat(phase-3): refuse done when CI is absent but the repo has workflows (#26)

## Where things stand

**VERDICT: ISSUES.** Gate green, all five acceptance criteria met with real tests, but the synthesized review holds 1 HIGH (P3R1-1), filed by all five severity-using reviewers. No CRITICAL. 19 MEDIUM, 24 LOW. No digest written (not CLEAN). Blocking state: P3R1-1 needs a fix unit.

- **ExecStart check: OK** after the gate and again after the mutation runs: `ExecStart=/home/alex/blast-off/.worktrees/blast-off-build/bin/blast-off run %f`.
- **Gate:** `scripts/gate.sh baton-runner/br-1115-issues/gate-phase-3-iter-1/`, run once, alone, `BLAST_OFF_TEST_ONLY` unset: exit 0, last line `GATE: PASS passed=18 failed=0 shellcheck=ok`. Log: `baton-runner/br-1115-issues/gate-phase-3-iter-1/tests-run.log`.
- **Review report:** `baton-runner/br-1115-issues/review-phase-3-iter-1.md` (reviewed at b9c39ad81d3e656c73e211080852a952465f018d; 6/6 reviewers returned; `## Report Audit` appended). Reviewer returns (retyped copies, not byte-verified): `baton-runner/br-1115-issues/review-phase-3-iter-1/*.md`.
- **The multi-agent review ran** (`Z0rd0nZords:zord-multi-agent-review spec ...`), inline: this unit is itself a subagent, so no orchestrator layer. Roster as in phase 2: code-reviewer, critical-thinking, silent-failure-hunter, security-reviewer, penetration-tester, tdd-guide. All are parked; each ran as a general-purpose agent reading its parked definition read-only. Synthesizer and report auditor ran as forks. Reviewers ran no test scenario.
- **New dependencies: none** (no tool, package or action). New reliance for the owner's eye: the `event` JSON field of `gh run list` (listed by `gh run list --help` on gh 2.101.0; no gh version floor is declared anywhere), `git ls-tree`, `awk` in `lib/ci.sh` (already used in `lib/checkpoint.sh`), and `git init`/`commit` inside scenario 41.

### Acceptance criteria (each met, test cited, mutant killed)

Mutants ran one at a time on a `git archive` copy with `BLAST_OFF_TEST_ONLY=41-ci-wait tests/run` (scenario 41 never calls `install_units`). Baseline: `GATE-ONLY: PASS passed=1`. Logs: `/tmp/claude-1000/-home-alex-blast-off--claude-worktrees-pending-items-53932d/60b15296-819e-491a-8ffe-34b3bd988f86/scratchpad/mut-v9ErzD/logs/`.

| AC | Test | Mutant of `lib/ci.sh` | Result |
|---|---|---|---|
| 1 absent + workflow at HEAD: exit 10 | `tests/41-ci-wait.sh:136-139` | workflow-check line deleted | killed: `absent CI with a workflow at HEAD: exit 0` |
| 2 absent, no workflow: done, logged | `tests/41-ci-wait.sh:113-116,133-134` | absent always refused; refused in any git workdir | both killed: `green and absent records: exit 10`; `absent CI, no workflow at HEAD: exit 10` |
| 3 PRs only from Status cells | `tests/41-ci-wait.sh:84-88,113-115` | whole-file grep restored; `awk` dropped (all cells) | both killed: `green and absent records: exit 10` (PR #98/#99 unread) |
| 4 dispatch runs do not count | `tests/41-ci-wait.sh:27-32,68-75` | filter dropped; red dispatch 72 counted; late red dispatch 73 counted | all killed: `green dispatch run counted: exit 0`; `red dispatch runs counted: exit 10` (twice). The PR 15 half, never seen red by the implementer, is live |
| 5 tests in 41, spec updated | `tests/41-ci-wait.sh`; `docs/spec.md:35,58,97,228` | absent branch skips `ci_head` | killed: `absent record gh could not check: exit 0`. Spec rows match the code (omissions: P3R1-21) |

### Judgments asked for

- `templates/checkpoint.md:29-30`: **now false, errs fail-open** (claims a PR named anywhere is gated). P3R1-5. `tests/51-templates.sh:74` pins the phrase `means this job's own PR` (read here; three reviewers said it does not), so the fix must change test 51 in the same commit.
- `skills/blast-off/SKILL.md:34-35`: **now wrong where HEAD has a workflow file, errs fail-closed** (promises a pass, written into brief §2). P3R1-6.
- `README.md:114-115`: **incomplete, not false**; `README.md:130` and `bin/blast-off:37` have the same gap. P3R1-7, P3R1-8.
- Checkpoint with no Phase plan table: **yes, a fail-open, new with this commit, and silent**. P3R1-1.
- Real gh and `event`: supported. `gh run list --help` lists `event`; a read-only `gh run list --repo z0rd0n88/blast-off --limit 40 --json databaseId,event,headSha` returned 13 `workflow_dispatch` and 13 `pull_request` runs, so the literal string is right (the reviewers could not run this and left it inconclusive).

## Findings: MEDIUM and above

| ID | severity | file:line | failure path | suggested fix |
|---|---|---|---|---|
| P3R1-1 | HIGH | `lib/ci.sh:66-67`; `lib/chain.sh:159`; `docs/spec.md:97` | Zero PRs read from Status cells (no table, `## Phase Plan`, `### Phase plan`, indented rows, key `P0`, PR column before Status, done row with no PR token): loop never runs, `job done`, exit 0, no log line. Phase 2 refused these with exit 10. Table-less checkpoints are supported (`docs/spec.md:22,61`) and have no receipt gate either | Log the PRs read at done, or `no PR named in a Phase plan Status cell; CI not read`. When `cp_phases` is 0 keep the old whole-file read (or refuse, or document: owner's call). Spec sentence. Tests: table-less with prose `PR #N`, done row with no PR token |
| P3R1-2 | MEDIUM | `lib/ci.sh:66-67`; `templates/checkpoint.md:27,47` | PR named only in `Completed phases` (the template's own shape) or another cell: ungated, nothing logged | The P3R1-1 log line; optionally log `PR #N named outside a Status cell; not read` |
| P3R1-3 | MEDIUM | `lib/ci.sh:72-75` | Workflow check reads workdir HEAD, not the PR head, record `head_sha` or base: a HEAD that deleted the workflow, or an uncommitted workflow, reads as none and absent passes; a workflow added in a later phase refuses earlier stacked PRs | Read the tree of the record's `head_sha` and `origin/<base>`; missing object = refusal; or state the limit in spec and log |
| P3R1-4 | MEDIUM | `lib/ci.sh:73-74,53-54` | Absent plus any file under `.github/workflows` (`.gitkeep`, `README.md`, dispatch-only workflow, `branches: [main]` on stacked PRs) is exit 10 forever; dispatch no longer counts; only exits are deleting the PR token (P3R1-1) or hand-editing the record | Count only top-level `*.yml`/`*.yaml`; name real exits in the message; one logged owner override the child cannot write |
| P3R1-5 | MEDIUM | `templates/checkpoint.md:29-30`; `tests/51-templates.sh:74` | Child-facing rule says a PR "anywhere here" is checked at done: false, fail-open | Reword to Status-cell-only and "a row closed without one gets no CI check"; update the phrase pinned in test 51 |
| P3R1-6 | MEDIUM | `skills/blast-off/SKILL.md:34-35` | Says the runner lets done through on absent; planner writes that into brief §2; job stops at exit 10 | State both cases (no workflow file: passes, logged; workflow file: refused) |
| P3R1-7 | MEDIUM | `README.md:114-115,130` | "red or unread" omits absent-with-workflow; row 10's remedy loops (`ci-wait` records absent again) | Add the absent case, "named in a Phase plan Status cell", and a remedy |
| P3R1-8 | MEDIUM | `bin/blast-off:37` | `--help` exit 10 line has the same omission | One clause |
| P3R1-9 | MEDIUM | `lib/ci.sh:67` (regex unchanged) | `PR 7`, `#7`, `PRs #7, #8`, `PR: #7`, `pull request #7` in a Status cell read no PR; before, a second mention elsewhere often caught them | The P3R1-1 log line; optionally accept `#N` after `PR` |
| P3R1-10 | MEDIUM | `tests/41-ci-wait.sh:80-139` | No case for an empty PR list in either direction (the old table-less `fin` fixture was replaced) | Cases from P3R1-1 |
| P3R1-11 | MEDIUM | `tests/41-ci-wait.sh:124-139` | `git -C "$TOP"` to `-C "$WORKDIR"` survives (by reading); from a subdirectory the pathspec prints nothing: fail-open | A job whose workdir is a subdirectory of the repo |
| P3R1-12 | MEDIUM | `lib/ci.sh:73`; `tests/41-ci-wait.sh:124-139` | `\|\| die` to `\|\| true` on the `ls-tree` line survives (by reading): git error would read as no workflow | A case where `ls-tree` fails (unborn HEAD) must not exit 0 |
| P3R1-13 | MEDIUM | `tests/41-ci-wait.sh:136-138` | Working tree read instead of HEAD survives (by reading) | An untracked workflow file; one committed then deleted on disk |
| P3R1-14 | MEDIUM | `tests/41-ci-wait.sh:27-32,71-75`; `tests/fakes/gh:28` | `select(.event == "pull_request")` survives: a red `push` run would be dropped | One counted run with `event-<id>` = `push`, red |
| P3R1-15 | MEDIUM | `tests/41-ci-wait.sh:84-86` | Dropping the `## Phase plan` range survives (measured on the fixture) | A digit-keyed row naming a PR under another heading |
| P3R1-16 | MEDIUM | `tests/41-ci-wait.sh:84-86` | `$(NF-1)` to `$5` survives (measured on the fixture) | A five-column table |
| P3R1-17 | MEDIUM | `tests/41-ci-wait.sh:84-86` | Dropping the digit-key filter survives (measured on the fixture) | A `P1` row naming a PR |
| P3R1-18 | MEDIUM | `tests/41-ci-wait.sh:127,133-138` | Pathspec unpinned: `-- .github`, `-- .` or none give the same result on the fixture's commits | Commit one ordinary file and one under `.github/` outside `workflows/` |
| P3R1-19 | MEDIUM | `tests/41-ci-wait.sh:124-139` | A mutant applying the workflow refusal to `success` records survives (by trace) | A success record in a git workdir with a workflow must pass |
| P3R1-20 | MEDIUM | `tests/41-ci-wait.sh` | No runner-level case joins criteria 1 and 4 (dispatch-only head plus workflow file: done refused) | One such case |

## Findings: LOW

| ID | sev | file:line | failure path | suggested fix |
|---|---|---|---|---|
| P3R1-21 | LOW | `docs/spec.md:97` | Row 10 omits: only digit-keyed rows read; table-less gets no CI check; `ls-tree` failure is exit 1; any file counts; dispatch-only head is absent then refused | One clause each |
| P3R1-22 | LOW | `lib/ci.sh:74` | Message says "push, or re-run it": nothing to re-run on absent | "run ci-wait again; push to the PR branch" |
| P3R1-23 | LOW | `lib/ci.sh:38,68-70` | A `success` record written by phase-2 code from a green dispatch run still passes (jobs in flight) | Record `event` per run, or note in the PR body |
| P3R1-24 | LOW | `lib/ci.sh:53-54` | `--limit 100` applies before the client-side filter; dispatch runs can crowd out a red PR run | Die when the list length equals the limit, or raise it |
| P3R1-25 | LOW | `lib/ci.sh:36-45,52-55` | `ci-wait` logs `absent ()` with no hint that dispatch runs were left out | Log the count left out |
| P3R1-26 | LOW | `lib/ci.sh:49-55`; `docs/spec.md:58` | By design a red dispatch run no longer blocks; dispatch-driven CI is fail-open | One spec sentence |
| P3R1-27 | LOW | `lib/ci.sh:54` | Pre-existing: `push`, `schedule` and other events count both ways | Document |
| P3R1-28 | LOW | `lib/ci.sh:66-67` | `for pr in $(pipeline)` discards the pipeline's status; a failing stage or a NUL byte in the cell reads as no PRs | `prs="$(...)" \|\| die`; `grep -a` |
| P3R1-29 | LOW | `lib/ci.sh:66` | No trailing pipe, extra column or `\|` shifts the cell read; mostly exit 9, but exit 0 outside git when the cell read starts "done" | Shared helper that strips a missing trailing pipe |
| P3R1-30 | LOW | `lib/ci.sh:67` | Another repo's `/pull/N` inside a Status cell is still read (issue 26's edge case, inside the cell) | Match `/pull/N` only for the workdir's repo, or document |
| P3R1-31 | LOW | `lib/ci.sh:73-75` | Outside git nothing is read yet the log says "no workflow file at HEAD" | Log "workdir is in no git repo; workflow files not read" |
| P3R1-32 | LOW | `tests/fakes/gh:20-21`; `docs/spec.md:97` | Fake `gh pr view` works outside git, real gh does not: the spec's non-git pass branch is fake-only | Note in spec or drop the branch |
| P3R1-33 | LOW | `tests/fakes/gh:22-30` | Fake prints `event` for any `--json` field containing "event"; ignores `--limit` | Match `(^\|,)event(,\|$)`, fail on unknown fields |
| P3R1-34 | LOW | `lib/ci.sh:52-55` | `ci_runs` relies on the caller's `pipefail` | `out="$(gh ...)" \|\| return 1`, then jq |
| P3R1-35 | LOW | `lib/ci.sh:2,73` | `ci_check` now needs `TOP`; header still says only JOB, WORKDIR | Add "TOP by chain_run" |
| P3R1-36 | LOW | `lib/ci.sh:73`; `lib/chain.sh:21` | `ls-tree` failure dies with exit 1; reason on stderr only | Log before dying |
| P3R1-37 | LOW | `tests/41-ci-wait.sh:81-86` | `fin` now needs the scenario dir outside any git repo (done rows, fake sha, no receipt) | A comment, or accept |
| P3R1-38 | LOW | `tests/41-ci-wait.sh:112,119,132` | `wf` job copies its record from the `cmd` job and leans on earlier fake state | Build the record in place |
| P3R1-39 | LOW | `baton-phase-3-work.md` | Criterion 2's RED was wording only; PR 15 half never seen red by the implementer (now shown live, see table above) | None |
| P3R1-40 | LOW | `lib/ci.sh:68` | Pre-existing: a hand-written `ci-pr-N.json` is trusted | File separately |
| P3R1-41 | LOW | `lib/ci.sh:41` | Pre-existing: `skipped` and `neutral` count as green | File separately |
| P3R1-42 | LOW | `lib/ci.sh:53` | gh `event` field with no declared gh version floor (old gh fails closed) | State a floor, or accept |
| P3R1-43 | LOW | `tests/41-ci-wait.sh` | No case for `gh run list` failing inside `ci_runs` | Optional case |
| P3R1-44 | LOW | `tests/41-ci-wait.sh:136` | "Any file under `.github/workflows` counts" is unpinned | Optional case |

## Next steps

1. Fix unit for P3R1-1 in `lib/ci.sh:64-67`: log the PR set read at done (including "none"); decide the table-less case (recommended: whole-file read when `cp_phases` is 0, which keeps issue 26's fix for jobs with a table); add the two cases to `tests/41-ci-wait.sh`; one sentence in `docs/spec.md:97`. That also closes P3R1-10 and most of P3R1-2 and P3R1-9.
2. Owner or manager decides whether the fix unit's target set widens to the stale docs: `templates/checkpoint.md:29-30` with `tests/51-templates.sh:74`, `skills/blast-off/SKILL.md:34-35`, `README.md:114-115,130`, `bin/blast-off:37` (P3R1-5 to P3R1-8). They are outside this phase's confirmed set.
3. Owner decides P3R1-3 and P3R1-4 (which commit decides "runs were due"; an override for a PR that can never get a run). Fix now or file as issues.
4. Next review: `scripts/gate.sh baton-runner/br-1115-issues/gate-phase-3-iter-2/`, once, alone. Test-run rule unchanged: one full suite at a time; reviewers run no `tests/run` unfiltered, no `scripts/gate.sh`, no scenario that calls `install_units`.

## Open questions / risks

- Reviewer "mutant survives" claims (P3R1-11 to P3R1-19) are by reading or snippet, not scenario runs; only the nine mutants in the table above ran through scenario 41.
- Reviewers disclosed rule slips: real `gh pr view <n> --json headRefOid` ran by accident through `timeout` (code-reviewer 9, silent-failure-hunter 12, security-reviewer 5, tdd-guide 5 calls), all in throwaway dirs, all reported as failing locally; `gh --version` twice. Nothing mutating. Put "stub gh as an executable on PATH, never as a shell function" in the next reviewer brief.
- Report audit (last section of the report) found three rendering flaws, no severity change: 19 MEDIUM rows trace to about 9 findings as filed; "all agree criteria 1 to 5" overstates (four reviewers said 1 to 4); one attribution slip on P3R1-42.
- The report lists 14 open questions for the author, all PENDING (report section `Open Questions for the Author`).
- Left in the session scratchpad (under /tmp, nothing in the repo): this unit's `mut-v9ErzD/` and reviewer dirs `ct3.Jdkiqo`, `rev3.8abnDc`, `sfh3.wdWhUx`, `pt3.CDv2LJ`. Other `mut-*` dirs there are not this unit's and were not touched.
- The synthesizer and auditor forks wrote the report file themselves (their only writes); the worktree's tracked files are unchanged (`git status --porcelain` shows only untracked `baton-runner/` paths).

## References

- Issues: z0rd0n88/blast-off issue 26; finding P2R1-1 in `baton-runner/br-1115-issues/baton-phase-2-review-1.md`
- Work baton: `baton-runner/br-1115-issues/baton-phase-3-work.md`
- Gate log: `baton-runner/br-1115-issues/gate-phase-3-iter-1/tests-run.log`
- Review report: `baton-runner/br-1115-issues/review-phase-3-iter-1.md`; reviewer returns in `baton-runner/br-1115-issues/review-phase-3-iter-1/`
- Code: `lib/ci.sh:52-80`, `lib/chain.sh:137-159`, `lib/checkpoint.sh:39-44`, `tests/41-ci-wait.sh`, `tests/fakes/gh`
