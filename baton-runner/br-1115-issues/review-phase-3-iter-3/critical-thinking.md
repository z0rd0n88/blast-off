# critical-thinking review: phase 3 (issue 26), round 3

Angle: the instruction texts agents obey (`templates/checkpoint.md:20-39`, `templates/brief.md` section 9, `skills/blast-off/SKILL.md` step 4) and the runner's refusal lines (`lib/ci.sh:68-100`), read literally and against `ci_check` / `ci_wait`. Read-only: no scenario run, no `lib/*.sh` sourced. Everything below is from reading files and `git diff feat/br-1115-issues/phase-2...HEAD`; claims about GitHub's behaviour are marked as recall.

Counts: 0 CRITICAL, 1 HIGH, 10 MEDIUM, 7 LOW. No fail-open path was found that an obedient, template-following child reaches without a tool failure or an off-brief phase shape. The HIGH is fail-closed: a job in a repo whose workflows do not start on stacked PR branches can never end `done`, the child's instruction loops through `blocked`, and no text gives anyone an action. The fail-open findings are all text-only controls: `no PR` is licensed by a fact the child controls and the runner cannot check (CT-5), the template's singular "own PR ... name another PR in prose" can send a phase's second PR out of the gate (CT-4), and four places tell a reader which edit takes a PR out of the check (CT-6, CT-7, CT-8, CT-9). `tests/51-templates.sh` pins the sentence that says where the runner does not look, and does not pin the clause that asks for a CI record or the qualifier that makes criterion 2 reachable (CT-11).

Answers to the five questions asked: (a) CT-2, (b) CT-1 and CT-3, (c) CT-4, CT-5, CT-6, (d) CT-10, (e) CT-16.

---

### CT-1: a PR no workflow can start on has no action in any text: the child blocks, the owner is told to "ask the owner", and the skill asks the question and drops the answer
- Severity: HIGH
- File: templates/brief.md:135-137; skills/blast-off/SKILL.md:34-38; lib/ci.sh:94; README.md:134
- Reachable by a template-following job: yes. Surest case, needing no recall about GitHub filters: a repo whose only workflow file is a release, schedule or dispatch one (any file under `.github/workflows` counts, ci.sh:92-94), where no PR ever gets a run. Also any repo whose workflows do not start for a PR based on the previous phase's branch (brief section 8 line 108 makes every phase PR that shape).
- Direction: fail-closed
- Origin: introduced by this diff (the refusal itself is owner ruling 2 and is not contested here; the finding is that the texts give no action for it)
- Known and new: the dead end itself is on record as P3R2-8 (MEDIUM, round 2; owner question 3, an owner-held override, not ruled; fix baton line 50). New in this round's texts: the brief now routes the child into `blocked`, README's exit 3 remedy routes the owner back into the same instruction, and the skill collects the fact before launch and drops it.
- Calibration: borderline HIGH or MEDIUM. Round 2 rated the dead end (P3R2-8) and the text gaps of this kind (P3R2-17, P3R2-18) MEDIUM. I rate it HIGH because the texts written since then turn a known limit into a block-and-relaunch loop that every template-following job in such a repo enters, with the fact in hand before launch. A synthesizer holding text gaps to round 2's level should make this the first MEDIUM to fix.
- Failure path:
  1. Repo has only `.github/workflows/release.yml` (`on: release`); no PR gets a run, from phase 0 on. Or: repo has `ci.yml` with `on: pull_request: branches: [main]`, phase 1's PR is opened with `--base <phase 0 branch>` (brief.md:108), and no run starts (recall: `pull_request.branches` filters on the base branch).
  2. Child runs `ci-wait`: `absent`, exit 10 (ci.sh:40,46).
  3. brief.md:135-137: "push once more for a run, and if none starts leave the row open, set `status: blocked` and record it under Open or blocked". Child sets `status: blocked`; runner exits 3 (chain.sh:161).
  4. README.md:127 tells the owner: "answer what `Open or blocked` asks, set `status: running`, `start` again". The next child reads the same step 4, gets `absent` again, blocks again. Nothing in the brief changes between rounds, so this repeats.
  5. If the owner closes the row by hand instead, `ci_check` refuses at ci.sh:94: "...if no workflow can start on this PR (a branch or path filter), there is no override: ask the owner". At `status: done` no child is launched (chain.sh:160), so the reader of that line is the owner. README.md:134 ends the same way: "ask the owner", in the "What to do" column the owner reads.
  6. SKILL.md:36-38 has the authoring agent "ask whether the repo's workflows start on the stacked PR branches, and put the answer in brief §2". It says nothing about what to do when the answer is no. The fact lands in §2 ("binding; do not loosen") with no instruction attached, and the job is launched to a certain block.
  A legitimate way out exists (the owner changes what starts a workflow on the PR branch, so a run exists), but no text names it. The edits a reader can work out from the texts alone are a false `no PR`, removing the workflow file at the PR's head, or editing `gate-logs/ci-pr-<n>.json`; each is a slip.
