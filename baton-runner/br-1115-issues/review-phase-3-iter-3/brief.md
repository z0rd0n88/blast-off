# Shared reviewer brief: blast-off phase 3 (issue 26), review round 3 of 3

You are one of five independent reviewers. Read this whole file, then your own role section in the prompt you were given.

## Hard rules (binding, verbatim from the owner)

- No reviewer agent may run `tests/run` unfiltered, `scripts/gate.sh`, or any scenario that calls `install_units`, on the repo or on any copy.
- No one deletes anything except a temp dir they created themselves in this run.
- Reviewers may read code, run shellcheck, `bash -n`, and (ONLY the reviewer whose prompt says it may) run a single scenario with `BLAST_OFF_TEST_ONLY=<name> tests/run` (41-ci-wait, 51-templates, 70-docs, 40-receipt-required, 21-soft-cap, 32-usage-per-phase; on the worktree or a /tmp copy), one at a time, after checking the scenario does not call `install_units`.
- Why: the suite installs and restores the owner's systemd user units with no lock; two suites at once corrupt them. An earlier review broke the owner's machine this way.
- You are read-only on product code. No Edit or Write to any tracked file. No mutating git command (no add, commit, checkout, stash, reset, restore, worktree), no push, no mutating gh. Read-only git (`git diff`, `git show`, `git log`) and read-only gh are fine.
- The only file you may write in the worktree is your own report, at the path your prompt names. Temp files go in a dir you make with `mktemp -d /tmp/p3r3-<role>.XXXXXX`. A plain `cp -r` of the worktree root carries its `.git` pointer: copy only `bin lib tests templates docs skills scripts README.md` into your temp dir.
- Never touch `~/.claude`, `~/.config`, other worktrees, the main checkout or system paths (reading `~/.claude/agents-parked/<your role>.md` is the one exception, read-only).
- Do not spawn further agents.

## Target

- Worktree: `/home/alex/blast-off/.claude/worktrees/pending-items-53932d` (bash project `blast-off`: a runner that launches a chain of checkpointed Claude sessions, "children", and refuses to end a job `done` unless gates pass). Use absolute paths; your cwd resets between shell calls.
- Diff under review: `git -C <worktree> diff feat/br-1115-issues/phase-2...HEAD -- . ':!baton-runner'`. Review only that diff; earlier phases are out of scope except where this diff breaks them. Mark every finding `introduced by this diff` or `pre-existing`.
- Changed product paths: `README.md bin/blast-off docs/spec.md lib/chain.sh lib/checkpoint.sh lib/ci.sh skills/blast-off/SKILL.md templates/brief.md templates/checkpoint.md tests/21-soft-cap.sh tests/32-usage-per-phase.sh tests/40-receipt-required.sh tests/41-ci-wait.sh tests/51-templates.sh tests/fakes/claude tests/fakes/gh`.
- The gate was run once by the coordinator on this HEAD: `GATE: PASS passed=18 failed=0 shellcheck=ok`. Do not re-run it.

## Intent: GitHub issue 26 of z0rd0n88/blast-off, as amended by two owner rulings

Issue 26 (short): D18 says absent checks are not a pass, but `done` was let through when a PR had no CI runs. Refuse `done` (exit 10) when CI is absent but the repo has workflows; allow absent only when there is no workflow file. Related: any `PR #N` in checkpoint.md was read as a PR of the workdir repo, so another repo's PR in prose blocked `done` forever; read PR numbers only from the Phase plan Status cells.

The two owner rulings are FIXED FACTS. They are binding and not yours to re-litigate. Do not file a finding that says a ruling is wrong; do file one where the code, tests or texts fail to do what a ruling says, or where something the rulings do not cover lets `done` through.

- Ruling 1: every done row's Status cell in the Phase plan table must hold `PR #N` or an explicit `no PR`; a done row with neither is refused (exit 10). Nothing in prose is ever read; there is no whole-file fallback. Existing checkpoints and the template add `no PR` to rows that have none.
- Ruling 2: when a PR shows no CI runs, whether runs were due is decided at the PR record's head commit (a file under `.github/workflows` at head_sha), not the workdir's HEAD; a head with no workflow file is allowed through and logged, one with a workflow file is refused (exit 10); a head commit not available locally fails closed.

Acceptance criteria:
1. A PR with no CI runs whose head commit has a workflow file: `done` refused, exit 10.
2. A PR with no CI runs whose head commit has no workflow file: `done` allowed, logged.
3. PR numbers come only from Phase plan Status cells; prose is never read; a done row with neither `PR #N` nor `no PR` is refused.
4. `workflow_dispatch` runs do not count as the PR's CI in either direction.
5. Tests for 1 to 4 in `tests/41-ci-wait.sh` (and `tests/51-templates.sh` for template text), and the spec, README, skill text and templates state the rules as they now are.

## Round 2's four HIGH findings and what the fix changed (commit d43324d)

Check each is really gone under the rulings, not reshaped into another form.

