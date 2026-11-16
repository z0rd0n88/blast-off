---
source: runner
scope: br-1115-issues
parent_session: ""
---
# Pass-Baton: phase 3 review 5 (issue 26): ISSUES, the allow-list's hidden-text model still lets a rendered red PR go unread

**Date:** 2026-11-16
**Scope:** br-1115-issues
**Branch:** feat/br-1115-issues/phase-3
**Worktree:** /home/alex/blast-off/.claude/worktrees/pending-items-53932d
**HEAD:** 15960ad fix(phase-3): one allow-list reader for the Phase plan section (P3R4-1, P3R4-2)
**Diff reviewed:** `git diff feat/br-1115-issues/phase-2...HEAD` (product paths only)

## VERDICT: ISSUES

- **Gate:** PASS. `GATE: PASS passed=18 failed=0 shellcheck=ok`, exit 0. It ran once, with nothing else running and `BLAST_OFF_TEST_ONLY` unset. Log: `baton-runner/br-1115-issues/gate-phase-3-iter-5/tests-run.log`.
- **ExecStart after the gate:** `ExecStart=/home/alex/blast-off/.worktrees/blast-off-build/bin/blast-off run %f`. It is intact.
- **Review:** `baton-runner/br-1115-issues/review-phase-3-iter-5.md`, by zord-multi-agent-review in one-shot spec mode. Five reviewers (architect-reviewer, critical-thinking, silent-failure-hunter, security-reviewer, penetration-tester) each ran as a general-purpose agent that read its parked definition read-only from `~/.claude/agents-parked/`. The synthesis and report audit ran as forks of the orchestrator. ID mapping: report `R5-n` = baton `P3R5-n`; P3R5-30 to P3R5-32 are mine. No reviewer ran a test scenario. No `--adversarial`, so the findings are unrefuted, but every HIGH was reproduced by at least one reviewer, and P3R5-1 and P3R5-5 were reproduced end to end by me (below).
- **What blocks CLEAN:** 8 HIGH (P3R5-1 to P3R5-8). Acceptance criterion 3 ("no Phase plan line can escape the gate by its format") is not met.
- **Counts:** CRITICAL 0, HIGH 8, MEDIUM 6, LOW 18. That is the 29 report findings plus 3 of mine (P3R5-30, P3R5-31, and P3R5-32 from the mutation check).

