---
source: runner
scope: br-1115-issues
parent_session: ""
---
# Pass-Baton: phase 3 fix 5 (issue 26): ruling 3 applied; one PR form; every MEDIUM dispositioned

**Date:** 2026-11-16
**Scope:** br-1115-issues
**Branch:** feat/br-1115-issues/phase-3
**Worktree:** /home/alex/blast-off/.claude/worktrees/pending-items-53932d
**HEAD:** 571ed81 chore(phase-3): owner ruling 3 (threat model) recorded; run resumed (nothing committed by this unit; the manager owns git)

## Where things stand

All work is uncommitted in the working tree. Steps 1-5 of the brief are done. The last full run is recorded at the end. New dependency: none. Logs are in `baton-runner/br-1115-issues/fix-phase-3-iter-5/`: `red-*` (before), `green-*` (after), `red-unit.log`/`green-unit.log` (cp_scan fixtures under gawk and mawk), `full-run-*.log`.

## Step 1, P3R5-8: one rule, `PR #<n>`

**Chosen:** the template stops inviting links. It now says each PR is written as `PR #<n>` ("that form, not a link or URL") or `no PR`.
- **Why:** it is the simplest rule and leaves the fewest ways to get it wrong. It also matches owner ruling 1 as worded ("`PR #N` or an explicit `no PR`").
- **Why not accept links:** the reader would have to parse `[..](..)` and `<..>`, relax the P3R4-8 `[`/`<` guard, and tie each link's repo to the workdir remote (P3R4-16, an owner question).
- **Reader unchanged:**
  - The bare `/pull/N` URL is still read, but no longer taught, so older checkpoints still pass.
  - The lib/ci.sh comment and spec.md:97 say this.
  - Cross-repo `/pull/N` stays open as owner question P3R4-16.
- **Tests, end to end through `done` (41):**
  - The forms the template names (`PR #8`, `no PR`) pass: cases `tp` (the template, closed), `nc` and others.
  - Forms it does not name are refused (exit 10), and the message tells the child to write "each of the phase's PRs as `PR #<n>`": `[PR #8](https://github.com/o/r/pull/8)`, `<https://github.com/o/r/pull/8>` and `https://github.com/o/r/pull/8#issuecomment-1`.
- **RED:** the 41 link cases were already refused before the change (green before and after), so they are not RED. The RED is the template pin: `red-pins.log` shows `(that form, not a link or URL)` absent at HEAD (0).
- **Why the reader keeps the bare URL although the template no longer names it:** in-flight jobs carry the old rules comment ("or its /pull/<n> link") in their own checkpoint.md. Refusing the URL would refuse those jobs at their end. The cross-repo risk of a bare URL is P3R4-16, an owner question.

## Per-finding disposition (32 findings)

