### Summary

I reviewed commit b9c39ad (`lib/ci.sh`, `tests/41-ci-wait.sh`, `tests/fakes/gh`, `docs/spec.md` rows F7, `ci-wait`, exit 10, `41-ci-wait`) against issue 26 and criteria 1 to 5, reading the changed files in full plus `bin/blast-off`, `lib/chain.sh`, `lib/checkpoint.sh`, `lib/receipt.sh`, `tests/lib.sh`, `ci.yml`, the templates, SKILL.md and README. The four criteria are implemented as written and the code on the changed lines fails closed on gh, jq and git errors. The problem is what criterion 3 costs: the CI gate now takes its list of PRs only from one cell that the gated child writes, and when that list is empty `done` goes through with no log line. Ten sample checkpoints that the phase-2 code refused with exit 10 now exit 0. That is one HIGH. The rest is MEDIUM and LOW: dead ends with no documented way out, a workflow check that reads local HEAD and not what GitHub runs, two stale child-facing or owner-facing docs, and test gaps on the fail-open-relevant lines. No injection, secret or new-tool issue found. I ran no test scenario; everything measured is from standalone snippets in a temp dir I created and removed.

One disclosure: my first snippet stubbed `gh` as a shell function, which `timeout` bypasses, so the real `gh pr view 9 --json headRefOid` ran 5 times in my non-git temp dir. Each failed locally with `failed to run git: fatal: not a git repository` before any API call. Nothing was mutated. It is outside the allowed gh list, so I am reporting it. I then used a stub script on PATH.

### Findings

#### CRITICAL

None.

#### HIGH

**H1. When no PR is read from a Status cell, `done` passes with no CI check and no log line (regression from phase 2)**
- **Location:** `lib/ci.sh:66-67` (the PR list), `lib/chain.sh:159`, `lib/receipt.sh:68-71`, `docs/spec.md:97`
- **Description:** `ci_check` loops over PRs found in the last cell of digit-keyed `## Phase plan` rows. Zero PRs means zero iterations and `chain_end 0 "job done"`. Nothing is logged. Measured with the exact pipeline and with `ci_check` sourced from the worktree (stubbed `log`, `chain_end`, no `gate-logs/ci-pr-9.json`): 10 of 10 sample checkpoints that phase-2's `ci_check` refused with exit 10 ("PR #9 CI unread") now exit 0 with 0 log lines from `ci_check`:
  - table-less checkpoint, `PR #9` in "Completed phases"
  - heading `## Phase Plan` (capital P)
  - heading `### Phase plan`
  - table indented by one space
  - row key `P1`
  - row key `**1**`
  - a `PR` column before Status (`| 1 | a | b | PR #9 | done (abc1234) |`)
  - Status `done (abc1234)` with the PR only in "Completed phases" (the template's own summary bullet carries `PR #<n>`)
  - a Notes column after Status
  - `PR #9 \| done (abc1234)` (escaped pipe)

  Answer to the table-less question: yes, it is a fail-open. Table-less checkpoints are documented as supported (`docs/spec.md:61`, `README.md:124` "hard child cap (no Phase plan table)", `lib/chain.sh:94-107`). In that mode the receipt gate was already off (no rows for `receipt_check` or `receipt_all_done` to see), so exit 10 was the only completion gate left, and this commit removes it. For the unseen-table variants the receipt gate does not help either: an unseen row is neither open nor done. The implementer listed this as an open risk; nobody decided it. Criterion 3 asks for Status-cell-only reading, so the code matches the criterion; the defect is that the gate has no floor and leaves no trace.
- **Suggested fix:** (1) Always log the set read at `done`: `CI read at done: PRs 7 9`, or `no PR named in a Phase plan Status cell; CI not read`. (2) With `cp_phases` = 0, keep the old whole-file read (a table-less checkpoint has no Status cell for criterion 3 to bind to), or decide and document that table-less jobs have no CI gate. (3) Log (or refuse) a done row whose Status cell names no PR. (4) Say in `docs/spec.md:97` that only digit-keyed rows are read and what a table-less checkpoint gets. (5) One test: table-less checkpoint with `PR #N` in prose.

#### MEDIUM

**M1. Absent is now refused with no way out when the workflow file can never give this PR a run**
- **Location:** `lib/ci.sh:73-74`, `README.md:130`, `skills/blast-off/SKILL.md:33-35`
- **Description:** Any file under `.github/workflows` at HEAD makes an absent record a refusal. Reproduced with `ci_check` against throwaway repos, each exit 10: a workflow with only `on: workflow_dispatch`; a directory holding only `README.md`; a workflow with `pull_request: branches: [main]`. The last matters most: SKILL.md prescribes "one stacked draft PR per phase", and a stacked PR whose base is the previous phase branch gets no run under a `branches: [main]` filter (GitHub behaviour, not run here). Same for `paths:` filters, schedule-only or `workflow_call`-only files, Actions disabled, a PR with merge conflicts. The message's remedy, "get the PR a run that is not a workflow_dispatch (push, or re-run it)", does not work in these cases: there is no run to re-run, and re-running a dispatch run keeps its event. The exits that do work are removing the PR from the Status cell (which lands in H1's silent bypass), hand-editing the record, or deleting the workflow. An unattended job stops at exit 10 with nothing in README telling the owner what to do.
- **Suggested fix:** Count only `*.yml`/`*.yaml` directly under `.github/workflows`. Say in the message and in `README.md:130` what to do when no run can exist. If an owner override is wanted, make it explicit and logged (for example an env var naming the PR), so the way out is not "delete the PR from the cell".

