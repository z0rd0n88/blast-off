### Summary

I reviewed commit b9c39ad (`lib/ci.sh`, `tests/41-ci-wait.sh`, `tests/fakes/gh`, `docs/spec.md`) against issue 26 and finding P2R1-1. The four criteria are implemented as written and each has an assertion that fails if `lib/ci.sh` is reverted. The change also opens one fail-open path that I rate HIGH: a checkpoint from which no digit-keyed Phase plan row parses now gets no CI gate at `done`, and no CI line is logged. Before this commit the whole-file read still caught those PRs. There are 6 MEDIUM and 9 LOW findings besides.

Method: I ran no test scenario and never ran `bin/blast-off`. I sourced `lib/ci.sh`, `lib/checkpoint.sh` and `lib/receipt.sh` in a subshell under `set -euo pipefail` with stubbed `log`, `die`, `chain_end` and a stub `gh` executable, against sample checkpoints and throwaway repos in my own temp dir.

**Rule breach to disclose.** My first trace run stubbed `gh` as a shell function, and `ci_head` calls it through `timeout`, which execs the real binary. The real `gh pr view 7 --json headRefOid` ran 12 times in throwaway dirs. All 12 failed locally before any API call: "no git remotes found" 10 times, "failed to run git: fatal: not a git repository" twice. I then put a stub executable first on `PATH` and reran everything. Nothing was written anywhere outside my temp dir.

Temp dir (left in place for re-running): `/tmp/claude-1000/-home-alex-blast-off--claude-worktrees-pending-items-53932d/60b15296-819e-491a-8ffe-34b3bd988f86/scratchpad/sfh3.wdWhUx` (`harness.sh`, `harness-full.sh`, `runs.sh`, `wait.sh`, sample checkpoints under `m/`, repos `repo-*`).

### Findings

#### CRITICAL

None.

#### HIGH

**H1. No parsed Phase plan row means no CI gate at `done`, with no CI line logged (introduced by this diff)**
- **Location:** `lib/ci.sh:66-67` (PR list now built from `sed -n '/^## Phase plan/,/^## /{/^| *[0-9]/p}' | awk -F'|' '{ print $(NF-1) }'`); done path `lib/chain.sh:159`.
- **Description:** When the sed range yields zero rows, `ci_check`'s loop body never runs. `receipt_all_done` (no open rows) and `receipt_check` (no done rows) also pass on zero rows, so nothing gates `done`. The old whole-file grep read the PR in every one of these cases.
  - Matrix of 29 sample checkpoints, old pipeline versus new, plus `cp_plan_rows`:
    - 5 read correctly by both (control, `PR #7, #8` as far as 7, markdown link to `/pull/7`, trailing whitespace after the last pipe, CRLF).
    - 3 end in exit 9 through `receipt_all_done` (no trailing pipe, `\|` in the Status cell, an extra column after Status).
    - 14 flip from refused (old read PR 7) to passed (new reads nothing). 8 of them are this finding: no table at all, `## Phase Plan`, `### Phase plan`, `## Phases`, row key `P0`, row key `**0**`, an indented table, a table with no leading pipes. The other 6 are M1 (3) and L8 (3).
    - 7 were unread by the old pipeline too (pre-existing, see L7).
  - Full done path (`receipt_check ""; receipt_all_done; ci_check`) with `TOP` set to a repo that has `.github/workflows/ci.yml` at HEAD and no CI record:
    - no table, PR #7 in prose: `rc=0`, output only `CHAIN_END 0: job done`.
    - `## Phase Plan` heading with `done (abc1234) · PR #7` in the Status cell: `rc=0`, same output.
  - "Silent" here means no CI line. The runner still logs `child cap N (hard: no Phase plan table in checkpoint.md)` at start (`lib/chain.sh:134`).
  - `docs/spec.md:61` documents table-less checkpoints as supported. The spec's exit 10 row does not say they get no CI read.
  - Criterion 3 mandates ignoring a PR outside a Status cell. It does not mandate dropping the gate when no row parses.
