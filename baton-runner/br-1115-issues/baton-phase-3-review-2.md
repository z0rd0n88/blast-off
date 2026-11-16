---
source: runner
scope: br-1115-issues
parent_session: ""
---
# Pass-Baton: phase 3 review 2 (issue 26): VERDICT ISSUES, gate green, 4 HIGH, criterion 3 met only in part

**Date:** 2026-11-15
**Scope:** br-1115-issues
**Branch:** feat/br-1115-issues/phase-3
**Worktree:** /home/alex/blast-off/.claude/worktrees/pending-items-53932d
**HEAD:** ecc6e90 fix(phase-3): address review findings (iter 1)

## Where things stand

**VERDICT: ISSUES.** The gate passed (exit 0, `GATE: PASS passed=18 failed=0 shellcheck=ok`), but the synthesized review holds 0 CRITICAL, 4 HIGH, 18 MEDIUM, 17 LOW (39 findings after dedup of 68 filed), and acceptance criterion 3 is met only in part. Two things block CLEAN: the four HIGH findings, and criterion 3. The round-1 HIGH (P3R1-1) is reshaped, not resolved: the fix closes the case "no Status cell names a PR", and the same hole stays open as soon as one cell does. I confirmed that on the real runner (below). Nothing is committed by this unit; the manager owns git. Blocking state: fix round 2 is needed, and the owner should answer question 4 (and 2) first, because each fix option changes what a checkpoint must contain.

- Gate log: `baton-runner/br-1115-issues/gate-phase-3-iter-2/tests-run.log` (run once, alone, `BLAST_OFF_TEST_ONLY` unset).
- Review report: `baton-runner/br-1115-issues/review-phase-3-iter-2.md` (per-reviewer reports in `baton-runner/br-1115-issues/review-phase-3-iter-2/`).
- **ExecStart check: OK** before the gate, after the gate, after the reviewers and after my own runs: `ExecStart=/home/alex/blast-off/.worktrees/blast-off-build/bin/blast-off run %f`.
- Skill audit: `baton-runner/br-1115-issues/skill-sheriff-phase-3.md` (ran to the end; nothing counts toward the verdict).

### How the review ran

The `Z0rd0nZords:zord-multi-agent-review` skill ran, inline in this unit (this unit is itself a subagent, so no orchestrator subagent was dispatched). Default roster: architect-reviewer, critical-thinking, silent-failure-hunter, security-reviewer, penetration-tester; synthesizer knowledge-synthesizer; then the report adversary. The roster's agents are parked, so each ran as a general-purpose agent that read its parked definition read-only. No adversarial refutation stage (not asked for). The report audit's verdict: "sound with corrections", 10 corrections, none changes the CRITICAL or HIGH count; it is appended to the report as `## Report Audit`.

