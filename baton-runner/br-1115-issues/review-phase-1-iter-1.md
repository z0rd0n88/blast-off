# Multi-Agent Review: spec set: .github/workflows/ci.yml + docs/spec.md + tests/00-harness.sh + tests/run

## Executive Summary

Six reviewers (critical-thinking, code-reviewer, penetration-tester, security-reviewer, silent-failure-hunter, tdd-guide) reviewed commit 10d228d, the issue 30 change that makes `tests/run` keep scenario work dirs under `BLAST_OFF_TEST_KEEP` and uploads them from CI on failure. The `tests/run` half works and its test is real (every reviewer measured it), but the CI half has never executed and one HIGH finding says it will fail when first needed: scenario `22-dirty-tree` leaves a file with a line feed in its name, which `actions/upload-artifact@v4` rejects before uploading anything. Totals after dedupe: 0 CRITICAL, 1 HIGH, 6 MEDIUM, 23 LOW; these are raw, unchallenged reviewer findings, since refutation did not run. Recommended action: **block** until the HIGH is fixed and one deliberately red CI run shows the artifact arriving; 18 open questions are PENDING.

## Critical Findings

None.

## High Findings

### H1. The artifact upload fails and uploads nothing on nearly every red run: a newline-named file is in the kept tree

- **Location:** `.github/workflows/ci.yml:43-48` (upload step), with `tests/run:34` (keeps every scenario dir) and `tests/22-dirty-tree.sh:123` (creates `test-<pid>-newline/notes\n.txt`, never removed).
- **Description:** With `BLAST_OFF_TEST_KEEP` set, the newline-named file lands under `22-dirty-tree/cwd/`. `actions/upload-artifact@v4` (v4.6.2, commit `ea165f8d65b6e75b540449e92b4886f43607fa02`) validates every file path and throws on `" : < > | * ? \r \n` before it creates the artifact, so the step fails and zero files are uploaded. `tests/run` continues after a failing scenario, so scenario 22 runs in every red gate except when 22 itself fails before line 123 or the suite aborts earlier. The harness test never exercises the upload, so the gate cannot catch this.
- **Evidence per reviewer:**
  - silent-failure-hunter, **HIGH**: ran the real `22-dirty-tree.sh` as a fixture with the keep dir set (98 non-hidden files kept), then ran the action's `validateFilePath` copied verbatim from `dist/upload/index.js` over them: `files checked=98 rejected=1`. Read, not run: validation precedes `CreateArtifact`, and the top-level handler calls `core.setFailed`.
  - code-reviewer, **HIGH**: a fixture copying line 123 through HEAD's `tests/run` left the file; a transcription of the validator gave `files checked=3 rejected=1` (`dist/upload/index.js:3356-3407`, called at `:3684`).
  - security-reviewer, **MEDIUM**: same cause and same source lines, kept tree confirmed with `od -c`; rated MEDIUM because the rejection is read from source and not executed, and states it "should be treated as HIGH once one red CI run confirms it".
  - penetration-tester and tdd-guide did not raise it; tdd-guide lists "which filename characters `upload-artifact` rejects" as inconclusive.
- **Not reproduced by anyone:** the real action end to end. Three reviewers report the permission classifier denied running the downloaded bundle locally.
- **Suggested fix:** in an `if: failure()` step, tar the keep dir (`tar -C "$RUNNER_TEMP" -czf "$RUNNER_TEMP/blast-off-tests.tgz" blast-off-tests`) and upload the tarball; that is immune to any file name and also keeps hidden files, modes and symlinks. Deleting the file at the end of scenario 22 fixes today's case only (a 22 that fails after line 123 exits before cleanup). Prove the step with one forced-red CI run before merge.
- **Attribution:** code-reviewer, silent-failure-hunter (HIGH); security-reviewer (MEDIUM).

## Medium and Low Findings

