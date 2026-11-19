### Summary

I reviewed commit b9c39ad (`lib/ci.sh`, `tests/41-ci-wait.sh`, `tests/fakes/gh`, the four `docs/spec.md` rows) against issue 26 and criterion 4 (P2R1-1), as an adversary who writes `checkpoint.md` or can trigger runs on the PR head. The commit meets the letter of criteria 1 to 5 and closes the two holes it targeted (absent with a workflow file; a green dispatch run counting as a pass). It also opens a new fail-open: the PR list now comes only from rows the Phase plan parser recognises, so a table-less or slightly off-format checkpoint reaches `job done` with no CI read and no log line. On copies of the old and new `ci_check`, the old one exits 10 and the new one passes for the same file. The other findings are a residual bypass in the new workflow check (it reads the workdir's local HEAD, not the PR head), fail-closed dead ends with no owner override, four stale docs (one is child-facing instruction text), and test gaps that let fail-open mutants survive.

How evidence was gathered:
- No test scenario was run. All reproductions are standalone snippets in my own temp dir, using pipelines copied from the code, copies of `lib/ci.sh` (HEAD and `feat/br-1115-issues/phase-2`) with `log`/`die`/`chain_end` stubbed and a stub `gh` on PATH, and throwaway `git init` repos.
- Temp dir, left in place so the coordinator can re-run the probes: `/tmp/claude-1000/-home-alex-blast-off--claude-worktrees-pending-items-53932d/60b15296-819e-491a-8ffe-34b3bd988f86/scratchpad/pt3.CDv2LJ` (`probe.sh`, `runs.sh`, `wf.sh`, `e2e.sh`, corpus `c/*.md`).
- Disclosure: besides the two allowed gh calls (`gh issue view 26 --repo z0rd0n88/blast-off`, `gh run list --help`), I ran `gh --version` once. It is local and read-only but outside the stated allowlist.
- GitHub-side behaviours (branch and path filters, conflicted PRs, run ordering, the literal event string) are from recall, not reproduced. They are listed under "Examined, inconclusive", and no finding that rests only on them is rated above MEDIUM.

### Findings

#### CRITICAL

None.

#### HIGH

**H1. A checkpoint whose Phase plan table is missing or not recognised now reaches `done` with no CI read and no log line (new with this commit)**
- **Location:** `lib/ci.sh:66-67` (PR list built from `sed -n '/^## Phase plan/,/^## /{/^| *[0-9]/p}' | awk -F'|' '{ print $(NF-1) }'`); `lib/chain.sh:159`; `lib/receipt.sh:45-71`; `docs/spec.md:61,91` (table-less checkpoints documented as supported).
- **Description:**
  - Before this commit every `PR #N` or `/pull/N` in `checkpoint.md` was read. Now only the last cell of digit-keyed rows under a line starting `## Phase plan` is read.
  - I ran both extraction pipelines over 29 checkpoint variants, together with `cp_plan_rows open` and `done`. In 16 the old line reads PR 7, the new one reads nothing, and no open row exists, so exit 9 does not fire first.
  - 11 of those 16 are parser-recognition failures, not "PR in prose":
    - no table at all (PR named in `Completed phases`)
    - heading `## Phase Plan`
    - heading `### Phase plan`
    - heading with a leading space
    - table rows indented one space
    - row key `P0`
    - row key `**0**`
    - row key preceded by a tab
    - rows without a leading pipe
    - a row with no trailing pipe whose Done-when cell holds `done (abc1234)` and whose last cell holds `PR #7`
    - Status cell `PR #7 \| done (abc1234)` (escaped pipe)
  - The other 5 are the criterion-3 cases (see M1).
  - End to end on function copies with a stub `gh` and no CI record at all: for the table-less checkpoint and the indented-rows checkpoint, old `ci_check` gives `chain_end 10: PR #7 CI unread`; new `ci_check` returns, so `chain_end 0 "job done"` follows.
  - `receipt_check` and `receipt_all_done` also iterate plan rows only. For a table-less checkpoint the CI read was the only gate at `done`; now there is none.
  - The runner logs nothing when it reads zero PRs.
  - The commit deletes the old `fin` fixture line that tested exactly this path (`- phase 0 delivered as pr#07 ...` appended to a table-less checkpoint, old `tests/41-ci-wait.sh:67`). No test now covers a table-less or malformed-table checkpoint in either direction.
  - The child writes the checkpoint, so one stray space or a renamed heading turns the CI gate off. Before, the child had to avoid the `PR #N` token everywhere.
- **Suggested fix:**
  - When no digit-keyed Phase plan row exists (`cp_phases` is 0), fall back to the old whole-file read. That keeps the documented table-less mode gated and does not bring back issue 26's dead end for jobs that have a table.
  - Always log the set read at `done`: `CI read for PRs: 7 9`, or `no PR named in a Phase plan Status cell; CI not read`.
  - Add a table-less case and one malformed-row case to `41-ci-wait`.

#### MEDIUM

**M1. A PR named anywhere but the Status cell is silently ungated, and the shipped template still models and promises the opposite (criterion 3 as written; new behaviour)**
- **Location:** `lib/ci.sh:66-67`; `templates/checkpoint.md:27,29-30,47`.
- **Description:**
  - 5 of the 29 variants: PR in a `PR` column before Status; PR only in `Completed phases` (the shape `templates/checkpoint.md:47` shows); PR in the Phase cell; PR in a second table under `## PRs`; PR on a prose line directly under the table.
  - On function copies with no CI record, the "Completed phases only" and "PR column before Status" variants give exit 10 under the old code and pass under the new.
  - This is what the issue asked for. The defect is that it is silent: nothing in `run.log` says no PR was checked, and `templates/checkpoint.md:29-30` still tells the child that a PR named anywhere is gated.
  - An adversarial child gets `done` by writing `done (<sha>)` in the cell and the PR in prose. Before this commit it had to avoid the token everywhere; an honest child that mentioned the PR anywhere was gated.
- **Suggested fix:** the log line from H1, and the template correction in M4. Optionally log (not refuse) `PR #N named outside a Status cell; not read`, so the owner sees it without blocking on another repo's PR.

**M2. The workflow check reads the workdir's local HEAD, not the commit the absent record is of (residual bypass in new code, not a regression)**
- **Location:** `lib/ci.sh:73` (`git -C "$TOP" ls-tree -r --name-only HEAD -- .github/workflows`).
- **Description:**
  - The record's `head_sha` is the PR head; `ci_head` only proves the record matches the PR head now. The workflow read is then of whatever the workdir has checked out.
  - Reproduced in a throwaway repo: PR head commit has `.github/workflows/ci.yml`, local HEAD is one unpushed commit ahead that deletes it. New `ci_check` logs `no CI runs and no workflow file at HEAD (absent, not a pass)` and passes.
  - A child gets there with `BLAST_OFF_CI_APPEAR=0 blast-off ci-wait` right after a push (instant `absent`; the child runs ci-wait and owns its env), plus a local-only commit removing the workflows.
  - The receipt side is traced, not run: a row done before child 1 is not diffed against HEAD (`lib/receipt.sh:62`), or the child re-gates and re-receipts at the local commit.
  - Deleting the workflow in the PR itself also passes (reproduced at the `ls-tree` level). That is visible in the PR diff, and whether GitHub then skips the run is recall.
  - Before this commit `absent` always passed, so the commit narrows this path. It also conforms to criterion 1's wording ("the workdir's HEAD"); the weakness is in the criterion.
  - A workflow file staged or untracked but not committed reads as "no workflow" (reproduced). A case-variant `.GitHub/workflows` reads as none (reproduced, correct).
- **Suggested fix:** read the tree of the record's `head_sha` (`git ls-tree -r --name-only "$h" -- .github/workflows`); a missing object is a refusal, not "no workflow". Also check `origin/<JOB_BASE>` so a PR that deletes its own workflows is still refused.

**M3. Fail-closed dead ends with no owner override; the refusal's remedy is partly impossible**
- **Location:** `lib/ci.sh:73-74`; `templates/brief.md:108` (`gh pr create --draft --base <previous phase's branch>`); `skills/blast-off/SKILL.md:33-34` (stacked PRs).
- **Description:**
  - Any file under `.github/workflows` at HEAD makes `absent` a permanent refusal. Reproduced with only `.github/workflows/README.md`, only a nested `.github/workflows/sub/x.yml`, and only a `workflow_dispatch`-only `release.yml`: all give `chain_end 10`.
  - By recall of GitHub behaviour, the same holds for a `pull_request: branches: [main]` filter combined with the stacked PRs this tool prescribes (every PR after the first has a base that is not `main`), `paths:` filters on a docs-only phase, and repos whose CI is itself dispatch-driven (every run is now filtered out).
  - There is no override. At `status: done` no child runs, so the owner's only exits are to remove the PR from the Status cell (the M1 bypass, which the implementer's note names as "the way out") or to hand-edit `ci-pr-N.json`.
  - The message says "get the PR a run that is not a workflow_dispatch (push, or re-run it)". An absent record has no non-dispatch run to re-run. For the timing case (runs listed after 60 s) the only action needed is `ci-wait` again, which the message puts second.