Only the skill's command summary loaded in this unit, so the reviewer brief, its severity rubric and its list of leads were written by me, from the task and the owner's `code-review.md` levels (the synthesizer read the skill's own consolidation rules). One rubric clause is mine alone: "instruction text that tells an agent to do the wrong thing" is HIGH. P3R2-4's HIGH rests on it; under the owner's levels it is HIGH or MEDIUM by judgement, and reviewers split. P3R2-3 is split too (2 HIGH, 3 MEDIUM). P3R2-1 and P3R2-2 are HIGH under the owner's levels as well (a completion gate that passes with a red record in hand; an acceptance criterion not met), and all five reviewers rated them HIGH, so the verdict stands on those two alone.

Deviations to know about:
- silent-failure-hunter (the one reviewer allowed to run scenario 41, on its own /tmp copy) also ran that copy's `bin/blast-off ci-wait` three times against the fake `gh`, and one scenario run with a patched `fail()` in the copy's `tests/lib.sh`. Neither calls `install_units`; no unit or suite was left running.
- security-reviewer's caveat: the shared probe script ran `ci_check` where bash ignores errexit. One finding depended on it (P3R2-29) and is marked contested. The HIGH findings do not: penetration-tester ran them with errexit on, and I ran P3R2-1 through the real `bin/blast-off run`.
- Reviewers left their own temp dirs under /tmp in place. Nobody deleted anything. No tracked file changed (`git status` shows only untracked `baton-runner/` paths).

### What I verified myself (scenario 41 only, in a /tmp copy, one run at a time)

- Baseline: `PASS 41-ci-wait` (23 s).
- Four mutants of my own, one per criterion, all KILLED: C1 pathspec typo `.github/workflowz` → `FAIL: absent CI with a workflow at HEAD: exit 0`; C2 absent pass not logged → `FAIL: absent not logged`; C3 whole row read instead of the last cell → `FAIL: green and absent records: exit 10`; C4 dispatch counted and push dropped → `FAIL: green dispatch run counted: exit 0`. silent-failure-hunter ran 27 more: 23 killed, 4 survived (P3R2-20, -23, -24, -25).
- **P3R2-1 on the real runner, unmutated code.** Job `mx` appended to the copy's scenario 41: row 0 `done (abc1234) · PR #8` with a green record, row 1 `done (abc1234)` with no token, `PR #7` only under `## Completed phases`, and a **red** `gate-logs/ci-pr-7.json` in the job. Result: `exit=0`, run.log `CI read for the PRs Phase plan Status cells name: 8; named elsewhere in checkpoint.md and not read: 7` then `job done`. Script and output are kept: `baton-runner/br-1115-issues/review-phase-3-iter-2/unit-mutants-and-e2e.sh`, `unit-e2e-mixed.log`. The comparison with phase 2 is penetration-tester's run, not mine: the same shapes against `git show feat/br-1115-issues/phase-2:lib/ci.sh` were refused with exit 10.
- Probes with `lib/ci.sh` sourced and stubs: a NUL byte in a table-less checkpoint → `no PR named in checkpoint.md; CI not read`, passes (P3R2-5); `PRs #7, #8`, `PR 7`, `#7`, two spaces in a Status cell → same line, passes (P3R2-6); `https://github.com/o/other/pull/99` in prose with no Status-cell PR → `PR #99 CI unread ... blast-off ci-wait <job-dir> 99` (P3R2-2).

### Acceptance criteria

| # | Criterion | Status | Passing test (`tests/41-ci-wait.sh`) |
|---|---|---|---|
| 1 | no runs + workflow file at HEAD: exit 10 | met for every PR the gate reads | lines 173-186 (`a2`, `a3`, `a4`), 191-197 (`ub`); my mutant C1 |
| 2 | no runs + no workflow file: allowed, logged | met | lines 171-172 (`a1`), 125-126, 130; my mutant C2 |
| 3 | PRs only from Status cells; prose ignored | **met in part**: true only when at least one Status cell names a PR. Lines 141-152 and 193-197 (`nt`, `np`, `ub`) assert the opposite: prose IS read when no cell names one | lines 94-110, 125-129 (`fin`) prove the half that holds; my mutant C3 |
| 4 | `workflow_dispatch` counts in neither direction | met | lines 75-76 (PR 14: a green dispatch alone is absent, exit 10), 77-78 (PR 15: red dispatches beside a green run leave success), 79 (none watched or viewed), 81-82 (PR 16: a red push run counts), 169-176 (at `done`); my mutant C4. Gap, not a finding: no `done` run uses PR 15's record, so red-dispatch-is-no-failure at `done` has no direct assertion; it follows from the record |
| 5 | tests for 1-4, docs match | met in part: tests exist with gaps (P3R2-20, -24, -25); docs carry untrue claims and remedies (P3R2-3, -4, -15, -16, -17, -19) | n/a |

### Findings, MEDIUM and above (detail, evidence and alternative fixes: the report's `#### P3R2-<n>` sections)

| ID | Severity | file:line | Failure path | Suggested fix |
|---|---|---|---|---|
| P3R2-1 | HIGH | `lib/ci.sh:71-73` | One `PR #N` in any Status cell switches off the read of every other PR the checkpoint names. A done row closed without its PR (PR only under Completed phases, the template's own shape) passes `done` with no record, a red record or a stale one; one log clause, exit 0. All five reviewers; reproduced on the real runner | Smallest: fall back to the whole-file read when ANY done digit-keyed row's Status cell names no PR (not only when none does), and add the `mx` case with a red record. Stricter alternative (owner question 4): refuse a done row with neither a PR token nor an explicit `no PR`. Reading only "named elsewhere" PRs that have a record is not enough (deleting the record is then the way out). **Note:** the smallest fix reads prose in more cases, so criterion 3 as written stays "met in part"; only the token-or-`no PR` option reads no prose at all. The owner must pick that option, or rule that a fail-closed fallback satisfies criterion 3; without one of the two, round 3 cannot be CLEAN |
| P3R2-2 | HIGH | `lib/ci.sh:74-76,90`; `templates/checkpoint.md:32` | In the fallback another repo's `/pull/N` link in prose is read as this repo's PR N. The hint "write any other PR with no '#'" does nothing for a link, and the refusal says `ci-wait <job-dir> N`, which reads an unrelated PR of the workdir repo: a dead end, or `done` passing on an unrelated green PR. Issue 26's own bug is back for jobs with no Status-cell PR | In the fallback skip a `/pull/N` link whose `owner/repo` is not the workdir repo's; reword the hint to "write any other PR as `other PR <n>` or by branch, and drop or unlink a /pull/<n> URL"; make the fallback's unread refusal say "if PR N is not this job's, reword it" before `ci-wait` |
| P3R2-3 | HIGH | `lib/ci.sh:86-87`; `README.md:132`; `docs/spec.md:97` | The absent refusal's remedy ("push to the PR branch for a run") cannot start a run for an earlier stacked PR whose branch has no workflow file (or a branch-filtered workflow): `ci-wait` records absent again, exit 10 without end. The exit that works is deleting the PR token (P3R2-1). Rated HIGH by ARCH and PEN, MEDIUM by CRIT, SFH, SEC; GitHub's half is reasoned from recall | Decide "runs were due" from the record's `head_sha` (`git ls-tree <head_sha> -- .github/workflows`), not the workdir's HEAD (owner question 2; also closes P3R2-7). At the least make the message, README and spec say when a push cannot help and that the owner must decide |
| P3R2-4 | HIGH | `templates/checkpoint.md:29-32`; `tests/51-templates.sh:74-75` | The rule comment children obey now says "A row closed without one gets no CI check": it tells the gated agent which edit drops a PR from the gate, contradicts line 27 ("Add `PR #<n>` after it"), and test 51 pins the sentence. Rated HIGH by CRIT, MEDIUM by SEC and ARCH | Reword to an obligation ("every closed row that has a PR names it in its Status cell; the runner reads every PR named here when a closed row names none"), once P3R2-1's rule is chosen; change the three pinned strings in test 51 with it |
| P3R2-5 | MEDIUM | `lib/ci.sh:97` | One NUL byte makes `grep -o` print nothing: `no PR named in checkpoint.md; CI not read`, exit 0. Defeats the fallback | `grep -a`; a test with a NUL in a table-less checkpoint (P3R1-28 still open) |
| P3R2-6 | MEDIUM | `lib/ci.sh:97,73,78` | `PRs #7, #8`, `PR 7`, `#7`, `PR: #7`, two spaces in a Status cell read no PR and pass with the untrue line "no PR named"; `PR #7, #8` reads 7 and 8 appears nowhere | At done, refuse or at least log a done Status cell that holds `#<digits>` or `PR` with no token read; widen the regex for list forms (P3R1-9 reshaped) |
| P3R2-7 | MEDIUM | `lib/ci.sh:86-88` | Workflow read is of the workdir's HEAD only: absent passes when the PR's branch has a workflow HEAD lacks, HEAD removed it, or it is uncommitted | Same as P3R2-3: read the record's `head_sha` |
| P3R2-8 | MEDIUM | `lib/ci.sh:86-87` | Any path under `.github/workflows` (`.gitkeep`, `README.md`, a dispatch-only workflow) counts; absent is then refused for good | Owner question 3: count `*.yml`/`*.yaml` only, or keep and document; an owner-held override |
| P3R2-9 | MEDIUM | `lib/ci.sh:81,103-108` | Nothing ties PR N to its row's commit or to HEAD; a record of any green PR of the repo satisfies the gate | Compare the PR's head with the row's sha or HEAD's history (pre-existing, made worse by P3R2-1) |
| P3R2-10 | MEDIUM | `lib/ci.sh:81,105-107` | The gate trusts whatever is in `gate-logs/ci-pr-<n>.json`; the gated child can write it | Pre-existing; file separately (P3R1-40) |
| P3R2-11 | MEDIUM | `lib/ci.sh:41` | A PR whose only runs were skipped records `success`; draft PRs are the default delivery | Pre-existing; treat all-skipped as absent, or file separately |
| P3R2-12 | MEDIUM | `lib/checkpoint.sh:11,40-45`; `lib/ci.sh:70` | A table the runner cannot read turns the receipt and all-done checks off; a second `## Phase plan` heading right after the first hides rows | Pre-existing; file separately |
| P3R2-13 | MEDIUM | `lib/ci.sh:73,76,78`; `lib/chain.sh:159` | The only signal for an unread PR is a run.log line on a path that ends exit 0 `job done` | Goes away with P3R2-1's fix; otherwise put the unread PRs in the `job done` line |
| P3R2-14 | MEDIUM | `lib/ci.sh:86-88` | Outside git no workflow read happens, yet run.log says "no workflow file at HEAD" | Say "workdir is in no git repo; workflow files not read" (P3R1-31, P3R1-32) |
| P3R2-15 | MEDIUM | `docs/spec.md:97`; `lib/ci.sh:64-66` | Spec row 10 and the comment claim "never lets done through with a named PR unread" and "fails closed"; untrue per P3R2-1, -5, -6 | Fix the code, or state the limits |
| P3R2-16 | MEDIUM | `templates/checkpoint.md:29-32` | The reworded rule parses two ways ("one" = a PR or a Status cell; what "unless" governs) and contradicts case `np` | Rewrite as two sentences with one subject each, with P3R2-4 |
| P3R2-17 | MEDIUM | `skills/blast-off/SKILL.md:34-37` | Step 4: "with no CI" names the wrong case (it is "no runs on this PR"), and "say which holds" asks for a prediction as a binding statement; nothing checks that workflows run on stacked PRs | Say "when a PR gets no runs"; have the skill ask whether the repo's workflows trigger on the stacked PR branches |
| P3R2-18 | MEDIUM | `templates/brief.md:135,142-144` | The child protocol gives no action for `absent`, so the refusal lands after the last phase | One line in the brief: on `absent` with a workflow file, stop and record it as blocked (file not in this diff) |
| P3R2-19 | MEDIUM | `README.md:132` | The exit 10 row names only Status-cell PRs and gives no remedy for the fallback case | Add the fallback case and its remedy |
| P3R2-20 | MEDIUM | `tests/41-ci-wait.sh:94-131,139-156`; `tests/51-templates.sh:74-75` | Tests pin the fail-open as wanted (`fin`'s `P1` row, the "not read" log); no mixed case with a record, no mis-spelled cell, no NUL | Add those three cases with the fixes above |
| P3R2-21 | MEDIUM | `lib/ci.sh:70` | Sixth copy of the row-range `sed`, third of `$(NF-1)`, outside `lib/checkpoint.sh` | A `cp_status_cells` helper in `lib/checkpoint.sh` (P3R1-29) |
| P3R2-22 | MEDIUM | `README.md:114-117,132`; `docs/spec.md:97,228`; `lib/ci.sh:57-66`; `templates/checkpoint.md:29-32`; tests | The three-way rule is written out in about eight places while four owner questions on it are open | Settle the owner questions first; keep the full rule in the spec, short pointers elsewhere |

### Findings, LOW

| ID | Severity | file:line | Failure path | Suggested fix |
|---|---|---|---|---|
| P3R2-23 | LOW | `lib/ci.sh:53-54`; `tests/fakes/gh:22-30` | `--limit 100` applies before the jq filter, so dispatch runs can crowd out the PR's runs; the fake ignores `--limit` (mutant `--limit 1` survived) | `die` at 100 entries; make the fake honour `--limit` (P3R1-24, -33) |
| P3R2-24 | LOW | `tests/41-ci-wait.sh:173-186` | Pathspec narrowed to `ci.yml` survives; `git ls-files` for `ls-tree HEAD` is killed only by `ub` | `git rm --cached` in `a4`; a second workflow file name in `a2` |
| P3R2-25 | LOW | `lib/ci.sh:107` | The `[ -n "$cur" ]` guard in `ci_head` has no test | A record with `head_sha` deleted while `gh pr view` fails |
| P3R2-26 | LOW | `lib/ci.sh:45,52-55` | `ci-wait` leaves dispatch runs out with no word in run.log | Log the count left out (P3R1-25) |
| P3R2-27 | LOW | `lib/ci.sh:81-83` | A `success` record written before this phase from a green dispatch run still passes | Record `event` per run, or note that old records must be re-made (P3R1-23) |
| P3R2-28 | LOW | `lib/ci.sh:36-43` | A `ci-wait` that dies part-way leaves `ci-pr-N.json.tmp`; fail-closed | Collect the views first, then jq |
| P3R2-29 | LOW | `lib/ci.sh:81` | A record with a valid first JSON value and trailing garbage. **Contested**: with errexit on the runner aborts (exit 1), it does not pass | `jq -rs` with `length == 1`; or drop the finding |
| P3R2-30 | LOW | `lib/ci.sh:89,108,45` | A record's `head_sha` and a run's name reach run.log raw (a forged `job done` line; exit code still 10) | Flatten control characters in `log` |
| P3R2-31 | LOW | `lib/ci.sh:16-18,36-43` | A record carries no repository identity | Record `nameWithOwner`; compare in `ci_head` |
| P3R2-32 | LOW | `lib/ci.sh:97` | The regex reads PRs out of ordinary words and paths (`expr #2`, `docs/pull/3`) | `(^\|[^[:alnum:]])PR ?#[0-9]+` |
| P3R2-33 | LOW | `lib/ci.sh:106` | `BLAST_OFF_CI_HEAD=0` means no timeout | Document, or treat 0 as the default |
| P3R2-34 | LOW | `lib/checkpoint.sh:5` | A BOM or UTF-16 hides `status:`; children keep launching. Not a fail-open | A log line when `cp_status` is empty |
| P3R2-35 | LOW | `lib/ci.sh:97` | `paste`: no dependency list needs to name it; a missing `paste` fails closed (rc 127). Separate, pre-existing: `README.md:16` Requirements omits `git` | None needed |
| P3R2-36 | LOW | `docs/spec.md:228` | "that heading only" is a prefix match (`## Phase planning notes` opens the range) | Say "a heading starting `## Phase plan`" |
| P3R2-37 | LOW | `docs/spec.md:97` | "the Status cell is the last cell" holds only with a trailing pipe | Strip or require the trailing pipe in one place |
| P3R2-38 | LOW | `lib/ci.sh:2,86` | `ci_check` reads the global `TOP` only `chain_run` sets | None now |
| P3R2-39 | LOW | `bin/blast-off:37-38`; `docs/spec.md:35` | Two wording nits in the header and the F7 row | Reword if touched |

### Round-1 HIGH and MEDIUM: status

| ID | Status | Note |
|---|---|---|
| P3R1-1 (HIGH) | **reshaped** | Closed where no Status cell names a PR and a readable token exists; open as soon as one cell does (P3R2-1), and for NUL and mis-spelled tokens (P3R2-5, -6). SEC and PEN read it "resolved for its listed shapes"; ARCH, CRIT, SFH and I read it reshaped |
| P3R1-2 | reshaped | Logged, still exit 0, a red record passes (P3R2-1, -13) |
| P3R1-3 | open | Limit now stated in the spec; owner question 2 (P3R2-3, -7) |
| P3R1-4 | open | Message reworded, still a dead end; owner question 3 (P3R2-3, -8) |
| P3R1-5 | reshaped | No longer false; now ambiguous and states the bypass (P3R2-4, -16) |
| P3R1-6 | resolved, one dissent | CRIT: "with no CI" and "say which holds" mislead (P3R2-17) |
| P3R1-7 | resolved as filed | New gaps: fallback missing from the exit 10 row, remedy cannot work (P3R2-19, -3) |
| P3R1-8 | resolved | Nit in P3R2-39 |
| P3R1-9 | reshaped | Logged, and the log line is untrue for these cells (P3R2-6) |
| P3R1-10 | resolved | Gap: no mixed case with a record (P3R2-20) |
| P3R1-11 | resolved | Test `a3` added; mutant killed |
| P3R1-12 | resolved | Test `ub` added; mutant killed |
| P3R1-13 | resolved | Test `a4` added; mutant killed; near-survivor in P3R2-24 |
| P3R1-14 | resolved | Test PR 16 added; mutant killed |
| P3R1-15 | resolved | `fin` row under `## Decisions`; mutant killed |
| P3R1-16 | resolved | `fin` five-column table; mutant killed |
| P3R1-17 | resolved, with a catch | The `P1` row test pins P3R2-1's behaviour as wanted |
| P3R1-18 | resolved | Narrower pathspec survives (P3R2-24) |
| P3R1-19 | resolved | Test `a5` added; mutant killed |
| P3R1-20 | resolved | `wf` builds its record with `ci-wait` on PR 14 |

### Owner questions (fix baton): is the default in the code the safe one?

1. **Whole-file read when no Status cell names a PR.** Safe in direction (it refuses), not sufficient and with a real cost. It is keyed on the whole table, so one tokened row turns it off (P3R2-1); and for a job with no Status-cell PR it brings issue 26's bug back, with a hint that does not apply to a link (P3R2-2). Keep the fallback; change its key and its texts.
2. **Workdir HEAD decides "runs were due".** Not safe in either direction: absent passes when the PR's branch has a workflow HEAD lacks (P3R2-7), and an earlier stacked PR is refused with no working way out (P3R2-3). It is what issue 26's words say, so changing it to the record's `head_sha` is the owner's call. I recommend the change.
3. **Any file counts, no override.** Fail-closed, so safe as a gate. In practice the override exists and is the wrong one: deleting the PR token (P3R2-1, P3R2-4). Keep the default only together with P3R2-1's fix; an owner-held override is then worth adding.
4. **Where some cells name PRs, a PR named elsewhere is logged and not read.** **Not the safe default.** It is P3R2-1: exit 0 with a red record in the job's own gate-logs. All five reviewers agree, and I reproduced it on the real runner.

### Skill audit (`skill-sheriff-cc` on `skills/blast-off`)

Ran to the end: docs fetched fresh (3 pages), quote check exit 0. Summary: 0 Fail, 3 Gap, 42 Pass, 3 N/A, 3 Can't verify (51 rows).
- On lines this phase changed (`SKILL.md:34-37`): **none**. The added words cross no limit (description 199 characters before and after; body 83 lines against 81). Nothing counts toward the verdict.
- Pre-existing, listed only: (a) the description says when to use the skill, not what it does (`SKILL.md:3`); (b) no table of contents in `README.md` (153 lines) and `templates/brief.md` (187 lines), both referenced at `SKILL.md:13-14`; (c) fewer than three evaluations in the skill folder. Auditor's note: `disable-model-invocation` unset was filed N/A; another auditor could call it a Gap, pre-existing either way.

### New dependencies

- `paste` (coreutils, the package `sort` and `tr` come from) in `lib/ci.sh:97` (`ci_prs`). No new package, tool install or action. No dependency list needs it: `DEPS` names no base tool of that package, and a missing `paste` fails closed (architect-reviewer ran it: rc 127). 
- `gh run list --json databaseId,event` (`lib/ci.sh:53`): the phase diff adds the `event` field, so the dispatch filter relies on the installed `gh` printing it. security-reviewer checked the field and its strings against gh 2.101.0. No gh version floor is stated anywhere (P3R1-42, still open). Not a new tool, but a new reliance on one.

## Next steps

1. Manager: put owner question 4 (and 2) to the owner with the recommendation above, then run fix round 2 against P3R2-1 to P3R2-4 first. The smallest P3R2-1 change is the fallback condition in `lib/ci.sh:71-76`; add the `mx` case (text in `baton-runner/br-1115-issues/review-phase-3-iter-2/unit-mutants-and-e2e.sh`: two done rows, one token, PR #7 under Completed phases, red record, expect exit 10). Mind the note in the P3R2-1 row: that change alone leaves criterion 3 "met in part", so the owner's ruling on criterion 3 is needed for round 3 to be able to close CLEAN.
2. With that fix: `grep -a` in `ci_prs` (P3R2-5), the reworded rule in `templates/checkpoint.md:29-32` and its three pins in `tests/51-templates.sh:74-75` (P3R2-4, -16), the link handling and hint (P3R2-2), and the spec and comment claims (P3R2-15).
3. Review round 3 is the last for this phase: `scripts/gate.sh baton-runner/br-1115-issues/gate-phase-3-iter-3/`, once, alone.
4. No phase-exit digest was written: the verdict is not CLEAN.

## Open questions / risks

- GitHub's half of P3R2-3 (no run starts on a branch with no workflow file; branch filters) is reasoned from recall by all five reviewers, not tested against GitHub.
- The report audit lists 10 corrections to the synthesized report (for example its summary says criterion 1 "met" flat, and P3R2-29 is counted though refuted; without it the LOW count is 16). None changes the HIGH count.
- Review round 3 is the cap. If the owner's answers to questions 2 to 4 are not in before fix round 2, the fix can only take the defaults I recommend above.

## References

- Issue: z0rd0n88/blast-off issue 26
- Gate log: `baton-runner/br-1115-issues/gate-phase-3-iter-2/tests-run.log`
- Review report: `baton-runner/br-1115-issues/review-phase-3-iter-2.md`; reviewer reports: `baton-runner/br-1115-issues/review-phase-3-iter-2/`
- Skill audit: `baton-runner/br-1115-issues/skill-sheriff-phase-3.md`
- Earlier batons: `baton-runner/br-1115-issues/baton-phase-3-work.md`, `baton-phase-3-review-1.md`, `baton-phase-3-fix-1.md`
- Code: `lib/ci.sh:57-98`, `lib/chain.sh:159`, `templates/checkpoint.md:27-32`, `tests/41-ci-wait.sh:94-197`, `tests/51-templates.sh:74-75`
