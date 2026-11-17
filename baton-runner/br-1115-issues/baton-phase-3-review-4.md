---
source: runner
scope: br-1115-issues
parent_session: ""
---
# Pass-Baton: phase 3 review 4 (issue 26): VERDICT ISSUES, gate green, 2 HIGH, P3R3-1 closed for its listed shapes but not as a class

**Date:** 2026-11-16
**Scope:** br-1115-issues
**Branch:** feat/br-1115-issues/phase-3
**Worktree:** /home/alex/blast-off/.claude/worktrees/pending-items-53932d
**HEAD:** e791f67 fix(phase-3): refuse done on any Phase plan line the parser does not read (P3R3-1)

## Where things stand

**VERDICT: ISSUES.**
- **Gate:** passed (exit 0, `GATE: PASS passed=18 failed=0 shellcheck=ok`).
- **Review:** the synthesized report holds 0 CRITICAL, **2 HIGH**, 14 MEDIUM and 29 LOW (45 IDs, deduplicated from 80 reviewer findings plus my probes).
- **Acceptance criterion 3 is not met.**
- **Blocking state:** P3R4-1 and P3R4-2 are open. This was review round 4, the first of the 3 rounds allowed after the reset, so the loop may go on to a fix.

Logs and records:
- Gate log: `baton-runner/br-1115-issues/gate-phase-3-iter-4/tests-run.log`. Run once, alone; `pgrep -af '[t]ests/run'` was empty and `BLAST_OFF_TEST_ONLY` unset.
- Review report: `baton-runner/br-1115-issues/review-phase-3-iter-4.md`. It ends with a `## Report Audit` and my disposition of it.
- My probes, mutants and the reviewer brief: `baton-runner/br-1115-issues/review-phase-3-iter-4/` (`probes.sh/.log`, `probes2.sh/.log`, `mut.sh/.log`, `brief.md`).
- **ExecStart check: OK**, checked after the gate, after my mutant runs and at the end: `ExecStart=/home/alex/blast-off/.worktrees/blast-off-build/bin/blast-off run %f`.

### The two HIGH findings, in plain words

