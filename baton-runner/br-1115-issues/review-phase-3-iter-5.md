# Multi-Agent Review: phase 3 of br-1115-issues (feat/br-1115-issues/phase-3 vs phase-2, review iter 5)

## Executive Summary
Five reviewers (architect-reviewer, critical-thinking, silent-failure-hunter, security-reviewer, penetration-tester) reviewed `git diff feat/br-1115-issues/phase-2...HEAD` at 15960ad. They looked at the `cp_scan` allow-list reader, the `ci_plan`/`ci_check` done path, and the docs, templates and tests. All five found the same thing: inside the table, row and Status-cell grammar holds and no reader bypasses `cp_scan`. But the reader models which Markdown lines are hidden (comments, fences, heading text) differently from CommonMark. In seven separately reproduced root causes, a rendered done row naming a red PR goes unread and `done` exits 0. One of them needs only `<!-->` inside the single Phase plan section. Acceptance criterion 3 ("no Phase plan line can escape the gate by its format") is therefore not met.

The run found 8 HIGH (7 fail-open, 1 template-led false refusal; the budget cap is 8, so none were demoted), 6 MEDIUM and 15 LOW findings, and no CRITICAL. The 29 findings are R5-1 to R5-29. Recommended action: **block**. Refutation did not run (no `--adversarial`), so every finding is unrefuted and rests only on each reviewer's own reproduction.

Roster ran as general-purpose agents reading parked definitions read-only from ~/.claude/agents-parked/; the synthesizer and report audit ran as forks.

## Critical Findings
None.

## High Findings

**R5-1 (HIGH). `<!-->` and `<!--->` open a comment that awk never closes, while CommonMark and HTML5 close it on the same line. A table in the one Phase plan section goes unread.**
- **Location:** lib/checkpoint.sh:65 (`-->` is searched only after `index(l,"<!--")+4`), :63, :89 (the after-table check reads `v`, which is "" while `cm` is set).
- **Failure path:** a green table, a blank line, `<!-->`, then a second table whose row is `| 1 | b | x | done (abc1234) · PR #7 |`, with a red `ci-pr-7.json`.
  - Real output: `cp_scan unread` is empty and `cells` holds row 0 only.
  - The done path logs `CI at done: PRs read: 8` (or `none`), then `chain_end 0: job done`, exit 0.
  - markdown-it renders both tables under the one `<h2>Phase plan</h2>`.
  - On the real template, the template's own rules comment closes awk's "open" comment at templates/checkpoint.md:44, so no extra closer is needed (CT fixture TA).
  - The same trick hides a second `## Phase plan` outside the section (CT fixture G, AR's `<!--->` variant).
  - The control (the same row inside the table) gives `PR #7 CI red`, exit 10.
  - gawk and mawk agree.
- **Suggested fix:** test for `-->` on the whole line, opener included, so `<!-->` and `<!--->` close at once. Fail-closed alternative: at done, refuse every `<!--` except the template's verbatim rules comment. Pin both forms in tests/41-ci-wait.sh `ur 14`.
- **Raised by:** critical-thinking, security-reviewer, penetration-tester, architect-reviewer, silent-failure-hunter.

**R5-2 (HIGH). Text after `-->` on a comment line is read as Markdown, so a raw `##` there ends the section.**
- **Location:** lib/checkpoint.sh:63 and :65 (`v = substr(l, i + 3)`), :73 (section end on `lvl(v)`), :75 (`!sec { next }`).
- **Failure path:** after the table's blank line, add `<!-- note -->#`, `<!-- see below -->##`, `<!-- note --> ## end`, or `<!--` / `x` / `-->## more`, then a red table.
  - awk reads `v` as a level-1 or level-2 heading and ends the section, so every later line is skipped.
  - Real output: `unread` is empty, then `PRs read: none` (or 8), then `job done`, exit 0.
  - In CommonMark the whole line is raw HTML, so no `<h2>` appears, and the red table renders inside the Phase plan section.
  - This is the P3R4-3 class, and it survives fix 4.
- **Suggested fix:** treat a line starting `<!--` (0-3 spaces), and a block comment's closing line, as wholly hidden for heading and section-end purposes. Refuse any non-blank text after `-->` at done. Better still, end the section only at a raw left-margin `#`/`##` line outside any fence or comment. AR's prototype, `if (sec && v == l && l ~ /^##?([ \t]|$)/) sec = 0`, refuses both routes and still passes the template control.
- **Raised by:** architect-reviewer, security-reviewer, critical-thinking.

**R5-3 (HIGH). A fence on a list-item marker line is not seen, so an indented `## x` inside it ends the section.**
- **Location:** lib/checkpoint.sh:64 (a fence opens only for `^ ? ? ?(```|~~~)` on the raw line), :28-33 (`lvl` strips up to 3 spaces), :73, :89 (`- ```` holds no `|` or `<`, so it passes).
- **Failure path:** after the table's blank line, add `- ```` / `  ## notes` / `  ```` (or `1. ~~~` / `   ## x` / `   ~~~`), a blank line, then a left-margin table with `done (abc1234) · PR #7`.
  - Real output: `unread` is empty, `cells` holds row 0 only, then `job done`, exit 0.
  - markdown-it renders `<li><pre><code>## notes`, then the red table, with no `<h2>` in between.
  - This route uses no HTML and no encoding, and it reads like a code sample in a note, so it is the least contrived of the in-section routes.
