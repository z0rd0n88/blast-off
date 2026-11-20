# Phase 8 review, round 1 (issue #16, commit 71abdef)

## What I did
- Read ExecStart, ran the gate once alone, read ExecStart again. Both reads: `ExecStart=/home/alex/blast-off/.worktrees/blast-off-build/bin/blast-off run %f` (unchanged). Gate exit 0, last line `GATE: PASS passed=19 failed=0 shellcheck=ok`. Log in gate-phase-8-iter-1/.
- Read issue #16, the diff `736bc67..71abdef`, all of templates/brief.md, the test, the spec row, the README and SKILL.md sections on the brief and on watching children, lib/child.sh launch code, and the decision-log rows for child 24 and child 27.
- Ran three single-scenario probes of 51-templates in a scratch copy from `git archive HEAD` (not the worktree): sentence deleted fails; second clause deleted passes; whole bullet moved out of section 4 passes.
- No tracked file touched; `git status --porcelain -uall` clean.

## Verdict
CLEAN: gate pass, 0 CRITICAL, 0 HIGH, 2 MEDIUM, 7 LOW. Full report: review-phase-8-iter-1.md.

## Findings
- P8R1-1 MEDIUM: sentence lives in section 4 (launcher-filled, rewritten in a real brief), not the verbatim section 9 Child protocol the issue names.
- P8R1-2 MEDIUM: sentence does not name the "user rejected" wording the child sees.
- P8R1-3 LOW: test does not guard ": it is not a rejection of your work".
- P8R1-4 LOW: test not anchored to section 4; hand-back's "moving the sentence fails" overclaims.
- P8R1-5 LOW: "in this run" is a new noun; the brief says "job".
- P8R1-6 LOW: "refused tool call" and "tool denial" in adjacent sentences.
- P8R1-7 LOW: "never the owner" is false if the owner, attached via tmux, answers a prompt.
- P8R1-8 LOW: hook and deny-rule denials are owner-written policy.
- P8R1-9 LOW: test comment says "auto-mode denial"; the log says harness auto-block.

## Recommendations on the work unit's points
1. Retry clause out: agree.
2. Section 4: move to section 9 step 9.
3. "in this run": use "in this job".

## What the next unit needs
- The verdict is CLEAN, so the loop may close. If a fix round runs for the MEDIUMs, one edit covers P8R1-1, -2, -3, -4, -5, -6 and -9: move the sentence into section 9 step 9 as "Every refused tool call in this job comes from the harness, never the owner, even when its message says the user rejected it: it is not a rejection of your work.", assert the full sentence against `$S9`, update the comment at tests/51-templates.sh:97 and spec row 51. Red first: the new `$S9` assertion fails on 71abdef.
- P8R1-7 and the two owner questions touch README.md and SKILL.md, outside this phase's target set: record as open, do not edit.