- **Suggested fix:** In `ci_check`, when `cp_phases` is 0, keep the old whole-file read (the "another repo's PR" complaint in issue 26 was about checkpoints that have a table). Failing that, always log one line at `done` naming the PRs read, including "none", so the pass is never silent. Add one `41-ci-wait` case for a table-less checkpoint and say in spec row 10 which behaviour holds.

#### MEDIUM

**M1. A PR named outside a Status cell passes `done` silently, and `templates/checkpoint.md:29-30` still tells children the opposite**
- **Location:** `lib/ci.sh:66-67`; `templates/checkpoint.md:29-30` and `:47`.
- **Description:** Criterion 3 asks for this narrowing; the defects are the silence and the stale instruction.
  - End to end in a throwaway repo with a real commit, a PASS receipt for it, a workflow at HEAD, the row `done (448bc36)`, and `PR #7; CI conclusion read` only in "Completed phases" (the place template line 47 puts it), with no `ci-pr-7.json`: `rc=0`, output only `CHAIN_END 0: job done`. Moving `PR #7` into the Status cell gives `rc=10 PR #7 CI unread`.
  - Same flip for a PR in the Phase cell and for a digit-keyed table in another section (3 matrix cases).
  - The template comment says a PR "anywhere here means this job's own PR: at done the runner wants a CI record for each". Children read that as an instruction. It now overstates the gate, so it errs fail-open. Line 27 and `templates/brief.md:143` do say to put the PR in the Status cell.
  - No test pins the words "anywhere here" (`tests/51-templates.sh:31` pins only `PR #<n>`).
- **Suggested fix:** Reword lines 29-30 to "only a `PR #<n>` or /pull/<n> in a Status cell is read; a row closed without one gets no CI check". Log the PR list at `done` (same line as H1).

**M2. The workflow check reads the workdir's HEAD, not the PR's head or base**
- **Location:** `lib/ci.sh:73`.
- **Description:** Two directions.
  - Fail-open: on a branch whose HEAD deleted `.github/workflows` (base still has it), an absent record of the current head gives `rc=0`, `LOG: PR #7: no CI runs and no workflow file at HEAD (absent, not a pass)`. Reproduced mechanically. That GitHub starts no `pull_request` run for a PR that removes the workflow file is recalled GitHub behaviour, not observed here.
  - Fail-closed: with stacked PRs, an earlier PR whose head predates the workflow file can never get a run, yet at `done` HEAD has the file, so its absent record is refused (mechanically the same as the plain "absent plus workflow" case, `rc=10`). This is the shape issue 26 describes ("PRs 1-8 merged with no CI").
- **Suggested fix:** Read the tree of the record's `head_sha` (the PR head) and of the base (`origin/<JOB_BASE>`): runs were due if either has a workflow file. Fall back to HEAD when the object is missing.

**M3. Absent plus a workflow file is a dead end for most no-run causes, and the one universal way out is the silent bypass in M1**
- **Location:** `lib/ci.sh:74` (message), `lib/ci.sh:53-54` (dispatch excluded).
- **Description:** The message offers "push, or re-run it". With an absent record there is no run to re-run.
  - Reproduced: `.github/workflows` holding only `README.md` gives `rc=10 ... HEAD has a workflow file (.github/workflows/README.md)`. A repo whose only workflow is `on: schedule` gives `rc=10` too. A push fixes neither.
  - Recalled, not observed: `on: pull_request` with `branches: [main]` on a stacked PR (the delivery model `skills/blast-off/SKILL.md:33-34` prescribes), a `paths:` filter the PR misses, a merge conflict, Actions or the workflow disabled. A push helps only the conflict case.
  - The natural manual remedy, a full-suite `workflow_dispatch` run, is now excluded by criterion 4.
  - Status stays `done`, so every re-run stops at the same exit 10 without a child. The owner's only general way out is deleting `PR #N` from the Status cell, after which `done` passes with nothing logged.
