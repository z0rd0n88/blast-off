---
source: runner
scope: br-1115-issues
parent_session: ""
---
# Pass-Baton: phase 3 fix 4 (issue 26): one allow-list reader of the Phase plan; both HIGHs closed as a class

**Date:** 2026-11-16
**Scope:** br-1115-issues
**Branch:** feat/br-1115-issues/phase-3
**Worktree:** /home/alex/blast-off/.claude/worktrees/pending-items-53932d
**HEAD:** 8ab4316 chore(phase-3): review iter 4 record (verdict ISSUES) (nothing committed by this unit; the manager owns git)

## Where things stand

All work is uncommitted in the working tree. Step 1 is complete: the deny-list is replaced by one allow-list scanner, `cp_scan` in lib/checkpoint.sh, and every Phase plan reader goes through it. Step 2 is complete: all 14 MEDIUMs have a written disposition (10 fixed or fixed in part, 4 out of scope or kept). Step 3: 15 LOWs fixed or moot, 14 open. Last full run: see the end of this file. New dependency: none. The scanner is POSIX awk: it gave the same output under gawk 5.2.1, `gawk --posix` and mawk 1.3.4 on 10 fixtures (`fix-phase-3-iter-4/awk-portability-2.log`). GNU sed `-E` with the `I` flag is still used in ci_check (pre-existing).

## The rule as built (lib/checkpoint.sh `cp_scan`, called at done by `ci_plan` in lib/ci.sh, before every other done gate)

- **Section.** It runs from the first level-2 `## Phase plan` heading (any case) to the next ATX heading of level 1 or 2. A second Phase plan heading refuses, and the message names both lines. A Phase plan heading is any ATX level from 1 to 6, setext or `<hN>` whose text, with markup, `&nbsp;`/`&#32;`, NBSP, ZWSP and a quote or list marker dropped, starts "phase plan" followed by a non-letter.
- **What is hidden.** Fenced code and block comments (a line opening `<!--`, up to `-->`) hide headings. A `## ` inside one neither ends the section nor counts.
- **Inside the section, in order:**
  - Blank lines.
  - A header: a well-formed row whose last cell is `Status`.
  - A separator with the header's cell count.
  - Rows, each well-formed (starts and ends with `|`, no `\|`) with the header's cell count. The table ends at a blank line, a `###`+ heading, or the end of the section.
  - After the table, prose with no `|`, no fence, and no HTML tag outside a comment.
  - Anything else refuses, with exit 10, naming the line and what to write.
- **Mid-line CR.** A CR inside a line anywhere in the file refuses.
- **Keys.** Each row is a phase keyed by its first cell, with blanks dropped. There is no key filter, so `P1` is read. At done, a key that is not letters, digits, `.`, `-` or `_` is refused by name, because keys name gate-logs files and are word-split. Outside done, such a done row reads as open.
- **Done.** The Status cell, trimmed and in any case, is `done` alone or followed by a blank or `(`. A cell that starts "done" any other way (`Done-ish`) is refused as unclassifiable. Every other cell is open, and `receipt_all_done` refuses it at done (exit 9).
- **Mid-run.** The row modes never refuse. A malformed row simply stops counting as a phase until done refuses it.

## Per-finding disposition