**M2. The workflow check reads the workdir's local HEAD, not what GitHub runs for the PR, so absent still passes where runs were due**
- **Location:** `lib/ci.sh:72-75`, `docs/spec.md:97`
- **Description:** Reproduced (git half): a repo whose HEAD has no workflow while branch `base` has `on: pull_request` gives exit 0 and logs "no CI runs and no workflow file at HEAD". For `pull_request`, GitHub takes workflows from the PR's merge ref, so a branch behind its base still gets runs (GitHub half not run here). Other cases with the same shape: organisation ruleset workflows (`gh run list --help` mentions them; no file in the repo), a workflow file in the work tree but not committed (reproduced: exit 0), and a workdir outside git with `GH_REPO` set (TOP empty skips the read). The exposure needs an absent record taken before the run was listed (`ci-wait` waits 60 s, or `BLAST_OFF_CI_APPEAR=0`), then a red run. The brief tells children to merge the base first, which narrows it.
- **Suggested fix:** Also read the PR base's tree (`gh pr view --json baseRefName`, then `git ls-tree origin/<base> -- .github/workflows`), or state the limit in the spec row and the log line.

**M3. `templates/checkpoint.md:29-30` is now false and children read it as instructions; a test pins the stale sentence**
- **Location:** `templates/checkpoint.md:29-30` (and `:26`), `tests/51-templates.sh:72-74`
- **Description:** It says a `PR #<n>` or `/pull/<n>` "anywhere here means this job's own PR: at done the runner wants a CI record for each". Now only a Status cell counts. Direction: mixed. The claim that a mention anywhere is gated errs fail-open: a child that names the PR only in "Completed phases" believes CI is enforced and it is not (H1, sample 8). The advice to write other PRs as `other PR <n>` errs fail-closed and is now needed only inside Status cells. Line 26, "Add `PR #<n>` after it", is now the single instruction that turns the CI gate on, and it gives no reason. `tests/51-templates.sh:74` asserts the phrase "means this job's own PR", so fixing the template means changing that test.
- **Suggested fix:** Reword to: the runner reads this job's PRs only from Status cells; a PR not named there gets no CI check at done; elsewhere any PR may be named freely. Update the pinned phrase in test 51.

