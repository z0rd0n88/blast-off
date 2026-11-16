# Failure baton: phase 3 (issue 26) hit the 3-round review cap without CLEAN

Branch feat/br-1115-issues/phase-3; last product commit d43324d. Owner rulings: owner-rulings-phase-3.md.

## What each round tried
- Work (b9c39ad): exit 10 on absent CI with workflows; PRs only from Phase plan Status cells; workflow_dispatch runs ignored.
- Review 1: ISSUES, 1 HIGH (P3R1-1: zero Status-cell PRs let done through silently) + 19 MEDIUM.
- Fix 1 (ecc6e90): whole-file fallback when no Status cell names a PR.
- Review 2: ISSUES, 4 HIGH (P3R2-1..4: fallback keyed on the whole table, prose links read, no way out for stacked PRs, template taught the slip).
- Owner rulings: every done row says `PR #N` or `no PR`, no prose read; CI-due decided at the PR head commit.
- Fix 2 (d43324d, after a 529 death and a continuation): rulings implemented across lib, templates, docs, skill, 6 tests.
- Review 3: ISSUES, 1 HIGH + 14 MEDIUM + 23 LOW. Gate PASS 18/18.

## Standing HIGH
P3R3-1 (lib/checkpoint.sh:43; lib/ci.sh:70-84; tests/41-ci-wait.sh:97,132,134): a done row the row parser drops (key `P1`, bold key, indented or tab-led row, no leading pipe, a second `## Phase plan` heading) beside one readable done row skips every gate; its PR is red or unread and done exits 0. The phase-2 base refused this (exit 10). Test 41 lines 97 and 132 currently pin the skip as expected behaviour.
Reviewer's fix: at `status: done`, refuse when the Phase plan section holds a table line that is not the header, the separator or a parsed row, or when the file has a second `## Phase plan` heading; name the line; turn 41:97,132 into refusal cases.

## Best hypothesis for the block
Each round closed one way past a fail-closed gate built on a loose Markdown parser, and the next round found the parser's edges. The reviewer's fix (refuse any unparsed table line) closes the class rather than the next instance.

## Logs
Gate: gate-phase-3-iter-3/. Report: review-phase-3-iter-3.md. Review baton: baton-phase-3-review-3.md (14 MEDIUM, 23 LOW listed there).
