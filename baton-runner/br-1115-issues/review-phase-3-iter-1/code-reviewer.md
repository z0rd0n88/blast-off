### Summary

I reviewed commit b9c39ad (`lib/ci.sh`, `tests/41-ci-wait.sh`, `tests/fakes/gh`, `docs/spec.md`) against issue 26 and finding P2R1-1, reading the four changed files in full plus `bin/blast-off`, `lib/chain.sh`, `lib/checkpoint.sh`, `lib/receipt.sh`, `tests/lib.sh`, `ci.yml`, both templates, the skill, the README and the implementer's baton. All five acceptance criteria are implemented as written and the new code paths fail closed on every gh, jq and git error I could inject. The change still opens one real hole in the completion gate: when zero PR tokens are parsed from Status cells, `done` exits 0 with no CI read and no log line. Five sample checkpoints that the old code refused with exit 10 now pass in a git workdir, and seven pass outside git. That follows from criterion 3, so the fix is additive (a log line, a spec sentence, a test), not a revert. The second cluster is fail-closed: the workflow check refuses on any file under `.github/workflows`, the refusal's remedy text is not a way out in several cases, and three unedited docs now contradict the code. I ran no test scenario; all numbers come from standalone snippets in my own temp dir.

Disclosure: one snippet batch called the real `gh pr view 7 --json headRefOid` nine times, because `timeout gh ...` in `ci_head` bypassed my shell-function stub. Eight ran in throwaway repos with no remote ("no git remotes found") and one in a non-git dir ("not a git repository"), so all failed locally before any network call. That is outside the gh allowlist. I reran with a stub `gh` on PATH; the results below are from the rerun.

Repro material is in `/tmp/claude-1000/-home-alex-blast-off--claude-worktrees-pending-items-53932d/60b15296-819e-491a-8ffe-34b3bd988f86/scratchpad/rev3.8abnDc` (`pipes.sh`, `harness2.sh`, `runs.sh`, sample `*.md`, throwaway repos). `harness2.sh` sources copies of `checkpoint.sh`, `receipt.sh` and old/new `ci.sh` and runs `receipt_check; receipt_all_done; ci_check; chain_end 0` with stubbed `log`, `die` and `chain_end`, against a repo with a workflow at HEAD and a hand-built valid receipt.

### Findings

#### CRITICAL

None.

#### HIGH

- **Title:** Zero PRs parsed from Status cells means `done` exits 0 with no CI read and no log line
- **Location:** `lib/ci.sh:66-67` (the `for pr in $(...)` list), reached from `lib/chain.sh:159`
- **Description:** The gate now exists only if a done row's last cell holds `PR #N`, `PR#N` or `/pull/N`. When the list is empty the loop body never runs and the runner logs `job done`. Nothing says CI was not read. Measured with `harness2.sh`, no `ci-pr-7.json` present, workflow at HEAD, old code vs new:

  | Sample checkpoint | Old, git | New, git | Old, no git | New, no git |
  |---|---|---|---|---|
  | Done row `done (<sha>)`, `PR #7` only under Completed phases | 10 | 0 | 10 | 0 |
  | No Phase plan table, `PR #7` in prose | 10 | 0 | 10 | 0 |
  | Heading `### Phase plan` | 10 | 0 | 10 | 0 |
  | Row indented by one space | 10 | 0 | 10 | 0 |
  | Row key `A` (no digit) | 10 | 0 | 10 | 0 |
  | Fifth column whose cell starts `done`, PR in column 4 | 9 | 9 | 10 | 0 |
  | No trailing pipe, "Done when" cell starts `done` | 9 | 9 | 10 | 0 |

  That is 5 flips from exit 10 to exit 0 in a git workdir and 7 outside git. The two malformed rows are saved in git only by `lib/receipt.sh:53` (empty row sha, exit 9), which is off outside git. The child-side route is plain omission at phase close: a child that skips `ci-wait` and writes `done (<sha>)` without the PR token passes, even if it names the PR in Completed phases as `templates/checkpoint.md:47` prompts. `templates/checkpoint.md:29-30` still tells every child that a PR named "anywhere here" is checked. There is no test for an empty PR list and no spec sentence for it.
