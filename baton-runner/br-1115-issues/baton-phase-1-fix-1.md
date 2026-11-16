---
source: runner
scope: br-1115-issues
parent_session: ""
---
# Pass-Baton: phase 1 fix 1, issue 30: the HIGH and all 6 MEDIUM adjudicated SUPPORTED and fixed locally; the CI steps still need one red run

**Date:** 2026-11-15
**Scope:** br-1115-issues
**Branch:** feat/br-1115-issues/phase-1
**Worktree:** /home/alex/blast-off/.claude/worktrees/pending-items-53932d
**HEAD:** 1e3d34d chore(phase-1): review iter 1 record (verdict ISSUES) (the fix is uncommitted; the manager owns git)

## Where things stand

The fix is complete locally and the full gate is green both ways, run after the last edit to any tracked file:
- var unset: `GATE: PASS passed=18 failed=0 shellcheck=ok` (`fix-phase-1-iter-1/tests-run.log`).
- `BLAST_OFF_TEST_KEEP=<scratch>/rt/blast-off-tests`, as CI sets it: `GATE: PASS passed=18 failed=0 shellcheck=ok` (`tests-run-keep.log`).
- The tar line, taken from `ci.yml` with `sed` and run with `RUNNER_TEMP=<scratch>/rt` on that real kept tree (`tar-proof.log`): 18 scenario dirs, 1445 files, 8.4M; 3 file names `upload-artifact` would refuse (`22-dirty-tree/cwd/test-826085-newline/notes\n.txt`, and this fix's own fixture under `00-harness/cwd/rt/` and its untarred copy under `00-harness/cwd/back/`); 578 files under dot dirs, 4 symlinks, no socket or FIFO. `tar exit=0`, one file `blast-off-tests.tgz` of 311979 bytes; untarred, `diff -r --no-dereference` against the kept tree exits 0 with no output, and the copy has 1445 files, 4 symlinks, 3 newline-named. One line of that log is a `grep: Unmatched [` error from the proof script's own check of the tar file's name (a bad pattern of mine, not a result); the name is the fixed `blast-off-tests.tgz`.

`shellcheck -S warning` is clean on both scripts and `ci.yml` parses.

All 32 findings have a disposition: 7 fixed (1 HIGH, 6 MEDIUM, two of them only as far as a local change can go), 12 LOW fixed, part fixed or changed, 13 LOW open, out of scope or needing no change. Blocking state: nothing blocks the next review unit; P1R1-1, -2, -3 and -6 touch workflow steps that only a pushed, deliberately red CI run can prove.

Files changed (tracked, uncommitted):
- `.github/workflows/ci.yml`: step timeout on the gate step; new `if: failure()` tar step; the upload step now takes the `.tgz`, is `actions/upload-artifact@v7`, and has `if-no-files-found: error`; comments.
- `tests/run`: keep dir checked before any scenario (refused under `bin/`, `lib/`, `tests/`; uncreatable), both with a `GATE: FAIL` line; a failed keep is `FAIL keep <name>` and the loop goes on; header.
- `tests/00-harness.sh`: keep block tightened; new blocks for an unkeepable work dir, an uncreatable keep dir, a keep dir under `tests/`, and the `ci.yml` tar line.
- `docs/spec.md:215`: the `00-harness` row names the new behaviour.

Untracked: this file and `baton-runner/br-1115-issues/fix-phase-1-iter-1/` (run logs).

## Adjudication: HIGH and MEDIUM

| ID | Verdict | Checked against | Disposition |
|---|---|---|---|
| P1R1-1 HIGH | SUPPORTED | `tests/22-dirty-tree.sh:123` writes `notes\n.txt` and nothing removes it; `actions/toolkit` `path-and-artifact-name-validation.ts` (read with `gh api`) lists `" : < > \| * ? \r \n` for file paths | **Fixed.** The tree is no longer uploaded. An `if: failure()` step runs `tar -C "$RUNNER_TEMP" -czf "$RUNNER_TEMP/blast-off-tests.tgz" blast-off-tests`; the upload step's `path` is that one file, whose name is fixed. No scenario is special-cased. |
| P1R1-2 MEDIUM | SUPPORTED | `grep -rl 'ci\.yml' tests/` was empty at HEAD | **Fixed as far as a local change can.** `00-harness` now reads `ci.yml`: the keep env literal, the upload path literal, two `if: failure()` steps, and it runs the tar line itself. `if-no-files-found: error`. The forced-red run is the manager's (needs a push). |
| P1R1-3 MEDIUM | SUPPORTED | `gh api`: `action.yml` at `v4` says `using: node20`, at `v6` and `v7` `node24`; inputs `name`, `path`, `if-no-files-found` are unchanged; v5, v6, v7 release notes list no break for them (v7 adds `archive`, moves to ESM) | **Fixed, unproven until it runs.** `@v7`, tag-pinned like `actions/checkout@v4`. |
| P1R1-4 MEDIUM | SUPPORTED | reproduced: RED 2 below (`PASS 01-ok`, then `mv: ...`, no `GATE:` line) | **Fixed.** `tests/run:42-47`: `FAIL keep <name>`, one more failure, the work dir is removed, the loop goes on. |
| P1R1-5 MEDIUM | SUPPORTED | reproduced by mutant: with the refusal removed the fixture ends `GATE: FAIL passed=1 failed=1 shellcheck=fail` | **Fixed.** `tests/run:22-30` refuses a keep dir under the three linted dirs, before making it. Not the whole repo: gate logs already live in the repo under `baton-runner/`, and a kept tree there harms nothing. |
| P1R1-6 MEDIUM | SUPPORTED, a limit of criterion 2 | `ci.yml` had only the job's `timeout-minutes: 30`; `tests/run` moves a work dir after its scenario ends | **Partly fixed, unproven until it runs.** `timeout-minutes: 25` on the gate step, so a hung gate is a failed step and `failure()` holds. Left as recorded limits in the `ci.yml` comments: a job timeout or a cancel uploads nothing, and the scenario in flight is not kept. See Deferred. |
| P1R1-7 MEDIUM | SUPPORTED | mutants of the HEAD `tests/run` under the old test survive per the review; under the new test all are killed (RED 1) | **Fixed.** `tests/00-harness.sh:34-39`: a planted `kept/01-ok/stale`, the second run's verdict, `kept/01-ok` is exactly `cwd out`, `kept` is exactly `01-ok 02-bad`. No more `tmp.*` name check. |

## RED evidence

Every run is `BLAST_OFF_NO_SHELLCHECK=1 tests/run <dir holding a symlink to 00-harness.sh>`. Tests were written first, one block at a time; each run below is the first failure of the block just added, so the blocks before it were green.

RED 1, P1R1-7 and P1R1-11 (test-only changes, so shown by mutants of the HEAD `tests/run` in a scratch copy of the repo):

```
--- merge into the old kept dir          killed: GATE: FAIL passed=0 failed=1 (failing line cut by `tail`)
--- stale kept dir wins                  killed: GATE: FAIL passed=0 failed=1 (failing line cut by `tail`)
--- no stale clear                       killed: GATE: FAIL passed=0 failed=1 (failing line cut by `tail`; the listing tail shows kept/02-bad/tmp.CQ0WDXyQ9c/cwd)
--- mkdir without -p                     FAIL: keep fixture's second run verdict: mkdir: cannot create directory '.../kept': File exists
--- empty instead of unset (P1R1-11)     FAIL: keep fixture verdict: FAIL 01-ok / FAIL 02-bad / GATE: FAIL passed=0 failed=2
```

For the first three the output was piped through `tail -n 6` and the `FAIL:` line itself was not captured. What was captured is the end of an `ls -RA kept` listing, which only the "second run did not replace the kept dirs" assertion prints, so that assertion is inferred, not read.

RED 2, P1R1-4 (HEAD `tests/run`, new test):

```
FAIL 00-harness
  | FAIL: unkeepable work dirs not named: PASS 01-ok
  | mv: cannot stat '/tmp/tmp.iCqA9DwPL5/cwd/kept2/01-ok': Not a directory
GATE: FAIL passed=0 failed=1 shellcheck=skipped
```

After the fix, two mutants of it are killed: a failed keep that is not counted gives `FAIL: unkeepable work dirs exited 0`; leaving the work dir behind gives `FAIL: unkeepable work dirs left in TMPDIR: tmp.MLbY4s6VGy`.

RED 3, P1R1-8 and P1R1-9 (P1R1-4 fixed, keep-dir check unchanged):

```
FAIL 00-harness
  | FAIL: uncreatable keep dir: mkdir: cannot create directory 'ok.out': Not a directory
GATE: FAIL passed=0 failed=1 shellcheck=skipped
```

RED 4, P1R1-5 and P1R1-10. The refusal went in with the same edit as RED 3's fix, so its red is by mutant of the fixed `tests/run`, not test-first:

```
--- no linted-dir refusal                FAIL: keep dir under tests/ not refused: ... FAIL shellcheck / GATE: FAIL passed=1 failed=1 shellcheck=fail / kept
--- refusal without absolutising         same output (a relative tests/kept is not recognised)
--- mkdir before the refusal             FAIL: keep dir under tests/ not refused: (right two lines, but self/tests/kept exists)
```

RED 5, P1R1-1 and P1R1-2 (`ci.yml` unchanged, new test):

```
FAIL 00-harness
  | FAIL: ci.yml does not upload runner.temp/blast-off-tests.tgz
GATE: FAIL passed=0 failed=1 shellcheck=skipped
```

GREEN after all five: `PASS 00-harness` / `GATE: PASS passed=1 failed=0 shellcheck=skipped`.

## What no local test can exercise

`actions/upload-artifact@v7` itself, `if: failure()`, `if-no-files-found: error`, and the step `timeout-minutes`. For these: the YAML parses (`python3` + PyYAML; the last three steps print as intended), and the reasoning is from documented behaviour only.
- The upload now gets one file with a fixed, valid name, so the path validator has nothing to refuse.
- `$RUNNER_TEMP` (tar step) and `${{ runner.temp }}` (env, upload path) are the same directory per the Actions docs.
- GNU tar exits non-zero for an unreadable file but still writes the archive with the rest (run here on a fixture with a mode 000 file and a FIFO: `tar exit=2`, the other entries listed); the upload step is its own bare `if: failure()`, so it runs whatever the tar step's result. A socket in the tree was not tried (none is left by any scenario).
- A step that hits its `timeout-minutes` fails, and `failure()` is then true for later steps; a job timeout cancels. This reading is not observed here. The review lists it as unverified too.

## LOW findings

| ID | Disposition |
|---|---|
| P1R1-8 | Fixed: a keep dir that cannot be made prints `GATE: FAIL passed=0 failed=1 shellcheck=skipped`. RED 3. |
| P1R1-9 | Fixed: the test requires the output to be exactly the `FAIL BLAST_OFF_TEST_KEEP=...` line and the verdict, so no scenario line. RED 3. |
| P1R1-10 | Fixed: absolutising (`realpath -m`) now feeds the refusal and its mutant is killed. RED 4. |
| P1R1-11 | Fixed: fixture tests `${BLAST_OFF_TEST_KEEP+x}`. RED 1. |
| P1R1-12 | Fixed: the unset run's verdict line is asserted. No mutant shown for it. |
| P1R1-14 | Part fixed: the second keep run names the dir by absolute path. Open: timed-out scenario, other filesystem (needs a mount; reviewers checked both by hand). |
| P1R1-15 | Changed incidentally, not in the suite: `realpath -m --` and `mkdir -p --` replace `cd`. By hand: `CDPATH=/tmp BLAST_OFF_TEST_KEEP=-` and `=-k` both end `GATE: PASS` and keep into dirs named `-` and `-k`. |
| P1R1-16 | Part fixed: the header says a `<dir>/<name>` already there is replaced (the stale-file assertion covers the behaviour). "Must be a dedicated dir" is not stated. |
| P1R1-19 | Fixed by the tar file: the test round-trips `.git/HEAD`. |
| P1R1-21 | Changed, workflow-only: comment reworded, `if-no-files-found: error`. |
| P1R1-23 | Fixed by test, not by one definition (`runner` is not available to job-level `env`): the harness pins both literals and runs the tar line between them. |
| P1R1-24 | Fixed by the tar file: the test round-trips a dangling symlink as a link. |
| P1R1-13 | Open: no default keep dir exists in the code, so the test would be guessing where a mutant writes. |
| P1R1-17 | Open: stale dirs of scenarios not in this run stay. CI's `runner.temp` is fresh; clearing `<dir>` at start would delete more than the header promises. |
| P1R1-18 | Open: `mv -T`. Race in a shared keep dir only, no test can hit it; a failing `mv` is now a named failure. |
| P1R1-20 | Open: retention is a policy choice for the manager. |
| P1R1-22 | Open: a re-run colliding on the artifact name is unverified and needs a real re-run. |
| P1R1-25 | Out of scope: issue 30 does not name the journal. |
| P1R1-26 | No change, as the review says. |
| P1R1-27 | Manager's: git history. |
| P1R1-28, -29, -30 | Out of scope: pre-existing, not in issue 30's diff. |
| P1R1-31 | Corrected here: the phase added a dependency (see below); the work is commit 10d228d; the work baton's file-name check missed CR and LF. |
| P1R1-32 | No code change: advisory about the report. The audit was read before the report was used. |

## Dependencies (declared)

- `actions/upload-artifact`: `@v4` becomes `@v7`. Tag `v7` is commit `cf430e030ddbb5b0abf93d22962f4752f3646cd9` today (latest release v7.0.2, 2026-10-07), `using: node24`. Not SHA-pinned, matching `actions/checkout@v4`.
- `tar` (GNU): in the new CI step (the Dependencies step already uses it) and now in `tests/00-harness.sh`, with `diff -r --no-dereference` (diffutils 3.3 or later).
- `realpath -m` (GNU coreutils 8.15 or later) in `tests/run`; `timeout` and `mktemp` from the same package were already used.
- Nothing installed; all three ship with `ubuntu-24.04`.

## Deferred, on purpose

- One deliberately red CI run. It is the only proof for the tar step on a runner, v7, the step timeout, and `if-no-files-found`. Needs a push.
- `if: failure() || cancelled()`: criterion 2 of issue 30 says `if: failure()`. A cancelled run uploads nothing.
- Making each work dir inside the keep dir, which would keep the scenario in flight: it changes where scenarios run when the var is set (inside a git repo if the keep dir is in one; 22-dirty-tree has a "workdir outside git" case), so a kept run would no longer be the same run.
- v7's `archive: false` (upload the `.tgz` unzipped): left at the default so `name` still applies. The download is `blast-off-tests.zip` holding `blast-off-tests.tgz`.
- SHA-pinning both actions, and `actions/checkout@v4` being `node20`: pre-existing style, manager's call.

## Next steps

1. Review unit: `git diff` in the worktree (4 tracked files), then `scripts/gate.sh baton-runner/br-1115-issues/gate-phase-1-iter-2/`.
2. Manager: commit the 4 files; push and force one red run (for example a throwaway commit adding `tests/99-red.sh` with `exit 1`), then check that the artifact `blast-off-tests` holds `blast-off-tests.tgz` with `99-red/out` and `22-dirty-tree/cwd/`.

## Open questions / risks

- The tarball publishes what the directory upload dropped: every scenario repo's `.git` and other dot files. On the real kept tree, a scan for token-shaped strings (`ghp_`-style, `github_pat_`, `sk-`, `AKIA`, `xox?-`, private key headers) matched 0 files. The check for the values of this box's own secrets ran on nothing: none of those variables is set in the shell the run used. The artifact is 578 files larger in content than what the old step would have sent, and readable by anyone with repo read access for the retention period (P1R1-20, open).
- `tests/00-harness.sh` finds the tar step by the pattern `run: tar ...` on one line. A multi-line rewrite of that step fails the test with "ci.yml has no one-line 'run: tar ...' step"; the `ci.yml` comment says so.

## References

- Issues: z0rd0n88/blast-off #30 (no open PR for this branch)
- Review baton: `baton-runner/br-1115-issues/baton-phase-1-review-1.md`; report: `baton-runner/br-1115-issues/review-phase-1-iter-1.md`
- Run logs: `baton-runner/br-1115-issues/fix-phase-1-iter-1/{tests-run.log,tests-run-keep.log,tar-proof.log}`
- Code: `tests/run:7-11,19-30,42-47`, `tests/00-harness.sh:22-57,65-87`, `.github/workflows/ci.yml:4-5,35-61`, `docs/spec.md:215`
