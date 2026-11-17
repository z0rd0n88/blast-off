---
source: runner
scope: br-1115-issues
parent_session: ""
---
# Pass-Baton: phase 3 fix 1 (issue 26 review findings): HIGH P3R1-1 fixed fail-closed, all 19 MEDIUM dispositioned

**Date:** 2026-11-15
**Scope:** br-1115-issues
**Branch:** feat/br-1115-issues/phase-3
**Worktree:** /home/alex/blast-off/.claude/worktrees/pending-items-53932d
**HEAD:** 14728fa chore(phase-3): review iter 1 record (verdict ISSUES)

## Where things stand

All 44 findings of `baton-phase-3-review-1.md` have a disposition below. P3R1-1 (HIGH) is fixed: `done` fails closed and is loud. Of the 19 MEDIUM: 16 fixed, 2 out of scope as owner decisions (P3R1-3, P3R1-4; their limits are now stated in the spec), 1 fixed by logging with its optional half refuted (P3R1-9). Of the 24 LOW: 4 fixed, 2 part-fixed, 18 open. Nothing committed or pushed (the manager owns git). Full-suite result: see "Full run" at the end. Blocking state: none for the next review; four owner questions are listed under "Open questions".

### What P3R1-1 does now (`lib/ci.sh` `ci_check`, new `ci_prs`)

1. PRs are read from Phase plan Status cells as issue 26 asks. `run.log` gets `CI read for the PRs Phase plan Status cells name: 7 9; named elsewhere in checkpoint.md and not read: 96 97 98 99`.
2. When no Status cell names a PR (no table, `## Phase Plan`, `### Phase plan`, indented rows, key `P0`, a PR column before Status, a done row with no PR token), every PR named anywhere in the checkpoint is read instead, which is the rule before issue 26. `run.log` gets `no Phase plan Status cell names a PR; CI read for every PR checkpoint.md names instead: 7 (name this job's PR in its row's Status cell; write any other PR with no '#')`. A job with no record for such a PR is refused, exit 10, as phase 2 refused it.
3. When the checkpoint names no PR at all, `done` goes through and `run.log` gets `no PR named in checkpoint.md; CI not read`.

Why this choice: issue 26 and the spec settle the case where Status cells name PRs (prose is ignored). They do not settle the case where none does. Refusing every `done` with no PR would break jobs that have no PR (most scenarios, and nothing in the spec requires a PR). The whole-file read is the fail-closed option that changes nothing against phase 2 for those jobs, and issue 26's third criterion still holds wherever a Status cell names a PR (`fin` job, PR #98 and #99).

### Dispositions: HIGH and MEDIUM

