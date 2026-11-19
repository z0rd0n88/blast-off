# critical-thinking review: phase 3 round 2

Reviewed `git diff feat/br-1115-issues/phase-2...HEAD` at `ecc6e90`, by reading and by scratch scripts
that source `lib/ci.sh` with stubs. No `tests/run` was run (not allowed for this reviewer).

"RAN (stubs)" below means: `ci_check` from `lib/ci.sh`, with `log`, `chain_end`, `die` and `ci_head`
stubbed and `TOP` empty, on a checkpoint and `gate-logs/ci-pr-N.json` files written into my own temp
dir, `/tmp/claude-1000/-home-alex-blast-off--claude-worktrees-pending-items-53932d/60b15296-819e-491a-8ffe-34b3bd988f86/scratchpad/crit.gwf6aO`
(scripts `mine.sh`, a copy of the brief's `probe.sh`, `loc.sh`; left in place). Reaching `ci_check` through
`receipt_check` and `receipt_all_done`, and everything on the workflow-file branch, is REASONED.

## Acceptance criteria, one at a time

| # | Criterion | Met as written? | Test that proves it (`tests/41-ci-wait.sh`) |
|---|---|---|---|
| 1 | no runs + workflow file at HEAD: `done` refused, exit 10 | Yes, for every PR the gate reads (`lib/ci.sh:84-87`). A PR the gate does not read (CRIT-1) is not refused. | `a2` lines 173-179; `a3` 181-182 (workdir a subdirectory); `a4` 184-186 (HEAD, not disk); control `a5` 188-190 |
| 2 | no runs + no workflow file: `done` allowed, logged | Yes (`lib/ci.sh:88`). | `a1` 171-172 (git repo, other files at HEAD); `d4` 125-130 (workdir in no git repo) |
| 3 | PR numbers read only from Status cells; prose ignored | Only when at least one Status cell names a PR. When none does, prose is read (`lib/ci.sh:74-76`): not met as written (CRIT-3). | Met half: `fin` 94-101, 127, 129. The opposite is pinned by `nt` 141-146, `np` 148-152, `ub` 193-197 |
| 4 | `workflow_dispatch` runs count in neither direction | Yes (`lib/ci.sh:52-55`, both list calls). | PR 14 and 15, lines 75-79; PR 16 (a push run counts) 81-82; at the runner, `wf` 169-178 |
| 5 | tests for 1 to 4, docs updated to match | Tests: yes, with the gap in CRIT-11. Docs: not all match (CRIT-1 spec sentence, CRIT-2, CRIT-4 to CRIT-7). | n/a |

## Findings

### CRIT-1 | HIGH | lib/ci.sh:71-73 | One Status cell naming a PR turns the gate off for every other done row: P3R1-1 is reshaped, not resolved
- Failure path: a table with row 0 `done (abc1234) · PR #7` (green record) and row 1 `done (abc1234)`, whose PR is named only under `## Completed phases` as `PR #8` (the shape `templates/checkpoint.md:49` prompts). `gate-logs/ci-pr-8.json` holds `verdict: failure`. `ci_check` logs `named elsewhere in checkpoint.md and not read: 8` and `done` passes. Same with no record for 8, and with an `absent` record for 8. The fallback fires only when *no* Status cell names a PR, but the hole is per row. Phase 2 refused the red and the no-record case (it read the whole file); in the absent case criterion 1 is simply not applied to PR 8. So the round-1 HIGH moved from "zero rows name a PR" to "one row forgot": one child of N leaving out `PR #<n>` is at least as likely as all of them doing so.
- The fix baton's reason ("issue 26 cannot tell it from another repo's") does not hold where a `gate-logs/ci-pr-8.json` exists: a record in this job dir means this job ran `ci-wait` on PR 8 in this workdir. A red record of the job's own making is passed over.
- Two texts overclaim. `docs/spec.md:97`: "a row closed without its PR never lets done through with a named PR unread". `lib/ci.sh:64-66`: "The gate fails closed (P3R1-1): when no Status cell names a PR (... a row closed without its PR)". Each is scoped to "when no Status cell names a PR", so neither is false; but each lists "a row closed without its PR" as a covered case, and a reader takes "never" and "fails closed" as the gate's guarantee. It holds only when every row lacks its PR.
- Evidence: RAN (stubs) `mixed_tpl`: `LOG: CI read for the PRs Phase plan Status cells name: 7; named elsewhere in checkpoint.md and not read: 8` then `=> DONE PASSES`, with `ci-pr-8.json` `failure`. `absent_prose`: same with `absent`. The brief's `probe.sh` `mixed` (second run): same.
- New in this diff (phase 2 read the whole file); the fix commit left it and added the two overclaiming sentences.
- Suggested fix: in the `[ -n "$prs" ]` branch, also read every PR in `$other` that has a `gate-logs/ci-pr-<N>.json` in the job dir; and correct the two sentences. The per-row half (a done row with no PR while others have one) needs owner question 4 answered; an explicit `no PR` word in the Status cell, required of a done row that names none, would close it without reading prose.

### CRIT-2 | HIGH | templates/checkpoint.md:30 | The rule comment now tells the gated party how to skip the gate
- Failure path: children read this comment every session. New sentence: "A row closed without one gets no CI check". Line 32 keeps "Name any other PR by its branch or as `other PR <n>`, no '#'", and `lib/ci.sh:76` logs "write any other PR with no '#'". Together they state, as neutral fact, that leaving `PR #<n>` out of the Status cell (or dropping the '#') removes the CI check. A child whose PR is red and that it cannot fix, or the owner at an exit 10 the docs call "no override" (`README.md:132`, `docs/spec.md:97`), has a one-edit way out, and the docs name it. Line 27 says "Add `PR #<n>` after it" with no reason; three lines down the text says what skipping it buys.
- Evidence: RAN (stubs). `evade_before` (Status `PR #7`, record red): `END 10: PR #7 CI red or unfinished`. `evade_after` (same job, both mentions rewritten `other PR 7`): `LOG: no PR named in checkpoint.md; CI not read`, `=> DONE PASSES`. `evade_mixed` (token dropped from one row only, another row green): `named elsewhere ... not read: 7`, `=> DONE PASSES`.
- The bypass itself is pre-existing (phase 2 also passed once the '#' was gone). Stating it as a rule is new in the fix commit, the one-cell version is new in this diff, and `tests/51-templates.sh:74` now pins the sentence.
- For triage: the sentence is round 1's own suggested wording for P3R1-5 ("a row closed without one gets no CI check"). The fix followed the reviewers; the fault is in that advice, read from the side of the agent being gated.
- Suggested fix: replace the sentence with an order and its reason, for example "Every closed row names its PR there: the runner reads this job's PRs from Status cells." Drop "gets no CI check" (and its pin in `tests/51-templates.sh:74`). In `ci_check`, log each done row whose Status cell names no PR, by row key.

### CRIT-3 | HIGH | lib/ci.sh:74-76 | Criterion 3 is not met when the fallback fires, and issue 26's own bug is back there
- Failure path (brief item (e)): a job with no PR in any Status cell (no PR of its own, or its PRs written `PR 7`) has `https://github.com/o/other/pull/99` under "Open or blocked". `ci_check` reads PR 99 and refuses: `PR #99 CI unread: no readable record for PR 99 in gate-logs/ci-pr-99.json; blast-off ci-wait <job-dir> 99, then run again`. That is the issue's "mentioning another repo's PR blocks `done`" case.
  - The log hint says "write any other PR with no '#'". A `/pull/99` link has no '#': the hint does nothing for it. The way out (delete or break the link) is in no message; `templates/checkpoint.md:32` says "by its branch", which an agent would have to connect to a URL by itself.
  - Following the refusal makes it worse: `ci_wait` runs `gh pr view 99` in the workdir (`lib/ci.sh:17-18`), so it reads the *workdir repo's* PR 99. Either gh fails (exit 1, no such PR), or an unrelated PR 99 of this repo gets a record: if green, the gate passes on evidence about the wrong PR; if red, `done` stays refused.
- The baton's reason for the default ("most scenarios" have no PR) counts test fixtures. Jobs the skill writes always have PRs (`templates/brief.md:108`, `skills/blast-off/SKILL.md:33-34`).
- Evidence: RAN (stubs) `xrepo_url`: `LOG: no Phase plan Status cell names a PR; CI read for every PR checkpoint.md names instead: 99 (...)`, `END 10: PR #99 CI unread ...`. What `ci-wait 99` then reads: REASONED from `lib/ci.sh:17-18`.
- New in the fix commit (b9c39ad ignored prose everywhere).
- Suggested fix: smallest, a message change: in the fallback branch refuse an unrecorded PR with its own text ("PR #N is named in checkpoint.md but in no Status cell: if it is this job's, name it in its row's Status cell and run ci-wait; if not, rewrite it as `other PR N` or remove the /pull/ link") instead of sending the reader to `ci-wait N`. Whether to keep the fallback at all is owner question 1.

### CRIT-4 | MEDIUM | templates/checkpoint.md:29-32 | The reworded rule parses two ways in two places and contradicts the code in one
- Failure path: a child reads the rule and acts on the wrong reading of one of these:
  - "A row closed without one": "one" can be the `PR #<n>` token (meant) or the nearer noun, "a CI record" from the clause just before. Second reading: "a row closed without a CI record gets no CI check", which reads as permission to skip `ci-wait`. An agent is likely to take the nearer noun.
  - "..., and a PR named only outside the Status cells is not read, unless no Status cell names a PR": "unless" can govern only the second clause (likely reading) or both. Under the likely reading the first clause is unconditional, and the code contradicts it: `np` (`tests/41-ci-wait.sh:148-152`) is a row closed without its PR that gets exit 10.
  - "gets no CI check" is per row; the code checks per PR, once, at `done`. Four phrases stand for one thing ("wants a CI record", "gets no CI check", "is not read", "is read"); nothing says "read" means `done` is refused without a green record.
  - Dropped reason: the old "anywhere here means this job's own PR" was why "Name any other PR ... no '#'" mattered. The new text says outside mentions are "not read", so the last sentence now looks optional; it still matters whenever the fallback fires.
  - Missing qualifier: the rule still says only "wants a CI record". An `absent` record is a CI record and is now refused where HEAD has a workflow file; no child-facing text says so (see CRIT-6).
  - "in a row's Status cell": the code reads the last `|`-separated cell of a digit-keyed row (`lib/ci.sh:70`). The template never says "last cell". A Status cell holding `\|`, or a row with no closing `|`, is not the cell read; the PR in it is then found only by the fallback.
- Evidence: REASONED from the diff of `templates/checkpoint.md` and `lib/ci.sh:70-79`. For the last point, RAN (stubs) `probe.sh` `escpipe` and `notrail`: both log `no Phase plan Status cell names a PR; CI read for every PR checkpoint.md names instead: 7`.
- New in the fix commit (the "last cell" gap is new in this diff).
- Suggested fix: three short sentences, one fact each: where the runner reads PRs; that every closed row must name its PR there; how to name a PR that is not this job's (including "no /pull/ link").

### CRIT-5 | MEDIUM | skills/blast-off/SKILL.md:34-37 | Step 4 asks for a prediction as a binding decision and names the wrong case
- Failure path: the scoping agent writes the wrong case into brief §2, or launches a job that cannot reach `done`:
  - "with no CI" used to mean "this repo has no CI". It now opens a sentence whose second half is about a repo that has a workflow file. A reader for whom "no CI" means "no workflows" takes the refusal clause as not applying. The case that bites, workflows that exist but do not run on this PR, is not named.
  - "say which holds in brief §2": decided at scoping, but the code reads HEAD at `done` (`lib/ci.sh:86`). A phase that adds a workflow, or the base merge each phase does (`templates/brief.md:131`), flips it after §2 ("binding; do not loosen") is written. It also reads two ways: state which case applies (likely), or state both rules.
  - Nothing tells the scoping agent to check that the repo's workflows will run on stacked PRs. The skill prescribes `--base <previous phase's branch>` (`templates/brief.md:108`); a workflow with `pull_request: branches: [main]` then gives every PR after the first no runs, and `done` is refused with no override.
- Evidence: REASONED from the SKILL.md diff, `lib/ci.sh:84-88`, `templates/brief.md:45,108`. GitHub's branch-filter behaviour is from recall, not run.
- New in the fix commit (the old sentence was wrong in a different way: P3R1-6).
- Suggested fix: "if the repo has a file under `.github/workflows/`, check its triggers run on a PR whose base is a phase branch; if not, settle that with the owner before launch. The runner refuses `done` for a PR with no runs while HEAD has such a file."

### CRIT-6 | MEDIUM | templates/brief.md:135,142-144 | The child protocol gives no action for `absent`, so the refusal lands after the last phase
- Failure path: step 4 says "absent checks are not a pass, and a red one means fix, commit, gate, receipt again", then "After ci-wait, set the row's Status to `done ...`" whatever ci-wait returned. With a workflow file at HEAD, a child that sees `absent` (exit 10) in phase 0 closes the row and goes on; the runner refuses only at the final `done`, after every phase has spent its usage. Before this diff the silence was harmless (absent passed). `templates/brief.md` is not in the diff; its words still agree with the code, its effect no longer does.
- Step 4 also says "No code commit after the receipt (the runner refuses with exit 9)" while the refusal at `lib/ci.sh:87` says "push to the PR branch". With nothing new to push there is no event; an amend moves the row's sha out of HEAD's history (exit 9); neither text says "an empty commit".
- Evidence: REASONED from `templates/brief.md:131-146`, `lib/ci.sh:84-88`, `lib/receipt.sh:54-63`.
- Pre-existing text made worse by this diff.
- Suggested fix: one clause in step 4: "absent where the repo has a workflow file: `done` will be refused; record it under Open or blocked with the workflow's trigger, do not close the job".

### CRIT-7 | MEDIUM | lib/ci.sh:87 | The absent refusal names a way out that cannot work in the two cases most likely to hit it
- Failure path (brief item (f), questions 2 and 3): (i) a later phase adds the workflow, so HEAD has it and every earlier stacked PR is refused. A push to an earlier PR's branch starts no run: neither that branch nor its base holds the workflow file. The real way out, putting the workflow on each earlier branch, is in no message. (ii) a workflow filtered to `branches: [main]`: no push to a stacked PR's branch ever starts a run. `README.md:132` and `docs/spec.md:97` say "there is no override". What is left is retargeting the PR's base or merging (the brief rules out both: `templates/brief.md:108` sets the base, `:110` says never merge) or the edit in CRIT-2. So "no override" is not true in practice: the override is deleting a '#', and it is the one nobody approves or sees named as an override.
- Evidence: REASONED. GitHub behaviour (which commit's workflow file a `pull_request` or `push` run uses, branch filters) is from recall, not run.
- The message is new in the fix commit (P3R1-22); the dead end is P3R1-3 and P3R1-4, still open.
- Suggested fix: say in the message what must be true for a push to help ("... if the PR branch holds the workflow and its triggers cover it; else see README exit 10") and give the README row the two cases. A logged owner override is owner question 3.

### CRIT-8 | MEDIUM | lib/ci.sh:97 (read at :69-70) | A NUL byte in the checkpoint empties the PR list and logs an untrue line; the open half of P3R1-28 is reachable
- Failure path: any NUL byte in `checkpoint.md`. `grep` prints "binary file matches" to stderr, exits 0, stdout is empty. `ci_prs` returns nothing for the whole-file read (and for the Status read when the NUL is in a row). `ci_check` logs `no PR named in checkpoint.md; CI not read` and `done` passes with a red record on disk. The baton's part-fix (a failing pipeline now stops the runner) does not reach this: nothing fails. The baton did say `grep -a` was not added; it gave no reason.
- Evidence: RAN (stubs) `fb_nul`: `grep: (standard input): binary file matches`, `LOG: no PR named in checkpoint.md; CI not read`, `=> DONE PASSES` (record `failure`). `tbl_nul`: same. Not a default-path problem: RAN `loc.sh`, the template's `·` and an invalid byte on the token's line both give `7` under `LC_ALL=C`, `POSIX` and `C.UTF-8` (grep 3.11).
- Pre-existing pattern; the fix commit doubled the reads and added a log line that is false here.
- Suggested fix: `command grep -aoiE` in `ci_prs`.

### CRIT-9 | MEDIUM | lib/ci.sh:71-73 | A PR spelled `PR 8` in a Status cell beside a well-formed row is unread and not logged; the baton's P3R1-9 disposition is wrong on both halves
- Failure path: row 0 `· PR #7`, row 1 `· PR 8` (also `#8`, `PRs #7, #8`, `PR  #8`, `pull request #8`). Neither read matches 8, so the log names only 7 and says nothing about row 1. The baton says such a cell "now ends in line 2 or 3"; with another row well-formed it ends in line 1.
- The baton refutes widening the pattern because "`PR <n>` with no '#' is the template's own way to name a PR that is not the job's". That convention is for prose. In a Status cell the new rule says a PR is the job's own, so a looser pattern there closes no one's way out.
- Evidence: RAN (stubs) `mixed_nohash`: `LOG: CI read for the PRs Phase plan Status cells name: 7`, `=> DONE PASSES`, with `ci-pr-8.json` `failure`. `probe.sh` `plural`, `nohash`, `barehash`, `twospace`, `pullreq`: each `no PR named in checkpoint.md; CI not read`, `=> DONE PASSES`.
- Pre-existing pattern, exposure widened by this diff; the log claim is new in the fix commit.
- Suggested fix: the per-row log line of CRIT-2 (a done row whose Status cell yields no PR number is named in `run.log`).

### CRIT-10 | MEDIUM | lib/ci.sh:73,76,78 with lib/chain.sh:159 | The only signal for an unread PR is a run.log line on a path that ends exit 0 with "job done"
- Failure path: in CRIT-1, CRIT-8, CRIT-9 and the "no PR named" case the runner exits 0 and its last line is `job done`. Nothing prompts anyone to read the line above it; a unit that succeeded is not inspected. The fix treats "logged" as the remedy for P3R1-2 and P3R1-9, and for half of P3R1-1 ("no CI read" still holds for a job whose checkpoint names no PR; only "no log line" was fixed).
- Evidence: REASONED from `lib/chain.sh:159` (`chain_end 0 "job done"`) and the RAN outputs above.
- New in the fix commit as a remedy; the exit-0 path is pre-existing.
- Suggested fix: carry it in the final line: `job done; CI read for PRs 7; named and not read: 8` or `job done; no CI read`.

### CRIT-11 | MEDIUM | tests/41-ci-wait.sh:127-129, tests/51-templates.sh:74 | Tests pin the fail-open as wanted and have no mixed case with a record
- Failure path: a later change to the gate's reading rule passes or fails the suite for the wrong reason. `fin` asserts PR 96 to 99 are "not read" and none has a record, so no test shows what happens when a PR named elsewhere has a red record of this job (CRIT-1). `nt`, `np`, `ub` pin prose being read, against criterion 3 as written, with no comment that this is a stated departure. `tests/51-templates.sh:74` pins "A row closed without one gets no CI check", so fixing CRIT-2 fails the gate until the test changes.
- Evidence: REASONED from the test files; not run.
- New in the fix commit.
- Suggested fix: one case in `fin`: copy a red record in as `ci-pr-98.json` and assert the behaviour the owner picks for question 4.

### CRIT-12 | LOW | README.md:132 | The exit 10 row says "named in a Phase plan Status cell" and leaves out the fallback
- Failure path: an owner at exit 10 for a prose-only PR (CRIT-3) looks up the row and finds it does not describe the case. The paragraph at `README.md:116-117` has the fallback; the table row does not. `bin/blast-off:37-38` says "a PR's CI", which is fine.
- Evidence: REASONED from the README diff.
- New in the fix commit.
- Suggested fix: "a PR the runner read (run.log names them)".

### CRIT-13 | LOW | lib/ci.sh:76 | The fallback hint is one line doing two jobs, and it shows on the refusal where the PR may be the job's own
- Failure path: "name this job's PR in its row's Status cell; write any other PR with no '#'": the reader decides which PR is "other". When the refused PR is the job's own and red, the second half is the cheaper instruction. It also does not cover `/pull/N` (CRIT-3).
- Evidence: REASONED from `lib/ci.sh:76`; the line itself RAN (stubs) in `xrepo_url`.
- New in the fix commit.
- Suggested fix: covered by CRIT-3's message.

## Round-1 findings checked
| ID | resolved / reshaped / open / not checked | why |
|---|---|---|
| P3R1-1 (HIGH) | reshaped | Zero Status PRs with a '#'-named PR elsewhere is now refused. One Status PR un-gates every other row (CRIT-1); no PR token anywhere still passes with no CI read, now with a line nobody is prompted to read (CRIT-10); a NUL gives the same pass with a false line (CRIT-8). |
| P3R1-2 | open | "Logged" is the whole remedy; a red record in the job dir for the unread PR is passed (CRIT-1). |
| P3R1-3 | open | Owner decision; spec states the limit. The refusal's way out fails for an earlier stacked PR (CRIT-7). |
| P3R1-4 | open | Owner decision; "no override" drives readers to the '#' edit (CRIT-2, CRIT-7). |
| P3R1-5 | reshaped | The rule is no longer false about where PRs are read; it is now ambiguous, contradicts `np`, and states the bypass (CRIT-2, CRIT-4). |
| P3R1-6 | reshaped | Both cases are stated; "with no CI" and "say which holds" mislead (CRIT-5). |
| P3R1-7 | resolved, one omission | Paragraph and row name absent and a working order of steps; the row leaves out the fallback (CRIT-12), and "push so a run starts" has CRIT-7's limit. |
| P3R1-8 | resolved | `bin/blast-off:37-38` names absent with a workflow file. |
| P3R1-9 | reshaped | Logged only when no other row is well-formed (CRIT-9); the refutation of the widening confuses prose with Status cells. |
| P3R1-10 | resolved in part | Cases `nt`, `np` and "no PR named" exist; no mixed case with a record (CRIT-11). |
| P3R1-11 to P3R1-19 | not checked | Cases `a3`, `ub`, `a4`, PR 16, rows `P1`/`| 3 |`/five columns, the two-file first commit and `a5` are present by reading; I ran no mutant and no scenario. |
| P3R1-20 | resolved by reading | `wf` builds its record with `ci-wait 14` (dispatch-only head), lines 169-178. |
| P3R1-21 | resolved in part | Spec row 10 has the omissions; it gained the false "never" sentence (CRIT-1). |
| P3R1-22 | reshaped | "re-run it" is gone; the new way out cannot work in two cases (CRIT-7) and sits against brief step 4 (CRIT-6). |
| P3R1-28 | open | The part-fix does not reach the NUL case, which now ends in an untrue log line (CRIT-8). |
| P3R1-30 | open | RAN (stubs) `probe.sh` `xrepo_link_status`: another repo's `/pull/99` in a Status cell is read as this job's PR 99. |
| P3R1-31 | open | `d4` (workdir in no git repo) still logs "no workflow file at HEAD". |
| P3R1-23 to -27, -29, -32 to -44 | not checked in the code | Their stated reasons are judged in the next section. |

## The fix baton's "out of scope" and "open" dispositions, by the reason it gives
Judged from the baton's own words; I did not re-test the findings behind them.

- **P3R1-3 and P3R1-4, "out of scope, owner decisions".** Holds for the rule (issue 26's words: HEAD, any file). Does not hold for what the fix commit itself wrote on top of the rule: the refusal's way out (`lib/ci.sh:87`) and the "there is no override" sentences (`README.md:132`, `docs/spec.md:97`). Those are this commit's text and they are wrong or incomplete in the two cases the findings named (CRIT-7). "Out of scope" was applied to the whole finding where it fits half of it.
- **P3R1-31, "wording only ... skipped for the call budget".** A budget reason, not a merit one. The line is untrue outside git and the fix is a string.
- **P3R1-33, "left untouched to stay under the 10-file limit"**, and with it **P3R1-24, -34, -43** ("no test without touching `tests/fakes/gh`"). A file-count limit of the fix unit decided four findings. None of the four is argued to be wrong. The same limit put the full gate log under /tmp and not in the repo.
- **P3R1-28, "`grep -a` not added".** No reason given, for a two-character change in a line the commit rewrote (CRIT-8).
- **P3R1-25, "needs `ci_runs` to report what it left out".** That describes the fix; it is not a reason to leave it.
- **P3R1-9, "widening REFUTED".** The reason confuses the prose convention with the Status cell (CRIT-9).
- **P3R1-2 "fixed ... logged as not read" and P3R1-1 "fixed".** "Fixed" overstates both (CRIT-1, CRIT-10): one is a log line, the other covers one of the shapes round 1 listed.
- **P3R1-23, -29, -30, -44.** Merit reasons (a record-format change, a refactor outside the issue, another gh read, waiting on the owner). P3R1-30 shares CRIT-3's root: the runner cannot tell this repo's PR from another's.
- **P3R1-26, -32, -36, -40, -41, -42.** Owner's call or pre-existing, as stated; not challenged.

## Owner questions (1-4): is the default the safe one?
1. **No PR in any Status cell: read every PR the checkpoint names.** Not the safe one, in either direction. It brings issue 26's bug back for those jobs and points the reader at `ci-wait` on the wrong repo's PR number (CRIT-3), and it leaves the gate open as soon as one row is well-formed (CRIT-1). Alternative (a) keeps both problems for table-less jobs only. Alternative (b), a done row must name its PR, is the closed one; with an explicit `no PR` word for a phase that has none it also never reads prose, so criterion 3 holds as written.
2. **Workdir HEAD at `done` decides "runs were due".** Closed, and the issue's words. Two costs: the stated way out cannot work for an earlier stacked PR whose branch has no workflow file (CRIT-7), and a workflow deleted at HEAD or not yet committed reads as none (fail-open, P3R1-3, not re-checked).
3. **Any file counts, no override.** Closed on paper. In practice there is an override, deleting the '#', and the template names it (CRIT-2). A logged owner override would be safer than the unlogged one agents will find.
4. **A PR named only under Completed phases is logged, not read.** Not the safe one where this job dir holds a record for that PR: a red record of the job's own `ci-wait` is passed (CRIT-1). Reading recorded PRs does not bring issue 26's bug back; another repo's PR has no record here.

## What I did not check
- No `tests/run` of any kind, no mutant, no real `gh`, no real GitHub repo. GitHub behaviour in CRIT-5 and CRIT-7 (branch filters, which commit's workflow file a run uses) is from recall.
- The full runner path: `receipt_check`, `receipt_all_done` and `chain_end` were read, not run. The workflow-file branch (`TOP` set) was not run; `ci_head` was stubbed.
- The locale the systemd unit gives the runner. `loc.sh` covered `C`, `POSIX`, `C.UTF-8` only (`en_US.UTF-8` is not installed here).
- `README.md:132`'s claim that the last `run.log` line names the PR and the case (`chain_exit` read, not run).
- `docs/spec.md` and `README.md` outside the changed rows; `tests/fakes/gh`; `paste` on other systems; round-1 LOW findings not listed above.
- shellcheck and `bash -n` (other reviewers' ground).
