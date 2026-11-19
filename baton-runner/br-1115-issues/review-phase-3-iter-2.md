# Review: phase 3 (issue 26), round 2

## Executive summary

- Not a clean round. After dedup: 0 CRITICAL, 4 HIGH, 18 MEDIUM, 17 LOW (39 findings from 68 filed: ARCH 16, CRIT 13, SFH 13, SEC 12, PEN 14). By the consolidation rule the verdict is WARN (no CRITICAL, at least one HIGH). The HIGH cap is off; nothing was demoted.
- P3R2-1 (HIGH, all five reviewers, RAN with errexit on): one `PR #N` in any Status cell switches off the read of every other PR the checkpoint names. A done row closed without its PR passes `done` with a red, stale or missing record. Phase 2 refused this. The round-1 HIGH is closed only where no cell names a PR.
- P3R2-2 (HIGH, all five): where the fallback fires, another repo's `/pull/N` link is read as this repo's PR, the log hint does not apply to a link, and the refusal sends the agent to `ci-wait` the wrong PR. Criterion 3 holds only when some Status cell names a PR.
- P3R2-3 (HIGH by two, MEDIUM by three): the absent refusal's remedy ("push to the PR branch") cannot work for an earlier stacked PR whose branch has no workflow file. The exit that does work is removing the PR token, which P3R2-1 then passes.
- P3R2-4 (HIGH by one, MEDIUM by two): the template's rule comment tells the gated child that a row closed without a PR "gets no CI check", and `tests/51-templates.sh:74` pins the sentence.
- The verdict does not hinge on the split ratings: P3R2-1 and P3R2-2 are HIGH from all five.
- Acceptance criteria: 1, 2 and 4 met; 3 and 5 met in part.
- Blocks a clean round: P3R2-1 to P3R2-4. Owner questions: question 4's default is judged unsafe by all five; question 2's is called unsafe outright by two and unsafe in one direction by two more, and all five say its stated remedy cannot work; question 3's is fail-closed alone but unsafe beside question 4's; question 1's fails closed but costs more than the fix baton states.
- HIGH themes: which PRs gate `done` (P3R2-1, P3R2-2); refusal text that cannot be followed (P3R2-2, P3R2-3); child-facing text that names the way round the gate (P3R2-4).

## How this review ran

The `zord-multi-agent-review` skill ran inline in the review unit's own context. The unit is itself a subagent, so no orchestrator subagent was dispatched. Roster (default): architect-reviewer, critical-thinking, silent-failure-hunter, security-reviewer, penetration-tester. The roster's agents are parked, so each ran as a general-purpose agent that read its parked definition read-only. The synthesizer, knowledge-synthesizer, ran the same way. No adversarial refutation stage ran (not requested). Target: `git diff feat/br-1115-issues/phase-2...HEAD` on nine product paths at HEAD `ecc6e90`. No exclusion list was injected into the reviewer brief. The synthesizer ran no test and no scratch script; its checks are by reading (and one read-only grep) and are marked "synthesizer check". The gate log the review unit left at `baton-runner/br-1115-issues/gate-phase-3-iter-2/tests-run.log` ends `GATE: PASS passed=18 failed=0 shellcheck=ok` (read, not run here).

What each reviewer reported about its own method:

- **architect-reviewer**: read the code and ran a copy of the shared `rev2/probe.sh`, extended, in `/tmp/arch-rev2.5XoBp4` (removed at the end). No `tests/run`. One read-only `gh issue view 26`.
- **critical-thinking**: read the code and ran stub scripts (`mine.sh`, a copy of `probe.sh`, `loc.sh`) in `.../scratchpad/crit.gwf6aO` (left in place). Its caveat: `ci_head` was stubbed and `TOP` was empty, so the workflow-file branch and the path through `receipt_check` and `receipt_all_done` are REASONED, not run.
- **silent-failure-hunter**: the one reviewer that ran the filtered scenario. 29 runs of `BLAST_OFF_TEST_ONLY=41-ci-wait tests/run`, one at a time, on a `git archive HEAD` copy in `/tmp/sfh2.aWjOTf`; baseline `PASS 41-ci-wait`; 27 mutants. The first attempt started nothing (its guard matched its own shell line). It named two things outside the letter of the allow-list, both in its own temp dirs:
  1. `cw.sh` ran the copy's real `bin/blast-off ci-wait` three times against the fake `gh`. P3R2-26 (SFH-8), P3R2-28 (SFH-12) and one row of its swallowed-errors table rest on it.
  2. One scenario run (the soft run of m1) used a `fail()` patched in the copy's `tests/lib.sh` to report and go on; the file was restored after.
  `ExecStart` in `~/.config/systemd/user/blast-off@.service` read the same before the first run and after the last. Temp dirs `/tmp/sfh2.aWjOTf` and `/tmp/sfh2w.BuzXns` were left in place.
- **security-reviewer**: read the code (HEAD and phase 2), ran stub scripts in `.../scratchpad/secrev.D6j176` (left in place), `shellcheck -S warning` and `bash -n` on `lib/ci.sh` and `tests/fakes/gh` (clean), and three read-only real `gh` calls (`gh run list --help`, `gh run list --limit 8 --json ...`, `gh issue view 26`). No `tests/run`.
- **penetration-tester**: built its own harness (`h.sh`) in `.../scratchpad/pen2.scGKTU` (left in place). It sources the real `lib/ci.sh`, `lib/checkpoint.sh` and `lib/receipt.sh` and runs the checks of `lib/chain.sh:137-159` in a `set -euo pipefail` subshell, with real PASS receipts in a throwaway git repo and a `gh` stub first on `PATH`. So its "exit 0" means the dirty-tree check, the receipt checks and `ci_check` all let `done` through. No `tests/run`. One case (`head_nogh`) was invalid and is not used.

Caveats that bear on findings:

- **security-reviewer's caveat on the shared harness.** `rev2/probe.sh` runs `ci_check` inside `( ... ) || echo`, where bash ignores errexit, so it prints `DONE PASSES` on paths the real runner aborts. The same harness stubs `ci_head`. One finding depends on this: P3R2-29 (SFH-9, a record that is valid JSON followed by garbage). security-reviewer (`probe3.sh`, errexit on: rc 5) and penetration-tester (`b7.sh`: "the runner aborts on jq's status") both saw an abort, not a pass. See "Excluded or contested".
- The other findings that quote `=> DONE PASSES` from the stub harness do not depend on the caveat, because a reviewer reproduced each with errexit on: P3R2-1 (security-reviewer `decoy`; penetration-tester `b1.sh`), P3R2-2 (security-reviewer `x_own_nohash`; penetration-tester `e_green` and the working ways out in `b8.sh`), P3R2-4 (the two edits it names are the passes of P3R2-1 and P3R2-2), P3R2-5 (security-reviewer `nul_cell`, `nul_prose`; penetration-tester `b2.sh`), P3R2-6 (penetration-tester `b3.sh`), P3R2-14 (penetration-tester `b5.sh` case `nogit`; also pinned by `tests/41-ci-wait.sh:125-130`).
- **GitHub's side is from recall in all five reports**: which commit's workflow file a `pull_request` or `push` run uses, branch filters, and that an all-skipped run reports `skipped`. P3R2-3 (its GitHub half), P3R2-11 and P3R2-17 rest on that.
- Locales checked: `C`, `POSIX`, `C.UTF-8` only. grep is GNU 3.11 throughout.

## Findings

### MEDIUM and above

