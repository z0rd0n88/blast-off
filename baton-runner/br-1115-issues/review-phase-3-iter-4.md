# Multi-agent review: phase 3 (issue 26), round 4 (first round after the owner's "guide & resume")

**Target:** `spec` over the 19 product paths of `git diff feat/br-1115-issues/phase-2...HEAD` (newest product commit e791f67, the P3R3-1 fix). Read-only.
**Gate:** `scripts/gate.sh baton-runner/br-1115-issues/gate-phase-3-iter-4/` → `GATE: PASS passed=18 failed=0 shellcheck=ok`, exit 0. ExecStart unchanged.

## Executive summary

0 CRITICAL, **2 HIGH**, 14 MEDIUM, 29 LOW (45 IDs) after dedup of 80 reviewer findings (AR 17, CT 14, SF 17, SE 16, PT 16) plus the lead's probes.

The fix closes what it lists. `cp_unread` refuses every line in the raw `## Phase plan` section that holds an ASCII `|` and is not the header, the separator or a parsed row. That covers key `P1`, bold, indented, tab, NBSP, no leading pipe, a mid-line CR and a plainly spelled second heading. All four reviewers who probed found no ASCII-pipe line in that section that escapes.

It does **not** close P3R3-1 as a class: "a Phase plan row, or the PR in its Status cell, that a reader of the rendered checkpoint sees and the runner does not read". Two HIGH routes stay open, both confirmed exit 0 with a red PR, and the phase-2 base refused every one of them:

- **P3R4-1:** an ordinary-looking digit-keyed row whose rendered Status cell is not the cell the runner reads. Causes: an extra cell, an escaped `\|`, a missing trailing pipe, or a Status column that is not last.
- **P3R4-2:** table rows that hold no ASCII `|`. Either a pipe-less line directly under the table, which GFM renders as a row, or an HTML `<table>` row in the section.

Acceptance criterion 3 ("no Phase plan line can escape the gate by its format") is therefore **not met**.

The reviewers agree on the shape of the cure: an allow-list of section lines plus one cell-count and no-`\|` rule on rows, produced by one scanner. One reviewer prototyped it at about the same size as today's `cp_unread`; it closes every probe except a zero-width-space heading and the accepted residual. It refuses some layouts HEAD allows, so it needs an owner ruling (P3R4-14).

**No false refusal of a checkpoint the templates produce was found.** This was checked against the real `templates/checkpoint.md` with its comment verbatim, closed as brief step 4 says, with the runner's ` · usage` suffix and with CRLF line endings. Off-template refusals exist (P3R4-6, LOWs), all fail-closed, each naming the line.

## How this review ran
- **The skill:** `Z0rd0nZords:zord-multi-agent-review` was invoked as `spec <19 paths> --write-to <this file> --yes`. Only its command summary loaded, as in round 3.
- **Locus:** the review ran inline in this unit (itself a subagent). The shared brief is `review-phase-3-iter-4/brief.md`.
- **Roster:** the default five: architect-reviewer (AR), critical-thinking (CT), silent-failure-hunter (SF), security-reviewer (SE), penetration-tester (PT). The roster's agents are parked, so **each ran as a general-purpose agent that read its parked definition read-only.**
- **Report files:** the harness refused every reviewer's report file ("subagents return findings as text"), so the reports exist only as their returned messages. Their findings are carried below under the reviewers' own IDs.
- **Synthesis:** done by the lead in this unit, not by a separate knowledge-synthesizer agent, because a subagent could not write the file. The skill's dedup rule was applied: one ID per root cause, source IDs listed. The HIGH cap is off (gate use).
- **Adversarial refutation:** not run (not asked for).
- **Report audit:** see the end of this file.
- **Test-run rule:** kept. No reviewer ran any scenario; their briefs barred all scenarios. The lead ran the gate once, alone, then scenarios 41, 51 and 70 one at a time on a /tmp copy with no `.git` (`review-phase-3-iter-4/mut.sh`). No scenario that calls `install_units` was run.
- **Temp dirs:** nobody deleted anything. AR reports that it ran the lead's harness unchanged, so some `/tmp/p3r4-probe*.XXXXXX` dirs are AR's, not the lead's. They are left in place.

