---
source: runner
scope: br-1115-issues
parent_session: ""
---
# Pass-Baton: phase 3 review 6 (issue 26, final round): ISSUES, one honest-slip HIGH (a copied PR number hides the phase's own PR)

**Date:** 2026-11-16
**Scope:** br-1115-issues
**Branch:** feat/br-1115-issues/phase-3
**Worktree:** /home/alex/blast-off/.claude/worktrees/pending-items-53932d
**HEAD:** c0517fb fix(phase-3): template names only PR #<n> or no PR; threat model stated (P3R5-8)
**Diff reviewed:** `git diff feat/br-1115-issues/phase-2...HEAD` (product paths only)

## VERDICT: ISSUES

- **Gate:** PASS. `GATE: PASS passed=18 failed=0 shellcheck=ok`, exit 0. Run once, nothing else running (`pgrep -af '[t]ests/run'` empty), `BLAST_OFF_TEST_ONLY` unset. Log: `baton-runner/br-1115-issues/gate-phase-3-iter-6/tests-run.log`.
- **ExecStart after the gate (and again after every scenario run):** `ExecStart=/home/alex/blast-off/.worktrees/blast-off-build/bin/blast-off run %f`. Intact.
- **Review:** `baton-runner/br-1115-issues/review-phase-3-iter-6.md`, zord-multi-agent-review, one-shot `spec` mode over all 19 changed product paths, `--yes`, no `--adversarial`, report audit on. An orchestrator subagent ran five reviewers (architect-reviewer, critical-thinking, silent-failure-hunter, security-reviewer, penetration-tester), each a general-purpose agent reading its parked definition read-only from `~/.claude/agents-parked/`; the orchestrator synthesized; a separate agent audited the report. Report `R6-n` = baton `P3R6-n`.
- **Reviewer test runs:** critical-thinking and penetration-tester each ran `BLAST_OFF_TEST_ONLY=41-ci-wait tests/run` twice, on their own /tmp copies, after `grep -c install_units` printed 0; all `GATE-ONLY: PASS`. The other three used standalone probes. Nobody ran the full suite, `scripts/gate.sh` or an `install_units` scenario.
- **What blocks CLEAN:** P3R6-1 (HIGH, honest-slip class (a)). Criterion 3 ("no checkpoint an honest child writes … can slip the gate") is not met. Criterion 5 is met only in part (P3R6-10: the threat model is not in SKILL.md).
- **Counts (in scope):** CRITICAL 0, HIGH 1, MEDIUM 12, LOW 23. Out of scope by ruling 3: 3 (no severity).
- **No HIGH (b):** checkpoints filled in exactly as templates/checkpoint.md, templates/brief.md step 4 and the README show (also CRLF, also with the runner's usage text) all exit 0 (41 `tp`, my probes, CT/PT probes).
- **No HIGH (c):** criteria 1, 2 and 4 held in every probe and every mutant below.

## Findings, MEDIUM and above

| ID | Severity | file:line | Failure path | Suggested fix |
|---|---|---|---|---|
| P3R6-1 | HIGH | lib/ci.sh:78-104, :123 (`sort -un` merges repeats); templates/checkpoint.md:35-40 | Honest slip (a): the child closes phase 1 by copying row 0's cell and changing only the sha, so both done rows say `PR #8`. Phase 1's own PR (#7, red, or never ci-waited) is named nowhere the gate reads. Phase 0's green record for PR #8 is still at its head, so done exits 0; run.log says only `PRs read: 8`. Reproduced by CT through the real `bin/blast-off run` and by SFH (exit 0). My own reproduction did not run (a broken probe insertion, see the criteria section). No run exercised receipts (the harness job is no git workdir); that the receipt check passes is reasoned from receipt.sh, which reads only the row's sha. New in this diff: before it the Completed-phases prose `PR #7` was read. **Why HIGH (a):** copying the row above and changing only the sha is a table edited by hand in an ordinary way, and it needs only a wrong number plus the phase's own PR red or never ci-waited. Unlike `no PR` on a red phase (a declaration ruling 1 trusts) the child declared a PR and the gate read a different one; unlike P3R6-4 it follows the template's table exactly. The cheap fix catches the copy only, not any wrong number. | Cheap: refuse (exit 10, naming both rows) one PR number in two done rows (brief §5: one stacked PR per phase). Structural: each named PR's record `head_sha` must have the row's sha as ancestor or equal (`git -C "$TOP" merge-base --is-ancestor`), failing closed when not local, as the absent branch does. Add a 41 case. |
| P3R6-2 | MEDIUM | lib/ci.sh:67-68, :90, :123; docs/spec.md:97 | A bare `/pull/N` from any repo or host, and a repo qualifier beside `PR #N` (`PR #8 (o/other)`, `acme/infra-pr#8`), are read as the workdir repo's PR N; exit 0 when that PR has a green record (all five reviewers; my probe: `https://github.com/o/other/pull/8` and `o/other/pull/8` exit 0, `PRs read: 8`). Needs a phase PR in another repo, which the runner does not support in any form (P3R6-3). | Stop reading `/pull/N` (it then refuses with the existing "write `PR #<n>`" advice), or accept only a URL whose owner/repo equals the workdir's `gh repo view --json nameWithOwner`; refuse `/` left in `rest`; anchor `(^|[^[:alnum:]])PR ?#`. Owner question P3R4-16. |
| P3R6-3 | MEDIUM | lib/ci.sh:18, :45, :129-134; templates/brief.md:134 | `ci-wait <job> N` records whatever PR N is in the workdir's repo (open, closed or merged) and logs no title, branch or state; the refusal prints that exact command, so a wrong or other-repo number gets a green record. This is the step that turns P3R6-1 and P3R6-2 into exit 0. | Read `state,headRefName,title` with `headRefOid`; log them; refuse a MERGED/CLOSED PR (job PRs are open drafts), or use P3R6-1's ancestor check. Say in the template that only the workdir repo's PRs are read. |
| P3R6-4 | MEDIUM | lib/checkpoint.sh:75-78; pinned by tests/41-ci-wait.sh:93-98 | A confused child adds phases under a new `## Added phases` heading with its own table; its red `PR #7` row is never read (exit 0, PT). The same under `###` refuses. Departs from the template ("one row per phase"), so not counted HIGH; borderline. | At done, refuse (read nothing) a table row outside the section whose last cell starts `done`, or a table whose header ends in Status. Reverses the 41:98 fixture: owner call. |
| P3R6-5 | MEDIUM | lib/checkpoint.sh:94; lib/chain.sh:160; lib/receipt.sh:62 | Mid-run, a `|` in a Done-when cell (`tests/run \| tail -1`) hides that row and all after it; P3R5-13 only logs. Hidden rows skip the "code changed after the receipt" exit 9 for good, and lose usage marks (AR). Regression from phase 2's reader. | Refuse instead of logging: call `ci_plan` at the loop head when status is not done (a fresh template has no unread line, 51). |
| P3R6-6 | MEDIUM | lib/ci.sh:90-95 | `no PR yet`, `no PR, blocked`, `no PR opened: push rejected` exit 0; the template says a PR that could not be opened is a blocked part. A PR opened later is never read. | In a `no PR` cell allow only `no PR`, usage, punctuation and blanks. |
| P3R6-7 | MEDIUM | lib/ci.sh:90-92 | A PR appended after the runner's ` · usage …` (`done (abc1234) · usage 5h 12% 7d 30% · PR #8`) exits 10 with a message quoting the usage text as the stray number; fails closed but invites editing runner text. (P3R5-15, raised.) | Strip the usage token wherever it sits, or say "PRs go before ` · usage`; never edit it". |
| P3R6-8 | MEDIUM | lib/ci.sh:90-92 vs lib/checkpoint.sh:50 | `done abc1234 · PR #8`, a backticked sha, `( abc1234 )`, `done<TAB>(…)` exit 10 blaming the sha as "a number the runner does not read"; the receipt reader accepts some of these. Fails closed. | Accept what `cp_row_sha` accepts, or name the `done (<sha>)` form in the message. |
| P3R6-9 | MEDIUM | lib/checkpoint.sh:50-55, :139; lib/ci.sh:87-93; lib/usage.sh:25 | The Status-cell grammar is in four places; no test runs `usage_read` output through `cp_mark_usage` into `ci_check`. A change in the usage text would refuse every honest done row. | One shared usage regex; one round-trip test. |
| P3R6-10 | MEDIUM | skills/blast-off/SKILL.md; tests/70-docs.sh:53-58; README.md:125-127; docs/spec.md:102-104 | Ruling 3 asks for the threat model in the spec and README, which have it (pinned in 70); the brief's criterion 5 also names "skill text and templates", which do not. A gap only under that wider reading. The "never slips the gate" sentence is contradicted by P3R6-1. | One threat-model sentence in SKILL.md (pinned in 70); keep the "never slips" claim true by closing P3R6-1. |
| P3R6-11 | MEDIUM | lib/ci.sh:41 (pre-existing line) | A record whose runs all concluded `skipped` (draft PRs with `if: draft == false` jobs) reads `success`; done passes with no job run. Not probed against GitHub. | Treat all-skipped like absent-with-workflow, or log "no job ran". |
| P3R6-12 | MEDIUM | lib/checkpoint.sh:50-51; lib/receipt.sh:70 | `✅ done (abc1234) · PR #7`, an NBSP-led cell, the whole cell in backticks, `**done**`: exit 9 "close it (run the gate …)", which sends the child to redo gate and receipt. Fails closed. | A Status cell holding the word `done` that is no done state → `bad()` (exit 10, naming the line, "start the cell with `done (<sha>)`"). |
| P3R6-13 | MEDIUM | lib/checkpoint.sh:36-40, :75; lib/ci.sh:101 | `## 2. Phase plan`, `##Phase plan`, `## 📋 Phase plan`, a table without outer pipes: exit 10 "no done row … add a `## Phase plan` table" while the table is there. Fails closed, misleads. | When no section is found, name any heading line that loosely contains "phase plan". |

## LOW findings
ID, location, problem; fixes are in the report.
- **P3R6-14** (lib/checkpoint.sh:43, :53): unpadded keys compare as numbers, so key `1` reads row `01`'s sha (fails closed, mostly exit 9). Fix: string compare.
- **P3R6-15** (lib/ci.sh:90, :123): `PR #0` is a token with no number; `PR #0 · no PR` exits 0 as `no PR`.
- **P3R6-16** (lib/ci.sh:108, :111, :132): the PR head from gh is not checked to be 40-hex before `git ls-tree` (fails closed).
- **P3R6-17** (lib/ci.sh:112): the fetch hint assumes `origin` is the PR's repo.
- **P3R6-18** (lib/checkpoint.sh:48): raw checkpoint lines go into run.log unescaped (control bytes).
- **P3R6-19** (lib/ci.sh:57 vs lib/chain.sh:157): the ci_plan comment says "before any other gate"; `receipt_check` runs first.
- **P3R6-20** (lib/checkpoint.sh:94): unclear message when a pipe in a cell changes the cell count.
- **P3R6-21** (templates/checkpoint.md:35): no example for a phase with two PRs; `PR #8/#9`, `PRs #8 and #9`, `PR #8, #9` refuse.
- **P3R6-22** (lib/ci.sh:87-92): `no PRs`, `✅`, NBSP, ZWSP, an em dash in a done cell refuse (fails closed).
- **P3R6-23** (lib/ci.sh:111-113, documented): any file under `.github/workflows` (`.gitkeep`, a README) counts as a workflow file.
- **P3R6-24** (lib/ci.sh:74-77): owner note under ruling 2: GitHub takes PR workflows from the merge ref, not the head.
- **P3R6-25** (lib/ci.sh:105-107): records written by the pre-diff ci_wait may hold workflow_dispatch runs; done cannot tell.
- **P3R6-26** (lib/ci.sh:129-134): a record is a snapshot by sha; a red re-run on the same head is not seen.
- **P3R6-27** (lib/ci.sh:36-43): a failed ci-wait leaves `ci-pr-N.json.tmp`; its error goes only to stderr.
- **P3R6-28** (lib/ci.sh:26): non-timeout `gh run watch` failures are discarded unlogged.
- **P3R6-29** (lib/checkpoint.sh:136): usage marking skips silently on a read failure (P3R5-25).
- **P3R6-30** (lib/ci.sh:87): the leading `!` reads a grep error as a clean cell (theoretical).
- **P3R6-31** (lib/ci.sh:53): `--limit 100` drops runs past 100 on one commit.
- **P3R6-32** (lib/ci.sh:123, :15): `PR #08` passes done but `ci-wait 08` exits 1; `PR #8a` reads as 8.
- **P3R6-33** (lib/checkpoint.sh:96): a deleted phase row is undetectable.
- **P3R6-34** (lib/ci.sh:18, :132): PR state is never read; a closed green PR passes (see P3R6-3).
- **P3R6-35** (P3R5-21 carried): an upper-case sha passes ci_check, receipt exits 9.
- **P3R6-36** (P3R5-17 carried): an awk operand shaped `name=value`.

## Out of scope by ruling 3 (no severity)
- Fence close keeps only the opener's first 3 characters (lib/checkpoint.sh:65, :67), so a ```` ```bash ```` line closes a ```` ``` ```` fence and 3 backticks close a 4-backtick fence (P3R5-4 family).
- Run-together PR words (`no PR, see pullrequest seven`) pass the word filter at lib/ci.sh:91.
- A hand-forged `ci-pr-8.json` with `head_sha: "null"` plus gh printing `{}` passes `ci_head` (lib/ci.sh:133). ci_wait never writes such a record.
- Round 5's P3R5-1 to P3R5-7, P3R5-14, P3R5-26, P3R5-29 stand as ruled.

## The bare `/pull/N` point (owner question P3R4-16)
- **Consistent with "the template names only `PR #<n>` or `no PR`"?** Not in practice. The template now says "(that form, not a link or URL)", and a Markdown link, an autolink and a `#fragment` URL refuse, yet a bare URL from any repo or host, a scheme-less `o/other/pull/8`, `/pull/8`, and `/pull/8/files` all pass. The reader accepts a form the template forbids, and the forbidden forms split on punctuation, not on meaning.
- **The compatibility reason is thin:** the phase-2 template taught `Add PR #<n> after it` for the Status cell; its `/pull/<n>` line was about naming PRs anywhere in the file. Only checkpoints made from the intermediate phase-3 template (never merged) were taught "or its /pull/<n> link".
- **Can it read another repo's PR as this repo's in an honest checkpoint?** Yes. My probe: `done (abc1234) · https://github.com/o/other/pull/8` and `done (abc1234) · o/other/pull/8` exit 0 with `PRs read: 8` (this repo's green PR 8). A link where the template says `PR #<n>` is a listed natural slip, but the exit 0 also needs a phase PR in another repo and this repo's PR with the same number not red. `PR #8` written for another repo's PR misreads the same way, so the root cause is P3R6-3 (the runner reads only the workdir's repo and never checks a PR belongs to the job), not the URL form. Rated MEDIUM (P3R6-2); HIGH if the owner runs jobs whose phases open PRs in other repos.
- **Recommendation:** stop reading `/pull/N` (a clear exit 10 with "write `PR #<n>`" costs an old checkpoint one edit), and close P3R6-1 with the ancestor check, which also catches the cross-repo collision.

## Status of P3R5-8 and the round-5 MEDIUMs
- **P3R5-8 (HIGH): CLOSED.** templates/checkpoint.md:35-36 names only `PR #<n>` "(that form, not a link or URL)" (pinned in 51); brief step 4 names only `PR #<n>`; link, autolink and fragment forms refuse with that advice (41:306-311). No false refusal of a template form found by anyone. The bare-URL leniency is P3R6-2.
- **P3R5-9: CLOSED** (41:231, "holds `\|`"; template says so).
- **P3R5-10: CLOSED** (41 `ok` case passes a `<sha>`/`<job-dir>`/`x<y` note; the after-table HTML refusal is gone).
- **P3R5-11: CLOSED** (41:250).
- **P3R5-12: CLOSED** (41:257).
- **P3R5-13: CLOSED as logging (41:253), but P3R6-5** shows logging leaves the receipt hole; refuse instead.
- **P3R5-14: OUT OF SCOPE** by ruling 3, as the fix baton recorded.

## Acceptance criteria and their tests
Mutants on /tmp copies (`/tmp/p3r6-mut.eJRX/<mutant>`, logs `/tmp/p3r6-mut.eJRX/<mutant>.log`, summary `/tmp/p3r6-mut.eJRX/result`), one scenario at a time, none calling `install_units`. Eight ran, eight KILLED; one did not apply.
- **Criterion 1: MET, test real.** tests/41-ci-wait.sh:346-347. Mutant `ac1-wf-allows` (lib/ci.sh:113 `[ -z "$wf" ] ||` → `true ||`): KILLED, "absent CI, workflow file at the PR's head: exit 0, want 10".
- **Criterion 2: MET, test real.** 41:337-339 (allowed and the log line checked). Mutant `ac2-nowf-refuses` (→ `false ||`): KILLED, "exit 10, want 0".
- **Criterion 3: NOT MET (P3R6-1).** The parts that hold are tested: neither-refusal 41:173-174, mutant `ac3-neither-ok` (ci.sh:97 → `true ||`) KILLED; prose never read 41:131, :159-161, :188-193, mutant `ac3-prose-read` (PRs read from the whole file) KILLED ("green records: exit 10"); allow-list 41:216-278, mutant `ac3-allowlist-off` (`bad()` a no-op) KILLED. My honest-slip probes (`/tmp/p3r6-probe.QLE0/probe.out`, 40 cases) found no other exit-0 slip than the cross-repo URL (P3R6-2). My P3R6-1 probe in `/tmp/p3r6-mut.eJRX/r61` did not run: its insert wrote to an unset `$M`, so 41 failed there (`GATE-ONLY: FAIL`); no result is claimed from it.
- **Criterion 4: MET, test real.** 41:77, :79. Mutant `ac4-dispatch-counts` (ci.sh:54 → `select(true)`): KILLED, "green dispatch run counted".
- **Criterion 5: MET for README, spec and templates; SKILL.md per P3R6-10.** Mutant `ac5-spec-threat` ("lazy or confused" → "careless" in docs/spec.md): KILLED by 70. Mutant `ac5-readme-nopr` (README `` `done (<sha>) · no PR` `` → `` `done (<sha>)` ``): KILLED by 70 (it SURVIVED in round 5, so P3R5-32 is closed). Mutant `ac5-template-link` (drop "(that form, not a link or URL)" from the template): NOT RUN, the sed did not apply because the phrase wraps across lines 35-36; the 51 pin for that sentence is at tests/51-templates.sh:82 (flattened text).
- After all runs: ExecStart unchanged; `git status --porcelain` in the worktree shows only untracked `baton-runner/` paths.

## New dependencies and reliance (for the owner's visibility)
- No new package or tool.
- POSIX awk (gawk and mawk agree, per round 5); GNU sed `-E` with the `I` flag in ci_check, as before.
- A local git object for each PR head (ruling 2): `git ls-tree` at `head_sha` in the workdir's repo; an unfetched head fails closed.
- `gh pr view` at done (`ci_head`) and in ci-wait, reading the workdir's repo only. New reliance worth naming: the gate trusts that every PR number in a Status cell is a PR of the workdir's repo opened by that phase (P3R6-1, -2, -3).

## Deviations
- This baton is at the contract path, not under `baton-pass/`, and no index was regenerated: containment comes first.
- Temp dirs created in this run, none deleted: `/tmp/p3r6-probe.QLE0` (my probes), `/tmp/p3r6-mut.*` (my mutants), the reviewers' `/tmp/p3r6-architect.PUJd`, `/tmp/p3r6-critical.N2Kd`, `/tmp/p3r6-silent.9PkP`, `/tmp/p3r6-security.wfMH`, `/tmp/p3r6-pentest.g12C`.
- The review report is not git-ignored; whether to commit it is the manager's call.

## Next steps
1. **Owner:** this was the last allowed round, so the loop stops at ISSUES. Decide: fix P3R6-1 (one more fix unit: refuse a PR number repeated across done rows, or the ancestor check, plus one 41 case), and rule on P3R4-16 (P3R6-2/-3) and P3R6-4 (reverses 41:98).
2. **Fix unit, if granted:** P3R6-1 first; then the cheap message/doc MEDIUMs (P3R6-6, -7, -8, -10, -12, -13) and P3R6-5 (call `ci_plan` mid-run).
3. Gate again with `scripts/gate.sh`, alone, and confirm ExecStart after.

## References
- Report: `baton-runner/br-1115-issues/review-phase-3-iter-6.md`
- Gate: `baton-runner/br-1115-issues/gate-phase-3-iter-6/tests-run.log`
- Rulings: `owner-rulings-phase-3.md`; history: `failure-phase-3.md`; previous: `baton-phase-3-review-5.md`, `baton-phase-3-fix-5.md`
- Issue: z0rd0n88/blast-off#26
- Code: `lib/ci.sh` `ci_check` (:78-119), `ci_prs` (:122-124); `lib/checkpoint.sh` `cp_scan` (:27-99)
