---
source: runner
scope: br-1115-issues
parent_session: ""
---
# Pass-Baton: phase 3 review 3 (issue 26, last round): VERDICT ISSUES, gate green, 1 HIGH, criterion 3 met only in part

**Date:** 2026-11-16
**Scope:** br-1115-issues
**Branch:** feat/br-1115-issues/phase-3
**Worktree:** /home/alex/blast-off/.claude/worktrees/pending-items-53932d
**HEAD:** d43324d fix(phase-3): address review findings (iter 2), under the owner rulings

## Where things stand

**VERDICT: ISSUES.** The gate passed (exit 0, `GATE: PASS passed=18 failed=0 shellcheck=ok`). The synthesized review holds 0 CRITICAL, **1 HIGH**, 14 MEDIUM, 23 LOW (38 findings after dedup of 69 filed), and acceptance criteria 3 and 5 are met only in part. Two things block CLEAN: P3R3-1, and criterion 3 (which P3R3-1 and P3R3-3 leave short). This was the third and last allowed review round, so the next move is the owner's: allow one narrow fix for P3R3-1, or accept it as a known limit. No phase-exit digest was written (not CLEAN). Nothing is committed by this unit; no tracked file changed. Blocking state: waiting on the owner's decision about P3R3-1.

- Gate log: `baton-runner/br-1115-issues/gate-phase-3-iter-3/tests-run.log` (run once, alone, `BLAST_OFF_TEST_ONLY` unset).
- Review report: `baton-runner/br-1115-issues/review-phase-3-iter-3.md` (554 lines, with a `## Report Audit` at the end); per-reviewer reports, the shared brief and my probe and mutant files in `baton-runner/br-1115-issues/review-phase-3-iter-3/`.
- **ExecStart check: OK** before the gate, after it, after my mutant runs, after the reviewers and at the end: `ExecStart=/home/alex/blast-off/.worktrees/blast-off-build/bin/blast-off run %f`.

### The one HIGH, in plain words