- Evidence: files and lines above, read. The release-only case rests on ci.sh:92-94 alone; the base-filter case is recall about GitHub, not tested. blast-off's own `.github/workflows/ci.yml` is `on: pull_request:` with no filter, so this repo's own jobs do not hit it.
- Suggested fix: SKILL step 4: have the agent read the `on:` blocks itself during step 1, and when no workflow starts on a stacked PR, tell the owner before launch that `done` will be refused for those PRs, and record in §2 which of the owner's choices applies (for example every PR based on the job's base, or the job ends `blocked` by design). brief step 4: say what the owner must change for the row to close, so a relaunch is not the same instruction again. ci.sh:94 and README:134: replace "ask the owner" with what the owner can do.
- Question: what end state does the owner want for such a repo: a job that ends `blocked` every time, or a delivery shape that gets runs?

### CT-2: brief section 9 gives no instruction for `absent` where the head has no workflow file, and the sentence parses two ways (question a)
- Severity: MEDIUM
- File: templates/brief.md:135-137 (and :81-83, :144-146)
- Reachable by a template-following job: yes (any repo with no workflow file: the case criterion 2 is about)
- Direction: fail-closed
- Origin: introduced by this diff
- Failure path: the sentence is "`absent`, no runs, is not a pass: where the PR's head has a file under `.github/workflows/` push once more for a run, and if none starts leave the row open, set `status: blocked` and record it under Open or blocked".
  - Reading A: "where the PR's head has a file" governs both halves. With no workflow file nothing applies; the child falls through to "After ci-wait, set the row's Status to `done (<sha>) · PR #<n>`" (brief.md:144-145), sets `done` at the end, and ci.sh:95 lets it through. Criterion 2 is reached.
  - Reading B: "and if none starts ..." is a second instruction under "is not a pass", not under "where". In a repo with no workflow file none starts, so the child leaves the row open and sets `status: blocked` (exit 3). The owner sets `running`, the next child does the same. The child never closes the row; criterion 2 is reached only if the owner closes the row by hand.
  - A literal-minded child takes A, in my judgment: "where ..." opens the clause and nothing closes it before "and if none starts", and "none starts" has no meaning without the push. So the obedient child closes the row and criterion 2 is reached, by falling through, not by instruction. The caveat: under A the no-file case has no words at all, and the child has just seen exit 10 beside "is not a pass". Two other lines push toward B: brief.md:83 "Unrun is not passed: a check that could not run is recorded as blocked with the reason", and brief.md:189-190 "Never ... report a check you did not run". This is a judgment from reading; no scenario runs a real child.
  - The phase-2 skill told the author to write the pass-through into the brief ("the runner lets `done` through logged ...: say so in brief §2"). The new step 4 replaced "say so" with "ask ... and put the answer", so the one sentence that told a child `absent` can still end `done` is gone from what children read.
