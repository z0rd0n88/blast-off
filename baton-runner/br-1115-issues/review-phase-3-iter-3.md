# Review: blast-off phase 3 (issue 26), round 3 of 3: synthesized report

Target: `feat/br-1115-issues/phase-3` at `d43324d`, diff `feat/br-1115-issues/phase-2...HEAD -- . ':!baton-runner'` (16 files, 301 insertions, 59 deletions).

## Executive Summary

- Gate: green, run once by the coordinator: `GATE: PASS passed=18 failed=0 shellcheck=ok`, exit 0 (`gate-phase-3-iter-3/tests-run.log`).
- Counts after dedup: **0 CRITICAL, 1 HIGH, 14 MEDIUM, 23 LOW** (38 findings). Filed before dedup: 69 (0 CRITICAL, 4 HIGH, 22 MEDIUM, 43 LOW), plus 6 ruling residuals that penetration-tester reported without filing.
- By origin: wholly pre-existing are MEDIUM P3R3-13, P3R3-14, P3R3-15 and LOW P3R3-34 to P3R3-38. Pre-existing and made worse, or mixed: P3R3-3, P3R3-18, P3R3-19, P3R3-29. The other 26 are introduced by this diff.
- The one HIGH. **P3R3-1: a Phase plan row the parser does not read is skipped by every gate, so its PR is never read and `done` ends exit 0 `job done`; the phase-2 base refused the same checkpoint (exit 10), and `tests/41-ci-wait.sh:97,132` pins the skip as wanted.** Filed by four reviewers (three HIGH, one MEDIUM), confirmed by the coordinator on the real runner (probes q1 to q3) and by silent-failure-hunter on both trees.
- Reach: no reviewer found a fail-open in this diff's code that a job following both templates word for word reaches. P3R3-1 needs a row written off the template's shape; an indented row, a tab, a missing leading pipe and a second `## Phase plan` heading break no sentence of the template as worded (P3R3-5). Template-reachable fail-opens found: P3R3-15 (pre-existing, by timing) and P3R3-8 (text: a failed `gh pr create` reads as "opened no PR").
- Closed, checked by probes: every `gh` failure, timeout, empty or `null` output, a missing `jq`, and every malformed record field ends in exit 10 or a runner abort (exit 1), never `job done`.
- Round 2's four HIGH: P3R2-2, P3R2-3, P3R2-4 resolved. P3R2-1 reshaped: closed for rows the parser reads, open at the row boundary (P3R3-1) and for a PR written without `#` beside a valid token (P3R3-3).
- Acceptance criteria: **1 met; 2 met; 3 met in part; 4 met; 5 met in part.**
  - 3: a done row the parser does not read is neither read nor refused (P3R3-1); ruling 1 says every done row.
  - 5: tests for 1 to 4 exist and are real, but the texts do not all state the rules as they are (P3R3-2, -4, -5, -6, -16, -17), the README, spec and skill wording has no test (P3R3-7), and one test asserts the opposite of ruling 1 (P3R3-1).
- Largest residual of a ruling (not a defect): under ruling 2 a PR whose head has a workflow file that cannot start on it (a base-branch filter on a stacked PR, a release-only workflow) is refused with no override. The texts give nobody an action for it: that part is P3R3-4.
- Verdict under the skill's rule: no CRITICAL, one HIGH: WARN. The HIGH cap is off; nothing was demoted or promoted to fit a budget.

## How the review ran

The `zord-multi-agent-review` default roster ran: architect-reviewer, critical-thinking, silent-failure-hunter, security-reviewer, penetration-tester; synthesizer knowledge-synthesizer; then a report adversary. The roster's agents are parked, so each ran as a general-purpose agent that read its parked definition read-only. The review ran inline in a coordinator that is itself a subagent. There was no adversarial refutation stage. Only silent-failure-hunter ran scenarios: single scenarios on its own /tmp copy, one at a time (12 runs: `41-ci-wait` eleven times, `40-receipt-required` once, one of them on a phase-2 tree); the others used stub probes (architect-reviewer, security-reviewer, penetration-tester sourced `lib/*.sh` with stubs in their own temp dirs) or read only (critical-thinking). The coordinator's own evidence is `review-phase-3-iter-3/unit-mutants.log`: scenarios 41 and 51 on a /tmp copy, probes q1 to q61 on the real runner, then mutants m1 to m10 and t1 to t5. The synthesizer ran no scenario and no test, and read files only.

One rule of the skill's consolidation reference was not applied, by the coordinator's instruction: "severity tiebreak: pick higher". Where reviewers disagree, each rating is recorded on the finding and the decision rests on five facts: direction, origin, reach by a template-following job, what the phase-2 base did with the same input, and whether the path follows from a binding ruling. No exclusion list was injected into the reviewer brief, so none was applied.

## Findings, MEDIUM and above