1. **P3R4-1:**
   - A normal-looking phase row can show a red PR in its Status cell while the runner reads a different cell.
   - Two shapes do it: one extra cell after Status (GitHub hides cells past the header's count) and an escaped `\|` inside the Status cell (the renderer keeps it as one cell; awk splits it).
   - The runner reads the hidden or split-off cell, for example `done (abc1234) · no PR`, and `done` ends exit 0.
   - The row obeys every rule the template states (left margin, digit key, in the section), so `cp_unread` lets it through.
   - The phase-2 base refused these, because it read the whole file. Four reviewers reproduced it (AR-1, PT-1, PT-3, SE-1, SE-2, SF-1).
2. **P3R4-2:**
   - A line written with no pipes directly under the table, such as `1 a b done (abc1234) · PR #7`, shows on GitHub as a table row.
   - `cp_unread` never looks at lines without a `|`, so `done` ends exit 0 with PR #7 red.
   - Confirmed on the real runner (scenario 41 copy, `mut.log`: `PROBE gfm-pipeless-cont exit 0: … job done`). The base refused it.
   - The new refusal message tells a refused child "with no other '|' line in that section", which points straight at this escape (P3R4-5).

**What does hold:** the fix closes every shape round 3 listed: key `P1`, bold, indented, tab, NBSP, no leading pipe, a mid-line CR, and a plainly spelled second heading at any level or setext. No reviewer found a `|` line that `cp_unread` treats as a non-row and still lets through.

**False refusals:** no checkpoint the templates produce is refused. I checked the real `templates/checkpoint.md` with its comment verbatim, closed as brief step 4 says, with the runner's ` · usage` suffix, also as CRLF (`probes2.log`, all OK).

### How the review ran

- The `Z0rd0nZords:zord-multi-agent-review` skill was invoked: `spec <19 product paths> --write-to baton-runner/br-1115-issues/review-phase-3-iter-4.md --yes`. Only its command summary loaded. It ran inline, because this unit is itself a subagent.
- Roster: architect-reviewer, critical-thinking, silent-failure-hunter, security-reviewer and penetration-tester. **The roster's agents are parked, so each ran as a general-purpose agent that read its parked definition read-only.**
- The harness refused every subagent's report file, so the reviewers' findings exist only in their returned messages. The synthesized report carries all 80 under their source IDs.
- **Synthesis was done by me** in this unit, not by a knowledge-synthesizer agent, because a subagent could not write the file. I applied the skill's dedup rule with the HIGH cap off.
- A general-purpose report adversary audited the report: "sound with corrections", 10 corrections, 9 accepted.
  - It flagged an inconsistent HIGH/MEDIUM line. I fixed it: HIGH only for P3R4-1's template-shaped rows and P3R4-2's pipe-less row. The HTML-table and entity routes moved to MEDIUM P3R4-3.
  - It found the pending-row route of P3R4-1 is pre-existing, not a regression.
  - It found P3R4-7's "honest path" sentence was wrong (withdrawn).
- No adversarial refutation stage (not asked for).
- **Test-run rule kept:**
  - Every reviewer brief barred all scenarios and carried both prohibitions verbatim; no reviewer ran a scenario.
  - I ran the gate once, then scenarios 41, 51 and 70 one at a time on `/tmp/p3r4-mut.hYMZJn` (no `.git`; `install_units` count 0 in each).
- Nobody deleted anything.
- Temp dirs left:
  - Mine: `/tmp/p3r4-mut.hYMZJn`, `/tmp/p3r4-keep.BMbaTQ`, `/tmp/p3r4-base.uzRCXv`, `/tmp/p3r4-probe.wAS4wc`, `/tmp/p3r4-probe2.brr9Mb`.
  - The reviewers': `/tmp/p3r4-{ar,ct,sf,se,pt}.*`.
  - AR also ran my harness unchanged, so some `/tmp/p3r4-probe*.*` dirs are AR's.

### What I verified myself

- **Mutants** (scenarios 41, 51 and 70 on the copy): 12 of 13 KILLED.
  - u1: the `cp_unread` call dropped.
  - u2: the second-heading refusal dropped.
  - u3: the CR guard dropped.
  - u4: the header may be any later line.
  - w1: the P3R3-3 whitelist dropped.
  - m1: criterion 1's refusal dropped.
  - m2: criterion 2's log line dropped.
  - m5: criterion 4's dispatch filter dropped.
  - t1: a pipe put back in the template comment (scenario 51).
  - d1 to d3: the README and SKILL pins (scenario 70).
  - **u5 SURVIVED:** the header's "no done in last cell" guard is unpinned (P3R4-27).
- **Real-runner probes** appended to scenario 41:
  - Controls: green-only exit 0, red-row exit 10.
  - `html-table`, `cmt-h2-then-table`, `fence-h2-then-table` and `gfm-pipeless-cont` all exit 0.
- **Phase-2 base, same stub probes:** all five escape probes refused (exit 10, PR #7 red).
- Unit probe tooling ran under GNU Awk 5.2.1 only.

### Acceptance criteria

| # | Criterion | Status | Passing test |
|---|---|---|---|
| 1 | No runs + workflow file at the PR's head: exit 10 | met | `tests/41-ci-wait.sh:270` (absent, `.github/workflows/release.yaml` at head); m1 killed |
| 2 | No runs + no workflow file at the PR's head: allowed, logged | met | `tests/41-ci-wait.sh:262` (`no CI runs and no workflow file at its head … (no CI configured; absent, not a pass)`); m2 killed |
| 3 | PRs only from Status cells; prose never read; neither-token row refused; no Phase plan line escapes by its format | **not met** | Holds for the shapes at `tests/41-ci-wait.sh:198-222` (u1 to u4 killed) and the whitelist at `:230-` (w1 killed). Escapes: P3R4-1 (extra cell, `\|`) and P3R4-2 (pipe-less row), with HTML, comment, fence and lone-CR routes in P3R4-3 and lookalike headings in P3R4-4 |
| 4 | `workflow_dispatch` counts in neither direction | met | `tests/41-ci-wait.sh:29-34,73-83`; m5 killed |
| 5 | Tests and texts state the rules | met in part | Tests are real (mutants above; u5 survived). Text drift: P3R4-9 (README and SKILL still say "opened no PR"), P3R4-10 (a brief field that does not exist), P3R4-11 (refusal bans only editing a workflow file), P3R4-5 (texts teach the gap) |

### Findings, MEDIUM and above (detail and evidence: the report's `#### P3R4-<n>` sections)

| ID | Severity | file:line | Failure path | Suggested fix |
|---|---|---|---|---|
| P3R4-1 | HIGH | `lib/checkpoint.sh:48,68,85` | A digit-keyed row `\| 1 \| a \| b \| done (abc1234) · PR #7 \| done (abc1234) · no PR \|` (the extra cell is hidden on render), or the same with `\|` in the Status cell: the reader sees red PR #7, the runner reads `no PR`, exit 0. Base: exit 10. The pending-row variant is pre-existing | Refuse at done any section row whose unescaped cell count differs from the header's, that holds `\|`, or that does not end in `\|`; refuse a header whose last cell is not `Status` |
| P3R4-2 | HIGH | `lib/checkpoint.sh:68` | A pipe-less line under the table (`1 a b done (abc1234) · PR #7`) renders as a row and is never examined: exit 0 on the real runner. Base: exit 10. The P3R4-5 message steers a refused child to it | Allow-list (P3R4-14): only blank lines, header, separator and contiguous rows; prose only after a blank line or `###+` heading |
| P3R4-3 | MEDIUM | `lib/checkpoint.sh:12,66-68` | Concealed routes: an HTML `<table>` row or `&#124;` row in the section; a raw `## ` inside a comment, fence, `<div>`, `<details>` or `<pre>` ends the runner's section early; a lone CR splits lines only for the renderer; a plan read only inside a comment. Exit 0; base: exit 10 | Refuse fences, raw HTML other than the one rules comment, a lone CR anywhere, and a `## Phase plan` inside an open comment or fence |
| P3R4-4 | MEDIUM | `lib/checkpoint.sh:62-63` | A second heading that renders as "Phase plan" is not counted: `## **Phase plan**`, NBSP, ZWSP, `&#32;`, `<h2>`, `> ##`, `- ##`, a two-line setext. Exit 0 | Normalise heading text (markup, entities, Unicode spaces, container prefixes) before matching |
| P3R4-5 | MEDIUM | `lib/ci.sh:73`; `templates/checkpoint.md:26-27`; README exit-10 row | The texts define the gate by its mechanism ("no other '\|' line in that section", "table line in that section") and so mark the escape | State the obligation only; move the test-51 pin |
| P3R4-6 | MEDIUM | `lib/checkpoint.sh:62` | False refusal at the end of a job: `### Phase plan changes`, `## Phase planning notes`, `# phase plan` in a fenced block, `#phase plan` prose (which blames the real heading), `#######` | Match the whole heading text, `{1,6}` hashes with a space; skip fences; name the first counted heading |
| P3R4-7 | MEDIUM | `lib/ci.sh:78`; `lib/checkpoint.sh:95` | `s/ · usage .*//` exempts the rest of the cell: `· usage see PR 7` gives exit 0. The greedy URL strip hides `PR_7` (PT-13). A child-written ` · usage` also blocks the runner's own (`checkpoint.sh:95`) | Strip only the runner's exact usage forms, anchored at the end of the cell; anchor the URL pattern |
| P3R4-8 | MEDIUM | `lib/ci.sh:78-79` | Fullwidth or Arabic-Indic PR text, `<!-- no PR -->` in a cell (exit 0 with neither token visible), reference links to `/pull/7` | Refuse non-ASCII other than `·`, `<` and `[` in a done cell, or match one exact cell grammar |
| P3R4-9 | MEDIUM | `README.md:114-115,136`; `skills/blast-off/SKILL.md:34`; `tests/70-docs.sh:52` | P3R3-8's rewording missing: "`no PR` if the phase opened none" (the outcome rule) still in owner-facing text, and pinned | Use the brief-based condition; move the pin |
| P3R4-10 | MEDIUM | `templates/checkpoint.md:34`; `templates/brief.md:73,147-148`; `lib/ci.sh:85,89` | "a phase the brief says opens no PR": the brief template has no such field (§5 says one PR per phase) | Add a `PR` column to brief §5, filled by SKILL steps 4-5 |
| P3R4-11 | MEDIUM | `lib/ci.sh:101` | The absent refusal bans only *editing* a workflow file; removing it at the PR head is the ruling-2 pass condition | "adding, removing, moving or editing", as the brief says; pin it in test 41 |
| P3R4-12 | MEDIUM | `lib/checkpoint.sh:10-12,48,66-68,78,84,95` | The grammar is written several times; the `cp_rows` comment ("every row reader starts here") is untrue; a one-sided change fails open with no test | One scanner that both `cp_rows` and `cp_unread` consume |
| P3R4-13 | MEDIUM | `lib/ci.sh:52-55,101` | Runs of the PR's head sha from other refs (a push-filtered branch, a second PR) count as the PR's CI and turn a ruling-2 refusal into success. Code reading only | Filter runs by `headBranch` = the PR's `headRefName`, or ask the owner |
| P3R4-14 | MEDIUM | `lib/checkpoint.sh:60-73` | Design: a deny-list over `\|` lines cannot match a renderer; every HIGH and MEDIUM above sits in the gap. The owner direction is worded as a deny-list | Owner ruling on an allow-list of section lines plus the cell-count rule (AR prototype `/tmp/p3r4-ar.7dEsxY/tree2`); cost: refuses `### detail` between separator and rows (`tests/41-ci-wait.sh:224`), rows after a blank line, raw HTML in prose |
| P3R4-15 | MEDIUM | `lib/ci.sh:92-106` | Pre-existing (P3R3-14): any green PR number satisfies a row | Ancestry of the row sha in the record's head; owner's call |
| P3R4-16 | MEDIUM | `lib/ci.sh:78,111` | Pre-existing (P3R3-29): another repo's `/pull/N` is read as this repo's PR N | Accept `/pull/N` only for the workdir remote's `owner/repo` |

### Findings, LOW

P3R4-17 to P3R4-45 are in the report's LOW table, each with its file:line, failure path and fix:

- **Gate and parser:**
  - P3R4-17: the sha slot accepts any letters and digits.
  - P3R4-18: `^done` also matches `Done-ish`.
  - P3R4-19: a short row passes.
- **Instruction text:**
  - P3R4-20: the template under-states the refusal.
  - P3R4-21: "`no PR` is no way out" is stated as enforcement.
  - P3R4-22: singular "the phase's own PR".
  - P3R4-23: the refusal gives no reason for a header digit or a CR.
  - P3R4-24: Status-cell text contradictions and invited spellings that are refused.
  - P3R4-25: brief step 4 closes the row unconditionally.
  - P3R4-26: README has no remedy for a second heading.
- **Tests:**
  - P3R4-27: pins and gaps, including u5.
  - P3R4-28: whitelist cells that pass by "neither".
  - P3R4-29: the NUL test.
  - P3R4-30: the accumulating-log grep.
  - P3R4-31: the `ok` case pins rows that render as prose.
- **Runner:**
  - P3R4-32: structure is checked after `receipt_all_done`.
  - P3R4-33: two instructions for absent CI.
  - P3R4-34: control characters reach run.log.
  - P3R4-35: `head_sha` is not validated.
  - P3R4-36: the record is child-writable.
  - P3R4-37: no snapshot of the checkpoint; exit status lost.
  - P3R4-38: cp_mark_usage's regex key.
  - P3R4-39: a `#fragment` URL is refused.
  - P3R4-40: a CR-only checkpoint.
- **Lead's notes:**
  - P3R4-41: off-template sha spellings are refused.
  - P3R4-42: classification note.
  - P3R4-43: gawk only.
  - P3R4-44: false-refusal summary.
  - P3R4-45: a cosmetic test message.

### P3R3-1 and round 3's MEDIUMs: status

| ID | Status | Note |
|---|---|---|
| P3R3-1 (HIGH) | **reshaped** | Closed for every listed shape (u1 to u4 killed; probes). Open as a class: P3R4-1, P3R4-2 (HIGH), P3R4-3, P3R4-4 (MEDIUM) |
| P3R3-2 | resolved | Brief step 4 has both `absent` cases (pinned); residual P3R4-25 (LOW) |
| P3R3-3 | reshaped | Whitelist in place (w1 killed); holes P3R4-7, P3R4-8, P3R4-17 |
| P3R3-4 | resolved in text | SKILL step 4 and README; residual P3R4-11, P3R4-21 |
| P3R3-5 | resolved | Template states the row shape; but P3R4-5 (the text marks the gap) |
| P3R3-6 | mostly resolved | Remaining drift: P3R4-9, P3R4-22, P3R4-26 |
| P3R3-7 | resolved | t1, d1 to d3 killed; residual P3R4-27 |
| P3R3-8 | partly resolved | Template and brief done; README and SKILL not (P3R4-9); the brief field is missing (P3R4-10) |
| P3R3-9 | resolved in template | `lib/ci.sh` and spec still singular (P3R4-22) |
| P3R3-10 | resolved | — |
| P3R3-11 | partly resolved | Brief and README full ban; refusal message partial (P3R4-11) |
| P3R3-12 | resolved | CAP_WHY at start and in preflight, pinned in `tests/10-chain-done.sh:74` |
| P3R3-13 | partly resolved | `cp_rows` shared by 5 readers; `cp_unread` and `cp_mark_usage` separate (P3R4-12) |
| P3R3-14 | open, pre-existing | P3R4-15 |
| P3R3-15 | open, out of scope | Not re-filed |

### lib/chain.sh, lib/preflight.sh, tests/10-chain-done.sh, tests/fakes/claude

These changes are needed and correct:
- `pf_estimate` now calls `cp_rows "$src"`, which is the same sed as before, so there is no behaviour change.
- The CAP_WHY text in `lib/chain.sh` is pinned at `tests/10-chain-done.sh:74`.
- `tests/fakes/claude` changed in comments only.

The only issue is the `cp_rows` comment's claim (P3R4-12).

### New dependencies and reliance

- **No new program.**
- **New reliance:**
  - `cp_unread` relies on gawk behaviour; it was exercised only under GNU Awk 5.2.1 (P3R4-43).
  - The whitelist uses GNU sed `-E` with the `I` flag and bash `${x,,}`.
  - The done gate now rests on a raw-line model of Markdown that differs from GitHub's renderer (P3R4-14).
- **Fix options that would add one:** a GFM parser (cmark-gfm or pandoc), if the owner wants the renderer to be the oracle. Not recommended over the allow-list.

## Next steps

1. **Fix round (round 5 of 6):** close P3R4-1 and P3R4-2 in `lib/checkpoint.sh` `cp_unread`.
   - P3R4-1: a row cell count equal to the header's, no `\|`, a trailing `|`, and a header whose last cell is `Status`.
   - P3R4-2: refuse a non-blank line directly under the last row, or, under an owner ruling, adopt the allow-list (P3R4-14).
   - Add refusal cases to `tests/41-ci-wait.sh` for the extra cell, the `\|` Status cell and the pipe-less row.
2. Same change, same lines:
   - P3R4-5: reword `lib/ci.sh:73` and `templates/checkpoint.md:26-27` to state the obligation only; move the `tests/51-templates.sh:77` pin.
   - P3R4-7: anchor the usage strip at `lib/ci.sh:78`.
   - P3R4-11: the full workflow-file ban at `lib/ci.sh:101`.
3. **Owner:** P3R4-14 (allow-list ruling), P3R4-13 and P3R4-15 (CI-run and PR ancestry questions). Owner question 3 is still unruled.
4. **Then:** run `scripts/gate.sh` once, alone. Phase 4 (issue 22) must not start from this branch as CLEAN; there is no `digest-phase-3.md`.

## Open questions / risks

- **Whether P3R4-2 is HIGH is a judgement call.** AR and PT rated it HIGH, SE and SF MEDIUM. I kept HIGH on two grounds:
  - It regresses against the base, as P3R3-1 did.
  - The new refusal text steers a refused child to that very shape.
- P3R4-13 rests on code reading only.
- The report's reviewer findings exist only as synthesized entries, because the reviewers' own report files were refused by the harness.

## References

- Issue: z0rd0n88/blast-off issue 26. Rulings: `baton-runner/br-1115-issues/owner-rulings-phase-3.md`. Direction: `failure-phase-3.md` (Owner choice).
- Gate log: `baton-runner/br-1115-issues/gate-phase-3-iter-4/tests-run.log`
- Review report: `baton-runner/br-1115-issues/review-phase-3-iter-4.md`
- My probes and mutants: `baton-runner/br-1115-issues/review-phase-3-iter-4/` (`probes.log`, `probes2.log`, `mut.log`)
- Previous batons: `baton-phase-3-fix-3.md`, `baton-phase-3-review-3.md`
- Code: `lib/checkpoint.sh:10-73` (`cp_rows`, `cp_plan_rows`, `cp_unread`), `lib/ci.sh:69-107` (`ci_check`)