- **Suggested fix:** Keep criterion 3. Add one log line when the list is empty at done, for example `no PR named in a Phase plan Status cell: CI not read`, and one listing the PRs that were read. Add the sentence to spec row 10 and a `41-ci-wait` case. Stronger option for the owner: refuse `done` when a done row names no PR while HEAD has a workflow file.

#### MEDIUM

- **Title:** Table-less checkpoints lose the CI gate entirely (asked judgement: yes, this is a fail-open)
- **Location:** `lib/ci.sh:66`; `docs/spec.md:61`, `:91` (exit 4 row); `lib/chain.sh:96-106`
- **Description:** The spec documents a checkpoint with no Phase plan table as supported (hard cap). Such a job has no done rows, so `receipt_check` is already vacuous, and CI was its only gate at done. Reproduced: the table-less sample with `PR #7` in prose gave exit 10 on the old code and exit 0 on the new, in git and outside it. Same root cause as the HIGH finding; listed separately because it was asked.
- **Suggested fix:** The log line above covers it at minimum. If the owner wants a gate here, fall back to the old whole-file read only when `cp_phases` is 0, and say which in spec row 10.

- **Title:** Absent plus any file under `.github/workflows` is a dead end whose printed remedy often does not work
- **Location:** `lib/ci.sh:73-74`
- **Description:** Measured: a repo whose only workflow is `on: workflow_dispatch` gives exit 10; a repo with only `.github/workflows/README.md` gives exit 10 naming that file. The message says "get the PR a run that is not a workflow_dispatch (push, or re-run it)". With an absent record there is nothing to re-run. Reasoned, not tested on GitHub: a re-run of a dispatch run keeps its event; a `pull_request: branches: [main]` filter never fires for the stacked PRs that `templates/brief.md:108` mandates; a workflow added mid-job never runs for earlier phase PRs (the case in `docs/decision-log/build-2026-11-04.tsv:24`, PRs with no CI until phase 8). In those cases the only exits are owner actions: drop the `PR #N` token from the Status cell or reword it to `PR 7` (both measured: exit 0, silent), hand-edit the record, or delete the workflow. So the practical escape from this refusal is the HIGH finding's hole.
- **Suggested fix:** Reword the message to name the real options. Give the owner one explicit, logged override instead of the silent token edit. Count only `*.yml` and `*.yaml` files.

- **Title:** `templates/checkpoint.md:29-30` is now false and errs fail-open (asked judgement)
- **Location:** `templates/checkpoint.md:29-30`
- **Description:** It says a `PR #<n>` or `/pull/<n>` "anywhere here means this job's own PR: at done the runner wants a CI record for each". Now only a Status cell counts. Every job checkpoint is built from this template and children read the comment as the runner's rules, so it gives false assurance that a PR named in prose is gated. Its advice to write other PRs without `#` is still needed inside Status cells and is harmless elsewhere. `tests/51-templates.sh:31` pins only the substring `PR #<n>`, so rewording will not break it.
- **Suggested fix:** "Only `PR #<n>` or a /pull/<n> link in a row's Status cell is read: at done the runner wants a CI record for each (exit 10). A done row with no PR there gets no CI check."

- **Title:** `skills/blast-off/SKILL.md:34-35` is now wrong for repos with a workflow file and errs fail-closed (asked judgement)
- **Location:** `skills/blast-off/SKILL.md:34-35`
- **Description:** It says that with no CI the runner lets `done` through, and tells the planner to say so in brief §2. True now only when HEAD has no workflow file. Where a workflow exists but a PR gets no run, the planner promises a pass and the job ends at exit 10 after every phase is finished.
- **Suggested fix:** State both cases: no workflow file at HEAD passes, logged; a workflow file with no run refuses `done` (exit 10).

#### LOW

- **Title:** `README.md:114-115`, `README.md:130` and `bin/blast-off:37` omit the absent case (asked judgement: stale by omission, errs fail-closed)
- **Location:** `README.md:114-115`, `README.md:130`, `bin/blast-off:37`
- **Description:** All three say `done` is refused when CI is "red or unread". Absent with a workflow file is now a third refusal, and the README row's "what to do" has no remedy for it. "A named PR" is also looser than "named in a Status cell", which errs fail-open for a reader. `tests/70-docs.sh` checks only that the codes exist.
- **Suggested fix:** "red, unread, or absent while HEAD has a workflow file", with the remedy.

