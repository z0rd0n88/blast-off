# Review: phase 3 (issue 26), iteration 6 (final round)

Target: worktree `pending-items-53932d`, HEAD `c0517fb`, diff `feat/br-1115-issues/phase-2...HEAD`, product paths only (baton-runner/ ignored). Mode: `spec`, one-shot, read-only, `--yes`, no `--adversarial`, report audit on.

Roster ran as general-purpose agents reading parked definitions read-only from ~/.claude/agents-parked/; synthesis by the orchestrator.

Reviewers: architect-reviewer (AR), critical-thinking (CT), silent-failure-hunter (SFH), security-reviewer (SEC), penetration-tester (PT).

## Executive Summary

| Severity | Count |
|---|---|
| CRITICAL | 0 |
| HIGH | 1 |
| MEDIUM | 12 |
| LOW | 23 |
| Out of scope by ruling 3 | 3 (no severity) |

**Verdict: ISSUES.** One HIGH (a) survives: a done row can name another phase's PR number (a copy-pasted row, or an off-by-one), and the phase's own red or unread PR is never read. Two reviewers reproduced it independently, one through the real `bin/blast-off run`, exit 0.

**Recommended action:**
1. Fix R6-1 before the gate passes. The cheapest close is to refuse (exit 10) one PR number in two done rows. The structural close is to require each row's sha to be an ancestor of, or equal to, the PR record's `head_sha` (`git merge-base --is-ancestor`), failing closed when the head is not local. The structural check also narrows R6-2 and R6-3.
2. Owner decisions: R6-2 / R6-3 (the `/pull/N` and cross-repo question, P3R4-16), and R6-4 (a second phase table under another `##` heading, pinned on purpose by scenario 41:93-98).
3. The other MEDIUMs are fail-closed message problems or doc gaps; fix in the same pass where cheap.