- **Suggested fix:**
  - An owner-side override the child cannot write, for example `BLAST_OFF_CI_ABSENT_OK="<pr> ..."` in the runner's env, logged as "absent, not a pass, owner override".
  - Count only `*.yml` and `*.yaml` directly under `.github/workflows`.
  - Reword the remedy: run `ci-wait` again first; then list the causes (filters, conflict, dispatch-only).
  - Tell children in `templates/brief.md` §9 step 4 to set `status: blocked` with the question when `ci-wait` records absent and the repo has workflows.

**M4. Four docs outside the diff now describe the old behaviour; none is pinned by a test**
- **Location:** `templates/checkpoint.md:29-30`; `skills/blast-off/SKILL.md:34-35`; `README.md:114-115,130`; `bin/blast-off:37`.
- **Description:**
  - `templates/checkpoint.md:29-30` says a PR named "anywhere here means this job's own PR: at done the runner wants a CI record for each". This is now false, and children read it as instruction. It errs fail-open: it claims a gate that no longer fires (see M1). Its second sentence (name other PRs without `#`) is now unnecessary but safe.
  - `skills/blast-off/SKILL.md:34-35` says that with no CI the runner lets `done` through, and "say so in brief §2". That is true only where HEAD has no workflow file. It errs fail-closed: the false "absent passes" promise is copied into every brief, and the job then stops at exit 10 (see M3).
  - `README.md:114-115` and the exit-10 row at `README.md:130` say done is refused "while a named PR's CI is red or unread". They omit absent-with-workflow (the code is stricter than the doc; the row's remedy does not cover it). "Named" is unqualified, which reads as stricter than the code for a PR named outside a Status cell.
  - `bin/blast-off:37` (`--help`) says "done refused: a PR's CI red or unread"; same omission.
  - `tests/70-docs.sh` and `tests/51-templates.sh` pin none of these sentences; 51 only checks that the string `PR #<n>` exists.
  - `templates/brief.md:135` ("absent checks are not a pass") still holds.
- **Suggested fix:**
  - Template: "`PR #<n>` or a /pull/<n> link in a row's Status cell means this job's own PR ... a PR named anywhere else is not read".
  - SKILL: "with no workflow file at HEAD ... lets `done` through; with one, `done` is refused (exit 10)".
  - README lines 114-115 and 130 and the help line: add "or absent while HEAD has a workflow file" and "named in a Phase plan Status cell".

**M5. Tests let fail-open mutants of the new gate survive**
- **Location:** `tests/41-ci-wait.sh:80-139`.
- **Description:**
  - Dropping the `## Phase plan` section range (reading the last cell of every digit-keyed table row in the file) survives. Reproduced: real pipeline and mutant both give `7 9` on the `fin` fixture, and differ only on my two-table variant (nothing versus `7`).
  - Replacing `|| die` on the `ls-tree` line with `|| true` (git error reads as "no workflow") survives by trace: no case makes git fail. I reproduced only that the real code dies on an unborn HEAD and on a non-repo `TOP`.
  - Reading the working tree instead of HEAD survives by trace: the `wf` job commits the file, so both agree.
  - `select(.event == "pull_request")` instead of `!= "workflow_dispatch"` survives: the fake's default event is `pull_request` and no push or schedule run exists in the fixtures.
  - A mutant that applies the workflow refusal to `success` records too survives: the only git workdir case uses an absent record.
  - There is no runner-level case for "dispatch-only head plus workflow file means done refused"; criteria 1 and 4 are tested apart.
  - There is no table-less or malformed-row case (see H1).
  - Killed by trace: `$(NF-1)` to `$NF` (line 89 would fail); reading the whole row (line 114, PR #98); filtering only the first list (run 73 at line 75); dropping `ci_head` in the absent branch (line 111).
- **Suggested fix:** add cases for:
  - a second digit-keyed table under another heading that names a PR with no record (must pass);
  - `ls-tree` failure (must exit non-zero, not 0);
  - an untracked workflow file;
  - a green `push` run beside a dispatch run;
  - a success record in a git workdir with a workflow (must pass);
  - a table-less checkpoint.

#### LOW

**L1. `--limit 100` is applied before the client-side event filter**
- **Location:** `lib/ci.sh:53-54`.
- **Description:** dispatch runs use up the 100-run window. Reproduced with jq: 100 dispatch runs listed ahead of one `pull_request` run leaves 0 ids, so the record is `absent` and the PR's red run is never seen. That is fail-closed where HEAD has a workflow and fail-open under M2's conditions. Truncation is never detected. The limit existed before; that the filtered runs still consume it is new. Real gh ordering is not confirmed.
- **Suggested fix:** die when the unfiltered list length equals the limit, or raise the limit.

**L2. Only `workflow_dispatch` is excluded; every other event still counts both ways (pre-existing)**
- **Location:** `lib/ci.sh:54`.
- **Description:** reproduced: ids of `push`, `schedule`, `repository_dispatch` and `dynamic` runs pass the filter, as do runs with a missing or null `event`. A lone green non-PR run on the head still yields `success` without a `pull_request` run.
- **Suggested fix:** document it, or require at least one `pull_request` run when a workflow at the head declares that trigger.

**L3. `ci-wait` never says dispatch runs were ignored**
- **Location:** `lib/ci.sh:45`.
- **Description:** a head with only dispatch runs logs `ci PR #N at <sha>: absent ()` after the full 60 s wait. A reader sees green runs on GitHub and "absent" in `run.log`.
- **Suggested fix:** log the count of dispatch runs left out.

**L4. `ci_check` now needs `TOP`, which only `chain_run` sets**
- **Location:** `lib/ci.sh:2,73`.
- **Description:** the file header still says "JOB, WORKDIR set by job_init". Under `set -u` any other caller dies on an unbound variable. Today the only caller is `lib/chain.sh:159`.
- **Suggested fix:** add "TOP by chain_run" to the header, as `lib/receipt.sh:2` has.

**L5. A workdir outside git skips the workflow read**
- **Location:** `lib/ci.sh:73`; `docs/spec.md:97`.
- **Description:** reproduced with empty `TOP`: absent passes. gh can only work there through `GH_REPO`, and that repo may have workflows. This is documented and only reachable through the runner's env.
- **Suggested fix:** none needed beyond the M3 override; note it.

**L6. An `ls-tree` failure exits 1 through `die`, so its reason is on stderr only**
- **Location:** `lib/ci.sh:73`; `lib/chain.sh:21`.
- **Description:** reproduced the die on an unborn HEAD. `run.log` gets only "runner exit 1 without a state". Fail-closed.
- **Suggested fix:** `chain_end 10` with the git error, or log before dying.

**L7. Fake `gh` diverges from the real CLI**
- **Location:** `tests/fakes/gh:22-30`.
- **Description:** its `--json` test prints `event` for `databaseId,events` and `databaseId,eventt` (reproduced: all three strings print true); the real gh rejects unknown fields. It ignores `--limit`. Every run defaults to `pull_request`.
- **Suggested fix:** match `(^|,)event(,|$)` on the field list and fail on unknown fields.

**L8. Pre-existing, unchanged by this commit**
- **Location:** `lib/ci.sh:41,67,68`.
- **Description:**
  - `gate-logs/ci-pr-N.json` is child-writable and unauthenticated; a hand-written `{"pr":N,"verdict":"success","head_sha":"<head>"}` passes.
  - `skipped` and `neutral` count as green.
  - `PR 7`, `#7`, `PR # 7` and `pull request #7` in a Status cell read as no PR, and `PR #7, #8` reads only 7 (reproduced identical in old and new).
- **Suggested fix:** out of this diff's scope; file separately.

**Requested judgements**
- **Three unedited docs:** each is now wrong. `templates/checkpoint.md:29-30` errs fail-open and is child-facing; `skills/blast-off/SKILL.md:34-35` errs fail-closed and propagates into brief §2; `README.md:114-115` omits the absent refusal and over-reads "named". Also stale: `README.md:130` and `bin/blast-off:37`. Detail in M4.
- **No Phase plan table:** yes, a fail-open, new with this commit, reproduced (H1). It is not required by criterion 3, which is about prose beside a table.
- **Real gh support:** `gh run list --help` on gh 2.101.0 lists `event` under JSON FIELDS and has `-c, --commit` and `-L, --limit`. The field is supported. The literal value `workflow_dispatch` is not shown by `--help`; I expect it from GitHub's API but did not verify it here.
- **New dependencies:** no new tool or action. New reliance on the `event` JSON field of `gh run list`, on `git ls-tree` (git is already in `DEPS`), and on the `TOP` global from `chain_run`. The test adds `git init` and `git commit` in a scenario temp dir, with identity passed by `-c`.

### Validated

**Confirmed correct**
- Criterion 1: copy of new `ci_check`, absent record, `TOP` with a committed `.github/workflows/ci.yml` gives `chain_end 10: PR #7 CI absent: no runs, but HEAD has a workflow file (.github/workflows/ci.yml)`. The old copy passed with `no CI runs (absent, not a pass)`.
- Criterion 2: `wf.sh` on a repo with no workflow dir, and with empty `TOP`, logs `PR #9: no CI runs and no workflow file at HEAD (absent, not a pass)` and continues.
- Criterion 3: `probe.sh` on the template-shaped variant gives old `7`, new `7`. On the `fin` fixture text the new pipeline gives `7 9`, so PR #98 (Phase cell) and PR #99 (prose) are not read. CRLF, trailing spaces after the last pipe and `## Phase plan (3 phases)` still read 7.
- Criterion 4, filter: `runs.sh` with a stub gh. A dispatch-only list gives no ids; a mixed list gives `6 7 8 9 10` with the dispatch id dropped. Both list calls go through `ci_runs` (`lib/ci.sh:20,30`).
- `ci_runs` under `set -euo pipefail` with the exact `new="$(ci_runs x)" || die` shape:
  - gh exit 1 after printing `[]`: die, rc 1.
  - non-array JSON and non-JSON text: jq error, then die, rc 1.
  - gh exit 0 with empty stdout: empty list, which becomes `absent`, never `success`.
- Verdict jq (`lib/ci.sh:37-42`): zero runs gives `absent`; one failure gives `failure`.
- `ls-tree` failure is not read as "no workflow": unborn HEAD and a non-repo `TOP` both die with exit 1 (`wf.sh`).
- Red record: old and new copies both give `chain_end 10: PR #7 CI red or unfinished`; unchanged.
- A no-trailing-pipe row with a normal Done-when cell drops the PR, but `cp_plan_rows open` returns `0`, so exit 9 fires first: fail-closed.
- errexit is live at the call site: `bin/blast-off:38,64` to `chain_run` to `lib/chain.sh:159`, all plain calls.
- `bash -n lib/ci.sh` and `bash -n tests/41-ci-wait.sh` are ok; `shellcheck -S warning` on `lib/ci.sh` and `tests/fakes/gh` is clean.
- The four spec rows (`docs/spec.md:35,58,97,228`) match the code as read, including "the workdir repo's HEAD", "or the workdir is in no git repo" and the new log text.
- Issue 26 text read with `gh issue view 26`; it matches the brief's quote and has three checkboxes.
- `.github/workflows/ci.yml:9-11`: triggers are `pull_request` and `workflow_dispatch` only, so in this repo a PR head's non-dispatch runs are its `pull_request` runs.

**Examined, inconclusive**
- `lib/ci.sh:54`: whether real gh emits exactly `workflow_dispatch` in `event`. Blocker: needs one real `gh run list --json event` call, which is not allowed here.
- `lib/ci.sh:53`: real gh ordering under `--limit 100` (L1). Blocker: needs a live repo with more than 100 runs on one commit.
- `lib/ci.sh:73-74` dead ends (M3) for `branches:` and `paths:` filters, conflicted PRs, nested workflow dirs, and a workflow deleted in the PR. Blocker: these are GitHub Actions behaviours from recall; only the `ls-tree` side was reproduced.
- M2 end to end through `receipt_check` (`lib/receipt.sh:54-62`). Traced that a row done before child 1 is not diffed against HEAD. Blocker: confirming it needs a runner run, which I may not do.
- `tests/41-ci-wait.sh:124-139` (`wf` job) passing as written. Read and traced. Blocker: I did not run it; the coordinator owns test runs.
- Mutant survival in M5 apart from the section-range one. By trace only. Blocker: needs scenario runs on a copy.

**Not examined**
- `lib/child.sh`, `lib/jev.sh`, `lib/preflight.sh` (beyond a 5-line grep), `lib/units.sh`, `lib/usage.sh`.
- `docs/spec.md` outside rows 35, 58, 61, 91, 96, 97, 216, 221, 228, 230 and the diff context.
- `tests/70-docs.sh` and `tests/51-templates.sh` beyond grepped lines.
- `baton-runner/` other than `baton-phase-3-work.md` and `baton-phase-2-review-1.md`.
- The fake `claude` and how the `done` fake-mode writes status.
- Any behaviour of the real `gh` or of GitHub Actions.

### Confidence

High on H1, M1, M2 (the `ls-tree` side) and the `ci_runs` error paths, all reproduced on copies of the code. Medium on M3 and L1, which rest partly on recalled GitHub behaviour. One real `gh run list --commit <sha> --json databaseId,event` on a PR head with a dispatch run, and coordinator-run mutants for M5, would raise it.
