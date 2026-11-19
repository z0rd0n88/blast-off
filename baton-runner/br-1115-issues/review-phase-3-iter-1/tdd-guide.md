### Summary

I reviewed commit b9c39ad (`lib/ci.sh`, `tests/41-ci-wait.sh`, `tests/fakes/gh`, `docs/spec.md`) against issue 26 and finding P2R1-1. All four behaviours are implemented and each has a live assertion: I measured that reverting either `ci_runs` call site, or dropping `event` from `--json`, breaks the PR 14 and PR 15 assertions, so the PR 15 half the implementer never saw red is not vacuous. The change also opens one hole I rate HIGH: a `done` with zero PRs read now passes with no log line, and the diff itself removes the CI read for table-less checkpoints, which the spec documents as supported. Eight mutants of the changed lines survive the tests, the new refusal has dead ends whose only exit is a silent bypass, and three docs outside the diff are stale, one of them child-facing and test-pinned.

**Rule breach to disclose:** my first `ci_check` snippet stubbed `gh` as a shell function, but `ci_head` calls it through `timeout`, so the real CLI ran. That was 5 calls of `gh pr view 7 --json headRefOid` in a non-git temp dir, each failing locally with `failed to run git: fatal: not a git repository`. Nothing was mutated; I discarded that batch and re-ran with a stub `gh` first on PATH.

**Method:** no scenario, no `tests/run`, no runner. I sourced `lib/ci.sh` read-only and copied it and `tests/fakes/gh` into my own temp dir (removed at the end), then ran `ci_check`, `ci_wait` and `ci_runs` as functions with `log`, `die` and `chain_end` stubbed. `git ls-tree` ran in throwaway repos there. The worktree is unchanged: the same 7 untracked `baton-runner/` paths as at the start.

### Findings

#### CRITICAL

None.

#### HIGH

**H1. `done` with zero PRs read passes silently, and the diff removes the CI read for table-less checkpoints**
- **Location:** `lib/ci.sh:66-67`; path `lib/chain.sh:159`; `docs/spec.md:21-22` (table-less documented), `docs/spec.md:97` (silent on it); no assertion in `tests/41-ci-wait.sh`.
- **Description:** Measured with `ci_check` under a stub `gh`, no CI record for PR 7 present. "Pre-diff" is the old whole-file grep copied from the diff.

  | Checkpoint | Pre-diff reads | Now reads | Result now |
  |---|---|---|---|
  | No Phase plan table, `PR #7` in `## Completed phases` | `7` (exit 10 unread) | nothing | `ci_check` returns 0, no log line |
  | Heading `## Phase Plan` (capital P), `PR #7` in the Status cell | `7` | nothing | returns 0, no log line |
  | Done row with no PR in Status, `PR #7` in `## Completed phases` | `7` | nothing | returns 0, no log line |
  | Normal row, `PR #7` in Status | `7` | `7` | exit 10 unread (control) |

  - Rows 1 and 2 are caused by this diff. For those checkpoints `cp_plan_rows` also returns nothing, so `receipt_check` and `receipt_all_done` are no-ops and `done` reaches `chain_end 0` with nothing read.
  - Row 3 is what criterion 3 asks for, but `templates/checkpoint.md:47` tells children to write `PR #<n>` in Completed phases and `:29` says "anywhere here" arms the gate (see M1).
  - In all three, `run.log` gets only `job done`. A reader cannot tell "CI read and green" from "no PR found, CI never read".
  - This answers the implementer's note: yes, the table-less case is a fail-open, and it is new.
- **Suggested fix:**
  - Log when the list is empty, for example `no PR named in a Phase plan Status cell; CI not read`, and pin that line in test 41.
  - For a checkpoint with no digit-keyed Phase plan row, either keep the old whole-file read or refuse. This is the owner's call; say which in spec row 10.
  - Missing tests: a table-less `done` checkpoint with a prose `PR #7`, and a done row with no PR in its Status cell.

#### MEDIUM

**M1. `templates/checkpoint.md:29-30` is now false, child-facing, and pinned by a test**
- **Location:** `templates/checkpoint.md:29-30`; `tests/51-templates.sh:74`.
- **Description:** The text says a `PR #<n>` or `/pull/<n>` link "anywhere here means this job's own PR: at done the runner wants a CI record for each". Only a Status cell counts now.
  - Direction: fail-open. A child that trusts it believes a mention in Completed phases arms the gate.
  - Its second sentence ("Name any other PR ... as `other PR <n>`, no '#'") is still safe, but it teaches the spelling that takes a PR out of the gate.
  - `tests/51-templates.sh:74` requires the phrase "means this job's own PR", so the stale sentence is enforced.