| ID | Disposition | RED evidence | Test |
|---|---|---|---|
| P3R5-1 | OUT OF SCOPE, ruling 3 (`<!-->` and `<!--->`: crafted, renderer-divergent comment) | — | — |
| P3R5-2 | OUT OF SCOPE, ruling 3 (text after `-->`: crafted comment line) | — | — |
| P3R5-3 | OUT OF SCOPE, ruling 3 (a fence in a list item hiding an indented `##`: crafted) | — | — |
| P3R5-4 | OUT OF SCOPE, ruling 3 (fence-model divergence: crafted). The one honest-reachable part, a backtick after a backtick opener, is fixed under P3R5-12. | — | — |
| P3R5-5 | OUT OF SCOPE, ruling 3 (entity, link, Unicode and nested-HTML headings). The code comment and spec no longer claim entities or odd spaces (see P3R5-23). | — | — |
| P3R5-6 | OUT OF SCOPE, ruling 3 (`--!>`: crafted HTML5 comment end) | — | — |
| P3R5-7 | OUT OF SCOPE, ruling 3 (an inline comment with `--`: crafted, renderer-dependent) | — | — |
| P3R5-8 HIGH | FIXED: the template names `PR #<n>` only (see Step 1) | `red-pins.log` (template sentence absent at HEAD) | 41 sp link loop, 41 `tp`, 51 pin |
| P3R5-9 MEDIUM | FIXED: the template says "No cell holds a pipe, written `\|` or `\\|`." and the refusal names it ("holds `\|`, which no Phase plan table cell may hold"). The ban stands: it is the owner's allow-list. | `red-41-ci-wait.log`: exit 10 with the old "no phase row" message, want 'holds `\|`' | 41 "escaped pipe in a cell (P3R5-9)" |
| P3R5-10 MEDIUM | FIXED: raw HTML after the table is no longer refused (see Step 5). The template and the message say "plain text with no `\|` and no code fence". A note like ``Closed as `done (<sha>)` after `blast-off ci-wait <job-dir> 8`; x<y.`` now passes. | `red-unit.log` p10: refused "follows the Phase plan table" | 41 `ok` case (the note added) |
| P3R5-11 MEDIUM | FIXED: a header with more than one Status cell is refused, naming the line. This is not ruling 3: a confused child can write it with no renderer divergence. | `red-unit.log` p11: unread empty, cells `no PR` only (PR #7 unread, exit 0) | 41 "two Status cells (P3R5-11)" |
| P3R5-12 MEDIUM | FIXED: a three-backtick opener followed later on the line by a backtick is inline code, not a fence (CommonMark), so the plan under it is read. A four-backtick fence still opens. | `red-unit.log` p12: cells empty (plan vanished) | 41 "inline code with three backticks before the plan (P3R5-12)"; 41 `ok` fence pair still passes |
| P3R5-13 MEDIUM | FIXED: each chain pass, unless status is done, logs a non-empty `cp_unread` ("checkpoint.md line N '…' …; the Phase plan rows from there on are not read, and done is refused, until it is fixed"), without refusing. lib/chain.sh loop head. | RED not captured as a run: 41 stopped at the P3R5-9 case first. `red-pins.log`: HEAD's chain.sh holds no `cp_unread` (0) | 41 "mid-run unread line not logged" (status blocked, exit 3) |
| P3R5-14 MEDIUM | OUT OF SCOPE, ruling 3: the gap between awk's hidden-text model and CommonMark matters only for crafted input. The spec and README now state the threat model, which answers the architecture point. | — | — |
| P3R5-15 LOW | OPEN: a PR after the runner's ` · usage` gets a misleading message; it fails closed and the template says usage is the runner's. | | |
| P3R5-16 LOW | OPEN: with duplicate keys receipt_check checks only the first row. ci_check reads both PRs; refusing duplicates changes the 41 `dup` pin. | | |
| P3R5-17 LOW | OPEN: an awk operand shaped `name=value`. It comes from an operator-supplied preflight path, so no child can reach it. | | |
| P3R5-18 LOW | OPEN: no snapshot at done; only a concurrent writer can race it. | | |
| P3R5-19 LOW | OPEN: a backticked sha is refused; it fails closed and the message says what to write. | | |
| P3R5-20 LOW | OPEN: `**done**` gives exit 9 with weak advice; it fails closed. | | |
| P3R5-21 LOW | OPEN: an upper-case sha gives exit 9; it fails closed. | | |
| P3R5-22 LOW | FIXED: README says "row keys (0, 1, 2a)". | `red-70-docs.log`, `red-pins.log` | 70 pin |
| P3R5-23 LOW | FIXED in part: the spec.md:97 claims ("own PR", "read through markup and odd spaces", HTML in notes) and the checkpoint.sh comment are corrected. OPEN: spec :96 "starts `done`" and :228 "duplicate keys each read" (true for ci_check). | | 70 (spec threat-model pins) |
| P3R5-24 LOW | OPEN: the CR refusal covers the whole file, and the template does not say so; a raw CR is rare. | | |
| P3R5-25 LOW | OPEN: `cp_mark_usage` is silent on a read failure; that is cosmetic. | | |
| P3R5-26 LOW | OUT OF SCOPE, ruling 3 (entity pseudo-rows: crafted) | | |
| P3R5-27 LOW | OPEN: `## Phase plans` is not counted; no template leads to it. | | |
| P3R5-28 LOW | OPEN: as ruled (ruling 1). | | |
| P3R5-29 LOW | OUT OF SCOPE, ruling 3: no pins for the P3R5-1 to -7 routes. | | |
| P3R5-30 LOW | FIXED: the template says "no other heading anywhere in this file whose text starts "Phase plan"". The spec says what the reader counts: "Phase plan" alone or followed by a non-letter. | `red-pins.log` | 51 pin |
| P3R5-31 LOW | OPEN: a BOM before the heading fails closed ("no done row"), and no template leads to it. | | |
| P3R5-32 LOW | FIXED: 70 pins the README's `done (<sha>) · PR #<pr>` and `done (<sha>) · no PR`. It is a test-gap fix, so it has no RED. | — | 70 |

## Step 2: the threat model
It is written in docs/spec.md (a paragraph after the exit-code table, which holds exit 10) and in README.md (after the done-rules paragraph that the exit-10 row points to).
- What the gate defends against: a lazy or confused child.
- What it does not defend against: a child crafting Markdown or HTML.
- Why: children run as the owner's user with bypass permissions and could edit the runner.
- The guarantee: a template-following checkpoint is never refused for its format and never slips the gate.

Both texts are pinned in 70 (RED: `red-pins.log`, 0/0 at HEAD). The templates carry none of it.

## Step 5: crafted-input code removed or kept
- **REMOVED: the after-table `<[A-Za-z/!?]` refusal** (lib/checkpoint.sh, `st == 3`). It only defeated raw HTML tables (ruling 3), and it refused honest notes such as `done (<sha>)` and `<job-dir>`. The 41 `ur 14` `<table>`-after-table case is removed with it. A `<table>` row inside the table is still refused, because any non-row line there refuses.
- **KEPT, fail-closed, never refusing a template-following checkpoint:**
  - `pp`'s entity, NBSP and ZWSP mapping.
  - Comment and fence hiding.
  - The Status-cell `[`/`<`/non-ASCII guard (P3R4-8): it also refuses the link forms in Step 1, with the right advice.
  - The CR refusal.

## Files changed
lib/checkpoint.sh, lib/chain.sh, lib/ci.sh (comment only), templates/checkpoint.md, README.md, docs/spec.md, tests/41-ci-wait.sh, tests/51-templates.sh, tests/70-docs.sh. templates/brief.md is unchanged: its step 4 already names only `PR #<n>`.

## Last full run
- `fix-phase-3-iter-5/full-run-2.log` (2026-11-16T13:51:38Z to 13:55:13Z, `BLAST_OFF_TEST_ONLY` unset, no other suite running): `GATE: PASS passed=18 failed=0 shellcheck=ok`, exit 0.
  - It ran after the last tracked edit: the template pipe wording, its 51 pin, and the spec's heading wording.
  - Only this untracked baton changed after it.
  - `full-run-1.log` (13:44-13:48Z) also passed 18/18, before those three edits.
- ExecStart after the run: `ExecStart=/home/alex/blast-off/.worktrees/blast-off-build/bin/blast-off run %f` (OK, untouched).
- Single-scenario greens before it: `green-41-ci-wait.log`, `green-51-templates.log`, `green-70-docs.log` (the 51/70 runs failed only on a shellcheck SC1010 in chain.sh, fixed before 41's rerun).

## References
- Findings: `review-phase-3-iter-5.md`, `baton-phase-3-review-5.md`; rulings `owner-rulings-phase-3.md`; previous fix `baton-phase-3-fix-4.md`
- Code: `lib/checkpoint.sh` `cp_scan`; `lib/chain.sh` loop head (P3R5-13); `lib/ci.sh` `ci_check` comment
- Temp dir I created: `/tmp/p3f5-red.Uwva` (left in place)
- This baton lives at the contract path, not under `baton-pass/`, and no INDEX was regenerated, because containment and the manager's path come first.

## Next steps
1. Manager: review `git diff`, commit, and run the final review round. Point it at honest, template-following checkpoints; ruling 3 excludes crafted input.
2. Owner: P3R4-13, P3R4-15, P3R4-16 (cross-repo bare `/pull/N`, still read).