**M4. `skills/blast-off/SKILL.md:34-35` promises the old behaviour**
- **Location:** `skills/blast-off/SKILL.md:34-35`
- **Description:** "with no CI, `blast-off ci-wait` records `absent` and exits 10, and the runner lets `done` through logged 'absent, not a pass': say so in brief §2". True now only where HEAD has no workflow file. Direction: the doc is more permissive than the code. No security hole, but the skill writes this into brief §2, so children are told absent is tolerated and the job then stops at exit 10 unattended (M1).
- **Suggested fix:** "...lets `done` through only when HEAD has no file under `.github/workflows`; with one, `done` is refused (exit 10)."

**M5. Test gaps on the lines that decide fail-open (mutants that survive by reading; not run, no test runs allowed)**
- **Location:** `tests/41-ci-wait.sh:124-139`, `:27-32`, `:68-75`
- **Description:**
  - `git -C "$TOP"` changed to `git -C "$WORKDIR"`: survives, because the fixture's workdir is the repo root. That mutant is a fail-open: from a subdirectory `git ls-tree -r --name-only HEAD -- .github/workflows` printed nothing with rc 0 in my throwaway repo.
  - `ls-tree` failure swallowed (`|| true`): survives. The code comment at `lib/ci.sh:72` claims a failed read is not "no workflow"; no test makes the read fail. (By snippet the shipped code dies with exit 1 on a non-repo TOP and on an unborn HEAD.)
  - HEAD replaced by the work tree (`[ -d .github/workflows ]`): survives, the fixture commits the file.
  - `select(.event != "workflow_dispatch")` changed to `select(.event == "pull_request")`: survives, the fixtures hold only those two events. That mutant drops a red `push` run (snippet: shipped keeps ids `71 80`, mutant keeps `71`).
  - Reading Status cells of any table, not only under `## Phase plan`: survives, the fixtures have one table.
- **Suggested fix:** One fixture each: workdir a subdirectory of the repo; a run with `event-<id>` = `push` and conclusion failure (expect failure); a workflow file present but uncommitted or a broken TOP.

#### LOW

**L1. README and the CLI header do not name the absent refusal**
- **Location:** `README.md:114-115`, `README.md:130`, `bin/blast-off:37`
- **Description:** All three say exit 10 is "red or unread". Not wrong, incomplete: absent with a workflow file is now a third cause, and the "What to do" cell has no remedy for it. Errs toward under-describing refusals (owner surprise), not fail-open.
- **Suggested fix:** Add "or absent while HEAD has a workflow file" and the remedy.

**L2. The PR pipeline's failure is discarded, and a NUL byte empties the list**
- **Location:** `lib/ci.sh:66-67`
- **Description:** `for pr in $(sed | awk | grep | sed | sort)` ignores the pipeline's status, so a failing `sed` or `awk` reads as "no PRs" and `done` passes. Reproduced one input that does it: a Status cell holding a NUL byte gives an empty list under `LC_ALL=C` and `C.UTF-8`, with only `grep: (standard input): binary file matches` on stderr. A Latin-1 0xB7 byte did not trigger it (PRs still read). The old code had the same weakness over the whole file.
- **Suggested fix:** `prs="$(...)" || die`, and `grep -a`.

**L3. Spellings in the Status cell that are silently not read**
- **Location:** `lib/ci.sh:67` (regex unchanged by this diff)
- **Description:** Reproduced, each read as no PR: `PR  #9` (two spaces), `PRs #9, #10`, bare `#9`, `PR 9`, `PR<nbsp>#9`, `pull request #9`, `o/r#9`. `PR #9, #10` reads 9 only. The regex is old; before this diff a correct mention elsewhere in the file still caught the PR, now the cell is the only source.
- **Suggested fix:** Covered by H1's log line; optionally accept `#N` after a `PR` word list.