- **Suggested fix:** Reword to "`PR #<n>` or a /pull/<n> link in a row's Status cell names this job's PR ... a PR named anywhere else is not read", and change the pinned phrase in test 51 in the same commit.

**M2. The gate is opt-in by exact spelling in one cell; no check that a done row names a PR**
- **Location:** `lib/ci.sh:66-67`.
- **Description:** Measured: a Status cell of `PR 7`, `#7`, `PR  #7` (two spaces), `pull request #7`, `PR-7` or `.../pulls/7` reads no PR, and `done` passes. These spellings were unread before the diff too, so they are pre-existing, but before it the Completed phases mention was a second net and it is gone. The party being gated decides whether the gate runs.
- **Suggested fix:** Refuse or at least log a done row whose Status cell names no PR, or accept an explicit `no PR` marker. Missing test: one row per spelling.

**M3. Absent plus a workflow file refuses with dead ends; the only exit is a silent bypass**
- **Location:** `lib/ci.sh:73-74`.
- **Description:**
  - Measured: any file under `.github/workflows` at HEAD counts. With only `.gitkeep` there, `ci_check` exits 10 with "HEAD has a workflow file (.github/workflows/.gitkeep)". The same holds for `README.md` and `sub/nested.yml`, none of which GitHub runs.
  - Not reproduced (needs GitHub, so rated no higher): a PR gets no `pull_request` run when the workflow has a `branches: [main]` filter and the PR is stacked on a feature branch, when a `paths:` filter excludes it, when it has conflicts, when the workflow is `on: push/schedule/workflow_dispatch` only, or when the workflow was added in a later phase than that PR's head. `skills/blast-off/SKILL.md:34` prescribes "one stacked draft PR per phase", so the stacked case is the product's own delivery mode. It is also this repo's own build history (PRs 1-8 predate `ci.yml`).
  - In each case the message's remedy ("push, or re-run it") does nothing. No override is documented. The exit that works is removing `PR #N` from the Status cell, which then passes silently (H1).
- **Suggested fix:** Count only top-level `*.yml` and `*.yaml`. Document an owner override for a PR that can never get a run (for example an owner-written marker in the record, logged). Missing test: refusal, then the PR gets a run, `ci-wait`, `run` exits 0.

**M4. The allow condition reads the workdir's HEAD, which the gated child controls**
- **Location:** `lib/ci.sh:73`.
- **Description:** Measured: a HEAD with no `.github/workflows` gives empty `ls-tree` output at rc 0, and `ci_check` logs "absent, not a pass" and allows `done`. A branch that deletes or moves the workflow gets no runs and passes. The issue says "the repo has no workflow file"; the code checks only this branch's tip.
- **Suggested fix:** Also read the base (`origin/<JOB_BASE>`), and refuse when either has a workflow. Missing test: workflow on base, deleted at HEAD.

**M5. Eight mutants of the changed lines survive `tests/41-ci-wait.sh`**
- **Location:** `tests/41-ci-wait.sh:84-86,115,125-139`.
- **Description:**

  | Mutant | How judged | Why it survives |
  |---|---|---|
  | `$(NF-1)` changed to `$5` | measured on the `fin` fixture: `7 9` | fixtures are 4 columns with a trailing pipe |
  | Phase plan section range dropped (any digit-keyed row in the file) | measured: `7 9` | no digit-keyed row outside the section |
  | Digit-key filter dropped (every line of the section) | measured: `7 9` | no PR in a non-digit row |
  | `select(.event != "workflow_dispatch")` changed to `== "pull_request"` | measured: PR 14 absent rc 10, PR 15 success `[71]` | every fake run defaults to `pull_request`; no `push` run |
  | `\|\| die` after `ls-tree` changed to `\|\| true` | by reading | no fixture makes `ls-tree` fail |
  | Working tree read instead of HEAD | by reading | the file is both committed and on disk |
  | `git -C "$WORKDIR"` instead of `-C "$TOP"` | by reading; measured that from a subdir the pathspec returns nothing | workdir is the repo root in the `wf` job |
  | Pathspec `.github` instead of `.github/workflows` | by reading | the only file is `ci.yml` |

- **Suggested fix:** One fixture each: a 5-column table; a digit-keyed row with a PR in another section; a `P1` row with a PR; a `push`-event run; a file committed then deleted on disk (and the reverse); a job whose workdir is a subdirectory; a repo with only `.github/CODEOWNERS`.