| ID | Severity | file:line | Title | Raised by | Evidence | Origin |
|---|---|---|---|---|---|---|
| P3R2-1 | HIGH | `lib/ci.sh:71-73` | One PR token in any Status cell switches off the read of every other PR the checkpoint names; a done row closed without its PR passes with a red, stale or missing record | ARCH-1, CRIT-1 (part), SFH-1, SEC-1, PEN-1 | RAN | new in this diff; the fix commit logs it and leaves it open |
| P3R2-2 | HIGH | `lib/ci.sh:74-76,90`; `templates/checkpoint.md:32` | In the fallback another repo's `/pull/N` link is read as this repo's PR; the hint does not apply to a link; the refusal sends the agent to `ci-wait` the wrong PR | ARCH-2, CRIT-3, CRIT-13, SFH-2, SEC-3, PEN-3 | RAN (refusal and hint); RAN by SEC and PEN for the pass after following it | new in the fix commit |
| P3R2-3 | HIGH | `lib/ci.sh:86-87`; `README.md:132`; `docs/spec.md:97` | The absent refusal's remedy cannot work for an earlier stacked PR whose branch has no workflow file; the exit that works is the one P3R2-1 leaves open | ARCH-3, PEN-2, CRIT-7, SFH-5, SEC-4 | RAN for the runner half (PEN `b9.sh`); REASONED from recall for GitHub's half (all five) | new in this diff; remedy text new in the fix commit |
| P3R2-4 | HIGH | `templates/checkpoint.md:29-32`; `tests/51-templates.sh:74-75` | The rule comment tells the gated child that a row closed without a PR gets no CI check | CRIT-2, SEC-2, ARCH-5 (part) | REASONED from the text; the edit it names RAN (CRIT `evade_after`, `evade_mixed`; SEC `x_hint_followed`) | new in the fix commit |
| P3R2-5 | MEDIUM | `lib/ci.sh:97` (read at `:69-70`, logged at `:78`) | One NUL byte makes `ci_prs` read nothing: `no PR named in checkpoint.md; CI not read`, exit 0 | ARCH-7, CRIT-8, SFH-4, SEC-6, PEN-4 | RAN | pre-existing made worse (false log line new in the fix commit) |
| P3R2-6 | MEDIUM | `lib/ci.sh:97` (`:73`, `:78`) | PR spellings the regex misses in a Status cell pass `done`; in list forms the second PR appears nowhere in `run.log` | ARCH-8, CRIT-9, SFH-3, SEC-7, PEN-5 | RAN | pre-existing made worse (log line new in the fix commit) |
| P3R2-7 | MEDIUM | `lib/ci.sh:86-88` | The workflow read is of the workdir's HEAD only: absent passes when the PR's branch has a workflow file HEAD lacks, or HEAD removed it, or it is uncommitted | PEN-6, SEC-10 (part) | RAN | new in this diff |
| P3R2-8 | MEDIUM | `lib/ci.sh:86-87` | Any path under `.github/workflows` counts as a workflow file, so absent is refused for good on files that never start a run | PEN-7 | RAN | new in this diff |
| P3R2-9 | MEDIUM | `lib/ci.sh:81,103-108` | Nothing ties PR N to the row that names it or to HEAD; a record for any PR of the repo satisfies the gate | SEC-5 | RAN (`decoy`); REASONED for the unpushed-commit case | pre-existing made worse |
| P3R2-10 | MEDIUM | `lib/ci.sh:81,105-107` | The gate trusts whatever sits in `gate-logs/ci-pr-<n>.json`; the gated child can write it | PEN-8 | RAN | pre-existing |
| P3R2-11 | MEDIUM | `lib/ci.sh:41` | A PR whose only runs were skipped is recorded `success`; the default delivery is draft PRs | PEN-10 | RAN (local half); REASONED (GitHub reports `skipped`) | pre-existing |
| P3R2-12 | MEDIUM | `lib/checkpoint.sh:11,40-45`; `lib/ci.sh:70` | A table the runner cannot read turns the receipt and all-done checks off; a second `## Phase plan` heading straight after the first hides its rows | PEN-9 | RAN | pre-existing |
| P3R2-13 | MEDIUM | `lib/ci.sh:73,76,78`; `lib/chain.sh:159` | The only signal for an unread PR is a `run.log` line on a path that ends exit 0 with `job done` | CRIT-10 | REASONED | new in the fix commit (as a remedy) |
| P3R2-14 | MEDIUM | `lib/ci.sh:86-88` | Outside git no workflow read happens, but `run.log` says "no workflow file at HEAD" | SFH-7, ARCH-15, SEC-10 (part), PEN-11 | RAN | new in this diff |
| P3R2-15 | MEDIUM | `docs/spec.md:97`; `lib/ci.sh:64-66` | The spec and the code comment claim more than the code keeps ("never lets done through with a named PR unread", "fails closed") | ARCH-4, CRIT-1 (part) | REASONED against the RAN cases of P3R2-1 | new in the fix commit |
| P3R2-16 | MEDIUM | `templates/checkpoint.md:29-32` | The reworded rule parses two ways in two places and contradicts the code in one | CRIT-4 | REASONED; RAN for the "last cell" point | new in the fix commit |
| P3R2-17 | MEDIUM | `skills/blast-off/SKILL.md:34-37` | Step 4 asks for a prediction as a binding decision and names the wrong case | CRIT-5 | REASONED | new in the fix commit |
| P3R2-18 | MEDIUM | `templates/brief.md:135,142-144` | The child protocol gives no action for `absent`, so the refusal lands after the last phase | CRIT-6 | REASONED | pre-existing made worse (file not in the diff) |
| P3R2-19 | MEDIUM | `README.md:132` | The exit 10 row names only Status-cell PRs and gives no remedy for the fallback | ARCH-6, CRIT-12 | REASONED | new in the fix commit |
| P3R2-20 | MEDIUM | `tests/41-ci-wait.sh:94-131,139-156`; `tests/51-templates.sh:74-75` | Tests pin the fail-open as wanted and have no mixed case with a record, no mis-spelled cell, no NUL | CRIT-11, SFH-6, ARCH-5 (part) | RAN (mutant m23 survived) | new in the fix commit |
| P3R2-21 | MEDIUM | `lib/ci.sh:70` | `ci_check` parses the checkpoint table itself: the sixth copy of the row range, the third of `$(NF-1)` | ARCH-9 | REASONED | pre-existing made worse |
| P3R2-22 | MEDIUM | `README.md:114-117,132`; `docs/spec.md:97,228`; `lib/ci.sh:57-66,73-78`; `templates/checkpoint.md:29-32`; `tests/51-templates.sh:74-75`; `tests/41-ci-wait.sh:5-8` | The three-way rule is written out in about eight places while four owner questions on it are open | ARCH-10 | REASONED | new in the fix commit |

#### P3R2-1 | HIGH | lib/ci.sh:71-73

- **Failure path.** Two done rows. Row 0's Status cell is `done (<sha>) · PR #7` with a green record. Row 1's is `done (<sha>)`, and its PR is named only under `## Completed phases` as `PR #8`, the shape `templates/checkpoint.md:47-49` prompts. `prs` is `7`, so the fallback at `:74` never runs; PR 8 goes into `other`, gets one log clause, and `job done` follows with exit 0. The same holds for a row the runner does not see (key `P1`) whose own Status cell names its PR (ARCH `p1row`; `tests/41-ci-wait.sh:96,127-129` pins that as wanted). The gate is non-monotonic (ARCH, PEN): with no cell naming a PR it reads 7 and 8; do what the fallback's hint asks for PR 7 alone and the red PR 8 stops being read.
- **Strongest evidence** (penetration-tester, `b1.sh`, full harness with errexit and real receipts, HEAD against `git show feat/br-1115-issues/phase-2:lib/ci.sh`):

  | Case | Records | HEAD | Phase 2 |
  |---|---|---|---|
  | `mixed_norec` | 7 success; 8 none | exit 0 | exit 10, `PR #8 CI unread` |
  | `mixed_red` | 7 success; 8 `failure` | exit 0 | exit 10, `PR #8 CI red or unfinished` |
  | `mixed_stale` | 7 success; 8 success of an older head | exit 0 | exit 10, `PR #8 CI unread for head 222…` |
  | `mixed_absent_wf` | 7 success; 8 absent | exit 0 | exit 0 |
  | `fb_red` (no cell names a PR; prose names 7 and 8) | 7 success; 8 `failure` | exit 10 | exit 10 |

  `run.log` at HEAD in the first four: `CI read for the PRs Phase plan Status cells name: 7; named elsewhere in checkpoint.md and not read: 8` then `job done`. security-reviewer `decoy` (errexit on): a green PR #1 in one cell, the job's PR #8 red in prose, `=> DONE PASSES (exit 0)`.