- **Title:** Spec row 10 does not state the zero-PR consequence or the exit 1 on a failed `ls-tree`
- **Location:** `docs/spec.md:97`, `docs/spec.md:35`
- **Description:** The row is accurate for what it covers. It does not say a done row with no PR token, or a table-less checkpoint, gets no CI check, nor that a failing `git ls-tree` ends the runner with exit 1 (measured on an unborn HEAD: `fatal: Not a valid object name HEAD`, die, exit 1).
- **Suggested fix:** One clause each.

- **Title:** With no git repo the log claims "no workflow file at HEAD" though nothing was read
- **Location:** `lib/ci.sh:73-75`
- **Description:** Measured with `TOP` empty: `PR #7: no CI runs and no workflow file at HEAD (absent, not a pass)`, exit 0. A non-git workdir can still reach a repo with workflows through `GH_REPO`. The spec documents the skip; the log wording is untrue.
- **Suggested fix:** Log "workdir is in no git repo; workflow files not read" on that path.

- **Title:** `--limit 100` is applied before the client-side dispatch filter
- **Location:** `lib/ci.sh:53-54`
- **Description:** Dispatch runs use up the 100 slots before they are filtered out. Needs 100 or more runs on one commit; not reproduced.
- **Suggested fix:** Accept, or note the ceiling in a comment.

- **Title:** Records written before this change that counted a dispatch run are still accepted
- **Location:** `lib/ci.sh:68-70`
- **Description:** A `success` record made from a green dispatch run on the current head still passes `ci_check`. Affects only jobs in flight across the upgrade.
- **Suggested fix:** Accept, or note it in the PR body.

- **Title:** Test gaps in `tests/41-ci-wait.sh` (mutants that would survive)
- **Location:** `tests/41-ci-wait.sh:124-139` and the file as a whole
- **Description:** Each by reading, not run:
  - Empty PR list at done (table-less, or a done row with no token): no case in either direction.
  - `git -C "$TOP"` changed to `git -C "$WORKDIR"`: survives, because the fixture's workdir is the repo root. Measured: from a subdirectory the same `ls-tree` prints nothing, which would be a fail-open.
  - HEAD changed to the working tree: survives, because the fixture commits the file.
  - The `ls-tree` die at `:73` changed to pass: no case.
  - `gh run list` failing inside `ci_runs`: no case.
  - Non-YAML file under `.github/workflows`: no case.
  - The implementer's baton says the PR 15 half was never seen red. By reading, an unfiltered re-list would watch run 73 and record a failure, so `:74` would catch it.
- **Suggested fix:** Add the empty-list case and a workdir-in-a-subdirectory case; the rest are optional.

- **Title:** The `fin` fixture now depends on the scenario dir being outside any git repo
- **Location:** `tests/41-ci-wait.sh:81-86`; `tests/run:48`
- **Description:** `fin` now has done rows with the fake sha `abc1234` and no receipt. `tests/run` uses `mktemp -d`, so with `TMPDIR` inside a git repo `TOP` is set and the scenario would exit 9. Before the diff the fixture had no done rows.
- **Suggested fix:** A comment, or accept.

- **Title:** Outside the diff: PR-token forms that read as no PR, now more exposed
- **Location:** `lib/ci.sh:67` (regex unchanged by this commit)
- **Description:** Measured, old and new alike: `PR 7`, `PRs #7, #8`, `PR: #7`, two spaces, bare `#7`, `pull request #7`, `PR **#7**` and `o/r#7` read no PR; `PR #7, #8` reads 7 only; `PR #0` reads none. Before, a second mention elsewhere in the file often caught these; now the cell is the only source.
- **Suggested fix:** Covered by the empty-list log line; optionally accept `#N` after `PR`.

- **Title:** Outside the diff: other pre-existing fail-open shapes seen while tracing
- **Location:** `lib/ci.sh:66-68`
- **Description:** A failing stage in the `for pr in $(...)` pipeline is swallowed and gives an empty list (measured with an unreadable file: loop ran 0 times, script continued). A hand-edited record with `verdict: success` over a red run passes (measured, exit 0). Neither is new.
- **Suggested fix:** None required for this phase.