**L4. A row without its trailing pipe shifts the cell read**
- **Location:** `lib/ci.sh:66` (`$(NF-1)`, same as `lib/checkpoint.sh:41`)
- **Description:** `| 1 | a | b | done (abc1234) · PR #9` (no closing pipe) reads cell "b": the row counts as open and `done` is refused with exit 9 (fail-closed, misleading message). If "Done when" itself starts with "done", the row counts as done and no PR is read: exit 0 outside git (reproduced); inside git exit 9 for a missing sha.
- **Suggested fix:** Strip a missing trailing pipe before splitting, in one shared helper.

**L5. `--limit 100` is applied before the dispatch filter**
- **Location:** `lib/ci.sh:53-54`
- **Description:** The filter is client-side. 100 newer `workflow_dispatch` runs on the head push the PR's own runs off the list. Result is absent (refused where HEAD has the workflow), so it mostly fails closed, but a red older run can drop out while a newer green one stays. Needs write access.
- **Suggested fix:** Raise the limit or note it.

**L6. Ignored dispatch runs leave no trace**
- **Location:** `lib/ci.sh:36-45`, `:52-55`
- **Description:** The record and the `ci PR #N ...` log line do not say that runs were left out. An owner who sees "absent" on a head with a green dispatch run has only the `done`-time message to explain it.
- **Suggested fix:** Log the count of dispatch runs left out.

**L7. By design, a red dispatch run no longer blocks**
- **Location:** `lib/ci.sh:49-55`
- **Description:** Criterion 4 asks for this. In a repo whose real PR tests are started by dispatch (a "/test" bot) with a cheap `pull_request` lint, a red test run plus a green lint now records success. Recorded so the owner sees the trade.
- **Suggested fix:** None, or a spec sentence.

**L8. Spec row 10 omissions**
- **Location:** `docs/spec.md:97`
- **Description:** It does not say that only digit-keyed rows are read, that a table-less checkpoint has no PR read, that a failing `git ls-tree` is exit 1, or that any file under the directory counts. The rest of the four edited rows matches the code.
- **Suggested fix:** One clause each.

**L9. The fake `gh pr view` works outside a git repo; the real one does not**
- **Location:** `tests/fakes/gh:20-21`, `tests/41-ci-wait.sh:81-122`, `docs/spec.md:97` ("or the workdir is in no git repo")
- **Description:** The whole "runner: exit 10 at done" section runs in a non-git workdir. Real `gh pr view 9` there fails with "failed to run git: fatal: not a git repository" (observed, see Summary), so `ci_head` would refuse first. The spec's "no git repo" pass branch is reachable only with `GH_REPO` or similar, and then it skips the workflow check for a repo that may have workflows (M2).
- **Suggested fix:** Note it in the spec, or drop the branch and treat TOP empty as unread.

**L10. `ci_runs` depends on the caller's `pipefail`**
- **Location:** `lib/ci.sh:52-55`
- **Description:** With `pipefail` (set at `bin/blast-off:38`) a failing `gh` dies. Without it, by snippet, a failing `gh` returns an empty list and no die, which would read as absent. Correct today, fragile if the function is reused.
- **Suggested fix:** `local out; out="$(gh ...)" || return 1`, then jq.

### Validated

