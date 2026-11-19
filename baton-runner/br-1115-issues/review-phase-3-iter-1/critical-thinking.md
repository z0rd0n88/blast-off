### Summary

I reviewed commit b9c39ad (`lib/ci.sh`, `tests/41-ci-wait.sh`, `tests/fakes/gh`, four rows of `docs/spec.md`) against issue 26 and finding P2R1-1. The change does what criteria 1 to 4 literally ask, and each has a test that fails on a plain revert. It also turns CI from "any PR the checkpoint mentions is read" into "only a PR the child wrote into the last cell of a digit-keyed Phase plan row is read", and nothing requires a done row to name a PR. Three ordinary checkpoint shapes now reach `job done` with CI never read while every other gate passes (measured, item 1). On the other side, the new refusal has no stated way out when a PR legitimately gets no runs, and the commit also excludes the one manual run that could have supplied one (item 4). The repo's own history raises the question of whether the rule addresses the incident the issue cites (item 5).

Nothing was changed. No scenario was run and no live `gh run list` was made. Snippets ran in `/tmp/claude-1000/-home-alex-blast-off--claude-worktrees-pending-items-53932d/60b15296-819e-491a-8ffe-34b3bd988f86/scratchpad/ct3.Jdkiqo` (left in place). Disclosure: I ran `gh --version` (local, read-only), which is outside the two gh commands the rules allow.

Tags: **[introduced]** by this diff, **[widened]** by it, **[pre-existing]**.

Measured extraction matrix, referenced below. `new` is the exact pipeline from `lib/ci.sh:66-67`, `old` is the phase-2 line, rows are `cp_plan_rows` copied from `lib/checkpoint.sh:39-44`:

```
01-no-table                                new=[]   old=[7]  done_rows=[]  open_rows=[]
02-capital-P  (## Phase Plan)              new=[]   old=[7]  done_rows=[]  open_rows=[]
03-nondigit-keys (| P0 |, | **1** |)       new=[]   old=[7 8] done_rows=[] open_rows=[]
04-pr-col-before-status                    new=[]   old=[7]  done_rows=[0] open_rows=[]  sha 0=abc1234
05-pr-col-after-status                     new=[7]  old=[7]  done_rows=[]  open_rows=[0]
06-no-trailing-pipe                        new=[]   old=[7]  done_rows=[]  open_rows=[0]
06b-no-trailing-pipe, Done-when "done when green"  new=[] old=[7] done_rows=[0] open_rows=[] sha 0=(none)
07-crlf                                    new=[7]  old=[7]  done_rows=[0]
08-escaped-pipe (done (abc1234) \| PR #7)  new=[7]  old=[7]  done_rows=[]  open_rows=[0]
09-pr-forms (8 done rows)                  new=[15] old=[7..16] done_rows=[0..7] open_rows=[]
10-done-row-no-pr-in-cell                  new=[]   old=[7]  done_rows=[0] open_rows=[]  sha 0=abc1234
11-indented-row                            new=[]   old=[7]  done_rows=[]  open_rows=[]
12-control (template form)                 new=[7]  old=[7]  done_rows=[0]
```

In fixture 09 the cells hold `PR: #7`, `PR 8`, `PRs #9, #10`, `pull request #11`, `PR [#12]`, `PR  #13` (two spaces), `#14`, `PR #15 and #16`. Only 15 is read from the cells. The regex did not change: `old` found the rest only because my fixture also names them in a `Completed phases` prose line, as `templates/checkpoint.md:46-47` tells children to do.

### Findings

**1. [introduced] Three ordinary checkpoint shapes now reach `done` with CI unread and every other gate green.**
- **Why it matters:** Fixtures 04 (a PR column before Status), 09 (PR written in a form the regex misses) and 10 (done row `done (abc1234)`, PR named only in `Completed phases`) all give `new=[]` with the row done and its sha read, so `receipt_check`, `receipt_all_done` and `ci_check` all pass. In phase 2 each was refused with exit 10. The whole-file read was a second net for a child that forgot or mis-wrote the cell; the diff removed it.
- **What to verify or decide:** Is a done row with no readable PR in its Status cell meant to pass silently? What tells the owner at `done` that zero PRs were read? Why is the number of PRs read not logged? Who is the gate protecting against, given that the child being gated writes the only cell it reads?