- **Suggested fix:** Count only `*.yml`/`*.yaml` under the directory. Name the real ways out in the message. Give the owner an explicit, logged override (one env var) so the escape is not an unlogged checkpoint edit.

**M4. Criterion 2 is tested only on an empty commit, so the pathspec is unpinned**
- **Location:** `tests/41-ci-wait.sh:127` (`commit --allow-empty`), `:133-138`.
- **Description:** On the fixture's two commits, `git ls-tree -r --name-only HEAD` gives the same first line with `-- .github/workflows`, with `-- .github`, with `-- .`, and with no pathspec: empty at the first commit, `.github/workflows/ci.yml` at the second. A mutant that drops or widens the pathspec would therefore pass both assertions. On a repo with one ordinary file and no workflow, the no-pathspec form gives `src/a`, so that mutant would refuse every real repo. Shown with standalone `ls-tree` calls; the mutant itself was not run through the scenario.
- **Suggested fix:** Commit one ordinary file (and one under `.github/` outside `workflows/`) in the `wf` fixture before the first run.

**M5. `skills/blast-off/SKILL.md:34-35` now has a session write a false promise into the brief**
- **Location:** `skills/blast-off/SKILL.md:34-35`.
- **Description:** It says that with no CI the runner lets `done` through and tells the session to "say so in brief §2". That holds only where HEAD has no workflow file. For a repo with workflows that do not fire on this PR, the brief will promise a pass and the job will end at exit 10. It errs fail-closed: no safety hole, but an overnight job that stops with no remedy named.
- **Suggested fix:** "with no workflow file at HEAD ... lets `done` through; with one, absent is refused (exit 10)".

**M6. `README.md:114-115`, `README.md:130` and `bin/blast-off:37` omit the absent refusal and give a remedy that loops**
- **Location:** as named.
- **Description:** All three say exit 10 means "red or unread". README's "What to do" cell says to fix CI or run `ci-wait` after the last push. For an absent refusal `ci-wait` records absent again and the next run refuses again. Each errs fail-closed (under-describes refusals). `tests/70-docs.sh` checks only that a row for code 10 exists.
- **Suggested fix:** Add "or absent while HEAD has a workflow file" and the remedy to all three.

#### LOW

**L1. `ci_wait` drops dispatch runs without a log line or a record field (introduced)**
- **Location:** `lib/ci.sh:52-55`, `:45`.
- **Description:** With two green dispatch runs on the head, the stubbed `ci_wait` gives `rc=10`, log `ci PR #7 at 1111...: absent ()`, record `{"verdict":"absent","runs":[]}`. An owner who sees green runs in GitHub gets no hint why the record says absent.
- **Suggested fix:** Log the count of `workflow_dispatch` runs left out.

**L2. A `success` record written before this commit from a dispatch-only head still passes (pre-existing record, not re-judged)**
- **Location:** `lib/ci.sh:68-70`.
- **Description:** Records carry no event. A record `{"pr":7,"verdict":"success","runs":[{"id":61,...}]}` of the current head gives `rc=0` with a workflow at HEAD. It affects only jobs in flight across the upgrade. A hand-written `success` record with empty `runs` also passes; that is pre-existing and untouched by the diff.
- **Suggested fix:** Record `event` per run, or accept and note it.

**L3. The event filter is pinned in one direction only**
- **Location:** `tests/41-ci-wait.sh:27-32,71-75`; `tests/fakes/gh:28`.
- **Description:** Every non-dispatch fixture run has the fake's default event `pull_request`. A mutant `select(.event == "pull_request")` would pass, and would turn push-only CI into absent. Argued from the fixtures, not run.
- **Suggested fix:** Give one counted run `event-<id>` = `push`.

**L4. The section range and malformed tables have no test**
- **Location:** `tests/41-ci-wait.sh:84-86`.
- **Description:** PR #99 sits in prose after `## Decisions` and PR #98 in another cell of a plan row. No fixture has a digit-keyed table row outside the Phase plan section, so a mutant that drops the `/^## Phase plan/,/^## /` range would pass. No fixture is table-less (H1). Argued, not run.
- **Suggested fix:** One digit-keyed row naming a PR under another heading; one table-less job.