**Confirmed correct**
- Criterion 1: `ci_check` with an absent record of the current head and `.github/workflows/ci.yml` at HEAD gives `chain_end 10 "PR #9 CI absent: no runs, but HEAD has a workflow file (...)"` (snippet against a throwaway repo; `lib/ci.sh:73-74`).
- Criterion 2: same record, repo with no `.github` at HEAD: exit 0 and log "PR #9: no CI runs and no workflow file at HEAD (absent, not a pass)" (snippet; `lib/ci.sh:75`).
- Criterion 3: template-shaped row reads PR 9; prose and other cells are not read (pipeline snippet over 26 sample checkpoints; `tests/41-ci-wait.sh:84-86,115`). CRLF, trailing whitespace after the last pipe, the runner's `· usage` suffix, a markdown link and a heading with trailing text all still read the PR.
- Criterion 4: `ci_runs` drops `workflow_dispatch` and keeps `pull_request`, `push`, `schedule`, `repository_dispatch`, `workflow_run`, `dynamic`, and runs with a missing or null `event` (snippet with stub gh output). Both list calls use it (`lib/ci.sh:20,30`); the test pins both, since run 73 is listed only on the re-list (`tests/41-ci-wait.sh:30-32,73-75`).
- gh and jq error handling in `ci_runs` under `set -euo pipefail`: gh rc 1 with or without output dies; non-array JSON and HTML die (jq error through pipefail); `[]` and empty stdout give an empty list, which becomes absent, not success (snippet, 11 cases).
- Verdict jq: no runs is "absent"; cancelled, empty and null conclusions are "failure" (snippet; `lib/ci.sh:40-42`).
- `git ls-tree` failure does not read as "no workflow": non-repo TOP and unborn HEAD both die with exit 1; TOP empty skips the read (snippet; `lib/ci.sh:73`). `local wf` is declared on its own line, so the `||` sees the substitution's status.
- `ci_head` runs before the workflow check on an absent record, so a moved head or a gh failure still refuses (`lib/ci.sh:71`).
- No injection: `$pr` can only be digits after the fixed regex and `sed 's/.*[#/]//'`; `$sha` is checked against `^[0-9a-f]{40}$`; the workflow path goes only into a log string.
- Real gh supports the call: `gh run list --help` on this box (gh 2.101.0) lists `databaseId` and `event` under JSON FIELDS and has `-c/--commit`, `-L/--limit`, `-e/--event`.
- New dependencies: none. `git ls-tree` (git is already in `DEPS`, `lib/chain.sh:84`), `awk` (already used by `lib/checkpoint.sh`, not in `DEPS`, pre-existing), one more gh JSON field. No new action, package or tool. The test adds `git init`/`commit` with `-c user.*`.
- The fake prints `event` only when `--json` asks for it (`tests/fakes/gh:28-29`), so dropping `event` from the real call would turn the PR 14 case red.
- `bash -n lib/ci.sh` ok; `shellcheck -S warning lib/ci.sh tests/fakes/gh` ok (0.11.0).
- `docs/spec.md` rows 35, 58, 97, 228 match the code, apart from L8.

**Examined, inconclusive**
- The live `event` string for a dispatch run (`workflow_dispatch`): `lib/ci.sh:54`. Blocker: no real `gh run list` call allowed; it is the GitHub API's event name and the `-e` flag takes the same names.
- GitHub behaviours behind M1 and M2 (no run for a base not matching `branches:`, workflows taken from the merge ref, ruleset workflows): blocker is that they need a live repo.
- That `41-ci-wait`, `51-templates` and `70-docs` pass on this commit: `tests/41-ci-wait.sh` read in full and traced by hand, not run (rule). The M5 mutants are judged by reading, not run.
- User-manager locale for L2: `systemctl --user show-environment` shows `LANG=C.UTF-8` on this box; other hosts not checked.

**Not examined**
- `lib/` files other than `ci.sh`, `chain.sh`, `checkpoint.sh`, `receipt.sh` (child, units, usage, jev, preflight).
- `templates/brief.md` beyond the CI and close-order lines (109, 120-165).
- `docs/spec.md` outside the four changed rows and line 61.
- `baton-runner/` beyond `baton-phase-3-work.md` and `baton-phase-2-review-1.md`.

### Confidence

High on H1, M1, the git half of M2, L2 to L4 and the Confirmed list (each run as a snippet); medium on M5 and the GitHub-side claims, which a coordinator-run mutant pass and one live PR with a dispatch run would settle.