**2. [introduced] Mandated judgment, table-less checkpoint: yes, it is a fail-open relative to phase 2.**
- **Why it matters:** Fixture 01 (PR in prose, no table) gives `new=[]`, `old=[7]`. Fixtures 02, 03 and 11 (heading `## Phase Plan`, non-digit keys, indented rows) behave the same: the runner sees no rows, so receipts were already off and the CI read was the only gate left. Now there is no gate at all. `docs/spec.md` supports table-less checkpoints (`JOB_MAX_CHILDREN` "with no Phase plan table") and the exit-10 row does not say they get no CI read.
- **Why it matters (test):** The phase-2 `fin` fixture was exactly this case (`printf -- '- phase 0 delivered as pr#07\n- phase 1: https://github.com/o/r/pull/9\n'`, no table, expecting exit 10). Hunk `@@ -58,13 +65,25 @@` of `tests/41-ci-wait.sh` replaced it with a table. The flip from gated to ungated has no test in either direction.
- **What to verify or decide:** Is "table-less job, PR open, CI red, `status: done`, exit 0" accepted? If so, where is that written, and should the spec's exit-10 row say it?

**3. [introduced] Which commit decides "runs were due": the code tests workdir HEAD, not the PR's head.**
- **Why it matters:** Measured in a throwaway repo: workflow committed, then removed in a later commit gives `HEAD=[]` while `pr-head=[.github/workflows/ci.yml]`, so an absent record passes although runs were due at the PR's head. The reverse also holds: a workflow first added in a later phase makes every earlier stacked PR's absent record a refusal. An untracked workflow file is not seen (`[]`, rc 0).
- **What to verify or decide:** The issue says "HEAD has `.github/workflows/*`". Was workdir HEAD chosen on purpose over the PR's `headRefOid`, which `ci_head` already fetches? With one stacked PR per phase (`templates/brief.md:108`, `--base <previous phase's branch>`), HEAD is the last phase's commit for every PR.

**4. [introduced] The refusal has no stated way out when the trigger legitimately does not fire, and the same commit removes the one manual exit.**
- **Why it matters:** Measured: `.github/workflows/.gitkeep` alone, a `README.md` there, a file in a subdirectory, a schedule-only workflow, and `.github/workflows` as a plain file all count as "a workflow file" and refuse an absent record. The message (`lib/ci.sh:74`) says "push, or re-run it": with zero runs there is nothing to re-run, and a push only helps if the trigger fires. `ci_runs` now discards every `workflow_dispatch` run, including a whole-suite dispatch (`ci.yml:231`: "Empty: the whole gate"), so the owner cannot give the head a run by hand either. No override exists. The only exits left are editing the PR out of the Status cell or hand-writing the record, and both are fail-open.
- **What to verify or decide (GitHub behaviour from recall, not run here):** Does a `pull_request` trigger with `branches: [main]` fire for a stacked PR whose base is the previous phase's branch? What about a PR with merge conflicts, a `[skip ci]` commit, `paths` filters, Actions disabled? For each, what should the owner do at exit 10? Is `event == workflow_dispatch` the right proxy for "diagnostic", when the real discriminator in this repo is a non-empty `only` input?

**5. [introduced, question] Does the rule address the incident the issue cites?**
- **Why it matters:** Issue 26: "In this build PRs 1-8 merged with no CI." Measured with `git ls-tree -r --name-only <merge>^2 -- .github/workflows`: heads of PRs 1 to 8 hold 0 workflow files; PR 9's head (45efb3e) holds 1; `ci.yml` was added in 376fa07, which is an ancestor of PR 9's head only. So no run was ever due at those eight heads.
- **What to verify or decide:** I have not seen that job's workdir HEAD or Status cells. If HEAD was PR 9's branch, the new rule refuses PRs 1 to 8: with what way out? If the rule were per PR head, it passes them, and the incident is not one the rule prevents. Which outcome did the owner want for that build?

**6. [introduced] Criterion 4 holds in `ci_wait` but not at the gate for records already on disk.**
- **Why it matters:** Traced, not run: the record schema is `{id, name, conclusion}` (`lib/ci.sh:38`), with no event. The `success` branch of `ci_check` (`:70`) checks only the head. A `success` record written by the phase-2 `ci_wait` from a green dispatch run still lets `done` through after the upgrade, and nothing in the record shows which events were counted or dropped.
- **What to verify or decide:** Do in-flight jobs need their records re-read after this lands? Should the record carry `event` so a reader can audit it?

**7. [introduced] Mandated judgment, three unedited docs (plus two more found stale the same way).**
- `templates/checkpoint.md:29-30`: **false; errs fail-open.** "`PR #<n>` or a /pull/<n> link anywhere here means this job's own PR: at done the runner wants a CI record for each". A child reading this believes a prose mention is gated, and line 46-47 of the same template invites one. The advice to write other PRs without `#` is now needless but harmless. `tests/51-templates.sh:74` pins the sentence `means this job's own PR` as a rule sentence, so the test now asserts a false rule and a fix must touch that test.
- `skills/blast-off/SKILL.md:34-35`: **false for a repo with workflows; errs fail-closed (a surprise refusal).** It promises "the runner lets `done` through" on absent and tells the planner to say so in brief §2. True now only where HEAD has no workflow file.
- `README.md:114-115`: **incomplete, not false.** "a named PR's CI is red or unread": "named" is unqualified (a reader assumes anywhere, the fail-open direction) and the absent refusal is missing.
- Same staleness, not on the implementer's list: `README.md:130` (exit-code table row 10, whose "What to do" has no remedy for absent) and `bin/blast-off:37` (`--help` text "10 done refused: a PR's CI red or unread").
- **What to verify or decide:** `templates/` text is instruction to children. Is leaving a false gate description in it acceptable for a merge whose point is the gate? `templates/checkpoint.md:27` ("Add `PR #<n>` after it") is now the only thing that arms the CI gate and does not say so.