- Evidence: brief.md lines above; `git show feat/br-1115-issues/phase-2:skills/blast-off/SKILL.md` lines 34-35; ci.sh:89-95; chain.sh:160-161. `tests/51-templates.sh:88` pins "`absent`, no runs, is not a pass" and "leave the row open, set `status: blocked`" but not "where the PR's head has a file under": the qualifier can be deleted (making every `absent` a block) with no test failing.
- Suggested fix: one clause for the other case, for example "where it has none, close the row as usual: the runner lets `done` through, logged"; split the two cases into two sentences; pin the qualifier.

### CT-3: step 4 says set `status: blocked` at once; step 9 says only when nothing independent is left; "push once more" has nothing to push
- Severity: MEDIUM
- File: templates/brief.md:136-137 against :169-171; :147-148
- Reachable by a template-following job: yes
- Direction: fail-closed
- Origin: introduced by this diff
- Failure path:
  - Contradiction: step 4 "leave the row open, set `status: blocked`"; step 9 "Blocked parts do not stop the job ... Set `status: blocked` only when nothing independent is left." A child at phase 1 of 5 with an `absent` PR is told both to stop the job now and to go on with independent work. Step 4 is the more specific and the later-written; a literal child stops, and phases 2 to 5 are not attempted.
  - "push once more for a run": after "push and open the draft PR" the branch is already pushed, so `git push` is a no-op and starts nothing. The text does not say what to push. An empty commit would survive `receipt_check` (receipt.sh:45-65: the row's sha stays an ancestor of HEAD and `git diff --quiet <sha> HEAD` is clean), but the next line the child reads is "No code commit after the receipt (the runner refuses with exit 9)". The other thing a child can do, amend and force-push, changes the sha the receipt names and ends in exit 9.
  - "if none starts": the text does not say how the child finds out (run `ci-wait` again is implied by "after the last push to it", not stated).
- Evidence: brief.md lines above; receipt.sh:45-65 read, not run.
- Suggested fix: say "record it under Open or blocked and go on with independent phases; set `status: blocked` when none is left" (or state that step 4 overrides step 9 and why); say "an empty commit" if that is what is meant, and "then ci-wait again".

### CT-4: "the phase's own PR ... refuses any other '#<n>' ...: name another PR in prose" can send a phase's second PR out of the gate (question c)
- Severity: MEDIUM
- File: templates/checkpoint.md:30-34 against lib/ci.sh:71-73
- Reachable by a template-following job: only when a phase has two PRs of its own (off brief section 8, which says one per phase)
- Direction: fail-open
- Origin: introduced by this diff
- Failure path: the template says the cell "names the phase's own PR" (singular) and "refuses any other '#<n>' in a Status cell: name another PR in prose, outside the table". "another PR" reads two ways: (1) a PR that is not this job's; (2) any PR beyond the one already named. A child whose phase has PR #7 and PR #9 takes reading 2 literally: `PR #7` in the cell, #9 in prose. The runner reads PRs only in the cell (ci.sh:71,83), so #9's CI is never read, red or not. The code would have accepted both (`ci_prs` collects every `PR #n` in the cell; the stray check at ci.sh:72 strips each), and the runner's own line 73 says "write each of the phase's PRs as `PR #<n>`". Template and runner message disagree on whether a cell may hold more than one.
- Evidence: checkpoint.md:30-34, ci.sh:71-73,104 read.
- Suggested fix: "names every PR the phase opened, each as `PR #<n>`"; "a PR that is not this job's goes in prose".

### CT-5: `no PR` is licensed by "opened no PR", a fact the child controls; no text says which phases may have none; nothing checks it
- Severity: MEDIUM
- File: templates/checkpoint.md:31; templates/brief.md:145-146; skills/blast-off/SKILL.md:34; lib/ci.sh:74-76
- Reachable by a template-following job: yes when `gh pr create` fails or is refused (the phase then "opened no PR", literally); otherwise only by a child that skips "push and open the draft PR"
- Direction: fail-open (a phase the brief gave a PR ends `done` with no PR and no CI read)
- Origin: introduced by this diff (ruling 1 makes `no PR` valid; the gap is in what the texts key it on)
- Failure path: brief section 5 heading and section 8 say every phase has one stacked draft PR. SKILL.md:34 then says "a phase with no PR closes its row with `no PR`" in the same parenthesis as "one stacked draft PR per phase", with no word on when a phase may have none or who decides. The child-facing rule is "Write `no PR` only for a phase that opened no PR". A child whose `gh pr create` failed (auth, rate limit, no commits between the branches) has, truthfully, a phase that opened no PR. The literal reading closes the row with `no PR`; brief.md:69-71 ("a refused tool call blocks that part") points the other way, and nothing ranks the two. `ci_check` takes the words as given (ci.sh:74-76): it does not ask gh whether the branch has a PR.
- Evidence: lines above, read. `tests/41-ci-wait.sh:182-184` pins that a row saying `no PR` passes while the job holds a red record for PR #7 named in prose ("as ruled").
- Suggested fix: key the permission on the plan, not the outcome: "only for a phase whose brief row says it opens no PR; a PR that could not be opened is a blocked part". Have SKILL step 4 settle with the owner which phases, if any, have no PR, and write it in §5.

### CT-6: "It reads PRs nowhere else in this file" tells a child where the gate does not look, and it is the pinned sentence (question c)
- Severity: MEDIUM
- File: templates/checkpoint.md:33; tests/51-templates.sh:78
- Reachable by a template-following job: no (the child must break "Write `no PR` only for a phase that opened no PR")
- Direction: fail-open
- Origin: introduced by this diff
- Failure path: a child with a red or `absent` PR #7 reads lines 30-34 together: a closed row may say `no PR`; the runner reads PRs nowhere else; another PR goes in prose. The edit is: `no PR` in the cell, "PR #7" under Completed phases. `ci_check` logs `PRs read: none; rows that say no PR: 0` and exits 0. The fix baton (line 39) says of this sentence: "Moving a PR to prose gets a refusal, not a pass." That is true only while the cell is left with neither token; with `no PR` written it is a pass, and the suite pins that pass (tests/41-ci-wait.sh:182-184, red record for PR #7 in the job, exit 0). The obligation sentence is clear and pinned, and it is the only control; the text states no consequence for a false `no PR`, and the sentence that describes the blind spot is not needed for the child to do its job (it needs "you may name other PRs in prose", not "the runner does not read them"). This is the class of P3R2-4 in a weaker form: the old sentence named the result ("gets no CI check"), this one names the mechanism.
- Evidence: checkpoint.md:30-34; ci.sh:74-76,84; tests/41-ci-wait.sh:182-184.
- Suggested fix: drop the mechanism clause from the child-facing comment (keep it in the spec), keep "name a PR that is not this job's in prose", and add that a false `no PR` is reporting a check that was not run (brief step 14).
- Question: what does a child do better for knowing where the runner does not read?

### CT-7: the no-done-row refusal offers `no PR` with no qualifier; the "both" refusal offers dropping the PR as an equal choice
- Severity: MEDIUM
- File: lib/ci.sh:82; lib/ci.sh:75
- Reachable by a template-following job: line 82 no (needs a job with no readable table); line 75 no
- Direction: fail-open
- Origin: introduced by this diff
- Failure path: line 78 says "`PR #<n>` (the phase's own PR) or `no PR` (the phase opened none)". Line 82 says "add a `## Phase plan` table with a row per phase ... that ends `done (<sha>) · PR #<n>` or `done (<sha>) · no PR`" with no condition on either. For whoever acts on an exit 10 (owner, or an agent the owner asks to clear it), the edit that needs no `ci-wait` is the one-row `no PR` table. `tests/fakes/claude:33-43` (`fin`) is that exact edit, with a hand-written PASS receipt beside it. Line 75, "keep the one that is true", is honest but lists deleting the PR token as one of two equal moves at the moment of refusal. Line 82 also does not say the added rows will each need a receipt (the next run is exit 9).
- Evidence: ci.sh:75,78,82 read; tests/fakes/claude:33-43 read.
- Suggested fix: carry line 78's parentheses into line 82; line 75: "if the phase opened PR #<n>, delete `no PR`".

### CT-8: the texts hand the child the pass condition (no file under `.github/workflows` at the PR head) and line 94 prints the deciding file; no sentence forbids changing workflow files to meet it
- Severity: MEDIUM
- File: templates/brief.md:136; lib/ci.sh:94; README.md:118,134
- Reachable by a template-following job: only when `.github/workflows` is in the job's Target set (a job that touches CI); otherwise the Target set rule stops an obedient child
- Direction: fail-open
- Origin: introduced by this diff (the condition is ruling 2 and is not contested; the finding is the missing guard in the texts)
- Failure path: PR #7's CI is red. A commit on the PR branch removes or moves the workflow file. New head: no runs (recall: no workflow at the PR's merge ref, none started), `ci-wait` records `absent`, `git ls-tree` at that head lists nothing, ci.sh:95 logs "no CI configured; absent, not a pass" and `done` passes. A red PR has become a pass by one edit that the brief names as the child's own decision test ("where the PR's head has a file under `.github/workflows/`") and that the refusal names by path ("has a workflow file (.github/workflows/ci.yml)") right before "there is no override".
- Evidence: ci.sh:89-95 read; GitHub half is recall.
- Suggested fix: one line in brief step 4 or section 4's safety defaults: never remove, move or disable a workflow file to change a CI result; and say so beside "there is no override".

### CT-9: "the runner only sees rows like that" now also means "a PR in a row with no digit key is not CI-read"
- Severity: MEDIUM
- File: templates/checkpoint.md:24
- Reachable by a template-following job: only by an off-template checkpoint (a child that keys a row `P1`, beside at least one digit-keyed done row)
- Direction: fail-open
- Origin: pre-existing text, made worse by this diff
- Failure path: at phase 2 `ci_check` grepped the whole file (`git diff` of lib/ci.sh: `grep -oiE ... "$JOB/checkpoint.md"`), so `PR #96` in a `P1` row was read. Now only `cp_done_cells` rows are read (checkpoint.sh:43 keeps `^| *[0-9]`), so that PR is not, and such a row is neither an open row (exit 9) nor a done row. Line 24 states the visibility rule to the child. The fix baton records the limit as deliberate; what changed is that the line now describes a way out of the CI check as well as the receipt check.
- Evidence: checkpoint.sh:43-46; ci.sh diff; baton-phase-3-fix-2.md line 38 (read, then checked against the code).
- Suggested fix: for the code reviewers (a row in the table whose key the runner cannot read could be refused). For the text: "a row keyed any other way is refused" once that is true.

### CT-10: nothing an owner or child reads says a job started before this change is refused at `done` until its rows are edited (question d)
- Severity: MEDIUM
- File: README.md:114-119,134; docs/spec.md:97; lib/ci.sh:78
- Reachable by a template-following job: yes (a job written from the phase-2 templates and still running when the checkout is updated; SKILL.md:89 notes the unit runs `bin/blast-off` from the checkout path)
- Direction: fail-closed
- Origin: introduced by this diff
- Failure path: the only statement of it is in the fix baton, which neither reads. `grep` for "started before", "existing", "earlier job", "upgrade", "migrat" in README, spec, skill and templates: no hit. What a live job has: its own `brief.md` (section 9 copied verbatim from the old template, no word of `no PR`) and its checkpoint's old rules comment ("`PR #<n>` or a /pull/<n> link anywhere here means this job's own PR ... Name any other PR ... no '#'"), which now contradicts the runner. Its children go on writing by the old rule; a phase with no PR is closed as `done (<sha>)`. The refusal comes only at the very end, at `status: done`, where chain.sh:160 goes straight to `ci_check` and launches no child, so only the owner can make the edit. Setting `status: running` to get a child does not help: that child's brief does not know the rule. The refusal stops at the first bad row (ci.sh:78 exits), so a job with five such rows takes five runs to list them. The refusal line and README row 10 do say what to write; they do not say why a job that followed its own brief is refused.
- Evidence: grep above; chain.sh:156-162; ci.sh:70-81.
- Suggested fix: one README paragraph ("jobs started before <version>": add `PR #<n>` or `no PR` to every done row; the job's own rules comment is out of date), and report every bad row in one refusal.

### CT-11: which new sentences are pinned, and which can be reworded back with no test failing
- Severity: MEDIUM
- File: tests/51-templates.sh:74-88; tests/70-docs.sh:17-25,43-45
- Reachable by a template-following job: n/a (test adequacy)
- Direction: neither
- Origin: introduced by this diff
- Failure path: pinned (51:74-79, 87-88): "Every closed row's Status cell names the phase's own PR, as `PR #<n>` (or its /pull/<n> link), or says `no PR`."; "Write `no PR` only for a phase that opened no PR."; "The runner refuses done (exit 10) for a closed row with neither"; "It reads PRs nowhere else in this file"; in the brief "`done (<sha>) · no PR` only for a phase that opened no PR", "`absent`, no runs, is not a pass", "leave the row open, set `status: blocked`".
  Not pinned, so each can be cut or turned around with the gate green:
  - checkpoint.md:32 "and wants a CI record (`blast-off ci-wait`) for each PR named there": the only sentence in the comment that asks for CI.
  - checkpoint.md:33-34 "and refuses any other '#<n>' in a Status cell: name another PR in prose, outside the table".
  - checkpoint.md:27-28 "After it comes `PR #<n>` or `no PR`".
  - brief.md:136 "where the PR's head has a file under `.github/workflows/`" and "push once more for a run" (CT-2).
  - brief.md:146 "the runner refuses a done row with neither, exit 10".
  - all of SKILL.md step 4 (70-docs pins other lines; the fix baton says so too).
  - README.md:114-119 and the text of row 10 (70-docs:40 checks only that a row for 10 exists).
  - the refusal lines at ci.sh:73 and :82 past their first words; lines 75 and 78 are pinned in part (41:198, 41:171), line 94's remedy in full (41:240).
  The two forbidden strings (51:82, "gets no CI check", "unless no Status cell") are exact matches: "is not CI-checked" or "skips the CI read" passes. The net effect is that the mechanism sentence of CT-6 cannot be removed without editing the test, while the CI obligation can.
- Evidence: the two test files, read; no scenario run.
- Suggested fix: pin the CI-record clause and the brief's qualifier; unpin or reword the mechanism sentence; pin one phrase of SKILL step 4.

### CT-12: refusal lines as instructions: gaps at ci.sh:91, :93, :94, :96
- Severity: LOW
- File: lib/ci.sh:91,93,94,96
- Reachable by a template-following job: yes (each is what the owner follows after exit 10)
- Direction: neither (line 96: see below)
- Origin: introduced by this diff for 91, 93, 94; pre-existing for 96
- Failure path:
  - :94 "push to the PR branch for a run": when the record is `absent` only because runs were listed after the 60 s wait (ci.sh:20-23), the right step is `ci-wait` again; the line sends a push first. With nothing to push the push does nothing (as CT-3).
  - :93 "git -C $TOP fetch origin pull/$pr/head": assumes a remote named `origin` that is the PR's repo, and prints `$TOP` unquoted (a path with a space pastes as two words). I did not run it (a fetch is a mutating git command under this review's rules).
  - :91 "run from a checkout of the PR's repo": does not say run what; `start` takes no workdir (SKILL.md:87), only `run <job-dir> [workdir]` does.
  - :96 "fix and push if red, then blast-off ci-wait ..., then run again": no gate and no receipt for the fix commit. At `status: done` every done row was done before child 1, so `receipt_check` skips the code-changed test for all of them (receipt.sh:62, chain.sh:155): the job ends `done` with a commit after its gated one. CI is green in that case. Pre-existing.
- Evidence: lines above, read.
- Suggested fix: ":94 first `ci-wait` again; if still absent, an empty commit and push"; quote the path; name the command in :91.

### CT-13: brief step 2 still points at a naming rule the comment no longer has
- Severity: LOW
- File: templates/brief.md:124-125 against templates/checkpoint.md:33-34
- Reachable by a template-following job: yes
- Direction: neither
- Origin: introduced by this diff
- Failure path: step 2: "a duplicate PR is recorded under "Open or blocked" before any code, named the way the checkpoint's rules comment says for a PR this job does not own". The old comment said: "by its branch or as `other PR <n>`, no '#'". The new one says only "name another PR in prose, outside the table", with no way of naming and no words "this job does not own". The pointer resolves to nothing specific. Harmless in direction: Open or blocked is outside the table and prose is not read.
- Evidence: phase-2 checkpoint.md line 29-30 (`git show`), current lines above.
- Suggested fix: step 2: "named under Open or blocked, never in the Phase plan table".

### CT-14: "wants a CI record" lost its exit code and its timing, and a red record is a record
- Severity: LOW
- File: templates/checkpoint.md:31-32
- Reachable by a template-following job: yes
- Direction: neither (the brief's "a red one means fix" covers the child)
- Origin: pre-existing ("wants a CI record for each"), made slightly weaker
- Failure path: old: "at done the runner wants a CI record for each (exit 10)". New: "The runner refuses done (exit 10) for a closed row with neither, and wants a CI record (`blast-off ci-wait`) for each PR named there." The exit 10 now belongs to the first clause only; "wants" has no stated result. Literally, a `failure` record is "a CI record". The comment never says the record must be green, or of the PR's head now, or what `absent` does.
- Evidence: phase-2 and current text.
- Suggested fix: "and refuses done (exit 10) unless `blast-off ci-wait` recorded a pass for each PR named there, after the last push to it".

### CT-15: SKILL step 4 asks the owner a fact the agent can read, in words that fit the wrong filter
- Severity: LOW
- File: skills/blast-off/SKILL.md:34-38
- Reachable by a template-following job: yes
- Direction: neither
- Origin: introduced by this diff
- Failure path: "ask whether the repo's workflows start on the stacked PR branches": the answer is in `.github/workflows/*.yml` `on:` blocks, which step 1 already has the agent read around. "start on the ... branches" fits a `push` filter (head branch); for `pull_request` the filter is on the base branch (recall), so an owner can answer the wrong question. In prompt-only mode an unanswered decision "goes in brief §2 marked as your recommendation" (SKILL.md:19-20); a fact has no recommendation. The pass condition is stated ("lets `done` through ... only where ...") but the refusal is never said outright, nor that there is no override. Also "logged "absent, not a pass"": the real line is "no CI runs and no workflow file at its head <sha> (no CI configured; absent, not a pass)" (ci.sh:95); the quoted words are a substring, fine.
- Evidence: lines above; old step 4 via `git show`.
- Suggested fix: fold into CT-1's fix.

### CT-16: README and spec row 10 against the templates (question e)
- Severity: LOW
- File: README.md:114-119,134; docs/spec.md:97; templates/checkpoint.md:30-34
- Reachable by a template-following job: n/a
- Direction: neither
- Origin: introduced by this diff
- Failure path: no contradiction found between README, spec row 10 and the templates on the rule itself. Differences, all omissions:
  - README prose (114-119) leaves out three refusals the spec and code have: a cell with both, a cell with another `#<n>` or `/pull/`, a head commit that cannot be read. Row 10 has the third, not the first two; it does say the last `run.log` line names the case.
  - README shows only `PR #<pr>`; the template adds "(or its /pull/<n> link)"; the spec adds `PR#N`, any case, leading zeros, and `no PR` in any case. The template does not say "both" is refused.
  - README does not say `ci-wait` itself exits 10 on `absent` even where `done` will pass (the spec does, the brief half does: CT-2).
  - `no PR` is conditioned three ways: README "for a phase that opened no PR" / "if the phase opened none"; template "only for a phase that opened no PR"; SKILL "a phase with no PR" (no "only").
  - Words: template "closed row", everything else "done row".
  - Spec F7 (docs/spec.md:35) still names `lib/chain.sh` as the refuser; it is `lib/ci.sh` (known nit, P3R2-39).
- Evidence: the three files, read.
- Suggested fix: add the two missing refusals to README row 10; one wording for the `no PR` condition everywhere.

### CT-17: the checkpoint template's Completed-phases line and Status rule say the PR twice; only one is read
- Severity: LOW
- File: templates/checkpoint.md:50-52
- Reachable by a template-following job: yes
- Direction: neither
- Origin: introduced by this diff ("or no PR" added to line 51)
- Failure path: line 51 has the child write "PR #<n> or no PR; CI conclusion read" under Completed phases as well as in the Status cell. The two can disagree (cell `no PR`, summary "PR #7"); the runner reads the cell and passes. `tests/41-ci-wait.sh:170-174` is that shape exactly (PR #7 under Completed phases, cell edited to `no PR`, "passes"). Nothing asks the two to match, and the final report (brief step 10, "PRs with CI read") is the only place an owner would see it.
- Evidence: lines above.
- Suggested fix: none needed in code; the README could tell the owner to compare `CI at done: PRs read: ...` in `run.log` with the final report.

### CT-18: one refusal per run
- Severity: LOW
- File: lib/ci.sh:70-81
- Reachable by a template-following job: yes
- Direction: fail-closed
- Origin: introduced by this diff
- Failure path: `chain_end` at the first bad row; a checkpoint with several rows to fix needs one `run` or `start` per row to learn them all. Covered under CT-10; listed so it is not lost if CT-10 is declined.
- Evidence: ci.sh:73,75,78.
- Suggested fix: collect the bad rows, refuse once.

---

## Round-2 HIGH status

From this angle (texts and the code they describe, by reading; I ran no test):

- P3R2-1: resolved. ci.sh:70-81 checks each done row's own cell; a row with neither is refused at :78; no whole-file read is left (`ci_prs` is called only at :71 and :83, on cells). Proving lines: tests/41-ci-wait.sh:177-180. What remains is as ruled: the same row saying `no PR` passes with a red record for a PR named in prose (41:182-184).
- P3R2-2: resolved. Nothing outside done rows' Status cells reaches `ci_prs`; 41:186-190.
- P3R2-3: resolved for the case it named (a PR head with no workflow file: ci.sh:92-95, 41:227-233). The other half, a head that has a workflow file no run can start from, is refused by ruling and has no action in any text: CT-1.
- P3R2-4: the sentence is gone and forbidden (51:82), and the rule is now an obligation (checkpoint.md:31, pinned). Reshaped in part, in weaker form: checkpoint.md:33 states where the runner does not read and is itself pinned (CT-6); ci.sh:82 offers `no PR` unqualified (CT-7); checkpoint.md:24 (CT-9); the singular "own PR" (CT-4).

## Acceptance criteria

1. Met in the runner: ci.sh:94; test 41:236-237. Not assessed here beyond reading.
2. Met in the runner: ci.sh:95; test 41:227-229. Met in part for a job that follows the brief: section 9 has no instruction for this case and one reading of it blocks (CT-2).
3. Met: ci.sh:70-84; tests 41:160-190 (prose not read), 41:170-171 (neither refused).
4. Not assessed in depth from this angle. `ci_runs` (ci.sh:52-55) drops `workflow_dispatch`; tests 41:74-82.
5. Met in part. Tests exist in 41 and 51. The texts state the rule; they do not give an action for three cases that occur (CT-1, CT-2, CT-10), two of them contradict each other or the runner's message (CT-3, CT-4), and several of the new sentences are unpinned (CT-11).

## New dependencies or reliance

- None added by the three texts as tools. New reliance, by reading:
  - The child's own check of "a file under `.github/workflows/`" (its working tree) and the runner's (`git ls-tree -r <head_sha>^{commit}`, ci.sh:92) are two different reads; they differ for an untracked or ignored workflows dir, and after any later commit.
  - ci.sh:93's remedy relies on a remote named `origin` and on GitHub's `pull/<n>/head` ref (recall).
  - ci.sh:53 relies on `gh run list --json event` (field name not checked against gh's docs by me).
  - The whole `no PR` rule relies on the child's statement being true; no tool checks it (CT-5).
- Not assessed: gh and git version floors.
