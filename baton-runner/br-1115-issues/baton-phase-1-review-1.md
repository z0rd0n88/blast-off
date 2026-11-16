---
source: runner
scope: br-1115-issues
parent_session: ""
---
# Pass-Baton: phase 1 review 1, issue 30: VERDICT ISSUES (1 HIGH: the CI upload step fails on a red run)

**Date:** 2026-11-15
**Scope:** br-1115-issues
**Branch:** feat/br-1115-issues/phase-1
**Worktree:** /home/alex/blast-off/.claude/worktrees/pending-items-53932d
**HEAD:** 10d228d feat(phase-1): tests/run keeps scenario work dirs under BLAST_OFF_TEST_KEEP (#30)

## Where things stand

**VERDICT: ISSUES.** The gate is green and the `tests/run` half is sound and really tested, but the synthesized review holds 1 HIGH: the new upload step would fail and upload nothing on almost every red CI run. Counts: 0 CRITICAL, 1 HIGH, 6 MEDIUM, 23 LOW from the review, plus 2 LOW of mine. No product code was changed by this unit. No digest was written (CLEAN only). Blocking state: P1R1-1 needs a fix unit.

- Gate: `scripts/gate.sh` exit 0, `GATE: PASS passed=18 failed=0 shellcheck=ok`. Log: `baton-runner/br-1115-issues/gate-phase-1-iter-1/tests-run.log`.
- Review report: `baton-runner/br-1115-issues/review-phase-1-iter-1.md` (reviewed at 10d228d13678c4157cc3c82c1ee9aa7fe971c99a; `Reviewers: 6/6 returned`; ends with a `## Report Audit`). Verbatim reviewer outputs: `baton-runner/br-1115-issues/review-phase-1-iter-1/<reviewer>.json`.
- The multi-agent review ran, with deviations, all listed in the report's `## Notes`: inline from this unit (no orchestrator layer); the six rostered agents (critical-thinking, code-reviewer, penetration-tester, security-reviewer, silent-failure-hunter, tdd-guide) are parked only, so each ran as a `general-purpose` agent reading its parked definition, read-only; `--high-cap off` added because this is a gate; `--yes` is a no-op on a `spec` target.

## Acceptance criteria

| # | Met? | Evidence |
|---|---|---|
| 1 keep when set, remove when unset | yes | Test `tests/00-harness.sh:22-37` (passes in the gate log). My full run with `BLAST_OFF_TEST_KEEP` set, the CI configuration: `GATE: PASS passed=18`, 18 subdirs each with `out` and `cwd/`, 85 `run.log` files on non-hidden paths, 0 sockets or FIFOs, 0 hidden files outside `.git`. |
| 2 ci.yml env + upload under `if: failure()` | on paper only | `.github/workflows/ci.yml:35-37` (step env) and `:43-48` (`actions/upload-artifact@v4`, `if: failure()`, last step). YAML parses; env value and upload `path` are the same string. But see P1R1-1: the step would fail when it runs. `actionlint` is not installed; nothing was pushed. |
| 3 header + spec | yes | `tests/run:7-8`; `docs/spec.md:215`. |
| 4 test proves criterion 1 both ways | yes | Mutants of `tests/run` on a /tmp copy, 00-harness only: baseline PASS; 8 of 10 distinct mutants killed, each at the intended assertion (no `unset`; `rm` instead of `mv`; `cp -r`; keep only on FAIL; no stale clear; unset branch without `rm`; no `mkdir -p`; drop `cwd`). tdd-guide separately reverted `tests/run` to origin/main and the test went red at "keep fixture verdict". Survivors: no absolutisation (P1R1-10), default keep dir when unset (P1R1-13). |

RED evidence in the work baton: criterion 1 set-half and criterion 4 have it (first RED is the isolation assertion; the rest by one-at-a-time reverts, which my mutants reproduce). **No RED evidence:** criterion 2 (workflow config, no test reads `ci.yml`) and criterion 3 (docs). The unset half of criterion 1 was green before the change; only the mutation shows it can fail.

## Findings

### P1R1-1 HIGH: the artifact upload fails and uploads nothing on a red run

- **Where:** `.github/workflows/ci.yml:43-48`, with `tests/run:34` and `tests/22-dirty-tree.sh:123`.
- **Failure path:** `22-dirty-tree.sh:123` creates `test-<pid>-newline/notes\n.txt` and never removes it. With the keep dir set it lands in `<keep>/22-dirty-tree/cwd/`. `actions/upload-artifact` validates every file path before creating the artifact and throws on any of `" : < > | * ? \r \n`, so the step fails with zero files uploaded. `tests/run` keeps going after a failure, so scenario 22 runs on nearly every red gate.
- **Evidence:** raised HIGH by code-reviewer and silent-failure-hunter, MEDIUM by security-reviewer (not run end to end). I confirmed both halves myself: my full keep run holds 861 non-hidden files and exactly 1 rejected path, `22-dirty-tree/cwd/test-651157-newline/notes\n.txt`; the validator's character list (CR and LF included) is in `actions/toolkit` `packages/artifact/src/internal/upload/path-and-artifact-name-validation.ts`. Not run: the action itself. The work baton's name check covered `":<>|*?` and left out CR and LF.
- **Suggested fix:** in an `if: failure()` step, `tar -C "$RUNNER_TEMP" -czf "$RUNNER_TEMP/blast-off-tests.tgz" blast-off-tests`, and upload the tarball. That also fixes P1R1-19 and P1R1-24. Then prove it with one deliberately red CI run (manager's call; needs a push).

### MEDIUM

| ID | File:line | Failure path | Suggested fix |
|---|---|---|---|
| P1R1-2 | `.github/workflows/ci.yml:35-37,43-48` | The CI wiring has never run and no test reads it; the upload step first runs on the day it is needed. | One forced-red run before merge; `if-no-files-found: error`; optionally pin the wiring in `00-harness` like `.gitignore` is pinned there. |
| P1R1-3 | `.github/workflows/ci.yml:45` | New dependency on a mutable tag that declares `using: node20` and is three majors behind; runners already force node20 actions onto Node 24 (annotation on run 43778239611). | Move to a Node 24 major (v6 or v7); pin by SHA if the repo wants that. |
| P1R1-4 | `tests/run:34` (`set -e`, `:10`) | A failed `mv` or `rm` in the keep step (unwritable keep dir, full disk, undeletable stale dir) aborts mid-suite: exit 1, no `GATE:` line, later scenarios unrun, work dir left in `TMPDIR`. | Count it as a named failure and continue: `mv ... \|\| { echo "FAIL keep $name"; failed=$((failed+1)); }`. |
| P1R1-5 | `tests/run:19,34` vs `:42` | A keep dir under `bin/`, `lib/` or `tests/` is linted by the gate's own shellcheck: gate goes red and stays red after the var is unset. I reproduced it (`BLAST_OFF_TEST_KEEP=tests/kept` on a mini suite: `GATE: FAIL ... shellcheck=fail`). | Refuse a keep dir inside `$REPO`, or say so in the header. |
| P1R1-6 | `.github/workflows/ci.yml:14,44`; `tests/run:27,34` | A cancelled or timed-out job uploads nothing, and the scenario in flight is never in the keep dir. Criterion 2 asks for `if: failure()` exactly, so this is a limit of the spec. | `if: failure() \|\| cancelled()`, or a step-level `timeout-minutes` on the gate step; or record the limit. |
| P1R1-7 | `tests/00-harness.sh:33-34` | The re-run assertion is met by run 1's leftovers: `mkdir` without `-p`, "stale kept dir wins" and "merge into the old kept dir" all survive. It also leans on GNU `mktemp`'s `tmp.*` name, looks only at `01-ok`, and nothing asserts exactly one subdir per scenario. | Plant `kept/01-ok/stale` before run 2, assert run 2's verdict line, assert `ls -A kept/01-ok` is `cwd out`. |

### LOW

| ID | File:line | Failure path | Suggested fix |
|---|---|---|---|
| P1R1-8 | `tests/run:18-19`, header `:9` | A keep dir that cannot be made exits 1 with no `GATE:` line. | Print `GATE: FAIL` first, or note it in the header. |
| P1R1-9 | `tests/run:18-19`; `tests/00-harness.sh:25-37` | "Fails before any scenario" is untested (moving `mkdir -p` into the loop passes). | Assert an uncreatable keep dir exits non-zero with no scenario line. |
| P1R1-10 | `tests/run:19` | `KEEP="$(cd "$KEEP" && pwd)"` does nothing (the main shell never changes dir); its mutant survives. | Reduce to `mkdir -p "$KEEP"`, or keep it and test it. |
| P1R1-11 | `tests/00-harness.sh:26` | The fixture cannot tell unset from empty (`export BLAST_OFF_TEST_KEEP=` survives). | Test `${BLAST_OFF_TEST_KEEP+x}`. |
| P1R1-12 | `tests/00-harness.sh:36-37` | The unset run asserts only a non-zero exit, not the verdict. | Repeat the line 29 `grep` after line 36. |
| P1R1-13 | `tests/00-harness.sh:36-37` | The unset half only looks at `TMPDIR`; a default keep dir when unset survives. | Snapshot the cwd before the unset run and assert nothing new but `keepfix.out`. |
| P1R1-14 | `tests/00-harness.sh:28-37` | Untested: timed-out scenario kept, absolute keep path (what CI uses), keep dir on another filesystem. | Add an absolute-path case at least. |
| P1R1-15 | `tests/run:19` | `cd "$KEEP" && pwd` breaks under an exported `CDPATH` and for the value `-`; `mkdir`/`cd` lack `--`. | Drop the normalisation; `mkdir -p -- "$KEEP"`. |
| P1R1-16 | `tests/run:34` | `rm -rf "$KEEP/$name"` silently deletes a pre-existing dir of that name. | Document that `<dir>/<name>` is replaced. |
| P1R1-17 | `tests/run:34` | Stale dirs of scenarios not in this run stay in a reused keep dir. | Say so in the header, or clear `$KEEP/[0-9][0-9]-*` at start. |
| P1R1-18 | `tests/run:19,34` | `mv` without `-T` trusts the keep dir's contents (race, shared dirs only). | `mv -T`, or create the work dir in place. |
| P1R1-19 | `.github/workflows/ci.yml:36,45-48` | Hidden files (every `.git`) are dropped; the comment says "every scenario's work dir". | The tarball fix; otherwise reword. |
| P1R1-20 | `.github/workflows/ci.yml:45-48` | Retention left at the repo default (90 days). | `retention-days: 7` or similar. |
| P1R1-21 | `.github/workflows/ci.yml:36,44` | The step fires on any earlier failed step and only warns when there is nothing to upload. | Reword the comment; `if-no-files-found`. |
| P1R1-22 | `.github/workflows/ci.yml:47` | Fixed artifact name with `overwrite: false`; a re-run collision is unverified. | `name: blast-off-tests-${{ github.run_attempt }}`. |
| P1R1-23 | `.github/workflows/ci.yml:37,48` | The keep path is written twice and can drift. | Set it once and reference it. |
| P1R1-24 | `.github/workflows/ci.yml:45-48` | The upload follows symlinks. | The tarball keeps links as links. |
| P1R1-25 | `.github/workflows/ci.yml:43-48`; `lib/chain.sh:21` | The user journal is not captured (outside issue 30). | `journalctl --user --no-pager` into the keep dir on failure. |
| P1R1-26 | `tests/run:8,21`; `docs/spec.md:215` | "Scenarios never see it" covers the inherited env only, not `/proc`. | None needed. |
| P1R1-27 | `baton-runner/br-1115-issues/{STATE.md,baton-phase-1-work.md,log.md}` | The commit introduces runner bookkeeping into history. | Manager decides. |
| P1R1-28 | `.github/workflows/ci.yml:21-22` | Pre-existing: shellcheck downloaded without a checksum. | Verify a SHA-256. |
| P1R1-29 | `.github/workflows/ci.yml:16` | Pre-existing: checkout keeps its token while PR code runs. | `persist-credentials: false`. |
| P1R1-30 | `tests/run:38-54` | Pre-existing: the shellcheck verdict depends on the caller's cwd. | `cd "$REPO"` around the call, separate change. |
| P1R1-31 (mine) | `baton-runner/br-1115-issues/baton-phase-1-work.md` | The work baton says "No new dependency" (there is one), gives HEAD d5172eb "uncommitted" (the work is commit 10d228d), and its file-name check missed CR and LF. | Correct in the fix unit's baton. |
| P1R1-32 (mine) | `baton-runner/br-1115-issues/review-phase-1-iter-1.md:188-193` | Report audit, advisory, about the report only: one coverage line overstates ("killed in every set"), one attribution error, two fixes credited to reviewers who did not propose them, and one tdd-guide point lost (restored in P1R1-7 above). | Read the audit before quoting the report. |

## New dependencies

- `actions/upload-artifact@v4` (`.github/workflows/ci.yml:45`): tag-pinned, not SHA-pinned, same style as `actions/checkout@v4`. `v4` resolves today to v4.6.2, commit `ea165f8d65b6e75b540449e92b4886f43607fa02` (2025-03-19), `using: node20`. Latest release is v7.0.2 (2026-10-07), checked with `gh api`.
- Nothing else: `tests/run` uses only `mkdir`, `mv`, `rm`.

## Next steps

1. Fix unit: P1R1-1 in `.github/workflows/ci.yml` (tar, then upload), then at least P1R1-4, P1R1-5 and P1R1-7 (`tests/run:19,34`, `tests/00-harness.sh:33-37`); re-run `scripts/gate.sh baton-runner/br-1115-issues/gate-phase-1-iter-2/`.
2. Manager: decide on one forced-red CI run to prove the upload (P1R1-2), and on the action version (P1R1-3). The report lists 18 open questions for the author, all PENDING.
3. Phase 2 (issue 31) should wait for this fix: it edits the same `ci.yml` and `tests/run`. `tests/00-harness.sh:13,16,29` pin the verdict line by exact match.

## Open questions / risks

- Three reviewers were denied (permission classifier) when they tried to run the downloaded upload-artifact bundle locally, and two wrote out the command for someone else to run. I did not run it. P1R1-1 rests on the action's source plus a real kept tree.
- penetration-tester reports that its probe `BLAST_OFF_TEST_KEEP=-` made `cd -` resolve to the worktree path; I checked afterwards: `git status` shows no tracked change and only `baton-runner/` files untracked, the worktree root holds no stray entry (`ls -A`), and there is no empty directory down to depth 3.
- critical-thinking's 14 items carry no severity and are not in the tables above; they are in the report's "Unstated Assumptions and Open Questions" section. The one with no twin among the findings: the upload fires only on a red job, but issue 30's own evidence describes a diagnostic run where the target test passed (10 of the 14 runs in that session were green), so this change may not cover the case that prompted it.
- Scratch dirs left under `/tmp` by reviewers: `/tmp/sfh.QSbR9m`, `/tmp/bo-secrev.0MPqJG`, `/tmp/bo-pt.zDzQRh`, `/tmp/bo-review.1mjuqk`, possibly `/tmp/tmp.lVl8pVVKXv`.
- Unverified by anyone: `failure()` on job timeout, artifact-name collision on a re-run, v4 on forced Node 24, whether `/tmp` and `RUNNER_TEMP` share a filesystem on the runner.

## References

- Issues: z0rd0n88/blast-off #30 (no open PR for this branch)
- Gate log: `baton-runner/br-1115-issues/gate-phase-1-iter-1/tests-run.log`
- Review report: `baton-runner/br-1115-issues/review-phase-1-iter-1.md`
- Work baton: `baton-runner/br-1115-issues/baton-phase-1-work.md`
- Code: `tests/run:17-21,34`, `tests/00-harness.sh:22-37`, `.github/workflows/ci.yml:34-48`, `docs/spec.md:215`, `tests/22-dirty-tree.sh:123`