- **Suggested fixes** (three, in order of how much each closes, by the limits reviewers showed):
  1. Refuse a done row whose Status cell names no PR once another row names one (SFH-1; the fix baton's alternative (b)). CRIT-1 offers a variant: an explicit `no PR` word, required of a done row that names none. silent-failure-hunter: "only one option closes this". It reads no prose, so criterion 3 holds as written. Its price: architect-reviewer and security-reviewer say alternative (b) breaks jobs that have a phase with no PR (the `no PR` word is critical-thinking's answer to that). It needs the owner's word (question 4).
  2. Key the fallback per row: read every PR the checkpoint names whenever any digit-keyed row's Status cell names no PR (ARCH-1, SEC-1). Closes the no-record, red, stale and absent rows above. ARCH checked it by reading against the fixtures: `fin`, `np`, `nt`, `wf` unchanged. Limit ARCH states: a job with one PR-less phase and another repo's PR in prose is refused until the prose is reworded (P3R2-2's cost, wider).
  3. In the Status-cell branch, also read each PR in `other` that has a `gate-logs/ci-pr-<n>.json` in this job (CRIT-1, SFH-1, PEN-1). Shown incomplete: silent-failure-hunter ran it as mutant m23 (the suite still passes; `tworows` then ends `END 10: PR #8 CI red or unfinished`), then ran `probe3.sh` with PR 8's record deleted: still `=> DONE PASSES`. Deleting the record becomes the way out. PEN-1 adds a second limit: a record written for an unrelated PR after P3R2-2's refusal would go on being read.

  Under any of the three, a row the runner does not see (key `P1`) stays unseen; architect-reviewer: that "needs the row-recognition decision (P3R1-29), not this fix".
- **Severity.** HIGH from all five. It is HIGH on the rubric clause "a fail-open a realistic input reaches" whichever way P3R1-1's status is read (see the round-1 table).

#### P3R2-2 | HIGH | lib/ci.sh:74-76,90

- **Failure path.** A job with no PR in any Status cell (no PR of its own, a table-less job, or its PRs written `PR 7`) whose prose links `https://github.com/o/other/pull/99`. The fallback reads 99 and refuses. The hint says "write any other PR with no '#'"; the link has no '#', so following it changes nothing. "Name this job's PR in its row's Status cell" has no row to act on in a table-less job (ARCH-2). The last `run.log` line, the one `README.md:132` sends the reader to, says `blast-off ci-wait <job-dir> 99`. `ci_wait` runs `gh pr view 99` in the workdir (`lib/ci.sh:17-18`), so it reads this repo's PR 99. CRIT-13: the hint is one line doing two jobs, and on the refusal of the job's own red PR its second half is the cheaper instruction.
- **Strongest evidence** (penetration-tester, `b8.sh`):

  | Case | run.log | Result |
  |---|---|---|
  | `e_norec` | `no Phase plan Status cell names a PR; CI read for every PR checkpoint.md names instead: 99 (name this job's PR in its row's Status cell; write any other PR with no '#')` then `PR #99 CI unread: … blast-off ci-wait <job-dir> 99, then run again` | exit 10 |
  | `ci-wait 99`, no PR 99 in this repo | `gh pr view 99 failed` | exit 1, then exit 10 again |
  | `e_green` (an unrelated green PR 99 here) | `ci PR #99 at 222…: success`, then `job done` | exit 0 |
  | `e_red` | `PR #99 CI red or unfinished at 222… ; fix and push if red, …` | exit 10 |
  | `e_absent` | `PR #99: no CI runs and no workflow file at HEAD (absent, not a pass)`, `job done` | exit 0 |

  Ways out that work, all exit 0 with `no PR named in checkpoint.md; CI not read`: `other PR 99 in o/other`, `o/other branch fix/thing`, `o/other#99`, `github.com/o/other pull 99`. Only the first two are in any text, and no text says a link counts.
- **Reviewers differ on direction.** silent-failure-hunter: "The gate itself fails closed here; this is a false refusal with a wrong remedy, not a fail-open." security-reviewer (`x_own_nohash`: this repo's PR 99 green, `=> DONE PASSES`, the job's own `PR 7` unread) and penetration-tester (`e_green`, `e_absent`) ran exit 0 after following the refusal. Both stand: the first refusal is fail-closed; following its instruction can pass `done` on an unrelated PR's CI.
- **Suggested fixes.**
  - Text only (ARCH-2, CRIT-3, SFH-2, PEN-3): reword the hint to cover both tokens ("no '#' and no /pull/ link"); in the fallback, end each per-PR refusal with why the PR was read and what to do if it is not this job's, instead of `ci-wait N`; add the `/pull/` clause to `templates/checkpoint.md:32`. This gives a way out; prose is still read, so criterion 3 stays unmet for these jobs.
  - Code (SEC-3): in the fallback read only `PR #N` tokens and `/pull/N` links whose `owner/repo` is absent or matches the workdir's remote. Closes more: the link case is no longer read at all. A bare `PR #99` of another repo in prose is still read. SEC adds P3R2-9's ancestor check so a wrong-PR read fails closed.
  - Owner's alternative (a), fallback only when `cp_phases` is 0 (SFH-2): mutant m13 shows the suite forbids it today (case `np`), so it needs the owner's word. Whether to keep the fallback at all is owner question 1 (CRIT-3).
- **Severity.** HIGH from all five ("an acceptance criterion not met", "instruction text that tells an agent to do the wrong thing"). CRIT-13 was filed LOW and is the same line and root cause.
- **Carries** round-1 P3R1-30 (another repo's `/pull/N` inside a Status cell is read): still open (ARCH and CRIT `xrepo_link_status`, SEC `x_status`, PEN-5's table).

#### P3R2-3 | HIGH | lib/ci.sh:86-87 (README.md:132, docs/spec.md:97)

- **Failure path.** The workflow is added in a later phase. Earlier stacked PRs (heads and bases cut before it) have absent records; the workdir's HEAD has the file, so `done` is refused with "push to the PR branch for a run that is not a workflow_dispatch". By the reviewers' recall of GitHub, a `pull_request` run takes its workflow from the PR's merge ref and a `push` run from the pushed commit; neither holds the file, so no push starts a run. `ci-wait` records absent again and the refusal repeats. Same for `branches: [main]` on a stacked base, a `paths:` filter, a dispatch-only workflow, or a non-workflow file (CRIT-7, SEC-4, PEN-2). `README.md:132` and `docs/spec.md:97` say "there is no override". The exits left are a hand-edited record or deleting ` · PR #N` from the cell, which P3R2-1 passes. ARCH-3 and SFH-5: this is the incident issue 26 cites (PRs 1 to 8 predate `ci.yml`).
- **Strongest evidence** (penetration-tester, `b9.sh`; the fake gh decides which commit has runs):

  | Step | Output | Result |
  |---|---|---|
  | `ci-wait 7`, `ci-wait 8`, run | `CI read for the PRs Phase plan Status cells name: 7 8` then `PR #7 CI absent: no runs, but HEAD has a workflow file (.github/workflows/ci.yml); push to the PR branch for a run that is not a workflow_dispatch, …` | exit 10 |
  | new commit on branch `a` (no workflow there), `ci-wait 7`, run | `ci PR #7 at 156e571…: absent ()`, then the same refusal | exit 10 |
  | ` · PR #7` removed from row 0's Status cell | `CI read for the PRs Phase plan Status cells name: 8; named elsewhere in checkpoint.md and not read: 7` then `job done` | exit 0 |

  GitHub's half is REASONED in all five reports and tested by none.
- **Suggested fixes.**
  - Decide "runs were due" from the commit the record is of: `ls-tree` the record's `head_sha`, not HEAD (ARCH-3, PEN-2). ARCH: a head object missing locally is a refusal. PEN: fall back to HEAD, and say so. Closes the stacked case and four rows of P3R2-7. Limits stated: a workflow only on the base is not seen (ARCH; PEN `default_only`); the branch-filter, dispatch-only and non-workflow-file cases stay dead ends.
  - An override the agent cannot set, read from the runner's environment (for example `BLAST_OFF_CI_ABSENT_OK="7 8"` passed at `start`), logged as an owner override (SEC-4). Covers the cases the first fix leaves. It is owner question 3.
  - Message only (CRIT-7, SFH-5, and ARCH-3 if HEAD stays the key): say what must be true for a push to help, and what to do when it is not (set `blocked` for the owner). Closes nothing in the code; stops the wrong instruction.
- **Severity.** ARCH-3 and PEN-2 rate HIGH; CRIT-7, SFH-5 and SEC-4 rate MEDIUM. HIGH stands. The refusal line is the instruction the agent acts on, and it tells the agent to do something that cannot work for the skill's default delivery (one stacked PR per phase); that is the rubric's "instruction text that tells an agent to do the wrong thing". penetration-tester ran the loop and the token removal that ends it. None of the three MEDIUM reports argues against that clause; with the cap off, the reviewer's higher rating is kept. The caveat stays: the GitHub half is from recall.

#### P3R2-4 | HIGH | templates/checkpoint.md:29-32

- **Failure path.** Children read this comment every session; it is headed "Rules the runner enforces on this file". New sentence: "A row closed without one gets no CI check, and a PR named only outside the Status cells is not read". Line 32 keeps "Name any other PR by its branch or as `other PR <n>`, no '#'". A child stuck at exit 10 (red CI, or P3R2-3's dead end) reads the exact edit that ends the refusal. `tests/51-templates.sh:74-75` pins the sentences. CRIT-2 notes the sentence is round 1's own suggested wording for P3R1-5.
- **Strongest evidence** (critical-thinking, stubs): `evade_before` (Status `PR #7`, record red): `END 10: PR #7 CI red or unfinished`. `evade_after` (both mentions rewritten `other PR 7`): `LOG: no PR named in checkpoint.md; CI not read`, `=> DONE PASSES`. `evade_mixed` (token dropped from one row only, another row green): `named elsewhere ... not read: 7`, `=> DONE PASSES`. The same passes were reproduced with errexit on under P3R2-1 and P3R2-2.
- **Suggested fix.** The three reviewers converge: state the duty, drop "gets no CI check", change the pin in `tests/51-templates.sh:74-75` in the same commit. CRIT-2: "Every closed row names its PR there: the runner reads this job's PRs from Status cells", and log each done row whose cell names no PR. SEC-2: keep the read rules in `docs/spec.md` only. ARCH-5: after P3R2-1's fix the sentence becomes "every closed row names its PR; a row without one makes the runner read every PR named anywhere here"; pin one phrase, not three.
- **Severity.** CRIT-2 rates HIGH; SEC-2 and ARCH-5 rate MEDIUM. security-reviewer's argument in full: "The sentence is accurate and describes; it does not instruct, so the rubric's 'instruction text that tells an agent to do the wrong thing' does not fit. The fail-open it points at is SEC-1, which carries the HIGH." It adds that the finding stands or falls with SEC-1: once P3R2-1 is fixed the sentence is false and must go. critical-thinking's reading: the text sits in the rules block of a file children treat as instructions, states as neutral fact what leaving the token out buys, and (CRIT-4) "one" can be read as "a CI record", which reads as permission to skip `ci-wait`. HIGH stands: the rubric clause fits on critical-thinking's reading and no clause rules it out; the cap is off and the consolidation rule keeps the higher reviewer rating. The split is real and is recorded in "Excluded or contested". The gate result does not turn on it.

#### P3R2-5 | MEDIUM | lib/ci.sh:97

- **Failure path.** GNU grep treats input holding a NUL as binary: `binary file matches` goes to stderr, exit 0, nothing on stdout. `|| true` and the pipeline see no failure. A NUL in a Status row, or anywhere when the PR is only in prose, empties both reads: `no PR named in checkpoint.md; CI not read`, exit 0, with a PR named in plain text. A NUL elsewhere keeps the cell read but silently empties the "named elsewhere" list. Invalid UTF-8 does not trigger it (all five under `C.UTF-8`; CRIT, SFH and PEN also under `C`).
- **Strongest evidence** (penetration-tester, `b2.sh`, both locales; `b11.sh` for the fix): `nul_elsewhere_prosePR` and `nul_in_status_cell`: `no PR named in checkpoint.md; CI not read`, `job done`, exit 0. "RAN: with `-a` all three NUL cases above are refused, exit 10."
- **Suggested fix.** `command grep -aoiE` in `ci_prs` (all five). Carries round-1 P3R1-28, whose `grep -a` half the fix baton left undone with no reason given (CRIT).
- **Severity.** MEDIUM from all five.

#### P3R2-6 | MEDIUM | lib/ci.sh:97

- **Failure path.** The regex is the gate's whole arming condition. A Status cell that names PRs as `PRs #7, #8`, `PR 7`, `#7`, `PR  #7`, `PR: #7`, `PR-7`, `pull request #7`, `**PR** #7`, `o/r#7`, `.../pulls/7` reads no PR; both reads share `ci_prs`, so the fallback sees nothing either: `no PR named in checkpoint.md; CI not read`, exit 0. The log line is untrue. `PR #7, #8` reads 7; 8 is neither read nor listed as "named elsewhere". Beside a well-formed row (CRIT-9, SEC-7) the missed PR leaves no trace at all, so the fix baton's claim that such a cell "now ends in line 2 or 3" is wrong there.
- **Strongest evidence** (penetration-tester, `b3.sh`, each with no CI record): `PRs #7, #8`: none read, exit 0. `PR #7, #8`, `PR #7/#8`, `PR #7 and #8`: 7 only; "with a success record for 7: exit 0, PR 8 never mentioned (`list_rec`)". critical-thinking `mixed_nohash` (stubs): `LOG: CI read for the PRs Phase plan Status cells name: 7`, `=> DONE PASSES`, with `ci-pr-8.json` `failure`.
- **Suggested fixes.**
  - Fail closed on a cell the runner cannot fully read (PEN-5, SFH-3): where a done row's cell holds more `#<digits>` tokens than `ci_prs` reads from it, or holds `PR` or `pull` and nothing is read, refuse with exit 10. Closes the most without widening the regex.
  - Widen the read inside Status cells only (ARCH-8, SEC-7): count any `#N` after a `PR`/`PRs` word, or any `#N`; keep the strict token for the whole-file read. critical-thinking: the baton's reason for refusing to widen ("`PR <n>` with no '#' is the template's way to name another PR") is a prose convention and does not apply inside a Status cell.
  - At least reword the line: "no `PR #N` or `/pull/N` token in checkpoint.md" (ARCH-8, SFH-3, SEC-7), and name in `run.log` each done row whose cell yields no PR (CRIT-9).
- **Severity.** MEDIUM from all five. Carries round-1 P3R1-9.

#### P3R2-7 | MEDIUM | lib/ci.sh:86-88

- **Failure path.** Absent record, and the workflow file is on the PR's branch but not at the workdir's HEAD: a side branch or linked worktree checked out, a HEAD that deleted or renamed the workflow (SEC-10), a workflow only on the default branch, or one uncommitted whose path the checkpoint names. Runs were due and did not come; `done` passes as "no workflow file at HEAD".
- **Strongest evidence** (penetration-tester, `b5.sh`, `b12.sh`): `pr_branch_only`, `wt`, `default_only`, `deleted_at_head`, `detached`: `PR #7: no CI runs and no workflow file at HEAD (absent, not a pass)`, exit 0. Untracked or staged workflow: exit 7 unless the checkpoint names the path, then `job done`, exit 0.
- **Suggested fix.** P3R2-3's first fix (read the record's `head_sha`; PEN-6, SEC-10). PEN states what it does not close: `default_only` and the uncommitted-and-named rows.
- **Severity.** PEN-6 rates MEDIUM; SEC-10 rates LOW (as one half of a two-part finding). MEDIUM stands: an edge-case defect on the gate's pass path, shown by run. Carries round-1 P3R1-3 (owner question 2).

#### P3R2-8 | MEDIUM | lib/ci.sh:86-87

- **Failure path.** Absent record, and HEAD holds `.github/workflows/.gitkeep`, `README.md`, `ci.yml.disabled`, `sub/ci.yml`, a dispatch-only `manual.yml`, a symlink, or a plain file named `.github/workflows`. Each refuses `done` and the message calls it "a workflow file". No push can start a run. Fail-closed, with P3R2-3's exit.
- **Strongest evidence** (penetration-tester, `b5.sh`): cases `gitkeep`, `notyaml`, `disabled_ext`, `nested`, `dispatch_only`, `symlink_dir`, `symlink_file`, `file_named_workflows`: all exit 10 with `HEAD has a workflow file (.github/workflows/README.md)` or the like.
- **Suggested fix.** Count only `*.yml` and `*.yaml` directly under the directory. A dispatch-only or branch-filtered workflow still needs the owner's answer to question 3. Carries round-1 P3R1-4.

#### P3R2-9 | MEDIUM | lib/ci.sh:81,103-108

- **Failure path.** The checks are `.pr == N` and "record head equals `gh pr view N` head now". PR N may be an old merged PR, an unrelated PR with the number of another repo's link (P3R2-2), or the job's PR at a head that lacks the row's gated commit (commits made after the last push are never seen by CI). All pass.
- **Strongest evidence** (security-reviewer): RAN `decoy` (PR #1 green in a cell, the job's PR #8 red: passes). The unpushed-commit case is REASONED from `lib/ci.sh:103-108` and `lib/receipt.sh:45-65`.
- **Suggested fix.** For a PR read from a row, require `git -C "$TOP" merge-base --is-ancestor <row sha> <record head_sha>`; refuse with "PR #N head does not hold row K's commit".

#### P3R2-10 | MEDIUM | lib/ci.sh:81,105-107

- **Failure path.** The child writes the record by hand. `ci_head` only checks that `head_sha` equals the PR's head now, which the child can read.
- **Strongest evidence** (penetration-tester, `b7.sh`, `b6.sh`): `{"pr":7,"verdict":"success","head_sha":"111…"}` with no `runs`: exit 0. Also exit 0: a duplicate `verdict` key, `success` with a failed run in `runs`, `"pr":7.0`, a symlink to another job's record.
- **Suggested fix.** An owner decision. One `ci_runs "$head"` at done, compared with the record's run ids, would make the record a cache of what the runner can check.
- **Severity.** PEN-8 rates MEDIUM. Round 1 filed the same as P3R1-40, LOW, "file separately". security-reviewer treats it as the baseline its grades are set against, not as a finding. The reviewer's MEDIUM is kept.

#### P3R2-11 | MEDIUM | lib/ci.sh:41

- **Failure path.** A workflow whose jobs carry `if: github.event.pull_request.draft == false` ends `skipped` on a draft PR. `ci-wait` records `success` and `done` passes with no check having run.
- **Strongest evidence** (penetration-tester, `b6.sh`): conclusion `skipped` gives `ci-wait rc=0 verdict=success`; so does `neutral`. That GitHub reports such a run as `skipped` is REASONED.
- **Suggested fix.** `success` needs at least one run whose conclusion is `success`; all skipped or neutral is `absent`. Round 1 filed this as P3R1-41, LOW; documented behaviour in `docs/spec.md:58`.

#### P3R2-12 | MEDIUM | lib/checkpoint.sh:11,40-45; lib/ci.sh:70

- **Failure path.** (1) Indented rows, `### Phase plan`, `## Phase Plan`, a BOM before the heading, CR-only line ends, key `P0`, rows with no leading `|`: `cp_phases` is 0, so no receipt is checked and no open row is seen. CI falls back to the whole file, so `done` is refused only if a readable PR token exists somewhere; with an unreadable one nothing at all is checked (`indented_nopr_elsewhere`: Status `PR 7`, exit 0). (2) `## Phase plan`, rows, `## Phase plan`, rows: sed's range ends on the second heading and does not start again on it, so a `pending` row in the second table is not seen.
- **Strongest evidence** (penetration-tester, `b4.sh`): `two_adjacent`: `phases=1`, `open_rows=[]`, the all-done check passes with a pending row. The shipped template with rows closed and no PR written passes with `no PR named in checkpoint.md; CI not read` (`tpl_asis`).
- **Suggested fix.** At `status: done`, refuse when `cp_phases` is 0 and the file holds a line that looks like a table row or a heading matching `phase plan` in any case.
- **Synthesizer check.** ARCH-12 says a second `## Phase plan` heading re-opens the range; PEN-9 says it does not. Both are right: ARCH's `twoheads` fixture has `## Other` between the two headings; PEN's `two_adjacent` has none. No contradiction.

#### P3R2-13 | MEDIUM | lib/ci.sh:73,76,78 with lib/chain.sh:159

- **Failure path.** In P3R2-1, P3R2-5, P3R2-6 and the "no PR named" case the runner exits 0 and its last line is `job done`. Nothing prompts anyone to read the line above it. The fix treats "logged" as the remedy for P3R1-2 and P3R1-9.
- **Evidence** (critical-thinking): REASONED from `lib/chain.sh:159` and the RAN outputs above.
- **Suggested fix.** Carry it in the final line: `job done; CI read for PRs 7; named and not read: 8` or `job done; no CI read`.

#### P3R2-14 | MEDIUM | lib/ci.sh:86-88

- **Failure path.** `TOP` empty skips `ls-tree`; an absent record then passes with `PR #N: no CI runs and no workflow file at HEAD (absent, not a pass)`. Nothing was read and there is no HEAD. `tests/41-ci-wait.sh:130` pins the wording for this non-git case. Reach is narrow: the real `gh` fails outside a repo unless `GH_REPO` is set (SFH-7, PEN-11).
- **Strongest evidence** (penetration-tester, `b5.sh` case `nogit`): that line, then `job done`, exit 0, while `.github/workflows/ci.yml` sits on disk.
- **Suggested fix.** Log `workdir is in no git repo; workflow files not read` on that branch (all four).
- **Severity.** SFH-7 rates MEDIUM; ARCH-15, SEC-10 and PEN-11 rate LOW. MEDIUM stands: the line states something untrue on the gate's pass path, which is the rubric's "a doc or message that could mislead", not "wording". It carries round-1 P3R1-31 (the baton's row for this wording); ARCH-15 and SFH-7 cite P3R1-32, which is a different row (the fake `gh` working outside git).

#### P3R2-15 | MEDIUM | docs/spec.md:97; lib/ci.sh:64-66

- **Failure path.** Spec row 10: "so a missing table, a heading or row the runner does not read, or a row closed without its PR never lets done through with a named PR unread, P3R1-1". The comment: "The gate fails closed (P3R1-1): when no Status cell names a PR (..., a row the runner does not read, a row closed without its PR)". Both hold only when no other cell names a PR. A reader takes "never" and "fails closed" as the gate's guarantee.
- **Evidence.** REASONED from those lines against the RAN cases of P3R2-1 (`mono_b`, `tpl_shape`, `p1row`, `mixed_tpl`).
- **Suggested fix.** Fix P3R2-1 and keep the sentence, or change "never" to "when no Status cell at all names a PR" (ARCH-4, CRIT-1).

#### P3R2-16 | MEDIUM | templates/checkpoint.md:29-32

- **Failure path** (critical-thinking; a child acts on the wrong reading of one of these):
  - "A row closed without one": "one" can be the `PR #<n>` token or the nearer noun, "a CI record", which reads as permission to skip `ci-wait`.
  - "unless no Status cell names a PR" can govern one clause or both. Under the likely reading the first clause is unconditional, and case `np` (`tests/41-ci-wait.sh:148-152`) contradicts it.
  - "gets no CI check" is per row; the code checks per PR. Four phrases stand for one thing.
  - The reason for "Name any other PR ... no '#'" was dropped, so it now looks optional; it still matters when the fallback fires.
  - No child-facing text says an `absent` record is refused where HEAD has a workflow file.
  - The template never says "last cell". A cell holding `\|`, or a row with no closing `|`, is not the cell read.
- **Evidence.** REASONED from the diff; RAN (stubs) `escpipe` and `notrail` for the last point: both fall back.
- **Suggested fix.** Three short sentences, one fact each: where the runner reads PRs; that every closed row must name its PR there; how to name a PR that is not this job's (including "no /pull/ link").

#### P3R2-17 | MEDIUM | skills/blast-off/SKILL.md:34-37

- **Failure path** (critical-thinking). "with no CI" now opens a sentence whose second half is about a repo that has a workflow file; the case that bites (workflows that exist but do not run on this PR) is not named. "say which holds in brief §2" is decided at scoping, but the code reads HEAD at `done`; a phase that adds a workflow flips it after §2 is written. Nothing tells the scoping agent to check that the repo's workflows run on stacked PRs.
- **Evidence.** REASONED; GitHub's branch-filter behaviour is from recall.
- **Suggested fix.** "if the repo has a file under `.github/workflows/`, check its triggers run on a PR whose base is a phase branch; if not, settle that with the owner before launch. The runner refuses `done` for a PR with no runs while HEAD has such a file."
- **Note.** architect-reviewer, silent-failure-hunter and security-reviewer read the same step as matching the code (P3R1-6 resolved). They judged accuracy; critical-thinking judged what the scoping agent will do with it.

#### P3R2-18 | MEDIUM | templates/brief.md:135,142-144

- **Failure path** (critical-thinking). Step 4 says "absent checks are not a pass", then "After ci-wait, set the row's Status to `done ...`" whatever `ci-wait` returned. With a workflow file at HEAD, a child that sees `absent` in phase 0 closes the row and goes on; the runner refuses only at the final `done`, after every phase has spent its usage. Step 4 also says "No code commit after the receipt (the runner refuses with exit 9)" while the refusal at `lib/ci.sh:87` says "push to the PR branch"; neither says "an empty commit".
- **Evidence.** REASONED from `templates/brief.md:131-146`, `lib/ci.sh:84-88`, `lib/receipt.sh:54-63`. The file is not in the diff.
- **Suggested fix.** One clause in step 4: "absent where the repo has a workflow file: `done` will be refused; record it under Open or blocked with the workflow's trigger, do not close the job".

#### P3R2-19 | MEDIUM | README.md:132

- **Failure path.** "done refused: the CI of a PR named in a Phase plan Status cell ..." is false in the fallback, where a prose PR causes exit 10. The line that explains why a prose PR was read is the one before the last. "Absent: push to the PR branch so a run starts" is P3R2-3's remedy. Lines 114-117 are accurate (ARCH-6).
- **Evidence.** REASONED from `lib/ci.sh:74-76,87-90`.
- **Suggested fix.** ARCH-6: "a PR named in a Phase plan Status cell (or, with none there, anywhere in `checkpoint.md`)"; add "a PR that is not this job's: reword it as `other PR N`, no `/pull/` link". CRIT-12: "a PR the runner read (run.log names them)".
- **Severity.** ARCH-6 rates MEDIUM; CRIT-12 rates LOW. MEDIUM stands: a doc row that does not describe a case it is looked up for is "a doc that could mislead".

#### P3R2-20 | MEDIUM | tests/41-ci-wait.sh:94-131,139-156; tests/51-templates.sh:74-75

- **Failure path.** `fin` asserts PRs 96 to 99 are "not read" and none has a record, so no test shows what happens when a PR named elsewhere has a red record of this job. Owner question 4 is untested in both directions. `nt`, `np`, `ub` pin prose being read, against criterion 3 as written, with no comment that this is a stated departure. No case has `PRs #7, #8`, `PR #7, #8`, or a NUL. `tests/51-templates.sh:74-75` pins three sentences of a rule four owner questions leave open, so fixing P3R2-4 fails the gate until the test changes.
- **Strongest evidence** (silent-failure-hunter): mutant m23 (read every "named elsewhere" PR that has a `ci-pr-N.json`) SURVIVED: `PASS 41-ci-wait`.
- **Suggested fix.** One job with two done rows, one PR in a Status cell (green record), one only under Completed phases with a red record, asserting whatever the owner decides; one `PR #7, #8` row. Pin one phrase of the template, not three.

#### P3R2-21 | MEDIUM | lib/ci.sh:70

- **Failure path.** `sed -n '/^## Phase plan/,/^## /{/^| *[0-9]/p}'` now sits in `lib/checkpoint.sh:11,40,48,54`, `lib/preflight.sh:77` and `lib/ci.sh:70`; `$(NF-1)` in `lib/checkpoint.sh:41,56` and `lib/ci.sh:70`. A later phase that changes row recognition must change six places, and no test checks that receipts and CI agree on what a row or a Status cell is. Synthesizer check: a read-only grep of `lib/*.sh` gives those six `sed` lines.
- **Suggested fix.** One line in `lib/checkpoint.sh`, `cp_status_cells() { <the sed> | awk -F'|' '{ print $(NF-1) }'; }`, called by `ci_check`. Carries round-1 P3R1-29.

#### P3R2-22 | MEDIUM | eight places (see table)

- **Failure path.** Any owner answer, or P3R2-1's fix, means editing all of them in step; two are pinned by tests on exact wording (`51-templates` three sentences, `41-ci-wait` two log lines). Drift between them is how round 1's five doc findings arose.
- **Suggested fix.** Keep the full rule in spec row 10 and the `ci_check` comment; README, template and `--help` state the outcome in one clause and point to the spec. Settle the owner questions before pinning more wording.

### LOW

| ID | file:line | Title | Raised by | Origin | Suggested fix |
|---|---|---|---|---|---|
| P3R2-23 | `lib/ci.sh:53-54`; `tests/fakes/gh:22-30` | `--limit 100` is applied by gh before the jq filter, so dispatch runs can crowd out the PR's runs; the fake models neither the limit nor field validation (mutant m25 `--limit 1` survived) | SEC-9, SFH-11 (part) | pre-existing, slightly changed by this diff; P3R1-24, P3R1-33 open | `die` when the unfiltered list has 100 entries; make the fake honour `--limit` and reject unknown `--json` fields |
| P3R2-24 | `tests/41-ci-wait.sh:173-186` | Two more survivors or near-survivors on the workflow read: m26 (pathspec `ci.yml` only) survived; m9 (`git ls-files` for `ls-tree HEAD`) is killed only by `ub`, because `a4` leaves the file in the index | SFH-11 (part) | new in the fix commit (the tests); P3R1-44 open | in `a4`, `git rm --cached` the file as well; a second workflow file name in `a2` |
| P3R2-25 | `lib/ci.sh:107` | The `[ -n "$cur" ]` guard in `ci_head` has no test (m10 survived); reach is a hand-written record with no `head_sha` while `gh pr view` fails | SFH-10 | pre-existing | in the `d3d` step, also try a record with `head_sha` deleted |
| P3R2-26 | `lib/ci.sh:45,52-55` | `ci-wait` leaves dispatch runs out with no word in `run.log` (`absent ()`) | SFH-8 | new in this diff; P3R1-25 open | have `ci_runs` count what it drops; add `, N workflow_dispatch runs left out` |
| P3R2-27 | `lib/ci.sh:81-83` (`:38`) | A `success` record written by phase-2 code from a green dispatch run still passes; records carry no event | SFH-13, SEC-12 | new in this diff (the exposure); P3R1-23 open | record `event` per run and re-derive the verdict, or note in the PR body that old records must be re-made |
| P3R2-28 | `lib/ci.sh:36-43` | A `ci-wait` that dies part-way leaves `ci-pr-N.json.tmp` with verdict success for the runs read so far; reason on stderr only. Fail-closed | SFH-12 | pre-existing | collect the views into a variable first (`views="$(for ...)" \|\| die`), then jq |
| P3R2-29 | `lib/ci.sh:81` | A record whose first JSON value is valid and the rest is not reads as its first verdict. **Contested**: two reviewers saw the runner abort, not pass; see "Excluded or contested" | SFH-9 | pre-existing | `jq -rs 'if length == 1 and .[0].pr == $n then .[0].verdict // "" else "" end'` |
| P3R2-30 | `lib/ci.sh:89,108,45`; `bin/blast-off:47` | A record's `head_sha` and a run's name reach `run.log` raw, newlines and escape sequences included (a forged `job done` line; exit code still 10). Also noted: with `core.quotePath=false` the workflow path in the refusal passes raw bytes above 0x80 | SEC-8 | pre-existing | flatten control characters in `log` once |
| P3R2-31 | `lib/ci.sh:16-18,36-43` | A record carries no repository identity (another workdir, `GH_REPO`, fork plus upstream remotes) | SEC-11 | pre-existing | record `gh repo view --json nameWithOwner` in `ci_wait`; compare in `ci_head` |
| P3R2-32 | `lib/ci.sh:97` | The regex reads PRs out of ordinary words and paths (`expr #2`, `docs/pull/3`), which the fallback turns into refusals | PEN-12 | pre-existing; reachable in prose again through the fix commit | `(^\|[^[:alnum:]])PR ?#[0-9]+` |
| P3R2-33 | `lib/ci.sh:106` | `BLAST_OFF_CI_HEAD=0` switches the head read's timeout off (`timeout 0` is no limit) | PEN-13 | pre-existing | document it, or treat 0 as the default |
| P3R2-34 | `lib/checkpoint.sh:5` | A BOM or UTF-16 at the top hides `status:`; the runner keeps launching children. Not a fail-open | PEN-14 | pre-existing | none needed for the gate; a log line when `cp_status` is empty |
| P3R2-35 | `lib/ci.sh:97` | `paste`: no dependency list should name it; the baton's declaration is right. A missing `paste` fails closed, at `done` only. Separate and pre-existing: `README.md:16` Requirements omits `git`, which `DEPS` checks | ARCH-11 | new in the fix commit | none needed |
| P3R2-36 | `docs/spec.md:228` | "that heading only" is a prefix match: `## Phase planning notes` opens the range | ARCH-12 | pre-existing parser, new doc claim | say "a heading starting `## Phase plan`" |
| P3R2-37 | `docs/spec.md:97` | "the Status cell is the last cell" holds only for a row with a trailing pipe | ARCH-13 | pre-existing parser, new doc claim | with P3R2-21's helper, strip or require the trailing pipe in one place |
| P3R2-38 | `lib/ci.sh:2,86` | `ci_check` reads the global `TOP` that only `chain_run` sets; a second caller would die under `set -u` | ARCH-14 | new in this diff | none now; pass the repo root as an argument when a second caller appears |
| P3R2-39 | `bin/blast-off:37-38`; `docs/spec.md:35` | Header and F7 row are accurate as summaries; two wording nits (the last clause can be read on all three cases; F7 names `lib/chain.sh` for a refusal that is in `lib/ci.sh`) | ARCH-16 | new in the fix commit (header); pre-existing (F7) | reword if touched |

## Round-1 findings: status

"nc" is "not checked". A status is given per reviewer only where that reviewer gave one.

| ID | Status | Who said what | Carried by |
|---|---|---|---|
| P3R1-1 (HIGH) | reshaped (disputed) | ARCH, CRIT, SFH: reshaped. SEC: resolved. PEN: resolved for its listed shapes. See below | P3R2-1; residue P3R2-5, P3R2-6 |
| P3R1-2 | reshaped | ARCH, SFH, SEC, PEN: reshaped (logged, still exit 0, a red record passes). CRIT: open ("logged" is the whole remedy) | P3R2-1, P3R2-13 |
| P3R1-3 | open | all five: open; the spec now states the limit | P3R2-3, P3R2-7 |
| P3R1-4 | open | all five: open; message reworded, still a dead end | P3R2-3, P3R2-8 |
| P3R1-5 | reshaped | ARCH: reshaped (now true, and tells the child how a row skips the check). SEC: reshaped (now accurate, and accurate about how to leave the gate). CRIT: reshaped (no longer false about where PRs are read; now ambiguous, contradicts case `np`, and states the bypass). SFH: resolved; it adds that the lines tell the child how to skip the check and do not cover a link. PEN: resolved, one gap (no word on `/pull/` links) | P3R2-4, P3R2-16, P3R2-2 |
| P3R1-6 | resolved (one dissent) | ARCH, SFH, SEC: resolved. PEN: nc (read only: both cases stated). CRIT: reshaped ("with no CI" and "say which holds" mislead) | P3R2-17 |
| P3R1-7 | resolved as filed; new gaps | SFH, SEC: resolved. CRIT: resolved, one omission. ARCH: reshaped (row wrong for the fallback). PEN: reshaped (remedy cannot work) | P3R2-19, P3R2-3 |
| P3R1-8 | resolved | ARCH, CRIT, SFH, SEC: resolved. PEN: nc | nit in P3R2-39 |
| P3R1-9 | reshaped | ARCH, CRIT, SFH, SEC: reshaped (logged; the line is untrue for these cells). PEN: open | P3R2-6 |
| P3R1-10 | resolved | SFH: resolved (m3, m13 killed). ARCH: resolved for what it asked. CRIT: resolved in part (no mixed case with a record). SEC, PEN: nc | gap in P3R2-20 |
| P3R1-11 | resolved | SFH: resolved (killed by the fix unit; not repeated). PEN: resolved in behaviour (RAN `subdir_workdir`). ARCH, CRIT, SEC: nc | none |
| P3R1-12 | resolved | SFH: resolved. PEN: resolved in behaviour (RAN `unborn`: exit 1). ARCH, CRIT, SEC: nc | none |
| P3R1-13 | resolved | SFH: resolved. PEN: resolved in behaviour (RAN `deleted_on_disk`). ARCH, CRIT, SEC: nc | near-survivor in P3R2-24 |
| P3R1-14 | resolved | SFH: resolved. SEC: resolved by reading (fake's event strings match real gh, RAN). ARCH, CRIT, PEN: nc | none |
| P3R1-15 | resolved | SFH: resolved. ARCH: resolved (fixtures read). CRIT, SEC, PEN: nc | none |
| P3R1-16 | resolved | SFH: resolved. ARCH: resolved (fixtures read). CRIT, SEC, PEN: nc | none |
| P3R1-17 | resolved, with a catch | SFH: resolved. ARCH: resolved, but the `P1` row pins P3R2-1's behaviour as wanted. CRIT, SEC, PEN: nc | P3R2-1, P3R2-20 |
| P3R1-18 | resolved | SFH: resolved (m26, a narrower pathspec, survived: that is P3R1-44). Others: nc | P3R2-24 |
| P3R1-19 | resolved | SFH: resolved. Others: nc | none |
| P3R1-20 | resolved | SFH: resolved (lines 169-176; live in the soft run of m1). CRIT: resolved by reading. Others: nc | none |

**P3R1-1, the disagreement.**

- *Resolved* (security-reviewer; penetration-tester "for its listed shapes"). Rests on: every shape with zero Status-cell PRs and a readable token somewhere now falls back and refuses (SEC RAN no table, no trailing pipe, `\|` in the cell, prose-only; PEN RAN `b4.sh` on all seven listed shapes, exit 10), and every branch logs. Both call the NUL and regex cases residue from code older than the diff.
- *Reshaped* (architect-reviewer, critical-thinking, silent-failure-hunter). Rests on: two of the listed shapes, "a done row with no PR token" and a row keyed `P0`, still pass as soon as another row names a PR (RAN `mono_b`, `p1row`, `mixed_tpl`, `tworows`); the fix's own comment (`lib/ci.sh:64-66`) and spec row 10 list those shapes as covered.
- *Synthesizer check, by reading the round-1 baton.* The P3R1-1 row is scoped to "Zero PRs read from Status cells ... loop never runs, `job done`, exit 0, no log line". The mixed table was filed in round 1 as P3R1-2, MEDIUM. So to the letter P3R1-1 is closed wherever a readable token exists, which is what security-reviewer and penetration-tester tested. In substance the hole moved from "no row names a PR" to "one row does not", and two inputs still read zero PRs and pass (P3R2-5, P3R2-6), now with a log line that is untrue. The status recorded here is "reshaped". Either way P3R2-1 is HIGH on its own clause ("a fail-open a realistic input reaches"), so the verdict does not depend on this reading.

**Round-1 LOW findings reviewers re-checked** (no row was asked for these): P3R1-21 part-resolved, now overclaims (ARCH, CRIT: P3R2-15, P3R2-36, P3R2-37). P3R1-22 reshaped (ARCH, CRIT, PEN: P3R2-3). P3R1-23 open (P3R2-27). P3R1-24, P3R1-33 open (P3R2-23). P3R1-25 open (P3R2-26). P3R1-28 open or reshaped (P3R2-5). P3R1-29 open, one copy worse (P3R2-21). P3R1-30 open (P3R2-2). P3R1-31 open (P3R2-14). P3R1-35 resolved (ARCH). P3R1-40 open (P3R2-10). P3R1-44 open (P3R2-24). The rest: not checked.

**critical-thinking on the fix baton's reasons** (judged from the baton's words, not re-tested): "out of scope" fits the rule in P3R1-3 and P3R1-4 but not the remedy text and "no override" sentences the fix commit itself wrote. P3R1-31 was skipped "for the call budget", a budget reason, not a merit one. A 10-file limit of the fix unit decided P3R1-24, -33, -34 and -43; none is argued to be wrong. P3R1-28's `grep -a` was left with no reason. P3R1-25's reason describes the fix. "Fixed" overstates P3R1-1 and P3R1-2.

## Acceptance criteria

Test lines are of `tests/41-ci-wait.sh` at HEAD. Only critical-thinking and silent-failure-hunter judged the criteria one by one; the other three touched criterion 3 through their findings.

| # | Criterion | Status | Test lines that prove it | P3R2 IDs against it |
|---|---|---|---|---|
| 1 | No runs and a workflow file at HEAD: `done` refused, exit 10 | met, for every PR the gate reads (CRIT; SFH "proved", live under m5, m9, m24) | 169-170 (the absent record is `ci-wait`'s own), 173-176 (`a2`), 177-179 (remedy text, status unchanged), 180-182 (`a3`, workdir a subdirectory), 183-186 (`a4`, HEAD not disk), 191-197 (`ub`, a failing read is exit 1); control 187-190 (`a5`) | P3R2-1 (a PR the gate does not read is not refused), P3R2-3, P3R2-7, P3R2-8 |
| 2 | No runs and no workflow file: `done` allowed, logged | met (CRIT, SFH; live under m27) | 171-172 (`a1`, git repo with other files at HEAD), 125-126 and 130 (workdir in no git repo) | P3R2-14 (the log line is untrue outside git), P3R2-7 |
| 3 | PR numbers only from Status cells; prose ignored | met in part: holds only when at least one Status cell names a PR (CRIT, SFH; ARCH-2, SEC-3, PEN-3 say the same) | proves the half: 94-98 (fixture), 100-101, 109-110, 125-127, 129. Pins the opposite when no cell names a PR: 141-146 (`nt`), 148-152 (`np`), 193-197 (`ub`) | P3R2-2; P3R2-1 and P3R2-6 (the half that holds is where the fail-open is) |
| 4 | `workflow_dispatch` runs count in neither direction | met (CRIT, SFH; live under m1, m11, m12, m18) | 75-76 (PR 14, green dispatch is no pass), 77-78 (PR 15, red dispatch is no failure), 79 (not watched or viewed), 81-82 (PR 16, a push run counts), 169-176 (at `done`, `wf` job) | P3R2-27 (records written before this phase), P3R2-23, P3R2-26. SFH notes, not as a finding: no `done` run uses PR 15's record |
| 5 | Tests for 1 to 4 in `tests/41-ci-wait.sh`; docs updated to match | met in part. Tests: present, with gaps. Docs: SFH reads them as stating what the code does, with remedies that inherit P3R2-2 and P3R2-3; CRIT: "not all match" | n/a | tests: P3R2-20, P3R2-24, P3R2-25. Docs: P3R2-3, P3R2-4, P3R2-15, P3R2-16, P3R2-17, P3R2-18, P3R2-19, P3R2-36, P3R2-37, P3R2-39 |

## Mutation results

Only silent-failure-hunter ran mutants this round: 27, one change each to `lib/ci.sh`, each through `BLAST_OFF_TEST_ONLY=41-ci-wait tests/run` on its copy. 23 killed, 4 survived. Every kill is a `FAIL 41-ci-wait` line with a `| FAIL:` assertion; none died of a syntax error or unbound variable. The fix unit's 11 mutants (M1, M11 to M19, all killed after the new cases) are prior work from the fix baton and were not repeated.

Killed, with the first failing assertion (line of `tests/41-ci-wait.sh`):

| Mutant | First failing assertion |
|---|---|
| m1 drop `select(.event != "workflow_dispatch")` | `green dispatch run counted: exit 0` (76) |
| m2 always read the union (`prs="$all"`) | `green and absent records: exit 10` (126) |
| m3 drop the `elif [ -n "$all" ]` fallback only | `no table, PR in prose, no record: exit 0` (144) |
| m4 drop `ci_head` on the absent branch | `absent record gh could not check: exit 0` (123) |
| m5 absent-with-workflow logs instead of refusing | `absent CI with a workflow at HEAD: exit 0` (176) |
| m6 drop the "named elsewhere and not read" part | `PRs read at done not logged` (129) |
| m7 `s/^0*//` removed | `done with unread CI: exit 10` (101) |
| m8 `-i` removed from grep | `done with unread CI: exit 10` (101) |
| m9 `git ls-files` for `ls-tree ... HEAD` | `ls-tree failing at done: exit 0` (197), by `ub` only |
| m11 unfiltered run list at line 20 only | `green dispatch run counted: exit 0` (76) |
| m12 unfiltered run list at line 30 only | `green dispatch run counted: exit 0` (76) |
| m13 fallback only when there is no table | `done row with no PR, PR named below: exit 0` (152) |
| m14 `/pull/N` dropped from the regex | `second PR unread: exit 0` (110) |
| m15 drop `ci_head` on the success branch | `green record of an old head: exit 0` (120) |
| m16 drop the `.pr == $n` check | `PR 8's record for PR 9: exit 0` (114) |
| m17 whole row read, not the last cell | `green and absent records: exit 10` (126) |
| m18 `--json databaseId` without `event` | `green dispatch run counted: exit 0` (76) |
| m19 `PR #` with the space required | `done with unread CI: exit 10` (101) |
| m20 `ci_head` without the head comparison | `green record of an old head: exit 0` (120) |
| m21 line 81 without `2>/dev/null \|\| true` | `done with unread CI: exit 1` (101) |
| m22 Phase plan range left open to end of file | `green and absent records: exit 10` (126) |
| m24 `ls-tree` also outside git | `green and absent records: exit 1` (126) |
| m27 no log on absent with no workflow | `absent not logged` (130) |

Survived, and the gap each shows:

| Mutant | Gap |
|---|---|
| m10 `[ -n "$cur" ]` guard removed | no test has a record with no `head_sha` while `gh pr view` fails (P3R2-25) |
| m23 read "named elsewhere" PRs that have a record | a proposed fix, not a defect: no test pins what happens to a PR named outside the Status cells when a record for it exists, so owner question 4 is untested in both directions (P3R2-1, P3R2-20) |
| m25 `--limit 1` | the fake `gh` ignores `--limit` (P3R2-23) |
| m26 pathspec `.github/workflows/ci.yml` | "any file under the directory" is pinned for no name but `ci.yml` (P3R2-24; P3R1-44, left open on purpose) |

Near-survivor: m9 is killed only by the last case, `ub`; case `a4` deletes the file on disk and leaves it in the index, so it does not separate the index from HEAD (P3R2-24). The soft run of m1 listed ten failing assertions.

## Owner questions 1-4

**1. No PR in any Status cell: read every PR the checkpoint names** (`lib/ci.sh:74-76`).

- architect-reviewer: yes in direction (it refuses), no as built. Alternative (a) is weaker, (b) breaks PR-less jobs. The key should be per row; the hint is wrong for links and for table-less jobs.
- critical-thinking: not the safe one, in either direction. It brings issue 26's bug back and leaves the gate open once one row is well-formed. Alternative (b), with an explicit `no PR` word for a phase that has none, is the closed one and never reads prose.
- silent-failure-hunter: safe as a gate (RAN). Its cost is larger than the baton states, and it leaves alternative (b) undone, "which is where the real hole is".
- security-reviewer: yes in direction; both alternatives are worse. The cost is larger than the baton says.
- penetration-tester: yes for the gate, with two holes that are not the owner's to choose (P3R2-5, P3R2-6). Keep the default; fix the texts.
- **Consolidated.** Four of five say the default fails closed (ARCH, SFH, SEC, PEN). Two say to keep it (SEC, PEN); architect-reviewer says "no as built" and wants a per-row key; silent-failure-hunter says only that it refuses; critical-thinking prefers (b). All five say the baton understates its cost (P3R2-2), and all five file the mixed table it does not reach as HIGH (P3R2-1). Reviewers split on (b): security-reviewer and architect-reviewer say it breaks jobs with no PR; critical-thinking's `no PR` word is offered as the answer to that.

**2. The workdir's HEAD at `done` decides "runs were due"** (`lib/ci.sh:86`).

- architect-reviewer: no. It refuses earlier stacked PRs for which no push can start a run, and passes absent when HEAD dropped the file or it is uncommitted. The record's `head_sha` is the key under which refusal and remedy agree.
- critical-thinking: closed, and the issue's words. Two costs: the way out cannot work for an earlier stacked PR, and a deleted or uncommitted workflow reads as none.
- silent-failure-hunter: safe in the common direction, unsafe to rely on in the other. The stated remedy cannot work for an earlier stacked PR (REASONED).
- security-reviewer: safe in direction for a workflow added later, not for one removed or renamed. The stated remedy cannot work; a dispatch no longer counts.
- penetration-tester: no. It fails open (P3R2-7, RAN) and refuses for good (P3R2-3; `ci-wait` records absent again, RAN). The record's `head_sha` is the safer commit.
- **Consolidated.** Not safe as built. All five agree the stated remedy cannot work for an earlier stacked PR whose branch has no workflow file; the runner half is RAN, GitHub's half is from recall. Three (ARCH, PEN, SEC) propose reading the record's `head_sha`; PEN shows what that leaves open.

**3. Any file counts, no override** (`lib/ci.sh:86-87`).

- architect-reviewer: yes for the narrow question. Counting only `*.yml`/`*.yaml` is harmless. An override is worth having only if the child cannot write it; without one, the token removal is the real override.
- critical-thinking: closed on paper. In practice the override is deleting the '#', and the template names it. A logged owner override would be safer.
- silent-failure-hunter: fail-closed, so safe alone. Not safe together with question 4's default.
- security-reviewer: fail-closed on its face. An override read from the runner's environment keeps the decision with the owner.
- penetration-tester: safe on paper, not in practice. A logged owner override is safer than the edit. Narrowing to `*.yml`/`*.yaml` is safe.
- **Consolidated.** Fail-closed alone; unsafe in combination with question 4's default, because the only exits from the dead end are the Status cell and the record file. CRIT, SEC and PEN say a logged owner override is safer than the unlogged one; ARCH wants one only if the child cannot write it; SFH says to decide the override before relying on the gate. ARCH and PEN judge the narrowing harmless.

**4. Where some Status cells name PRs, a PR named only elsewhere is logged and not read** (`lib/ci.sh:71-73`).

- architect-reviewer: no. It is the fail-open in P3R2-1. A per-row key reads it without bringing back issue 26's bug for jobs whose every row names its PR.
- critical-thinking: not the safe one where this job dir holds a record for that PR.
- silent-failure-hunter: not the safe default (RAN, red record ignored). Reading it when this job holds a record keeps issue 26's fix and passes the present suite (m23).
- security-reviewer: not the safe default. Read the union whenever a done row has no token.
- penetration-tester: no. `done` passes with a red record in the job's own `gate-logs` (RAN); phase 2 refused it (RAN).
- **Consolidated.** Unsafe, from all five (critical-thinking limits it to a PR this job holds a record for). They differ on the fix; the three options and their shown limits are under P3R2-1.

## Excluded or contested

**Excluded under the exclusion-list rules:** nothing. The reviewer brief carried no `## DO NOT report findings already tracked in:` list, so no finding was dropped as already tracked. Pre-existing findings and findings in files outside the diff (P3R2-10, P3R2-11, P3R2-12, P3R2-18, P3R2-34 and others) are kept and marked by origin.

**Refuted by other reviewers:**

- **P3R2-29 (SFH-9).** silent-failure-hunter ran `probe2.sh` case `garbage` (a valid record followed by a line of garbage) and got `=> DONE PASSES`. security-reviewer names this exact case in its harness caveat: with errexit on (`probe3.sh`) it is rc 5, which `chain_exit` turns into exit 1. penetration-tester's full harness agrees (PEN-8 table: "`success` document then `not json`: the runner aborts on jq's status (exit 1 after `chain_exit`), no state"). Synthesizer check, by reading: line 81's `2>/dev/null || true` does hide jq's failure and `v` is the first verdict, as SFH-9 says; but the `success` and `absent` branches then call `ci_head`, whose line 105 (`h="$(jq -r '.head_sha // ""' ...)"`) has no handler, so jq's failure on the same file stops the runner. silent-failure-hunter's own swallowed-errors table says so for line 105 ("jq failing stops the runner"). The stub harness never reaches line 105 because it stubs `ci_head`. Reading: not a fail-open; `done` ends exit 1 with no state instead of exit 10 "unread". The finding stays in the LOW table at that reduced meaning.

**Contested between reviewers (kept, both positions recorded above):**

- **P3R2-4 severity**: HIGH (CRIT-2) against MEDIUM (SEC-2, with a stated argument; ARCH-5).
- **P3R2-3 severity**: HIGH (ARCH-3, PEN-2) against MEDIUM (CRIT-7, SFH-5, SEC-4).
- **P3R2-14, P3R2-19, P3R2-7 severity**: one MEDIUM against one or more LOW each; the reasons are in each subsection.
- **P3R1-1 status**: resolved (SEC, PEN) against reshaped (ARCH, CRIT, SFH).
- **P3R2-2 direction**: "not a fail-open" (SFH) against exit 0 after following the refusal (SEC `x_own_nohash`; PEN `e_green`, `e_absent`).
- **P3R2-17 against P3R1-6 "resolved"**: three reviewers read SKILL step 4 as matching the code; critical-thinking finds it misleading to the scoping agent.
- **P3R2-10**: a MEDIUM finding to penetration-tester, the stated baseline (not a finding) to security-reviewer, LOW in round 1.

**Attribution slips found in the inputs** (no effect on any rating): ARCH-15 and SFH-7 cite P3R1-32 for the outside-git wording; the round-1 baton's row for it is P3R1-31. P3R2-12's apparent conflict between ARCH-12 and PEN-9 is two different fixtures.

## Report Audit

Verdict: sound with corrections. Ten problems, none of which drops a finding or changes the count of CRITICAL (0) or HIGH (4); one bears on the LOW count (problem 4).

Advisory section, appended by the report adversary. It audits this document against the five source reports, the reviewer brief and the worktree at `ecc6e90`, by reading only (no test, no scenario, no script against the product). "Line" is a line of this report unless a source is named.

1. **Summary marks criterion 1 met with no qualifier.** Line 11 says "Acceptance criteria: 1, 2 and 4 met". The table at line 323 says "met, for every PR the gate reads" and lists two HIGH findings against it (P3R2-1, P3R2-3). critical-thinking's own cell (source line 16) reads "Yes, for every PR the gate reads ... A PR the gate does not read (CRIT-1) is not refused", and CRIT-1 (source line 25) says "in the absent case criterion 1 is simply not applied to PR 8"; line 76 shows an absent record for PR 8 passing at exit 0 (`mixed_absent_wf`). Correction for line 11: "1 met only for the PRs the gate reads (P3R2-1 is a PR it does not read); 2 and 4 met; 3 and 5 met in part".
2. **Owner question 1: "all five" overstated.** Line 381 says "All five say the baton understates its cost". Three say so in words: silent-failure-hunter (source line 205), security-reviewer (243-244), penetration-tester (369-370). architect-reviewer (219-221) and critical-thinking (155) name the same costs but make no comparison with the baton. Line 12's "question 1's fails closed but costs more than the fix baton states" also leaves out critical-thinking's answer, "Not the safe one, in either direction" (source line 155; it is in the body at line 377). Correction: "Three say the baton understates its cost (SFH, SEC, PEN); ARCH and CRIT name the same costs", and add critical-thinking's dissent to line 12.
3. **Owner question 2: consolidated line flatter than the sources.** Line 390 says "Not safe as built." critical-thinking says "Closed, and the issue's words. Two costs" (source line 156); silent-failure-hunter "Safe in the common direction ... unsafe to rely on in the other" (206); security-reviewer "Safe in direction for a workflow added later" (247). Only architect-reviewer (222) and penetration-tester (373) say "no". Line 12 has the two-and-two split right but does not say what the fifth said. Correction: "Two say no (ARCH, PEN); two say safe in one direction only (SFH, SEC); CRIT says closed, with two costs. All five say the stated remedy cannot work."
4. **P3R2-29 carries two labels and is counted.** Line 268 marks it "Contested"; lines 414-416 file it under "Refuted by other reviewers" and conclude "not a fail-open". It is still one of the 17 LOW and the 39 total at line 5, under silent-failure-hunter's original title ("reads as its first verdict"). The refutation holds: security-reviewer source lines 267-270 (rc 5 with errexit on), penetration-tester source line 250 (the runner aborts), and `lib/ci.sh:105` has no handler (checked in the worktree). Correction: use one label, and either retitle the row to the reduced meaning ("`done` ends exit 1 with no state instead of exit 10 unread") or take it out of the count (16 LOW, 38 findings).
5. **P3R2-15 has no severity line.** It is MEDIUM (lines 57, 204-208) and carries part of CRIT-1, which critical-thinking filed HIGH (source lines 24, 27). The other source, ARCH-4, is MEDIUM (source line 79). The HIGH half of CRIT-1 is in P3R2-1, so no count changes, but the report does not say so. Correction: add "ARCH-4 rates MEDIUM; CRIT-1's HIGH is for the gate half, carried by P3R2-1".
6. **Origin column drops security-reviewer's dissent in three rows.** Line 47 (P3R2-5) says "pre-existing made worse"; SEC-6 says "Pre-existing made narrower" (source line 135; its actor table, line 215, says "harder"). Line 44 (P3R2-2) says "new in the fix commit"; SEC-3 says "Pre-existing for the read itself (phase 2 read it too)" (source line 85). Line 266 (P3R2-27) says "new in this diff (the exposure)"; SEC-12 says "Pre-existing made visible by this diff" (source line 203). Correction: name the split in each Origin cell.
7. **Round-1 table: "SFH: resolved" on rows P3R1-12 to P3R1-19 (lines 297-304) is not silent-failure-hunter's own run.** Its source row (line 199) covers P3R1-11 to P3R1-19 with "Killed by the fix unit (not repeated, as told)". The report carries that note only on P3R1-11 (line 296) and in the mutation section (line 331). For P3R1-19 (line 304) no reviewer checked anything else, and for P3R1-18 (line 303) the only reviewer run is m26, which survived; "resolved" there rests on the fix unit's own mutants. Correction: add "(the fix unit's kill, not repeated)" to those rows.
8. **Three statements about what a fix closes are the synthesizer's inference, not a source's, and are not marked.** Line 82: "Closes the no-record, red, stale and absent rows above" is put under ARCH-1 and SEC-1; neither says it (architect-reviewer source lines 30-35, security-reviewer 48-49), and penetration-tester says "closes the red, stale and absent rows" of the other fix (source line 54). Line 105: "A bare `PR #99` of another repo in prose is still read" is not in SEC-3 (source lines 91-93). Line 123: "the branch-filter, dispatch-only and non-workflow-file cases stay dead ends" is not stated with that fix by ARCH-3 or PEN-2; the same line's "four rows of P3R2-7" is four cases in two rows of PEN-6's table (source line 210). Correction: mark each "synthesizer check, by reading", as the report does elsewhere.
9. **Two source details left out.** Line 187 gives `two_adjacent` as "the all-done check passes with a pending row" and omits penetration-tester's next clause, "it was refused only because the fallback read PR 7" (source lines 266-267): no run shows exit 0 for the second-heading half of P3R2-12. Line 246 gives silent-failure-hunter's test and leaves out critical-thinking's smaller one, "copy a red record in as `ci-pr-98.json`" in `fin` (source line 105).
10. **Line 33 names `x_own_nohash` as an errexit-on run.** security-reviewer states errexit for `decoy` (source line 43) and for `nul_cell` and `nul_prose` (line 132), not for `x_own_nohash` (lines 82-83). The errexit reproduction of P3R2-2's pass rests on penetration-tester's `e_green` (source line 117, harness at lines 11-15), which line 33 also cites. Correction: cite `e_green` alone for that claim.

Checked and found correct:

- Check 1, dropped findings: sources filed 68 (ARCH 16, CRIT 13, SFH 13, SEC 12, PEN 14); the report maps 68. Every source ID sits in a "Raised by" cell of one of the two tables; none is only in "Excluded or contested".
- Check 2, dedupe: each merge shares a failure path and a fix. The four splits (CRIT-1, ARCH-5, SEC-10, SFH-11) follow two-part source findings. CRIT-13 (LOW) inside P3R2-2 is stated at line 107, and CRIT-13's own fix defers to CRIT-3. The `tests/51-templates.sh:74-75` pin shows under P3R2-4, P3R2-20 and P3R2-22; it is one edit and no count depends on it.
- Check 3, severity: no finding sits below its highest source rating. P3R2-3, P3R2-4, P3R2-7, P3R2-14 and P3R2-19 keep the higher rating and give a rubric clause for it. No severity is above every source's. The 13 source HIGH ratings all land in P3R2-1 to P3R2-4.
- Check 4, evidence: the Evidence column matches the sources' RAN and REASONED marks for all 22 rows. The quoted tables match their sources cell by cell (P3R2-1 `b1.sh`, P3R2-2 `b8.sh`, P3R2-3 `b9.sh`, the 27-mutant table).
- Check 4, file:line against the worktree, all 22 MEDIUM-and-above rows: `lib/ci.sh` 41, 64-66, 69-78, 81, 86-90, 97, 103-108; `lib/chain.sh:159`; `lib/checkpoint.sh:11,40-45`; `templates/checkpoint.md:29-32,47-49`; `templates/brief.md:135,142-144`; `tests/51-templates.sh:74-75`; `tests/41-ci-wait.sh` (every line cited); `README.md:114-117,132`; `docs/spec.md:35,58,97,228`; `skills/blast-off/SKILL.md:34-37`. All match.
- Check 4, the synthesizer's own checks: the six `sed` lines and three `$(NF-1)` lines (line 250); `twoheads` has `## Other` between its headings (`rev2/probe.sh:35`), so ARCH-12 and PEN-9 do not conflict (line 189); P3R1-31 is the outside-git wording and P3R1-32 the fake `gh` (round-1 baton lines 83-84); P3R1-40 and P3R1-41 are LOW, "File separately" (lines 92-93); the P3R1-1 scope quote at line 311 (round-1 baton line 48); the gate log's last line (line 17); "all 11" fix-unit mutants (fix baton line 126).
- Check 5, round-1 status table: every per-reviewer status in rows P3R1-1 to P3R1-20 matches that reviewer's own table (problem 7 is about a missing note, not a wrong status). The P3R1-1 disagreement is stated as the sources have it: SEC and PEN resolved, ARCH, CRIT and SFH reshaped.
- Check 5, acceptance criteria table: statuses for criteria 2 to 5 and every test line match critical-thinking's and silent-failure-hunter's tables and `tests/41-ci-wait.sh`; the report's ranges take in the comment line above each assertion.
- Check 5, owner questions: each per-reviewer bullet for questions 1 to 4 matches its source. Questions 3 and 4 are consolidated correctly.
- Check 5, "How this review ran" and the mutation section: each reviewer's method, temp dirs, the two items silent-failure-hunter named, the 29 runs, 23 killed and 4 survived match the sources.
- Check 6, format: 22 rows start `| P3R2-<n> | <SEVERITY> |` (4 HIGH, 18 MEDIUM), seven columns each; the LOW table has 17 rows; IDs 1 to 39 are unique and in order HIGH, MEDIUM, LOW; the counts at line 5 equal the rows. The LOW table has no Severity column, so a reader that counts LOW by that row pattern gets 0; LOW is the 17 rows of the second table.

Not checkable from the named inputs: the consolidation rule behind "WARN" and "The HIGH cap is off; nothing was demoted" (line 5), and line 17's account of how the skill and the synthesizer ran. They come from the skill, not from the sources or the brief.