### My end-to-end reproduction (the real `bin/blast-off run`, through scenario 41's harness, on a /tmp copy)
I inserted probes after tests/41-ci-wait.sh:236 in `/tmp/p3r5-probe.PVDD/repo` and ran `BLAST_OFF_TEST_ONLY=41-ci-wait tests/run` once. Output is in `/tmp/p3r5-probe.PVDD/probe.out`. Row 0 has PR #8 green; the hidden row has PR #7, and its record is red:
- `<!-->` after the table's blank line, then a second table holding the red row: **rc=0**, `PRs read: 8`, `job done`.
- `<!--->`, then `## Phase plan` and a red table: **rc=0**, `PRs read: 8`, `job done`.
- `## Phase&#160;plan` and a red table: **rc=0**, `PRs read: 8`, `job done`.
- `done (abc1234) · [PR #8](https://github.com/o/r/pull/8)` (PR #8 green): **rc=10**, "holds a character the runner does not read there".
- The note ``Phase 0 closed with `done (<sha>)` per the rule.`` under the table: **rc=10**, "follows the Phase plan table".
- The bare URL `https://github.com/o/r/pull/8`: rc=0, as expected.

My own cp_scan fixtures (`.../scratchpad/fx/`, run by `.../scratchpad/run.sh`) give identical output under gawk 5.2.1 and mawk 1.3.4. busybox is not installed, and `/usr/bin/nawk` is gawk, so busybox awk is untested.

## Findings, MEDIUM and above

| ID | Severity | file:line | Failure path | Suggested fix |
|---|---|---|---|---|
| P3R5-1 | HIGH | lib/checkpoint.sh:65, :63, :89 | `<!-->` or `<!--->` opens a comment that awk never closes; CommonMark/HTML5 close it on the same line. A second table (or a second `## Phase plan`) holding a red PR renders inside the section but is never read. Done exits 0 (reproduced above). The template's own rules comment closes awk's false comment at templates/checkpoint.md:44. | Look for `-->` on the whole opener line, or at done refuse every `<!--` except the verbatim rules comment. Pin both forms in 41 `ur 14`. |
| P3R5-2 | HIGH | lib/checkpoint.sh:63, :65, :73, :75 | Text after `-->` on a comment line is read as Markdown, so `<!-- note -->##` ends the section for awk. CommonMark renders the whole line as raw HTML, so the red table that follows stays in the section. Done exits 0. | Treat comment lines as wholly hidden and refuse text after `-->` at done. End the section only at a raw left-margin `#`/`##` line outside any fence or comment. |
| P3R5-3 | HIGH | lib/checkpoint.sh:64, :28-33, :73, :89 | A fence on a list-item line (`- ```` / `  ## notes` / `  ````) is unseen by awk, so the indented `## notes` ends the section. markdown-it renders it as code, and the next left-margin red table is still in the section. Done exits 0. It needs no HTML and no encoding. | Detect fences on the container-stripped line and refuse fence markers after the table, or apply P3R5-2's left-margin section end. |
| P3R5-4 | HIGH | lib/checkpoint.sh:62, :64, :68-71 | The fence model differs from CommonMark in both directions: a backtick info string (```` ```x`y ````) is a fence to awk only; a short closer closes early; an unclosed fence in a list item; ```` ``` ```` inside `<div>`. Each hides a rendered red Phase plan, or makes a green decoy the one read. Done exits 0. | Model fences per CommonMark (character, length, info string, container end, open at EOF refused), or refuse fence lines at done (this changes the 41 `ok` case, :269-274). |
| P3R5-5 | HIGH | lib/checkpoint.sh:34-38, :28-33, :67-69; docs/spec.md:97 | The second-heading counter misses headings that render "Phase plan": entity letters or spaces (`&#80;`, `&#160;`, `&ensp;`...), Unicode spaces, BOM, form feed, `## [Phase plan](#x)`, multi-line or nested `<h2>`, setext in a quote or list item, 4-space ATX in a list item. A second rendered Phase plan section with a red PR is not read. Done exits 0 (`&#160;` reproduced above). Round 4 rated this class MEDIUM (P3R4-4). It is HIGH here because the ASCII entity and link forms are outside the accepted homoglyph residual, and the code and spec claim the coverage. | Fail closed: at done, refuse any heading-like line (in any container, setext, or `<hN>` anywhere) whose text holds `&`, `[`, `<` or non-ASCII. Correct checkpoint.sh:22-23 and spec.md:97. |
| P3R5-6 | HIGH | lib/checkpoint.sh:63, :65, :66, :89 | `<!-- x --!>` then a raw `<table>` row with a red PR, then `-->`. awk and CommonMark see one comment, but the HTML5 tokenizer ends it at `--!>`, so a browser shows the table. Done exits 0. GitHub's rendering is unchecked. | Treat `--!>` as a comment end, or refuse any comment in or after the section whose body holds `--!>`, `<`+letter or a pipe. |
| P3R5-7 | HIGH | lib/checkpoint.sh:66, :89 | The inline `<!-- … -->` strip removes `x -- <table>…PR #7…</table>`, which CommonMark 0.29/0.30 (GitHub cmark-gfm) does not parse as a comment, so the HTML table renders (markdown-it-py; GitHub cmark-gfm not checked). Done exits 0. This depends on the renderer: 0.31.2 hides it. | Do not strip inline comments in or after the section; after the table, refuse `<[A-Za-z/!?]` on the raw line unless it is a line-start block comment. |
| P3R5-8 | HIGH | templates/checkpoint.md:34-35; lib/ci.sh:86-87, :89-91 | FALSE REFUSAL. The template invites "`PR #<n>` (or its /pull/<n> link)". The forms `[PR #9](…/pull/9)`, `<…/pull/12>` and `…/pull/8#issuecomment-1` are refused (exit 10) at the end of the job (reproduced above). The refusal fails closed and its message says what to write. By impact alone it would be MEDIUM. It is HIGH by this run's rule because the template text leads to it. | Reword the template and brief step to "the bare `https://…/pull/<n>` URL (no brackets, `<>` or `#fragment`)", or accept a Markdown link or autolink whose numbers agree. |
| P3R5-9 | MEDIUM | lib/checkpoint.sh:40, :87; templates/checkpoint.md:24-28 | A GFM-correct `\|` in any cell (e.g. a Done-when holding ``tests/run 2>&1 \| tail -1``) is refused with "no phase row … with the header's cells", which misleads. | Name `\|` as banned in the template and the message, or refuse it only in the key and Status cells. |
| P3R5-10 | MEDIUM | lib/checkpoint.sh:89-90; templates/checkpoint.md:26-27 | FALSE REFUSAL, possible but not likely: the template asks for notes "as plain text" and nothing in the templates shows a pipe or `<...>` in a note, whereas P3R5-8's template line names a link form outright. The template invites "notes … as plain text", but a note with a `\|`, a code span with a pipe, or a `<placeholder>` (`done (<sha>)`, `<job-dir>`), an autolink or `x<y` refuses done. The message says "no table, code block or HTML", which these are not (reproduced above). | Template and message: "plain text with no `\|` and no `<`", or drop code spans before the test. |
| P3R5-11 | MEDIUM | lib/checkpoint.sh:41, :78 | `\| # \| Phase \| Status \| Status \|`: only the last column is read, so a PR in the other column labelled Status goes unread and done exits 0 (PT reproduced it). | Refuse a header where any non-last cell trims to `status`. |
| P3R5-12 | MEDIUM | lib/checkpoint.sh:64; lib/ci.sh:100; lib/chain.sh:100-108, :155-157 | A ```` ``` ````-led inline-code line before the plan (e.g. in Next action) hides the whole plan. Mid-run the cap goes hard and the receipts see no rows; at done the refusal says "no done row" and names no line. It fails closed but misleads. | The P3R5-4 fix; and have `ci_plan` name a hidden level-2 Phase plan heading. |
| P3R5-13 | MEDIUM | lib/checkpoint.sh:84-87, :21; lib/chain.sh:100, :155, :170; lib/jev.sh:52; lib/preflight.sh:18, :81 | Mid-run, one malformed row drops it and every later row. The soft cap, receipt_check, cp_mark_usage, jev and preflight then see nothing, and nothing is logged until done. | Log a non-empty `cp_unread` at each child's end, without refusing. |
| P3R5-14 | MEDIUM | lib/checkpoint.sh:58-75, :89 | Architecture: the allow-list is complete inside the table, but the section bounds, the after-table zone and the heading counter rest on a partial CommonMark model in awk. Everything awk calls "hidden" is accepted unread, which is a deny-list. P3R5-1 to P3R5-7 all sit in that gap. | Shrink the model so anything it does not understand refuses. A prototype is at `/tmp/p3r5-architect-reviewer.SUSW9W/proto/checkpoint.sh`, checked against its own fixtures only. |

## LOW findings
Each line gives the ID, the location, the problem, and the fix.

- **P3R5-15** (lib/ci.sh:89-91): a PR written after the runner's ` · usage` is refused with a misleading message. Fix: say "PRs go before ` · usage`".
- **P3R5-16** (lib/checkpoint.sh:50; lib/receipt.sh:50-51; docs/spec.md:228): with duplicate keys, receipt_check checks only the first row's sha. Fix: refuse a repeated key in unread mode.
- **P3R5-17** (lib/checkpoint.sh:91; lib/preflight.sh:77): awk takes a source path shaped `name=value` as an assignment. Fix: pass `./$f` or `< "$f"`.
- **P3R5-18** (lib/chain.sh:160; lib/ci.sh:62, :79; lib/receipt.sh:69): the done gates re-read checkpoint.md 3 to 4 times with no snapshot. Fix: copy the file once at done.
- **P3R5-19** (lib/ci.sh:89-91): a backticked sha is refused (P3R4-41 is still open).
- **P3R5-20** (lib/checkpoint.sh:47): `**done**` gives exit 9 with wrong advice. Fix: refuse it via `bad()`.
- **P3R5-21** (lib/checkpoint.sh:52 vs lib/ci.sh:89): an upper-case hex sha passes ci_check but reads as no commit (exit 9).
- **P3R5-22** (README.md:145): it still says "digit row keys", but `P1` keys are now read.
- **P3R5-23** (docs/spec.md:96, :97, :228; lib/checkpoint.sh:22-23): docs and comment overclaim heading normalisation, "own PR", "starts done", and "duplicate keys each read".
- **P3R5-24** (lib/checkpoint.sh:59, :68-71): the CR and second-heading refusals cover the whole file, and the template does not say so.
- **P3R5-25** (lib/checkpoint.sh:129): `cp_mark_usage` returns 0 silently on a read failure.
- **P3R5-26** (lib/checkpoint.sh:89): an entity pseudo-row (`&#124;`, `&vert;`) after the table passes as prose. That is prose under ruling 1, so the refusal is optional.
- **P3R5-27** (lib/checkpoint.sh:37): `## Phase plans` and `## Phase plan_v2` are not counted as second headings.
- **P3R5-28** (lib/ci.sh:92-94): a PR in another column beside `no PR` passes, as ruled. Fix (optional): refuse it.
- **P3R5-29** (tests/41-ci-wait.sh:217-274): no test pins the P3R5-1 to P3R5-7 routes. Fix: add each reproduced fixture as an exit-10 case, plus passing controls.
- **P3R5-30** (lib/checkpoint.sh:37, :71; mine): `### Phase plan notes` is refused as a second heading. This is the deliberate P3R4-6 residual. The template says "one `## Phase plan` heading" but does not say that a sub-heading containing those words refuses, so add that clause.
- **P3R5-31** (lib/checkpoint.sh:31; mine): a UTF-8 BOM at the start of the file hides a `## Phase plan` on line 1. A BOM inside a heading on any line is part of P3R5-5. Done then refuses with "no done row" and names no line. It fails closed and no template leads to it.

## Round-4 status
- **P3R4-1 (HIGH): CLOSED.** In-table routes now refuse: extra cell, `\|`, no trailing pipe, short row, a done cell past Status. Pinned by 41 `ur 13`, confirmed by four reviewers (SR, PT, SFH, AR).
- **P3R4-2 (HIGH): CLOSED for the reported routes, but the class is REOPENED.** A pipe-less row, a second table, a pipe in a note, an HTML table or a fence after the table all refuse (41 `ur 14`). The same outcome (a rendered row unread, exit 0) comes back through comment, fence and heading divergence: P3R5-1 to P3R5-7.
- **P3R4-3: PARTIAL.** A `## ` in a well-formed comment is handled, but P3R5-1, -2, -3, -6 and -7 are the same class.
- **P3R4-4: PARTIAL.** See P3R5-5.
- **P3R4-5: FIXED.** The texts state the obligation, with some drift left in P3R5-23.
- **P3R4-6: PARTIAL by choice.** See P3R5-27 and P3R5-30.
- **P3R4-7: FIXED** (41 sp loop).
- **P3R4-8: FIXED**, but it causes the P3R5-8 false refusal.
- **P3R4-9: FIXED** in text (70 pin).
- **P3R4-10: FIXED** in text (brief §5 clause).
- **P3R4-11: FIXED** (41 grep).
- **P3R4-12: FIXED.** Every Phase plan reader goes through `cp_scan`. The wrappers are at chain.sh:100/155/170/196, jev.sh:52-54, preflight.sh:18/77/81, receipt.sh:50-51/69 and ci.sh:62/79. The other checkpoint reads (`cp_status`, `cp_names`, usage) read no plan. My grep and all five reviewers agree.
- **P3R4-13: OPEN** (owner): run listing by head sha.
- **P3R4-14: FIXED in form.** The allow-list was adopted, but P3R5-14 shows the hidden-text model is still a deny-list.
- **P3R4-15: OPEN** (owner).
- **P3R4-16: OPEN** (owner) for the cross-repo `/pull/N` part. The PT-13 anchoring is fixed.

## Verdicts on the three deliberate behaviour changes
1. **`## Phase Plan` is matched in any case: ACCEPT.** It only widens what is read, and no template-following checkpoint can be refused by it. Test `hd` (41:163) pins it.
2. **`P1`-style keys are now read: ACCEPT.** This also only widens what is read. Template keys (0, 1, 2a) are unaffected, and a done row with an odd key is refused by name. README.md:145 still says "digit row keys" (P3R5-22).
3. **Any `|` or row after the table refuses: ACCEPT the rule, FIX the wording.** It fails closed against second tables. A template-following child reaches it only through notes, which the template invites as "plain text". A note with a pipe, a code span with a pipe, or a `<placeholder>` is refused with a message that does not describe those (P3R5-10, MEDIUM). The template's own rules comment passes, because the comment is hidden and holds no `|`.

## Acceptance criteria and their tests
I mutated /tmp copies and ran one scenario at a time (`/tmp/p3r5-mut.2eXs/mut.sh`, results in `/tmp/p3r5-mut.2eXs/result`).

Logs are `/tmp/p3r5-mut.2eXs/<mutant>.log`. Seven mutants ran. Six were killed (the scenario FAILED); one survived.

- **Criterion 1 (no runs, workflow file at head, refused): MET, test real.**
  - Test: tests/41-ci-wait.sh:328.
  - Mutant `ac1-wf-allows` (lib/ci.sh:112 `[ -z "$wf" ] ||` changed to `true ||`): KILLED. 41 FAILED with "exit 0, want 10 … has a workflow file (.github/workflows/release.yaml)".
- **Criterion 2 (no runs, no workflow file at head, allowed and logged): MET, test real.**
  - Test: tests/41-ci-wait.sh:319.
  - Mutant `ac2-nowf-refuses` (`[ -z "$wf" ]` changed to `false`): KILLED. 41 FAILED with "exit 10, want 0".
- **Criterion 3: NOT MET.**
  - **Status-cell part.** The neither-refusal is pinned at 41:174. Mutant `ac3-neither-ok` (lib/ci.sh:96 `[ -n "$n" ] ||` changed to `true ||`): KILLED.
  - **Prose is never read.** No mutant covers this part; it is pinned by 41:159-161, 41:178-187 and 41:188-193.
  - **Allow-list.** Pinned by 41:216-274. Mutant `ac3-allowlist-off` (`bad()` made a no-op): KILLED, first at the indented-row case.
  - **Why it is not met.** "No Phase plan line can escape the gate by its format" fails on P3R5-1 to P3R5-7, and no test pins those routes (P3R5-29).
- **Criterion 4 (workflow_dispatch counts neither way): MET, test real.**
  - Tests: 41:77 (a green dispatch is not a pass) and 41:79 (red dispatches are not a failure).
  - Mutant `ac4-dispatch-counts` (lib/ci.sh:54 filter changed to `select(true)`): KILLED with "green dispatch run counted".
- **Criterion 5 (texts state the rules): MET IN PART.**
  - Template: mutant `ac5-template-nopr` (templates/checkpoint.md "or says `no PR`" changed to "or says nothing"): KILLED by 51 ("checkpoint.md lacks: Every closed row's Status cell names every PR …").
  - README: mutant `ac5-readme-nopr` (README.md:114 `` `done (<sha>) · no PR` `` changed to `` `done (<sha>)` ``): **SURVIVED**. 70-docs still PASSED. tests/70-docs.sh:48 pins the README's refusal sentence, but not the Status-cell form the README teaches. This is LOW P3R5-32 below.
  - The texts also drift on details (P3R5-22, P3R5-23) and teach forms that are refused (P3R5-8, P3R5-10).

**P3R5-32 (LOW, tests/70-docs.sh:47-50; README.md:114):** the README's done-cell example forms are not pinned, so dropping `· no PR` from them passes 70. Fix: add `` `done (<sha>) · no PR` `` and `` `done (<sha>) · PR #<pr>` `` to the line-48 pin list.

After the mutants, `git status --porcelain` in the worktree shows only untracked `baton-runner/` paths, and ExecStart is unchanged.

## New dependencies and reliance (for the owner's visibility)
- **No new package or tool.**
- **POSIX awk for the gate.** gawk and mawk agree on every fixture; busybox awk is not installed and untested.
- **GNU sed `-E` with the `I` flag** in ci_check, as before.
- **A local git object for the PR head (ruling 2).** `git ls-tree` runs at the PR record's `head_sha` in the workdir's repo, and an unfetched head fails closed.
- **`gh pr view` at done** (`ci_head`), as before.
- **Design reliance (new):** the gate is only as strong as awk's model of which Markdown text is hidden matching the renderer's. No reference renderer is named in docs/spec.md (see P3R5-14).

## Deviations
- The baton-pass skill files notes under `baton-pass/` and regenerates `INDEX.md`. The containment contract allows writes only under `baton-runner/br-1115-issues/`, so this baton is at the contract path and no index was regenerated.
- The review report path is not git-ignored, and it names unfixed fail-open routes. Whether to commit it is the manager's call.
- Temp dirs created in this run, none deleted:
  - `/tmp/p3r5-probe.PVDD`
  - `/tmp/p3r5-mut.2eXs`
  - the reviewers' `/tmp/p3r5-*`

## Next steps
1. **Fix unit:** close P3R5-1 to P3R5-7 as one class, failing closed:
   - refuse at done every `<!--` except the template's verbatim rules comment;
   - refuse every fence marker in or after the section;
   - end the section only at a left-margin `#`/`##` line;
   - refuse heading-like lines holding `&`, `[`, `<` or non-ASCII;
   - pin each reproduced fixture (`/tmp/p3r5-*` and `.../scratchpad/fx/a01-a08`) in tests/41-ci-wait.sh.
2. **Fix unit:** reword templates/checkpoint.md:26-27 and :34-35 and templates/brief.md:147 (P3R5-8, P3R5-10), and README.md:145 (P3R5-22).
3. **Owner:** the open questions in `review-phase-3-iter-5.md`, above all whether fences after the section may be refused (this changes 41:269-274), and P3R4-13, -15 and -16.

## References
- Report: `baton-runner/br-1115-issues/review-phase-3-iter-5.md`
- Gate: `baton-runner/br-1115-issues/gate-phase-3-iter-5/tests-run.log`
- Rulings: `owner-rulings-phase-3.md`; direction: `failure-phase-3.md`; previous fix: `baton-phase-3-fix-4.md`
- Issue: z0rd0n88/blast-off#26
- Code: `lib/checkpoint.sh` `cp_scan` (:25-92), `lib/ci.sh` `ci_plan` (:60-64) and `ci_check` (:77-118)