**L5. The fake `gh` diverges from the real CLI in two ways that matter here**
- **Location:** `tests/fakes/gh:20-21,28-29`; `tests/41-ci-wait.sh:113-116`; `docs/spec.md:97`.
- **Description:**
  - The fake's `pr view` works in a directory that is not a git repo. The real one does not: my accidental real calls failed with "failed to run git: fatal: not a git repository". So the `fin` job's "absent, workdir in no git repo, done passes" path is reachable only with the fake (or `GH_REPO` set, which `start` does not pass). With real gh `ci_head` fails first and the PR is unread. The spec's "or the workdir is in no git repo" describes a path that does not occur in practice. On that path the log also says "no workflow file at HEAD" when there is no HEAD.
  - The fake accepts any `--json` field name; the real gh rejects unknown ones.
- **Suggested fix:** Note the first in the spec row or drop the clause; no change needed for the second.

**L6. `for pr in $(sed | awk | grep ...)` discards the pipeline's status**
- **Location:** `lib/ci.sh:66-67`.
- **Description:** `ci_check` alone against a job dir with no `checkpoint.md`: sed prints "can't read", `rc=0`, job done. With `receipt_all_done` first, as in `lib/chain.sh:159`: `rc=2` (errexit in `k="$(cp_open_rows)"`). So it is unreachable today, and it rests on call order. The pattern is pre-existing; the diff adds two stages to it.
- **Suggested fix:** Assign the list to a local first (`prs="$(...)" || die ...`), then loop.

**L7. PR forms the regex never read (pre-existing, less redundancy now)**
- **Location:** `lib/ci.sh:67` (`PR ?#[0-9]+|/pull/[0-9]+`, unchanged).
- **Description:** Seven matrix cases were unread by old and new alike: `PR 7`, `#7`, `PRs #7, #8`, `pull request #7`, `PR: #7`, `PR  #7` (two spaces), `o/r#7`. `PR #7, #8` reads only 7. Before this diff a second mention elsewhere in the file often supplied the match; now only the Status cell counts.
- **Suggested fix:** Accept bare `#N` inside a Status cell, or log the PR list at `done`.

**L8. Three contrived last-cell misparses pass**
- **Location:** `lib/ci.sh:66` (`$(NF-1)`, the same cell `cp_plan_rows` reads).
- **Description:** A row with no trailing pipe, a `\|` in the Status cell, or an extra column passes with no PR read when the cell that gets read happens to start with "done" and hold a 7 to 40 hex word. Otherwise these shapes end in exit 9.
- **Suggested fix:** None beyond the H1 log line.

**L9. Refusal wording**
- **Location:** `lib/ci.sh:74`.
- **Description:** "(push, or re-run it)": nothing exists to re-run on an absent record.
- **Suggested fix:** "push a commit to the PR branch".

#### Requested judgements

- **`templates/checkpoint.md:29-30`:** wrong now; errs fail-open (M1).
- **`skills/blast-off/SKILL.md:34-35`:** wrong for any repo with a workflow file; errs fail-closed (M5).
- **`README.md:114-115`:** incomplete, and line 130's remedy loops on absent; errs fail-closed (M6). `bin/blast-off:37` has the same gap.
- **Table-less checkpoint:** yes, a fail-open, and newly so (H1).
- **Real `gh run list --json databaseId,event`:** `gh run list --help` (gh 2.101.0) lists `event` and `databaseId` under JSON FIELDS and has `-c, --commit SHA`, so the call shape is supported. The help does not show the value `workflow_dispatch`; that is the GitHub API's event name from memory. If the string were wrong, dispatch runs would be counted as before (fail-open for a green one).
- **New dependencies:** the `event` JSON field of `gh run list`; `git ls-tree` (git is already in `DEPS`, `lib/chain.sh:84`); `awk` and `sed`, now used in `lib/ci.sh` and already used by `lib/checkpoint.sh` (neither is in `DEPS`). No new tool, action or package. README names no minimum gh version.