| ID | Severity | file:line | Failure path | Suggested fix |
|---|---|---|---|---|
| P3R3-1 | HIGH | `lib/checkpoint.sh:43`; `lib/ci.sh:70-84`; `tests/41-ci-wait.sh:97,132,134` | A done row whose line the row filter drops (key `P1`, a bold key, an indented or tab-led row, no leading pipe, a row after a second `## Phase plan` line) sits beside one readable done row. The receipt gate, the all-rows-done gate and the CI gate all skip it. Its PR is red, unread, stale or absent; run.log says `PRs read: none`; exit 0 `job done`. The phase-2 base: exit 10 | At `status: done`, refuse when the `## Phase plan` section holds a table line that is not the header, the separator or a row the parser returned, and when the file has a second `## Phase plan` heading; name the line. Turn `41:97,132` from "must not hold done back" into a refusal case |
| P3R3-2 | MEDIUM | `templates/brief.md:135-137,169-171`; `lib/ci.sh:45-46`; `tests/51-templates.sh:87-88` | Brief step 4's `absent` sentence gives no instruction for a head with no workflow file (criterion 2's case), tells the child to set `status: blocked` at once where step 9 says only when nothing independent is left, and says "push once more" with nothing to push | Two sentences: with a workflow file, record it under Open or blocked and go on (step 9 decides the status), saying what to push; with none, close the row, the runner lets it through, logged. Pin the qualifier in test 51 |
| P3R3-3 | MEDIUM | `lib/ci.sh:69,72-76,104` | The Status cell is checked by a blacklist of `#<digit>` and `/pull/`, not by grammar. (a) The words `no PR` anywhere in the cell beside a PR written without `#` (`PR 7 · no PR checks failed`) count as the `no PR` statement. (b) A second PR without `#` beside a valid token (`PR #5, 7`) is dropped; `PR #1,234` is read as PR 1. Exit 0 with that PR red | Whitelist: after `done (<sha>)` and before the runner's ` · usage`, accept only one or more `PR #<n>` or `/pull/<n>` tokens, or exactly `no PR`; refuse anything else with the same message |
| P3R3-4 | MEDIUM | `templates/brief.md:135-137`; `skills/blast-off/SKILL.md:34-38`; `lib/ci.sh:94`; `README.md:127,134`; `docs/spec.md:97` | A PR no workflow can start on is refused (ruling 2). No text gives an action: the brief sends the child to `blocked`, README's exit 3 remedy sends the owner back to the same instruction, the exit 10 row tells the owner to "ask the owner", and the skill asks the question before launch and drops the answer | Skill step 4: read the `on:` blocks, tell the owner before launch that `done` will be refused for such PRs, record the owner's choice in brief section 2. Brief, `ci.sh:94`, README: say what the owner can change (the PR's base, the trigger filter) and that `no PR` is not a way out |
| P3R3-5 | MEDIUM | `templates/checkpoint.md:24,33` | The template's only statement of what a row is leaves out three things the parser needs (line starts at the left margin with a pipe, row ends with a pipe, Status is the last cell). A child that indents the table has kept every stated rule and its rows are unseen. Read with line 33, line 24 says how a row leaves the gate | After P3R3-1's fix: "a row is a line that starts with a pipe and a digit at the left margin and ends with a pipe; Status is its last cell; the runner refuses done while the table holds a line it cannot read" |
| P3R3-6 | MEDIUM | `README.md:116,117,128`; `docs/spec.md:35,61,91,97`; `bin/blast-off:18,37`; `lib/chain.sh:96-98`; `lib/ci.sh:57-61`; `templates/checkpoint.md:30-33`; `tests/fakes/claude:17,32` | Twelve sentences are untrue or contradict another: the exit 4 remedy no longer works, "cannot end done either" is not so, "no Phase plan table" is really "no row the runner reads", README puts all-open rows under exit 10, the spec cites a settled owner question as open | Correct each in place, the five about exit 4 and exit 10 first; the "every done row" sentences become true with P3R3-1's fix |
| P3R3-7 | MEDIUM | `tests/51-templates.sh:74-88`; `tests/70-docs.sh:17-25,40-45` | The clause that asks for a CI record, the brief's "where the PR's head has a file" qualifier, all of skill step 4 and the README rule text can be cut or turned round with the gate green; the sentence that says where the runner does not read is pinned | Pin the CI-record clause, the brief's qualifier and one phrase of skill step 4; unpin or reword the mechanism sentence |
| P3R3-8 | MEDIUM | `templates/checkpoint.md:31`; `templates/brief.md:145-146`; `skills/blast-off/SKILL.md:34`; `lib/ci.sh:74-76` | `no PR` is allowed "for a phase that opened no PR", an outcome the child controls. A child whose `gh pr create` failed has, truthfully, a phase that opened no PR; the row closes with `no PR` and no CI is read | Key the permission on the plan: "only for a phase whose brief row says it opens no PR; a PR that could not be opened is a blocked part". Skill step 4 settles which phases have none |
| P3R3-9 | MEDIUM | `templates/checkpoint.md:30-34`; `lib/ci.sh:71-73` | "names the phase's own PR" (singular) with "name another PR in prose" reads two ways. A phase with two PRs of its own puts the second in prose, where it is never read. The runner's own message says "each of the phase's PRs" | "names every PR the phase opened, each as `PR #<n>`; a PR that is not this job's goes in prose" |
| P3R3-10 | MEDIUM | `lib/ci.sh:75,82` | The no-done-row refusal offers `done (<sha>) · no PR` with no condition, and does not say the added rows each need a receipt; the "both" refusal lists dropping the PR as one of two equal moves | Carry line 78's parentheses into line 82; line 75: "if the phase opened PR #<n>, delete `no PR`" |
| P3R3-11 | MEDIUM | `templates/brief.md:136`; `lib/ci.sh:94`; `README.md:118,134` | The texts state the pass condition (no file under `.github/workflows` at the PR's head) and line 94 prints the deciding file, with no sentence that forbids removing or moving a workflow file to change a CI result | One line in brief step 4 or section 4: never remove, move or disable a workflow file to change a CI result; the same beside "there is no override" |
| P3R3-12 | MEDIUM | `lib/chain.sh:94-109,160`; `lib/ci.sh:82`; `README.md:128`; `docs/spec.md:91` | A checkpoint with no row the runner reads (`## Phase Plan`, a header-only table) cannot end `done` as it stands, yet the runner starts it and pays for up to 12 children; the start log says only that the cap is hard | At start, when `cp_phases` is 0, log and print in `preflight`: "no Phase plan row the runner reads: this job cannot end done until the checkpoint has one" |
| P3R3-13 | MEDIUM | `lib/checkpoint.sh:11,43,51,57,69`; `lib/preflight.sh:77` | The row grammar ruling 1 rests on is copied six times; a fix to which lines are rows (P3R3-1) must be made in each, or the gates disagree on which rows exist. Pre-existing | One `cp_rows` function; the five readers pipe from it |
| P3R3-14 | MEDIUM | `lib/ci.sh:85-88,110-116` | Nothing ties the PR a row names to the row: a wrong number typed in the cell that is another green PR of the repo, or the right PR with its head moved to an old green commit, satisfies the gate. Pre-existing (P3R2-9) | At `done`, require the row's sha to be an ancestor of its PR record's `head_sha` (`git merge-base --is-ancestor`); a partial tie |
| P3R3-15 | MEDIUM | `lib/ci.sh:20-33` | `ci-wait` re-lists runs once after the watches; a second workflow's run listed after that is never in the record, and `ci_check` does not list runs at `done`. Reachable by timing alone. Pre-existing | At `done`, list the head's runs and treat an id missing from the record as unread |

## Findings, LOW

| ID | Severity | file:line | Failure path | Suggested fix |
|---|---|---|---|---|
| P3R3-16 | LOW | `README.md:114-119,134`; `docs/spec.md:97`; `lib/ci.sh:78` | A job started before this change is refused at `done` (exit 10) for each done row with no token. No child is launched at `status: done`, so only the owner can edit; no product text says so, nor that the PRs to write are the ones under Completed phases. Fail-closed, with a push toward adding `no PR` to every refused row. Sources: ARCH-9 LOW, CT-10 MEDIUM, SFH-4 LOW, PEN-10 LOW | One README line: write each done row's own PR into its Status cell from the Completed-phases summary; `no PR` only where the summary names none |
| P3R3-17 | LOW | `README.md:114-119,134,143-144`; `bin/blast-off:37-38`; `docs/spec.md:21,35,228,230`; `templates/brief.md:124-125`; `templates/checkpoint.md:31-34`; `tests/fakes/claude:5-11` | Sentences that are stale or leave a case out (list below the table). Sources: ARCH-6 LOW, CT-13 LOW, CT-14 LOW, CT-16 LOW, SFH-14 LOW | Edit in place; none needs code |
| P3R3-18 | LOW | `lib/ci.sh:86,89,92,112-115` | The record is read back with no shape check. A hand-written `success` passes, so do a `success` over a failed run, two JSON values, `pr: 7.0`, and a `head_sha` that is no sha when `gh` prints the same text; bytes after the JSON value abort the runner (exit 1) with no "CI unread" line. Needs a hand-written record; not reachable with a real `gh` for the non-sha forms. Pre-existing (P3R2-10), except that the unchecked text now reaches `git ls-tree`. Sources: SFH-8 LOW, SEC-4 LOW, SEC-6 LOW, PEN-6 LOW | One `jq -e` shape test at `done`: one value, `.pr` the integer, `.head_sha` 40 hex, `.verdict` one of three words; in `ci_head`, `[[ $cur =~ ^[0-9a-f]{40}$ ]]` |
| P3R3-19 | LOW | `lib/checkpoint.sh:44,59` | "Status cell" is whatever cell is last (`$(NF-1)`); the header is never read. A column after Status, an escaped pipe, or a row with no trailing pipe moves it. Mostly fail-closed (exit 9); fail-open when the cell read instead starts `done` and says `no PR`. Sources: ARCH-7 LOW, SEC-12 LOW, PEN-5 LOW | Refuse a done row whose cell count differs from the header row's, or whose header's last cell is not `Status`; treat an escaped pipe as cell text |
| P3R3-20 | LOW | `lib/ci.sh:92-94` | Any path under `.github/workflows` counts as a workflow file (`README.md`, `.gitkeep`, a symlink, `sub/x.yml`, the path as a plain file): absent is refused with "has a workflow file (...README.md)" and "no override". `2>/dev/null` hides why git failed, so every failure gets the "fetch" advice. Fail-closed; ruling 2 says "a file", owner question 3 is not ruled. Sources: SFH-9 LOW, SEC-9 LOW (also PEN-8, third item) | Count only `*.yml` and `*.yaml` directly in the directory, or say in the README that any file counts; keep git's stderr in the message |
| P3R3-21 | LOW | `tests/41-ci-wait.sh:115,204,209`; `tests/70-docs.sh` | Test gaps: mutants m3, m8, S1 to S5 survive; `41:115` greps a line an earlier run already wrote; `41:204` accepts any refusal for seven cells; `41:209` accepts exit 9 or 10 and does not assert PR 7 was read; four kills are by message text only. Sources: ARCH-12 LOW, SFH-12 LOW | Fixture cells `No PR` (passes) and `PR #8 see /pull/x` (refused); cases for a record with no `head_sha` while gh fails, a tree-sha head, `no PRs`, a PR named twice; per-run log greps |
| P3R3-22 | LOW | `lib/ci.sh:91,93,94,96` | Refusal lines as instructions: `:93` assumes a remote named `origin` on GitHub and prints `$TOP` unquoted; `:94` sends a push before a second `ci-wait`; `:91` does not say run what; `:96` names no gate or receipt for the fix commit. Sources: ARCH-13 LOW, CT-12 LOW | Reword: `:94` first `ci-wait` again, then an empty commit and push; `:93` "fetch the PR's head (on GitHub: `git fetch <remote> pull/<n>/head`)"; name the command in `:91` |
| P3R3-23 | LOW | `lib/ci.sh:92` | `git ls-tree` honours replace refs: after `git replace <PR head> <a commit with no workflow file>` an absent record passes. On purpose only; such a child can also write the record by hand. Sources: SEC-5 LOW, PEN-7 LOW | `git --no-replace-objects -C "$TOP" ls-tree ...` |
| P3R3-24 | LOW | `lib/ci.sh:95` | The pass line says "no CI configured", which is more than was read: only Actions runs of the head and the head's tree were read. A PR that deletes the directory, a case-variant directory, or CI from another service logs the same line. Sources: SEC-8 LOW, SFH-13 LOW | Log what was read: "no Actions runs and no file under .github/workflows at its head <sha>"; name the base when the base has a workflow file the head lacks |
| P3R3-25 | LOW | `lib/ci.sh:74-76,84`; `templates/checkpoint.md:50-52` | A false `no PR` leaves no trace: the cell can disagree with the Completed-phases line, and a CI record no row names lies unused in `gate-logs/`. The pass itself is ruling 1. Sources: SEC-13 LOW, CT-17 LOW | Log a warning (not a refusal) when a row says `no PR` while a `ci-pr-*.json` exists that no row names; README: compare `CI at done: PRs read` with the final report |
| P3R3-26 | LOW | `templates/checkpoint.md:33`; `tests/51-templates.sh:78` | "It reads PRs nowhere else in this file" tells a child where the gate does not look, and it is the pinned sentence. Sources: CT-6 MEDIUM (SFH-14, second half, LOW on the same sentence) | Drop the mechanism clause from the child-facing comment or say "another repo's PR" for "another PR"; add that a false `no PR` is reporting a check that was not run |
| P3R3-27 | LOW | `lib/ci.sh:70-81` | One refusal per run: `chain_end` at the first bad row, so a checkpoint with five rows to fix takes five runs to list them. Fail-closed. Sources: CT-18 LOW | Collect the bad rows, refuse once |
| P3R3-28 | LOW | `lib/ci.sh:72-75` | Honest cell forms are refused: `[#7](https://github.com/o/r/pull/7)`, a form the template's "(or its /pull/<n> link)" allows, is refused as a stray `#7` (the base passed it with a green record); `PR #7 · no PR checks` is refused as "both". Sources: PEN-8 LOW | Take a whole markdown link `[...](.../pull/<n>)` out as one token before the stray test; P3R3-3's grammar handles the second |
| P3R3-29 | LOW | `lib/ci.sh:104` | Another repo's `/pull/N` link inside a Status cell is read as this repo's PR N. Fail-closed in the usual case; fail-open for N when this repo has a green record of that number. Pre-existing (P3R1-30), now confined to done cells. Sources: SEC-11 LOW | Accept `/pull/N` only without a host, or with the workdir remote's host and path |
| P3R3-30 | LOW | `tests/fakes/claude:30-43,74,76,89,96` | `fin` in the fake masks no assertion, but leaves four couplings: a second copy of the receipt's shape and the row format, the repo read from `dirname "$JOB_DIR"` not the workdir, a forged receipt beside an uncommitted path, stale mode comments. Sources: ARCH-8 LOW | None needed for correctness; fix the comments |
| P3R3-31 | LOW | `lib/ci.sh:72-82`; `lib/receipt.sh:68-71`; `README.md:134` | Exit 10 now means three unrelated things (CI red or unread, a malformed row text, no done row), and the plan-shape refusals live in the CI module while the sibling "row not done" is exit 9. Sources: ARCH-11 LOW | Split `ci_check` into row policy and record policy; whether row refusals move to exit 9 is the owner's call |
| P3R3-32 | LOW | `lib/ci.sh:72,81,104` | Statuses dropped on the gate's read path: a failing `sed` at `:72` turns the stray check off (reasoned, not run); `cp_done_cells` through process substitution hides a failing `sed` or `awk`; a `grep` error reads as "no PR named". Fail-closed today. Sources: SFH-11 LOW | Read `cp_done_cells` into a variable, `die` when it fails, then loop over the variable; write the strip without the `I` flag |
| P3R3-33 | LOW | `lib/ci.sh:92` | In a partial clone `git ls-tree` at `done` starts a network fetch with no time limit while the runner holds the job lock. A hang, not a bypass. Sources: SEC-10 LOW | `timeout "${BLAST_OFF_CI_HEAD:-60}" git ...` |
| P3R3-34 | LOW | `lib/checkpoint.sh:37-38,52,60`; `lib/receipt.sh:50-51` | Two rows with one key: the receipt gate reads the first row's sha for both, so the second row's commit needs no receipt. The CI gate reads each. Pre-existing. Sources: ARCH-10 LOW | Refuse a duplicated key at `done` |
| P3R3-35 | LOW | `lib/ci.sh:45,91,93,96,115` | A record's `head_sha` and a run's `name` are written raw into `run.log`: a forged `job done` line, terminal escapes. The exit code is unchanged. Pre-existing (P3R2-30); two more print sites added. Sources: SEC-7 LOW | P3R3-18's sha check; `@json` for `.name` at `:45` |
| P3R3-36 | LOW | `lib/ci.sh:36-43` | A `ci-wait` that dies part-way keeps the older record in force and leaves a half-written `.tmp` with verdict `success`. Reached only by a child that goes on after `ci-wait` exits 1. Pre-existing (P3R2-28). Sources: SFH-7 LOW | Remove the record and its `.tmp` at the start of `ci_wait` |
| P3R3-37 | LOW | `lib/ci.sh:21,26,113`; `lib/chain.sh:89-91` | `BLAST_OFF_CI_APPEAR`, `_WATCH` and `_HEAD` are not checked as numbers: `60s` skips the wait, `abc` skips the watch with no log line. Fail-closed. Pre-existing. Sources: SFH-10 LOW | Validate the three as `chain_nums` does |
| P3R3-38 | LOW | `lib/ci.sh:113` | `timeout` without `-k` around `gh pr view`: a `gh` that ignores SIGTERM hangs the runner at `done`. Pre-existing. Sources: SEC-14 LOW | `timeout -k 5 ...` |

### LOW findings where reviewers' ratings differ

- **P3R3-16** (CT-10 MEDIUM; ARCH-9, SFH-4, PEN-10 LOW). Decision: LOW. It is fail-closed; ruling 1 itself orders the edit ("existing checkpoints ... add `no PR` to rows that have none"); and the refusal already says what to write (`ci.sh:78`; silent-failure-hunter probe H1: exit 10, `after the sha write PR #<n> (the phase's own PR) or no PR (the phase opened none)`). What is missing is one README sentence. PEN-10's point stands inside the LOW: an owner who adds `no PR` to every refused row takes PRs the base gated out of the gate, so the sentence should say where the PR numbers come from.
- **P3R3-26** (CT-6 MEDIUM; silent-failure-hunter rates the same sentence LOW inside SFH-14). Decision: LOW. The sentence is true and states ruling 1's own rule ("nothing in prose is ever read"), which `README.md:118-119` states as well; the obligation that guards it stands one sentence earlier and is pinned; and under ruling 1 a false `no PR` passes whether or not the template says where the runner reads. It differs from P3R3-10, kept at MEDIUM, in that P3R3-10's line leaves out a condition the ruling carries, while this sentence leaves nothing out. That the test pins this sentence and not the CI-record clause is P3R3-7.

### LOW bundles, item by item

P3R3-17, stale sentences and left-out cases:
1. `README.md:114-119` and `bin/blast-off:37-38` leave out three refusals the code makes: a cell with both, a stray `#<n>` or `/pull/`, and `absent` with a head git cannot read or no git repo. The header also leaves out "no done row". (ARCH-6, CT-16, SFH-14)
2. `README.md:134` and `bin/blast-off:37` call exit 10 "done refused" only; `ci-wait` itself exits 10 on red or absent, also where `done` will pass. (ARCH-6, CT-16)
3. `docs/spec.md:230`, the `51-templates` row, does not name the new pins. (ARCH-6)
4. `docs/spec.md:228`, the `41-ci-wait` row, does not say the scenario pins a non-digit row's PR as not read, or the NUL case; "a run of any event but `workflow_dispatch` counts" is tested for `push` only. (ARCH-6)
5. `docs/spec.md:21` (K3): "phase row carries PR number"; now PR number or `no PR`. (ARCH-6)
6. `README.md:143-144`: the list of rules the templates carry lacks the `PR #<n>` or `no PR` rule. (ARCH-6)
7. `tests/fakes/claude:5-11`: six modes are described as "done"; each now also appends a table and, in git, a receipt. (ARCH-6)
8. `templates/brief.md:124-125`: a duplicate PR is "named the way the checkpoint's rules comment says for a PR this job does not own"; the comment no longer gives a way, only a place. (ARCH-6, CT-13)
9. `templates/checkpoint.md:31-32`: "wants a CI record" lost its exit code and never says the record must be green, of the head now, or what `absent` does. (CT-14)
10. The `no PR` condition is worded three ways (README "for a phase that opened no PR", template "only for a phase that opened no PR", skill "a phase with no PR", no "only"); the template says "closed row", everything else "done row"; README shows only `PR #<pr>` where the template adds the link form and the spec adds case and leading zeros. (CT-16)
11. `docs/spec.md:35` (F7) still names `lib/chain.sh` as the refuser. (CT-16; also row 9 of P3R3-6)
12. `templates/checkpoint.md:33-34`: "name another PR in prose" should say "another repo's PR". (SFH-14, second half; see also P3R3-26)

P3R3-18, record shapes (all need a hand-written record): passes on `success` over a failed run (SFH C5, PEN row 101; scenario 41 relies on it at `:109`); two values, success then another PR's failure (SFH C3, PEN row 102); `pr: 7.0` or `8.0` (SFH C6); `head_sha: "null"` with gh printing a null head (SFH C11, SEC-4, PEN row 104); a short sha, a branch or tag name, `HEAD~1` as `head_sha` with gh printing the same (SEC-4, PEN row 67). Refused as they should be: `pr` a string, success then failure, no `head_sha` with gh failing, an empty file, verdict `skipped`, option-shaped text, a tree sha. Trailing garbage: `rc=5 (no END line)`, runner exit 1 (SEC-6).

P3R3-19, which cell is read: a fifth column whose text starts `done` and says `no PR` (ARCH-7 case G, SFH probe A5: `exit 0 ... rows that say no PR: 0 1`; base exit 10); an escaped pipe inside the Status cell (SEC-12); no trailing pipe with a "Done when" text that starts "done", holds a hex word and says `no PR` (PEN-5 row 73, full order with a real receipt: PASS; base E10 red). Each fail-open form carries the words `no PR` in the cell the parser reads.

P3R3-21, surviving mutants: coordinator m3 (`no PR` matched case-sensitively) and m8 (stray check without `/pull/`); silent-failure-hunter S1 (`sort -un`), S2 (`grep -a`), S3 (the `[ -n "$cur" ]` guard in `ci_head`), S4 (`^{commit}`), S5 (the word boundary of `no PR`). See Test realness.

P3R3-30, the fake's `fin`: scenarios 10, 11, 12, 20, 21, 22, 23, 30, 31, 32, 40, 50 were read by architect-reviewer and 41, 21, 32, 40 by silent-failure-hunter; neither found a masked assertion. The hard cap (exit 4) uses mode `step`, not `fin`; a job with no table refused at `done` is `41:160-162` with a pre-set status; receipts are scenario 40, whose jobs carry their own table.

## Detail, MEDIUM and above

#### P3R3-1: a Phase plan row the parser does not read is skipped by every gate

- Sources and ratings: ARCH-1 HIGH, SFH-1 HIGH, PEN-1 HIGH, SEC-1 MEDIUM. PEN-1 adds that a synthesizer who weighs likelihood first may put it at MEDIUM; SEC-1's reason for MEDIUM is the off-template reach ("honest but sloppy child").
- Decision: HIGH. It is fail-open, introduced by this diff for the CI gate (the base's `ci_check` did not use the parser and refused the same file), it does not follow from a ruling (the row says `PR #7`, never `no PR`), it falls short of ruling 1 ("every done row") and of criterion 3, and the suite asserts it as wanted. The off-template reach lowers how often it happens; it does not change that the gate this phase exists to close lets a red PR through where its base did not.
- Direction: fail-open.
- Origin: introduced by this diff for the PR read. The same blindness in `receipt_check` and `receipt_all_done` is pre-existing (an open or sha-less unread row passed on both trees: SFH probe A7, PEN row 27).
- Reachability: only by an off-template checkpoint, beside at least one readable done row. Forms measured: keys `P1`, `R1`, `Phase 1`, `v1`, `one`, `#1`, `(1)`, a bold, backtick or struck-through key, a circled or Arabic-Indic digit; a row indented one space; a tab before the row or after the first pipe; a no-break space, zero-width space, byte-order mark or NUL before the key; no leading pipe; a row inside a blockquote or an HTML comment; a row after a second `## Phase plan` line or a `## Phase plan (continued)` line. An indented row, a tab, a missing leading pipe and the second heading break no sentence of `templates/checkpoint.md:24` as worded (P3R3-5).
- The boundary, from the logs:
  - No readable done row at all: refused, exit 10 (q4; q61, two adjacent headings with all rows after them; PEN rows 29, 91).
  - A second `## Phase plan` line after a readable done row: fail-open (SFH A4, PEN row 23, ARCH case S2).
  - A row the parser reads but does not class as done: refused, exit 9 (q6 no trailing pipe, q7 a check-mark before `done`, q8 bold `done`, q9 `complete`, q11 key `1)`, q12 a cell after Status).
  - Two `## Phase plan` sections with another section between: both read, exit 10 (PEN row 90, ARCH case S3).
- Disputed sub-case: a digit-keyed row cut off by another `## ` line inside the table (`## Phase 1 notes`, then the row). ARCH-1 (cases S1, K) and SEC-1 count it here; penetration-tester files it as residual R-6 of issue 26's scope, pinned at `41:98-99` by round 1's request (P3R1-15). Decision: listed here, because neither ruling covers it and the base refused it (PEN row 22: now PASS, base E10 red); the HIGH rating does not rest on it. It needs its own rule (a table line directly under a heading with no header of its own, or a remembered row count) and the owner's word, since `41:98-99` asserts the opposite for a row under `## Decisions`.
- Evidence. Coordinator, real runner, PR #7's red record in the job:
  ```
  PROBE q1 [| 0 | a | b | done (abc1234) · no PR | ;; | P1 | a | b | done (abc1234) · PR #7 | ;; ]: exit 0: 2026-11-16T08:07:55Z job done
  PROBE q1 readline: 2026-11-16T08:07:55Z CI at done: PRs read: none; rows that say no PR: 0
  ```
  Silent-failure-hunter, same probe on the phase-2 tree: `PROBE A1 key P1  exit 10 | | last: PR #7 CI red or unfinished at 1111111111111111111111111111111111111111`. Penetration-tester: with PR 7 having no record, PASS against base `E10 norecord`; with a stale record, PASS against `E10 stale`; with row 0 naming a green PR #5, PASS with `PRs read: 5`. `tests/41-ci-wait.sh:97` puts `| P1 | a | b | c | done (abc1234) · PR #96 |` in the table and `:132` fails the scenario if PR #96 is read.
- Lineage: round 1's P3R1-17 and P3R1-29, round 2's P3R2-12 and P3R2-20; the fix baton calls it a "deliberate limit, open" and pre-existing. Measured against this diff's base it is new for the CI gate.
- Fix: keep ruling 1 (no prose read). One function in `lib/checkpoint.sh`, called at `status: done`: exit 10 (or 9, beside `receipt_all_done`) when the section holds a line with a pipe that is not the header, the `|---|` separator or a row `cp_plan_rows` returned, and when the file has more than one `^## Phase plan` line; the message names the line. Penetration-tester checked one form on the template (prints nothing) and on the attack files (prints the hidden row): `sed -n '/^## Phase plan/,/^## /p' checkpoint.md | grep -a '|' | grep -avE '^\| *[0-9]|^\| *# *\||^\|[ :|-]+$'`. Turn `41:97,132` round. A duplicated key (P3R3-34) and the header check (P3R3-19) fall out of the same function.

#### P3R3-2: brief step 4's `absent` sentence

- Sources and ratings: ARCH-2 MEDIUM, CT-2 MEDIUM, CT-3 MEDIUM, SFH-2 MEDIUM. Penetration-tester filed nothing and reads the sentence the other way: "an obedient child reaches it: `templates/brief.md:135-137` sends only heads with a workflow file to push once more".
- Decision: MEDIUM, as all four filers rate it.
- Direction: fail-closed (the job stops at exit 3, or the child guesses).
- Origin: introduced by this diff (the sentence is new; `ci_wait` exiting 10 on absent is older).
- Reachability: yes, by any template-following job in a repo with no workflow file (criterion 2's case), and by any job whose PR gets no run.
- Evidence. The sentence: "`absent`, no runs, is not a pass: where the PR's head has a file under `.github/workflows/` push once more for a run, and if none starts leave the row open, set `status: blocked` and record it under Open or blocked". Three faults:
  1. No words for a head with no workflow file. What the child sees there is one line, `ci PR #9 at 3333333333333333333333333333333333333333: absent ()` (SFH probe G3), exit 10, beside "is not a pass". Criterion 2 is reached only by a child that reads the silence as "go on". critical-thinking judges a literal child takes that reading; `brief.md:83` ("Unrun is not passed") pushes the other way. The phase-2 skill told the author to write the pass-through into the brief; the new step 4 no longer does.
  2. Step 9 (`:169-171`): "Blocked parts do not stop the job ... Set `status: blocked` only when nothing independent is left." Step 4 says set it at once.
  3. "push once more": the branch is already pushed, so `git push` starts nothing; the next line the child reads is "No code commit after the receipt".
  `tests/51-templates.sh:88` pins "is not a pass" and "set `status: blocked`", not the qualifier: mutant t4 is killed, but the "where the PR's head has a file" clause can be cut with no test failing.
- Fix: as in the table; have `ci_wait` print on absent which case this is and what to do.

#### P3R3-3: the Status cell is checked by a blacklist, not by grammar

- Sources and ratings: path (a) SEC-2 MEDIUM, SFH-6 LOW, PEN-4 LOW; path (b) SEC-3 MEDIUM, PEN-2 MEDIUM.
- Decision: MEDIUM, one finding, because all five name the same fix. Path (b) is MEDIUM by both filers. Path (a) shares its facts (fail-open, off-template, the same base behaviour), so it is not rated apart. The two LOW ratings on (a) have different grounds. PEN-4 is LOW because it reads most of (a) as ruling 1's residual; that holds only for a cell that states `no PR` and nothing else (see "Where the line to ruling 1 runs" below and Residuals). SFH-6 is LOW because it calls (a) pre-existing: "phase 2 passed the same cells, run 3". The logs settle that split: silent-failure-hunter's base fixture had no Completed-phases line naming the PR, and the base passed (its phase-2 probes B1 to B7: exit 0); where such a line names the PR, as the template prompts at `templates/checkpoint.md:50-51`, the base refused (security-reviewer's template-shaped run: `phase2-would-read=[7] => phase 2: failure arm, exit 10`; penetration-tester rows 52 and 53: base+prose `E10 red`, base without the prose line PASS). So for a checkpoint written the template's way (a) is a weakening against the base, not pre-existing.
- Direction: fail-open.
- Origin: (a) the `no PR` matcher and the stray check are new in this diff; whether the outcome is new depends on the prose line, as above. (b) the token grammar is pre-existing and made worse: the base read `PR #8` from the Completed-phases line and refused.
- Reachability: only by an off-template checkpoint. (a) needs a PR written without `#<digit>` and the words `no PR` in the same cell. (b) needs a phase with two PRs (brief section 8 says one) and the second written without `#`, or a thousands separator.
- Where the line to ruling 1 runs: a cell whose only PR statement is `no PR` (any case, in brackets, with a full stop, "no PR yet") is the ruling's explicit `no PR`. A cell that also names a PR in a spelling the runner does not read, or where `no PR` is part of other words ("no PR checks failed"), is this finding: the code's own "both" refusal (`ci.sh:75`) and P3R2-6's fix ("a PR written a way the runner does not read is refused, never passed as no PR named") show the intent, enforced only for `#<digit>` and `/pull/`.
- Evidence. Coordinator: `PROBE q13 [| 0 | a | b | done (abc1234) · no PR, see PR 7 | ;; ]: exit 0 ... job done`, `PRs read: none; rows that say no PR: 0`; q14 the same for `no PR (was pull request 7)`. Security-reviewer, template-shaped checkpoint, red record for PR 7: `cell=[done (abc1234) · PR 7 · no PR checks failed]  LOG CI at done: PRs read: none; rows that say no PR: 0  PASSED: job done rc=0  phase2-would-read=[7] => phase 2: failure arm, exit 10`. Path (b): `cell=[PR #7, 8], Completed-phases entry "PR #7, PR #8"  PRs read: 7  PASSED: job done rc=0  phase2-would-read=[7 8] => PR 8 red, exit 10`; `cell=[PR #1,234], green record for PR 1  PRs read: 1  PASSED`. Penetration-tester rows 34 to 42: `PR #5 and PR 7`, `PR #5, 7`, `PR #5/7`, `PR #5 (supersedes PR 7)`: PASS(read=5) / base+prose E10 red. `PRs read: 7` looks healthy in run.log, so (b) is harder to see afterwards than (a). Controls that are refused: `PR #5, #7`, `no PRs`, `no  PR`, `no-PR`, `PR #7 · no PR checks` (both). Locale: under `LC_ALL=C` a cell that starts the words with a non-ASCII letter reads as `no PR`.
- Fix: as in the table. It makes `stray` unnecessary and closes mutant S5's gap.

#### P3R3-4: a PR no workflow can start on has no action in any text

- Sources and ratings: CT-1 HIGH (its own note: "borderline HIGH or MEDIUM"), SFH-3 MEDIUM, CT-15 LOW (skill step 4's wording, "fold into CT-1's fix"). Penetration-tester reports the dead end as residual R-4 and calls the child's `blocked` "the honest end".
- Decision: MEDIUM. It is fail-closed; the refusal is ruling 2 and the missing override is owner question 3, put in round 2 and not ruled (P3R2-8), so neither is a defect of this diff. What this diff adds is words that send child and owner round a loop and a skill step that collects the fact and drops it: a text shortfall, which SFH-3 rates MEDIUM for the same facts.
- Direction: fail-closed, with a push toward a fail-open edit (a false `no PR`, a hand-written record).
- Origin: introduced by this diff (the texts); the dead end itself is on record as P3R2-8.
- Reachability: yes. Surest case: a repo whose only workflow file is a release, schedule or dispatch one (any file counts, `ci.sh:92-94`). Also a repo with `on: pull_request: branches: [main]` once a phase's PR is opened on the previous phase's branch, as `brief.md:108` prescribes; that half is from the reviewers' recall of GitHub, not tested. blast-off's own `ci.yml` has no filter.
- Evidence, the loop by file:line: `brief.md:135-137` sets `status: blocked` (exit 3, `chain.sh:161`); `README.md:127` tells the owner "answer what `Open or blocked` asks, set `status: running`, `start` again", and the next child reads the same step 4; if the owner closes the row by hand, `ci.sh:94` refuses with "there is no override: ask the owner", and at `status: done` the reader of that line is the owner; `README.md:134` ends the same way in the owner's "What to do" column; `SKILL.md:36-38` has the author "ask whether the repo's workflows start on the stacked PR branches, and put the answer in brief §2" with nothing for the answer "no". CT-15: the fact is in the `on:` blocks the agent already reads; "start on the ... branches" fits a `push` filter, not a `pull_request` base filter; a fact has no "recommendation" in prompt-only mode.
- Fix: as in the table. critical-thinking's question for the owner: for such a repo, is the wanted end state a job that ends `blocked` every time, or a delivery shape that gets runs?

#### P3R3-5: the template's row sentence says less than the parser needs

- Sources and ratings: CT-9 MEDIUM, PEN-9 LOW.
- Decision: MEDIUM. Line 24 is the only place a child is told what a row is, and it is incomplete in three measured ways, so part of P3R3-1 is reachable by a child that keeps every stated rule. That differs from P3R3-26, where the sentence is true and complete.
- Direction: neither as text; it feeds a fail-open today, and a fail-closed surprise once P3R3-1 is fixed.
- Origin: line 24 pre-existing and made worse (it now also describes a way out of the CI check); line 33 introduced by this diff.
- Reachability: yes, it is the template.
- Evidence: `templates/checkpoint.md:24`: "Each row's first cell starts with a digit (0, 1, 2a): the runner only sees rows like that". Unstated: the line must start at the left margin with a pipe then spaces only (PEN rows 13 to 19), the row must end with a pipe (q6: exit 9), Status must be the last cell (q12: exit 9). The spec has the last of these (`docs/spec.md:97`); the template does not.
- Fix: as in the table, with P3R3-1.

#### P3R3-6: sentences that are untrue or contradict another

- Source and rating: ARCH-5 MEDIUM as a set ("each alone is LOW"). No other reviewer rated the set.
- Decision: MEDIUM, as filed; criterion 5 asks that the texts state the rules as they are.
- Direction: neither, except item 1 (points at an edit that does not work) and item 6 (hides P3R3-1).
- Origin and reachability: per item; these are what the owner and child read.
- Evidence, the twelve:
  1. `README.md:128`: exit 4 remedy "add a Phase plan table, or raise `JOB_MAX_CHILDREN`"; the same row now says such a job cannot end `done`, so raising the cap alone ends in 4 again or in 10. This diff.
  2. `README.md:128`, `lib/chain.sh:97-98`: "such a job cannot end `done` either". It can once a child adds a table with a done row; the suite's own fake does that. This diff.
  3. `README.md:128`, `docs/spec.md:91`, `bin/blast-off:18`, `lib/chain.sh:96`: the condition is called "no Phase plan table"; it is `cp_phases` = 0, which a header-only table, `## Phase Plan` or only `P1` rows also give. Pre-existing, now load-bearing for exit 10.
  4. `README.md:117`: exit 10 "while the job has no done row at all"; a table whose rows are all open is exit 9. This diff.
  5. `docs/spec.md:97`, end: cites owner question P4Q1 as if open (ruling 2 settled it), and "absent is never reported as green" stands in the row that says `done` is let through on `absent`. This diff.
  6. `docs/spec.md:35`, `README.md:116`, `bin/blast-off:37`, `templates/checkpoint.md:30-32`, `lib/ci.sh:57-61`: "every done Phase plan row"; true only of rows the parser reads (P3R3-1). This diff.
  7. `docs/spec.md:97`: "its Status cell is the last cell"; only when the row ends in a pipe and Status is the last column. This diff.
  8. `docs/spec.md:61`, `lib/checkpoint.sh:10`: rows "whose first cell is a number"; it is "starts with a digit" (`2a` counts). Pre-existing.
  9. `docs/spec.md:35`: names `lib/chain.sh` as the refuser and `blast-off ci-wait <pr>`; it is `ci_check` in `lib/ci.sh` and `ci-wait <job-dir> <pr>`. Pre-existing, in a sentence this diff edited.
  10. `templates/checkpoint.md:33`: "refuses any other '#<n>' in a Status cell"; only in a done row's cell. This diff.
  11. `tests/fakes/claude:32`: the receipt is "written here as `blast-off receipt` would"; `fin` writes four of the eight fields and does so with uncommitted paths present. This diff.
  12. `tests/fakes/claude:17`: close-sha writes "`done (<sha>)`"; it writes `done (<sha>) · no PR`. This diff.
  The other comments in `lib/ci.sh` were checked line by line and are true as written.
- Fix: correct each in place, items 1 to 5 first.

#### P3R3-7: which new sentences are pinned, and which can be turned round with the gate green

- Source and rating: CT-11 MEDIUM. SFH-12 (LOW, P3R3-21) says the same of `tests/70-docs.sh`.
- Decision: MEDIUM, as filed: criterion 5 names `tests/51-templates.sh` for template text.
- Direction: neither. Origin: introduced by this diff. Reachability: n/a (test adequacy).
- Evidence. Pinned (`51:74-79,87-88`; mutants t1 to t5 all killed): the "names the phase's own PR ... or says `no PR`" sentence, "Write `no PR` only for a phase that opened no PR.", "The runner refuses done (exit 10) for a closed row with neither", "It reads PRs nowhere else in this file", and three brief phrases. Not pinned: `checkpoint.md:32` "and wants a CI record (`blast-off ci-wait`) for each PR named there", the only sentence in the comment that asks for CI; `:33-34` "refuses any other '#<n>' ..."; `:27-28`; `brief.md:136` "where the PR's head has a file under `.github/workflows/`" and "push once more"; `brief.md:146`; all of skill step 4; `README.md:114-119` and the text of row 10 (`70-docs:40` checks only that a row for 10 exists); the refusal lines at `ci.sh:73` and `:82` past their first words. The two forbidden strings (`51:82`) are exact matches: "is not CI-checked" passes.
- Fix: as in the table.

#### P3R3-8: `no PR` is licensed by a fact the child controls

- Source and rating: CT-5 MEDIUM. The pass on an explicit `no PR` is ruling 1 (Residuals); the finding is what the texts key the permission on.
- Decision: MEDIUM, as filed.
- Direction: fail-open (a phase the brief gave a PR ends `done` with no PR and no CI read).
- Origin: introduced by this diff (the `no PR` texts).
- Reachability: yes when `gh pr create` fails or is refused (auth, rate limit, no commits between the branches): the phase then "opened no PR", literally. Otherwise only by a child that skips "push and open the draft PR".
- Evidence: `templates/checkpoint.md:31` "Write `no PR` only for a phase that opened no PR"; `SKILL.md:34` "a phase with no PR closes its row with `no PR`" in the same bracket as "one stacked draft PR per phase", with no word on which phases may have none or who decides; `brief.md:69-71` ("a refused tool call blocks that part") points the other way and nothing ranks the two; `ci.sh:74-76` takes the words as given.
- Fix: as in the table.

#### P3R3-9: "the phase's own PR ... name another PR in prose"

- Source and rating: CT-4 MEDIUM.
- Decision: MEDIUM, as filed.
- Direction: fail-open. Origin: introduced by this diff.
- Reachability: only when a phase has two PRs of its own (off brief section 8).
- Evidence: `templates/checkpoint.md:30-34` against the runner's line `ci.sh:73` "write each of the phase's PRs as `PR #<n>`". The code accepts several tokens in one cell (q39; `ci_prs` collects each). Template and runner message disagree on whether a cell may hold more than one. Read, not run.
- Fix: as in the table.

#### P3R3-10: two refusal lines offer `no PR` without its condition

- Source and rating: CT-7 MEDIUM. Penetration-tester, on the same lead: "No refusal message, README line, spec line or template line I read tells anyone to swap `PR #7` for `no PR` after an exit 10."
- Decision: MEDIUM, as filed. Both readings are true of the text: no line says "swap", and line 82 lists `done (<sha>) · no PR` with none of line 78's conditions. Under ruling 1 the cell's words are the gate for a named PR, so the words handed out at the moment of refusal matter.
- Direction: fail-open by a later edit, not by the code. Origin: introduced by this diff.
- Reachability: line 82 only for a job with no readable table; line 75 only for a cell with both.
- Evidence: `ci.sh:78` "`PR #<n>` (the phase's own PR) or `no PR` (the phase opened none)"; `ci.sh:82` "that ends `done (<sha>) · PR #<n>` or `done (<sha>) · no PR`"; `tests/fakes/claude:33-43` is that exact edit with a hand-written PASS receipt beside it. Line 82 does not say the added rows each need a receipt (the next run is exit 9).
- Fix: as in the table.

#### P3R3-11: no sentence forbids changing workflow files to meet the pass condition

- Source and rating: CT-8 MEDIUM. The path itself (a head with no workflow file passes) is ruling 2 (Residuals; PEN R-3, SEC-8).
- Decision: MEDIUM, as filed.
- Direction: fail-open. Origin: introduced by this diff (the texts).
- Reachability: only when `.github/workflows` is in the job's Target set; otherwise the Target set rule stops an obedient child.
- Evidence: `brief.md:136` names the child's decision test; `ci.sh:94` prints the deciding file ("has a workflow file (.github/workflows/ci.yml)") right before "there is no override". Penetration-tester measured that a head which removes the directory lists nothing (`ls-tree` by hand: passes). That GitHub then starts no run is from recall.
- Fix: as in the table.

#### P3R3-12: a job that cannot end `done` is started without a word

- Source and rating: ARCH-3 MEDIUM.
- Decision: MEDIUM, as filed.
- Direction: fail-closed. Origin: introduced by this diff (in phase 2 the hard-cap job could end `done`; refusing a job with no done row is the fixer's fail-closed reading of ruling 1, stated in `docs/spec.md:97`).
- Reachability: no for the template (it has a table); yes for a mis-typed heading, a header-only table, or rows keyed without a digit.
- Evidence: q4 (`exit 10 ... status done but the Phase plan has no done row`), q61; `chain_cap` logs `child cap 12 (hard: no Phase plan table in checkpoint.md)` and up to 12 children run; at `status: done` no child is launched (`chain.sh:160`), so only the owner can repair the checkpoint.
- Fix: as in the table. The larger one, refusing to start such a job and retiring exit 4, is the owner's call: `tests/lib.sh` `new_job` writes no table.

#### P3R3-13: the row grammar is copied six times

- Source and rating: ARCH-4 MEDIUM.
- Decision: MEDIUM, as filed (a maintainability concern by the rubric's own words).
- Direction: neither. Origin: pre-existing (round 2's P3R2-21 fixed only the copy phase 3 had added). Reachability: n/a.
- Evidence: `grep -n "Phase plan/,"` over `lib`: `lib/checkpoint.sh:11,43,51,57,69` (the last as a `sed -i` address) and `lib/preflight.sh:77`.
- Fix: as in the table; do it with P3R3-1.

#### P3R3-14: nothing ties the PR a row names to the row

- Source and rating: PEN-3 MEDIUM. Pre-existing: round 2's P3R2-9, set aside as out of scope.
- Decision: MEDIUM, as filed and as round 2 rated it.
- Direction: fail-open. Origin: pre-existing; on the base the template-shaped file was refused only because prose also named `PR #7`.
- Reachability: yes by a slip (a wrong number typed in the cell), otherwise on purpose.
- Evidence: penetration-tester row 44: cell `PR #5`, PR 5 green, PR 7 (the phase's real PR) red: `PASS read=5 / E10 red / PASS`. Row 45: `PR #7`, record green at commit A, head set back to A: PASS on all three. The unread refusal tells the child `blast-off ci-wait <job-dir> 5, then run again`, which turns the slip into a pass.
- Fix: as in the table.

#### P3R3-15: `ci-wait` never reads a run listed after its last re-list

- Source and rating: SFH-5 MEDIUM. Outside this diff; reported because it is the one fail-open found that a template-following job reaches through code.
- Decision: MEDIUM, as filed.
- Direction: fail-open. Origin: pre-existing. Reachability: yes, by timing.
- Evidence: silent-failure-hunter probe I3: `ci-wait, a red run listed only from the third list on: exit 0 | record: {"verdict":"success","runs":[95]} | run lists made: 2`. How often GitHub lists a push's runs apart is from recall.
- Fix: as in the table.

## Residuals of the owner rulings

These paths exist because a ruling says so. They are not counted as defects. Where a reviewer filed a text or log shortfall on the same path, that shortfall has its own ID.

Ruling 1 (the cell is the declaration; nothing else is read):

1. **An explicit `no PR` on a row that has a PR passes with that PR red, unread or absent.** Row `done (abc1234) · no PR`, PR 7 red, `PR #7` still under Completed phases: exit 0, `PRs read: none; rows that say no PR: 0 1`. The base refused it when prose named the PR, passed it when not. Pinned as ruled at `tests/41-ci-wait.sh:181-184`. The same for `NO PR`, `No pr`, `(no PR)`, `no PR.`, `no PR yet` (q21 to q23, q29, q30; PEN rows 50, 51). Who can produce it: a child that breaks `templates/checkpoint.md:31` and `templates/brief.md:145-146`, on purpose or by closing a row before its PR exists, or an owner in a hurry after an exit 10. Nothing in run.log shows it but the earlier line that named the PR. Shortfalls filed on this path: P3R3-8 (the permission is keyed on an outcome), P3R3-10 (two refusal lines), P3R3-25 (no trace), P3R3-26 (the mechanism sentence). (PEN R-1, SEC-13, CT-17)
2. **A deleted row takes its PR with it.** Row 1 removed, `PR #7` left under Completed phases, PR 7 red: exit 0; base refused it only through prose. No template rule says a row may not be removed; the receipt gate has the same gap. A fix that reads no prose: log `cp_phases` at each child's start and refuse `done` when the count is lower than the highest seen. (PEN R-2)
3. **A PR named only in prose or in another cell is never read**, so its red or missing record no longer refuses `done` once every done row says `PR #N` or `no PR`. (SEC, "what this diff weakens")
4. **A job with rows closed the old way is refused until each row is edited** ("existing checkpoints ... add `no PR`"). Silent-failure-hunter probe H1: exit 10, no child launched; the phase-2 tree passed the same checkpoint. The missing words are P3R3-16.

Ruling 2 (the PR record's head commit decides whether runs were due):

5. **A head with no workflow file passes on `absent` although runs may have been due or CI exists elsewhere.** Logged `no CI runs and no workflow file at its head <sha> (no CI configured; absent, not a pass)`; pinned at `41:227-234`. Cases: a branch cut before the base got its workflows (GitHub builds `pull_request` runs from the merge of head and base, from recall), where "no runs" can mean a merge conflict or a slow queue; a head commit that deletes `.github/workflows` (measured: `ls-tree` prints nothing); case variants `.github/Workflows`, `.GITHUB/workflows` and a sibling `.github/workflows-old/` (measured: PASSED; whether GitHub runs them was not checked); an empty tree at the path; CI from a commit status or another app, which `gh run list` never reads (pre-existing, stated in the spec). The phase-2 base passed every absent record, so nothing here is weaker than before. Shortfalls filed: P3R3-11 (no sentence forbids the delete), P3R3-24 (the log wording). (PEN R-3, SEC-8, SFH-13)
6. **A head with a workflow file that cannot start on the PR is refused, with no override.** Record `absent` at a head with a file: exit 10 (base: PASS). Cases: a release-only, schedule-only or dispatch-only workflow file; `on: pull_request: branches: [main]` on a stacked PR whose base is the previous phase's branch (from recall). The owner has no sanctioned move in the texts; what ends the job is a change to the workflow triggers or the PR's base, or one of three slips: a false `no PR`, a hand-written record, a replace ref. An obedient child ends at `status: blocked`, exit 3. Owner question 3 (an owner-held override; which files count) was not ruled. Shortfall filed: P3R3-4. (PEN R-4, CT-1, SFH-3)
7. **A head git cannot read, or a workdir in no git repo, is refused.** Record `absent` at a sha the repo lacks: exit 10 with a fetch line (base: PASS); `TOP` empty: exit 10; a shallow clone whose depth does not reach the head: `fatal: Not a valid object name`, refused. Pinned at `41:127-128,253-256`. (PEN R-5)
8. **Any file under `.github/workflows` counts** ("a file"): the fail-closed over-breadth is listed as P3R3-20 because the message calls a `README.md` a workflow file and owner question 3 is open.

Not a ruling, but fixed by criterion 4: a red `workflow_dispatch` run on the PR's head no longer makes the record `failure`.

## Round-2 status

Reviewers were asked for a status on the four HIGH only. The MEDIUM rows are derived from this round's findings, the logs and the files; the fix baton's dispositions were checked against them, not taken as proof.

| ID | Status | Reviewers' split, and one line of evidence |
|---|---|---|
| P3R2-1 (HIGH) | reshaped | SFH, PEN: reshaped. ARCH: resolved as filed, reshaped at the row boundary. SEC, CT: resolved (SEC with a residue). Closed for rows the parser reads (`41:177-180`, `:192-198`; fixer mutant mB killed); open through an unread row (P3R3-1, q1: exit 0) and a second PR without `#` (P3R3-3) |
| P3R2-2 (HIGH) | resolved | All five. `ci_prs` is called only on done cells (`ci.sh:71,83`); `41:186-190`; mutants mC, m9 and M38 killed. Residue inside a cell: P3R3-29 |
| P3R2-3 (HIGH) | resolved | All five, for the case it named: `ci.sh:89-95`, `41:227-256`; mutants m1, m6, m7, mD, mF killed. The neighbour (a head whose workflow cannot start on the PR) is refused by ruling 2; its missing text is P3R3-4, the child's text P3R3-2 |
| P3R2-4 (HIGH) | resolved | ARCH, SFH, SEC, PEN: resolved. CT: reshaped in part, in weaker form. `templates/checkpoint.md:30-32` is an obligation, pinned and the old sentence forbidden (`51:75-82`; t1, t2, t5 killed). What is left: P3R3-5, P3R3-9, P3R3-10, P3R3-26 |
| P3R2-5 | resolved | `grep -a` at `ci.sh:104`; PEN row 94 (a NUL inside the token): now E10 red, base PASS. The prose half is moot. The test is loose (`41:209` takes 9 or 10) and dropping `-a` survives (S2): P3R3-21 |
| P3R2-6 | reshaped | Single mis-spelled cells are refused (`41:199-205`; q24 to q28, q40, q41; mE killed). Open: a PR without `#` beside `no PR` or beside a valid token (P3R3-3) |
| P3R2-7 | resolved | Ruling 2: the record's head is read, not HEAD or the working tree (`41:230-234`, `:244-248`; mD killed). A workflow only on the PR's base is the ruling's residual 5 |
| P3R2-8 | out of scope by ruling | Any file counts ("a file"); owner question 3 not ruled. Still measured: `README.md`, `.gitkeep`, a symlink, a nested file all refuse (SFH D1 to D4, SEC-9): P3R3-20, and the dead end in residual 6 |
| P3R2-9 | pre-existing, open | P3R3-14 (PEN rows 44, 45) |
| P3R2-10 | pre-existing, open | P3R3-18 (a hand-written `success`: PASS on both trees) |
| P3R2-11 | pre-existing, open | Not re-filed this round; `ci.sh:41` still counts `skipped` as green |
| P3R2-12 | reshaped | With no readable row the job is refused (`41:163-168`, q4, q61). Beside one readable done row the hidden rows pass: P3R3-1 (SFH A4). Round 2 called it pre-existing; measured against the base it is new for the CI gate |
| P3R2-13 | resolved | The "named elsewhere and not read" pass is deleted with the fallback; `CI at done: PRs read: ...` is logged on every pass (`41:134`) |
| P3R2-14 | resolved | Outside git an absent record is refused with a true line (`ci.sh:91`, `41:127-128`; SFH M3 killed, by message text) |
| P3R2-15 | reshaped | The old claims are gone; the new "every done row" sentences are true only of rows the parser reads (P3R3-6 items 5 to 7) |
| P3R2-16 | resolved | The two-way parse is gone. A new one ("own PR", "another PR") is P3R3-9 |
| P3R2-17 | reshaped | Step 4 now says "when a PR gets no CI runs" and asks the question; the answer is dropped and the question fits the wrong filter (P3R3-4); no test pins it (P3R3-7) |
| P3R2-18 | reshaped | The brief gives an action for `absent` with a workflow file (`51:87-88`; t4 killed); none for a head with no file, and it contradicts step 9 (P3R3-2) |
| P3R2-19 | resolved | `README.md:114-119,134` names the row case and the PR case with a remedy each. Omissions: P3R3-17; "ask the owner": P3R3-4 |
| P3R2-20 | reshaped | The mixed case, the mis-spelled cells and the NUL case were added; the `P1` row still pins the fail-open (`41:97,132`): P3R3-1 |
| P3R2-21 | resolved | For the copy phase 3 added (`cp_done_cells`, pinned at `51:31`). The older copies are pre-existing: P3R3-13 |
| P3R2-22 | open | The rule is still written out in README, spec, template, brief, skill and the `bin` header (the fixer: ruling 1 names those texts). This round found drift among them: P3R3-6, P3R3-17 |

## Acceptance criteria

| # | Criterion | Status | Passing test, and what is missing |
|---|---|---|---|
| 1 | No runs, workflow file at the PR's head: exit 10 | met | `tests/41-ci-wait.sh:236-237` (exit 10, `PR #17 CI absent: no runs, but its head <sha> has a workflow file (.github/workflows/release.yaml)`), `:243`, `:248`. Mutants m1 and m7 killed there; SFH M33 at `:243`. All five reviewers: met |
| 2 | No runs, no workflow file at the PR's head: allowed, logged | met | `tests/41-ci-wait.sh:227-229` (pass, log line pinned), `:233-234` (a workflow file at HEAD only still passes). Mutants m2 and mD killed. The criterion is the runner's behaviour and all five say it is met there. ARCH, CT and SFH add "met in part for an obedient child" (the brief has no step for this case), SEC and PEN do not; that gap is P3R3-2 and is counted under criterion 5 |
| 3 | PRs only from Status cells; prose never read; a done row with neither refused | met in part | Holds for rows the parser reads: `tests/41-ci-wait.sh:132`, `:160-162`, `:186-190` (prose and other cells never read; mC, m9, m10 killed), `:170-171`, `:177-180` (neither refused; mB killed). Missing: a done row the parser does not read is neither read nor refused, and `:97`, `:132` assert that (P3R3-1); a PR in a spelling the runner does not read passes beside a valid token or the words `no PR` (P3R3-3). ARCH, SFH, SEC, PEN: met in part. CT: met |
| 4 | `workflow_dispatch` runs count in neither direction | met | `tests/41-ci-wait.sh:76-80` (a green dispatch alone is absent; a red dispatch beside a green run is success; none watched), `:82-83` (a push run counts), `:222-226` with `:228` and `:237` (at `done`). Mutant m5 killed. Gap, not a finding: "any event but `workflow_dispatch`" is tested for `push` only. CT and PEN judged it by reading |
| 5 | Tests for 1 to 4 in 41 (and 51 for template text); spec, README, skill and templates state the rules as they now are | met in part | Tests exist and are real (see Test realness); template text is pinned at `tests/51-templates.sh:74-88` (t1 to t5 killed). Missing: the texts do not all state the rules as they are (P3R3-2, -4, -5, -6, -16, -17); the README, spec and skill wording has no test and the CI-record clause is unpinned (P3R3-7); two rules the spec states have no pin (m3, m8: P3R3-21); one test pins the opposite of ruling 1 (P3R3-1). SEC: "met as far as this angle read"; the other four: met in part |

## Test realness

Mutants, all on /tmp copies, one scenario at a time:

| Who | Killed | Survived |
|---|---|---|
| Fixer (`fix-phase-3-iter-2/mutants-41.log`) | 6 of 6: mA no-done-row refusal dropped; mB "neither" refusal dropped; mC PRs read from the whole file; mD workdir HEAD read in place of the record's head; mE stray check dropped; mF unreadable head let through | none |
| Coordinator (`review-phase-3-iter-3/unit-mutants.log`) | 13 of 15: m1 absent+workflow refusal dropped; m2 absent pass not logged; m4 "both" refusal dropped; m5 dispatch filter dropped; m6 absent head check dropped; m7 pathspec narrowed to `ci.yml` (closes round 2's P3R2-24); m9 PRs read from the whole table section; m10 whole row printed for the cell; t1 to t5 (template and brief sentences, scenario 51) | m3 `no PR` matched case-sensitively; m8 stray check without `/pull/` |
| silent-failure-hunter | 7 of 12: M1 the `.pr == $n` record check; M2 `ci_head` dropped on the success path; M3 the `[ -n "$TOP" ]` guard; M6 `-r` dropped from `ls-tree`; M7 `tolower` dropped (scenario 40); M33 `$WORKDIR` for `$TOP`; M38 the table range never ends. M2, M3, M6 and M7 are killed by message text only: the exit code did not change | S1 `sort -un`; S2 `grep -a`; S3 `[ -n "$cur" ]` in `ci_head`; S4 `^{commit}`; S5 the word boundary of `no PR`. The five ran as one bundle (`PASS 41-ci-wait`), never singly |

What the survivors mean: with S3 gone, a record with no `head_sha` while `gh pr view` fails goes from exit 10 to exit 0 (probe C4); with S5 gone, `no PRs` goes from exit 10 to exit 0 (probe B8); with S4 gone a tree sha is read as a tree (not reachable with a real gh); S1 changes only log order and repeated gh calls; for S2 no input was found where `-a` changes the outcome on this box (GNU grep 3.11, `C.UTF-8`; bash drops NUL bytes before grep sees them).

Behaviours no test pins:
- A refusal for a table row the parser does not read; the opposite is pinned (`41:97,132`). The second-heading case has no test either way.
- `no PR` in any case (m3); a stray `/pull/` in a done cell (m8); the word boundary of `no PR` (S5); a cell that says `no PR` beside a PR without `#`, and a second PR without `#` (P3R3-3).
- The `[ -n "$cur" ]` guard (S3); the `^{commit}` peel (S4); a non-sha `head_sha`; a replace ref.
- Which refusal fires for the seven mis-spelled cells (`41:204` accepts any message starting `phase row 0 `); the NUL case's exit code and that PR 7 is read (`41:209`); `41:115` greps a line an earlier run wrote, so only the exit code tells there.
- A run of any event other than `push` or `workflow_dispatch`; a red dispatch record's effect at `done` (it follows from the record).
- The rule text in `README.md`, `docs/spec.md` and `skills/blast-off/SKILL.md` (`tests/70-docs.sh` checks only that the README has a row per exit code); in the templates, the CI-record clause, the brief's "where the PR's head has a file" qualifier and "push once more", `checkpoint.md:27-28` and `:33-34` (P3R3-7).
- "No table at `done`" is covered only with a pre-set status (`41` jobs `nt`, `hd`, `nr`); the fake's `fin` means the suite's other jobs cover "no table at start, table at done".

The fake's `fin` helper masks no assertion (architect-reviewer and silent-failure-hunter, by reading; P3R3-30).

## New dependencies or reliance

No new program. New reliance, the union of what the reviewers listed:

- `gh run list --json databaseId,event`: the `event` field and the literal `workflow_dispatch` (`lib/ci.sh:53-54`). A gh that does not know the field fails the call and `ci-wait` dies (fail-closed). No gh version floor is stated.
- `git ls-tree -r --name-only <sha>^{commit} -- .github/workflows` in the workdir's repo at `done` (`lib/ci.sh:92`): the `^{commit}` peel, and the PR's head commit and its trees present locally. A new operational need: a head made elsewhere must be fetched first. It honours replace refs (P3R3-23) and in a partial clone it fetches with no time limit (P3R3-33).
- The refusal text's `git fetch origin pull/<n>/head`: a remote named `origin` and GitHub's pull refs (P3R3-22).
- GNU sed's `I` flag with `-E` in `s~...~~Ig` (`lib/ci.sh:72`); not POSIX. The repo already needs GNU sed (`sed -i`, `0,/re/`).
- `paste -sd' '` (first use in `lib/`), `sort -un`, `grep -a` with `-o -i -E` (`lib/ci.sh:104`).
- bash `[[ =~ ]]` with the pattern in a variable, and a `while read` fed by process substitution (`lib/ci.sh:70-81`): a failure of `cp_done_cells` is not seen (P3R3-32).
- The current locale's `[:alnum:]` for the `no PR` word boundary (`lib/ci.sh:74`); it differs under `LC_ALL=C` (P3R3-3).
- awk on a NUL byte: gawk keeps the line; `41:206-209` allows exit 9 for an awk that cuts it.
- `ci_check` now reads `TOP`, which `chain_run` sets: `lib/ci.sh` depends on `lib/chain.sh` state for the first time.
- The CI gate now rests on the row parser of `lib/checkpoint.sh:43-46`, which the base's `ci_check` did not use (P3R3-1).
- Two different reads of "a file under `.github/workflows`": the child's (its working tree) and the runner's (`ls-tree` at the record's head); they differ for an untracked directory and after any later commit.
- A GitHub rule taken as given: with no file under `.github/workflows` at the PR's head, no run was due. From recall, `pull_request` workflows are read from the PR's merge commit, so a base that gained a workflow can make a run due on a head that has none; the brief's "merge the base in before the gate" keeps a template-following job out of that case. Only Actions runs are read; commit statuses from other CI are not.
- The `no PR` rule relies on the child's statement being true; no tool checks it (ruling 1).
- Tests: the fake `gh` gains `event-<id>`; the fake `claude` now needs `git` and `jq` and knows the receipt's field names and the row format (P3R3-30).

## Fail-open paths

Every input found this round that ends in exit 0 `job done` while a PR's CI did not pass or was not read.

Defects:
1. A done row with a non-digit key (`P1`, `R1`, `Phase 1`, `v1`, `one`, `#1`, `(1)`, bold, backtick, struck-through, a circled or Arabic-Indic digit) beside a readable done row. **P3R3-1.** (q1, q2; SFH A1, A2, A13; PEN rows 7 to 10, 30 to 33)
2. A done row indented, led by a tab, with a tab or no-break space after the first pipe, with a zero-width space or byte-order mark before it, with no leading pipe, inside a blockquote or an HTML comment. **P3R3-1.** (q3; SFH A3, A10; PEN rows 13 to 17, 19 to 21)
3. A done row after a second `## Phase plan` or `## Phase plan (continued)` line that follows a readable done row. **P3R3-1.** (SFH A4; PEN row 23; ARCH case S2)
4. A digit-keyed done row cut off by another `## ` line inside the table. **P3R3-1, disputed sub-case** (penetration-tester files it as R-6 of issue 26's scope; `41:98-99` pins the same for a row under `## Decisions`). (ARCH cases S1, K; SEC-1; PEN row 22)
5. A row led by a NUL byte. **P3R3-1**; passes on the base too. (PEN row 18)
6. A cell with the words `no PR` beside a PR written without `#<digit>`: `no PR, see PR 7`, `PR 7 · no PR checks failed`, `no PR · pull/7`, `no PR · PR # 7`, `no PR · PR #0`, `no PR · GH-7`, a fullwidth `#` or digit, `.../pulls/7`. **P3R3-3 (a).** (q13, q14; SFH B1 to B7; SEC-2; PEN rows 52 to 54)
7. A second PR without `#` beside a valid token: `PR #5, 7`, `PR #5 and PR 7`, `PR #5/7`, `PR #7-9`, `PR #5 (supersedes PR 7)`; `PR #1,234` read as PR 1. **P3R3-3 (b).** (SEC-3; PEN rows 34 to 42)
8. A column after Status, an escaped pipe, or no trailing pipe, where the cell the parser reads starts `done` and says `no PR` while the real Status cell names a PR. **P3R3-19.** (SFH A5; ARCH case G; SEC-12; PEN rows 72, 73, 75, 78 to 80)
9. A wrong PR number in the cell that is another green PR of the repo; the right PR with its head moved back to an old green commit. **P3R3-14**, pre-existing. (PEN rows 44, 45)
10. A red run listed after `ci-wait`'s last re-list: record `success`. **P3R3-15**, pre-existing. (SFH I3)
11. A `ci-wait` that dies part-way, with an older green record of the same head left in force. **P3R3-36**, pre-existing; needs a child that goes on after exit 1. (SFH G1, G2)
12. A hand-written record: `success`; `success` over a failed run; two JSON values; `pr: 7.0`; a non-sha `head_sha` that a `gh` prints back. **P3R3-18**, pre-existing; on purpose only. (SFH C3, C5, C6, C11; SEC-4; PEN rows 100 to 104, 67)
13. `git replace` of the PR's head by a commit with no workflow file, record `absent`. **P3R3-23**; on purpose only. (SEC-5, PEN-7)
14. Another repo's `/pull/N` link in a done cell, where this repo has a green record for PR N. **P3R3-29**, pre-existing. (SEC-11)
15. A phase whose `gh pr create` failed, closed with a truthful `no PR`. The pass is ruling 1; the text that licenses it is **P3R3-8.** (CT-5, read, not run)
16. A phase's second PR named in prose because the template says "name another PR in prose". The pass is ruling 1; the wording is **P3R3-9.** (CT-4, read, not run)

Ruling residuals (see that section):
17. An explicit `no PR` on a row that has a PR, in any case or dress. Ruling 1, residual 1. (`41:181-184`; PEN rows 50, 51, 55)
18. A done row deleted from the table. Ruling 1, residual 2. (PEN row 28)
19. A PR named only in prose or in another cell, every done row tokened. Ruling 1, residual 3.
20. `absent` at a head with no workflow file while runs were due: a workflow only on the base, a head that deletes the directory, a case-variant or sibling directory, an empty tree, CI that is not Actions. Ruling 2, residual 5. (`41:230-234`; PEN rows 59, 60, 69; SEC-8)
21. Every row says `no PR` and `jq` is missing: passes, as ruled (no record is read).

Not about a PR's CI, noted for completeness: an open or sha-less row the parser does not read lets `done` through the receipt and all-rows-done gates on both trees (SFH A7, PEN row 27; pre-existing, under P3R3-1); two rows with one key (P3R3-34).

Checked and found closed. The reviewers probed these and each ends in exit 10, exit 9 or a runner abort, never `job done`:
- `gh pr view` failing (exit 1; exit 4 with no token), timing out, printing nothing, `null`, `{}` or non-JSON, for `success` and `absent` records alike (16 security-reviewer probes; SFH C9, C10, C12; `41:124`); `gh run list` or `gh run view` failing or printing nothing in `ci-wait` (SFH I1, I2, G1: exit 1 or 10).
- `jq` missing (exit 127 from a fake): `CI unread`, exit 10.
- Malformed records: no file, an empty or cut-off file, an array, `pr` missing or a string, a record of another PR copied in, verdict missing, null, an array, `skipped` or `Success`, failure-then-success, `head_sha` missing with gh failing, a PR number past 2^53: exit 10. Bytes after the JSON value: runner abort, exit 1.
- `git ls-tree` on a missing object, a shallow clone that lacks the head, a tree sha, option-shaped text, no git repo: exit 10. No checkpoint or record text reaches a shell, a `jq`, `sed` or `grep` program, or a path unquoted (`$(touch ...)` in `head_sha`: no file made).
- Rows the parser reads but does not class as done (no trailing pipe, a check-mark or bold on `done`, `complete`, key `1)`, a plain cell after Status): exit 9. A CRLF checkpoint with a red PR: exit 10 (q60). A NUL inside the PR token: read, exit 10. Odd `status:` lines (PEN rows 96 to 99): no exit 0.
- A failing `tee` in `log` ends the runner by errexit before `exit 0` (line walk, `chain.sh:6`).

## Source map

| Reviewer ID | Reviewer's rating | P3R3 ID |
|---|---|---|
| ARCH-1 | HIGH | P3R3-1 |
| ARCH-2 | MEDIUM | P3R3-2 |
| ARCH-3 | MEDIUM | P3R3-12 |
| ARCH-4 | MEDIUM | P3R3-13 |
| ARCH-5 | MEDIUM | P3R3-6 |
| ARCH-6 | LOW | P3R3-17 |
| ARCH-7 | LOW | P3R3-19 |
| ARCH-8 | LOW | P3R3-30 |
| ARCH-9 | LOW | P3R3-16 |
| ARCH-10 | LOW | P3R3-34 |
| ARCH-11 | LOW | P3R3-31 |
| ARCH-12 | LOW | P3R3-21 |
| ARCH-13 | LOW | P3R3-22 |
| CT-1 | HIGH | P3R3-4 |
| CT-2 | MEDIUM | P3R3-2 |
| CT-3 | MEDIUM | P3R3-2 |
| CT-4 | MEDIUM | P3R3-9 |
| CT-5 | MEDIUM | P3R3-8 |
| CT-6 | MEDIUM | P3R3-26 |
| CT-7 | MEDIUM | P3R3-10 |
| CT-8 | MEDIUM | P3R3-11 |
| CT-9 | MEDIUM | P3R3-5 |
| CT-10 | MEDIUM | P3R3-16 |
| CT-11 | MEDIUM | P3R3-7 |
| CT-12 | LOW | P3R3-22 |
| CT-13 | LOW | P3R3-17 |
| CT-14 | LOW | P3R3-17 |
| CT-15 | LOW | P3R3-4 |
| CT-16 | LOW | P3R3-17 |
| CT-17 | LOW | P3R3-25 |
| CT-18 | LOW | P3R3-27 |
| SFH-1 | HIGH | P3R3-1 (its probe A5 is also evidence for P3R3-19) |
| SFH-2 | MEDIUM | P3R3-2 |
| SFH-3 | MEDIUM | P3R3-4 |
| SFH-4 | LOW | P3R3-16 |
| SFH-5 | MEDIUM | P3R3-15 |
| SFH-6 | LOW | P3R3-3 |
| SFH-7 | LOW | P3R3-36 |
| SFH-8 | LOW | P3R3-18 |
| SFH-9 | LOW | P3R3-20 |
| SFH-10 | LOW | P3R3-37 |
| SFH-11 | LOW | P3R3-32 |
| SFH-12 | LOW | P3R3-21 (its `70-docs` point is also in P3R3-7) |
| SFH-13 | LOW | P3R3-24 |
| SFH-14 | LOW | P3R3-17 (its template half is also cited in P3R3-26) |
| SEC-1 | MEDIUM | P3R3-1 |
| SEC-2 | MEDIUM | P3R3-3 |
| SEC-3 | MEDIUM | P3R3-3 |
| SEC-4 | LOW | P3R3-18 |
| SEC-5 | LOW | P3R3-23 |
| SEC-6 | LOW | P3R3-18 |
| SEC-7 | LOW | P3R3-35 |
| SEC-8 | LOW | P3R3-24 (the path is residual 5) |
| SEC-9 | LOW | P3R3-20 |
| SEC-10 | LOW | P3R3-33 |
| SEC-11 | LOW | P3R3-29 |
| SEC-12 | LOW | P3R3-19 |
| SEC-13 | LOW | P3R3-25 (the path is residual 1) |
| SEC-14 | LOW | P3R3-38 |
| PEN-1 | HIGH | P3R3-1 |
| PEN-2 | MEDIUM | P3R3-3 |
| PEN-3 | MEDIUM | P3R3-14 |
| PEN-4 | LOW | P3R3-3 |
| PEN-5 | LOW | P3R3-19 |
| PEN-6 | LOW | P3R3-18 |
| PEN-7 | LOW | P3R3-23 |
| PEN-8 | LOW | P3R3-28 (its third item, any file counts, is also in P3R3-20) |
| PEN-9 | LOW | P3R3-5 |
| PEN-10 | LOW | P3R3-16 |
| PEN R-1 | residual, not filed | Residuals 1 (cells that also name a PR without `#`: P3R3-3) |
| PEN R-2 | residual, not filed | Residuals 2 |
| PEN R-3 | residual, not filed | Residuals 5 |
| PEN R-4 | residual, not filed | Residuals 6 (the missing text: P3R3-4) |
| PEN R-5 | residual, not filed | Residuals 7 |
| PEN R-6 | residual, not filed | P3R3-1, disputed sub-case (not a ruling's residual) |

69 filed findings map to 38 IDs; 6 reported residuals map to the Residuals section or, for R-6, to P3R3-1.

Ratings set below a reviewer's own, each with its reason on the finding: P3R3-4 (CT-1 HIGH, set MEDIUM), P3R3-16 (CT-10 MEDIUM, set LOW), P3R3-26 (CT-6 MEDIUM, set LOW). Ratings set above a reviewer's own: P3R3-1 (SEC-1 MEDIUM, set HIGH), P3R3-3 (SFH-6 and PEN-4 LOW, merged at MEDIUM with SEC-2, SEC-3 and PEN-2), P3R3-5 (PEN-9 LOW, set MEDIUM). Every other finding keeps the rating all its filers gave.

## Report Audit

Verdict: sound with corrections

Advisory only; nothing above this heading was changed. The audit read the report, the brief, the five reviewer reports, `unit-mutants.log` with its script and probe file, and `owner-rulings-phase-3.md`. It ran no scenario, test or gate.

What held:
- Arithmetic. 13 + 18 + 14 + 14 + 10 = 69 filed; 4 HIGH, 22 MEDIUM, 43 LOW; after dedup 1 + 14 + 23 = 38. Coordinator mutants 13 of 15, silent-failure-hunter 7 of 12. Diff stat and gate line as stated.
- Coverage in the Source map. Every ID from ARCH-1 to 13, CT-1 to 18, SFH-1 to 14, SEC-1 to 14, PEN-1 to 10 and R-1 to R-6 has a row, and each maps to an ID that names it, with the exceptions in corrections 1 to 4.
- Citations. Checked against the files at `d43324d`, all hold: `lib/checkpoint.sh:11,43,44,51,57,59,69`; `lib/preflight.sh:77`; `lib/ci.sh:20-33,36-43,45-46,53-54,69-84,86,89-97,104,112-115`; `lib/chain.sh:89-91,94-109,160-161`; `lib/receipt.sh:50-51,68-71`; `tests/41-ci-wait.sh:76-83,97-99,109,115,127-128,132,134,160-171,177-184,186-198,201-209,227-237,240,243,248,253-256`; `tests/51-templates.sh:31,74-82,87-88`; `tests/70-docs.sh:40`; `templates/checkpoint.md:24,27-34,50-51`; `templates/brief.md:69-71,83,108,124-125,135-137,145-146,169-171`; `README.md:114-119,127,128,134,143-144`; `docs/spec.md:21,35,61,91,97,228,230`; `skills/blast-off/SKILL.md:34-38`; `bin/blast-off:18,37-38`; `tests/fakes/claude:5-11,17,30-43,74,76,89,96`.
- The Round-2 rows for the four HIGH match the reviewers' own round-2 sections, split by split.
- Criteria statuses match the reviewers' sections and the body. Criterion 2 was tested apart, since ARCH, CT and SFH wrote "met in part for an obedient child": the criterion is worded as the runner's behaviour, all five say it is met there (`41:227-229`), and the child's path to it is booked under criterion 5 through P3R3-2. "Met" stands.
- Residuals. Nothing parked under Residuals is a shortfall against a ruling or a criterion. Each shortfall on those paths has its own ID (P3R3-4, -8, -10, -11, -16, -20, -24, -25, -26), with correction 12's caveat on where Residual 7's clause comes from.

### Corrections

Each gives where, what the report says, what the source says, and the effect on the CRITICAL or HIGH count and on the criteria.

Coverage

1. Source map row SFH-6, and P3R3-3. Report: SFH-6 maps to P3R3-3, which carries its first half only. Source: SFH-6's second half is that the stray refusal at `lib/ci.sh:73` ("write each of the phase's PRs as `PR #<n>` and no other '#<n>' there") is met by deleting the `#` from `no PR (#7 dropped)`, after which the cell passes as `no PR`. No finding carries it; it belongs beside P3R3-10 (refusal lines that point at an edit which drops a PR). Effect: none.
2. Source map row SFH-1, and the closing "ratings set below" paragraph. Report: SFH-1 HIGH maps to P3R3-1, "its probe A5 is also evidence for P3R3-19". Source: SFH-1 lists "a cell after Status" (A5: HEAD exit 0, phase 2 exit 10) inside its HIGH. The report rates that case LOW in P3R3-19, as ARCH-7, SEC-12 and PEN-5 do, but the closing paragraph does not list it among ratings set below a reviewer's own. Effect: none; the LOW is supported by three filers.
3. P3R3-22, row and Sources. Report: "`:96` names no gate or receipt for the fix commit", inside a bundle of message wording. Source: CT-12's point on `:96` is a code path, not wording: at `status: done` every done row was done before child 1, so `receipt_check` skips the code-changed test (`lib/receipt.sh:62`, `lib/chain.sh:155`) and a fix commit pushed after the gated one ends `done` ungated. CT marks it pre-existing and read, not run. The report's origin tally counts P3R3-22 as introduced, and the "not about a PR's CI" list under Fail-open paths does not carry it. Effect: none (LOW, pre-existing).
4. P3R3-5, Decision. Report: MEDIUM because line 24 "is incomplete in three measured ways". Source: that is PEN-9's finding, which PEN rated LOW. CT-9, the MEDIUM filer, says something else: line 24 now describes a way out of the CI check. The report gives CT-9's point one clause ("Read with line 33 ..."). The rating is taken from one filer and the reasoning from the other. Effect: none.

Dedup

5. P3R3-3, Decision. Report: "Path (a) shares its facts ... so it is not rated apart", and "PEN-4 is LOW because it reads most of (a) as ruling 1's residual". Source: PEN-4 says of itself "This finding is only about text that does not say the phase has no PR" and rates that part LOW with no reason given; the residual reading is PEN's R-1, a separate entry. PEN's own key puts rows 52 and 54 under R-1; the report cites them as defect evidence in Fail-open paths item 6. One fact is not shared: an (a) cell holds the words `no PR`, which ruling 1 makes the cell's declaration; a (b) cell does not. The merge is sound on the fix (one whitelist, named by SEC-2, SEC-3, PEN-2, PEN-4 and SFH-6), but path (a) alone stands at one MEDIUM against two LOW, and the reason given for setting PEN-4 aside is not PEN's. Effect: none; (b) carries MEDIUM by both its filers.
6. P3R3-8, P3R3-9, P3R3-26, P3R3-6 items 6 and 10, P3R3-17 items 9 and 12. Report: separate IDs. Source: all are sentences of one comment block, `templates/checkpoint.md:30-34`, and the suggested rewordings overlap ("another repo's PR", "a PR that is not this job's goes in prose", "drop the mechanism clause"). The IDs are per misreading, which is defensible, but one rewrite closes them, so the MEDIUM and LOW counts overstate the work. The same holds for P3R3-5 and P3R3-13, whose fixes are parts of P3R3-1's. Effect: none.

Severity

7. P3R3-1: rightly HIGH. The fact that carries it is in PEN's table: rows 7 to 10, 13 to 17, 19 to 21 and 23 are `E10 red` on the base with the prose line and without it. So the loss is not the ruled removal of the prose read; the base refused because the table row itself says `PR #7`. Add: fail-open, measured on the real runner on both trees (SFH A1 to A4, A10, A13), a done table row that ruling 1's "every done row" covers, and a test that pins the skip (`41:97,132`). Against: off-template only, low by accident, SEC-1 MEDIUM. Under the rubric it is a bug in the gate, not a maintainability concern. One precision point on the table row and the Executive Summary: "its PR is red, unread, stale or absent ... the phase-2 base: exit 10" does not hold for an absent record (PEN row 33: PASS on all three) or for the NUL-led rows (row 18: base PASS); the base refusal holds for red, no record and stale. Effect: none.
8. P3R3-3: rightly MEDIUM, not HIGH, but the Decision does not give the fact that separates it from P3R3-1. Report: "MEDIUM, one finding, because all five name the same fix". Source: PEN rows 34 to 42 and 52 to 53 are PASS on the base without the prose line, and SFH's phase-2 run passes B1 to B7. The base caught these cells only through the Completed-phases line, and that read is what ruling 1 removed (the report's own Residual 3). What is left is an incomplete fix of P3R2-6, which round 2 rated MEDIUM. It also needs two departures at once (free text or a second PR in the cell, and a PR written without `#`). No filer rated it above MEDIUM. Effect: none.
9. P3R3-4: rightly MEDIUM. It is fail-closed, the refusal is ruling 2, and the missing override is owner question 3, not ruled (`baton-phase-3-fix-2.md:50,121`); rating it HIGH would rate the ruling's dead end, not the texts. CT-1's own note calls it borderline and asks for "the first MEDIUM to fix". The tested half is the code: any file under `.github/workflows` with an absent record is refused (`41:236-237`, with `release.yaml`). The half that gives the wide reach, a base-branch filter on a stacked PR, is recall in every source. A fact for the owner, not a correction: the report says it did not apply the skill's "severity tiebreak: pick higher". Applied, P3R3-4 would be HIGH (two HIGH), and P3R3-16 and P3R3-26 would be MEDIUM. Effect: none on this audit's view.
10. P3R3-10: this audit would put it at LOW. Report: MEDIUM as filed, set apart from P3R3-26 because line 82 "leaves out a condition". Source: CT-7 gives reach "no" for both lines (line 82 needs a job with no readable table, line 75 a cell with both); the reader is the owner; direction is "fail-open by a later edit, not by the code"; the other reviewer on the same lead (PEN, R-1) found no line that tells anyone to swap a PR for `no PR`. On reach and direction it sits with P3R3-16, P3R3-25 and P3R3-26. P3R3-9 and P3R3-11 pass the report's own "leaves something out" test and can stay MEDIUM; each is single-filer, off-brief or Target-set-only, and read, not run. The other MEDIUM hold: P3R3-13, P3R3-14 and P3R3-15 on origin (pre-existing, outside the diff the brief scopes); P3R3-8 is the nearest to HIGH on the report's five facts (fail-open, introduced, reached on a tool failure) and stays MEDIUM because it rests on one reading of the text against `brief.md:69-71`, was read, not run, and the pass itself is ruling 1. No LOW should rise. The lowerings of CT-10 (P3R3-16) and CT-6 (P3R3-26) are supported by the facts cited. Effect: MEDIUM 14 to 13 and LOW 23 to 24 if taken; no CRITICAL or HIGH change, no criterion change.

Ruling discipline

11. P3R3-24. Report: the pass line says "no CI configured", "which is more than was read"; fix: reword it. Source: `owner-rulings-phase-3.md:4`, ruling 2: 'A PR whose head has no workflow file is allowed through as "no CI configured", logged'. The brief's wording of ruling 2 left the phrase out, so SEC-8 and SFH-13 did not know it was the owner's. The wording half is the ruling's own text and belongs under Residuals as a note for the owner; the half that adds something (name the base when it has a workflow file the head lacks) can stay LOW. Effect: none.
12. Residual 7, and P3R3-20. Report: a head git cannot read is refused "because a ruling says so". Source: that clause ("a head commit not available locally fails closed") is in the brief's wording of ruling 2, not in `owner-rulings-phase-3.md`; the same holds for "(exit 10)" on ruling 2. It is fail-closed and no reviewer contests it. For P3R3-20 the first fix offered (count only `*.yml` and `*.yaml`) departs from ruling 2's "a file" and is owner question 3; the row says so, and the fix list should mark that option as the owner's. Effect: none.
13. Fail-open paths, item 4, and P3R3-1's disputed sub-case. Report: a digit-keyed row cut off by another `## ` line is listed under "Defects". Source: criterion 3 and issue 26 say PR numbers come only from the Phase plan; a row under another heading is outside it, and `41:98-99` with `:132` pins that at round 1's request (PEN R-6). ARCH-1 and SEC-1 count it, PEN does not. The report says the HIGH does not rest on it and that it needs the owner's word; it should stand as an owner question, not in the defect list. Effect: none.

Internal consistency

14. Executive Summary, "Closed, checked by probes". Report: "every malformed record field ends in exit 10 or a runner abort (exit 1), never `job done`". Source: the report's own P3R3-18 and Fail-open paths item 12: `pr: 7.0` (SFH C6), two JSON values (SFH C3, PEN row 102), `success` over a failed run (C5), and `head_sha: "null"` with a gh that prints null (C11, SEC-4) end exit 0. The sentence is SEC's summary line carried over; the "Checked and found closed" list in the body is the accurate one. Effect: none.
15. Executive Summary, "By origin". Report: wholly pre-existing P3R3-13 to 15 and 34 to 38; mixed P3R3-3, 18, 19, 29; "the other 26 are introduced by this diff". Source, the report's own Origin fields: P3R3-35 is "pre-existing; two more print sites added" (mixed, not wholly); P3R3-5 is "line 24 pre-existing and made worse" (mixed, counted as introduced); P3R3-29 is pre-existing and narrowed ("now confined to done cells"), not made worse; P3R3-6 items 3, 8, 9, P3R3-17 item 2 and P3R3-22's `:96` are pre-existing parts of IDs counted as introduced. Effect: none.
16. Executive Summary, "Reach". Report: "Template-reachable fail-opens found: P3R3-15 ... and P3R3-8". Source: P3R3-14's own Reachability field says "yes by a slip" (PEN-3), pre-existing; it is missing from the list. In the same bullet, "a job following both templates word for word" sits beside "an indented row, a tab, a missing leading pipe and a second heading break no sentence of the template as worded": the reviewers' term is "off the template's shape", and the bullet should say shape, since the words are kept. Effect: none.
17. Round-2 status, row P3R2-15. Report: "(P3R3-6 items 5 to 7)". Source: items 6 and 7 are the "every done row" and "last cell" sentences; item 5 is the P4Q1 citation. The rows P3R2-5 to P3R2-22 have no reviewer section behind them, as the report says; `lib/ci.sh:41` for P3R2-11 holds, and m7 against round 2's surviving `ci.yml` mutant for P3R2-24 holds. Effect: none.
18. P3R3-29. Report: "Pre-existing (P3R1-30)". Source: SEC-11, its only filer, cites P3R2-2; no source of this round names P3R1-30. Unverified lineage. Effect: none.

Evidence

19. P3R3-1, "The receipt gate, the all-rows-done gate and the CI gate all skip it", beside "confirmed by the coordinator on the real runner". Source: the coordinator's and silent-failure-hunter's probe jobs sit in no git repo (`41:89`), where `receipt_check` returns at once (`lib/receipt.sh:46`). The real-runner runs prove the skip for the all-rows-done and CI gates. The receipt-gate skip rests on PEN's "full order" run in a stub harness with real receipts (PASS against base `E10 red`) and on ARCH's reading of `lib/receipt.sh:50`. The claim holds; its evidence is one step weaker than the sentence reads. Effect: none.
20. Probe citations. (a) P3R3-9 cites q39 for "the code accepts several tokens in one cell"; q39 is `PR #8 · PR #8`, the same PR twice. SEC-11's `PRs read: 7 8` is the evidence. (b) "probes q1 to q61" are 39 probes (q1 to q14, q21 to q43, q60, q61), run through `bin/blast-off` of the /tmp copy. (c) Residual 1 cites q21 to q23, q29 and q30 for "PR 7 red, `PR #7` still under Completed phases"; those probes had a green record for PR 8 and no prose line, so they show only that the case and dress variants read as `no PR`. PEN rows 50 and 51 carry the rest. Effect: none.
21. Recall marks dropped between body and summary. (a) Executive Summary, "Largest residual": "a base-branch filter on a stacked PR" is stated plain; P3R3-4 and Residual 6 mark it as recall. (b) Executive Summary and the P3R3-15 row: "reachable by timing alone" rests on probe I3 against a fake `gh`; how far apart GitHub lists a push's runs is recall, as the detail says. (c) P3R3-20's fix (which files GitHub reads as workflows), P3R3-24 (another service's CI, a deleted directory getting no run) and P3R3-35 (a newline kept in a workflow name) are recall in SFH-9, SEC-9, SFH-13 and SEC-7 and unmarked in the rows. (d) "Bytes after the JSON value abort the runner (exit 1)": SEC-6 measured `rc=5` in a stub harness; exit 1 is its reading of the runner's EXIT trap. (e) P3R3-34 and P3R3-38 are from reading (ARCH-10, SEC-14), stated as fact. Effect: none.

Corrections that change the CRITICAL/HIGH count or a criterion status: none