- P3R2-1: one `PR #N` token in any Status cell switched off the read of every other PR the checkpoint named, so a done row closed without its PR passed with a red record. Fix: `ci_check` (`lib/ci.sh:68-100`) walks every done row (`cp_done_cells`, `lib/checkpoint.sh:37-47`) and refuses a row whose Status cell has neither token, or both; the whole-file fallback is deleted.
- P3R2-2: in the fallback another repo's `/pull/N` link in prose was read as this repo's PR N. Fix: by removal; nothing outside done rows' Status cells is read.
- P3R2-3: the absent-CI refusal had no working way out for an earlier stacked PR whose own head has no workflow file. Fix: `git ls-tree -r <record head_sha>^{commit} -- .github/workflows` in the workdir's repo decides; unreadable commit or no git repo refuses.
- P3R2-4: `templates/checkpoint.md` told the child "A row closed without one gets no CI check": which edit drops a PR from the gate. Fix: reworded to an obligation (`templates/checkpoint.md:30-34`), pinned in `tests/51-templates.sh`.

Also changed by the fix: a done Status cell holding any other `#<digit>` or `/pull/` is refused; a job with no done row at all (no table, header-only table, mis-typed heading) is refused at `done`; `grep -a` in `ci_prs`; `templates/brief.md` says what to do on `absent`; `skills/blast-off/SKILL.md` step 4 reworded; `tests/fakes/claude` got a `fin` helper that appends a one-row Phase plan table (and, in a git workdir, a PASS receipt) whenever a fake child sets status done.

Earlier material you may read: `baton-runner/br-1115-issues/baton-phase-3-review-2.md`, `review-phase-3-iter-2.md`, `baton-phase-3-fix-2.md`, `owner-rulings-phase-3.md` (same directory tree). The fix baton is the fixer's own account: verify, do not trust.

## What to look for

This phase changes a completion gate. Above all, hunt for FAIL-OPEN paths: any input, gh error, empty output, missing tool, malformed record or malformed checkpoint that lets `status: done` end in exit 0 `job done` when a PR's CI did not pass or was never read. For each, give the exact input and the path through the code.

Leads, as open questions (find your own too; answer with evidence, either way):
- A row whose key has no digit (`P1`), a bold key, an indented row, a row with no trailing pipe, extra cells after Status: is such a row read, refused, or silently skipped by every gate? What happens when it sits beside a row the runner does read? What did the phase-2 code (`git show feat/br-1115-issues/phase-2:lib/ci.sh`) do with the same checkpoint?
- A table with no rows, no table, two `## Phase plan` headings, a row marked done in a way the parser does not recognise.
- `no PR` written on a row that plainly has a PR; `no PR` beside a PR written without `#`; case and spacing variants of `PR #N` and `no PR`.
- The record file `gate-logs/ci-pr-<n>.json`: missing fields, wrong types, two JSON values, a head_sha that is not a sha; `gh pr view` failing, timing out, printing nothing.
- `git ls-tree` on odd inputs: a shallow clone, a tag or tree sha, `.github/workflows` as a file or symlink, a workdir in a different repo than the PR.
- Does any refusal message, README line, spec line or template line point a child or owner at an edit that drops a real PR from the gate (for instance replacing `PR #7` with `no PR` after an exit 10)?
- `ci_wait` exits 10 on every `absent` record, workflow file or not. Following `templates/brief.md` section 9 word for word, what does a child in a repo with NO workflow file do after that exit 10: can criterion 2 be reached by an obedient child?
- The fix baton says a live job started before this change is refused at `done` until its rows are edited. Is that stated anywhere an owner or a child will read it (README, spec, the refusal text)? At `status: done` no child is launched, so who can make the edit?
- Does the fake's `fin` helper (`tests/fakes/claude`) mask an assertion an earlier-phase scenario relied on (a job with no table ending done, the hard cap of exit 4, the receipt check)?
- Are the tests real? Which assertion fails if the code line it covers is removed? Name any behaviour the diff adds that no test pins.
- New dependencies or new reliance on a tool, a tool version, a gh field or a git feature: list each.

## Severity rubric (the owner's levels; apply them honestly, in both directions)

- CRITICAL: security vulnerability or data-loss risk: block merge.
- HIGH: bug or significant quality issue: fix before merge.
- MEDIUM: maintainability concern: consider fixing.
- LOW: style or minor suggestion: optional.

Report EVERYTHING you find at EVERY severity. Do not be conservative, do not pre-filter, do not drop LOW items. Equally, do not inflate. For every finding state these facts, because the synthesizer needs them to rate consistently:
- `reachable by a job that follows templates/checkpoint.md and templates/brief.md as written`: yes / no / only by an off-template checkpoint (say what the child or owner must have done).
- `direction`: fail-open (done passes when it should not) / fail-closed (done refused when it should pass) / neither.
- `origin`: introduced by this diff / pre-existing / pre-existing and made worse.
- `evidence`: how you know (command run and its output, or file:line read). Mark reasoning from recall about GitHub's behaviour as such.

## Report format

Write your report to the path your prompt names. Start with a 3 to 6 line summary, then one section per finding:

```
### <ROLE>-<n>: <title>
- Severity: CRITICAL | HIGH | MEDIUM | LOW
- File: <path>:<line>
- Reachable by a template-following job: ...
- Direction: ...
- Origin: ...
- Failure path: <exact input, then what the code does, step by step>
- Evidence: ...
- Suggested fix: ...
```

Then three closing sections: `## Round-2 HIGH status` (P3R2-1 to P3R2-4: resolved / reshaped / open, one line of evidence each), `## Acceptance criteria` (1 to 5: met / met in part / not met, with the test line that proves it), `## New dependencies or reliance`. Your final message back is a 10-line summary: counts by severity, the titles of every CRITICAL and HIGH, and your report path.