### Validated

**Confirmed correct**
- Criterion 1: absent record of the current head with `.github/workflows/ci.yml` at HEAD gives `rc=10`, message `PR #7 CI absent: no runs, but HEAD has a workflow file (.github/workflows/ci.yml)...` (`lib/ci.sh:71-74`, stubbed harness).
- Criterion 2: same record on a repo with `src/a` and no `.github` gives `rc=0` with the log line at `lib/ci.sh:75`.
- Criterion 3: control checkpoint and the filled-in template with the PR in the Status cell both give `rc=10 PR #7 CI unread`; CRLF, trailing whitespace and a markdown `/pull/7` link are read.
- Criterion 4 (`ci_runs`, `lib/ci.sh:52-55`, stubbed `gh`): events pull_request, workflow_dispatch, push, schedule, dynamic give ids `1 3 4 5`. Stubbed `ci_wait`: green pull_request plus red dispatch gives `rc=0`, runs `[71]`, no watch or view of 72; dispatch-only gives `rc=10`, absent.
- `ci_runs` fails closed on gh errors: gh exit 1 with or without output, non-JSON on stdout, and an object in place of an array all give `DIE: gh run list failed` (pipefail holds inside `$(...)` under `||`). Empty stdout and `[]` give no ids, so absent.
- A failing `ls-tree` is not read as "no workflow": unborn HEAD and a `TOP` that is no repo both give `rc=1 DIE: git ls-tree HEAD failed in ...`.
- The head check still runs first on an absent record: with the PR head moved, `rc=10 PR #7 CI unread for head 2222...`.
- Unreadable records stay unread: verdict `Success`, `null`, an empty file and `"pr":"7"` all give `rc=10 CI unread`.
- Each criterion has an assertion that fails on a revert of `lib/ci.sh`, by reading `tests/41-ci-wait.sh:71-75,113-116,133-138`; the RED tails in `baton-phase-3-work.md` agree. Not run by me.
- `bash -n` passes on the three changed scripts; `shellcheck -S warning lib/ci.sh tests/41-ci-wait.sh tests/fakes/gh` exits 0.
- `docs/spec.md` rows F7 (35), `ci-wait` (58), exit 10 (97) and `41-ci-wait` (228) match the code, except the two gaps in H1 and L5.
- Issue 26's text read with `gh issue view 26`; it matches the criteria given.

**Examined, inconclusive**
- `lib/ci.sh:54`, the literal `"workflow_dispatch"`: the field is confirmed by `--help`; the value needs one real `gh run list --json event` on a commit with a dispatch run, which my rules forbid.
- `lib/ci.sh:73` against GitHub's behaviour (M2, M3): whether a PR that deletes its workflow, a branch or path filter, or a merge conflict leaves a head with no run needs observation on GitHub.
- `tests/41-ci-wait.sh:125-139` (`wf` job): my reading that the child sets `status: done` and that `receipt_check` passes after the second commit rests on `tests/fakes/claude`, which I did not read, and on the implementer's green run.
- Surviving mutants in M4, L3 and L4 are argued from fixtures and standalone snippets; none was run through a scenario.

**Not examined**
- `tests/fakes/claude`, `tests/run`, `scripts/gate.sh`, `lib/child.sh`, `lib/units.sh`, `lib/usage.sh`, `lib/preflight.sh`, `lib/jev.sh`.
- `docs/spec.md` outside the four changed rows and the lines my greps hit; `templates/brief.md` beyond lines 109-161 as grepped.
- The `baton-runner/` bookkeeping in the diff, and the phase-3 `full-gate.log`.
- Any behaviour on a real GitHub repo or under the systemd unit.

### Confidence

High on the mechanics (every HIGH and MEDIUM code claim was run against the real functions with stubs); medium on the GitHub-side halves of M2 and M3 and on the event string, which one real `gh run list` on a dispatched commit and one PR with a path-filtered workflow would settle.
