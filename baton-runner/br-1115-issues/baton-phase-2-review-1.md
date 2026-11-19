---
source: runner
scope: br-1115-issues
parent_session: ""
---
# Pass-Baton: phase 2 review round 1 (issue 31), VERDICT CLEAN, 0 CRITICAL, 0 HIGH, 6 MEDIUM, 16 LOW

**Date:** 2026-11-15
**Scope:** br-1115-issues
**Branch:** feat/br-1115-issues/phase-2
**Worktree:** /home/alex/blast-off/.claude/worktrees/pending-items-53932d
**HEAD:** 5062c7d feat(phase-2): BLAST_OFF_TEST_ONLY filter in tests/run and a ci `only` dispatch input (#31)

## Where things stand

VERDICT: CLEAN by the contract's rule: gate exit 0, zero CRITICAL or HIGH in the synthesized report, and every acceptance criterion with behaviour has a passing test (cited below). CLEAN does not mean nothing to fix: 6 MEDIUM and 16 LOW are open and are the manager's to triage. The one to read before phase 3 is P2R1-1 (`ci-wait` counts a filtered dispatch run), because issue 26 changes `lib/ci.sh` and `tests/41-ci-wait.sh`.

- Gate: `scripts/gate.sh` ran once, alone, before any reviewer: exit 0, `GATE: PASS passed=18 failed=0 shellcheck=ok`. Log: `baton-runner/br-1115-issues/gate-phase-2-iter-1/tests-run.log`.
- ExecStart check: `ExecStart=/home/alex/blast-off/.worktrees/blast-off-build/bin/blast-off run %f` after the gate, after my mutation runs and at the end. Unchanged.
- Multi-agent review: ran. Report: `baton-runner/br-1115-issues/review-phase-2-iter-1.md` (6/6 reviewers returned, reviewed at 5062c7da28f15dd87d294c5f491a1ac0fd9f4f4b, Report Audit appended, 2 audit issues, neither touching a severity or count). Reviewer outputs: `baton-runner/br-1115-issues/review-phase-2-iter-1/<reviewer>.md`. Deviations, all in the report's `## Notes`: inline from this unit (no orchestrator layer); the six rostered agents (critical-thinking, code-reviewer, penetration-tester, security-reviewer, silent-failure-hunter, tdd-guide) are parked, so each ran as a `general-purpose` agent reading its parked definition read-only; `--high-cap off`; reviewers were held to static work (no scenario runs at all), so I ran their repro commands and mutants myself afterwards, one scenario at a time on a `git archive` copy.
- Side effect of the review: security-reviewer deleted `<session scratchpad>/rt` by mistake. It held phase 1's kept work-dir tree (`blast-off-tests`); not restorable. Nothing in the repo, worktree, `~/.claude` or `~/.config` was touched. Phase 1's record `fix-phase-1-iter-1/tests-run-keep.log` is intact.
- New dependencies: none. No new action, package or tool. The change does lean on one GitHub behaviour nobody has observed here: `${{ inputs.only }}` being empty on a `pull_request` event.
- Tracked files unchanged by this unit (`git status --porcelain` shows only untracked `baton-runner/` paths).

## Intent check (issue 31)

| Criterion | Evidence | Test real? |
|---|---|---|
| 1. `only` input, env only, empty is the full suite, unknown name fails | `ci.yml:12-16,51`; PyYAML: no step's `run` holds `${{`; the 3 expression lines are `:48,51,70`. Filter, several names, unknown name, empty: `tests/00-harness.sh:22-50` | Yes for the filter (M2, M3, M4 red). The workflow half is file and line only, unproven on a runner. `ci.yml` has no `push` trigger (`:9-11`), only `pull_request` and `workflow_dispatch` |
| 2. Filtered verdict is not `GATE: PASS`; receipt refuses; filter in `tests/run`, in its header | `tests/run:11-16,39-40,46,61-63,85-91`; `lib/receipt.sh:8` | `tests/40-receipt-required.sh:60-67` (M1, M7 red) |
| 3. Tests prove 2 and the filter | `tests/00-harness.sh:22-50,108-110`; `tests/40-receipt-required.sh:60-67` | 7 of 7 intended mutants red |
| 4. Spec and header name it | `docs/spec.md:206-207,216`; `tests/run:11-16` | read |

Mutants, each run alone through a one-symlink scenario dir on a scratch copy (baseline: both scenarios `GATE: PASS passed=1`):

- Red as intended: M1 `gate=GATE-ONLY` to `GATE` (00 "one named scenario", 40 "receipt on a filtered run's log: exit 0"); M2 filter line removed; M3 unknown-name loop removed; M4 `unset` removed; M5 `ci.yml` env line deleted; M6 `${{ inputs.only }}` in the run script; M7 `lib/receipt.sh:8` loosened to `"GATE"*` (40 red: a FAIL receipt is written).
- Survive, as reviewers predicted: S1 `ci.yml:12-16` deleted; S2 `tests/run ${{ env.BLAST_OFF_TEST_ONLY }}` at `ci.yml:56`; S3 `read` without `-d ''`; S4 substring match at `tests/run:62`; S5 `GATE:` prefix kept when `DIR = HERE` (00 and 40 both green); S6 no shellcheck on a filtered run.
- Probes: keep dir refused plus filter ends `GATE: FAIL passed=0 failed=1 shellcheck=skipped`; `only=-n` ends `only=` (blank); `only='x##[error]boom'` printed raw in both lines; `$'01-ok\n09-x'` gives `PASS 01-ok`, `FAIL only 09-x`, `GATE-ONLY: FAIL passed=1 failed=1`; `only=nope` with a keep dir then the `ci.yml:64` tar line: tar exit 0, 1 member, 121 bytes; the CI dispatch path on the copy (real suite dir, keep dir, `only=70-docs`, run from the copy's root): `PASS 70-docs`, `PASS shellcheck (33 files)`, `GATE-ONLY: PASS passed=1 failed=0 shellcheck=ok only=70-docs`, exit 0, keep dir holds `70-docs` only; the `ci.yml:64` tar line on that filtered kept tree: exit 0, 4 members, all under `blast-off-tests/70-docs`.

## Findings

Severity is the report's (highest any reviewer filed). "Confirmed" means I ran it. P2R1-20 to 22 are mine, not in the report's table.

| ID | Sev | Where | Failure path | Suggested fix |
|---|---|---|---|---|
| P2R1-1 | MEDIUM | `lib/ci.sh:19,29,35-41`; `ci.yml:12-16,51`; claim at `baton-phase-2-work.md:134` | `ci_wait` lists runs by commit with no event filter and records `{id,name,conclusion}`, all named `ci`. On a PR head with no `pull_request` run, one green `only=70-docs` dispatch turns the record from `absent` (exit 10) to `success` (exit 0). A red diagnostic dispatch or a typo'd name makes `ci-wait` exit 10 until the head moves. It cannot mask a red full run. The work baton's "nothing gates on it" is false. Verdict half needs GitHub, not run | Read `event` in both `gh run list` calls and leave `workflow_dispatch` out of the verdict, with one `41-ci-wait` case. Outside this phase's files; phase 3 touches both |
| P2R1-2 | MEDIUM | `tests/run:88-89`; `scripts/gate.sh:4,10` | A filtered pass exits 0. `gate.sh` passes the caller's env and the status through, so an exported `BLAST_OFF_TEST_ONLY` makes the review gate one scenario with exit 0. Exit 0 on a filtered pass confirmed; `gate.sh` itself not re-run (gate runs once). This round's gate log ends `GATE: PASS passed=18`, so it was not filtered | `env -u BLAST_OFF_TEST_ONLY tests/run` in `scripts/gate.sh`, or fail when the last line is not `GATE: `. Outside the file set |
| P2R1-3 | MEDIUM | `tests/00-harness.sh:108-110` | The pin is one line plus a count of `inputs.`. Deleting the input declaration, moving the env line to another step, or writing `${{ env.BLAST_OFF_TEST_ONLY }}`, `${{ inputs['only'] }}` or `${{ toJSON(inputs) }}` into the run script all stay green. Extends P1R2-2. Confirmed (S1, S2) | Assert the set of `${{` lines is the three at `ci.yml:48,51,70`; pin `      only:` under `inputs:` |
| P2R1-4 | MEDIUM | `tests/run:39`; `tests/00-harness.sh:33` | No test value holds a newline or tab. Without `-d ''` every name after the first line is dropped and the run passes. Confirmed (S3) | Add `$'02-b\n01-a'` and a tab form to the loop |
| P2R1-5 | MEDIUM | `tests/00-harness.sh:25-50,89-99`; `tests/run:66,87` | Every filtered test run is a fixture dir with shellcheck skipped; CI's path (`DIR = HERE`) has no assertion. A mutant printing `GATE: PASS passed=1` on a filtered real-suite run passes both scenarios. Confirmed (S5, S6) | One run of the `self` fixture with `BLAST_OFF_TEST_ONLY=01-ok`, last line exact |
| P2R1-6 | MEDIUM | `tests/00-harness.sh:22-23`; `tests/40-receipt-required.sh:60-61`; `tests/run:21,87` | Pre-existing, not made worse: `tests/run <dir with one scenario>` still prints `GATE: PASS passed=1`, which `receipt` accepts. The new comments say one green scenario never receipts a phase | Reword both comments to "a run filtered by BLAST_OFF_TEST_ONLY"; file the scenario-dir case |
| P2R1-7 | LOW | `tests/run:30` before `:39`; `docs/spec.md:216` | Keep dir refused plus filter ends in a `GATE: FAIL` line; the spec says "never a `GATE:` line". Fails closed. Confirmed | Parse `only` above the keep block and use `$gate`/`$tail` in `no_keep`, or soften the spec |
| P2R1-8 | LOW | `tests/00-harness.sh:28`; `ci.yml:48,51` | Keep dir plus filter, what CI sets on every dispatch, has no test. By hand it keeps only the named scenario | One keep-plus-only case |
| P2R1-9 | LOW | `tests/run:33,61-63`; `ci.yml:4-5,62-71` | A typo'd name: red run, tar exit 0 on an empty keep dir, green upload of an empty archive. A new route beside P1R2-1, which its fix would not cover. Confirmed locally | Fix with P1R2-1 (no upload when empty); reword `ci.yml:4-5` |
| P2R1-10 | LOW | `tests/run:87` | `echo` eats a sole name `-n`, `-e`, `-E`: verdict ends `only=`. Confirmed | `printf '%s' "${only[*]}"` |
| P2R1-11 | LOW | `tests/run:39,62,87` | Names are echoed raw: a CR, escape bytes or `x##[error]boom` reach the log. From runner source (penetration-tester) `##[...]` lines become workflow commands; a dispatch needs write access, the run is always red. Local half confirmed; runner half unproven | Refuse a name not matching `^[0-9A-Za-z._-]+$`, printed with `%q` |
| P2R1-12 | LOW | `tests/run:62`; `tests/00-harness.sh:40-45` | The whole-word match of the unknown-name check is unpinned. Confirmed (S4) | Add `'01-a 1-a'` and `'01-a 0?-a'` cases |
| P2R1-13 | LOW | `tests/run:11-16`; `docs/spec.md:216,227`; `ci.yml:14` | Docs say "spaces or commas" (tabs and newlines split too), do not say shellcheck still runs on a filtered real-suite run, nor that separators-only is the whole suite; spec row 40 does not name its new assertion | One clause each |
| P2R1-14 | LOW | `README.md:107,148`; `scripts/gate.sh:3-4`; `docs/spec.md:24`; `templates/brief.md:61`; `skills/blast-off/SKILL.md:33,85`; `.claude/big-next-job.md:5-6` | Still say every `tests/run` ends `GATE: PASS` or `GATE: FAIL`. Outside criterion 4's list | One clause, or accept |
| P2R1-15 | LOW | `tests/run:56-59` | A reused keep dir holds stale dirs of scenarios a filtered local run skipped. CI unaffected | Header clause |
| P2R1-16 | LOW | `tests/run:39` | `\|\| true` hides a failed here-string; the run then stops with no verdict line. Close to unreachable | `declare -a only` first |
| P2R1-17 | LOW | `tests/40-receipt-required.sh:62-67` | Only a `GATE-ONLY: PASS` log is put through `receipt`; the FAIL side holds by reading | Optional second fixture |
| P2R1-18 | LOW | `tests/run:39,86` | Naming: `only` is a string then an array; a variable named `tail` | Optional |
| P2R1-19 | LOW | `tests/00-harness.sh:28-50` | All `only` calls share `onlyfix.out`; a repeated name is unpinned | Optional |
| P2R1-20 | LOW | `ci.yml:12-16,51` | Nothing in this diff has run on GitHub: `inputs.only` on `pull_request`, an empty dispatch and a filtered dispatch are all unobserved. Extends P1R2-3 to every PR run | One PR run, one `only=70-docs` dispatch, before merge |
| P2R1-21 | LOW | `ci.yml:9-11` | Criterion 1 says "push/pull_request"; `ci.yml` has no `push` trigger. Pre-existing | None unless a push run is wanted |
| P2R1-22 | LOW | `tests/run:66-82` | Outside the diff, cause not verified: the same copy and command gave `shellcheck=fail` (SC2034 on `CHILD_WIN`, `TIMEOUT`, `BLAST_OFF_TRUST_SECONDS`) when `tests/run` was called by absolute path from another directory, and `shellcheck=ok` from the copy's root. CI and `scripts/gate.sh` run from the root | Check `source=` path resolution; `cd "$REPO"` before linting if confirmed |

The report also lists 13 PENDING open questions (its `## Open Questions for the Author`) and 2 Report Audit items: the Executive Summary credits all five severity-using reviewers with "four criteria met" where two said it, and one Coverage attribution to critical-thinking is too wide.

## Next steps

1. Manager: triage P2R1-1 to P2R1-22. P2R1-1 and P2R1-2 need files outside phase 2's set (`lib/ci.sh`, `tests/41-ci-wait.sh`, `scripts/gate.sh`); P2R1-1 fits phase 3 (issue 26).
2. If a fix round runs: P2R1-3, -4, -5, -7, -10, -12 are each one or two lines in `tests/run` or `tests/00-harness.sh`.
3. Before merge: one `pull_request` run and one `gh workflow run ci --ref <branch> -f only=70-docs` (P2R1-20). Note that dispatch leaves the run P2R1-1 describes on the PR head.

## Open questions / risks

- CLEAN rests on the contract's rule, not on an absence of findings. P2R1-5 means the tests would not notice the issue's own hole reopening on the CI path.
- Scratch left behind: `/tmp/claude-1000/-home-alex-blast-off--claude-worktrees-pending-items-53932d/60b15296-819e-491a-8ffe-34b3bd988f86/scratchpad/p2r1.MVQXCF` (my copy and probe dirs).

## References

- Issues: z0rd0n88/blast-off issue 31; next phase issue 26
- Docs: `baton-runner/br-1115-issues/review-phase-2-iter-1.md`, `baton-runner/br-1115-issues/gate-phase-2-iter-1/tests-run.log`, `baton-runner/br-1115-issues/baton-phase-2-work.md`, `baton-runner/br-1115-issues/digest-phase-2.md`
- Code: `tests/run:39-40,46,61-63,85-91`, `tests/00-harness.sh:22-50,108-110`, `tests/40-receipt-required.sh:60-67`, `.github/workflows/ci.yml:12-16,51`, `lib/receipt.sh:8`, `lib/ci.sh:19-41`