Criteria 1, 2 and 4 held in every probe from every reviewer (absent + workflow file → 10; absent + none → 0 and logged; head not local → 10; `TOP` empty → 10; dispatch runs ignored both ways) (unprobed edge cases: R6-11 for criterion 1, R6-23 for criterion 2's definition of a workflow file, R6-25 for criterion 4). AR: criterion 3 mostly met (R6-2, R6-5, R6-6), criterion 5 mostly met (R6-10). No CRITICAL: no shell injection path (PR numbers reach gh/jq/filenames as digits only; done-row keys are checked against `[0-9A-Za-z._-]+`). No HIGH (b): template-exact checkpoints (filled in with sed, CRLF, no trailing newline, comment block kept) all exit 0.

## Test runs

- CT ran `BLAST_OFF_TEST_ONLY=41-ci-wait tests/run` twice, only on its own copy `/tmp/p3r6-critical.N2Kd/wt`, with probe blocks added after `passes()`; `grep -c install_units` printed 0 before each run; both runs `GATE-ONLY: PASS passed=1 failed=0 shellcheck=ok`.
- PT ran `BLAST_OFF_TEST_ONLY=41-ci-wait tests/run` twice, only on its own copy `/tmp/p3r6-pentest.g12C/wt` (a modified 41 made of stock lines 1-40 plus probes; `.git` pointer renamed so nothing reached the real repo); `grep -c install_units` printed 0 before each run; both `GATE-ONLY: PASS`.
- AR, SFH, SEC ran no scenario: standalone probes sourcing lib/*.sh in their own /tmp dirs.
- No reviewer ran `tests/run` unfiltered, `scripts/gate.sh`, or anything calling `install_units`. Nothing in the worktree was written by a reviewer.

## Critical

None.

## High

### R6-1. HIGH (a): a done row can name another phase's PR, so the phase's own red or unread PR is never read
- **Where:** lib/ci.sh:78-104 (`ci_check`), lib/ci.sh:123 (`ci_prs`, `sort -un` merges duplicates silently); template rule at templates/checkpoint.md:35-40.
- **Failure path (ran, exit 0):** two done rows both naming `PR #8` (CT: rows 0/1, `done (abc1234) · PR #8` and `done (def5678) · PR #8`, phase 1's real PR #7 red; SFH: rows 1/2, `abc1234`/`abc1235`, phase 2's real PR #9 red or never ci-waited). Result "job done", exit 0; run.log says only `CI at done: PRs read: 8; rows that say no PR: none`. (Reasoned; neither probe ran `receipt_check`:) receipt_check reads only the row's sha, so with valid receipts the real runner also exits 0 in a git workdir.
- **Why plausible:** brief §8 opens one stacked PR per phase, so each closing child types a new number. Copying the row above and changing only the sha is "a table edited by hand in an ordinary way"; the template itself says "replace an older sha". The earlier phase's green record, still at its current head, is what lets the copied number through. A child whose ci-wait was cut off, or who forgot to re-run it after a red-fix push, is refused under the right number but passes under the copied one.
- **Why new in this diff (SFH):** before it, ci_check read every `PR #N` in the file, so the Completed-phases summary (template line 57) would have caught the real PR; now only Status cells are read and nothing ties a cell's PR to its phase.
- **Fix:** cheap: refuse (exit 10) when one PR number appears in two done rows (brief §5: one stacked draft PR per phase). Structural: for each PR a row names, require that row's sha (`cp_row_sha`) to be an ancestor of, or equal to, the PR record's `head_sha` (`git -C "$TOP" merge-base --is-ancestor <row sha> <head>`), failing closed when the head is not local as the absent branch does; this still allows a PR legitimately shared by phases and also narrows R6-2/R6-3. Alternative: read `headRefName` in the same `gh pr view` and match the row's branch in brief §5. Add a scenario-41 case.
- **Raised by:** CT (#1, "HIGH (a), or MEDIUM if a wrong PR number does not count as a typo"), SFH (#1, HIGH).

## Medium

### R6-2. MEDIUM (HIGH (a) if a job may open PRs outside the workdir's repo): a bare `/pull/N`, or a repo qualifier beside `PR #N`, is read as this repo's PR N
- **Where:** lib/ci.sh:67-68 (comment), :90 (the `rest` strip of `https?://host/a/b/pull/N` and `/pull/N`), :91, :105-107, :123 (`ci_prs` reads `/pull/[0-9]+` and an unanchored `PR ?#`); docs/spec.md:97; templates/checkpoint.md:35-40; templates/brief.md:134 (step 4).
- **Failure path (all exit 0, reading this repo's green PR 8):** `done (abc1234) · https://github.com/o/other/pull/8`; `github.com/o/other/pull/8`; `o/other/pull/8`; `/pull/8`; `https://gitlab.example.com/grp/proj/pull/8` (any host); `.../pull/8/files`, `.../pull/8/checks`, `.../pull/8/` (while P3R5-8 refuses a fragment or link — inconsistent); `PR #8 (o/other)`; `PR #8 in o/other` / `PR #8 in other-repo`; `o/other PR #8`; `acme/infra-pr#8` (the unanchored `PR ?#` matches inside the repo name). `o/other#8` alone and `PR o/other#8` are refused (10). run.log shows only `PRs read: 8`, no trace of `o/other`.
- **Honest route:** a phase opens `o/other#8`; the child writes it; done refuses "CI unread … `blast-off ci-wait <job-dir> 8`"; the child runs exactly that (step 4 never mentions the optional workdir arg), which records this repo's PR 8 (open, closed or merged, e.g. an old merged green PR with a fixed head); `ci_head` matches; done exits 0. The other repo's PR is never read.
- **Severity reasoning:** needs a job whose phases open PRs outside the workdir's repo, and a PR with the same number in this repo whose head is not red (the honest child records it via the printed `ci-wait`). The URL forms are exactly the brief's (a)-listed "link where the template says `PR #<n>`" slip, so the only reason this is not HIGH is the multi-repo precondition. The spec (:97) and the ci.sh comment already say a PR "may be another repo's". CT and PT grade MEDIUM; AR, SFH and SEC grade MEDIUM, or HIGH (a) when jobs open PRs in another repo. Kept MEDIUM with that condition stated, as an owner call (P3R4-16).
- **Fix:** drop `/pull/[0-9]+` from both the strip (:90) and `ci_prs` (:123), so a URL refuses with the existing "write `PR #<n>`" advice (matches the template; old checkpoints pay one clear exit 10). If compatibility is wanted, accept only `https://github.com/<owner>/<repo>/pull/N` whose owner/repo equals `gh repo view --json nameWithOwner` in WORKDIR, refuse scheme-less and other-host forms. Either way: refuse any `/` left in `rest` so `owner/repo` cannot sit beside `PR #N`; anchor the token as `(^|[^[:alnum:]])PR ?#` in both places; optionally store `nameWithOwner` in ci-pr-N.json and compare in `ci_check`. R6-1's ancestor check closes the number-collision class too.
- **Raised by:** AR (F2), CT (#3), SFH (#2), SEC (F1), PT (F2).

### R6-3. MEDIUM: ci-wait records whatever PR N is in the workdir's repo, with no check that it is this job's PR; the templates cannot express a PR the phase opened in another repo
- **Where:** lib/ci.sh:18, :45, :93-132 (`ci_head` at :132 compares only the sha); templates/checkpoint.md:35-40; templates/brief.md:108, :134.
- **Failure path:** `blast-off ci-wait <job> 8` for a PR that lives elsewhere, or for a wrong number, records this repo's PR 8 (possibly old, merged, green). ci_wait logs only `ci PR #8 at <sha>: success (...)` — no title, branch or state — so nothing shows the mix-up. This is the step that turns R6-1 and R6-2 into exit 0. The template says "a PR that is not this job's goes in prose", but a phase's PR in another repo *is* the job's, so there is no correct way to write it. Related (SEC, fails closed): `ci-wait <job> N <other-workdir>` writes the same `gate-logs/ci-pr-N.json` with no repo field, so two repos' PR 8 overwrite each other and `ci_head` then refuses.
- **Fix:** read `state,headRefName,title` alongside `headRefOid`, log them in run.log and the record; refuse (exit 10) a MERGED or CLOSED PR (the brief says never merge, so job PRs are open drafts); or use R6-1's ancestor check. State in the template that blast-off reads PRs of the workdir's repo only and a phase PR in another repo is a blocked part; or record `nameWithOwner` and check it at done.
- **Raised by:** SFH (#3), PT (F3, from reading; not run), SEC (F1 "related" and step 3-4 of its path).

### R6-4. MEDIUM (borderline HIGH (a)): a second phase table under another level-2 heading is never read, so a red PR there passes
- **Where:** lib/checkpoint.sh:75-78 (the section ends at any `#`/`##` heading; nothing after it is checked). Pinned on purpose by tests/41-ci-wait.sh:93-98 (row `| 3 | ... | done (abc1234) · PR #97 |` under `## Decisions`; P3R1-15 / R-6).
- **Failure path (ran, PT row 98):** Phase plan row 0 `done (abc1234) · PR #8`, blank line, then `## Added phases` with the same header, separator and row `| 1 | a | b | done (abc1234) · PR #7 |` (PR 7 red) → exit 0. The same table under `### Added phases` → exit 10 (row 99): only the heading level decides. The extra phase also escapes `receipt_all_done` and the receipts.
- **Plausibility:** a confused child adding mid-job phases in a new section instead of extending the one table. The template says one row per phase, so this departs from it; if the owner counts it as "a table edited by hand in an ordinary way", it is HIGH (a). Owner call (it reverses a pinned fixture).
- **Fix:** at done (unread mode), refuse (not read) any pipe-table row outside the section whose last cell starts `done` (any case), or any table whose header ends in `Status`. Refusing reads no PR, so ruling 1 holds. The fixture at 41:98 would change.
- **Raised by:** PT (F1).

### R6-5. MEDIUM: rows hidden mid-run lose the receipt check (extends P3R5-13; a regression from phase 2)
- **Where:** lib/checkpoint.sh:16-22, :94 (`st = 3` stops reading), :136; lib/chain.sh:100, :160 (the P3R5-13 fix only logs); lib/receipt.sh:50, :62.
- **Failure path (probed, AR `/tmp/p3r6-architect.PUJd/mid.md`):** 4 rows; row 1's Done-when cell is `` `tests/run | tail -1` says GATE: PASS `` (a shell pipe in an acceptance cell, a natural slip). `cp_scan done` prints only `0`, `open` nothing, row count 1 (soft cap 3); `unread` names line 7. The phase-2 reader prints done `0 1 2`, open `3`, phases `4`, so the drop is new. Consequences (reasoned from receipt.sh:62): (i) a row closed while hidden, with code committed after the receipt, never gets the D4-1 "code changed after it" exit 9 — once the line is fixed, the next run's pre-child `rows` snapshot already holds that row, so the diff is skipped for good; (ii) a child that fixes the line mid-run makes every previously hidden row count as closed by it, giving a false exit 9 that clears on re-run; (iii) ` · usage` marks for hidden rows are lost.
- **Fix:** refuse instead of logging: at the loop head, when status is not done, call `ci_plan` (exit 10, status unchanged), or call it after each child. A fresh template has no unread line (scenario 51), so nothing honest is refused earlier than at done.
- **Raised by:** AR (F1).

### R6-6. MEDIUM: free text after `no PR` is accepted, including text saying a PR is still to come or is blocked
- **Where:** lib/ci.sh:90-95.
- **Failure path (ran/probed, exit 0):** `done (abc1234) · no PR yet`; `no PR, CI red`; `no PR opened: push rejected`; `no PR, blocked`; (fine: `no PR needed`, `no PR (docs only)`). `no PR (gh pr create failed, ...)` is refused only by accident because it contains "pr". The whitelist bans only digits, `#` and the word PR. templates/checkpoint.md:36-37 says "a PR that could not be opened is a blocked part, not `no PR`". Path to an unread PR (CT): close as `no PR yet`, open the PR later; the row is never revisited and the PR's CI never read.
- **Not HIGH:** no PR is named, and ruling 1 trusts `no PR` (SEC). Plain `no PR` on a phase with a real red PR also passes, a direct consequence of ruling 1 (noted, not a finding). Only the absent-case refusal message says "`no PR` is no way out"; the red and unread messages do not.
- **Fix:** in a `no PR` cell allow only `no PR` plus usage, punctuation and blanks (no letters/digits left), or refuse `yet`/`later`/`pending`/`todo`/`blocked`. Optionally refuse a `no PR` row unless the same row's Done-when cell (copied from brief §5) also says `no PR`.
- **Raised by:** SEC (F2, MEDIUM), CT (#2, MEDIUM), AR (F4, LOW). Highest kept.

### R6-7. MEDIUM: a PR written after the runner's ` · usage …` suffix is refused, and the message blames the runner's own text
- **Where:** lib/ci.sh:90-92 (usage stripped only at end of cell, `[[:space:]]*$`); lib/checkpoint.sh:135-141 (appends it once).
- **Failure path (ran, exit 10):** a row closed as `done (abc1234)` without a PR gets ` · usage 5h 12% 7d 30%` at child end; the repairer appends the PR: `done (abc1234) · usage 5h 12% 7d 30% · PR #8` → exit 10, "holds ' · usage 5h 12% 7d 30% ·  ' beside done … a number or PR the runner does not read". Also `done (abc1234) · PR #8 · usage 5h 40% 7d 10% · PR #5` (SFH) and `… · usage 5h 3% 7d 40% · PR #18` (PT row 50). The message invites deleting the usage text, which the template says never to edit and which the preflight estimate reads.
- **Fix:** strip one ` · usage <figure>` `·`-delimited token wherever it sits, or say in the message "put PRs before ` · usage`; never edit it".
- **Raised by:** CT (#5, MEDIUM), SFH (#5, MEDIUM), PT (F6, LOW), SEC (carried from round 5).

### R6-8. MEDIUM: natural sha-format slips are refused with a message that blames the sha (fails closed; the two sha readers disagree)
- **Where:** lib/ci.sh:90-92 (`^done *`, sha only in parens right after `done`) versus lib/checkpoint.sh:50 (`/^done([ \t(]|$)/`, any 7-40 hex word).
- **Failure path (ran, all exit 10):** `done abc1234 · PR #8` ("holds 'abc1234 ·  ' … a number or PR the runner does not read" — the receipt reader accepts that sha); `` done (`abc1234`) · PR #8 ``; `done ( abc1234 ) · PR #8`; `done (abc1234 ) · PR #8`; `done (abc1234, PR #8)` ("holds '(abc1234, ) '"); `done<TAB>(abc1234) · PR #8` (quotes `(abc1234)` as stray).
- **Fix:** accept `done`, optional `(`, optional backtick, the sha, optional backtick, optional `)` with `[[:blank:]]*` around, matching what `cp_row_sha` accepts; or name the sha form in the message ("the sha goes as `done (<sha>)`").
- **Raised by:** CT (#6, MEDIUM), SEC (F5, LOW), SFH (#11, LOW), AR (F3 failure path), PT (F7, rows 44 and 46, LOW). Highest kept.

### R6-9. MEDIUM (maintainability): the Status-cell grammar lives in four places, and the usage format round-trip is untested
- **Where:** cp_scan lib/checkpoint.sh:50-55 (done detection, key, sha = first 7-40 hex word anywhere); ci_check lib/ci.sh:87-93 (sha only in parens after done, usage regex, PR tokens, `no PR`, whitelist); writer `cp_mark_usage` lib/checkpoint.sh:139; format source `usage_read` lib/usage.sh:25.
- **Failure path:** today the sha readers disagree (R6-8). Latent: any change to `usage_read`'s text (another window, a non-integer figure) would refuse every honest done row at done (exit 10). No test runs `usage_read` output through `cp_mark_usage` then `ci_check`; scenario 41 hand-writes usage strings at :185 and :290.
- **Fix:** have cp_scan's `cells` mode emit parsed parts (sha, PR tokens, remainder with usage removed); at least keep the usage regex in one shared variable used by `cp_mark_usage` and `ci_check`; add one round-trip test.
- **Raised by:** AR (F3).

### R6-10. MEDIUM: criterion 5 only partly met — the threat model is absent from SKILL.md and the templates, and the "never slips" claim overreaches
- **Where:** skills/blast-off/SKILL.md, templates/checkpoint.md, templates/brief.md; tests/70-docs.sh:53-58; README.md:123-127, docs/spec.md:99-104.
- **Gap:** criterion 5 names "the spec, README, skill text and templates". Grep finds the threat model only in README.md:123-127 and docs/spec.md:99-104 ("lazy or confused", "malicious", "ruling 3", "bypass" all absent elsewhere); 70-docs checks only README and spec. README:125-127 and spec:102-104 claim a template-following checkpoint "never slips the gate"; R6-1 is a hand-edit slip that does.
- **Fix:** one sentence on the threat model in SKILL.md (near step 4's delivery text) and arguably in the rules comment of templates/checkpoint.md (AR: child-facing templates arguably need not carry it); have 70-docs check them; narrow the "never slips" claim or close R6-1.
- **Raised by:** CT (#4, MEDIUM), AR (F9, LOW). Highest kept.

### R6-11. MEDIUM (pre-existing line, bears on criterion 1): a record whose runs all concluded `skipped` is `success`
- **Where:** lib/ci.sh:41.
- **Failure path:** the brief mandates `gh pr create --draft`; repos commonly gate jobs with `if: github.event.pull_request.draft == false`. Whether GitHub reports that as `skipped` or as `success` with skipped jobs, the gate reads only run-level conclusions, so every phase can pass done with no test run though the head has a workflow file. Not probed against real GitHub.
- **Not HIGH (c):** pre-existing line outside this diff, and not probed against GitHub.
- **Fix:** treat an all-`skipped` record like absent-with-workflow (refuse), or log it loudly as "no job ran".
- **Raised by:** SFH (#4).

### R6-12. MEDIUM: a done cell that does not start with `done` exits 9 with a misleading message
- **Where:** lib/checkpoint.sh:50-51 (no unread message unless the cell starts with "done"); lib/receipt.sh:70.
- **Failure path (ran):** `✅ done (abc1234) · PR #7` → exit 9 (PT row 41); a Status cell led by an NBSP → exit 9 (row 85). The message "phase row 0 is not done; close it (run the gate on HEAD…, blast-off receipt…)" sends the child to re-run gate and receipt instead of fixing the cell. Children often decorate status cells with emoji. (Extends the lead's `**done**` → 9.)
- **Fix:** in emit, a Status cell containing the word `done` (any case) that is no done state → `bad()` with "start the Status cell with `done (<sha>)`" (exit 10, naming the line).
- **Raised by:** PT (F4).

### R6-13. MEDIUM: a numbered or unrecognised Phase plan heading gets a misleading "no done row" refusal
- **Where:** lib/checkpoint.sh:36-40, :75; message at lib/ci.sh:101.
- **Failure path (ran, each exit 10 with "the Phase plan has no done row … add a `## Phase plan` table"):** `## 2. Phase plan` (PT row 88); `##Phase plan` (89); `## 📋 Phase plan` (94); a setext main heading (97); a GFM table without outer pipes (75 — its `# | Phase | ...` header parses as an H1 and ends the section). The table is there; the unrecognised line is never named. templates/brief.md numbers its `##` sections (`## 9. Child protocol`), so a numbered checkpoint heading is a natural slip.
- **Fix:** when no section is found, name any heading line whose text loosely contains "phase plan" in the refusal.
- **Raised by:** PT (F5: MEDIUM for the numbered heading, LOW for the rest).

## Low

### R6-14. LOW: an unpadded key is compared as a number, so key `1` can read row `01`'s sha
- **Where:** lib/checkpoint.sh:43, :53 (`ck == ENVIRON["CP_KEY"]`). New in this diff.
- **Failure path (probed):** rows `|01|a|done (aaaaaaa) · no PR|` and `|1|b|done (bbbbbbb) · no PR|`: `CP_KEY=1 cp_scan sha` returns `aaaaaaa`; `cp_scan unread` says nothing. With padded cells (`| 1 |`) the comparison is by string and correct. `receipt_check` then checks row 1 against row 01's sha, mostly exit 9 (fails closed).
- **Fix:** force string comparison: `ck "" == ENVIRON["CP_KEY"] ""`.
- **Raised by:** SEC (F3).

### R6-15. LOW: `PR #0` is a PR token that yields no number
- **Where:** lib/ci.sh:90, :123 (`s/^0*//; /^$/d`).
- **Failure path (probed):** `done (abc1234) · PR #0 · no PR` → exit 0, read as `no PR` instead of the "both" refusal; `· PR #8 PR #0` and `· PR #8 · PR #00` → exit 0 with #0 dropped; `· PR #0` alone → exit 10 with "says neither `PR #<n>` nor `no PR`" (untrue as worded). No real PR hidden.
- **Fix:** refuse `PR #0+` explicitly ("PR #0 is no PR number").
- **Raised by:** SEC (F4), SFH (#10).

### R6-16. LOW: the PR head from `gh` is not checked to be 40-hex before `git ls-tree`
- **Where:** lib/ci.sh:108, :111, :132.
- **Detail:** `h` must equal `gh pr view`'s `headRefOid`, never checked to be hex; an option-like value fails closed (probed: git rc 129, refusal).
- **Fix (defence in depth):** `[[ $h =~ ^[0-9a-f]{40}$ ]]` before `git ls-tree` (and see the ruling-3 note on `ci_head` at :133).
- **Raised by:** SEC (F6).

### R6-17. LOW: the fetch hint assumes `origin` is the PR's repo
- **Where:** lib/ci.sh:112.
- **Detail:** `git -C $TOP fetch origin pull/$pr/head` fetches nothing, or another repo's PR N ref, in a fork layout. Cannot cause a false pass (lookup is by sha); misleading hint on a fail-closed path.
- **Fix:** name the head sha and say to fetch it from the remote the PR lives on.
- **Raised by:** SEC (F7).

### R6-18. LOW (pre-existing in spirit): raw checkpoint lines go into run.log and the journal
- **Where:** lib/checkpoint.sh:48 (`bad()`); only CR is escaped, so ESC and other control bytes are logged as-is.
- **Fix:** `gsub(/[[:cntrl:]]/, "?", t)`.
- **Raised by:** SEC (F8).

### R6-19. LOW: the ci_plan comment is wrong about order
- **Where:** lib/ci.sh:57 says "at status done, before any other gate", but `receipt_check` runs first at the loop head (lib/chain.sh:157), on the partial row set; an exit 9 on a visible row comes before the exit 10 for an unread line.
- **Fix:** correct the comment, or move `ci_plan` ahead of `receipt_check` at status done.
- **Raised by:** AR (F5).

### R6-20. LOW: unclear message when a pipe inside a cell changes the cell count
- **Where:** lib/checkpoint.sh:94. The `mid.md` row gives "is no phase row … with the header's 4 cells"; to the child it looks like a phase row.
- CT: a note with a backticked `a|b` exits 10 (documented).
- **Fix:** when `row(s)` is true but `cn != hc`, say "has N cells, the header M: a `|` inside a cell, even in backticks, splits it".
- **Raised by:** AR (F6).

### R6-21. LOW: no template example for a phase with two PRs; some natural joins are refused
- **Where:** templates/checkpoint.md:35.
- **Failure path:** rc 10: `PR #8/#9`, `PRs #8 and #9`, `PR #8, #9`, `PR #8 #18` (PT row 54). Exit 0: `PR #8 · PR #9`, `PR #8, PR #18`, `PR #8 and PR #18`, `PR #8 / PR #18` (PT rows 5-8).
- **Fix:** add the example `done (<sha>) · PR #8 · PR #9`.
- **Raised by:** AR (F7); PT rows.

### R6-22. LOW: ordinary wording, non-ASCII decoration and invisible characters in a done cell are refused (fails closed; messages name the text)
- **Where:** lib/ci.sh:87-92 (refuses any digit, `#`, or the word pr/prs/pull); lib/checkpoint.sh:43-44, :81.
- **Failure path (exit 10):** `done (abc1234) · no PRs` ("says neither `PR #<n>` nor `no PR`", confusing); `PR #8 · CI green (2 runs)` / `(3/3)`; `PR #8 (draft pull request)`; `PR #8 ✅`; `PR #8 · CI ✅`; `done ✅ (abc1234)`; `PR #18 (stacked on 8)`; `PR #8<br>PR #18`; NBSP or ZWSP anywhere in the cell; NBSP in the header's `Status` or in the key; `**Status**` header.
- **Fix:** optional: accept `no PRs` as `no PR`; normalise NBSP to a space before parsing; mention or strip a trailing emoji. Rest acceptable as is.
- **Raised by:** CT (#7), AR (F8), PT (F7).

### R6-23. LOW (documented): any file under `.github/workflows`, at any depth, counts as a workflow file
- **Where:** lib/ci.sh:111-113.
- **Failure path (ran, PT rows 112-115, exit 10):** an absent record whose head holds only `.github/workflows/.gitkeep`, `README.md`, `old/ci.yml`, or `ci.yml.disabled` refuses with "has a workflow file … no override". GitHub runs only top-level `*.yml|*.yaml`, so by that definition these are false refusals. Pinned on purpose (41:345, "any name under .github/workflows"; spec:97 "any file"; known P3R3-20).
- **Not HIGH (c):** spec:97 and the pinned fixture 41:345 define a workflow file as any file there; fails closed.
- **Fix (optional):** match only `^\.github/workflows/[^/]+\.ya?ml$`.
- **Raised by:** AR (F10), CT (#8), PT (F8).

### R6-24. LOW (owner question, not a bug under ruling 2): the comment's "runs were never due" premise is loose
- **Where:** lib/ci.sh:74-77; docs/spec.md:97.
- **Detail:** for `pull_request`, GitHub takes workflow files from the merge ref (head into base); `pull_request_target` uses the base's. A head with no workflow on a base that has one can owe runs that never appeared (e.g. no merge ref because of conflicts), and done is allowed and logged. Low plausibility (brief step 4 merges the base in first). Also (SEC, no severity): a lazy child who deletes the workflow file on its PR branch gets exit 0 — the brief forbids it and ruling 2 owns it.
- **Fix:** reword to "decided at the PR's head (owner ruling 2)" without claiming runs were never due.
- **Raised by:** CT (#9); SFH and SEC as ruling-bound notes.

### R6-25. LOW: records written by the pre-diff ci_wait can contain workflow_dispatch runs, and done cannot tell
- **Where:** lib/ci.sh:105-107.
- **Failure path:** the old `gh run list … --json databaseId` had no event filter; a job spanning the upgrade with a green dispatch-only record of the current head reads `success`, exit 0. Records carry no event or version.
- **Not HIGH (c):** only records written before this diff, in a job that spans the upgrade; the current writer filters dispatch runs (lib/ci.sh:20, :30).
- **Fix:** store `event` per run (or a schema field) in the record; treat records without it as unread.
- **Raised by:** SFH (#6).

### R6-26. LOW: a record is a snapshot by sha, so a red re-run or late run on the same head is not seen
- **Where:** lib/ci.sh:129-134.
- **Failure path (probed):** ci-wait re-run with gh failing mid-way (`run view` 502) exits 1; the old green record of the same head survives; ci_check exits 0.
- **Fix:** at done, re-list `ci_runs <head>` (one gh call) and refuse when the run-id set differs from the record's.
- **Raised by:** SFH (#7).

### R6-27. LOW: a failed ci-wait leaves `gate-logs/ci-pr-N.json.tmp`, and its error goes only to stderr
- **Where:** lib/ci.sh:36-43.
- **Failure path (probed):** after `die: gh run view 21 failed` (exit 1), `ci-pr-8.json.tmp` remains with partial content; `die` writes to stderr, not run.log. Aborting before `mv` relies on pipefail + errexit at the `ci-wait)` top level (holds today). The leftover may count as an uncommitted path for chain_dirty (exit 7) if the job dir is tracked.
- **Fix:** `trap 'rm -f "$r.tmp"' RETURN`, or check after the pipeline; log the failure.
- **Raised by:** SFH (#8).

### R6-28. LOW: every `gh run watch` failure other than timeout is discarded unlogged
- **Where:** lib/ci.sh:26 (`> /dev/null 2>&1 || [ $? -ne 124 ] || log`).
- **Detail:** 401/403/rate-limit/network failure looks like a red run; fails closed (an unfinished run records `""`, read as `failure`) but nothing tells the child why.
- **Fix:** log the exit code and last stderr line when non-zero and not 124.
- **Raised by:** SFH (#9).

### R6-29. LOW: usage marking skips silently on a read failure
- **Where:** lib/checkpoint.sh:136 (`nums="$(cp_scan nums)" || return 0`, in this diff).
- **Fix:** `|| { log "usage not marked: checkpoint.md unreadable"; return 0; }`.
- **Raised by:** SFH (#12).

### R6-30. LOW (theoretical): the leading `!` treats a grep error as a clean cell
- **Where:** lib/ci.sh:87 (`! LC_ALL=C command grep -qE … || chain_end`). A grep exit 2 inverts to "no bad character" (fails open); static regex on a here-string, not reachable in practice.
- **Fix:** `case $? in 0) chain_end …;; 1) ;; *) chain_end 10 "cannot check cell";; esac`.
- **Raised by:** SFH (#13).

### R6-31. LOW: `gh run list --limit 100` silently drops older runs past 100 on one commit
- **Where:** lib/ci.sh:53. Not realistic today.
- **Fix:** log when exactly 100 runs come back.
- **Raised by:** SFH (#14).

### R6-32. LOW: leading zeros and trailing letters in a PR number
- **Where:** lib/ci.sh:123, :15.
- **Failure path (ran):** `PR #08` / `PR#08` pass done as PR 8 (PT rows 2-3), but `blast-off ci-wait <job> 08` exits 1 "must be a PR number" (row 1); the done refusal prints `ci-wait <job-dir> 8`, so the child still gets the right command. `PR #8a` reads PR 8, exit 0 (row 60), harmless.
- **Fix (optional):** let ci-wait drop leading zeros the same way.
- **Raised by:** PT (F9).

### R6-33. LOW: dropping a phase row is undetectable
- **Where:** lib/checkpoint.sh:96.
- **Failure path (ran):** deleting a phase row → exit 0 (PT row 108); a row commented out after the blank line, single-line or block → exit 0 (rows 101-102); the same comment directly under the table → exit 10 (row 100) — inconsistent, though the renderer agrees the row is gone.
- **Fix:** cross-check the number of Phase plan rows against `N` in the checkpoint's `phase: k of N` line at done.
- **Raised by:** PT (F10).

### R6-34. LOW: PR state is never read
- **Where:** lib/ci.sh:18, :132 read only `headRefOid`.
- **Failure path (from code; the fake gh has no state):** a closed, unmerged, abandoned PR with green CI passes as the phase's PR; a closed PR with red CI is a dead end ("fix and push" cannot apply).
- **Fix:** a template sentence ("a closed PR is a blocked part"), or read `state` in `ci_head` and name it in the refusal (see R6-3's fix).
- **Raised by:** PT (F11).

### R6-35. LOW (carried from round 5): upper-case sha passes `ci_check` but the receipt exits 9
- **Where:** lib/checkpoint.sh `cp_scan sha` (lower-case hex only) vs lib/ci.sh:90.
- **Failure path:** `done (ABC1234) · PR #8` passes ci_check; in a git workdir receipt_check exits 9 (fails closed). CT, SFH and PT observed the same caveat (their probes ran outside git, receipt off).
- **Fix:** read hex case-insensitively in one place (see R6-9).
- **Raised by:** SEC (carried), CT, SFH, PT (caveats).

### R6-36. LOW (carried from round 5): an awk file argument that contains `=` is read as an assignment
- **Where:** cp_scan's awk invocation (lib/checkpoint.sh).
- **Fix:** prefix the path with `./` when relative, or pass it via ENVIRON / stdin.
- **Raised by:** SEC (carried).

## Out of scope by ruling 3 (no severity)

- **Fence close (AR, reasoned, not probed):** lib/checkpoint.sh:65, :67 store only the first 3 characters of the fence opener and close on any line starting with them, so a ```` ```bash ```` line inside a ```` ``` ```` fence closes it, and a 3-backtick line closes a 4-backtick fence; CommonMark does neither. P3R5-4 family.
- **Run-together PR words (CT ran; PT from code):** `no PR, see pullrequest seven` exits 0; the `(prs?|pull)` word filter at lib/ci.sh:91 misses run-together spellings. Only crafted text gets through.
- **Forged record files (SFH):** a hand-written `ci-pr-8.json` with `head_sha: "null"`, plus gh printing `{}` with exit 0, passes `ci_head` (`"null" == "null"`), exit 0. ci_wait never writes such a record (it checks for a 40-hex sha first). Hardening: `[[ $cur =~ ^[0-9a-f]{40}$ ]]` at lib/ci.sh:133.
- SEC, PT and SFH found no other crafted, renderer-divergent escapes; round 5's P3R5-1..7 stand as ruled.

## Notes bound by rulings (not findings)
- Ruling 1: `no PR` is accepted unverified; a lazy child could write it on a phase with a red PR (CT, SFH). brief.md §5's phase table marks no-PR phases, so a cross-check that reads no prose exists if the owner wants one (see R6-6's optional fix).
- Ruling 2: see R6-24.

## The bare `/pull/N` question

**Is reading a bare `/pull/N` consistent with "the template names only `PR #<n>` or `no PR`"? No in practice.** AR, SFH and PT: not consistent. SEC: only partly consistent. CT: formally consistent (the reader accepts a superset of the template) but inconsistent in practice. templates/checkpoint.md:35-36 says "`PR #<n>` (that form, not a link or URL)", yet lib/ci.sh:90/:123 and docs/spec.md:97 still read a bare URL from any host/owner/repo, host-less `o/r/pull/N`, `/pull/N`, and suffixes like `/files` and `/checks`, while refusing `[..](..)`, `<url>` and `#fragment`. Spec and code agree ("still read but no longer taught"); template and code do not. README and SKILL do not mention URL reading.

**The compatibility rationale is thin.** The phase-2/main template line 27 taught `Add PR #<n> after it` for the Status cell; line 29's "/pull/<n> link anywhere here" mostly covered prose, which is no longer read, and meant "this job's own PR" — which justifies this repo's links at most, never other repos' or hosts'. Markdown links are refused now anyway, so compatibility covers only a bare URL in a cell, and ruling 1 already forces old checkpoints to edit rows without a PR.

**Can an honest checkpoint read another repo's PR as this repo's? Yes, confirmed by all five** (the lead's two cases plus `github.com/o/other/pull/8`, other hosts, `/pull/8`, and the non-URL forms `PR #8 (o/other)`, `PR #8 in o/other`, `o/other PR #8`, `acme/infra-pr#8`). It needs (a) a phase that opened a PR outside the workdir's repo, and (b) a current, non-red record for this repo's PR N — which the honest child creates itself by running the `ci-wait <job-dir> N` the refusal message prints (R6-3). The URL is not the root cause (`PR #8` misreads the same way), but it is the one input where the cell proves the PR is another repo's, and the reader throws that away.

**Severity: MEDIUM (R6-2)**, HIGH (a) if the owner runs jobs whose target set or allowed actions include another repo. Recommended: stop reading `/pull/N` and refuse it with the existing "write `PR #<n>`" advice (or accept only a URL whose owner/repo equals the workdir's), refuse `/` in `rest`, anchor the `PR ?#` token; R6-1's ancestor check closes the number-collision class.

## Report Audit

Auditor: one general-purpose agent, read-only, given the five reviewer outputs, the brief and the draft report. **Verdict on the draft: ISSUES (no dropped findings; counts 0/1/12/23 + 3 OOS matched the body).** All problems below were applied to this report before publication:

- Wrong location `templates/brief.md:214` (file has 192 lines; came from SEC) → corrected to `templates/brief.md:134` (step 4) in R6-2 and R6-3. Applied.
- `/pull/N` answer said "No (all five reviewers)", misstating SEC ("only partly consistent") and CT ("formally consistent, practically inconsistent") → reworded with per-reviewer positions. Applied.
- R6-2 grade attribution wrong (AR and SFH also gave the conditional HIGH) → corrected. Applied.
- R6-2 severity reasoning understated the precondition ("a matching number") and ignored the brief's (a)-listed "link where the template says `PR #<n>`" slip → reasoning replaced; severity stays MEDIUM with the multi-repo condition as an owner call. Applied.
- R6-1 presented "receipts pass `receipt_check`" as run when neither probe ran the receipt check, and misdescribed CT's rows → separated ran vs reasoned, corrected rows. Applied.
- R6-8 missing PT (F7, rows 44 and 46) attribution → added. Applied.
- R6-11, R6-23, R6-25 fit HIGH (c) on their face with no stated reason for the lower grade → "Not HIGH (c)" reason added to each (pre-existing/unprobed; spec-defined and fail-closed; pre-diff records only). Severities kept; the owner may promote. Applied.
- Summary's "criteria 1, 2 and 4 held in every probe" lacked the unprobed caveats → caveat added, plus AR's criterion 3/5 "mostly met" verdicts. Applied.
- Small omissions: CT's backticked `a|b` note result (added to R6-20); SFH's "no new crafted Markdown" (added to the out-of-scope section). Applied.
- No two findings are duplicates; R6-3 and R6-34 overlap on PR state but have different failure paths and cross-reference each other.
