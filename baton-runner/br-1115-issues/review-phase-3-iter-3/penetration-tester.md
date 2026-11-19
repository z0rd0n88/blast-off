# penetration-tester: phase 3 (issue 26), review round 3

## Summary

- 1 HIGH, 2 MEDIUM, 7 LOW, plus 6 residuals of the rulings and of issue 26's own scope (reported, not filed as defects). No CRITICAL.
- The one HIGH: a done row the parser does not see (letter or bold key, an indented or tab row, a row under a second adjacent `## Phase plan` heading) takes its PR out of the CI gate. With one seen done row beside it, `done` passes exit 0 with that PR red, unread, stale or absent. The phase-2 base refuses the same file (exit 10). Round 2's P3R2-1 is closed at the door it named and open at this one.
- The door round 2 named is shut: a seen done row with neither token, both tokens, or a stray `#<n>` is refused; prose is never read; absent with a workflow file at the PR's head is refused; a head git cannot read is refused.
- Every other pass I found needs an explicit `no PR` (ruling 1's own statement), a PR written without `#` beside a valid token, a wrong PR number, or a hand-written record.
- About 250 checkpoint and record shapes were run against this HEAD and against `feat/br-1115-issues/phase-2`; the table below groups them into 105 rows.

## Method

Read-only on the worktree. No scenario run, no `tests/run`, no `scripts/gate.sh`. Work dir `/tmp/p3r3-pen.DzaelL` (mine, left in place). `lib/checkpoint.sh`, `lib/ci.sh`, `lib/receipt.sh` copied from HEAD into `now/`, and from `git show feat/br-1115-issues/phase-2:lib/<f>` into `base/`. Runner used for every case:

```bash
env -i PATH="$T/bin:/usr/bin:/bin" HOME="$T" LANG=C.UTF-8 FAKE_HEADS="$job/heads" bash -c '
  set -euo pipefail
  chain_end() { echo "END $1: $2"; exit "$1"; }
  log() { echo "LOG $*"; }
  die() { echo "DIE $*"; exit 1; }
  JOB="$2"; WORKDIR="$1/repo"; TOP="$1/repo"; JOBREL=
  . "$1/$3/checkpoint.sh"; . "$1/$3/ci.sh"; . "$1/$3/receipt.sh"
  receipt_all_done; ci_check; echo "PASSED: job done"
' _ "$T" "$job" "$side"        # side = now | base
```

- The script that ran also took a locale (`LANG=C` for the byte cases) and a mode with `TOP=` empty and `WORKDIR=$T` for the no-git case; nothing else differs.
- `$T/bin/gh`: answers only `gh pr view <n> --json headRefOid` from `$job/heads/<n>`; no file means exit 1.
- `$T/repo`: throwaway `git init`. Commit A has no workflow file, B (child of A, the default branch tip) has `.github/workflows/ci.yml`, C (branch `nowf`, child of A) has none. X is a sha the repo lacks.
- Records: `gate-logs/ci-pr-<n>.json` = `{"pr":N,"head_sha":"<sha>","utc":"t","runs":[],"verdict":"<v>"}`.
- Every checkpoint is this file with the two `ROW` lines replaced as the table says:

```
# Checkpoint: job

status: done
phase: 2 of 3 — x
step: finishing
updated: 2026-11-16T00:00:00Z by child 4
worktree: /w · branch b · HEAD abc1234 · base main
other worktrees: none

## Next action
none

## Phase plan
| # | Phase | Done when | Status |
|---|---|---|---|
| 0 | spec | reviewed | done (abc1234) · no PR |        <- ROW 0 (unless the case says otherwise)
| 1 | impl | green | done (abc1234) · PR #7 |           <- ROW 1 (the attack varies this line)

## Current phase: 2 — delivery
**Progress**
- done

## Completed phases (summary each, newest last)
- **Phase 1, impl** (done 2026-11-15, children 2-3). works; gate PASS; PR #7; CI read.

## Open or blocked (append only)
- none
```

- Default state: the job really opened PR #7; its record is `failure` at head B, head now B. "base+prose" is the file as above (the Completed-phases line names `PR #7`, as `templates/checkpoint.md:49-51` prompts). "base-np" is the same file with that line cut to `- **Phase 1, impl** done.`, so only the table names the PR.
- Result codes: `PASS` = `PASSED: job done`. `E10 red/neither/stray/both/norecord/stale/no-done-row/absent+wf/absent+unreadable/absent+nogit` = `chain_end 10` with that message. `E9 open` = `receipt_all_done` refused.

Harness gaps, stated so nobody reads more into the table than it holds:
- `receipt_check` is not in the main runner. I ran seven cases through the real order (`receipt_check "$rows"; receipt_all_done; ci_check`) with real receipts in the throwaway repo; they are marked "full order" below. For a row the parser does not see, `receipt_check` skips it too (`lib/receipt.sh:50` loops over `cp_done_rows`), so it never turns such a PASS into an exit 9. No other reader of the table refuses at `done`: `grep -n 'Phase plan' bin/blast-off lib/*.sh` shows only `cp_phases` (the cap), `jev` (open rows, model choice), `preflight` (the estimate) and `cp_mark_usage`.
- `ci_wait` was not executed (it needs more of gh than my fake gives). Criterion 4 is judged by reading `lib/ci.sh:52-55` and `tests/41-ci-wait.sh:73-83`.
- Everything about when GitHub starts runs is from recall and marked so.

## Findings

### PEN-1: A done row the parser does not see drops its PR from the CI gate; `done` passes with that PR red, unread, stale or absent
- Severity: HIGH (see the note on likelihood at the end of this finding)
- File: lib/checkpoint.sh:43 (the `sed` row filter), used by lib/ci.sh:81; pinned as wanted at tests/41-ci-wait.sh:91-99 (fixture; the `P1` row is line 97) and :134 (the assertion `PRs read: 7 9`)
- Reachable by a template-following job: only by an off-template checkpoint. Letter, bold, backtick, `#1`, `Phase 1`, `(1)` keys break `templates/checkpoint.md:24` ("Each row's first cell starts with a digit"). An indented row, a tab after the pipe, and a row with no leading pipe do NOT break that sentence as worded (the first cell still starts with a digit) and are unseen all the same. A second adjacent `## Phase plan` heading breaks no stated rule either; it is a table the template does not show.
- Scope of this finding: rows inside a `## Phase plan` section, including one under a second `## Phase plan` heading that the `sed` range skips. A row under some other `## ` heading is outside the Phase plan, which issue 26 and round 1 (P3R1-15, the test at tests/41-ci-wait.sh:98-99) put out of reach on purpose; that one is R-6, not part of this HIGH.
- Direction: fail-open
- Origin: introduced by this diff for the CI read (the base refuses the same file, with and without the prose line, because it read PR tokens from the whole file). The same blindness in `receipt_check` and `receipt_all_done` is pre-existing.
- Not a residual of ruling 1: no `no PR` is written anywhere on the row; the row says `PR #7`. Ruling 1 says every done row must hold one of the two tokens; here a done row holds one and is never looked at.
- Failure path: ROW 1 = `| P1 | impl | green | done (abc1234) · PR #7 |`, record for PR 7 `failure`. `cp_plan_rows` keeps only lines matching `^| *[0-9]` between `## Phase plan` and the next `## ` line, so the row never reaches awk. `cp_open_rows` is empty, `receipt_all_done` passes. `cp_done_cells` yields row 0 only (`no PR`), `cells` is non-empty, `prs` is empty, the `for pr` loop runs zero times. `run.log` gets `CI at done: PRs read: none; rows that say no PR: 0`, the same line an honest job gets. `chain_end 0 "job done"`.
- Evidence (commands run in the harness; now / base+prose / base-np):
  - `| P1 | …PR #7 |`: PASS / E10 red / E10 red. Full order with real receipts: PASS / E10 red.
  - `| **1** |`, `` | `1` | ``, `| #1 |`, `| Phase 1 |`, `| (1) |`, `| v1 |`, `| one |`, `| ① |`: PASS / E10 red / E10 red.
  - ` | 1 | …` (one leading space), `<TAB>| 1 | …`, `|<TAB>1 | …`, `|<NBSP>1 | …`, `<ZWSP>| 1 | …`, `<BOM>| 1 | …`, `<NUL>| 1 | …`, `1 | impl | green | done (abc1234) · PR #7 |`, `> | 1 | …`, `<!-- | 1 | … | -->`: PASS / E10 red / E10 red (the two NUL rows: base PASS, the base's own NUL hole).
  - A line `## Phase plan (continued)` before ROW 1 (the second heading ends the first range and does not start a new one): PASS / E10 red / E10 red.
  - Same with PR 7 having no record: PASS / E10 norecord. With a stale record (record head A, head now B): PASS / E10 stale. With an absent record at head B (workflow file there): PASS / PASS (the base passed every absent).
  - With row 0 = `done (abc1234) · PR #5` (green record) instead of `no PR`: PASS, `PRs read: 5`.
  - An unseen row with no sha and no receipt, full order: PASS (pre-existing half).
  - Control, all rows unseen: E10 no-done-row (the new refusal holds).
- Why the fix baton's "pre-existing parser, out of scope" does not hold for CI: the parser is old, but the base's `ci_check` did not use it. This diff is what routes the CI gate through it. The measured before and after differ.
- Likelihood: low by accident (a child has to add or rewrite one row off-format while leaving another readable), nil added value on purpose (an on-purpose child has `no PR`). Rated HIGH because it is a measured fail-open regression of the gate this phase exists to close, the suite asserts it as wanted, and nothing in `run.log` shows it. A synthesizer who weighs likelihood first may put it at MEDIUM.
- Suggested fix: do not read the row; refuse it. At `done`, exit 10 when the Phase plan section holds a line with a `|` that is not a row the runner reads, the header or the separator, naming the line. Checked on the template and on my attack files: `sed -n '/^## Phase plan/,/^## /p' checkpoint.md | grep -a '|' | grep -avE '^\| *[0-9]|^\| *# *\||^\|[ :|-]+$'` prints nothing for `templates/checkpoint.md` and prints the hidden row for the letter, indent, tab, NBSP, no-leading-pipe, blockquote and comment forms. Also refuse more than one `^## Phase plan` line. Rows under another heading (R-6) and deleted rows (R-2) need the row count remembered. Then turn `tests/41-ci-wait.sh:97` (`P1` row) from "must not hold done back" into a refusal case.

### PEN-2: A second PR written without `#` beside a valid token is dropped without a word
- Severity: MEDIUM
- File: lib/ci.sh:69,72-73 (`stray='#[0-9]|/pull/'`), lib/ci.sh:104
- Reachable by a template-following job: only by an off-template checkpoint (a phase with two PRs, the second written `PR 7`, `, 7`, `/7`, `pull/7`, or as an `/issues/7` link; brief section 8 says one PR per phase).
- Direction: fail-open
- Origin: pre-existing token grammar, made worse. The stray check this diff added closes `PR #5, #7` and `PRs #5 and #7` and stops there. On the base the template-shaped file was still refused, because the Completed-phases line named `PR #7`.
- Failure path: ROW 1 = `| 1 | impl | green | done (abc1234) · PR #5, 7 |`, PR 5 green at its own head, PR 7 red. `ci_prs` reads `5`. The cell less its tokens is `done (abc1234) · , 7`, which holds no `#<digit>` and no `/pull/`, so no stray refusal. `PRs read: 5`. PR 7 is in no log line. Exit 0.
- Evidence (now / base+prose / base-np): `PR #5 and PR 7`, `PR #5, 7`, `PR #5/7`, `PR #5, pull/7`, `PR #5 (supersedes PR 7)`, `PR #5 · https://github.com/o/r/issues/7`, `PR #5 · https://github.com/o/r/pulls/7`, `PR #5 and PR # 7`, `PR #5 and PR ＃7`, `PR #5 and PR no. 7`, `PR #5 PR #<0xff>7`, `PR #5, PR #<ZWSP>7`: all PASS(read=5) / E10 red / PASS. `PR #5, 7` with PR 7 having no record at all: PASS / E10 norecord / PASS. Full order: PASS / E10 red. Controls: `PR #5, #7` and `PRs #5 and #7`: E10 stray.
- Suggested fix: after taking out the tokens read and a `no PR`, refuse a cell that still holds the word `PR`, `PRs`, `pull` or `issues/` (any case), or a bare number right after a token and a separator (`, 7`, `/7`, `& 7`, `and 7`). Or state the cell's whole grammar and refuse anything else: `done (<sha>) · PR #<n>[ · PR #<n>]…` or `done (<sha>) · no PR`, then the runner's own ` · usage …`.

### PEN-3: Nothing ties the PR a row names to the row: an unrelated green PR, or the right PR with its head moved to an old green commit, satisfies the gate
- Severity: MEDIUM
- File: lib/ci.sh:85-88, 110-116
- Reachable by a template-following job: yes by a slip (a wrong number typed in the cell), otherwise on purpose.
- Direction: fail-open
- Origin: pre-existing (round 2's P3R2-9, set aside as out of scope). On the base the template-shaped file was refused only because prose also named `PR #7`.
- Failure path: ROW 1 = `| 1 | impl | green | done (abc1234) · PR #5 |`. PR 5 is some other PR of the repo with a green record at its own head. PR 7, the phase's real PR, is red. `ci_check` asks only that `ci-pr-5.json` says `pr: 5`, `success`, and that its `head_sha` is PR 5's head now. Exit 0. If the child first gets `PR #5 CI unread`, the refusal tells it `blast-off ci-wait <job-dir> 5, then run again`, which turns the slip into a pass. Variant: the cell names PR 7 and the record is green at commit A; PR 7's branch is set back to A while the phase's work sits at another commit. The row's sha and the record's `head_sha` are never compared.
- Evidence: `PR #5` with 5 green and 7 red: PASS(read=5) / E10 red / PASS. `PR #7`, record success at A, head now A: PASS / PASS / PASS.
- Suggested fix: at `done`, for each row, require the row's sha to be an ancestor of (or equal to) its PR record's `head_sha` (`git merge-base --is-ancestor`, local, no network), and refuse otherwise. It does not stop a later stacked PR being named in an earlier row, so it is a partial tie.

### PEN-4: `no PR` is matched as a substring anywhere in the cell, so words that are not the statement count as it
- Severity: LOW
- File: lib/ci.sh:74
- Reachable by a template-following job: only by an off-template checkpoint (free text in the Status cell that happens to hold the words `no PR`, and the PR written without `#`).
- Direction: fail-open
- Origin: introduced by this diff (the matcher is new). This finding is only about text that does not say the phase has no PR. Every cell that does say so, in whatever dress, is R-1.
- Failure path: ROW 1 = `| 1 | impl | green | done (abc1234) · PR 7 has no PR checks |`. `ci_prs` reads nothing (`PR 7` has no `#`). No stray. The grep at `:74` matches `no PR` inside "no PR checks". The row goes into `none`. Exit 0, PR 7 red. The same holds for "no PR review yet", "no PR comments" and the like.
- Evidence (now / base+prose / base-np): `PR 7 has no PR checks`: PASS(nopr=0 1) / E10 red / PASS. With the PR written the template's way the same words are refused: `PR #7 · no PR checks`: E10 both. Refused as neither: `no  PR` (two spaces), `no PRs`, `noPR`, `no-PR`, `no_PR`, `none`, `n/a`, `PR none`, `no pull request`, `piano PR 7`, `éno PR 7`.
- Suggested fix: accept `no PR` only as a whole `·`-separated part of the cell (after the sha, before the runner's ` · usage`), not as a substring. `PR 7 has no PR checks` then reads as neither.

### PEN-5: A row with no trailing pipe has its "Done when" cell read as the Status cell; with the right words there it passes and its real Status cell, PR and all, is never read
- Severity: LOW
- File: lib/checkpoint.sh:44 (`st = $(NF-1)`)
- Reachable by a template-following job: only by an off-template checkpoint (no trailing pipe, a "Done when" text that starts with "done", holds a 7 to 40 character hex word and the words `no PR`).
- Direction: fail-open in that one shape; fail-closed (exit 9, or exit 10 "neither" with a message that points at a cell the reader sees as fine) otherwise
- Origin: pre-existing parser (P3R1-29), made worse: the base read `PR #7` from the whole file and refused.
- Failure path: ROW 1 = `| 1 | impl | done when 9b68a67 is green, no PR needed | done (9b68a67) · PR #7` (no pipe at the end). awk's `$(NF-1)` is the third cell. It starts with "done", so the row is done; `cp_row_sha` finds `9b68a67` in it; `ci_check` finds `no PR` in it. The real last cell is never read.
- Evidence: full order with a real receipt: PASS / E10 red. Without the hex word: `END 9: phase row 1 is done but names no commit` on both. Plain no-trailing-pipe row: E9 open on both. Extra cell after Status (`… | done (abc1234) · PR #7 | note |`): E9 open on both. On purpose only: `| 1 | impl | green | PR #7 red | done (abc1234) · no PR |`, `… | PR #7 red \| done (abc1234) · no PR |`, `… | done (abc1234) · no PR | PR #7 red`: PASS / E10 red / E10 red; these carry an explicit `no PR` and are R-1 in another coat.
- Suggested fix: PEN-1's fix covers it if a row must also end in `|` and have the header's cell count; otherwise refuse a row whose cell count differs from the header row's.

### PEN-6: The record file is taken on trust; a hand-written `success` passes, and so do a record of two JSON values and a `head_sha` that is no sha
- Severity: LOW
- File: lib/ci.sh:86, 112-114
- Reachable by a template-following job: no; on purpose only.
- Direction: fail-open
- Origin: pre-existing (P3R2-10, set aside). Same result on the base.
- Failure path: write `gate-logs/ci-pr-7.json` = `{"pr":7,"head_sha":"<PR 7's head now>","verdict":"success"}` by hand. `ci_check` reads `.verdict`, `ci_head` compares `.head_sha` with gh. Exit 0. `runs` is not looked at: `{"pr":7,…,"verdict":"success","runs":[{"conclusion":"failure"}]}` passes too.
- Evidence (now / base): hand-written success: PASS / PASS. success with a failed run listed: PASS / PASS. `{…success}{"pr":8}` (two values; jq prints `success` and an empty line, `$(…)` drops the empty one): PASS / PASS. `"pr":7.0`: PASS / PASS. `head_sha":"null"` with a gh that answers `{"headRefOid":null}`: PASS / PASS (needs a gh that answers so; the real one does not, from recall). Refused as unread: failure-then-success, other-then-success, `"pr":"7"`, no `pr`, `Success`, missing, null or array verdict, an array record, an empty or cut-off file, PR 5's record copied to `ci-pr-7.json`, no file.
- Suggested fix: out of this phase's scope, as the fix baton says. Cheap hardening if wanted: `jq -e` on one value only (`jq -s 'length == 1'`), recompute the verdict from `runs` in `ci_check`, and require `head_sha` to match `^[0-9a-f]{40}$` there as `ci_wait` does at `:19`.

### PEN-7: The absent read honours git replace refs, so a replaced head reads as having no workflow file
- Severity: LOW
- File: lib/ci.sh:92
- Reachable by a template-following job: no; on purpose only.
- Direction: fail-open
- Origin: introduced by this diff
- Failure path: PR 7's head Y has `.github/workflows/ci.yml` and no runs; record `absent`. In the workdir's repo: `git replace Y <a commit with no workflow file>`. `git -C "$TOP" ls-tree -r --name-only "Y^{commit}" -- .github/workflows` now prints nothing, exit 0. `ci_check` logs `no CI runs and no workflow file at its head` and passes.
- Evidence: in `/tmp/p3r3-pen.DzaelL/repo2`: before the replace the command prints `.github/workflows/ci.yml`; after `git replace` it prints nothing with rc 0; with `GIT_NO_REPLACE_OBJECTS=1` it prints the file again.
- Suggested fix: `GIT_NO_REPLACE_OBJECTS=1 git -C "$TOP" ls-tree …`. A child that would do this can also write the record by hand (PEN-6), so it buys little alone.

### PEN-8: Three honest ways of writing the cell or the tree are refused, one of them a form the template itself allows
- Severity: LOW
- File: lib/ci.sh:72-75, 92-94
- Reachable by a template-following job: yes
- Direction: fail-closed
- Origin: introduced by this diff
- Failure path and evidence:
  - `done (abc1234) · [#7](https://github.com/o/r/pull/7)`: the template says "as `PR #<n>` (or its /pull/<n> link)". The link is read (`/pull/7`), then the `#7` left in the link text is a stray. Now E10 stray; base E10 red (it read PR 7). With a green record for PR 7 (run): now E10 stray, base PASS. `[PR #7](https://github.com/o/r/pull/7)` is read fine.
  - `done (abc1234) · PR #7 · no PR checks`: E10 both ("keep the one that is true"), though nothing false is written.
  - A PR head whose `.github/workflows` holds only `README.md`, or is a file or a symlink: `ls-tree` prints a path, so an absent record is refused for good with "there is no override: ask the owner". Measured in `repo2`: `README.md` only, a file, a symlink, `sub/ci.yml` all print a path. (`.GitHub/workflows` prints nothing and passes; whether GitHub runs workflows from that spelling I did not check.)
- Suggested fix: take out a whole markdown link `[…](…/pull/<n>)` as one token before the stray test; PEN-4's fix handles the second; for the third, ruling 2 says "a file", so leave it and name it in the spec (it does: "any file").

### PEN-9: The template says less than the parser needs, and its two sentences together are the recipe for PEN-1
- Severity: LOW
- File: templates/checkpoint.md:24, 33
- Reachable by a template-following job: yes (it is the template)
- Direction: neither (text); it feeds a fail-open
- Origin: line 24 pre-existing, line 33 introduced by this diff
- Failure path: line 24, "Each row's first cell starts with a digit (0, 1, 2a): the runner only sees rows like that", does not say the line must start at column 0 with `|` then spaces only, that the Status cell must be the last cell, or that the row must end with `|`. A child that indents the table or drops trailing pipes has kept every stated rule. Line 33, "It reads PRs nowhere else in this file", read beside line 24, tells a child exactly how a row leaves the gate: give it a key that does not start with a digit.
- Evidence: file read; PEN-1 and PEN-5 measurements.
- Suggested fix: with PEN-1 fixed the recipe stops working. Then say in line 24 what a row is: "a line that starts `| <digit>` at the left margin and ends with `|`; Status is its last cell; the runner refuses done while the table holds a line it cannot read."

### PEN-10: Nothing an owner reads says that a job started before this change is refused at `done` until its rows are edited
- Severity: LOW
- File: README.md:114-119,134; docs/spec.md:97
- Reachable by a template-following job: yes (any job whose checkpoint was written from the old template)
- Direction: fail-closed, with a push toward the wrong edit
- Origin: introduced by this diff
- Failure path: an old checkpoint has `done (<sha>)` rows and its PRs under Completed phases; the base read them there. After this change the runner exits 10 "says neither". At `status: done` no child is launched, so the owner edits the file. The refusal and README row 10 say what to write and are correct ("`PR #<pr>`, or `no PR` if the phase opened none"). Nothing tells that owner the PRs to write are the ones the old checkpoint names under Completed phases; an owner who adds `no PR` to each refused row instead takes PRs the base gated out of the gate.
- Evidence: `grep -n -i 'before this\|existing checkpoint\|started before\|live job\|older checkpoint\|upgrade' README.md docs/spec.md skills/blast-off/SKILL.md templates/*.md` prints nothing. Measured: row with neither, PR 7 red in prose: now E10 neither / base+prose E10 red; the same row after `no PR` is added: now PASS.
- Suggested fix: one README line: "A job started before this change: write each done row's own PR into its Status cell from the Completed-phases summary; `no PR` only where the summary names none."

## Residuals of the rulings (reported as asked; not defects)

### R-1 (ruling 1): an explicit `no PR` on a row that has a PR passes with that PR red, unread or absent
- Checkpoint: ROW 1 = `| 1 | impl | green | done (abc1234) · no PR |`, PR 7 red, `PR #7` still under Completed phases.
- Result: now PASS (`PRs read: none; rows that say no PR: 0 1`) / base+prose E10 red / base-np PASS. Pinned as ruled at tests/41-ci-wait.sh:181-184.
- Same result for every dress of the statement, with the PR beside it written without `#`: `NO PR`, `No pr`, `(no PR)`, `no PR yet`, `no PR; see PR 7`, `no PR (PR 7 draft)`, `no PR · pull/7`, `no PR · PR # 7`, `no PR · PR №7`, `no PR · https://github.com/o/r/issues/7`, `<!-- no PR --> PR 7`, `no<NUL> PR`. Refused: `no PR · PR #7` and `no PR #7` (both), `no PR · #7` and `no PR<NBSP>#7` (stray).
- Who can produce it: only by breaking `templates/checkpoint.md:31` ("Write `no PR` only for a phase that opened no PR") and `templates/brief.md:145-146`; on purpose, or a child that closes a row before its PR exists.
- No refusal message, README line, spec line or template line I read tells anyone to swap `PR #7` for `no PR` after an exit 10. The "both" refusal says "keep the one that is true".

### R-2 (ruling 1): a deleted row takes its PR with it
- Checkpoint: ROW 1 removed, `PR #7` left under Completed phases, PR 7 red.
- Result: now PASS / base+prose E10 red / base-np PASS. No template rule says a row may not be removed. The receipt gate has the same gap (pre-existing).
- A fix that reads no prose: log `cp_phases` at each child's start and refuse `done` when the count is lower than the highest seen.

### R-3 (ruling 2): a PR head with no workflow file passes on absent although runs were due or CI exists elsewhere
- Record `absent` at head A or C (no workflow file) while the default branch tip B has one: now PASS, logged `no CI runs and no workflow file at its head` / base PASS. Pinned at tests/41-ci-wait.sh:230-234.
- A head that deletes `.github/workflows` (measured in `repo2`: `ls-tree` prints nothing): passes. A child can make this head on purpose.
- From recall, not checked: GitHub starts `pull_request` workflows from the PR's merge ref, so a base-only workflow does run on such a PR; "no runs" there can mean a merge conflict or a path filter, not "no CI configured". `pull_request_target` and ruleset-required workflows live outside the head too. CI that is not GitHub Actions (status checks from another service) is never read by `gh run list`; that part is pre-existing.

### R-4 (ruling 2): a PR whose head has a workflow file that cannot start on it has no exit but a false statement
- Record `absent` at head B: now E10 absent+wf / base PASS. The message says "there is no override: ask the owner".
- From the attacker's side: the owner has no sanctioned move either. What ends the job is `no PR` in the cell (R-1), a hand-written record (PEN-6) or a replace ref (PEN-7). From recall: `on: pull_request: branches: [main]` is a common trigger, and a stacked PR whose base is the previous phase's branch (brief section 8) gets no run under it. An obedient child follows `templates/brief.md:135-137`, leaves the row open and sets `status: blocked` (exit 3), which is the honest end.

### R-5 (ruling 2, fail-closed side): a head git cannot read, or no git repo
- Record `absent` at X (not in the repo): now E10 absent+unreadable / base PASS. `TOP` empty: now E10 absent+nogit / base PASS. A tree sha or `--help` as `head_sha` (with a gh that answers the same): E10 absent+unreadable. A short sha or a branch name as `head_sha`, with a gh that answers the same string: PASS (not reachable with the real gh, from recall; `ci_check` does not test the 40-hex shape, PEN-6).

### R-6 (issue 26 and round 1's P3R1-15): a digit-keyed done row under another `## ` heading is not a Phase plan row
- Checkpoint: a line `## Phase 1 detail` between ROW 0 and ROW 1, PR 7 red.
- Result: now PASS (`PRs read: none`) / base+prose E10 red / base-np E10 red. The base read the whole file; issue 26 asked for the Phase plan only, and tests/41-ci-wait.sh:98-99 with :134 pins that such a row's PR is not read.
- Who can produce it: a child that puts a heading inside its table; no stated rule forbids it, and no receipt or done check sees the row either (pre-existing). R-2's row count would catch it.

## Every attack tried

Columns: result now / base+prose / base-np. "np" = the Completed-phases line does not name PR #7. Unless said, PR 7 is `failure` at B, row 0 is `no PR`.

| # | Checkpoint shape (ROW 1 unless said) | now | base+prose | base-np |
|---|---|---|---|---|
| 1 | control `done (abc1234) · PR #7`, red | E10 red | E10 red | E10 red |
| 2 | control, PR 7 green | PASS read=7 | PASS | PASS |
| 3 | control, no record | E10 norecord | E10 norecord | E10 norecord |
| 4 | control, record at A, head now B | E10 stale | E10 stale | E10 stale |
| 5 | control, gh fails | E10 stale/gh | E10 stale/gh | E10 stale/gh |
| 6 | `done (abc1234)` (neither) | E10 neither | E10 red | PASS |
| 7 | key `P1` | PASS | E10 red | E10 red |
| 8 | key `**1**` | PASS | E10 red | E10 red |
| 9 | key `` `1` `` | PASS | E10 red | E10 red |
| 10 | keys `#1`, `Phase 1`, `(1)`, `①`, `١`, `v1`, `one` | PASS | E10 red | E10 red |
| 11 | keys `2a`, `1.`, `01`, `1 a` | E10 red | E10 red | E10 red |
| 12 | keys `1)`, `1️⃣`, `1<0xff>`, `1<NUL>` | E9 open | E9 open | E9 open |
| 13 | row indented one space | PASS | E10 red | E10 red |
| 14 | tab before the row | PASS | E10 red | E10 red |
| 15 | `|<TAB>1 |` | PASS | E10 red | E10 red |
| 16 | `|<NBSP>1 |` | PASS | E10 red | E10 red |
| 17 | `<ZWSP>| 1 |`, `<BOM>| 1 |` | PASS | E10 red | E10 red |
| 18 | `<NUL>| 1 |`, `|<NUL> 1 |` | PASS | PASS (base NUL hole) | PASS |
| 19 | no leading pipe `1 | impl | …` | PASS | E10 red | E10 red |
| 20 | `> | 1 | …` | PASS | E10 red | E10 red |
| 21 | `<!-- | 1 | … | -->` | PASS | E10 red | E10 red |
| 22 | `## Phase 1 detail` line before the row | PASS | E10 red | E10 red |
| 23 | `## Phase plan (continued)` line, or a bare second `## Phase plan` line, before the row | PASS | E10 red | E10 red |
| 24 | `### sub` line before the row | E10 red | E10 red | E10 red |
| 25 | second table (own header) in the same section | E10 red | E10 red | E10 red |
| 26 | `|0|spec|…|` and `|1|impl|green|done (abc1234) · PR #7|` | E10 red | E10 red | E10 red |
| 27 | `| P1 | impl | green | pending |` (open, unseen) | PASS | E10 red | PASS |
| 28 | ROW 1 deleted | PASS | E10 red | PASS |
| 29 | both rows keyed `P0`, `P1` | E10 no-done-row | E10 red | E10 red |
| 30 | row 0 `PR #5` green, ROW 1 key `P1` PR 7 red | PASS read=5 | E10 red | E10 red |
| 31 | key `P1`, PR 7 no record | PASS | E10 norecord | E10 norecord |
| 32 | key `P1`, PR 7 stale | PASS | E10 stale | E10 stale |
| 33 | key `P1`, PR 7 absent at B | PASS | PASS | PASS |
| 34 | `PR #5 and PR 7` (5 green) | PASS read=5 | E10 red | PASS |
| 35 | `PR #5, 7` | PASS read=5 | E10 red | PASS |
| 36 | `PR #5/7` | PASS read=5 | E10 red | PASS |
| 37 | `PR #5, pull/7` | PASS read=5 | E10 red | PASS |
| 38 | `PR #5 (supersedes PR 7)` | PASS read=5 | E10 red | PASS |
| 39 | `PR #5 · https://github.com/o/r/issues/7`, `…/pulls/7` | PASS read=5 | E10 red | PASS |
| 40 | `PR #5 and PR # 7`, `PR ＃7`, `PR no. 7` | PASS read=5 | E10 red | PASS |
| 41 | `PR #5 PR #<0xff>7`, `PR #5, PR #<ZWSP>7` | PASS read=5 | E10 red | PASS |
| 42 | `PR #5, 7`, PR 7 no record | PASS read=5 | E10 norecord | PASS |
| 43 | `PR #5, #7`, `PRs #5 and #7`, `PR #5 <0xff>, #7` | E10 stray | E10 red | PASS |
| 44 | `PR #5` (wrong number; 5 green, 7 red) | PASS read=5 | E10 red | PASS |
| 45 | `PR #7`, record green at A, head now A | PASS | PASS | PASS |
| 46 | `PR 7`, `PR-7`, `PR: 7`, `PR # 7`, `GH-7`, `PR №7`, `pull request 7`, `pull/7`, `PR #0`, `PR #-7`, `PR#７` | E10 neither | E10 red | PASS |
| 47 | `PR  #7`, `PR: #7`, `#7`, `PR&nbsp;#7`, `PR \#7`, `o/r#7` | E10 stray | E10 red | PASS |
| 48 | `pr#7`, `Pr #07`, `/pull/7`, `https://github.com/o/r/pull/7/files`, `[PR #7](…/pull/7)`, `PR #7a`, `~~PR #7~~` | E10 red | E10 red | E10 red |
| 49 | `[#7](https://github.com/o/r/pull/7)` | E10 stray | E10 red | E10 red |
| 50 | `no PR`, `NO PR`, `No pr`, `(no PR)` | PASS nopr | E10 red | PASS |
| 51 | `no PR yet` | PASS nopr | E10 red | PASS |
| 52 | `no PR; see PR 7`, `no PR (PR 7 draft)`, `no PR · pull/7`, `no PR · PR # 7`, `no PR · PR №7`, `no PR · …/issues/7` | PASS nopr | E10 red | PASS |
| 53 | `PR 7 has no PR checks` | PASS nopr | E10 red | PASS |
| 54 | `<!-- no PR --> PR 7` | PASS nopr | E10 red | PASS |
| 55 | `no<NUL> PR` | PASS nopr | PASS | PASS |
| 56 | `no  PR`, `no PRs`, `noPR`, `no-PR`, `no_PR`, `none`, `n/a`, `PR none`, `no pull request`, `piano PR 7`, `éno PR 7` | E10 neither | E10 red | PASS |
| 57 | `no PR · PR #7`, `no PR #7`, `PR #7 · no PR checks`, `PR #5 n<NUL>o PR` | E10 both | E10 red | E10 red (NUL case PASS) |
| 58 | `no PR · #7`, `no PR<NBSP>#7`, `no PR · #<NUL>7` | E10 stray | E10 red (NUL case PASS) | PASS |
| 59 | absent, head C (no workflow file) | PASS, logged | PASS | PASS |
| 60 | absent, head A (none; default branch has one) | PASS, logged | PASS | PASS |
| 61 | absent, head B (workflow file) | E10 absent+wf | PASS | PASS |
| 62 | absent, head X (not in the repo) | E10 absent+unreadable | PASS | PASS |
| 63 | absent, no git repo (`TOP` empty) | E10 absent+nogit | PASS | PASS |
| 64 | absent, record at C, head now B | E10 stale | E10 stale | E10 stale |
| 65 | absent, gh fails | E10 stale/gh | E10 stale/gh | E10 stale/gh |
| 66 | absent, `head_sha` a tree sha / `--help` (gh answers the same) | E10 absent+unreadable | PASS | PASS |
| 67 | absent, `head_sha` a 7-char sha / branch name of C (gh answers the same) | PASS, logged | PASS | PASS |
| 68 | absent, head whose `.github/workflows` is a file, a symlink, README only, `sub/ci.yml` (ls-tree run by hand) | refused (path printed) | n/a | n/a |
| 69 | absent, head that removed `.github/workflows`; `.GitHub/workflows` (ls-tree by hand) | passes (nothing printed) | n/a | n/a |
| 70 | absent, head with a workflow file, `git replace` to a commit without (ls-tree by hand) | passes (nothing printed) | n/a | n/a |
| 71 | no trailing pipe | E9 open | E9 open | E9 open |
| 72 | no trailing pipe, Done-when `done when green, no PR needed` | PASS nopr (real runner: exit 9, no sha) | E10 red | E10 red |
| 73 | no trailing pipe, Done-when `done when <sha7> is green, no PR needed`, full order | PASS | E10 red | n/a |
| 74 | extra cell after Status `… | done … PR #7 | note |` | E9 open | E9 open | E9 open |
| 75 | `… | PR #7 red | done (abc1234) · no PR |` | PASS nopr | E10 red | E10 red |
| 76 | `… | PR #7 | done (abc1234) |` | E10 neither | E10 red | E10 red |
| 77 | `… | done (abc1234) | PR #7 |` | E9 open | E9 open | E9 open |
| 78 | `… | PR #7 red \| done (abc1234) · no PR |` | PASS nopr | E10 red | E10 red |
| 79 | `… | done (abc1234) · no PR | PR #7 red` | PASS nopr | E10 red | E10 red |
| 80 | `… | done (abc1234) · PR #5 | and #7 (red)` | PASS read=5 | E10 red | PASS |
| 81 | trailing spaces after the last pipe | E10 red | E10 red | E10 red |
| 82 | `Done`, `DONE`, `done.`, ` done`, `donezo`, `Done ✔` | E10 red | E10 red | E10 red |
| 83 | `✅ done`, `**done**`, `` `done` ``, `complete`, `closed`, `merged`, `[x] done`, `<0xff>done`, `<NUL>done`, `do<NUL>ne` | E9 open | E9 open | E9 open |
| 84 | two rows keyed `1`: first `no PR`, second `PR #7` | E10 red | E10 red | E10 red |
| 85 | second row keyed `0` with `PR #7` | E10 red | E10 red | E10 red |
| 86 | heading `## Phase Plan`, `### Phase plan`, `##  Phase plan`, ` ## Phase plan`, `## Phases`, `<BOM>## Phase plan` | E10 no-done-row | E10 red | n/a |
| 87 | heading `## Phase plan (3 phases)` | E10 red | E10 red | n/a |
| 88 | no table at all, `PR #7` in prose | E10 no-done-row | E10 red | n/a |
| 89 | header-only table | E10 no-done-row | E10 red | n/a |
| 90 | two `## Phase plan` sections with `## Notes` between, row 1 in the second | E10 red | E10 red | n/a |
| 91 | two `## Phase plan` lines one after the other, then both rows | E10 no-done-row | E10 red | n/a |
| 92 | CRLF on the two rows; CRLF on every line | E10 red | E10 red | E10 red |
| 93 | BOM at the start of the file | E10 red | E10 red | n/a |
| 94 | `P<NUL>R #7`, `PR #<NUL>7`, NUL after the last pipe | E10 red | PASS (base NUL hole) | n/a |
| 95 | `done (abc1234) <0xff> PR #7` | E10 red | E10 red | E10 red |
| 96 | `status: done` then `status: running` | cp_status `done`; E10 red | same | n/a |
| 97 | `status: running` then `status: done` | cp_status `running`: a child is launched, no exit 0 | same | n/a |
| 98 | `status: done (PR #7 CI red, see below)` | cp_status `done`; gated as usual | same | n/a |
| 99 | `status: done-pending-ci`, `status: Done`, BOM before `status:` | cp_status not `done`: no exit 0 | same | n/a |
| 100 | record hand-written `success` | PASS | PASS | n/a |
| 101 | record `success` listing a failed run | PASS | PASS | n/a |
| 102 | record `{…success}{"pr":8}` | PASS | PASS | n/a |
| 103 | record `"pr":7.0` | PASS | PASS | n/a |
| 104 | record `"head_sha":"null"`, gh answers null | PASS | PASS | n/a |
| 105 | records: failure-then-success, other-then-success, `"pr":"7"`, no `pr`, `Success`, verdict missing / null / array, array record, empty, cut off, PR 5's record copied, `head_sha` missing or empty | E10 norecord or stale | same | n/a |

Rows 7 to 21, 23 and 30 to 33 are PEN-1 (row 27 is its pre-existing half: an open row nobody sees). Row 22 is R-6. Rows 34 to 42 and 80 are PEN-2. Rows 44, 45 are PEN-3. Row 53 is PEN-4. Rows 72, 73 are PEN-5. Rows 100 to 104 are PEN-6. Row 70 is PEN-7. Row 49 is PEN-8. Rows 50 to 52, 54, 55, 75, 78, 79 are R-1. Row 28 is R-2. Rows 59, 60, 69 are R-3. Row 61 is R-4. Rows 62, 63, 66, 67 are R-5. Both locales (`C.UTF-8`, `C`) gave the same result for rows 16 to 18, 41, 43, 55, 57, 58, 92, 94, 95.

## Round-2 HIGH status

- P3R2-1: reshaped. The named door is shut: a seen done row with neither token is E10 neither (row 6), with a red PR only in prose (tests/41-ci-wait.sh:175-180). The same outcome, a done row's red PR passing because another row is readable, is open through a row the parser does not see (PEN-1, rows 7 to 21 and 23: now PASS, base E10) and through a second PR written without `#` (PEN-2).
- P3R2-2: resolved. In no run did this HEAD read a PR from prose: every "now" result is the same with and without the prose line, and `PRs read:` never lists 7 unless a seen Status cell names it. A `/pull/N` link inside a Status cell is still read as this repo's PR N whatever repo it names; that is fail-closed and the template asks for the phase's own PR there.
- P3R2-3: resolved for the case it named; the pressure it described remains for one neighbour. An absent record at a head with no workflow file passes, logged (rows 59, 60). The "cannot be read" remedy (`git -C <top> fetch origin pull/<n>/head`) is workable where the remote is called `origin` (reasoned, not run). For a head whose workflow file cannot start on the PR (a base-branch or path filter) the refusal stands with no override, and the only edits that end the job are a false `no PR`, a hand-written record or a replace ref (R-4). That is ruling 2 as ruled.
- P3R2-4: resolved. `templates/checkpoint.md:30-34` states an obligation ("Write `no PR` only for a phase that opened no PR") and no longer says a row closed without a PR gets no check; `tests/51-templates.sh:74-82` pins the four sentences and forbids the two old ones. What is left is PEN-9: lines 24 and 33 read together still say how a row leaves the gate, and that works until PEN-1 is fixed.

## Acceptance criteria

1. Met. Absent at a head with a workflow file: E10 (row 61; base PASS). Test: tests/41-ci-wait.sh:236-237.
2. Met. Absent at a head with none: PASS, logged (rows 59, 60). Test: tests/41-ci-wait.sh:227-229. An obedient child reaches it: `templates/brief.md:135-137` sends only heads with a workflow file to "push once more … `status: blocked`".
3. Met in part. Prose is never read (tests/41-ci-wait.sh:185-189) and a seen done row with neither token is refused (tests/41-ci-wait.sh:169-171). But "a done row with neither … is refused" holds only for rows the parser sees: a done row it does not see is neither read nor refused (PEN-1), and tests/41-ci-wait.sh:91-99 asserts that.
4. Met, by reading only: `ci_runs` (lib/ci.sh:52-55) is the one place runs are listed; tests/41-ci-wait.sh:73-83 cover a green dispatch alone (absent), a red dispatch beside a green run (success) and a red push run (failure). I did not execute `ci_wait`.
5. Met in part. Tests for 1 to 4 exist and the README, spec, skill and templates state the rules. Not pinned or not stated: a refusal for an unreadable row (the opposite is pinned), PEN-2's forms, what a row is in the template (PEN-9), and the note for jobs started before the change (PEN-10).

## New dependencies or reliance

- `git ls-tree -r --name-only <sha>^{commit} -- .github/workflows` in the workdir's repo at `done` (git was already required). It needs the PR's head commit present locally, honours replace refs (PEN-7), and in a partial clone may fetch.
- The remedy text relies on a remote named `origin` and on GitHub's `pull/<n>/head` ref.
- `gh run list --json databaseId,event`: the `event` field (present in gh's run JSON fields, from recall; not checked against a gh version).
- GNU sed: the `I` flag in `s~…~~Ig` with `-E` (lib/ci.sh:72). Not POSIX.
- `paste -sd' '`, `grep -a`, bash process substitution and `=~` (lib/ci.sh:72,81,104).
- awk on a NUL byte: gawk here keeps the line; the test allows exit 9 or 10 for an awk that cuts it (tests/41-ci-wait.sh:206-209).
- The gate now relies on the row parser of `lib/checkpoint.sh:43-46` for CI, which the base did not.