**M6. `skills/blast-off/SKILL.md:34-35` describes the old behaviour**
- **Location:** `skills/blast-off/SKILL.md:34-35`.
- **Description:** It says that with no CI the runner lets `done` through, and tells the author to say so in brief §2. That is true now only when HEAD has no file under `.github/workflows`. Direction: fail-closed surprise. The brief promises the owner a pass and the job ends at exit 10.
- **Suggested fix:** Add "only where HEAD has no workflow file; with one, `done` is refused until the PR has a run".

#### LOW

**L1. `README.md:114-115`, `README.md:130` and `bin/blast-off:37` omit the new refusal**
- **Description:** All say "red or unread". None names absent-with-workflow or that "named" means a Status cell. `README.md:130`'s remedy ("fix CI, or run ci-wait after the last push") loops on absent: `ci-wait` records absent again. Direction: fail-closed surprise.
- **Suggested fix:** One clause each.

**L2. Another repo's `/pull/N` inside a Status cell is still read**
- **Location:** `lib/ci.sh:67`.
- **Description:** Measured: `done (abc1234) · PR #7, port of https://github.com/o/other/pull/55` with PR 7 green gives exit 10 "PR #55 CI unread". The issue's edge case survives inside the cell.
- **Suggested fix:** Match `/pull/N` only for the workdir's own repo, or document it.

**L3. `$(NF-1)` picks the wrong cell on other table shapes**
- **Description:** Measured: a row with no trailing pipe, an extra `Notes` column, or an escaped `\|` in Status reads no PR. These mostly fail closed through exit 9 (the row reads as open). When the last cell happens to start with "done", the row is done and no PR is read. `cp_plan_rows` has the same pre-existing convention.
- **Suggested fix:** Document "Status is the last cell" in the template comment; no code change needed.

**L4. The PR-list pipeline's status is discarded**
- **Location:** `lib/ci.sh:66` (`for pr in $(...)`).
- **Description:** Measured: a missing `checkpoint.md`, or a failing `awk`, gives zero PRs and `ci_check` returns 0. Earlier callers would normally stop first; nothing here does.
- **Suggested fix:** Assign the list to a variable with `|| die` before the loop.

**L5. The `ls-tree` failure path is untested**
- **Description:** Measured: an unborn HEAD gives rc 128 and `die` exits 1. That is fail-closed and correct, but it has no assertion and is absent from spec row 10.
- **Suggested fix:** One clause in the spec; a test is optional.

**L6. The refusal message says "re-run it"**
- **Location:** `lib/ci.sh:74`.
- **Description:** An absent PR has no run to re-run, and a re-run dispatch stays `workflow_dispatch`.
- **Suggested fix:** "push to the PR branch, or close and reopen the PR".

**L7. `--limit 100` is applied before the dispatch filter**
- **Location:** `lib/ci.sh:53`.
- **Description:** Dispatch runs use up list slots, so many diagnostics on one head can push PR runs out of the list.
- **Suggested fix:** Raise the limit, or note the ceiling.

**L8. The dispatch filter is fail-open by design for dispatch-driven CI; other non-PR events still count**
- **Description:** Where a repo's real CI is started by `workflow_dispatch`, a red run is ignored and any green `pull_request` run gives `success`. `schedule` and `repository_dispatch` runs on the same sha still count either way. The spec states the dispatch rule but not this consequence.
- **Suggested fix:** One sentence in the spec's `ci-wait` row.

**L9. `docs/spec.md:97` gaps**
- **Description:** It does not say that only digit-keyed rows are read, that a table-less checkpoint has no PR read, that a dispatch-only head records absent and is then refused, or that `ls-tree` failure exits 1.
- **Suggested fix:** Add the four clauses.

**L10. Test structure**
- **Location:** `tests/41-ci-wait.sh:132,119`.
- **Description:** The `wf` section copies its record from the `cmd` job and relies on fake state left by earlier lines (`pr-9-head` reset at `:112`, `hang-pr-7` still set from `:119`). The scenario stops at its first `fail`, so later halves of a new block are never seen red.
- **Suggested fix:** Build the `wf` record in place.

**L11. TDD evidence is thin for two criteria**
- **Description:** Criterion 2's RED was a log-wording change, not behaviour. The PR 15 half was never run red by the implementer; my measurement below covers it.
- **Suggested fix:** None needed beyond recording it.

**L12. A hand-edited record is trusted (pre-existing)**
- **Description:** Measured: a record with `verdict: absent` and a `failure` in `runs` passes where there is no workflow file. `ci_check` reads only `.verdict`. This is outside the diff.
- **Suggested fix:** Recompute the verdict from `runs` in `ci_check`, if the owner wants it.