| ID | Disposition | RED evidence | Test |
|---|---|---|---|
| P3R4-1 HIGH | FIXED by the allow-list (cell count = header's, no `\|`, ends in `\|`, header's last cell Status) | `fix-phase-3-iter-4/red-p3r4-1-2-unit.log`: old `cp_unread` empty for the extra-cell and `\|` rows, done cells read `1\|done (abc1234) · no PR`, PR #7 never read | 41 `ur 13` loop (extra cell, `\|`, no trailing pipe, short row, pending row with a done cell past Status), header-not-Status case |
| P3R4-2 HIGH | FIXED: a non-blank line in the table that is no row refuses, and so does `\|`, a fence or HTML after it | same log, case 3 (pipe-less row: cp_unread empty) | 41 `ur 13` (pipe-less, `&#124;`, `<table>` rows), `ur 14` loop (row, second table, note with a pipe, HTML table and a fence after a blank line), `### detail` then `\| P1 \|` |
| P3R4-3 | FIXED in part: a `## ` in a comment or fence no longer ends the section; HTML, fences and a lone CR are refused; a plan only inside a comment has no section, so it gets the "no done row" refusal. Residual: an HTML block other than a comment (`<div>`) outside the section is not modelled | — | 41 `ur 17` (comment), lone-CR case, `ur 14` fence/HTML |
| P3R4-4 | FIXED in part: markup, entities, NBSP, ZWSP, `<hN>`, quote and list markers. Residual: homoglyph letters, two-line setext text | — | 41 heading loop (`## **Phase plan**`, `> ## Phase plan`, `<h2>`); NBSP in awk-portability fixture f6 |
| P3R4-5 | FIXED: refusals state the obligation, and the template and README are reworded; the 51 pin moved; the "no other '\|' line" message is gone | — | 51 pins |
| P3R4-6 | FIXED in part: `#phase plan`, `#######`, `## Phase planning notes` and a heading in a fence no longer count, and the message names both lines. KEPT: `### Phase plan changes` and `# phase plan (cont.)` still count. A continuation table under such a heading would be an unread plan, so I chose fail-closed (41 pins `(cont.)`) | — | 41 `ok` pass case, heading loop |
| P3R4-7 | FIXED: only the runner's own usage forms (`lib/usage.sh`), anchored at the end, are stripped | `red-step2-41.log`: `Status cell 'PR #8 · usage see PR 7': exit 0, want 10` | 41 sp loop |
| P3R4-8 | FIXED: a done Status cell with non-ASCII (other than `·`), `<` or `[` is refused | — | 41 sp loop (fullwidth, Arabic-Indic, comment, reference link) |
| P3R4-9 | FIXED in text: README 114-115 and 136 and SKILL step 4 use the brief-based condition; 70 pin moved | — | 70 |
| P3R4-10 | FIXED in text: the brief §5 heading says a phase that opens no PR says `no PR` in its Done when; SKILL points there. No new column | — | 70 pin |
| P3R4-11 | FIXED: the absent refusal says "adding, removing, moving or editing a workflow file" | — | 41 grep |
| P3R4-12 | FIXED: one scanner. cp_rows, cp_phases, cp_done_rows, cp_open_rows, cp_done_cells, cp_unread, cp_row, cp_row_sha and cp_mark_usage (by line number) all go through it | — | 41, 51, 10, 21, 32, 40, 60, 61 green |
| P3R4-13 | OUT OF SCOPE: ci_wait's run listing is pre-existing and was found by code reading only. Filtering by `headBranch` changes which runs count, so it is the owner's call | | |
| P3R4-14 | FIXED: allow-list adopted under the manager's brief (owner direction) | | |
| P3R4-15 | OUT OF SCOPE: pre-existing (P3R3-14); tying a row's sha to the PR is the owner's call | | |
| P3R4-16 | OUT OF SCOPE for the cross-repo part: the template offers `/pull/<n>`, so dropping it or binding it to the remote changes a documented form (owner). PT-13 part FIXED: the URL pattern is anchored to `host/owner/repo/pull/N` | — | 41 `https://h/o/r?n=PR_7&x=/pull/8` |

### LOW
Fixed or moot:
- P3R4-17: the sha slot is hex only (41 `sx`).
- P3R4-18: `Done-ish` refused.
- P3R4-19: a short row refused.
- P3R4-20: MOOT; comment content is no longer read.
- P3R4-22: in part; the ci.sh "neither" message now says "each PR the phase opened" (spec 97 still says "own PR").
- P3R4-23: MOOT; the header digit and done rules are gone.
- P3R4-26: README gives a remedy for a second heading.
- P3R4-27: in part. u5 is MOOT; cases added for a sub-heading then a bad row and for header and separator rules.
- P3R4-31: the old `ok` layout is now refused.
- P3R4-32: `ci_plan` runs before `receipt_all_done`.
- P3R4-37: done cells are read with their exit status checked.
- P3R4-38: the line number replaces the key regex.
- P3R4-43: POSIX awk.
- P3R4-45: the grep is aligned.