**8. [introduced] Mandated judgment, real gh support: field and flags confirmed, event value unverified.**
- **Why it matters:** `gh run list --help` (gh 2.101.0) lists `databaseId` and `event` under JSON FIELDS and has `--commit` and `--limit`. The help does not enumerate event values, so the string `workflow_dispatch` is unverified here; it matches the workflow trigger key from recall. jq check: an object with no `event` key or `event: null` passes the filter (counted), and `Workflow_Dispatch` also passes (case-sensitive).
- **What to verify or decide:** One real `gh run list --commit <sha> --json databaseId,event` on a head that has a dispatch run, before merge. P2R1-20 already asks for that dispatch.

**9. [introduced] Mandated judgment, new dependencies: no new tool; one new reliance with no declared floor.**
- **Why it matters:** New reliances are the `event` JSON field of `gh run list` and `git ls-tree` (git is already in `DEPS`, `lib/chain.sh:84`). `gh` is not in `DEPS`, and I found no gh version floor in `README.md`, `docs/spec.md`, `lib/` or `bin/`. An older gh without the field fails `gh run list`, which dies (fail-closed; measured that `x="$(ci_runs)" || die` sees the pipefail status through the function).
- **What to verify or decide:** Is a gh floor worth stating, or is "dies with `gh run list failed`" enough of a message?

**10. [introduced] Tests: assertions that survive a mutated implementation.**
- **Why it matters:** Each criterion's test fails on a plain revert, but these mutants pass the scenario by reading:
  - `git -C "$WORKDIR" ls-tree` in place of `$TOP`: the `wf` fixture's workdir is the repo root. Measured: from a subdirectory the pathspec gives `[]`, a fail-open in a monorepo workdir.
  - `|| true` in place of `|| die` on the `ls-tree` line: no fixture makes `ls-tree` fail (measured: unborn HEAD gives rc 128, and the real line dies).
  - Working tree read in place of HEAD (`ls .github/workflows`): no fixture has an untracked or removed workflow.
  - `-- .github` in place of `-- .github/workflows`: no fixture with another file under `.github`.
  - `select(.event == "pull_request")` in place of `!= "workflow_dispatch"`: the fake's only other event is the default `pull_request`, so "push and other events still count" is unpinned.
  - `$5` in place of `$(NF-1)`, or dropping the `## Phase plan` range: no fixture with an extra column or a digit-row table in another section.
  - Nothing tests a table-less checkpoint, a PR column before Status, or a done row with no PR (items 1 and 2).