A Phase plan row the runner's parser does not see is skipped by every gate. The parser takes only lines that start `|`, optional spaces, then a digit. A done row keyed `P1` or `**1**`, an indented row, or a row under a second `## Phase plan` heading is invisible. When it sits beside one readable done row, `done` ends exit 0 `job done` with that row's PR red, unread or absent, and `run.log` says `PRs read: none`. I reproduced it on the real runner (probes q1, q2, q3 in `review-phase-3-iter-3/unit-mutants.log`: exit 0 with a red `ci-pr-7.json` in the job). The phase-2 base read the whole file and refused the same checkpoint (exit 10; run on both trees by three reviewers, and I read phase-2's `ci_check`). `tests/41-ci-wait.sh:97,132` pins the skip as wanted. When every row is invisible the job is refused (q4: exit 10), so the hole needs a mixed table.

Why HIGH and not MEDIUM: it is a fail-open on the gate this phase exists to tighten, it is new against the base, and ruling 1 says "every done row". Against: only an off-template table reaches it (the template's rows are digit-keyed at the left margin). Reviewers split 3 HIGH (architect, silent-failure, penetration), 2 MEDIUM (security; critical-thinking filed the template side, CT-9). The synthesizer and the report audit both say HIGH. I went in leaning MEDIUM on reachability and changed my mind on two facts: the base refused it, and an indented table keeps every rule the template states (P3R3-5). The fix is small and stays inside ruling 1 (suggested fix in the table).

### How the review ran

The `Z0rd0nZords:zord-multi-agent-review` skill ran, inline in this unit (this unit is itself a subagent, so no orchestrator subagent was dispatched). Only the skill's command summary loaded, so the reviewer brief is mine: `review-phase-3-iter-3/brief.md` (target, both rulings as fixed facts, round 2's four HIGH and what the fix changed, the fail-open ask, the owner's severity levels, "report everything, do not be conservative"). Default roster: architect-reviewer, critical-thinking (given the instruction-text wording check), silent-failure-hunter, security-reviewer, penetration-tester; synthesizer knowledge-synthesizer (it read the skill's own consolidation rules, HIGH cap off); then the report adversary. The roster's agents are parked, so each ran as a general-purpose agent that read its parked definition read-only. No adversarial refutation stage (not asked for). Report audit verdict: "sound with corrections", 21 corrections, none changes the CRITICAL/HIGH count or a criterion status.

Test-run rule: kept. Both prohibitions went verbatim into every brief. Only silent-failure-hunter ran scenarios (12 single-scenario runs on its own /tmp copy, one at a time, after my own runs had ended); the others used stub probes or read only. Nobody deleted anything. Temp dirs left in place: `/tmp/p3r3-mut.C4bVdg`, `/tmp/p3r3-keep.58TMZW` (mine), `/tmp/p3r3-architect-reviewer.6KJ1sQ`, `/tmp/p3r3-pen.DzaelL`, `/tmp/p3r3-sec.JoNdB8`, `/tmp/p3r3-sfh.EaN615`. One slip to know: critical-thinking read two of its own persisted tool-output files under `~/.claude/projects/` (read-only; outside the brief's one read exception).

### What I verified myself (scenarios 41 and 51 only, on a /tmp copy with no `.git`, one run at a time)

- Baseline `PASS 41-ci-wait`, `PASS 51-templates`.
- 15 mutants, 13 KILLED: m1 absent+workflow refusal dropped (criterion 1), m2 absent pass not logged (criterion 2), m4 "both" refusal dropped, m5 dispatch filter dropped (criterion 4), m6 absent head check dropped, m7 pathspec narrowed to `ci.yml`, m9 PRs read from the whole table section (criterion 3), m10 whole row for the cell, t1 to t5 (template and brief sentences, scenario 51). 2 SURVIVED: m3 `no PR` matched case-sensitively, m8 stray check without `/pull/` (both fail-closed test gaps, P3R3-21).
- 39 probes on the real runner. Held: no table and all-invisible rows refused (exit 10); unrecognised done spellings, a missing trailing pipe and a cell after Status end exit 9; `No PR`, `NO PR`, `no pr`, `(no PR)` pass as `no PR`; `no  PR`, `no-PR`, `noPR`, `no PRs`, `none`, `PR #0`, `PR # 8` refused; both tokens refused; CRLF read correctly. Open: q1 to q3 (P3R3-1); `no PR, see PR 7` passes with PR 7 red (q13, q14: P3R3-3).

### Acceptance criteria

| # | Criterion | Status | Passing test |
|---|---|---|---|
| 1 | no runs + workflow file at the PR's head: exit 10 | met | `tests/41-ci-wait.sh:236-237`, `:243`, `:248`; m1, m7 killed |
| 2 | no runs + no workflow file at the PR's head: allowed, logged | met | `tests/41-ci-wait.sh:227-229`, `:233-234`; m2 killed. The child's path to it is unclear in the brief (P3R3-2) |
| 3 | PRs only from Status cells; prose never read; a done row with neither refused | **met in part** | Holds for rows the parser reads: `tests/41-ci-wait.sh:132`, `:160-162`, `:170-171`, `:177-190`. A done row the parser does not read is neither read nor refused (P3R3-1); a PR written without `#` passes beside a token or `no PR` (P3R3-3) |
| 4 | `workflow_dispatch` counts in neither direction | met | `tests/41-ci-wait.sh:76-83`, `:222-228`; m5 killed |
| 5 | tests for 1 to 4; spec, README, skill, templates state the rules | **met in part** | Tests are real; template text pinned at `tests/51-templates.sh:74-88`. Texts fall short (P3R3-2, -4, -5, -6, -16, -17); README, spec and skill wording unpinned (P3R3-7); one test pins the opposite of ruling 1 (P3R3-1) |

### Findings, MEDIUM and above (detail and evidence: the report's `#### P3R3-<n>` sections)

| ID | Severity | file:line | Failure path | Suggested fix |
|---|---|---|---|---|
| P3R3-1 | HIGH | `lib/checkpoint.sh:43`; `lib/ci.sh:70-84`; `tests/41-ci-wait.sh:97,132,134` | A done row the row filter drops (key `P1`, bold key, indented or tab-led row, no leading pipe, a row after a second `## Phase plan` line) beside one readable done row: every gate skips it; its PR is red or unread; exit 0. Phase-2 base: exit 10 | At `status: done` refuse when the `## Phase plan` section holds a table line that is not the header, the separator or a row the parser returned, and when the file has a second `## Phase plan` heading; name the line. Turn `41:97,132` into a refusal case |
| P3R3-2 | MEDIUM | `templates/brief.md:135-137,169-171`; `lib/ci.sh:45-46` | Brief step 4 has no instruction for `absent` with no workflow file (criterion 2's case), sets `status: blocked` at once where step 9 says only when nothing independent is left, and says "push once more" with nothing to push | Two sentences: with a workflow file, record it under Open or blocked and go on (step 9 decides the status); with none, close the row. Pin the qualifier in test 51 |
| P3R3-3 | MEDIUM | `lib/ci.sh:69,72-76,104` | The Status cell is checked by a blacklist, not a grammar. `PR 7 · no PR checks failed` counts as `no PR`; `PR #5, 7` drops PR 7; `PR #1,234` reads PR 1. Exit 0 with that PR red (q13, q14) | Whitelist: after `done (<sha>)` and before ` · usage`, accept only `PR #<n>` or `/pull/<n>` tokens, or exactly `no PR`; refuse anything else |
| P3R3-4 | MEDIUM | `templates/brief.md:135-137`; `skills/blast-off/SKILL.md:34-38`; `lib/ci.sh:94`; `README.md:127,134`; `docs/spec.md:97` | A PR no workflow can start on is refused (ruling 2) and no text gives an action: the child blocks, the owner is told to "ask the owner", the skill asks before launch and drops the answer. Fail-closed. One reviewer rated HIGH, called it borderline | Skill step 4: read the `on:` blocks, tell the owner before launch, record the choice in brief section 2. Say what the owner can change (PR base, trigger filter) and that `no PR` is not a way out |
| P3R3-5 | MEDIUM | `templates/checkpoint.md:24,33` | The template's only statement of what a row is leaves out what the parser needs (left margin, trailing pipe, Status last). An indented table keeps every stated rule and is unseen. Line 24 with line 33 says how a row leaves the gate | After P3R3-1's fix, state the row shape and that the runner refuses done while the table holds a line it cannot read |
| P3R3-6 | MEDIUM | `README.md:116,117,128`; `docs/spec.md:35,61,91,97`; `bin/blast-off:18,37`; `lib/chain.sh:96-98`; `lib/ci.sh:57-61`; `templates/checkpoint.md:30-33`; `tests/fakes/claude:17,32` | Twelve sentences untrue or in conflict: the exit 4 remedy, "no Phase plan table" for "no row the runner reads", all-open rows under exit 10, a settled owner question cited as open | Correct each in place, the exit 4 and exit 10 ones first |
| P3R3-7 | MEDIUM | `tests/51-templates.sh:74-88`; `tests/70-docs.sh:17-25,40-45` | The CI-record clause, the brief's workflow-file qualifier, all of skill step 4 and the README rule text can be cut with the gate green | Pin those; unpin or reword the mechanism sentence |
| P3R3-8 | MEDIUM | `templates/checkpoint.md:31`; `templates/brief.md:145-146`; `lib/ci.sh:74-76` | `no PR` is allowed "for a phase that opened no PR", an outcome the child controls: after a failed `gh pr create` that is true, and no CI is read | "Only for a phase whose brief row says it opens no PR; a PR that could not be opened is a blocked part" |
| P3R3-9 | MEDIUM | `templates/checkpoint.md:30-34`; `lib/ci.sh:71-73` | "the phase's own PR" (singular) with "name another PR in prose" sends a phase's second PR to prose, where it is never read | "names every PR the phase opened, each as `PR #<n>`; a PR that is not this job's goes in prose" |
| P3R3-10 | MEDIUM | `lib/ci.sh:75,82` | The no-done-row refusal offers `· no PR` with no condition; the "both" refusal lists dropping the PR as one of two equal moves. The audit would rate this LOW | Carry line 78's parentheses into line 82; line 75: "if the phase opened PR #<n>, delete `no PR`" |
| P3R3-11 | MEDIUM | `templates/brief.md:136`; `lib/ci.sh:94`; `README.md:118,134` | The texts name the pass condition (no workflow file at the PR's head) and no sentence forbids removing a workflow file to change a CI result | One line in the brief and beside "there is no override" |
| P3R3-12 | MEDIUM | `lib/chain.sh:94-109,160`; `lib/ci.sh:82` | A checkpoint with no row the runner reads cannot end `done`, yet the runner starts it and pays for up to 12 children | At start and in `preflight`, say so when `cp_phases` is 0 |
| P3R3-13 | MEDIUM | `lib/checkpoint.sh:11,43,51,57,69`; `lib/preflight.sh:77` | The row grammar is copied six times; a fix to P3R3-1 must reach each. Pre-existing | One `cp_rows` function |
| P3R3-14 | MEDIUM | `lib/ci.sh:85-88,110-116` | Nothing ties the PR a row names to the row: another green PR's number satisfies the gate. Pre-existing (P3R2-9) | Require the row's sha to be an ancestor of the record's `head_sha` |
| P3R3-15 | MEDIUM | `lib/ci.sh:20-33` | `ci-wait` re-lists runs once; a run listed later is never in the record. Pre-existing | At `done`, list the head's runs; an id missing from the record is unread |

### Findings, LOW

| ID | Severity | file:line | Failure path | Suggested fix |
|---|---|---|---|---|
| P3R3-16 | LOW | `README.md:114-119,134`; `lib/ci.sh:78` | A job started before this change is refused at `done` for each done row with no token; no child runs at `done`, so only the owner can edit; no product text says so. Fail-closed | One README line: write each done row's PR from the Completed-phases summary; `no PR` only where it names none |
| P3R3-17 | LOW | `README.md:114-119,134,143-144`; `bin/blast-off:37-38`; `docs/spec.md:21,35,228,230`; `templates/brief.md:124-125` | Stale or incomplete sentences (README omits the "both" and stray refusals) | Edit in place |
| P3R3-18 | LOW | `lib/ci.sh:86,89,92,112-115` | The record is read with no shape check (hand-written `success`, `pr: 7.0`, non-sha `head_sha`). Needs a hand-written record; pre-existing (P3R2-10) | One `jq -e` shape test at `done` |
| P3R3-19 | LOW | `lib/checkpoint.sh:44,59` | "Status cell" is whatever cell is last; a column after Status or an escaped pipe moves it. Mostly exit 9 | Refuse a done row whose cell count differs from the header's |
| P3R3-20 | LOW | `lib/ci.sh:92-94` | Any path under `.github/workflows` counts (`README.md`, `.gitkeep`); `2>/dev/null` hides why git failed. Fail-closed; owner question 3 not ruled | Count `*.yml`/`*.yaml` only, or say any file counts; keep git's stderr |
| P3R3-21 | LOW | `tests/41-ci-wait.sh:115,204,209` | Test gaps: m3, m8 and five of silent-failure-hunter's survive; loose assertions | Fixture cells `No PR`, `PR #8 see /pull/x`, `no PRs`; per-run log greps |
| P3R3-22 | LOW | `lib/ci.sh:91,93,94,96` | Refusal lines as instructions: assumes remote `origin`; push before a second `ci-wait` | Reword |
| P3R3-23 | LOW | `lib/ci.sh:92` | `git replace` makes `ls-tree` read another tree. On purpose only | `git --no-replace-objects` |
| P3R3-24 | LOW | `lib/ci.sh:95` | "no CI configured" says more than was read. The audit notes the phrase is ruling 2's own | Owner's call; log what was read |
| P3R3-25 | LOW | `lib/ci.sh:74-76,84` | A false `no PR` leaves no trace; a CI record no row names lies unused | Warn when a `ci-pr-*.json` exists that no row names |
| P3R3-26 | LOW | `templates/checkpoint.md:33`; `tests/51-templates.sh:78` | "It reads PRs nowhere else in this file" tells a child where the gate does not look, and is pinned. One reviewer rated MEDIUM | Say "another repo's PR"; drop the mechanism clause |
| P3R3-27 | LOW | `lib/ci.sh:70-81` | One refusal per run: five bad rows take five runs | Collect, refuse once |
| P3R3-28 | LOW | `lib/ci.sh:72-75` | `[#7](.../pull/7)` refused as a stray `#7` though the template allows the link. Fail-closed | Take a markdown link out as one token |
| P3R3-29 | LOW | `lib/ci.sh:104` | Another repo's `/pull/N` in a Status cell reads as this repo's PR N. Pre-existing (P3R1-30) | Accept `/pull/N` only for the workdir remote |
| P3R3-30 | LOW | `tests/fakes/claude:30-43` | `fin` masks no assertion; four couplings, stale comments | Fix the comments |
| P3R3-31 | LOW | `lib/ci.sh:72-82`; `lib/receipt.sh:68-71` | Exit 10 now means three unrelated things | Owner's call |
| P3R3-32 | LOW | `lib/ci.sh:72,81,104` | Statuses dropped on the read path (process substitution hides a failing `sed`/`awk`). Fail-closed today | Read `cp_done_cells` into a variable, `die` on failure |
| P3R3-33 | LOW | `lib/ci.sh:92` | In a partial clone `ls-tree` fetches with no time limit under the job lock | `timeout` around it |
| P3R3-34 | LOW | `lib/checkpoint.sh:52,60`; `lib/receipt.sh:50-51` | Duplicate keys: the receipt gate reads the first row for both. Pre-existing | Refuse a duplicated key at `done` |
| P3R3-35 | LOW | `lib/ci.sh:45,91,93,96,115` | Record `head_sha` and run names reach `run.log` raw. Pre-existing (P3R2-30) | Sha check; `@json` |
| P3R3-36 | LOW | `lib/ci.sh:36-43` | A `ci-wait` that dies part-way keeps the older record. Pre-existing | Remove the record at the start of `ci_wait` |
| P3R3-37 | LOW | `lib/ci.sh:21,26,113` | `BLAST_OFF_CI_*` not checked as numbers. Pre-existing | Validate as `chain_nums` does |
| P3R3-38 | LOW | `lib/ci.sh:113` | `timeout` without `-k`. Pre-existing | `timeout -k 5` |

Residuals of the rulings (not defects, full list in the report): an explicit `no PR` on a row that has a PR passes (ruling 1; pinned at `tests/41-ci-wait.sh:181-184`); a deleted row takes its PR with it; a head with no workflow file passes though its base has one (ruling 2); a head whose workflow cannot start on the PR is refused with no override (ruling 2, owner question 3 not ruled).

### Round-2 HIGH and MEDIUM: status

| ID | Status | Note |
|---|---|---|
| P3R2-1 (HIGH) | **reshaped** | Closed for rows the parser reads (`41:177-180`, `:192-198`). Open through an unread row (P3R3-1) and a PR without `#` (P3R3-3) |
| P3R2-2 (HIGH) | resolved | All five reviewers; `ci_prs` runs only on done cells; `41:186-190` |
| P3R2-3 (HIGH) | resolved | For the case named (`lib/ci.sh:89-95`, `41:227-256`). The neighbour case is ruling 2's; its text gap is P3R3-4 |
| P3R2-4 (HIGH) | resolved | Sentence gone, forbidden by `51:82`. Weaker residues: P3R3-5, -9, -10, -26 |
| P3R2-5, -7, -13, -14, -16, -19, -21 | resolved | Loose test on -5 (P3R3-21); a new two-way parse replaces -16's (P3R3-9) |
| P3R2-6, -12, -15, -17, -18, -20 | reshaped | -6: P3R3-3; -12 and -20: P3R3-1; -15: P3R3-6; -17: P3R3-4, -7; -18: P3R3-2 |
| P3R2-8 | out of scope by ruling | P3R3-20 |
| P3R2-9, -10, -11 | pre-existing, open | P3R3-14, P3R3-18; -11 not re-filed |
| P3R2-22 | open | Drift among the copies: P3R3-6, -17 |

### Things the task asked me to press on

- **A done row whose key has no digit:** it escapes the gate when it sits beside a readable done row (P3R3-1); alone, the job is refused.
- **No rows, no table:** refused, exit 10 (`41:160-168`, q4, q61).
- **Done marked a way the parser does not know:** exit 9, row reads as open (q6 to q9, q11, q12).
- **`no PR` on a row that plainly has a PR:** passes; that is ruling 1. `no PR` beside `PR #N` is refused; beside `PR 7` it passes (P3R3-3).
- **Case and spacing:** any case of both tokens is read; spacing variants are refused (fail-closed).
- **A live job started before this change:** refused at `done` until its rows are edited; the refusal line says what to write, but no README, spec or template line says so, and at `done` no child runs, so the edit is the owner's (P3R3-16).

### New dependencies and reliance

No new program. New reliance: the `event` field of `gh run list --json` (no gh version floor stated); `git ls-tree <sha>^{commit}` with the PR's head present in the workdir's repo (a head made elsewhere must be fetched first); the refusal's `git fetch origin pull/<n>/head` assumes a remote `origin`; GNU sed's `I` flag; `paste`, `grep -a`; the CI gate now rests on the row parser in `lib/checkpoint.sh` and on `TOP` set by `lib/chain.sh`; the fake `claude` now needs `git` and `jq`. One GitHub rule is taken from recall, not tested: with no workflow file at the PR's head no run was due.

## Next steps

1. Manager: put P3R3-1 to the owner. Recommendation: allow one narrow fix, because it is a few lines in `lib/ci.sh` `ci_check` (or a `cp_unread_rows` helper in `lib/checkpoint.sh`) plus turning `tests/41-ci-wait.sh:97,132` into a refusal case, and it closes criterion 3's main gap. The other choice is to accept it as a stated limit and file it as an issue; it then ships as a known fail-open for off-template tables.
2. If a fix is allowed, take P3R3-3 in the same change (same lines, whitelist grammar for the Status cell) and P3R3-5 (template row sentence). Then re-run `scripts/gate.sh` once, alone.
3. File the rest as follow-up issues: text fixes P3R3-2, -4, -6, -7 to -11, -16, -17; pre-existing P3R3-13 to -15.
4. Phase 4 (issue 22, `lib/chain.sh` child count) should not start from this branch as CLEAN; there is no `digest-phase-3.md`.

## Open questions / risks

- Owner: fix P3R3-1 now or accept it (above).
- Owner question 3 is still not ruled (which files count as a workflow file; an owner-held override). It is behind P3R3-4 and P3R3-20.
- The receipt-gate half of P3R3-1 rests on stub runs and reading: the real-runner probes ran outside git, where the receipt gate is off.
- The report audit lists 21 corrections to the synthesized report (for example its summary says every malformed record is refused, while P3R3-18 lists hand-written forms that pass). None changes the HIGH count.

## References

- Issue: z0rd0n88/blast-off issue 26; rulings `baton-runner/br-1115-issues/owner-rulings-phase-3.md`
- Gate log: `baton-runner/br-1115-issues/gate-phase-3-iter-3/tests-run.log`
- Review report: `baton-runner/br-1115-issues/review-phase-3-iter-3.md`; reviewer reports and brief: `baton-runner/br-1115-issues/review-phase-3-iter-3/`
- My probes and mutants: `baton-runner/br-1115-issues/review-phase-3-iter-3/unit-mutants.sh`, `unit-probes.txt`, `unit-mutants.log`
- Earlier batons: `baton-runner/br-1115-issues/baton-phase-3-fix-2.md`, `baton-phase-3-review-2.md`
- Code: `lib/ci.sh:68-105`, `lib/checkpoint.sh:42-47`, `templates/checkpoint.md:24-34`, `templates/brief.md:132-146`, `tests/41-ci-wait.sh:95-99,132,143-257`