Open, each with its reason:
- P3R4-21: owner-facing wording.
- P3R4-24: template examples.
- P3R4-25: the brief step 4 parenthetical.
- P3R4-28: whitelist asserts by prefix only.
- P3R4-29: NUL test (not re-run under mawk).
- P3R4-30: log grep (tail).
- P3R4-33: the absent instruction is aligned in part.
- P3R4-34: control characters in run.log (pre-existing).
- P3R4-35: `head_sha` validation.
- P3R4-36: the record is child-writable (owner).
- P3R4-39: a `#fragment` URL is still refused (fail-closed).
- P3R4-40: CR-only status read.
- P3R4-41: backticked sha (fail-closed).
- P3R4-42 and P3R4-44: notes, no action.

## Behaviour changes for the reviewer (instruction-text ledger)

- `## Phase Plan` in any case is now the section; it was refused before. Test `hd` was flipped.
- Rows keyed `P1` or tab-led after the pipe are now read, where they used to be refused unread. Their PRs gate done.
- Narrower than "free prose": any `|` after the table refuses (a row after a blank line, a second table), and so does text between the heading and the table.
- templates/checkpoint.md row rule: old "...its first cell (the key) starting with a digit...refuses...any table line in that section that is not the header, the separator or such a row". New: "One `## Phase plan` heading. Under it, first, one table: ... Notes go under the table after a blank line, as plain text. At done the runner refuses (exit 10) a Phase plan that is not written this way, naming the line."
- templates/brief.md §5 heading: one clause added. SKILL step 4: one clause changed.

## Files changed

lib/checkpoint.sh, lib/ci.sh, lib/chain.sh, tests/41-ci-wait.sh, tests/51-templates.sh, tests/70-docs.sh, templates/checkpoint.md, templates/brief.md, README.md, docs/spec.md, skills/blast-off/SKILL.md.

**Removed as dead:**
- The sed range reader and its digit filter.
- The `cp_plan_rows` awk.
- The deny-list `cp_unread` awk (heading regex, `#`-header guard, CR-row guard).
- The separate `cp_row`/`cp_row_sha` awks.
- `cp_mark_usage`'s key-regex sed address.
- `ci_check`'s cp_unread call and its mechanism message.

## Last full run

- `fix-phase-3-iter-4/full-run-1.log` (2026-11-16T12:34:49Z to 12:38:25Z, `BLAST_OFF_TEST_ONLY` unset, `pgrep -af '[t]ests/run'` empty before): `GATE: PASS passed=18 failed=0 shellcheck=ok`. It ran after the last tracked edit; only this baton changed after it.
- ExecStart after the run: `ExecStart=/home/alex/blast-off/.worktrees/blast-off-build/bin/blast-off run %f` (OK, untouched).
- Temp dirs I created: `/tmp/p3f4-red.*` and `/tmp/p3f4-awk.*` (left in place); none deleted.

## References

- Findings: `baton-runner/br-1115-issues/review-phase-3-iter-4.md`, `baton-phase-3-review-4.md`
- Rulings: `owner-rulings-phase-3.md`; direction: `failure-phase-3.md`
- Logs: `baton-runner/br-1115-issues/fix-phase-3-iter-4/` (red-*, green-*, step1-*, step2-*, awk-portability*)
- Code: `lib/checkpoint.sh` `cp_scan`; `lib/ci.sh` `ci_plan`, `ci_check`; `lib/chain.sh:160`

## Next steps

1. Manager: review `git diff`, commit, and run review round 5. It should press `cp_scan` with renderer-divergent inputs outside the section and confirm there are no false refusals of real jobs.
2. Owner: P3R4-13, -15, -16 (cross-repo `/pull/N`), and question 3.