- **Why it matters (evidence):** The implementer's note says only the PR 14 half of criterion 4 was seen red; the PR 15 half first ran after the fix.
- **What to verify or decide:** Which of these behaviours are part of the contract? Those that are need a fixture.

**11. [introduced] Fake `gh` diverges from the real CLI on field validation.**
- **Why it matters:** The fake emits `event` when its arguments match `--json [a-zA-Z,]*event`, so `--json databaseId,events` or `eventX` also gets an `event` key and the scenario stays green, where real gh rejects an unknown field. The fake ignores `--limit` and returns the same three fields from `run view` whatever is asked (both pre-existing).
- **What to verify or decide:** Should the fake reject fields outside the help's JSON FIELDS list, so a typo fails locally?

**12. [widened] Row-shape handling that fails closed, and one shape that does not outside git.**
- **Why it matters:** Fixtures 05 (PR column after Status), 06 (no trailing pipe) and 08 (escaped pipe in the cell) leave the row open, so `receipt_all_done` ends with exit 9, in or out of git. CRLF (07) reads correctly. Fixture 06b (no trailing pipe, "Done when" cell starting with "done") reads the row as done with no sha: exit 9 in git, but outside git `receipt_check` is off and the PR is unread.
- **What to verify or decide:** Exit 9's message for 05, 06 and 08 talks about receipts, not table shape. Will an owner find the cause? Is the 06b path outside git worth closing?

**13. [pre-existing] A failing read of `checkpoint.md` in `ci_check` reads as "no PRs".**
- **Why it matters:** Measured under `set -euo pipefail`: `for pr in $(sed ... /nonexistent | awk | grep | sort)` prints sed's error, skips the loop, returns 0, and the next statement (`chain_end 0`) runs. The phase-2 line had `|| true` and behaved the same. Reachable only if the file becomes unreadable between `cp_status` and `ci_check`.
- **What to verify or decide:** Accept as is, given `chain_dirty` writes the porcelain to a file for exactly this reason ("a failing git status must not read as a clean tree")?

**14. [introduced, minor] Outside git, absent passes with no workflow check.**
- **Why it matters:** Measured: `TOP` empty gives `wf=[]` and the pass branch. The spec row documents it. A PR can still exist there if `GH_REPO` points gh at a repo.
- **What to verify or decide:** Intended, or should a non-git workdir with a readable PR be treated as unknown?

### Validated

- **Confirmed:** `bash -n lib/ci.sh` passes; `shellcheck -S warning lib/ci.sh tests/fakes/gh` rc 0. `wf="$(...)" || die` keeps git's status because `local wf` is declared on its own line (`lib/ci.sh:65,73`; snippet: unborn HEAD gives "die reached", rc 1). `git -C "$TOP"` with a top-relative pathspec finds the workflow from a subdirectory workdir. `ci_runs` failure reaches `die` through `$( )` with pipefail. Non-JSON or object output from gh makes jq exit 5, so it dies. Empty gh output with exit 0 yields no ids, hence `absent`. Spec rows F7, `ci-wait`, exit 10 and `41-ci-wait` match the code as written. Criteria 1 to 4 each have an assertion that a revert fails (`tests/41-ci-wait.sh:71-75,113-116,133-139`).
- **Examined, not verified:** the old-record path (item 6, traced only); every GitHub trigger behaviour in item 4; the `workflow_dispatch` string against a live API.
- **Not examined:** `lib/units.sh`, `lib/usage.sh`, `lib/child.sh`, `lib/preflight` code; `docs/spec.md`, `templates/brief.md`, `README.md` and `SKILL.md` outside the regions and grep hits for `CI`, `exit 10`, `absent`, `PR #`, `workflow`; any scenario run.

### Confidence

High on the measured items (1, 2, 3, 5, 7, 10, 12, 13), medium on item 4's dead ends because they rest on GitHub trigger behaviour I could not run; one live `gh run list --json databaseId,event` on a dispatched head and the owner's answer on PRs 1 to 8 would settle the rest.
