---
source: runner
scope: br-1115-issues
parent_session: ""
---
# Pass-Baton: phase 3 fix 3 (issue 26): P3R3-1 closed by rule, 13 MEDIUMs adjudicated, 4 LOWs fixed

**Date:** 2026-11-16
**Scope:** br-1115-issues
**Branch:** feat/br-1115-issues/phase-3
**Worktree:** /home/alex/blast-off/.claude/worktrees/pending-items-53932d
**HEAD:** d100fa1 chore(phase-3): owner chose guide & resume; run resumed (nothing committed by this unit; the manager owns git)

## Where things stand

All work is in the working tree, uncommitted. P3R3-1 fixed under the owner's direction, then every MEDIUM adjudicated (10 fixed, 1 moot, 3 out of scope), then 4 small LOWs. Every touched scenario green one at a time. Full-suite result: see "Last full run". New dependency: none. The new code relies only on what the old code already did (awk, GNU sed `I` flag, bash `${x,,}`); the `{0,3}` awk interval was removed so no gawk-only feature is needed.

## Per-finding disposition

| ID | Disposition | RED evidence | Files changed |
|---|---|---|---|
| P3R3-1 (HIGH) | SUPPORTED, fixed per owner direction. New `cp_unread` in lib/checkpoint.sh returns the first line that would keep a row away from the parser. That is a second Phase plan heading (any ATX level or case, or setext), or a `## Phase plan` section line that holds a `\|` and is not one of these: the header (the first `\|` line, first cell `#`, no digit, no "done" in its last cell), a separator, or a row the parser takes (`^\| *[0-9]`). A line with a carriage return in mid-line is refused too. `ci_check` calls it first at done: exit 10, naming the line number and the text. A failed read is exit 10 too. The rule closes the class, not one shape. Refused now: key `P1`, bold, strikethrough, indented, tab-led, a tab after the pipe, no leading pipe, a `#`-keyed done row posing as the header, a later `#` row (pending or done), a row inside an HTML comment, a CR joining two rows, and a second heading inside or after the section. Still allowed: CRLF, aligned separators, `###` sub-headings and prose with no pipe. Test 41: old line 97 (the `P1` row in the `fin` fixture) became the first case of the new refusal loop; old line 132 now checks only PRs 97-99. 18 refusal cases and 1 pass case added. Fixtures (tests/lib.sh new_job, the `fin` and `close` modes in tests/fakes/claude, and plan() in tests 10/21/32/40/60/61) all write digit-keyed rows at the left margin, and each of those scenarios passes. The template rule had to lose its literal pipes, because the template's comment sits inside the section; the new 51 check caught this. | `fix-phase-3-iter-3/red-p3r3-1.log`: `FAIL: unread line '\| P1 \| a \| b \| done (abc1234) · PR #7 \|': exit 0, want 10`, and run.log reads `CI at done: PRs read: 8` then `job done` while PR #7's record is red. Template: the first `p3r3-1-51-templates.log` run named template line 25. | lib/checkpoint.sh, lib/ci.sh, tests/41-ci-wait.sh, tests/51-templates.sh, templates/checkpoint.md, README.md, docs/spec.md, bin/blast-off, skills/blast-off/SKILL.md |
| P3R3-2 | SUPPORTED, fixed. Brief step 4, `absent`: with a workflow file at the head, leave the row open, record it and go on (step 9 decides the status). With none, no CI is configured: close the row. "push once more" removed. Pinned in 51. | `red-medium-51-templates.log` (51 fails on the new pins before the text edit) | templates/brief.md, tests/51-templates.sh |
| P3R3-3 | SUPPORTED, fixed. Whitelist in `ci_check`: strip `done`, a `(<alnum>)` sha group, the runner's ` · usage ...`, PR tokens (URL `/pull/N`, `/pull/N`, `PR #N`) and `no PR`. Anything left that holds a digit, `#` or the word PR/PRs/pull is refused (exit 10). This replaces the `#<n>`//pull/ blacklist. | `red-p3r3-3.log`: `FAIL: Status cell 'no PR, see PR 7': exit 0, want 10` | lib/ci.sh, tests/41-ci-wait.sh (cells `no PR, see PR 7`, `PR #8, 7`, `PR #8,234`, `PR 7 · no PR checks failed`, `(see PR 7) no PR`), docs/spec.md |
| P3R3-4 | SUPPORTED, fixed in text. Skill step 4: if no workflow starts on the stacked branches, tell the owner before launch: refused at done, no override, `no PR` is no way out, and the PR base and trigger filter are theirs to change; record the choice in brief §2. Same words in the README exit-10 row and the `ci_check` absent refusal. Owner question 3 (an override) is still not ruled. | text; pinned in 70 (P3R3-7) | skills/blast-off/SKILL.md (addition only), README.md, lib/ci.sh |
| P3R3-5 | SUPPORTED, fixed with P3R3-1: the template states the row shape and the done refusal as an obligation. | see P3R3-1 | templates/checkpoint.md |
| P3R3-6 | SUPPORTED, fixed, 12 items. 1-2: exit 4 row in README (raising the cap is no way to done). 3: "no Phase plan table" became "no Phase plan row the runner reads" in README, spec:61/91, bin/blast-off:18, chain.sh comment and CAP_WHY. 4: README "no done row" became "no row the runner reads". 5: spec P4Q1 marked settled; "absent never reported as green" reworded. 6: MOOT by P3R3-1 (every row is now read or refused). 7: spec now says the Status cell is last and the row ends in a pipe. 8: "starts with a digit" (spec:61, checkpoint.sh). 9: spec F7 now names `ci_check` in lib/ci.sh and `ci-wait <job-dir> <pr>`. 10: template sentence rewritten (P3R3-9). 11, 12: fake comments corrected. | 10: `red-medium-10-chain-done.log` (new cap text) | README.md, docs/spec.md, bin/blast-off, lib/chain.sh, lib/checkpoint.sh, templates/checkpoint.md, tests/fakes/claude, tests/10-chain-done.sh |
| P3R3-7 | SUPPORTED, fixed. 51 now pins the row-shape and done-refusal sentence, the CI-record clause, the new PR sentences, the brief's two `absent` cases and the workflow-file ban. It forbids "It reads PRs nowhere else" and "the runner only sees rows". 70 pins three README rule phrases and three SKILL step 4 phrases (flattened). No mutant was run on the 70 pins. | `red-medium-51-templates.log` | tests/51-templates.sh, tests/70-docs.sh |
| P3R3-8 | SUPPORTED, fixed. Template, brief and the "neither" and "no done row" refusals now read: `no PR` only for a phase the brief says opens no PR; a PR that could not be opened is a blocked part. | pinned in 51 (RED above) | templates/checkpoint.md, templates/brief.md, lib/ci.sh |
| P3R3-9 | SUPPORTED, fixed. "names every PR the phase opened, each as `PR #<n>`"; "A PR that is not this job's goes in prose". | pinned in 51 | templates/checkpoint.md |
| P3R3-10 | SUPPORTED, fixed. "Both" refusal: "if the phase opened that PR, delete `no PR`; a PR that is not this job's goes in prose". The "no done row" refusal adds the `no PR` condition and "from the left margin". The prefixes the tests check are unchanged. | text (prefix kept for 41's checks) | lib/ci.sh |
| P3R3-11 | SUPPORTED, fixed. "Never add, remove or edit a workflow file to change what the runner reads of CI" (brief, pinned). The README exit-10 row and the absent refusal say it too. | pinned in 51 | templates/brief.md, README.md, lib/ci.sh |
| P3R3-12 | SUPPORTED, fixed. The hard-cap CAP_WHY appears in the start log and in preflight's `cap:` line, and now says "no Phase plan row the runner reads in checkpoint.md; done is refused (exit 10) until it has one". | `red-medium-10-chain-done.log`: `FAIL: hard cap source not logged: ... (hard: no Phase plan table in checkpoint.md)` | lib/chain.sh, tests/10-chain-done.sh |
| P3R3-13 | SUPPORTED, fixed in part. New `cp_rows [file]` is the one row reader for cp_phases, cp_plan_rows, cp_row, cp_row_sha and preflight's estimate (5 of the 7 copies). Still separate: `cp_mark_usage` (it edits in place with `sed -i`, so cannot share a reader) and `cp_unread` (it must see the lines that are not rows, by design). Tests 32, 40, 41, 51 and 60 green. | refactor, no behaviour change; scenarios green before and after | lib/checkpoint.sh, lib/preflight.sh |
| P3R3-14 | OUT OF SCOPE: pre-existing (P3R2-9), not in issue 26 or the rulings. Tying a row to its PR by ancestry is a new gate condition and needs the owner, because rows such as `done (earlier)` have no sha to test. | | |
| P3R3-15 | OUT OF SCOPE: pre-existing `ci_wait` listing behaviour (F7, D4-6), not issue 26. Re-listing at done would add gh calls under the lock; that is the owner's call. | | |

### LOW findings

Fixed (tiny, clearly right, covered by tests):
- P3R3-21 in part: m3 and m8 closed. `No PR` passes; `no PRs` and `PR #8 see /pull/x` are refused (test 41).
- P3R3-23: `git --no-replace-objects` on the workflow-file read (41's absent cases cover the line).
- P3R3-26: the mechanism clause dropped from the template; 51 forbids it.
- P3R3-38 in part: `timeout -k 5` on `ci_head` (41's hang case covers it). `ci_wait`'s watch keeps a plain timeout, because its 124 check logs the timeout.

Open, with the reason:
- P3R3-16: README line for jobs started before the change. A doc sentence no test pins; left for the owner.
- P3R3-17: the remaining stale sentences need a line-by-line pass beyond P3R3-6's twelve; README still omits the refusal of a cell with "both" tokens.
- P3R3-18: shape check on the record. Pre-existing; changes what a hand-written record does.
- P3R3-19: cell count against the header. Mostly exit 9 today; a new refusal rule.
- P3R3-20: which files count as workflow files is owner question 3, still unruled.
- P3R3-22: rewording the refusal's `origin` and push. Not tiny with the push order.
- P3R3-24, P3R3-31: the owner's call, as filed.
- P3R3-25: warn on an unused `ci-pr-*.json`. New behaviour.
- P3R3-27: collect all refusals into one. A restructure of `ci_check`.
- P3R3-28: markdown link `[#7](…/pull/7)` as one token. Still refused (fail-closed).
- P3R3-29: `/pull/N` of another repo. Pre-existing; needs the remote's name.
- P3R3-30: two fake comments fixed under P3R3-6 (11, 12); the other couplings are not changed.
- P3R3-32: `cp_done_cells` read through process substitution. Fail-closed today.
- P3R3-33: `timeout` on `ls-tree` in a partial clone. Needs a limit value and a test.
- P3R3-34: duplicate keys at the receipt gate. Pre-existing.
- P3R3-35: raw text in run.log. Pre-existing (P3R2-30).
- P3R3-36: remove the record at the start of ci-wait. Changes ci-wait, which has no test for a mid-run death.
- P3R3-37: number checks on `BLAST_OFF_CI_*`. Pre-existing.

## Instruction-text ledger (child-facing texts reworded on review direction; the manager or the owner reviews it)

- templates/checkpoint.md, row rule. Old: "Each row's first cell starts with a digit (0, 1, 2a): the runner only sees rows like that." New: a 4-line obligation: one heading and one table; rows from the left margin, keyed by a digit, Status last; done refuses a second heading or any other table line. The clause "the runner only sees rows like that" was dropped on purpose: it described a way past the gate.
- templates/checkpoint.md, PR rule. Changed: "the phase's own PR" became "every PR the phase opened"; "only for a phase that opened no PR" became "only for a phase the brief says opens no PR; a PR that could not be opened is a blocked part". Dropped: "It reads PRs nowhere else in this file" (P3R3-26) and "refuses any other '#<n>' in a Status cell", replaced by "Past `done (<sha>)` ... no other number, '#' or PR". Changed: "name another PR in prose" became "A PR that is not this job's goes in prose". Kept: refuses done for neither; wants a CI record.
- templates/brief.md, step 4. Dropped: "push once more for a run, and if none starts ... set `status: blocked`". Added: both `absent` cases and the workflow-file ban. The `no PR` condition was changed as above.
- skills/blast-off/SKILL.md: additions only (step 4 sentence; "each from the left margin" in step 5).

## Last full run

- Run 1 (`fix-phase-3-iter-3/full-run-1.log`): `GATE: FAIL passed=17 failed=1`. 00-harness: `FAIL: spec has no filled row for 10`. Cause: I had written a literal `|` (in backticks) into spec row 10, which split the table cell. Fixed by writing "a pipe" (docs/spec.md, 2 places). After the fix, 00-harness and 70-docs passed on single-scenario runs.
- Run 2, the final one (`fix-phase-3-iter-3/full-run-2.log`), started after the last tracked edit: `GATE: PASS passed=18 failed=0 shellcheck=ok`.
- ExecStart after both runs: `ExecStart=/home/alex/blast-off/.worktrees/blast-off-build/bin/blast-off run %f` (OK, untouched).
- `pgrep -af '[t]ests/run'` printed nothing before each full run. Temp dirs: only the suite's own; none created or deleted by hand.

## Residuals for round 4 (mine, not filed)

- `cp_unread` accepts a header only if it has no digit. A custom header such as `| # | Phase | 7d % | Status |` is refused at done. The refusal says "header first (first cell `#`)" but not "no digit". Fail-closed.
- One comment line in `ci_check` (lib/ci.sh, the "Refused:" sentence) now runs past the file's usual wrap width. Cosmetic; left alone so the last full run stays later than the last edit.

## References

- Owner direction: `baton-runner/br-1115-issues/failure-phase-3.md` (Owner choice); rulings `owner-rulings-phase-3.md`
- Findings: `baton-runner/br-1115-issues/baton-phase-3-review-3.md`, `review-phase-3-iter-3.md`
- Logs (RED and GREEN per step): `baton-runner/br-1115-issues/fix-phase-3-iter-3/`
- Code: `lib/checkpoint.sh` (`cp_rows`, `cp_unread`), `lib/ci.sh` (`ci_check`), `tests/41-ci-wait.sh` (the P3R3-1 and P3R3-3 loops)

## Next steps

1. Manager: review the diff (`git diff`), then commit under the review loop. Round 4 should press `cp_unread` for any line that still escapes it.
2. Owner: question 3 (which files count as workflow files; an override) is still behind P3R3-4 and P3R3-20.