- **Suggested fix:** detect fences on the container-stripped line `c` and refuse any fence marker after the table. Or end the section only at a left-margin heading (the R5-2 fix covers this route).
- **Raised by:** architect-reviewer, silent-failure-hunter, critical-thinking.

**R5-4 (HIGH). The fence model differs from CommonMark in both directions (info string, closer length and character, container end, HTML blocks). It hides a visible second Phase plan, or lets a decoy plan be the one read.**
- **Location:** lib/checkpoint.sh:62 (closes on any line starting with the opener's first 3 characters), :64 (opens on any ```` ``` ````/`~~~` with no info-string check; `fc = substr(...,1,3)`; ignores containers and HTML blocks), :68-71.
- **Failure path:** each route below gave `unread` empty and exit 0, while markdown-it shows a red Phase plan.
  - **A backtick in a backtick info string** (```` ```x`y ````, ```` ```x` ````, ```` ```see `x` ````, ```` ``` a`b ````). CommonMark has no fence there, but awk opens one and hides a second `## Phase plan` with its red table.
  - **Decoy** (SR f4b, SFH f4, CT B). A four-backtick fence is closed early by an inner ```` ``` ```` for awk only. The green decoy plan inside it is what awk reads. The next ```` ```` ```` opens an awk fence to EOF, hiding the only rendered `<h2>Phase plan</h2>`, which is red.
  - **Unclosed fence in a list item** (SR f4c, SFH f7). CommonMark closes it when the item ends; awk never does. This one could happen by accident.
  - **```` ``` ```` inside a `<div>` HTML block** (AR, SFH f6).
- **Suggested fix:** model fences per CommonMark:
  - keep the fence character and run length;
  - a backtick opener with a backtick in its info string is no fence;
  - close only on the same character, at least as long, with nothing after it but blanks;
  - close at the container's end;
  - refuse a fence still open at EOF.

  Simpler fail-closed alternatives: refuse every fence line anywhere at done (this changes test 41:269-274's `ok` case, which is the owner's call), or count a heading whose whole text is `phase plan` even inside a fence.
- **Raised by:** critical-thinking, security-reviewer, penetration-tester, architect-reviewer, silent-failure-hunter.

**R5-5 (HIGH). The second-heading counter misses many forms that render "Phase plan", although the code comment (:22-23) and docs/spec.md:97 claim it reads "through markup, entities, odd spaces".**
- **Location:** lib/checkpoint.sh:34-38 (`pp` maps only `&nbsp;`/`&#32;`/`&#x20;`/NBSP/ZWSP and drops `*_~` and backticks, not `[`), :28-33 (`lvl` gives 0 at 4 spaces even inside a list), :67-69 (`<h` only at line start and on the same line; setext tested on raw `p`/`v`, not on container-stripped `c`).
- **Failure path:** a valid green plan, then `## Completed phases`, then one of the headings below and a table with `done (abc1234) · PR #7`. Each gave `unread` empty, `PRs read: 8` (or none), then `job done`, exit 0, and markdown-it renders a second `<h2>Phase plan</h2>`:
  - entity letters: `## &#80;hase plan`, `## &#x50;hase plan`, `## Phase p&#108;an`, `## Phas&#101; plan`;
  - entity spaces: `## Phase&#160;plan`, `&#032;`, `&#x0020;`, `&#xA0;`, `&ensp;`, `&NonBreakingSpace;`, `&Tab;`, `&#9;`;
  - form feed, and Unicode U+2002/U+2003/U+2009/U+3000/U+000B, plus U+00AD/U+200C/U+2060/U+FEFF;
  - links: `## [Phase plan](#x)`, `## [Phase](#x) plan`;
  - `<div><h2>Phase plan</h2></div>`, and `<h2>` / `Phase plan` / `</h2>` on three lines;
  - setext inside a quote or list item (`> Phase plan` / `> ---`, `- Phase plan` / `  ---`);
  - a 4-space ATX heading inside a list item (`- note` / blank / `    ## Phase plan`, and `10. notes` …).
  - Re-confirmed accepted residual: two-line setext `Phase` / `plan` / `----`.
- **Suggested fix:** fail closed rather than normalise. At done, refuse any heading-like line whose text holds `&`, `[`, `<` or a non-ASCII byte. Heading-like means ATX after any container prefix at any indent, any setext underline (container-stripped), or any `<h[1-6]` anywhere on the line, including one not closed on that line. Alternatively, decode every entity and map every Unicode space before `pp`. Correct the claims at checkpoint.sh:22-23 and spec.md:97.
- **Raised by:** critical-thinking, penetration-tester, architect-reviewer, silent-failure-hunter (HIGH); security-reviewer (MEDIUM).

**R5-6 (HIGH). A comment closed the HTML5 way (`--!>`) hides a raw-HTML table from awk that a browser shows.**
- **Location:** lib/checkpoint.sh:63, :65, :66, :89.
- **Failure path:** after the table:
  - SFH f5 / PT e-bangclose: `<!-- x --!>` / `<table>…<td>done (abc1234) · PR #7</td>…</table>` / `-->`.
  - SFH f5b: the same on one line.
  - SFH f5c: `Notes: <!-- x --!> <table>…</table> -->`.

  Each gave `cp_unread` empty, then `job done`, exit 0. CommonMark and awk both see one comment ending at `-->`, but the HTML5 tokenizer ends it at `--!>`. Python `html.parser` confirms that a `table` starts there. Not checked in a browser or on GitHub, whose sanitizer may differ.
- **Suggested fix:** treat `--!>` as a comment end, or refuse any comment in or after the section whose body holds `--!>`, `<`+letter, or `|`. Fail-closed alternative: refuse every comment except the rules comment.
- **Raised by:** silent-failure-hunter (HIGH), penetration-tester (MEDIUM).

**R5-7 (HIGH). The inline `<!-- … -->` strip removes text that CommonMark 0.29/0.30 does not parse as a comment (a `--` inside), so an HTML table in a note passes.**
- **Location:** lib/checkpoint.sh:66, :89.
- **Failure path:** SFH f5d, after the table: `Notes: <!-- x -- <table><tr>…<td>done (abc1234) · PR #7</td></tr></table> -->`.
  - Real output: `unread` empty, `PRs read: none`, then `job done`, exit 0.
  - markdown-it renders `&lt;!-- x -- <table>…PR #7…</table> --&gt;`, so the row is visible.
  - This reopens the `<table>` route (P3R4-2/-3) that `ur 14` pins as closed.
  - It depends on the renderer: CommonMark 0.31.2 would treat it as a comment.
- **Suggested fix:** do not strip inline comments in or after the section. After the table, refuse any `<[A-Za-z/!?]` on the raw line unless the line is a block comment that starts at the line start.
- **Raised by:** silent-failure-hunter.

**R5-8 (HIGH). False refusal: the template invites "its /pull/<n> link", but a Markdown link, an autolink, or a URL with a `#fragment` in the Status cell is refused (P3R4-24/-39, still open).**
- **Location:** templates/checkpoint.md:34-35; lib/ci.sh:86-87 (`[<[]` refused), :89-91.
- **Failure path:** each was refused with exit 10:
  - `done (abc1234) · [PR #9](https://github.com/o/r/pull/9)` and `<https://github.com/o/r/pull/12>`: "holds a character the runner does not read there (not ASCII, or '<' or '[')".
  - `…/pull/8#issuecomment-1`: "holds ' · #issuecomment-1 '".

  The bare URL, `…/pull/12/files`, `PR #12 (draft)` and `**PR #12**` pass. The refusal fails closed, its message says what to write, and it comes at the end of a job.
- **Suggested fix:** change the template (and brief step) wording to "its bare `https://…/pull/<n>` URL (no brackets, no `<>`, no `#fragment`)". Or accept `[PR #N](…/pull/N)` and `<…/pull/N>` when the numbers agree.
- **Raised by:** architect-reviewer (HIGH), security-reviewer (MEDIUM), silent-failure-hunter (MEDIUM), penetration-tester (LOW), critical-thinking (LOW).

## Medium and Low Findings

| ID | Severity | Title | Location | Reviewer(s) | One-line description with suggested fix |
|---|---|---|---|---|---|
| R5-9 | MEDIUM | Escaped pipe `\|` in any cell refuses `done` with a misleading message | lib/checkpoint.sh:40, :87; templates/checkpoint.md:24-28 | critical-thinking, security-reviewer | A GFM-correct ``| 0 | spec | `tests/run 2>&1 \| tail -1` is GATE: PASS | done … |`` (4 rendered cells) is refused as "no phase row … with the header's 4 cells"; the owner rule stands, so name `\|` in the template and the message, or split only on unescaped `\|` and refuse it only in the Status cell. |
| R5-10 | MEDIUM | Notes under the table are refused for a `\|` or for the template's own `<placeholder>` style | lib/checkpoint.sh:89-90; templates/checkpoint.md:26-27 | security-reviewer, penetration-tester (M4, L1), architect-reviewer (M1, L1), critical-thinking (LOW), silent-failure-hunter (L1) | `Phases 2a \| 2b …`, ``…`tests/run \| tail -1`…``, `` `blast-off ci-wait <job-dir> 9` ``, `done (<sha>)` and `x<y and a>b` all exit 10, and the message says "no table, code block or HTML"; write "plain text with no `\|` and no `<`" in the template and the refusal, or drop code spans before the test. |
| R5-11 | MEDIUM | A duplicate `Status` header reads only the last column, so a PR in the other Status column goes unread (exit 0) | lib/checkpoint.sh:41, :78 | penetration-tester (M2, reproduced), architect-reviewer (L5, code reading) | `\| # \| Phase \| Status \| Status \|` with `done … · PR #7 \| done … · no PR` gives `PRs read: none`, then `job done`; refuse a header where any non-last cell trims to `status`. |
| R5-12 | MEDIUM | A triple-backtick inline-code line before the plan makes the whole plan vanish; the refusal at done says "no done row" and names no line | lib/checkpoint.sh:64; lib/ci.sh:100; lib/chain.sh:100-108, :155-157 | penetration-tester | The template's `Next action` written as ```` ```blast-off ci-wait <job-dir> 9``` … ```` gives rows=0, so the cap goes hard and receipt_check silently skips rows mid-run, and done says "add a ## Phase plan table"; fix the fences (R5-4) and have `ci_plan` refuse a hidden level-2 Phase plan heading, naming its line. |
| R5-13 | MEDIUM | Mid-run, one malformed row silently drops it and every later row | lib/checkpoint.sh:84-87 (`st = 3`), :21; lib/chain.sh:100, :134, :155, :170; lib/jev.sh:52; lib/preflight.sh:18, :81 | critical-thinking, architect-reviewer (M3), penetration-tester (L4) | A row 0 with `\|` gives rows/open/done all empty, so the soft cap is lost (hard cap 12, exit 4), receipt_check, cp_mark_usage, jev and preflight see nothing, and nothing is logged until done; log a non-empty `cp_unread` at each child's end, without refusing. |
| R5-14 | MEDIUM | Architecture: the gate rests on a partial CommonMark block parser in awk; the section boundary, after-table zone and heading count are a deny-list over that approximation | lib/checkpoint.sh:58-75, :89 | architect-reviewer | R5-1 to R5-7 are all places where the model differs from CommonMark; shrink it so that what it does not understand refuses (left-margin `#`/`##` bounds only, a comment opens only with no `-->` on its line, refuse text after `-->`, fence markers and `<` after the table, refuse heading candidates holding entities, brackets or tags). The prototype is at /tmp/p3r5-architect-reviewer.SUSW9W/proto/checkpoint.sh. |
| R5-15 | LOW | A PR added after the runner's ` · usage` is refused with a misleading message | lib/ci.sh:89-91 | security-reviewer | `done (abc1234) · PR #7 · usage 5h 30% 7d 12% · PR #9` gives "holds ' ·  · usage … ·  '"; say "PRs go before the runner's ` · usage ...`", or strip the usage form anywhere if only PR tokens follow it. |
| R5-16 | LOW | Duplicate row keys are accepted, and receipt_check checks only the first row's sha | lib/checkpoint.sh:50 (`!got++`); lib/receipt.sh:50-51; docs/spec.md:228 | security-reviewer, architect-reviewer (L4) | Two rows keyed `1` give `done` = `1 1` and `sha` = first only, so the second commit never meets exit 9 (ci_check still reads both PRs); refuse a repeated key in unread mode. |
| R5-17 | LOW | A source path of the form `name=value` is taken by awk as an assignment | lib/checkpoint.sh:91; lib/preflight.sh:77 | security-reviewer | `cp_scan rows 'prev=t0.md'` reads stdin and prints 0 lines (preflight says "no estimate", or blocks on a tty); pass `./$f` or redirect `< "$file"`. |
| R5-18 | LOW | Done gates re-read checkpoint.md 3-4 times with no snapshot | lib/chain.sh:160; lib/ci.sh:62, :79; lib/receipt.sh:69; lib/child.sh:143 | security-reviewer, silent-failure-hunter (L4) | A live writer (e.g. under `JOB_KEEP_WINDOWS=1`) could swap a row after `ci_plan`, and `receipt_all_done` drops cp_open_rows' exit status; copy the file once at done and pass the path to every `cp_scan`. |
| R5-19 | LOW | A backticked sha is refused (P3R4-41, still open) | lib/ci.sh:89-91 | architect-reviewer | ``done (`abc1234`)`` gives exit 10, and the template shows `done (<sha>)` in backticks; accept the backticks or say "no backticks". |
| R5-20 | LOW | `**done**` gives exit 9 with wrong advice | lib/checkpoint.sh:47 | architect-reviewer | A reader sees done; the runner says open and advises a receipt re-run; refuse markup around `done` through `bad()`, as at :48. |
| R5-21 | LOW | Upper-case hex sha: the two readers disagree | lib/checkpoint.sh:52 vs lib/ci.sh:89 (`I` flag) | silent-failure-hunter | `done (ABC1234)` passes ci_check's whitelist but reads as "names no commit" (exit 9); drop `I` for the sha part or lower-case it in awk. |
| R5-22 | LOW | README says "digit row keys" | README.md:145 | penetration-tester | `P1`-style keys are now read (criterion 5); write "row keys (0, 1, 2a)". |
| R5-23 | LOW | Docs and comment overclaim or drift | docs/spec.md:96, :97, :228; lib/checkpoint.sh:22-23 | architect-reviewer (H4, L4, L6), silent-failure-hunter (L6, H5), critical-thinking | spec.md:97 claims a second heading is refused "read through markup and odd spaces" (false, R5-5) and says "the phase's own PR" (the template says every PR); :96 says "Status starts `done`" (the code wants `done` alone, or followed by a blank or `(`); :228 says "duplicate row keys are each read" (true only in ci_check); align them. |
| R5-24 | LOW | The CR and second-heading refusals cover the whole file, and the template does not say so | lib/checkpoint.sh:59, :68-71 | silent-failure-hunter | A raw CR pasted into Progress, or a prose "Phase plan …" line followed by `---`, refuses done; add one clause to the template rule. |
| R5-25 | LOW | `cp_mark_usage` gives up silently on a read failure | lib/checkpoint.sh:129 | silent-failure-hunter | `\|\| return 0` logs nothing; log "usage marks skipped: checkpoint.md unreadable". |
| R5-26 | LOW | Entity pseudo-rows after the table pass as prose | lib/checkpoint.sh:89 | silent-failure-hunter | `&#124; 1 &#124; … PR #7 &#124;` or `&vert;` renders as a row-like text line; under ruling 1 it is prose, so optionally refuse `&#124;`/`&vert;`/`&verbar;` after the table. |
| R5-27 | LOW | `## Phase plans` and `## Phase plan_v2` are not counted as second headings | lib/checkpoint.sh:37 | penetration-tester | The cost of the P3R4-6 narrowing; optionally count `plans?` and keep `_` as a word boundary. |
| R5-28 | LOW | A PR named in another column beside `no PR` passes (as ruled) | lib/ci.sh:92-94 | penetration-tester | `\| 0 \| a \| PR #7 \| done (abc1234) · no PR \|` gives exit 0; optionally refuse `no PR` when another cell of the row holds a PR token (fail-closed, no ruling change). |
| R5-29 | LOW | No test pins the R5-1 to R5-7 routes | tests/41-ci-wait.sh:217-274 (`ur 14`, `ur 17`, `uh` loop, `ok` case) | security-reviewer, silent-failure-hunter (L8), critical-thinking, architect-reviewer | Only a multi-line comment (:236), a row inside `<!-- -->` (:221), plain headings (:252-262) and a left-margin fence (:269-274) are pinned; add each reproduced fixture as an exit-10 case, plus a passing well-formed comment and fence. |

## Coverage Report
Reviewers: 5/5 returned
Reviewed at: 15960ad6b617daa0aebd8948127015c5f3f9833e
Any commit after this one is unreviewed.

**Confirmed**
- **Every Phase plan reader goes through `cp_scan`.**
  - Greps of lib/ and bin/ found only the cp_* wrappers at chain.sh:100/155/170/196, jev.sh:52-54, preflight.sh:18/77/81, receipt.sh:50-51/69 and ci.sh:62/79.
  - The other checkpoint.md reads (cp_status, cp_names, units.sh:71, usage.sh:81) read status or header only.
  - PR parsing exists only in `ci_prs`, which is fed only by `cp_done_cells`.
  - All five reviewers confirmed this.
- **Done-path order and exit-status checks.** `ci_plan` runs before `receipt_all_done` and `ci_check` (chain.sh:160). ci.sh:62 and :79 check cp_scan's exit status. Confirmed by all five.
- **Allow-list core inside the table holds.** Cell count, `\|`, trailing pipe, header last cell = Status, separator, pipe-less or indented rows, rows above the header, a mid-line CR, and bad keys (read as open) all behave as specified (checkpoint.sh:39-44, :59, :77-88). Confirmed by SR, PT, SFH and AR.
- **Controls.**
  - A red row inside the table gives exit 10.
  - A second table after the blank line is refused (line 8/20).
  - A plain second `## Phase plan` is refused ("second Phase plan heading").
  - Confirmed by all five.
- **Template-following checkpoints pass.** templates/checkpoint.md, closed as the brief says, passes with the usage suffix, CRLF, `## Phase Plan`, `P0..P2` keys, `PR #8 · PR #9`, the bare `/pull/N` URL, `(draft)`, `**PR #12**`, `no PR`, plain notes and a balanced four-backtick fence. The rules comment keeps `v` empty and holds no `|`. Confirmed by all five.
- **The three deliberate changes.** `## Phase Plan` in any case and `P1` keys only widen what is read, so no template-following checkpoint is refused by them. "Any `|` or row after the table" reaches a template-following child only through notes (R5-10). Confirmed by all five.
- **gawk 5.2.1 and mawk 1.3.4 give identical cp_scan output** on the fail-open fixtures (SR, PT, SFH).
- **Lint.** `shellcheck` on the changed libs shows only the pre-existing SC2016 at preflight.sh:102, and `bash -n` is clean (SR, PT, SFH, AR).
- **cp_mark_usage cannot change a row's cell count.** `USAGE` (usage.sh:17-36) cannot hold `|` (AR).
- **Diffs to the other tests and fakes agree with the rulings** (tests 10/21/32/40/51/70 and fakes/claude, fakes/gh). README.md:112-120 and the SKILL.md diff state the rulings as built (AR).

**Examined, inconclusive**
- How GitHub (cmark-gfm plus its sanitizer) renders `<!-->`, list-item fences, backtick-info fences and `--!>`. Blocker: no cmark-gfm or network; markdown-it-py 3.0.0 and Python `html.parser` were used instead (CT, SR, PT, SFH, AR).
- f5d (R5-7) depends on the renderer: CommonMark 0.31.2 would parse it as a comment (SFH).
- A pipe-less one-column GFM table after the table (SR f5) gives runner exit 0, and markdown-it renders a paragraph. Whether cmark-gfm renders a table there is unknown.
- A comment opened inside a list item (SR f3) gives runner exit 0, and markdown-it closes it with the item, but a browser may swallow the rest. Not claimed.
- All routes ran in stub harnesses (`TOP=`, `ci_head` stubbed), not a full `bin/blast-off run`. `cp_scan done`/`rows` match the green control, so receipt_check in git sees only the honest row (PT, SR).
- AR's prototype fix was checked only against AR's 16 fixtures, not against test 41.
- SFH: one probe made a single read-only real `gh pr view 12`, which failed with "not a git repository" and changed nothing.

**Not examined**
- No scenario run (41, 51, 70 or others) by any reviewer.
- `ci_wait` and `ci_runs` runtime behaviour: criteria 2 and 4 are not exercised at runtime (P3R4-13).
- tests/41-ci-wait.sh outside lines ~90-330 case by case.
- The full README, the full spec and SKILL.md beyond the diff and cited lines.
- receipt_check with `TOP` set and real receipts.
- SIGPIPE on `cp_open_rows | head -n 1` (jev.sh:52, preflight.sh:18).
- Homoglyph headings (an accepted residual).
- GitHub issue 26 text (CT).

**Engagement check:** all five reviewers engaged. Each has a substantive Confirmed list and reproduced HIGH findings. None is tagged `[DID NOT ENGAGE]`.

## Unstated Assumptions and Open Questions (from critical-thinking)
- **Item:** the allow-list assumes awk's idea of "hidden" (comments, fences) matches the renderer's.
  - **Why it matters:** all three of critical-thinking's HIGHs sit where the two differ, and an allow-list that accepts anything it calls hidden, unread, is not one.
  - **What to verify or decide:** why accept any comment or fence at all, instead of only the one verbatim rules comment and no fences anywhere?
- **Item:** the heading counter is described as complete.
  - **Why it matters:** it matches text against an open-ended syntax, so each round finds the next spelling. A visible plan under another heading is already accepted (P3R4-42).
  - **What to verify or decide:** is the counter a guarantee or a lint, and what bounds the syntax it must cover?
- **Item:** row modes never refuse, and one bad line drops every later row mid-run.
  - **Why it matters:** receipts, usage marks, jev, preflight and possibly the cap type are all affected silently until the end.
  - **What to verify or decide:** why not log `cp_unread` at each child's end?
- **Item:** `\|` is refused in every cell, not only in the key and Status cells that feed the gate.
  - **Why it matters:** only those two cells are read. This is a binding owner decision.
  - **What to verify or decide:** does any route stay closed only because `\|` is refused outside the key and Status cells?
- **Item:** tests pin only routes earlier rounds found.
  - **Why it matters:** the comment, fence and heading cases at test 41:221, :232, :236, :252-262 and :271 do not cover `<!-->`, `<!--->`, text after `-->`, container fences, closer length, info-string fences, entities, multi-line `<h2>` or quoted setext headings.
  - **What to verify or decide:** add TA, H, G, I, B, C, D, E, F, L1, T3 and K as cases.
- **Item:** the reference reader is never named.
  - **Why it matters:** route 1 depends on CommonMark plus HTML5 comment parsing; a raw-text reader sees everything.
  - **What to verify or decide:** name the reference renderer in docs/spec.md, so "a line that escapes by its format" can be tested.

## Reviewer Disagreements
- **R5-5 (heading normaliser):** HIGH from CT, PT, AR and SFH; MEDIUM from SR; round 4 rated the class MEDIUM (P3R4-4). **Resolution:** HIGH. Under this run's guide a PR goes unread and done exits 0, and the ASCII forms (entity letters, links) are outside the accepted homoglyph residual.
- **R5-8 (template-invited link form):** HIGH from AR; MEDIUM from SR and SFH; LOW from PT and CT. **Resolution:** rendered HIGH under the highest-severity rule, because the template text leads to it. By impact it is MEDIUM: it fails closed and the message says what to write. The fix is a one-line template wording change.
- **R5-6 (`--!>`):** HIGH from SFH; MEDIUM from PT, because browser and GitHub rendering are unchecked. **Resolution:** HIGH, with the rendering caveat recorded under Examined, inconclusive.
- **R5-10 (notes refusal):** MEDIUM from SR, PT (pipe) and AR (pipe); LOW from CT, SFH, and PT and AR for the placeholder case. **Resolution:** MEDIUM. Both triggers share one root cause (checkpoint.sh:89 plus the template's "plain text" wording) and one fix.
- **R5-11 (duplicate Status header):** MEDIUM from PT (reproduced exit 0); LOW from AR (code reading only). **Resolution:** MEDIUM as filed. Note that PT's reproduction is a PR in a reader-visible "Status" column going unread with exit 0, which meets this run's HIGH definition. The owner should weigh that against ruling 1's "last cell is Status".
- **R5-13 (mid-run row drop):** MEDIUM from CT and AR; LOW from PT, because it is documented behaviour. **Resolution:** MEDIUM. The behaviour is documented, but its silence affects the cap type and the receipts.
- **Fix strategy:** SR, PT and SFH propose modelling CommonMark more faithfully. AR and CT propose shrinking the model and failing closed (refuse comments other than the rules comment, refuse fences, refuse heading candidates with entities, brackets or tags). **Resolution:** prefer fail-closed. It is smaller, fits the owner's allow-list direction, and ends the round-by-round chase.
- **No factual contradictions** between reviewers. The same fixtures (`<!-->`, list fences, backtick info strings, entity headings) were reproduced independently with matching outputs.

## Recommended Changes (Prioritized)
1. Disposition the 9 open questions.
2. Make the comment model fail closed: at done, refuse any `<!--` other than the template's verbatim rules comment, and any `--!>`, or at least close on `-->` anywhere on the opener line (R5-1, R5-6).
3. Treat comment lines as wholly hidden, refuse any text after `-->`, and stop stripping inline comments in or after the section (R5-2, R5-7).
4. End the Phase plan section only at a raw left-margin `#`/`##` line outside any fence or comment (R5-2, R5-3).
5. Refuse fence markers in and after the section, or model fences per CommonMark (character, length, info string, container end, open at EOF) (R5-3, R5-4, R5-12).
6. Refuse any heading-like line, in any container or as `<hN>` anywhere, whose text holds `&`, `[`, `<` or non-ASCII, instead of normalising toward "Phase plan" (R5-5).
7. Pin every reproduced fixture from R5-1 to R5-7, plus passing controls, in tests/41-ci-wait.sh (R5-29).
8. Reword templates/checkpoint.md:34-35 and the brief step to "the bare `https://…/pull/<n>` URL, no brackets, `<>` or `#fragment`" (R5-8).
9. Refuse a header with more than one `Status` cell (R5-11).
10. State "no `|` and no `<`" for notes, and name `\|` as banned, in the template rules and the refusal messages (R5-9, R5-10).
11. Log a non-empty `cp_unread` at each child's end without refusing (R5-13).
12. Snapshot checkpoint.md once at done and pass that path to every `cp_scan` (R5-18).
13. Refuse duplicate row keys in unread mode (R5-16).
14. Correct the docs and comment drift at docs/spec.md:96, :97 and :228, README.md:145 and lib/checkpoint.sh:22-23 (R5-22, R5-23, R5-24).
15. Fix the small LOWs: the misleading message for a PR after usage, `./`-prefixing the awk operand, backticked sha, `**done**`, upper-case sha, cp_mark_usage logging, and optionally entity pseudo-rows, `plans?`, and a PR in another column beside `no PR` (R5-15, R5-17, R5-19, R5-20, R5-21, R5-25 to R5-28).

## Open Questions for the Author
- Should `cp_scan` accept any comment or fence at all, rather than only the one verbatim rules comment and no fences anywhere? — Disposition: PENDING
- Is the second-heading counter a guarantee or a lint, and what syntax bound must it cover? — Disposition: PENDING
- May the test 41 `ok` case (tests/41-ci-wait.sh:269-274), which pins a left-margin fence after the section as a pass, change if fences are refused at done? — Disposition: PENDING
- Is a real CommonMark parser dependency (e.g. markdown-it-py) acceptable for the gate (P3R4-14), or must it stay POSIX awk? — Disposition: PENDING
- Which renderer is the reference (GitHub cmark-gfm plus sanitizer, or CommonMark 0.30/0.31.2), named in docs/spec.md so "escapes by its format" can be tested? — Disposition: PENDING
- Should `cp_unread` be logged at each child's end, without refusing, so a malformed line is fixed in the session that wrote it? — Disposition: PENDING
- Does any route stay closed only because `\|` is refused outside the key and Status cells, i.e. could the ban be narrowed? — Disposition: PENDING
- Should a duplicate `Status` header, and a PR token in another cell beside `no PR`, be refused (fail-closed, no ruling change)? — Disposition: PENDING
- Should the reproduced fixtures (TA, H, G, I, B, C, D, E, F, L1, T3, K and the other reviewers' f-series) all become test cases? — Disposition: PENDING

## Notes
- Reviewers could not save report.md copies in their /tmp dirs, because the harness refused subagent report-file writes. The hand-back messages are the only copies, and the synthesis used them verbatim. Fixtures and harnesses remain in /tmp/p3r5-architect-reviewer.SUSW9W, /tmp/p3r5-critical-thinking.WDHYeP, /tmp/p3r5-silent-failure-hunter.LIjgiM, /tmp/p3r5-security-reviewer.72MPzs and /tmp/p3r5-penetration-tester.m9owZ9.
- Skill steps were skipped on the caller's instruction ("Do not edit any other file"). Per-reviewer checkpoints under `<git-root>/.claude/reviews/<slug>/` were not written, and info/exclude was not touched. The report path is the caller's `--write-to` path, which git does not ignore.
- No reviewer ran a test scenario. All evidence comes from direct `cp_scan` and `ci_check` stub-harness fixtures plus markdown-it-py renders. Nobody checked GitHub (cmark-gfm plus sanitizer) rendering.
- `--adversarial` was not passed, so the findings are unrefuted.

## Report Audit

- **Class 5 (coverage inflation): the Controls bullet.**
  - The report says, under Coverage Report › Confirmed › Controls: "A red row inside the table gives exit 10. A second table after the blank line is refused (line 8/20). A plain second `## Phase plan` is refused … Confirmed by all five."
  - The source shows only four reviewers recorded control runs:
    - critical-thinking: "Control A_ctl …" and "A plain second `## Phase plan` (CTL2) is refused".
    - security-reviewer: "`ctl-red.md` … `EXIT=10`".
    - architect-reviewer: "Control fixtures: …".
    - silent-failure-hunter: "Control `ctrl.md` gives exit 10 on PR #7 red".
  - penetration-tester's Validated section lists no control run. Its harness note says only "records with PR 8 green and PR 7 red". So "all five" credits penetration-tester with a confirmation it did not report.

- **Class 5 (coverage inflation): the done-path order bullet.**
  - The report says: "`ci_plan` runs before `receipt_all_done` and `ci_check` (chain.sh:160). ci.sh:62 and :79 check cp_scan's exit status. Confirmed by all five."
  - In the source, critical-thinking ("`ci_plan` runs first at done … (lib/chain.sh:160)"), security-reviewer, architect-reviewer and silent-failure-hunter each list this under Confirmed.
  - penetration-tester's Validated section does not confirm the order or the exit-status checks. Only its Summary mentions the harness running `ci_plan; receipt_all_done; ci_check; chain_end 0`. None of the reviewers' Validated text shows penetration-tester or critical-thinking checking the ci.sh:62/:79 exit status.
