# Review: phase 8, round 2, narrow (issue #16, fix commit f4baca5)

## Summary
- Gate: run once, alone, exit 0, last line `GATE: PASS passed=19 failed=0 shellcheck=ok`. Log: baton-runner/br-1115-issues/gate-phase-8-iter-2/ (stdout in gate-stdout.txt, scenarios in tests-run.log).
- ExecStart before the gate: `ExecStart=/home/alex/blast-off/.worktrees/blast-off-build/bin/blast-off run %f`. After: the same. No change.
- Scope: `git diff 71abdef..f4baca5` (the fix) and `git diff 736bc67..f4baca5` (the phase): 3 files, templates/brief.md (one hunk, section 9 step 9), tests/51-templates.sh (+3), docs/spec.md (row 51). 736bc67 not reviewed.
- Round 1: all 9 findings closed; P8R1-4 closed for section anchoring, not step anchoring (P8R2-3); P8R1-7 holds only while no owner answers a prompt in a child's window (round 1 owner question 2, still open).
- Findings: 0 CRITICAL, 0 HIGH, 1 MEDIUM, 4 LOW.
- VERDICT: CLEAN (gate pass, zero CRITICAL/HIGH). The MEDIUM is the parse question the brief asked about: "do not ... ask the owner about it" next to "Record each ... with the question". A two-word fix ("in chat") settles it.

## Round 1 closure
- P8R1-1 closed. The sentences sit in section 9 step 9 (templates/brief.md:171-174). `git diff 736bc67 f4baca5 -- templates/brief.md` has one hunk, in step 9; section 4 lines 69-71 equal 736bc67.
- P8R1-2 closed. "even when its message says the user rejected it" is present and asserted.
- P8R1-3 closed. The test asserts both sentences through "...ask the owner about it." (tests/51-templates.sh:98-99).
- P8R1-4 closed for section anchoring: the assertion runs against `$S9`. Not anchored to step 9 (see P8R2-3).
- P8R1-5 closed. "in this job".
- P8R1-6 closed. "refused tool call" in both sentences; `grep -i 'denial\|denied' templates/brief.md` finds nothing.
- P8R1-7 closed in wording ("never a live reply from the owner"). Still true only while the owner never answers a prompt in an attached child window; README.md:97 and skills/blast-off/SKILL.md:73 still say only "watch the live child". Round 1 owner question 2 stays open.
- P8R1-8 closed. "live reply" leaves owner-written hooks and deny rules on the harness side; no retry clause (decided).
- P8R1-9 closed. Test comment: "a child read a harness tool denial as the owner rejecting its work and stopped its round", which matches the decision log row 2026-11-06T14:55:10Z.

## Ledger of the template edit (rebuilt from `git diff 736bc67..f4baca5 -- templates/brief.md` alone)
- One hunk, section 9 step 9. Section 4 and every other section: no change.
- Preserved, word for word: heading "**Blocked parts do not stop the job.**"; "Record each under "Open or blocked" with the question and your recommendation, leave any patch in `phases/`, and continue the independent work. Set `status: blocked` only when nothing independent is left." (the last line is an unchanged context line).
- Changed: line wrap only. "your" moved from the start of old line 2 to the end of new line 4; "Set" stays at the end of the line before `status: blocked`.
- Added, between the heading and "Record each": "A refused tool call is a blocked part. Every refused tool call in this job comes from the harness, never a live reply from the owner, even when its message says the user rejected it: it is not a rejection of your work, so do not stop the job or ask the owner about it."
- Dropped: nothing.
- The hand-back's ledger agrees on every item. One wrong line number (P8R2-4).

## Test probe (one, scratch copy from `git archive HEAD`, `BLAST_OFF_TEST_ONLY=51-templates bash tests/run`, copy deleted after)
- Both new sentences cut from step 9 and appended to the end of step 14 (still inside section 9): `GATE-ONLY: PASS passed=1 failed=0 shellcheck=ok only=51-templates`. The test does not see a move within section 9.
- Not re-run, taken from the fix hand-back: removing ": it is not a rejection of your work" fails (probe 1); moving both sentences into section 4 fails (probe 2). By reading: deleting either sentence or any word of them fails, since the assertion is one literal string over the flattened section; `fail` exits 1 (tests/lib.sh), so it cannot pass vacuously.

## Findings