| Severity | Title | Location | Reviewer(s) | One-line description |
|---|---|---|---|---|
| MEDIUM | The CI wiring has never executed and no test reads it | `.github/workflows/ci.yml:35-37,43-48`; no reader in `tests/` | penetration-tester (MEDIUM), security-reviewer (MEDIUM), tdd-guide (MEDIUM) | Branch is unpushed, the last runs were all green, and the upload step runs only on a red job, so its first run is the day it is needed; any edit to these lines passes the gate. Fix: one deliberately red run before merge; pin the wiring in `00-harness` (env set, `path:` equal, `if: failure()`); `if-no-files-found: error`. |
| MEDIUM | New dependency `actions/upload-artifact@v4`: mutable major tag, `using: node20`, three majors behind v7.0.2 | `.github/workflows/ci.yml:45` | code-reviewer (MEDIUM), tdd-guide (MEDIUM), security-reviewer (MEDIUM for the runtime, LOW for the tag), penetration-tester (LOW for the tag; runtime inside its MEDIUM), silent-failure-hunter (LOW) | Tag resolves today to v4.6.2 `ea165f8d…`; CI run 43778239611 already shows `actions/checkout@v4` forced from Node 20 onto Node 24, and v4 on Node 24 is unverified. Fix: move to a node24 major (v6 or v7), pin by commit SHA if the repo wants immutability, confirm with the red run. |
| MEDIUM | A failed `mv` or `rm` in the keep step aborts the gate mid-suite with no `GATE:` line | `tests/run:34` (under `set -e`, `:10`); comment `:18-19`; header `:9` | silent-failure-hunter (MEDIUM), security-reviewer (MEDIUM), code-reviewer (LOW), penetration-tester (LOW), tdd-guide (LOW) | Measured: unwritable keep dir prints `PASS 01-…`, then `mv: … Permission denied`, exit 1, no verdict, later scenarios unrun, work dir left in `TMPDIR`; a stale kept dir that cannot be removed does the same on the second run. Fix: count it and continue (`mv … || { echo "FAIL keep $name"; failed=$((failed+1)); }`), or probe writability up front. |
| MEDIUM | A keep dir under `bin/`, `lib/` or `tests/` turns the gate red through its own shellcheck, and it stays red after the var is unset | `tests/run:19,34` against `tests/run:42`; header `tests/run:7-8` | silent-failure-hunter (MEDIUM), penetration-tester (MEDIUM), security-reviewer (LOW), code-reviewer (LOW), tdd-guide (LOW) | Measured on mini repos: `BLAST_OFF_TEST_KEEP=tests/kept` gives `GATE: FAIL … shellcheck=fail` (SC2034/SC2148 on kept fixtures); `00-harness` leaves such files by design; `scripts/gate.sh` `cd`s to the repo root so a relative value lands in the repo. Fix: refuse a keep dir inside `$REPO` (or those three dirs) at line 19, or say so in the header. |
| MEDIUM | A cancelled or timed-out job uploads nothing, and the in-flight scenario's dir is never under the keep dir | `.github/workflows/ci.yml:14,44`; `tests/run:27,34` | code-reviewer (MEDIUM), penetration-tester (LOW), security-reviewer (LOW), silent-failure-hunter (LOW), tdd-guide (LOW) | Work dirs move only after a scenario ends; `timeout-minutes: 30` is reached by about six hung scenarios; a single scenario timeout is handled (measured). Fix: `if: failure() \|\| cancelled()` (or `!success()`), or a step-level `timeout-minutes`; or create the work dir directly as `$KEEP/$name`. Criterion 2 mandates `if: failure()`, so this is a limit of the criterion. |
| MEDIUM | The re-run assertion is satisfied by the first run's leftovers; re-run mutants survive | `tests/00-harness.sh:33-34` | tdd-guide (MEDIUM), silent-failure-hunter (LOW) | Line 33 ignores the second run's verdict (`\|\| true`) and line 34 checks only what run 1 already made true; survivors: `mkdir` without `-p`, "stale kept dir wins", merge into the old kept dir. Fix: plant `kept/01-ok/stale` before the second run, assert its verdict line, assert `ls -A kept/01-ok` is exactly `cwd out`. |
| LOW | A keep dir that cannot be made exits 1 with no `GATE:` line | `tests/run:18-19`; header `tests/run:2-3,9` | penetration-tester, silent-failure-hunter, tdd-guide, code-reviewer (inside its keep-dir finding) | Intended early failure, but the header says exit 1 means `GATE: FAIL …`. Fix: print `GATE: FAIL` before exiting, or note the exception in the header. |
| LOW | The "fails before any scenario" promise is untested | `tests/run:18-19`; `tests/00-harness.sh:25-37` | penetration-tester, tdd-guide | Moving `mkdir -p` into the loop leaves the test passing. Fix: one assertion that an uncreatable keep dir exits non-zero with no scenario line. |
| LOW | Absolutising `KEEP` does nothing and no test distinguishes it | `tests/run:19` | code-reviewer, penetration-tester, silent-failure-hunter, tdd-guide | The main shell never changes directory; the mutant without `cd … && pwd` passes. Fix: reduce to `mkdir -p "$KEEP"`, or keep it and cover it. |
| LOW | The fixture cannot tell an unset var from an empty one | `tests/00-harness.sh:26` | penetration-tester | Replacing `unset BLAST_OFF_TEST_KEEP` with `export BLAST_OFF_TEST_KEEP=` survives. Fix: test `${BLAST_OFF_TEST_KEEP+x}`. |
| LOW | The unset half asserts only the exit code, not the verdict | `tests/00-harness.sh:36-37` | code-reviewer, silent-failure-hunter | A run that crashed before any scenario would satisfy lines 36-37. Fix: repeat the line 29 verdict `grep` after line 36. |
| LOW | The unset half only looks at `TMPDIR` | `tests/00-harness.sh:36-37` | tdd-guide | A mutant that keeps to a default dir when the var is unset passes; the test proves "not left in TMPDIR", not "removed". Fix: snapshot the cwd's entries before the unset run and assert nothing new except `keepfix.out`. |
| LOW | Cases the test does not cover | `tests/00-harness.sh:28-37` | silent-failure-hunter, penetration-tester | Not tested: a timed-out scenario's dir is kept, an absolute keep path (what CI uses), a keep dir on another filesystem; all work by hand. Fix: add an absolute-path case at least. |
| LOW | `cd "$KEEP" && pwd` breaks under an exported `CDPATH` and for the value `-`; `mkdir`/`cd` lack `--` | `tests/run:19` | penetration-tester, security-reviewer | `KEEP` becomes two lines, `mv` fails after scenario 1, exit 1, no verdict; `-k` is read as an option. Fix: drop the normalisation and use `mkdir -p -- "$KEEP"` (or `cd --`/`cd -P`). |
| LOW | `rm -rf "$KEEP/$name"` deletes a pre-existing dir of that name without a message | `tests/run:34` | penetration-tester, security-reviewer, silent-failure-hunter | Measured: a user file under `<keep>/01-ok/` was deleted silently; a symlinked `KEEP` is followed. Fix: document that `<dir>/<name>` is replaced and the dir must be dedicated; optionally require a marker file. |
| LOW | Stale dirs of scenarios not in this run stay in a reused keep dir | `tests/run:34` | code-reviewer, penetration-tester, silent-failure-hunter, tdd-guide | Old and new evidence mix locally; concurrent runs sharing a keep dir clobber each other; CI's fresh `runner.temp` is unaffected. Fix: say so in the header, or clear `$KEEP/[0-9][0-9]-*` at start. |
| LOW | `mv` without `-T` trusts the keep dir's contents | `tests/run:19,34` | penetration-tester | A symlink planted at `$KEEP/$name` between `rm` and `mv` would redirect the work dir (race not reproduced; shared world-writable locations only). Fix: `mv -T`, or make the work dir in place. |
| LOW | Hidden files are dropped from the artifact; the comment says "every scenario's work dir" | `.github/workflows/ci.yml:36,45-48` (top comment `:1-4`) | code-reviewer, penetration-tester, security-reviewer, silent-failure-hunter | `include-hidden-files` defaults to `false`, so every scenario repo's `.git` is excluded (2.6M to 516K for 22); the file's top comment does not mention the artifact. Fix: the tarball covers it; otherwise `include-hidden-files: true` or reword. |
| LOW | Artifact retention left at the default | `.github/workflows/ci.yml:45-48` | code-reviewer, penetration-tester, security-reviewer | Repo retention is 90 days; all 18 scenario dirs are uploaded on any red run. Fix: `retention-days: 7` or similar. |
| LOW | The upload step fires on any earlier failed step and only warns when there is nothing to upload | `.github/workflows/ci.yml:36,44` | code-reviewer, tdd-guide, silent-failure-hunter, security-reviewer | A failed dependency or systemd step gives a "no files found" warning; the comment says "when the gate is red"; `if-no-files-found` is `warn`. Fix: reword the comment; `if-no-files-found: error` (tdd-guide) or `ignore` (code-reviewer). |
| LOW | Fixed artifact name with `overwrite: false` | `.github/workflows/ci.yml:47` | code-reviewer, penetration-tester | v4 fails when an artifact of that name exists; whether a re-run attempt collides is unverified. Fix: `name: blast-off-tests-${{ github.run_attempt }}`. |
| LOW | The keep path is written twice and can drift | `.github/workflows/ci.yml:37,48` | silent-failure-hunter, tdd-guide (inside its criterion 2 finding) | If the two literals drift the upload finds nothing and only warns. Fix: set the path once and reference it. |
| LOW | The upload follows symlinks | `.github/workflows/ci.yml:45-48` | security-reviewer | The action's glob default is `followSymbolicLinks: true`; today's two links point into the repo, a future link to `$HOME` would upload its target. Fix: the tarball keeps links as links. |
| LOW | The user journal is not captured | `.github/workflows/ci.yml:43-48`; `lib/chain.sh:21` | silent-failure-hunter, tdd-guide | Scenarios 11, 12 and 31 start units whose early stderr goes only to the journal. Fix: on failure, `journalctl --user --no-pager` into the keep dir before the upload (outside issue 30's wording). |
| LOW | "scenarios never see it" holds for the inherited environment only | `tests/run:8,21`; `docs/spec.md:215` | penetration-tester | The value is still in `/proc/<pid>/environ` of the `tests/run` ancestor; fine for the stated purpose, not an isolation boundary. Fix: none needed. |
| LOW | The commit carries three baton-runner bookkeeping files | `baton-runner/br-1115-issues/STATE.md`, `baton-phase-1-work.md`, `log.md` | code-reviewer | `origin/main` tracks nothing under `baton-runner/`; this commit introduces it. Fix: decide whether runner bookkeeping belongs in history. |
| LOW | Pre-existing, not in this diff: shellcheck binary downloaded without a checksum | `.github/workflows/ci.yml:21-22` | security-reviewer, penetration-tester | `curl … \| tar -xJ` then onto `PATH`. Fix: verify a SHA-256 before extracting. |
| LOW | Pre-existing, not in this diff: checkout keeps its token in `.git/config` while PR code runs | `.github/workflows/ci.yml:16` | security-reviewer, penetration-tester | Read-only token; the workspace is not in the artifact. Fix: `persist-credentials: false`. |
| LOW | Pre-existing, not in this diff: the shellcheck verdict depends on the caller's cwd | `tests/run:38-54` | security-reviewer, tdd-guide | Same copy and fixture give `shellcheck=ok` from the repo root and `shellcheck=fail` (SC2034) from elsewhere. Fix: `cd "$REPO"` around the shellcheck call, in a separate change. |

## Coverage Report

Reviewers: 6/6 returned
Reviewed at: 10d228d13678c4157cc3c82c1ee9aa7fe971c99a
Any commit after this one is unreviewed.

**Confirmed**

- Criterion 1, keep: a keep run leaves `<keep>/<name>/out` and `<keep>/<name>/cwd/…` per scenario, passed and failed alike, 0 dirs left in a pinned `TMPDIR`, verdict unchanged; absolute paths, paths with spaces, a trailing slash and a symlinked keep dir work; kept dirs are mode 700 (code-reviewer, penetration-tester, security-reviewer, silent-failure-hunter, tdd-guide; fixture runs on `/tmp` copies).
- Criterion 1, unset: HEAD and `origin/main` give identical output and exit code on three fixtures; unset and empty string both leave 0 dirs in `TMPDIR`; the only loop change is `tests/run:34` (code-reviewer, penetration-tester, security-reviewer, tdd-guide).
- The var is hidden from scenarios and nested runs: `tests/run:21`; an outer keep dir holds only the outer scenario; removing the `unset` is caught (all five severity-using reviewers).
- Criterion 4, the test is real: reverting `tests/run` to `origin/main` turns it red (tdd-guide). Mutants killed by `tests/00-harness.sh:22-37`: code-reviewer 9 of 10, security-reviewer 7 of 7, silent-failure-hunter 6 of 8, penetration-tester 6 of 9, tdd-guide 12 of 17. Killed in every set: no `unset`, no stale `rm`, `cp` instead of `mv`, no removal when unset, keep only `out`, keep only failed scenarios.
- A timed-out scenario is kept with its output (`BLAST_OFF_TEST_TIMEOUT=1` probes; code-reviewer, penetration-tester, security-reviewer, silent-failure-hunter, tdd-guide).
- A cross-filesystem keep dir works: tmpfs in a private mount namespace, a file, a FIFO and a dangling symlink all moved, rc 0 (silent-failure-hunter, E6).
- `set -e` applies inside the `|| { … }` group at `tests/run:19`: a failed `mkdir` aborts before any scenario (code-reviewer, security-reviewer, silent-failure-hunter).
- A scenario leaving a `chmod 555` dir aborts `origin/main`'s `tests/run` the same way, so that abort class is not new (code-reviewer; penetration-tester agrees for the unset path).
- Scenario names cannot escape the keep dir: glob `[0-9][0-9]-*.sh` and `basename` at `tests/run:24,26` (penetration-tester, security-reviewer). A symlink planted at `$KEEP/<name>` is unlinked, not followed (penetration-tester, security-reviewer).
- Criterion 2 as written: the YAML parses; `BLAST_OFF_TEST_KEEP` is set at step level (`ci.yml:35-37`); the upload step has `if: failure()` and the same path (`ci.yml:43-48`); `runner` is an allowed context in `steps.env` and `steps.with` and not in job-level `env`; `contents: read` suffices for the upload (code-reviewer, penetration-tester, security-reviewer, silent-failure-hunter, tdd-guide).
- Criterion 3: `tests/run:7-8` documents the var; `docs/spec.md:215` names the behaviour in the `00-harness` row, matching measured behaviour; no other file documents `tests/run` env vars (all five).
- `run.log` is inside the kept tree: `bin/blast-off:60`, `tests/lib.sh:23` (tdd-guide, security-reviewer).
- No real secret reaches the kept dirs: scenarios pin `GH_TOKEN=dummy-not-a-token`, `tests/lib.sh:10` unsets the Jev keys, fakes record `set`/`unset` or a 6-character dummy prefix, no scenario dumps the environment; `ci.yml` references no `secrets.*`; trigger is `pull_request` on a private repo (code-reviewer, penetration-tester, security-reviewer, silent-failure-hunter, tdd-guide).
- The only upload-hostile file name found statically is `tests/22-dirty-tree.sh:123`; no scenario creates a FIFO or socket; the two symlinks (`tests/23-runner-lock.sh:26`, `tests/61-jev-pick.sh:57`) point at repo files (code-reviewer, penetration-tester, security-reviewer, silent-failure-hunter).
- The action's glob follows symlinks: `dist/upload/index.js:125432` (code-reviewer), `index.js:9770` (security-reviewer).
- Dependency facts: tag `v4` resolves to `ea165f8d65b6e75b540449e92b4886f43607fa02` (v4.6.2), `action.yml` declares `using: node20`, `include-hidden-files: 'false'`, `overwrite: 'false'`, `if-no-files-found: 'warn'`; latest release is v7.0.2; v6 and v7 declare `node24` (all six).
- Nothing consumes the artifact: `ci.yml` is the only workflow (penetration-tester).
- `bash -n tests/run` passes and `shellcheck -S warning` is clean on `tests/run` and `tests/00-harness.sh` (penetration-tester).
- The logged full gate at this commit ends `GATE: PASS passed=18 failed=0 shellcheck=ok`, with the var unset (code-reviewer, penetration-tester, silent-failure-hunter).
- The four reviewed files are identical to HEAD in the worktree (tdd-guide).

**Examined, inconclusive**

- `ci.yml:43-48` end to end on GitHub: the action was never executed; needs one red CI run (all reviewers; three were denied running the bundle locally).
- `ci.yml:45`: whether `upload-artifact@v4` works when forced onto Node 24; only `checkout@v4` is observed running that way.
- `ci.yml:14,44`: whether `failure()` is true on a job timeout or cancel; code-reviewer and security-reviewer read the docs as "no", the other four say the docs do not settle it; needs a real run.
- `ci.yml:47`: whether a re-run attempt collides on the fixed artifact name; README and `action.yml` do not settle it.
- `tests/run:34` in CI: whether `/tmp` and `RUNNER_TEMP` share a filesystem on `ubuntu-24.04`; not checked on a runner.
- The shellcheck flip on the real 18-scenario suite: shown on mini repos, inferred for the full suite.
- Other scenarios' kept dirs: only `00` and `22` were run for real (silent-failure-hunter); the rest were checked by grep.

**Not examined**

- A kept tree from a real full-suite keep run: its size, upload time and complete file-name inventory. No reviewer ran the full suite; the author's full keep run is asserted in the work note with no log.
- Scenarios 10 to 70 at run time with a keep dir set, other than 22.
- `lib/*.sh` and `bin/blast-off` beyond the token, file-name and `run.log` greps.
- The rest of `docs/spec.md` against the code; only line 215 was checked against behaviour.
- `actionlint` (not installed).
- A coverage percentage (no bash coverage tool here).

**Engagement check:** all five severity-using reviewers have substantive Confirmed lists backed by commands and file:line citations; none is tagged `[DID NOT ENGAGE]`.

## Unstated Assumptions and Open Questions (from critical-thinking)

1. **The new action is three majors behind and targets a removed runtime.** Why: `v4` declares `node20`, v6 and v7 declare `node24`, CI already forces `checkout@v4` onto Node 24, and the step's first real run is the moment it is needed. Verify: why v4 and not the current major; is a floating tag the accepted pin policy; who corrects "No new dependency" in the work note.
2. **`if: failure()` against the issue's own evidence.** Why: on `fix/ci-dead-status` (2026-11-09 to 11-11) 14 `ci` runs were 4 red and 10 green; only the red ones would have produced an artifact, and the issue's Evidence describes a run where the target test passed. Verify: was that run red or green; if green, what does this change do for an intermittent failure that passes on the diagnostic dispatch.
3. **CI now always takes the keep path, which has new ways to end with no verdict line.** Why: measured, an unwritable keep dir gives exit 1 with no `GATE:` line and unrun scenarios; local gates, `scripts/gate.sh` and `receipt`'s logs take the unset path. Verify: is exit 1 with no `GATE:` line acceptable for a keep-dir failure; is it acceptable that the default path is exercised in CI only through nested fixture runs.
4. **A cross-filesystem move is untested.** Why: the test pins `TMPDIR` inside the cwd so every tested `mv` is a `rename()`; in CI `/tmp` to `runner.temp` may be copy-then-delete over a tree still being written. Verify: are `/tmp` and `RUNNER_TEMP` on the same filesystem on hosted `ubuntu-24.04`, and on what evidence.
5. **The scenario in flight when `tests/run` dies is never in the keep dir.** Why: measured, `timeout 3 tests/run` left an empty keep dir and the work dir in `TMPDIR`; a job cancel or the 30-minute timeout is the uncovered case. Verify: does the upload step run at all on a job timeout or cancel; why move afterwards instead of creating the work dir inside the keep dir.
6. **A keep dir inside the repo turns the gate red.** Why: measured, `BLAST_OFF_TEST_KEEP=tests/kept` gives `shellcheck=fail`; the kept tree is also untracked and not ignored. Verify: is "outside `bin/`, `lib/` and `tests/`" an intended constraint, and where is it stated.
7. **Reusing a keep dir deletes and mixes content.** Why: measured, `keep/01-ok/precious` was deleted and `keep/99-gone` survived; concurrent runs can race between `rm` and `mv` (inferred). Verify: is a keep dir assumed fresh and owned by one run; is silent deletion of `<dir>/<name>` the intended contract.
8. **Three parts of the new code that no assertion notices.** Why: truncating a passing scenario's `out` still passes (only the failed scenario's content is pinned); removing the absolutising step still passes, and that line breaks under an exported `CDPATH`; the "fails here" comment at `tests/run:18` has no test and the unset run checks only a non-zero exit. Verify: which of these belong to the tested contract.
9. **What the artifact holds versus what a diagnosis needs.** Why: it holds `out`, cwd and `run.log`; it does not hold the child dirs under `$XDG_RUNTIME_DIR`, the user journal, or anything under a dot-directory (every `.git`); symlink handling and lost file permissions were unverified. Verify: for the failure behind issue 30 (and issue 29's dead-pane case), would `run.log` and `out` alone have been enough.
10. **Scenario work dirs are now published, with default retention.** Why: no `retention-days`; anything a scenario writes or prints is downloadable by repo readers; nothing stops a future scenario writing something sensitive. Verify: is 90 days intended; is that visibility recorded where a scenario author would see it.
11. **Fixed artifact name and re-runs.** Why: `overwrite` is `false` and re-running a red job is the natural use of this feature. Verify: what happens to the upload step on "re-run failed jobs" when attempt 1 already uploaded `blast-off-tests`.
12. **Evidence gaps behind the "done" claim.** Why: the only logged gate run is the unset path; the full keep run is asserted with no log; the upload step never ran; `actionlint` is absent; ci.yml was edited after the last gate run. Verify: is a deliberate red run on a throwaway branch planned before this is relied on.
13. **Discoverability of the artifact.** Why: the ci.yml header comment, `README.md`, `docs/` and `skills/` do not mention the artifact; the plan says the var is unset "inside the scenario subshell" while the code unsets it once in the main shell (same effect). Verify: how does the next person facing a red CI run learn that an artifact exists.
14. **Side observation, not part of this diff: the shellcheck verdict depends on the caller's cwd.** Why: the same command gives `PASS shellcheck (33 files)` from the repo root and `shellcheck=fail` from `/tmp`. Verify: is "run from the repo root" an intended precondition, and should the header say so.

## Reviewer Disagreements

- **Severity of the upload-step failure.** code-reviewer and silent-failure-hunter: HIGH. security-reviewer: MEDIUM, only because the action was not run end to end. penetration-tester and critical-thinking say all four criteria are met and report no HIGH; tdd-guide lists the rejected characters as inconclusive. Resolution: HIGH stands (highest reviewer rating; two independent measurements of the kept file plus the action's own validator); one forced-red CI run settles it.
- **Is criterion 2 met?** silent-failure-hunter: "met on paper only"; code-reviewer: "does not work as written". penetration-tester, security-reviewer, tdd-guide, critical-thinking: met as written, statically. Resolution: the config matches the criterion's wording, and H1 says it does not deliver the issue's purpose; treat the criterion as unproven until the red run.
- **Strength of the harness test.** security-reviewer: 7 of 7 mutants killed, no gap. code-reviewer: 9 of 10, the survivor "is a redundant line, not a test gap". silent-failure-hunter (6 of 8), penetration-tester (6 of 9) and tdd-guide (12 of 17, four non-equivalent survivors, rated MEDIUM) found real gaps. Resolution: the mutant sets differ; take the union of survivors as the gap list.
- **Is a failing `mv`/`rm` abort new?** silent-failure-hunter and security-reviewer: MEDIUM, two added abort points owned by a diagnostics option. penetration-tester: "the old failure class moved one run later, not a new one" (LOW); code-reviewer: LOW. Resolution: the unwritable-keep-dir case is new and live on every CI run; fix it by counting the failure.
- **Do the dropped hidden files matter?** silent-failure-hunter and security-reviewer: `.git` is the thing under test for `22-dirty-tree` and `40-receipt-required`. penetration-tester: "no hidden file under a job dir that diagnosis needs". Resolution: the tarball fix for H1 removes the question.
- **Does `failure()` cover a job timeout?** code-reviewer and security-reviewer state from the docs that it does not; the other four say the docs do not settle it. Resolution: observe it once, or use `failure() || cancelled()`.

## Recommended Changes (Prioritized)

1. Disposition the 18 open questions.
2. Replace the directory upload with a tarball made in an `if: failure()` step and upload that file (fixes H1 and the hidden-file, symlink and permission losses).
3. Run the workflow once on a branch with a deliberately failing scenario and confirm the artifact holds `<scenario>/out` and a `run.log`.
4. Move `actions/upload-artifact` to a node24 major (v6 or v7) and decide whether to pin both actions by commit SHA.
5. Make a failed keep (`mv`/`rm`) a counted, named failure so the loop continues and the `GATE:` line still prints.
6. Refuse a keep dir inside `$REPO` (or at least `bin/`, `lib/`, `tests/`), or state the constraint in the `tests/run` header.
7. Decide on `if: failure() || cancelled()` (or a step-level timeout) and record the choice in the ci.yml comment.
8. Tighten the re-run test: plant a stale marker, assert the second run's verdict, assert the kept dir is exactly `cwd out`.
9. Pin the CI wiring in `00-harness` (env set, same path, `if: failure()`) and set `if-no-files-found: error`.
10. Add the small test assertions: uncreatable keep dir, unset-run verdict, nothing new in the cwd when unset, an absolute keep path, unset versus empty.
11. Drop the redundant absolutising of `KEEP` and use `mkdir -p -- "$KEEP"`.
12. Document in the header that `<dir>/<name>` is replaced, stale dirs persist and the dir must be dedicated.
13. Set `retention-days`, a per-attempt artifact name and a single definition of the keep path; reword the ci.yml comments.
14. Consider a `journalctl --user` dump into the keep dir on failure.
15. Correct "No new dependency" in the work note and decide whether `baton-runner/` bookkeeping belongs in history.
16. In separate changes: checksum the shellcheck download, set `persist-credentials: false`, and `cd "$REPO"` before the shellcheck call.

## Open Questions for the Author

- Why `actions/upload-artifact@v4` and not the current major, and is a floating tag the accepted pin policy for this repo? — Disposition: PENDING
- Who corrects "No new dependency" in `baton-phase-1-work.md`? — Disposition: PENDING
- Was the run in issue 30's Evidence section red or green, and what does this change do for a failure that passes on the diagnostic dispatch? — Disposition: PENDING
- Is exit 1 with no `GATE:` line an acceptable outcome for a keep-dir failure, given the header documents exit 1 as `GATE: FAIL …`? — Disposition: PENDING
- Is it acceptable that CI no longer exercises the default (unset) path at top level, only through the nested fixture runs in `00-harness`? — Disposition: PENDING
- Are `/tmp` and `RUNNER_TEMP` on the same filesystem on hosted `ubuntu-24.04`, and on what evidence? — Disposition: PENDING
- Does the upload step run on a job timeout or cancel, and is `if: failure() || cancelled()` wanted? — Disposition: PENDING
- Why move the work dir afterwards instead of creating it inside the keep dir? — Disposition: PENDING
- Is "the keep dir must be outside `bin/`, `lib/` and `tests/`" an intended constraint, and where is it stated? — Disposition: PENDING
- Is a keep dir assumed fresh and owned by one run, and is silent deletion of `<dir>/<name>` the intended contract? — Disposition: PENDING
- Which of the untested parts (a passing scenario's `out` content, the absolutising step, the early-failure comment, the unset-run verdict) belong to the tested contract? — Disposition: PENDING
- For the failure behind issue 30 and issue 29's dead-pane case, would `run.log` and `out` alone have been enough, or was the evidence in the child dir or the journal? — Disposition: PENDING
- Is 90 days the intended retention, and is "scenario cwd and output are readable by anyone with repo read access" recorded where a scenario author would see it? — Disposition: PENDING
- What happens to the upload step on "re-run failed jobs" when attempt 1 already uploaded `blast-off-tests`? — Disposition: PENDING
- Is a deliberate red run on a throwaway branch planned before this is relied on? — Disposition: PENDING
- How does the next person facing a red CI run learn that an artifact exists and where to get it? — Disposition: PENDING
- Is "run `tests/run` from the repo root" an intended precondition, and should the header say so? — Disposition: PENDING
- Do the three `baton-runner/` bookkeeping files belong in this repo's history? — Disposition: PENDING

**Merge gate.** Recommended action: block. H1 is unresolved and 18 questions are PENDING; once H1 is fixed and the red run confirms the artifact, the action is at most merge-with-fixes until the questions are dispositioned.

## Notes

- Roster came from context-aware selection (floors `critical-thinking`, `code-reviewer`; forced `penetration-tester` and `security-reviewer` on the external-I/O risk flag of the artifact upload; signal lanes `silent-failure-hunter` for error handling and `tdd-guide` for tests). None of the six is an active agent in this repo (`.claude/agents/` does not exist); all six are parked in `~/.claude/agents-parked/`. Each ran as a `general-purpose` agent told to read its parked definition and adopt it, read-only (the user's paste method), not as a registered `subagent_type`. The skill's own rule for a parked-only name is to hard-fail or ask for activation; this run deviated from it and says so here.
- The review ran inline inside a baton-runner review unit that is itself a subagent, not through the skill's orchestrator subagent, to keep to two dispatch layers.
- `--high-cap off` was applied although the caller did not pass it, because the report feeds a gate on the CRITICAL and HIGH count.
- Reviewer checkpoints are in `baton-runner/br-1115-issues/review-phase-1-iter-1/` in the worktree, not in the primary checkout's `.claude/reviews/` (the unit may write only under `baton-runner/br-1115-issues/`); the `.claude/reviews/` ignore step was skipped for the same reason.
- Three reviewers (code-reviewer, security-reviewer, silent-failure-hunter) report that the permission classifier denied running the downloaded upload-artifact bundle locally; the upload-step failure rests on the action's source plus a kept tree, not an end-to-end run.
- The penetration-tester reports that one probe (`BLAST_OFF_TEST_KEEP=-`) made `cd -` resolve to the worktree path through `OLDPWD`, that the resulting `rm -rf` target did not exist, and that `git status` was unchanged; scratch dirs were left under `/tmp` by several reviewers.
- The security-reviewer reports its advisor tool was rate-limited.

## Report Audit

- **Class 5 (coverage inflation).** The Coverage Report says "Killed in every set: no `unset`, no stale `rm`, `cp` instead of `mv`, no removal when unset, keep only `out`, keep only failed scenarios." silent-failure-hunter's set has no "keep only failed scenarios" mutant: its table lists "M1: no `unset BLAST_OFF_TEST_KEEP`", "M2: no `rm` before `mv`", "M3: unset path leaves the dir", "M4: copy instead of move", "M5: never keep", "M6: keep only `out`", "M7: merge into the old kept dir", "M8: no absolute-path resolution". That mutant was killed in four of the five sets, not every set.
- **Class 6 (attribution).** The Confirmed entry "The only upload-hostile file name found statically is `tests/22-dirty-tree.sh:123`; no scenario creates a FIFO or socket; the two symlinks … point at repo files (code-reviewer, penetration-tester, security-reviewer, silent-failure-hunter)" credits penetration-tester with the file-name claim. Its Validated list says only "No fifo or socket is created in a scenario cwd; the only symlinks point at single files" and never mentions `22-dirty-tree.sh:123` or a rejected-character search; the report's own H1 says "penetration-tester and tdd-guide did not raise it".
- **Class 6 (loss).** tdd-guide's MEDIUM on `tests/00-harness.sh:33-34` also says "The check also depends on GNU `mktemp`'s default `tmp.*` name and looks only at `01-ok`. Nothing asserts that the keep dir holds exactly one subdir per scenario." The report's row ("Line 33 ignores the second run's verdict (`|| true`) and line 34 checks only what run 1 already made true; survivors: …") carries neither point, and no other section does.
- **Class 6 (attribution, minor).** Two table rows give a fix no reviewer proposed. "The fixture cannot tell an unset var from an empty one … Fix: test `${BLAST_OFF_TEST_KEEP+x}`" is attributed to penetration-tester, whose suggested fix for that finding is "Delete the normalisation, or add one assertion for an unmakeable keep dir (non-zero exit, no scenario output)." "Cases the test does not cover … Fix: add an absolute-path case at least" is attributed to silent-failure-hunter and penetration-tester; silent-failure-hunter's fix is "Before the second run, drop a marker file in `kept/01-ok/` and assert it is gone afterwards; grep the verdict on line 36", and penetration-tester proposes no absolute-path test.
