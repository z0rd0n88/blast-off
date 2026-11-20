# Phase 8 fix, round 1 (issue #16)

Commit: f4baca5 `fix(templates): denial wording in the child protocol (#16, review round 1)`
(templates/brief.md, tests/51-templates.sh, docs/spec.md). Committed before the probes so `git archive HEAD` carries the fix.

New text, section 9 step 9, after the heading "Blocked parts do not stop the job.":
"A refused tool call is a blocked part. Every refused tool call in this job comes from the harness, never a live reply from the owner, even when its message says the user rejected it: it is not a rejection of your work, so do not stop the job or ask the owner about it."

## Per finding
- P8R1-1 (MEDIUM): done. Sentence moved out of section 4 into section 9 step 9. Section 4 Stop condition is byte-identical to 736bc67 (`git diff 736bc67 -- templates/brief.md` shows only step 9).
- P8R1-2 (MEDIUM): done. Adds "even when its message says the user rejected it".
- P8R1-3 (LOW): done. Test asserts the whole text through "it is not a rejection of your work, so do not stop the job or ask the owner about it." Probe 1 proves it.
- P8R1-4 (LOW): done. Test asserts against `$S9` (section 9 slice, tests/51-templates.sh:88). Probe 2 proves it.
- P8R1-5 (LOW): done. "in this job".
- P8R1-6 (LOW): done. "refused tool call" both times, the term section 4 and the new first sentence use; "denial" no longer appears in the brief.
- P8R1-7 (LOW): done by wording. "never a live reply from the owner" stays true given that no owner answers prompts in a child's window. The README/SKILL "watch only" clause (owner question 2) is outside this phase's target set; not touched.
- P8R1-8 (LOW): done by wording. Owner-written hooks and deny rules reach the child through the harness and are not a live reply, so the sentence holds. No retry clause added (agreed to leave out); the part stays blocked.
- P8R1-9 (LOW): done. Test comment now "a child read a harness tool denial as the owner rejecting its work".
- Spec row 51: now "a section 9 step 9 sentence that every refused tool call in this job comes from the harness, never a live reply from the owner, even when its message says the user rejected it, and is not a rejection of the work (#16)".

## Runs
- Red (test changed, template not yet): `GATE-ONLY: FAIL passed=0 failed=1 shellcheck=ok only=51-templates` (FAIL: brief section 9 lacks: A refused tool call is a blocked part. ...)
- Green: `GATE-ONLY: PASS passed=2 failed=0 shellcheck=ok only=51-templates,70-docs`
- Probe 1, `git archive HEAD` copy, ": it is not a rejection of your work" deleted: `GATE-ONLY: FAIL passed=0 failed=1 shellcheck=ok only=51-templates`
- Probe 2, `git archive HEAD` copy, both new sentences moved from step 9 into the section 4 Stop condition: `GATE-ONLY: FAIL passed=0 failed=1 shellcheck=ok only=51-templates`
- Copies deleted after.

## Ledger against 736bc67
Section 4 (Stop condition):
- Preserved: the whole bullet, word for word and line for line (lines 69-70 as at 736bc67).
- Changed: nothing.
- Added: nothing.
- Dropped: nothing (the 71abdef sentence is gone, so section 4 equals 736bc67).

Section 9 (step 9):
- Preserved: heading "Blocked parts do not stop the job." and every word of the old step text ("Record each under "Open or blocked" with the question and your recommendation, leave any patch in `phases/`, and continue the independent work. Set `status: blocked` only when nothing independent is left.").
- Changed: line wrap only for the old text (rewrapped after the inserted sentences).
- Added: "A refused tool call is a blocked part. Every refused tool call in this job comes from the harness, never a live reply from the owner, even when its message says the user rejected it: it is not a rejection of your work, so do not stop the job or ask the owner about it."
- Dropped: nothing.