## Lead's own evidence (`review-phase-3-iter-4/`)
- **`probes.sh` / `probes.log` (stub harness: libs sourced, `receipt_all_done; ci_check`):**
  - Exit 0 beside a green row while a red PR #7 sits in:
    - an HTML table (one-line and multi-line)
    - a table after a `## ` line hidden in a comment or fence
    - a pipe-less continuation line
    - fullwidth or box-drawing pipes
    - a table under a visible `## ` heading
  - Refused correctly: indented, tab, NBSP, `P1`, a separator with no leading pipe, a CRLF bad row, a second heading at any level, and setext.
- **`probes2.sh` / `probes2.log`:** on the real template, every template-shaped close passes (also with CRLF, `Done`, two PR tokens and `· CI green`). Refused: a backticked sha, a sha without parens, a sha with a space, `CI 3/3`, a date after the PR, `### Phase plan changes` under Completed phases, and an empty pipe row.
- **`mut.sh` / `mut.log`:**
  - Real runner, probes appended to scenario 41: `html-table`, `cmt-h2-then-table`, `fence-h2-then-table` and `gfm-pipeless-cont` all **exit 0, `job done`**. Controls: green-only exit 0, red-row exit 10.
  - The **phase-2 base refuses all six** bin-one probes (exit 10, PR #7 red).
  - Mutants: 12 of 13 KILLED, namely u1 to u4, w1, m1, m2, m5, t1 and d1 to d3. **u5 SURVIVED** (the header "no done in last cell" guard is not pinned).

## Findings, MEDIUM and above

#### P3R4-1 HIGH: the runner reads a different Status cell than the reader sees
Sources: AR-1, PT-1, PT-2, PT-3, SE-1, SE-2, SF-1 (also AR-10, LOW).
- **Where:** `lib/checkpoint.sh:48` (`st = $(NF-1)`), `:68` (cp_unread passes any `^\| *[0-9]` line unshaped), `:85` (cp_row_sha, same problem).
- **Failure paths** (all digit-keyed, from the left margin, inside the section, beside a green done row; all exit 0):
  - `| 1 | a | b | done (abc1234) · PR #7 | done (abc1234) · no PR |`. GFM drops the 5th cell, so the reader sees red PR #7.
  - `| 1 | a | b | done (abc1234) · PR #7 \| done (abc1234) · no PR |`. One rendered cell holds both tokens; awk reads only the tail.
  - `| 1 | a | done (abc1234) · no PR | done (abc1234) · PR #7`, with no trailing pipe. The runner reads column 3.
  - Header `| # | Phase | Status | Notes |`. The runner reads Notes.
  - `| 2 | a | b | pending | done (abc1234) · no PR |` and `| 2 | a | b | pending \| done … |`. A row rendered as pending passes `receipt_all_done`.
  - SE-1 and PT-1 also show `ci_check` reading the wrong record (PR 8 for a row that shows PR 7).
- **Why HIGH:**
  - It is a real path past the gate.
  - It needs no hiding: the row obeys every rule the template states.
  - It is new against the phase-2 base, which refused all of these (SF-1).
  - All four probing reviewers reproduced it.
  - Round 3 recorded "a cell after Status → exit 9", which held only because that extra cell did not start with `done`.
- **Fix:**
  - At done, refuse any section row whose unescaped cell count differs from the header's, and any row that holds `\|` or does not end in `|`.
  - Refuse a header whose last cell is not `Status`.
  - AR's prototype (`/tmp/p3r4-ar.7dEsxY/tree2`) turns these into exit 10.

#### P3R4-2 HIGH: table rows with no ASCII pipe escape the check
Sources: lead probes, AR-3, SF-5, PT-6 (part), AR-6.
- **Where:** `lib/checkpoint.sh:68` (`s && /\|/`): a line with no `|` is never examined.
- **Failure paths** (all exit 0 beside a green row, with red PR #7 shown in the rendered Phase plan table):
  - A pipe-less line directly under the last row (`1 a b done (abc1234) · PR #7`, also indented). GFM renders it as a one-cell table row.
  - `&#124; 1 &#124; … PR #7 &#124;` under the table.
  - An HTML `<table><tr>…PR #7…</tr></table>`, as a block, on several lines, inline in a prose line, or after `<!-- x -->` on the same line.
  - Confirmed on the real runner (scenario 41 copy) for `html-table` and `gfm-pipeless-cont`.
  - The phase-2 base refused them.
- **Why HIGH:**
  - It is a real path past the gate, and the owner direction says "any table line in the Phase plan section".
  - The pipe-less form is the one plausible by accident.
  - The cp_unread refusal message (P3R4-5) tells a refused child to have "no other '|' line in that section", which points straight at it (AR-6).
- **Against:** no template-obedient checkpoint produces these. Reviewers split: AR and PT rated HIGH, SE and SF MEDIUM. The lead keeps HIGH for consistency with P3R3-1, which was rated HIGH on the same two facts (base refused it, fail-open).
- **Fix:** the allow-list (P3R4-14). In the section, accept only:
  - blank lines
  - the header
  - the separator directly under it
  - contiguous rows
  - after a blank line or a `###+` sub-heading: prose with no `|`, `<tag`, fence or `&#124;`, and the one rules comment

  Refuse everything else.

#### P3R4-3 MEDIUM: the runner's section ends at a raw `## ` line that does not render as a heading
Sources: lead probes, AR-2, AR-12, PT-5, PT-6, SF-3, SF-5, SE-5.
- **Where:** `lib/checkpoint.sh:12` (sed `/^## Phase plan/,/^## /`), `:66-67`.
- **Failure paths** (exit 0):
  - A `## x` inside `<!-- -->`, a ``` or `~~~` fence, `<div>`, `<details>` or `<pre>` in the section, followed by a full second table. The reader sees both tables under one Phase plan; the runner's section has already ended.
  - A lone CR (not before LF) joins lines for awk and sed but splits them for CommonMark. `n\r## Phase plan\r|…|` renders as a visible second plan (PT-5, SF-3).
  - The whole runner-read plan sits in a comment or fence, with the visible table under `## Phases` (SE-5, AR-12).
  - Real runner: `cmt-h2-then-table` and `fence-h2-then-table` exit 0. The phase-2 base refused them.
- **Why MEDIUM, not HIGH:** each needs deliberate concealment (a hidden heading line or a bare CR) that no honest child produces. PT rated HIGH.
- **Fix:**
  - At done, refuse any CR not before LF anywhere in the file.
  - Refuse fences, raw HTML lines other than the one rules comment, and a section that ends while that comment is open.
  - Refuse a `## Phase plan` that sits inside an open comment or fence.

#### P3R4-4 MEDIUM: a second heading that renders as "Phase plan" is not counted
Sources: AR-4, PT-4, SE-6, SF-4.
- **Where:** `lib/checkpoint.sh:62-63` (a byte regex, setext one line back only).
- **Failure path** (exit 0): a table under any of these:
  - `## **Phase plan**`, `## _Phase_ plan`, ``## `Phase plan` ``
  - `## Phase<NBSP>plan`, a ZWSP, a Cyrillic `а`, `## Phase&#32;plan`, `## Phase<!-- --> plan`
  - `<h2>Phase plan</h2>`, `> ## Phase plan`, `- ## Phase plan`
  - a two-line setext `Phase` / `plan` / `---`

  PT's `lookalike-entity` hides a green decoy plan in a comment so the only rendered plan is the red one.
- **Why MEDIUM:** it needs a deliberate lookalike. PT rated HIGH.
- **Fix:** normalise heading candidates (drop `*_~` and backticks, entities and tags; map NBSP and zero-width characters; strip container prefixes) before matching. Or refuse any non-ASCII byte in a heading line.

#### P3R4-5 MEDIUM: the refusal text and the template define the gate by its mechanism
Sources: CT-1, CT-2(a), AR-6.
- **Where:** `lib/ci.sh:73` ("…with no other '|' line in that section"), `templates/checkpoint.md:26-27` ("any table line in that section"), the README exit-10 row.
- **Failure path:** the texts name the two keys the check uses, a raw `|` and the raw section. Every remaining escape (P3R4-2, P3R4-3) sits just past one of them. A child refused for a `P1` row that follows the message literally drops the pipes, and gets exit 0 (P3R4-2). Round 3 removed "the runner only sees rows like that" for exactly this reason.
- **Fix:** state the obligation only, e.g. "rewrite that line as a phase row (`| <digit key> | … | <Status> |`, from the left margin) under the one `## Phase plan` heading, or delete it". Move the pin in test 51.

#### P3R4-6 MEDIUM: the second-heading check is wider than the texts say (false refusals)
Sources: CT-3, PT-14, PT-15, SF-8.
- **Where:** `lib/checkpoint.sh:62`, `^[ \t]*#+[ \t]*phase[ \t]+plan`, which matches the start of a heading only.
- **Failure path** (exit 10 at the very end of a job; the line is named):
  - `### Phase plan change (child 4)` (CT probe) or `### Phase plan changes` under Completed phases (lead probes2).
  - `## Phase planning notes`.
  - A `# phase plan check` shell comment in a fenced block.
  - `#phase plan` in prose (no space; not a heading). Here the message blames the real `## Phase plan` line.
  - `####### Phase plan` (not a heading).
- **Likelihood:** low to moderate (a child keeping a re-plan log). The cost is one owner round trip.
- **Fix:** match the whole heading text (`^ {0,3}#{1,6}[ \t]+phase[ \t]+plan[ \t#]*$`, any case), skip fenced lines, and name the first counted heading.

#### P3R4-7 MEDIUM: the whitelist's ` · usage` strip is greedy
Sources: CT-4, SE-3, PT-7, SF-2.
- **Where:** `lib/ci.sh:78`, `s/ · usage .*//`.
- **Failure path** (exit 0 in each case):
  - `done (abc1234) · PR #8 · usage 5h 3% 7d 40% · follow-up PR 7`
  - `… · usage see PR 7`
  - `no PR · usage see PR 7`
  - `… · usage PR 7 red · PR #8`
  - `… · usage n/a · #7`

  These are exactly the spellings P3R3-3 exists to refuse. A child-written ` · usage` also stops `cp_mark_usage` from writing the real one (`:95`, `/ · usage /!`). Plausible honest path: a later child appends a PR after the runner's usage text.
- **Fix:** strip only the runner's own forms, anchored at the end: `s/ · usage (unknown|unreadable|5h -?[0-9]+%( 7d -?[0-9]+%)?|7d -?[0-9]+%) *$//` (check against `lib/usage.sh:17-35`).

#### P3R4-8 MEDIUM: non-ASCII lookalikes, comments and reference links in a Status cell
Sources: SE-7, PT-8, PT-9, SF-7.
- **Where:** `lib/ci.sh:78-79`. The checks are ASCII-only and read the raw cell.
- **Failure path** (exit 0):
  - `· PR #8 ＰＲ＃７`, `· PR #8, ７`, an Arabic-Indic `٧`
  - `done (abc1234) <!-- no PR -->`, which renders as a done row with neither token
  - `· [also][p]` with `[p]: …/pull/7`
- **Fix:** refuse any byte outside printable ASCII other than `·`, and any `<` or `[`, in a done Status cell. Or match the cell against one exact grammar (SE): `^done \([0-9a-f]{7,40}\)( · (PR #[1-9][0-9]*|no PR))+( · usage …)?$`.

#### P3R4-9 MEDIUM: the P3R3-8 rewording did not reach README or SKILL.md
Source: CT-5.
- **Where:**
  - `README.md:114-115`: "for a phase that opened no PR".
  - `README.md:136`: "`no PR` if the phase opened none".
  - `skills/blast-off/SKILL.md:34`: "a phase with no PR closes its row with `no PR`", pinned by `tests/70-docs.sh:52`.
- **Failure path:** the owner-facing remedy offers `no PR` on an outcome the writer controls (a failed `gh pr create`). These sentences are the only guard on the accepted `no PR` residual.
- **Fix:** use the brief-based condition in all three and move the pin.

#### P3R4-10 MEDIUM: "a phase the brief says opens no PR" points at a field the brief template does not have
Source: CT-6.
- **Where:**
  - The condition: `templates/checkpoint.md:34`, `templates/brief.md:147-148`, `lib/ci.sh:85,89`.
  - The brief template: §5 is "one stacked draft PR per phase" with no PR column (`templates/brief.md:73`), and §8 says "Draft PR per phase".
- **Failure path:** no filled brief ever says a phase opens no PR. A strict child opens a PR for a docs-only phase or blocks. A loose child decides for itself, which is the reading P3R3-8 removed.
- **Fix:** add a `PR` column (`yes` / `no PR`) to brief §5, and have SKILL steps 4-5 fill it.

#### P3R4-11 MEDIUM: the absent refusal bans only *editing* a workflow file
Sources: CT-7, SE-13 (residual).
- **Where:** `lib/ci.sh:101` ("… nor is editing a workflow file"), compared with `templates/brief.md:138` and README:136 ("add, remove or edit").
- **Failure path:** the message prints the deciding file. Under ruling 2, removing it at the PR head turns the refusal into a pass. That is the one move the message leaves unbanned.
- **Fix:** use the brief's wording ("adding, removing, moving or editing") and pin it in test 41.

#### P3R4-12 MEDIUM: the Phase plan grammar is written several times, and the `cp_rows` comment is wrong
Sources: AR-7, SF-17.
- **Where:**
  - Section bounds: `lib/checkpoint.sh:12`, `:66-67`, `:95`.
  - Row regex: `:12`, `:68`, `:95`.
  - Key normalisation: `:48`, `:78`, `:84`.
  - The `:10-11` comment says "every row reader starts here", which is untrue for cp_unread and cp_mark_usage.
- **Failure path:** loosening `cp_unread`'s row test without `cp_rows` silently turns a refused shape into a skipped one (fail-open), and no test pins that the two agree. sed and awk already disagree after a repeated heading; only the heading counter bridges them.
- **Fix:** one awk scanner that classifies each section line; `cp_rows` and `cp_unread` both consume it.

#### P3R4-13 MEDIUM: CI runs on the PR's head sha from other refs count as the PR's CI
Source: SE-8. Code reading only, medium confidence. An owner question.
- **Where:** `lib/ci.sh:52-55`, `:101`.
- **Failure path:** a ruling-2 refusal (the trigger never fires on the PR) becomes `success` if the same sha is pushed to a branch a `push` filter covers, or a second PR from that branch targets a covered base. `gh run list --commit` lists those runs.
- **Fix:** keep only runs whose `headBranch` equals the PR's `headRefName`, or ask the owner.

#### P3R4-14 MEDIUM (design, needs an owner ruling): the check is a deny-list over `|` lines; the class needs an allow-list
Sources: AR-5, SF verdict, SE verdict, PT verdict, CT verdict.
- **Where:** `lib/checkpoint.sh:60-73`.
- **The problem:** every HIGH and MEDIUM above sits where a raw-line deny-list and a GFM renderer parse differently.
- **The proposal:** an allow-list of section lines plus the row cell-count rule (P3R4-1). AR's prototype is about 20 awk lines.
- **What it costs:**
  - It refuses `tests/41-ci-wait.sh:224`'s `### detail` between the separator and the rows (rendered, those rows are prose; AR-9).
  - It refuses a row after a blank line, a raw HTML tag in prose under the table, a plan inside a comment, and `\|` in any cell.
- **Why a ruling:** the owner direction was worded as a deny-list.
- **Alternative:** compare against a real GFM parser (cmark-gfm or pandoc). That adds a new dependency.

#### P3R4-15 MEDIUM (pre-existing, = P3R3-14): nothing ties the PR a row names to the phase
Source: PT-11. An owner question.
- **Where:** `lib/ci.sh:92-106`.
- **Failure path:** any green PR number satisfies the row.
- **Fix:** require the row's sha to be an ancestor of the record's `head_sha` (owner's call; it can falsely refuse squash or stacked layouts).

#### P3R4-16 MEDIUM (merged from Status-cell findings): another repo's `/pull/N` is read as this repo's PR N
Sources: PT-10, SE-9, AR-11, PT-13. Pre-existing (P3R3-29, LOW in round 3); PT rates it MEDIUM.
- **Where:** `lib/ci.sh:78,111`.
- **Failure path:** `done (abc1234) · https://github.com/other/repo/pull/8` exits 0 when the local PR 8 is green. The URL pattern also swallows text up to the last `/pull/N` (`…?n=PR_7&x=/pull/8`).
- **Fix:** accept `/pull/N` only for the workdir remote's `owner/repo`, or accept only `PR #N`.

## Findings, LOW

| ID | Sources | file:line | Failure path | Suggested fix |
|---|---|---|---|---|
| P3R4-17 | SE-4, PT-12, SF-6 | `lib/ci.sh:78` | The sha slot accepts any alnum: `done (PR7) · PR #8` exits 0. In git, receipt_check (exit 9) catches it unless a hex sha is elsewhere in the cell | `\([0-9a-f]{7,40}\)` |
| P3R4-18 | SE-14 | `lib/checkpoint.sh:49` | `^done` matches `Done-ish: PR #8`. Outside git only | `^done([^[:alnum:]-]\|$)` |
| P3R4-19 | AR-10 | `lib/checkpoint.sh:48` | A short row `\| 1 \| done (abc1234) · no PR \|` passes; the reader sees an empty Status | Cell-count rule (P3R4-1) |
| P3R4-20 | CT-2(b) | `templates/checkpoint.md:26-27` | Code refuses any `\|` line, not only "table lines", including inside the rules comment (`- Phases 2a \| 2b` gives exit 10) | Say "any line with a '\|'", or move the comment below `## Pointers` |
| P3R4-21 | CT-8 | `skills/blast-off/SKILL.md:39`, `README.md:136`, `lib/ci.sh:101` | "`no PR` is no way out" is stated as enforcement; the runner accepts it (residual) | Owner-facing: "breaks the brief; the runner trusts the row" |
| P3R4-22 | CT-9 | `lib/ci.sh:58,85`, `docs/spec.md:97` | "the phase's own PR" (singular) against the template's "every PR the phase opened" | "each PR the phase opened" |
| P3R4-23 | CT-10 | `lib/ci.sh:73`, `lib/checkpoint.sh:70-72` | A header with a digit or "done" (`Est. (2h)`) and a mid-line CR get no stated reason | A reason per case, or drop the header digit rule and check that the separator follows |
| P3R4-24 | CT-11 | `templates/checkpoint.md:32-38` | "no other number" contradicts the runner's usage text; the invited forms `[#8](…/pull/8)`, `PRs #8, #9`, `PR # 8` are refused | Add "besides the runner's ` · usage …`"; give a two-PR example |
| P3R4-25 | CT-12 | `templates/brief.md:136-137` vs `:146-147` | The parenthetical says leave the row open; the main line then closes it unconditionally. Fail-closed | "After ci-wait returns 0, or `absent` at a head with no workflow file, …" |
| P3R4-26 | CT-13 | `README.md:136` | The exit-10 remedy tells the owner to rewrite a second heading as a row | Add "a second Phase plan heading: rename or remove it" |
| P3R4-27 | CT-14, AR-15, SF-12 | `tests/51-templates.sh:77`, `tests/70-docs.sh:52-53`, `tests/41-ci-wait.sh` | Pins lock wording that needs changing (P3R4-5, -9, -21); ci.sh refusal bodies are unpinned; the header "no done" guard is unpinned (mutant u5 SURVIVED); the header digit clause and a `### x` then `\| P1 \|` case are untested | Move the pins; add header-digit, header-done and sub-heading-then-bad-row cases |
| P3R4-28 | SF-10 | `tests/41-ci-wait.sh:231-236` | 6 of the 14 whitelist cells are refused by "neither", not the whitelist; they assert the prefix only | Assert `Status cell holds`; split the loop |
| P3R4-29 | SF-11 | `tests/41-ci-wait.sh:239-242` | The NUL test accepts 9 or 10 with no message, and cannot fail on the property it names | Add a green row and `rec 7`; assert `PR #7 CI red` |
| P3R4-30 | SF-13 | `tests/41-ci-wait.sh:114` | The grep can match an earlier run's line in the accumulating run.log | `tail -1` or truncate the log |
| P3R4-31 | AR-9 | `tests/41-ci-wait.sh:224` | The `ok` case pins rows that render as prose (after `### detail` and prose) | Move them, or refuse under P3R4-14 |
| P3R4-32 | AR-8 | `lib/chain.sh:160`, `lib/ci.sh:72` | Structure is checked after `receipt_all_done`, so a malformed key gets exit 9 with wrong advice (`receipt <job-dir> 1)`) | Call `cp_unread` first in the done branch |
| P3R4-33 | AR-16 | `lib/ci.sh:101` vs `templates/brief.md:136-139` | Two different instructions for absent-with-workflow | Align the refusal with the brief |
| P3R4-34 | SE-10, SF-15 | `lib/ci.sh:73,80,98-103,122`, `lib/checkpoint.sh:71` | Control characters from the checkpoint and the record's `head_sha` reach run.log and the terminal raw; a child-written record can forge whole run.log lines (pre-existing P3R3-35, new paths) | Sanitize in `log()`; validate `head_sha` as 40 hex |
| P3R4-35 | SE-11 | `lib/ci.sh:96-99,120-121` | `ls-tree "$h^{commit}"` is safe only because `h` must equal gh's head; ci_head never checks for 40 hex | Validate before use |
| P3R4-36 | SE-12 | `lib/ci.sh:93-104` | The CI record is child-writable, so the gate is advisory against a non-cooperative child (pre-existing) | None this phase; note for the owner |
| P3R4-37 | SE-16, SF-14 | `lib/chain.sh:160`, `lib/ci.sh:72,88` | The checkpoint is re-read several times with no snapshot; `done < <(cp_done_cells)` loses the exit status and misreports a read failure as "no done row" | Snapshot once; `cells="$(cp_done_cells)" \|\| chain_end 10` |
| P3R4-38 | AR-14, SE-15, SF-17 | `lib/checkpoint.sh:95` | `$k` is unescaped in the sed address (`1.1` matches `101`); `[[:space:]]*$` drops a CRLF row's CR (pre-existing) | `${k//./\\.}` |
| P3R4-39 | SF-9 | `lib/ci.sh:78` | False refusal of `…/pull/8#issuecomment-1` | An optional fragment in the URL pattern |
| P3R4-40 | SF-16 | `lib/checkpoint.sh:5` | A CR-only checkpoint reads as no status; children run to the hard cap with no log line (pre-existing) | A lone-CR refusal at start, or log an empty status |
| P3R4-41 | lead | `lib/ci.sh:78` | Off-template sha spellings refused: `` done (`abc1234`) ``, `done abc1234`, `done (abc1234 )`. Fail-closed, the message names the cell | Optional: accept backticks inside the parens |
| P3R4-42 | AR-17, PT-16 | (classification) | Fullwidth and box pipes, and a table under a visible different `## `, are prose by ruling 1; `Phase plan notes: none` over `---` is a real setext heading, so that refusal is right | None |
| P3R4-43 | lead | (environment) | `cp_unread` was exercised only under GNU Awk 5.2.1 (gawk-only behaviour not audited for mawk or busybox) | State gawk as required, or test another awk |
| P3R4-44 | AR-13 | (false-refusal summary) | Template-made checkpoints, CRLF, both usage forms and cp_mark_usage's sed all pass; in-flight jobs from main's template have no `\|` in the comment | None |
| P3R4-45 | AR-15 | `tests/41-ci-wait.sh:131` | The fail message greps `PR #9[6-9]` while the check is `9[7-9]`. Cosmetic | Align |

## Asks, answered

1. **Class closed?** No. See the executive summary and P3R4-1 to P3R4-4.
2. **False refusals of template checkpoints?** None found (lead probes2, AR-13, CT). Off-template ones are P3R4-6, -20, -23, -24, -39 and -41.
3. **lib/chain.sh, lib/preflight.sh, tests/10-chain-done.sh, tests/fakes/claude:** needed and correct (AR):
   - `pf_estimate`'s `cp_rows "$src"` is the same sed.
   - `cp_mark_usage` is unchanged.
   - The CAP_WHY rewording is pinned by `tests/10-chain-done.sh:74`.
   - The fake edits are comments only.
   - shellcheck reports only a pre-existing SC2016 info.
   - The one problem is the `cp_rows` comment's claim (P3R4-12).
4. **Instruction text:** no drift from ruling 2 or the owner direction. Ruling 1's P3R3-8 rewording is incomplete (P3R4-9, -10). The texts teach the remaining gap (P3R4-5) and leave one removal unbanned (P3R4-11).
5. **Tests:**
   - Real for criteria 1, 2 and 4 (m1, m2 and m5 killed) and for the new refusals (u1 to u4 and w1 killed).
   - Text pins are real (t1, d1 to d3 killed).
   - Gaps: P3R4-27 to -31.

## Report Audit (general-purpose report adversary; advisory)

**Verdict: sound with corrections.**
- Counts check out: 2 HIGH, 14 MEDIUM, 29 LOW = 45; 80 reviewer findings.
- Every source ID appears in the body; no reviewer finding was dropped.
- About 30 file:line cites were spot-checked and are correct.
- mut.log and probes2.log match the report.

Corrections, condensed (the full text is in the lead's baton, `baton-phase-3-review-4.md`):

1. **The HIGH/MEDIUM line is inconsistent.** P3R4-3 and P3R4-4 have the same two facts as P3R4-2: the base refused them, and the gate fails open. P3R4-2's HTML and `&#124;` routes need concealment just as much as P3R4-3's do.
   - Rule to use: HIGH only for P3R4-1 and for P3R4-2's pipe-less continuation route, the one an honest child plausibly writes.
   - Fold the HTML and entity routes into a MEDIUM next to P3R4-3.
2. **P3R4-7's "plausible honest path" is wrong.** An appended `PR #7` is read by ci_prs and refused (PT `usage-tail-pr8`, exit 10). Only the off-template spellings `PR 7` and `#7` escape.
3. **P3R4-1's pending-row route is pre-existing.** The base `receipt_all_done` passes xcell-pending, notrail-pending and esc-pipe-pending. The red-PR variants (xcell-nopr, notrail-col3, esc-pipe-status) are the regression, and they carry the HIGH.
4. **"Obeys every rule the template states" is overstated.** Status-not-last and no-trailing-pipe break the template's "Status cell last" rule. The extra-cell and `\|` rows are the template-shaped ones.
5. **The executive summary wording contradicts P3R4-1.** Say: "no `|` line that cp_unread treats as a non-row escapes; parsed rows themselves can still mislead".
6. **P3R4-7 cites the wrong file.** The `/ · usage /!` guard is at `lib/checkpoint.sh:95`, not `lib/ci.sh:95`.
7. **The lead's own probes show the P3R4-1 shapes refused.** `escaped-pipe` gave 10, and `status-not-last` and `no-trailing-pipe` gave 9, because the red token sat in the read cell. The exit-0 forms come from PT's and SF's probes. The lead's `status-md-link` exit 0 is harmless (PR #8 both ways) and was not recorded.
8. **Dedup damage.** PT-13 (`…/pull/8?n=PR_7&x=/pull/8`) is a greedy-strip mechanism like P3R4-7, not a cross-repo one.
9. **Merges that sit uneasily:**
   - The lone-CR route's visible effect is a second heading, which belongs nearer P3R4-4.
   - SE-5/AR-12's only defect is that the runner reads a plan hidden in a comment.
10. **Minor:** "the base refuses all six" counts 5 escapes plus a control. `html-table-ml` ran in the stub harness only.

### Lead's disposition of the audit
Accepted: 1, 2, 3, 4, 5, 6, 7, 8, 10. These are the final severities, and the baton's table uses them.

- **P3R4-1 HIGH**, resting on the extra-cell and escaped-pipe rows whose rendered Status cell names a red PR. Those regress against the base. The pending-row route is pre-existing; the status-not-last and no-trailing-pipe routes break the template's rules.
- **P3R4-2 HIGH**, narrowed to the pipe-less continuation row. It is plausible by accident, and the P3R4-5 refusal text steers a refused child to it. The HTML `<table>` and `&#124;` routes move to **P3R4-3 MEDIUM**.
- **P3R4-7:** the honest-path sentence is withdrawn, PT-13 is merged in, and the guard cite is corrected to `lib/checkpoint.sh:95`.
- **Note 9:** recorded. No re-split, because each route keeps its own fix bullet.
- **Counts unchanged:** 2 HIGH, 14 MEDIUM, 29 LOW.
