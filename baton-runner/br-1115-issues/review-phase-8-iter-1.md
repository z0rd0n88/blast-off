# Review: phase 8, round 1 (issue #16, commit 71abdef)

## Executive summary
- Gate: run once, exit 0, last line `GATE: PASS passed=19 failed=0 shellcheck=ok`. Log: baton-runner/br-1115-issues/gate-phase-8-iter-1/ (stdout in review-gate-stdout.txt).
- ExecStart before and after the gate: `ExecStart=/home/alex/blast-off/.worktrees/blast-off-build/bin/blast-off run %f` (unchanged).
- Scope: `git diff 736bc67..71abdef`, 3 files (templates/brief.md, tests/51-templates.sh, docs/spec.md). 736bc67 not reviewed.
- Issue acceptance ("template text present; tests/51-templates asserts it") holds literally.
- Findings: 0 CRITICAL, 0 HIGH, 2 MEDIUM, 7 LOW.
- VERDICT: CLEAN (gate pass, zero CRITICAL/HIGH). The two MEDIUMs are worth a fix round: the sentence sits in a section the launcher rewrites, and it does not name the "user rejected" wording the child actually sees.

## Ledger of the template edit (rebuilt from the diff alone)
- Preserved, word for word: "Stop condition: a change outside the target set and the may-widen list, a decision this brief lacks, a reviewer or gate that cannot run, or a refused tool call blocks that part." and "Finish the independent work, record it."
- Changed: line wrap only. "Finish the" left the end of old line 70 and rejoined "independent work, record it." on new line 72. No word changed.
- Added: "Every tool denial in this run comes from the harness, never the owner: it is not a rejection of your work." (new lines 70 to 71, between the two preserved sentences).
- Removed: nothing.
- Test: one comment line and a two-line assertion added after the section 9 loop (tests/51-templates.sh:97-99). Spec: row 51 gains "a stop condition that says every tool denial comes from the harness, never the owner (#16)," before "and no hand-back on an estimate".

## Test probes (run in a scratch copy from `git archive HEAD`, `BLAST_OFF_TEST_ONLY=51-templates bash tests/run`, one at a time; no tracked file touched)
- M1, new sentence deleted: `GATE-ONLY: FAIL passed=0 failed=1`. The test catches removal.
- M2, ": it is not a rejection of your work" deleted, rest kept: `GATE-ONLY: PASS passed=1 failed=0`. Second clause unguarded.
- M3, whole Stop condition bullet (lines 69-72) moved out of section 4 to the end of the file: `GATE-ONLY: PASS passed=1 failed=0`. Not anchored to section 4.
- By reading (not run): the sentence moved alone, without the "or a refused tool call blocks that part." clause before it, fails; the sentence turned around ("from the owner, never the harness") fails. `fail` exits 1 (tests/lib.sh:13) and line 55 fails first on a missing brief, so the check cannot pass vacuously.

## Findings

### P8R1-1 MEDIUM: the sentence lives in section 4, which the launcher fills and rewrites, not in the verbatim section 9 Child protocol
- Location: templates/brief.md:69-72.
- Evidence: the issue says "add to the child protocol in `templates/brief.md`"; section 9 is the section titled "Child protocol". skills/blast-off/SKILL.md:49 says "Fill every section of `templates/brief.md` (§9 Child protocol verbatim ...)" and README.md:41-43 says "fill every section ... §9, the child protocol, stays verbatim." Section 4 is a filled section. A real filled brief already rewrote this exact line: /home/alex/blast-off/.worktrees/blast-off-build/.big-next-job/brief.md:233-235 reads "Stop condition: a change outside the target set, a decision the brief lacks, a reviewer or gate that cannot run, a usage limit (...), or a tool policy refusing a launch, blocks that part." A launcher that rewrites the bullet the same way drops the new sentence, and the child that needed it never sees it. The issue's acceptance box still ticks because the template holds it.
- Fix: put the sentence in section 9 step 9 ("Blocked parts do not stop the job."), for example: "A refused tool call is a blocked part. Every refused tool call in this job comes from the harness, never the owner, even when its message says the user rejected it: it is not a rejection of your work." Assert it against `$S9` in tests/51-templates.sh and update the spec row 51 wording. Leaving the section 4 sentence as well is harmless but duplicates; the lazier result is one copy, in section 9.