### P8R2-1 MEDIUM: "do not ... ask the owner about it" reads against "Record each ... with the question"
- Location: templates/brief.md:173-175 (section 9 step 9); same string in tests/51-templates.sh:98.
- Evidence: the step now says "...so do not stop the job or ask the owner about it. Record each under "Open or blocked" with the question and your recommendation". "Open or blocked" is the brief's channel for asking the owner: templates/checkpoint.md:61 ("<item needing the owner, with the question and your recommendation ...>") and README.md:163 ("blocked: the job needs the owner | answer what `Open or blocked` asks"). A child can read it two ways:
  - (a) "ask the owner" means ask in chat (the decision log row 2026-11-06T14:55:10Z: child 27 "stopped and asked the owner"), so it records the refused call with a question as usual. This is the reading the step needs, and step 14 already bans chat questions.
  - (b) "ask the owner about it" covers any question to the owner, so a refused call gets recorded with no question, or, with "each" now read as "each refused tool call" (its nearest antecedent after the insert), "with the question" contradicts the sentence before it.
  Reading (b) costs the owner the one thing that can unblock the part (grant the permission, change the hook, or run the step). Not HIGH: the "Record each" imperative still stands, so the part is recorded either way.
- Fix: add "in chat": "...so do not stop the job for it or ask the owner about it in chat." Update the asserted string in tests/51-templates.sh:98 to match. Lazier alternative: drop "or ask the owner about it" (step 14 already covers chat), but "in chat" keeps the pointer to the incident.

### P8R2-2 LOW: "do not stop the job" is unconditional, two sentences before the case where the job does stop
- Location: templates/brief.md:173 and 175-176.
- Evidence: "so do not stop the job" is followed by "Set `status: blocked` only when nothing independent is left." When the refused call blocks the last independent work, the child must set `status: blocked`, which ends the job. The heading ("Blocked parts do not stop the job") and "only when" let a careful reader reconcile them; a literal one sees two rules.
- Fix: "do not stop the job for it" (part of P8R2-1's wording) ties the rule to the refusal alone.

### P8R2-3 LOW: spec row 51 says "section 9 step 9"; the test checks only section 9
- Location: docs/spec.md:253; tests/51-templates.sh:88 and 98-99.
- Evidence: `S9` runs from "## 9. Child protocol" to end of file. The probe above moved both sentences into step 14 and the scenario passed. Row 51 also says "a ... sentence"; the asserted text is two sentences and includes "do not stop the job or ask the owner about it", which the row does not mention. Effect is small: anywhere in section 9 is still read by every child, verbatim.
- Fix: lazier: reword the row to "a section 9 child-protocol rule that a refused tool call is a blocked part, comes from the harness ...". Or anchor the test: slice step 9 out of `$S9` (`x="${S9#*'**Blocked parts do not stop the job.**'}"; x="${x%%'10. **Finish.**'*}"`) and assert against `$x`.

### P8R2-4 LOW: the hand-back ledger gives section 4's Stop condition as lines 69-70; it is 69-71
- Location: baton-runner/br-1115-issues/baton-phase-8-fix-1.md:30.
- Evidence: `git show 736bc67:templates/brief.md | sed -n 69,71p` prints the whole bullet on three lines, the last "independent work, record it.". The ledger also covers only the template; the test and spec changes are listed only under "Per finding". Content otherwise matches the rebuilt ledger above.
- Fix: none needed in tracked files; note for the run record.

### P8R2-5 LOW: "Every refused tool call ... comes from the harness" is false if a child counts a remote refusal as a refused tool call
- Location: templates/brief.md:171-172.
- Evidence: "refused tool call" is not defined. A `git push` rejected by branch protection or a `gh` call answered 403 is refused by GitHub, not the harness. Read that broadly, the sentence states a false source. Effect nil: the step still makes it a blocked part, recorded, work continues, which is the right outcome.
- Fix: none needed. If touched, "(a permission, hook or classifier block)" after the first "refused tool call" bounds it.

## Other checks (no finding)
- Every other sentence is true: "A refused tool call is a blocked part" matches section 4 ("or a refused tool call blocks that part"); "even when its message says the user rejected it" paraphrases the harness text the child saw (issue #16: "read ... as 'You rejected my command'"); "it is not a rejection of your work" holds for a permission, hook or classifier block.
- "do not stop the job" correctly overrides the harness denial text, which in Claude Code tells the session to stop and wait for the user (from the harness text as I know it; not recorded in this repo).
- No retry clause, as decided.
- Gate: shellcheck ok, 19 of 19 scenarios pass, ExecStart unchanged.

## Owner questions
1. P8R2-1: for a refused tool call, should the child record a question for the owner under "Open or blocked" (for example "allow X, or run step Y yourself?")? Recommendation: yes; add "in chat" so the step bans only the chat question that stalled child 27.
2. Carried from round 1, question 2, still open and out of this phase's target set: should README.md:97 and skills/blast-off/SKILL.md:73 say "watch only; never answer a prompt in a child's window", so "never a live reply from the owner" stays true? Recommendation: yes, as a follow-up issue.

VERDICT: CLEAN
