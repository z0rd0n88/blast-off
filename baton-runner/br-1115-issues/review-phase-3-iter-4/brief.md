# Review brief: phase 3 (issue 26) round 4, blast-off

Repo (bash project): /home/alex/blast-off/.claude/worktrees/pending-items-53932d (a git worktree, branch
feat/br-1115-issues/phase-3). Use absolute paths. Diff under review:
`git diff feat/br-1115-issues/phase-2...HEAD -- . ':!baton-runner'` (19 product files). The newest commit
e791f67 is the round-3 fix: `git diff HEAD~1 HEAD -- . ':!baton-runner'`.

## HARD RULES (verbatim from the owner's brief; breaking one is a failed review)
- No reviewer agent may run `tests/run` unfiltered, `scripts/gate.sh`, or any scenario that calls `install_units`, on the repo or on any copy.
- No one deletes anything except a temp dir they created themselves in this run.
- In this round you may NOT run any test scenario at all (`tests/run` in any form): the lead runs them. You may read code, run `shellcheck`, `bash -n`, and the lead's stub harnesses `bash <repo>/baton-runner/br-1115-issues/review-phase-3-iter-4/probes.sh <tree>` / `probes2.sh <tree>` (they source the libs with stubs; no suite, no systemd). You may copy the repo to a `mktemp -d /tmp/p3r4-<you>.XXXXXX` dir to edit copies and run those harnesses on them.
- Do not edit any file in the repo. Do not run any mutating git or gh command. Write nothing outside your own /tmp dir. Do not touch ~/.claude, ~/.config or other worktrees (reading your own parked agent definition is the one exception).
- Report everything you find at every severity. Do not be conservative and do not pre-filter.

## Fixed facts (binding, not yours to re-litigate)
- Issue 26 (z0rd0n88/blast-off): exit 10 on absent CI when workflows exist; PRs only from Phase plan Status cells; workflow_dispatch runs ignored.
- Owner ruling 1: every done row's Status cell in the Phase plan table holds `PR #N` or an explicit `no PR`; a done row with neither is refused (exit 10). Nothing in prose is ever read.
- Owner ruling 2: when a PR shows no CI runs, whether runs were due is decided at the PR record's head commit; a head with no workflow file is allowed and logged; one with a workflow file is refused (exit 10); a head not available locally fails closed.
- Owner direction this round: at `status: done`, refuse (exit 10, naming the line) any table line in the Phase plan section that is not the header, the separator or a parsed row, and any second `## Phase plan` heading.
- Accepted residuals of the rulings (not defects): a done row that says `no PR` though a PR exists passes; a deleted row takes its PR with it; a table under a different `## ` heading is prose.

## What round 3 found and what the fix changed
P3R3-1 (HIGH): a done row the row parser (`cp_rows`, `sed -n '/^## Phase plan/,/^## /{/^| *[0-9]/p}'`) drops (key `P1`, bold, indented, tab-led, no leading pipe, a second `## Phase plan` heading) beside a readable done row skipped every gate; exit 0 with that row's PR red. The fix added `cp_unread` (lib/checkpoint.sh) called first in `ci_check` (lib/ci.sh): refuses a second Phase plan heading (any level/case, ATX or setext) and any line of the section that holds a `|` and is not the header (first `|` line, first cell `#`, no digit, last cell lacks "done"), a separator or a parsed row; refuses mid-line CR. It also: replaced the Status-cell blacklist with a whitelist (P3R3-3), added `cp_rows` as the shared row reader (lib/preflight.sh uses it), reworded CAP_WHY (lib/chain.sh, tests/10-chain-done.sh), fake comments (tests/fakes/claude), and edited templates/checkpoint.md, templates/brief.md, skills/blast-off/SKILL.md, README.md, docs/spec.md. Fix record with an instruction-text ledger: baton-runner/br-1115-issues/baton-phase-3-fix-3.md. Round 3's findings: baton-runner/br-1115-issues/baton-phase-3-review-3.md.

## Lead's probe results so far (facts; judge severity yourself)
baton-runner/br-1115-issues/review-phase-3-iter-4/probes.log and probes2.log. Done let through (exit 0) beside a readable done row while a hidden row names a red PR #7: an HTML `<table>` row in the section (one-line and multi-line); a `## ` line inside an HTML comment or a fenced code block in the section, followed by a full second table (the runner's section ends at that raw line, the rendered section does not); a pipe-less line directly under the table (GFM renders it as a one-cell row); fullwidth/box-drawing pipes; a table under a visible second `## ` heading. Refused correctly: indented, tab, NBSP, P1 key, no leading pipe separator, CRLF bad row, second heading at any level, setext. A checkpoint made from templates/checkpoint.md as brief step 4 says passes, also CRLF; off-template sha spellings (backticked sha, no parens) and any digit after the PR are refused.

## Ask
1. Fail-open paths: any way a Phase plan line (as a reader of the rendered checkpoint would see it) escapes cp_unread + ci_check, beyond the list above. Does the fix close P3R3-1 as a class?
2. False refusals: anything a legitimate checkpoint written from templates/checkpoint.md (and the brief's step 4, the runner's own ` · usage` writes, cp_mark_usage's sed) would contain that now fails `done`. Rate by likelihood.
3. Are the lib/chain.sh, lib/preflight.sh, tests/10-chain-done.sh, tests/fakes/claude changes needed and correct? Does `cp_rows` change behaviour anywhere (preflight estimate, cp_mark_usage which kept its own sed)?
4. Instruction text (templates/checkpoint.md, templates/brief.md, skills/blast-off/SKILL.md, refusal messages in lib/ci.sh): meaning drift vs the rulings, and any line that teaches a child how to slip the gate.
5. Tests: do tests/41-ci-wait.sh, 51-templates.sh, 70-docs.sh pin the new rules, or could they be cut with the suite green?

## Output
Markdown, findings only, each: ID (<your-prefix>-n), severity (CRITICAL/HIGH/MEDIUM/LOW, owner's scale: CRITICAL security/data loss; HIGH a real path past the gate or a real false refusal of a checkpoint the templates produce; MEDIUM maintainability or a gate gap only an off-template file reaches; LOW minor), file:line, failure path (concrete input → observed/expected exit), evidence (command + output if you ran one), suggested fix. Then a one-paragraph verdict on P3R3-1 as a class. Write your report to /tmp/p3r4-<you>/report.md as well as returning it.