| ID | Verdict | Disposition | Proof |
|---|---|---|---|
| P3R1-1 | SUPPORTED | fixed | RED 1; cases `nt`, `np` in `tests/41-ci-wait.sh`; mutant M1 killed |
| P3R1-2 | SUPPORTED | fixed where no Status cell names a PR (case `np`: refused); where some do, the PR named elsewhere is logged as not read (issue 26 cannot tell it from another repo's) | RED 1; `fin` log assertion |
| P3R1-3 | facts SUPPORTED, defect OUT OF SCOPE | no code change: issue 26 says "when HEAD has `.github/workflows/*`". Limit stated in `docs/spec.md` row 10 (workdir HEAD at done, not the PR head, base or working tree). Owner question 2 | case `a4` pins HEAD against the working tree |
| P3R1-4 | facts SUPPORTED, defect OUT OF SCOPE | no narrowing and no override: issue 26 says any `.github/workflows/*`, and loosening a fail-closed gate is the owner's call. The refusal message now names the real way out (P3R1-22); spec and README say there is no override. Owner question 3 | RED 3 |
| P3R1-5 | SUPPORTED | fixed: `templates/checkpoint.md` rule reworded; `tests/51-templates.sh` pins three sentences of it | RED 4 |
| P3R1-6 | SUPPORTED | fixed: `skills/blast-off/SKILL.md` step 4 states both cases | read against `lib/ci.sh`; 70-docs green |
| P3R1-7 | SUPPORTED | fixed: `README.md` close-order paragraph and exit 10 row (absent case, Status cell, remedy that does not loop) | 70-docs green |
| P3R1-8 | SUPPORTED | fixed: `bin/blast-off` header, exit 10 clause | `--help` output read; 70-docs green (still 10 codes) |
| P3R1-9 | SUPPORTED (silent), widening REFUTED | fixed by the log lines: such a cell now ends in line 2 or 3 above. Regex unchanged: `PR <n>` with no '#' is the template's own way to name a PR that is not the job's (`templates/checkpoint.md`), so reading it would close that way out | case `np` third run |
| P3R1-10 | SUPPORTED | fixed: cases `nt` (no table), `np` (done row, no PR token), `np` third run (no PR anywhere) | RED 1 |
| P3R1-11 | SUPPORTED (M11 survived) | test added: run with the workdir a subdirectory of the repo (`a3`) | M11 killed |
| P3R1-12 | SUPPORTED (M12 survived) | test added: job `ub`, a repo with no commit, PR in prose: exit 1 with `git ls-tree HEAD failed` | M12 killed |
| P3R1-13 | SUPPORTED (M13 survived) | test added: workflow at HEAD, deleted on disk, still refused (`a4`). The other direction (untracked workflow passes) is not pinned: P3R1-3 questions it | M13 killed |
| P3R1-14 | SUPPORTED (M14 survived) | test added: PR 16, one red `push` run: verdict failure, runs `[81]` | M14 killed |
| P3R1-15 | SUPPORTED (M15 survived) | test added: `fin` has a digit-keyed row with PR #97 under `## Decisions` | M15 killed |
| P3R1-16 | SUPPORTED (M16 survived) | test added: `fin` table has five columns, PR #98 in the fourth | M16 killed |
| P3R1-17 | SUPPORTED (M17 survived) | test added: `fin` has a `P1` row with PR #96 | M17 killed |
| P3R1-18 | SUPPORTED (M18a, M18b survived) | test added: `wf` first commit holds `README.md` and `.github/dependabot.yml` | both killed |
| P3R1-19 | SUPPORTED (M19 survived) | test added: a success record with a workflow at HEAD passes (`a5`) | M19 killed |
| P3R1-20 | SUPPORTED (missing case) | test added: `wf` builds its record with `ci-wait` on PR 14 (head with one `workflow_dispatch` run): absent, passes with no workflow file, refused with one | green run |

### Dispositions: LOW

| ID | Disposition | Why |
|---|---|---|
| P3R1-21 | part-fixed | spec row 10 now says: digit-keyed rows, last cell; the no-Status-cell rule; any file; `ls-tree` failure is exit 1; dispatch-only head is absent |
| P3R1-22 | fixed | message now `push to the PR branch for a run that is not a workflow_dispatch, then blast-off ci-wait <job-dir> N, then run again`; RED 3 |
| P3R1-23 | open | needs `event` in the record format and a re-read rule for jobs in flight |
| P3R1-24 | open | behaviour change in `ci_runs`; the fake ignores `--limit`, so no test without touching `tests/fakes/gh` |
| P3R1-25 | open | needs `ci_runs` to report what it left out |
| P3R1-26 | open | by design (spec row `ci-wait` already says a red dispatch is no failure); owner's call whether to say more |
| P3R1-27 | open | pre-existing; now pinned by PR 16's case and one clause in the spec's test row |
| P3R1-28 | part-fixed, untested | the PR read is now two assignments, so a failing pipeline stops the runner (`set -e`, `pipefail`) and no longer reads as no PRs; `grep -a` not added |
| P3R1-29 | open | shared row-parsing helper is a refactor of `lib/checkpoint.sh`, outside issue 26 |
| P3R1-30 | open | matching the workdir's repo needs another gh or git read; the template's way out (`other PR <n>`) stands |
| P3R1-31 | open | wording only, and the spec quotes the line; skipped for the call budget |
| P3R1-32 | open | a spec note or dropping the non-git branch: owner's call (report question 15) |
| P3R1-33 | open | `tests/fakes/gh` left untouched to stay under the 10-file limit |
| P3R1-34 | open | `bin/blast-off` sets `pipefail`; no failing-`run list` fake to test the change with |
| P3R1-35 | fixed | header comment names `TOP` (comment only, no test) |
| P3R1-36 | open | `die` logging is the same for every runner error (`chain_exit` logs `runner exit 1 without a state`) |
| P3R1-37 | fixed | comment above the `fin` job |
| P3R1-38 | fixed | `wf` builds its record in place with `ci-wait`. The new `ub` job copies PR 9's record from `cmd`, as `fin` does |
| P3R1-39 | no action | process note. This unit's RED lists every failing assertion, not only the first (see Evidence) |
| P3R1-40 | open | pre-existing; file separately |
| P3R1-41 | open | pre-existing; file separately |
| P3R1-42 | open | owner's call on a gh version floor |
| P3R1-43 | open | optional; needs a failing `run list` in the fake |
| P3R1-44 | open | a test would pin "any file counts", the behaviour P3R1-4 questions; left unpinned until the owner answers |

### Files changed (8 tracked, plus this file)

- `lib/ci.sh`: `ci_check` rule above; new `ci_prs` (the token read, shared by both reads); absent message; header comment.
- `tests/41-ci-wait.sh`: PR 16 (red `push` run); `fin` table widened to five columns with rows `P1` and `| 3 |` under `## Decisions`; new jobs `nt`, `np`, `ub`; `wf` rebuilt (first commit with two non-workflow files, record from `ci-wait` on PR 14, runs `a3` to `a5`).
- `tests/51-templates.sh`: pins `in a row's Status cell means this job's own PR`, `A row closed without one gets no CI check`, `unless no Status cell names a PR`.
- `templates/checkpoint.md`, `skills/blast-off/SKILL.md`, `README.md`, `bin/blast-off`, `docs/spec.md` (rows exit 10 and `41-ci-wait`).

Ledger for the two instruction texts (old sentence part: outcome):

- `templates/checkpoint.md` PR rule. "`PR #<n>` or a /pull/<n> link": kept. "anywhere here": changed to "in a row's Status cell". "means this job's own PR": kept. "at done the runner wants a CI record for each (exit 10)": kept. "Name any other PR by its branch or as `other PR <n>`, no '#'": kept. Added: "A row closed without one gets no CI check, and a PR named only outside the Status cells is not read, unless no Status cell names a PR: then every PR named anywhere here is read."
- `skills/blast-off/SKILL.md` step 4. "one stacked draft PR per phase, never merged": kept. "with no CI, `blast-off ci-wait` records `absent` and exits 10": kept. "the runner lets `done` through logged "absent, not a pass"": kept, now limited by "only while the workdir's HEAD has no file under `.github/workflows/`". Added: "and refuses `done` (exit 10) once HEAD has one". "say so in brief §2": changed to "say which holds in brief §2". `templates/brief.md:134-135` ("absent checks are not a pass") agrees with both; not edited.

New reliance to declare: `paste` (coreutils, the package `sort` and `tr` come from) in `ci_prs`. No new tool, package or action.

## Evidence

Method. RED runs and mutants ran in copies of the worktree's tracked files under the session scratchpad (`.../scratchpad/fix1/`, scripts `softred.sh` and `mutloop.sh`), scenario 41 alone, one run at a time, with `fail` made to report and go on, so one run lists every failing assertion. Scenario 41 never calls `install_units`. GREEN runs are `BLAST_OFF_TEST_ONLY=<name> tests/run` in the worktree.

RED 1 (P3R1-1, -2, -10; tests written, `lib/ci.sh` untouched; 5 assertions failed):

```
SOFT-FAIL: PRs read at done not logged: ... (fin job: no such line in run.log)
SOFT-FAIL: no table, PR in prose, no record: exit 0: ... child cap 12 (hard: no Phase plan table in checkpoint.md) ...
SOFT-FAIL: whole-file read not logged: ...
SOFT-FAIL: done row with no PR, PR named below: exit 0: ... child cap 3 (soft: 1 Phase plan rows x JOB_CAP_FACTOR 3) ...
SOFT-FAIL: done with no PR named: exit 0: ... job done ...   (exit right, log line missing)
```

GREEN 1: `PASS 41-ci-wait`, `GATE-ONLY: PASS passed=1 failed=0 shellcheck=ok only=41-ci-wait`.

RED 2 (P3R1-11 to -19, by mutant, before the new cases; `M1` is the P3R1-1 fix removed):

```
== M1: KILLED (failed assertions 2)
== M11: SURVIVES   == M12: SURVIVES   == M13: SURVIVES   == M14: SURVIVES   == M15: SURVIVES
== M16: SURVIVES   == M17: SURVIVES   == M18a: SURVIVES  == M18b: SURVIVES  == M19: SURVIVES
```

Mutants: M11 `git -C "$WORKDIR" ls-tree`; M12 `|| true` for `|| die`; M13 `find` in the working tree for `ls-tree HEAD`; M14 `select(.event == "pull_request")`; M15 no `## Phase plan` range; M16 `$5` for `$(NF-1)`; M17 no digit-key filter; M18a pathspec `.github`; M18b no pathspec; M19 `success|absent)` sharing the workflow refusal.

RED 3 (P3R1-22; all new cases in, code not yet reworded; the only failing assertion, so every mutant-killing case passes on the real code):

```
SOFT-FAIL: absent refusal names no way out: ... PR #14: no CI runs and no workflow file at HEAD (absent, not a pass) ... job done ...
```

GREEN 2 and 3: `PASS 41-ci-wait`. Same mutants after the new cases: all 11 `KILLED` (first failing assertion each: M11 `workdir a subdirectory of the repo: exit 0`; M12 `ls-tree failing at done: exit 0`; M13 `workflow at HEAD, deleted on disk: exit 0`; M14 `red push run not counted`; M15 `PR #97 CI unread`; M16 `done with unread CI` and 11 more; M17 `PR #96 CI unread`; M18a, M18b `absent CI, no workflow at HEAD: exit 10`; M19 `green record with a workflow at HEAD: exit 10`).

RED 4 (P3R1-5; `tests/51-templates.sh` changed first):

```
FAIL 51-templates
  | FAIL: checkpoint.md lacks: in a row's Status cell means this job's own PR
GATE-ONLY: FAIL passed=0 failed=1 shellcheck=ok only=51-templates
```

GREEN 4: `GATE-ONLY: PASS passed=1 failed=0 shellcheck=ok only=51-templates`, then `GATE-ONLY: PASS passed=1 failed=0 shellcheck=ok only=70-docs`.

## Full run

One full `tests/run`, alone, `BLAST_OFF_TEST_ONLY` unset, after the last edit to a tracked file: exit 0 after 212 s, 18 scenarios and shellcheck passed, no `FAIL` line.

```
PASS shellcheck (33 files)
GATE: PASS passed=18 failed=0 shellcheck=ok
```

Log: `/tmp/claude-1000/-home-alex-blast-off--claude-worktrees-pending-items-53932d/60b15296-819e-491a-8ffe-34b3bd988f86/scratchpad/fix1/full-gate.log` (under /tmp, not kept in the repo: a tenth touched file would have hit the unit's file limit).

**ExecStart check: OK**, before and after the run: `ExecStart=/home/alex/blast-off/.worktrees/blast-off-build/bin/blast-off run %f`.

A first attempt to start the full run did not start it: its "is another suite running" guard matched its own shell's command line and printed `ANOTHER SUITE IS RUNNING; full run not started`. No suite ran in that attempt, so the full suite ran exactly once.

Budget at hand-back: 49 tool calls, 9 files touched in the worktree (8 tracked, this file).

## Next steps

1. Review round 2: `scripts/gate.sh baton-runner/br-1115-issues/gate-phase-3-iter-2/`, once, alone. Read `lib/ci.sh:57-91` (`ci_check`) and `tests/41-ci-wait.sh` from `# --- runner: exit 10 at done ---` down.
2. Before the commit: the edit hook asked for the `skill-sheriff-cc` audit of `skills/blast-off` (one sentence of step 4 changed). Not run in this unit.
3. Put the four owner questions below to the owner; each has a default already in the code.

## Open questions / risks

1. **Owner, P3R1-1.** With no PR in any Status cell the runner reads every PR the checkpoint names. Alternatives not taken: (a) do that only when there is no Phase plan table (`cp_phases` is 0) and let a table whose rows name no PR pass with the log line; (b) refuse any done row whose Status cell names no PR. The default costs one thing: a job with no PR of its own that names another repo's PR as `PR #N` in prose is refused until the prose says `other PR N` (the log line says so).
2. **Owner, P3R1-3.** Which commit decides "runs were due": the workdir's HEAD at done (issue 26's words, the code), the PR's head, or its base? Today a workflow added in a later phase refuses the earlier stacked PRs, and an uncommitted workflow counts as none.
3. **Owner, P3R1-4.** Should only `*.yml` and `*.yaml` directly under `.github/workflows/` count, and should there be a logged owner override for a PR whose workflows never run on it (branch filter, dispatch-only workflow)? Today any file counts and there is no override.
4. **Owner, P3R1-2.** Where some Status cells name PRs, a PR named only under `Completed phases` is logged and not read. Refusing it would bring back issue 26's bug for another repo's PR.
- Not verified: the reworded docs were checked by 51-templates and 70-docs and by reading against `lib/ci.sh`; no reviewer has read them.
- The scratchpad copies (`fix1/red1`, `red2`, `base-M*`, `after-M*`, `full-gate.log`) are under /tmp and were left in place.

## References

- Issue: z0rd0n88/blast-off issue 26
- Review baton: `baton-runner/br-1115-issues/baton-phase-3-review-1.md`; report `baton-runner/br-1115-issues/review-phase-3-iter-1.md`
- Work baton: `baton-runner/br-1115-issues/baton-phase-3-work.md`
- Code: `lib/ci.sh:57-99`, `lib/chain.sh:137-159`, `tests/41-ci-wait.sh`, `tests/51-templates.sh:73-75`, `templates/checkpoint.md:29-32`, `docs/spec.md:97,228`