- **Title:** New dependencies (asked judgement): none beyond one CLI field
- **Location:** `lib/ci.sh:53`, `:73`; `tests/41-ci-wait.sh:127,136`
- **Description:** New reliance: the `event` JSON field of `gh run list` and the string `workflow_dispatch`; `git ls-tree -r --name-only` (git is already in `DEPS`); `awk` in `ci.sh` (already used in `checkpoint.sh`); `git init` and commit in scenario 41. No new tool, package, flag family or action; `ci.yml` is untouched.
- **Suggested fix:** None.

### Validated

- **Confirmed correct:**
  - Criterion 1: absent record plus workflow at HEAD gives exit 10 with the file named (`harness2`-style run: `END 10: PR #7 CI absent: no runs, but HEAD has a workflow file (.github/workflows/ci.yml)`). Old code on the same input: exit 0.
  - Criterion 2: absent record, repo with no workflow file, gives the log line and exit 0. A workflow present only uncommitted in the worktree also gives exit 0 (HEAD is read, as the issue says). `.circleci` and `.github/workflows-old` do not count.
  - Criterion 3: `lib/ci.sh:66` uses the same sed range and `$(NF-1)` as `cp_plan_rows` (`lib/checkpoint.sh:40-41`). In 35 sample checkpoints, PRs in prose, another cell or an HTML comment were not read; CRLF, trailing spaces and a ` · usage` suffix still read the PR.
  - Criterion 4: `ci_runs` under `set -euo pipefail` with stubbed gh, 12 cases. Mixed events gave ids 6 7 8 9 10 with the dispatch id 5 dropped. gh exit 1, gh exit 1 with JSON on stdout, non-JSON, an object instead of an array, and "Unknown JSON field" all end in `DIE: gh run list failed`, exit 1. Empty output and `[]` give an empty list (absent). No fail-open found.
  - Shell options: `local wf` is declared apart from the assignment at `:65`/`:73`, so the `|| die` sees git's status. Unborn HEAD dies with exit 1.
  - `shellcheck -S warning lib/ci.sh tests/41-ci-wait.sh tests/fakes/gh`: exit 0. `bash -n lib/ci.sh`: ok.
  - `gh run list --help` on this box (gh 2.101.0) lists `event` among the JSON fields and has `-e, --event`.
  - Gate logs `baton-runner/br-1115-issues/phase-3/full-gate.log` and `gate-phase-3-iter-1/tests-run.log` both end `GATE: PASS passed=18 failed=0 shellcheck=ok`.
  - Spec rows F7, `ci-wait`, exit 10 and `41-ci-wait` match the code for what they state.
  - `tests/51-templates.sh` and `tests/70-docs.sh` do not pin the stale doc strings.
- **Examined, inconclusive:**
  - The `event` string value (asked judgement). `lib/ci.sh:54` compares against `workflow_dispatch`; the fake (`tests/fakes/gh:28`) encodes the same assumption. I could not list a real run under the rules. If the real value differed, the filter would never match and dispatch runs would count again (fail-open for a green dispatch, as P2R1-1 described). If an older gh lacks the field, it fails closed with exit 1. Needs one real `gh run list --commit <sha> --json databaseId,event` on a commit with a dispatch run.
  - Whether GitHub creates a run in the dead-end cases (branch filters on stacked PRs, a workflow added mid-job, a re-run keeping its event): reasoning from GitHub's documented behaviour, not observed.
  - Scenario 41 as a whole: not run by me (rule). Mutant verdicts in the test-gap finding are by reading `tests/41-ci-wait.sh:71-75, 113-116, 133-139`.
  - Implementer's "each test seen red": the baton shows red output for criteria 1, 3 and 4 (PR 14 half) and a wording-only red for criterion 2; not re-run.
- **Not examined:**
  - `lib/child.sh`, `lib/usage.sh`, `lib/units.sh`, `lib/jev.sh`, `lib/preflight.sh` beyond a grep.
  - `ci_wait` lines 24-46 beyond the two changed list calls.
  - Behaviour on a real GitHub repo, and on gh versions other than 2.101.0.
  - Partial or treeless clones for the `ls-tree` read.

### Confidence

High on the code-path findings (each has a measured exit code); medium on the GitHub-side dead-end reasoning and the `event` string, which one real `gh run list` on a dispatch-run commit and one stacked-PR run would settle.