#### Requested judgements

- **`templates/checkpoint.md:29-30`:** wrong now; errs fail-open; test-pinned (M1).
- **`skills/blast-off/SKILL.md:34-35`:** wrong where HEAD has a workflow file; errs fail-closed (M6).
- **`README.md:114-115`:** incomplete, not false; errs fail-closed (L1).
- **Table-less checkpoint:** yes, a fail-open, new in this diff, silent (H1).
- **Real `gh` and `--json databaseId,event`:** `gh run list --help` (gh 2.101.0) lists `event` under JSON FIELDS and has `-e, --event`. The field is confirmed. The value string `workflow_dispatch` is not shown in help and I could not run a real `gh run list` under the rules, so that part is inconclusive.
- **New dependencies:** no new tool, action or package. `git` and `awk` were already used. New reliance: the `event` JSON field of `gh run list`, the event string `workflow_dispatch`, and `git ls-tree -r --name-only HEAD -- <path>`.

### Validated

**Confirmed correct**
- **Criterion 4, first `ci_runs` call site** (`lib/ci.sh:20`): reverted to unfiltered, measured PR 14 rc 0 `success [61]` and PR 15 rc 10 `failure [71,72]`, with 4 dispatch watch/view calls. Killed by `tests/41-ci-wait.sh:72,74,75`.
- **Criterion 4, second call site** (`:30`): reverted, measured PR 14 rc 0 `success [61]` and PR 15 rc 10 `failure [71,72,73]`, 6 calls. Killed by the same lines.
- **Criterion 4, both reverted:** PR 15 rc 10 `failure [71,72,73]`. The PR 15 assertion at `:74` is live.
- **Criterion 4, `event` dropped from `--json`:** PR 14 `success [61]`, PR 15 `failure [71,72,73]`. Killed; the fake's "only fields asked for" rule (`tests/fakes/gh:28-29`) does its job.
- **Unmutated code:** PR 14 rc 10 `absent []`, PR 15 rc 0 `success [71]`, 0 dispatch watch/view calls.
- **Criterion 3, on the `fin` fixture text (`:84-86`):** the original pipeline reads `7 9`. Whole-row read gives `7 9 98`, killed by `:114`. Whole-file read gives `7 9 98 99`, killed. A prose-only read gives `99`, killed by `:89`.
- **Criterion 1** (`lib/ci.sh:73-74`, test `:137-139`): by reading, always-allow is killed by `:138`. Measured: `ls-tree` without `-r` prints `.github/workflows`, so that mutant is killed by the `(.github/workflows/ci.yml)` grep.
- **Criterion 2** (test `:114,116,134`): by reading, always-refuse is killed by `:114` and `:134`. Dropping the `[ -z "$TOP" ]` guard is killed by `:114`, because `git -C ""` in a non-git dir exits 128 (measured).
- **Shell options in `ci_runs`:** measured under `set -euo pipefail`. `gh` exit 1, `[]` with exit 1, non-JSON output and an error object all reach `die "gh run list failed"`. `[]` with exit 0 gives an empty list. A run with no `event` field is counted.
- **`wf="$(...)" || die`** (`lib/ci.sh:73`): `local wf` is declared separately at `:65`, so the substitution's status is not masked. Measured: unborn HEAD dies with rc 1; empty `TOP` gives empty `wf` and passes.
- **Spec rows F7, `ci-wait`, exit 10, `41-ci-wait`:** each matches the code as far as it goes (gaps in L9).
- **Static checks:** `shellcheck -S warning` and `bash -n` on the three changed scripts both exit 0.

**Examined, inconclusive**
- **Real `gh` event string** (`lib/ci.sh:54`): the field is listed in help; the value needs a real `gh run list` against a dispatched run.
- **GitHub run-creation cases in M3** (`lib/ci.sh:73-74`): base-branch filter, `paths:`, conflicts, later-added workflow. These need a real repository.
- **`tests/41-ci-wait.sh:125-139` end to end:** traced by reading (child 1 sets done, receipt fixture, `ci_head` against `pr-9-head`); I did not run it, by rule.

**Not examined**
- `lib/preflight.sh`, `lib/units.sh`, `lib/usage.sh` and `lib/child.sh`.
- The other fakes (`claude`, `jev`).
- `.claude/big-next-job.md`, beyond the grep that found no stale CI wording.
- The coordinator's own mutation runs and the full-gate log.

### Confidence

High on the measured items (H1, the dispatch mutants, the parser and `ls-tree` cases); medium on M3's GitHub-side cases, which one real PR with a `branches:` filter and one real dispatched run would settle.