### P8R1-2 MEDIUM: the sentence does not name the wording the child actually sees
- Location: templates/brief.md:70-71.
- Evidence: docs/decision-log/build-2026-11-04.tsv row at 2026-11-06T14:55:10Z: "the denial was the harness's unattended auto-block, which the child read as an owner rejection ... Lesson for the template: a 'user rejected' denial in an unattended run is the auto-block". The child was misled by the word "user" in the denial text. "never the owner" does not mention "user", so a child matching on the message text still has to make the connection itself.
- Fix: add "even when its message says the user rejected it" (see P8R1-1's wording), and extend the asserted string to cover it.

### P8R1-3 LOW: the test does not guard the second clause
- Location: tests/51-templates.sh:98.
- Evidence: probe M2 passes with ": it is not a rejection of your work" deleted.
- Fix: extend `s` to the end of the sentence ("... never the owner: it is not a rejection of your work").

### P8R1-4 LOW: the test is not anchored to section 4, and the hand-back overclaims
- Location: tests/51-templates.sh:99; baton-runner/br-1115-issues/baton-phase-8-work.md ("anchored to the stop-condition clause, so dropping or moving the sentence fails").
- Evidence: probe M3 passes with the whole bullet moved to the end of the file. Moving the sentence alone does fail; moving the bullet does not.
- Fix: if the sentence stays in section 4, test against a section 4 slice (`sed -n '/^## 4\./,/^## 5\./p' "$b" | flat`), the way `S9` is built at line 88. If it moves to section 9 (P8R1-1), test against `$S9` and this goes away.

### P8R1-5 LOW: "in this run" is a new noun in the brief
- Location: templates/brief.md:71.
- Evidence: the brief calls the whole thing a "job" throughout ("owner-authorized job", "this job", "this job's branches"); elsewhere "run" means run.log, the runner, or one run of the gate ("the gate ... run on the committed tree"). "this run" can read as this child's session or one gate run. Harmless in effect, inconsistent in vocabulary.
- Fix: "in this job".

### P8R1-6 LOW: two terms for one thing in adjacent sentences
- Location: templates/brief.md:70.
- Evidence: "a refused tool call blocks that part. Every tool denial ..." A literal reader can ask whether a "denial" is a different class from a "refused tool call" (for example a hook block versus a permission refusal) and whether the block rule covers it.
- Fix: one term: "Every refused tool call in this job comes from the harness ...".

### P8R1-7 LOW: "never the owner" is false when the owner is attached to the child's window
- Location: templates/brief.md:70-71.
- Evidence: children are interactive `claude` sessions in tmux windows (lib/child.sh:2, :50), and README.md:97 tells the owner `tmux -L blast-off-<name> attach -t job-<name>   # watch the live child`. Safety prompts appear even under bypass (decision log 2026-11-06T12:43:30Z, child 24, "the harness's own rm guard, auto-blocked in unattended sessions"). An attached owner who answers such a prompt "No" is a real owner denial. The decision log calls typing into the child's window "off-limits", but that rule is in the launcher's log, not in README or the skill. Effect is small: the stop condition still blocks the part either way.
- Fix: either document "watch only, never answer a prompt in a child's window" next to README.md:97 and SKILL.md:73 (owner call), or soften to "never a reply from the owner". Owner question below.

### P8R1-8 LOW: denials from hooks and permission deny rules are owner-written policy
- Location: templates/brief.md:70-71.
- Evidence: children run as the owner's user with the owner's settings plus `--settings $CHILD_DIR/settings.json` (lib/child.sh:46-50), so the owner's PreToolUse hooks and `permissions.deny` rules apply. Their denials come through the harness but encode the owner's standing policy. "never the owner" is true of a live owner, and the stop condition keeps the safe outcome (block the part); a child should not read "never the owner" as "the owner does not mind, find another way". This is the reason the omitted retry clause (point 1) matters.
- Fix: none needed if point 1 stays as decided. If wording is touched for P8R1-2, "comes from the harness, never from a live reply by the owner" covers both P8R1-7 and P8R1-8.

### P8R1-9 LOW: the test comment misnames the denial source
- Location: tests/51-templates.sh:97 ("a child read an auto-mode denial as the owner rejecting its work").
- Evidence: the decision log row at 2026-11-06T14:55:10Z says it was "the harness's unattended auto-block", not the auto-mode classifier (the issue text also says "auto-mode classifier"; the primary record disagrees).
- Fix: "a child read a harness tool denial as the owner rejecting its work".

## Other checks (no finding)
- Does any sentence parse two ways: beyond P8R1-5 and P8R1-6, no. "it is not a rejection of your work" reads as intended next to "blocks that part".
- Is the brief used in an attended run: no. The brief opens "You are a fresh Claude Code session running an owner-authorized job under blast-off" and only blast-off children read it; the launcher session writes it but does not follow it. The only attended case is P8R1-7.
- skills/blast-off/SKILL.md and README.md: neither restates the child protocol or the stop condition; both point to the template (section 9 verbatim). README.md:84-88 talks about classifier denials in the launcher session, a different audience. No wording change needed there.
- Spec row 51 matches what the test checks (it says "a stop condition", and the test anchors on the stop-condition clause).
- Gate: shellcheck ok, all 19 scenarios pass.

## Recommendations on the work unit's 3 points
1. Retry clause left out: agree. A general "retry with a narrower command" invites rephrasing until a classifier, hook or deny rule lets the call through (P8R1-8). The existing "blocks that part" is the safe rule. The decision log's real case (rewrite `rm -f $S/*.sh` as `"${S:?}"/*.sh`) is fixing a defect in the command, which a child may do anyway as ordinary work; it needs no retry clause. Owner question 1 asks whether to add a narrow line for that case.
2. Section 4 instead of section 9: disagree. Move it to section 9 step 9 (P8R1-1). Section 9 is the verbatim Child protocol the issue names; section 4 is filled and has been rewritten in a real brief.
3. "in this run" instead of "in an unattended run": neither. Use "in this job" (P8R1-5). The brief is only ever read by unattended children, so the qualifier "unattended" adds a condition the child would have to judge for nothing, and "run" is not the brief's word.

## Open owner questions
1. Should the brief say a child may fix a real defect a denial names (for example an unguarded variable path in `rm`), but never rephrase a command just to get past a denial? Recommendation: no new line; "blocks that part" plus ordinary engineering covers it.
2. Should README.md:97 and SKILL.md:73 say "watch only; never answer a prompt in a child's window"? Recommendation: yes, one clause, so "never the owner" stays true (P8R1-7). Out of this phase's target set, so a follow-up issue.

VERDICT: CLEAN
