# Multi-Agent Review: spec set: .github/workflows/ci.yml + docs/spec.md + tests/00-harness.sh + tests/run (round 2, after fix 97a4ebe)

## Executive Summary

Six reviewers (critical-thinking, code-reviewer, penetration-tester, security-reviewer, silent-failure-hunter, tdd-guide) reviewed HEAD 97a4ebe, the issue 30 change plus the round-1 fix. No reviewer filed a CRITICAL or HIGH: the round-1 HIGH (P1R1-1) is fixed by the tar step and holds on real kept trees locally, and the `tests/run` half is sound and measured by every reviewer. The CI half is still unexecuted and weaker than the fix baton says: with nothing kept the tar step leaves a 45-byte empty archive so the upload goes green and `if-no-files-found: error` cannot fire (the `ci.yml` comment says the opposite), and the new `ci.yml` test in `00-harness` is substring greps that let most wiring mutants through. Totals after dedupe: 0 CRITICAL, 0 HIGH, 6 MEDIUM, 37 LOW; these are raw, unchallenged reviewer findings, since refutation did not run. Recommended action: **merge-with-fixes** (correct the empty-archive case and its comment, then one deliberately red CI run); 21 open questions are PENDING, so `merge` is not available. Outside the diff: this review's own parallel suite runs left the owner's installed systemd unit pointing at a scratch dir (see Notes); the owner must restore it.

**Round-1 HIGH and MEDIUM at HEAD**

| ID | critical-thinking | code-reviewer | penetration-tester | security-reviewer | silent-failure-hunter | tdd-guide | Merged |
|---|---|---|---|---|---|---|---|
| P1R1-1 | fixed locally, unproven on a runner | resolved in design, proven locally, unproven on a runner | resolved locally, unproven on a runner | resolved locally, unproven on GitHub | resolved locally, unproven on a runner | resolved in design and locally, never executed on GitHub | resolved locally, unproven on a runner |
| P1R1-2 | reshaped, not resolved | reshaped | not resolved, reshaped | reshaped, not resolved | reshaped, not resolved | not resolved, reshaped | reshaped (not resolved) |
| P1R1-3 | half resolved | half resolved | runtime resolved (read), tag still mutable | half resolved | runtime half resolved, tag half still true | resolved for the runtime, tag still mutable | partly resolved |
| P1R1-4 | resolved on the keep branch only | resolved for the keep step | resolved | resolved for the keep branch | resolved for the keep path | resolved | resolved for the keep branch; four reviewers note the unset branch still aborts with no verdict (pre-existing), two say plain "resolved" |
| P1R1-5 | resolved for the three dirs, tested for one | resolved | resolved | resolved for direct paths, test covers one arm of three | resolved in code, test covers `tests/` only | resolved | resolved in code; test covers one of three dirs |
| P1R1-6 | reshaped | partly resolved | partly resolved | partly resolved | reshaped | half resolved, unexecuted | partly resolved; critical-thinking and silent-failure-hunter say reshaped (the hung scenario is not in the artifact) |
| P1R1-7 | resolved | resolved | resolved | resolved | resolved | resolved | resolved |

## Critical Findings

None.

## High Findings

None. All five severity-using reviewers state that nothing they could reproduce reaches HIGH at HEAD.

## Medium and Low Findings

| Severity | Title | Location | Reviewer(s) | One-line description |
|---|---|---|---|---|
| MEDIUM | Tar on a missing keep dir leaves an empty archive; the upload succeeds and `if-no-files-found: error` cannot fire | `.github/workflows/ci.yml:50-54,61` | code-reviewer (MEDIUM), penetration-tester (MEDIUM), security-reviewer (MEDIUM), silent-failure-hunter (MEDIUM), tdd-guide (MEDIUM) | `[new in fix]` Measured by all five: tar exits 2 and leaves a 45-byte, 0-member `.tgz`; v7 source applies `if-no-files-found` only at 0 files, so a run that failed before the gate uploads an empty artifact green, and the comment "Both steps also run, and fail" is false. Fix: stop tar leaving the file (gate-step `id` condition, `test -d` guard, or remove the file on failure) and correct the comment; the harness pins must change with it. |
| MEDIUM | The `ci.yml` test in `00-harness` binds text, not steps | `tests/00-harness.sh:71-87`; claim at `:73-74`; `docs/spec.md:215` | code-reviewer (MEDIUM, 10 of 17 mutants survive), penetration-tester (MEDIUM), security-reviewer (MEDIUM, 11 of 11 structural), silent-failure-hunter (MEDIUM, 14 of 15), tdd-guide (MEDIUM, 11 of 21) | `[new in fix]` `grep -qF` substring matches and a file-wide count of `if: failure()`: survivors include the env commented out, moved or suffixed, the upload path suffixed, the upload step deleted or reordered, `@v4`, `if-no-files-found` and `timeout-minutes` dropped; "cannot drift apart" is false. Fix: parse the YAML (or whole-line matches) and assert per step: env on the gate step, tar then upload, both `if: failure()`, `with.path` equal to the tar output, pinned `uses`. |
| MEDIUM | The CI wiring has still never executed | `.github/workflows/ci.yml:35-61` | code-reviewer (MEDIUM), penetration-tester (MEDIUM), silent-failure-hunter (MEDIUM); security-reviewer and tdd-guide state it in their P1R1-2 rows | `[still open from round 1 (P1R1-2)]` No remote branch, no run, 0 artifacts in the repo: the keep path on a runner, the tar step, `upload-artifact@v7`, `failure()` and the step timeout are unobserved. Fix: push and force one red run; check the artifact holds `22-dirty-tree/cwd/`; also check one green run. |
| MEDIUM | A gate killed by the step timeout uploads an archive without the hung scenario, whose output is never printed | `.github/workflows/ci.yml:36-38,40`; `tests/run:36-37,44-47` | silent-failure-hunter (MEDIUM), penetration-tester (LOW); tdd-guide lists it under still-open | `[still open from round 1 (P1R1-6)]` Measured: keep dir holds only finished scenarios, the hung one's `out` stays in `TMPDIR`; `timeout` has no `-k`, so a scenario ignoring TERM is unbounded (pre-existing). Fix: `timeout -k 10`, or trap TERM/INT and move `$work`, or tar leftover `/tmp/tmp.*/out`. |
| MEDIUM | Spec row and header promise refusal under `bin/`, `lib/` or `tests/`; the test proves only relative `tests/kept` | `tests/00-harness.sh:65-69`; `tests/run:26-27`; `docs/spec.md:215` | security-reviewer (MEDIUM), code-reviewer (LOW), penetration-tester (LOW), silent-failure-hunter (LOW), tdd-guide (LOW) | `[new in fix]` Survivors: `bin/` and `lib/` arms dropped, `case "$abs"` without the trailing slash, `realpath -s`; behaviour is right by hand. Fix: loop the assertion over `bin/k`, `lib/k`, `tests/k` and bare `tests`. |
| MEDIUM | Concurrent suite runs corrupt the owner's installed unit files | `tests/lib.sh:30-46`; `tests/11-unit-smoke.sh:13,51` | tdd-guide (MEDIUM), security-reviewer (LOW), code-reviewer (LOW), penetration-tester (LOW) | `[pre-existing, outside the diff; missed by round 1]` `install_units`/`restore_units` save and restore with no lock; observed live in this review (see Notes). Fix: `flock` around install-to-restore or a per-scenario `XDG_CONFIG_HOME`; one full-suite run at a time per box. |
| LOW | Unset path: a work dir that cannot be removed (or a failed `mktemp`) ends the run with no `GATE:` line | `tests/run:36,44` | code-reviewer, silent-failure-hunter, security-reviewer | `[pre-existing, outside the diff]` Same on `origin/main`; the keep and unset paths now differ, and CI always takes the keep path so such a scenario passes CI and breaks local gates. Fix: count-and-continue on the unset branch too. |
| LOW | A failed keep deletes the fresh work dir and can leave a truncated or stale `<dir>/<name>` | `tests/run:45-46` | code-reviewer, security-reviewer, penetration-tester, tdd-guide | `[new in fix]` Measured on ENOSPC (cross-filesystem) and on an undeletable stale dir: old and new evidence both lost. Fix: leave `$work` and print its path, or remove `$KEEP/$name`. |
| LOW | `rm -rf "$work" \|\| true` after a failed keep can leave the work dir with no line saying so | `tests/run:46`; `tests/00-harness.sh:44-45` | silent-failure-hunter, code-reviewer | `[new in fix]` Measured on a second keep run over a mode 555 subdir. Fix: echo the path when that `rm` fails. |
| LOW | A keep failure is counted on top of the scenario's own result | `tests/run:38,46`; `tests/00-harness.sh:51` | code-reviewer, security-reviewer, penetration-tester, tdd-guide | `[new in fix]` Two passing scenarios give `passed=2 failed=2`; `lib/receipt.sh:33` copies the tally. Fix: say so in the header, or count keep failures separately. |
| LOW | An existing but unwritable keep dir is not caught up front | `tests/run:28` | silent-failure-hunter | `[new in fix]` The whole suite runs, then every scenario gets `FAIL keep`. Fix: `[ -w "$abs" ] \|\| no_keep "not writable"`. |
| LOW | The `rm` half of the keep step has no test | `tests/run:45`; `tests/00-harness.sh:44-52` | code-reviewer, silent-failure-hunter, tdd-guide | `[new in fix]` `rm …; mv …` survives; only `mv` is made to fail. Fix: add an undeletable-stale-dir case. |
| LOW | `KEEP="$abs"` is not pinned | `tests/run:29` | code-reviewer, security-reviewer, penetration-tester, silent-failure-hunter, tdd-guide | `[new in fix]` Removing it survives; matters only for values starting with `-`. Fix: one `-k` assertion, or accept. |
| LOW | A default keep dir when the var is unset still survives | `tests/00-harness.sh:41-43` | code-reviewer, security-reviewer, penetration-tester, silent-failure-hunter, tdd-guide | `[still open from round 1 (P1R1-13)]` Fix: snapshot the cwd around the unset run. |
| LOW | A passing scenario's kept `out` content is not asserted | `tests/00-harness.sh:32` | code-reviewer, security-reviewer, penetration-tester, silent-failure-hunter, tdd-guide | `[still open from round 1 (no ID; a round-1 survivor per penetration-tester)]` Truncating `out` survives. Fix: have `01-ok` print a mark and `grep -qx` it. |
| LOW | The unset-run verdict assertion (P1R1-12) has no demonstrated red | `tests/00-harness.sh:41-42` | security-reviewer, tdd-guide | `[new in fix]` No mutant shown; one attempt died at an earlier line. |
| LOW | `00-harness` is coupled to the shape of `ci.yml` | `tests/00-harness.sh:78-80,85` | code-reviewer, security-reviewer, penetration-tester, silent-failure-hunter, tdd-guide | `[new in fix]` Exactly two `if: failure()` lines rejects `failure() \|\| cancelled()`, a third failure step, `${{ failure() }}`, a guarded `if` and a block-scalar tar; every one-line `run: tar …` is run through `bash -c`; fails where `.github/` is absent. Fix: assert on parsed steps. |
| LOW | `realpath -m` is GNU-only; a missing or failing `realpath` ends the gate with no verdict | `tests/run:26` | code-reviewer, security-reviewer, penetration-tester, tdd-guide | `[new in fix]` Measured: exit 127 (or 1) and no `GATE:` line; the harness also now needs GNU `tar` and `diff --no-dereference`. Fix: `… \|\| no_keep "cannot be resolved"`. |
| LOW | The header does not say an unkept work dir is deleted | `tests/run:7-10` | code-reviewer | `[new in fix]` One clause in the header. |
| LOW | A trailing line feed in the value is dropped | `tests/run:26` | penetration-tester | `[new in fix]` `…/nl\n` keeps into `…/nl`. Nit. |
| LOW | A repo whose `tests/` (or `bin/`, `lib/`) is a symlink bypasses the refusal | `tests/run:26-27` | security-reviewer | `[new in fix]` Measured: `shellcheck=fail`, stays red with the var unset. Fix: also compare against `realpath "$REPO/tests"` etc., or note it. |
| LOW | A keep dir elsewhere in the repo is accepted | `tests/run:27`; `scripts/gate.sh:9` | penetration-tester, silent-failure-hunter | `[new in fix]` `.` and `docs/kept` pass and leave nested `.git` dirs; a relative value under `scripts/gate.sh` resolves against the repo root. Fix: one header sentence. |
| LOW | After a step timeout `tests/run` may keep running as an orphan while the tar step runs | `.github/workflows/ci.yml:35-38,52-54` | security-reviewer | `[new in fix]` Simulated from runner source, not reproduced on a runner. Fix: `exec tests/run` as the step's last command, or record the limit. |
| LOW | A non-zero tar exit still uploads, with no marker of what is missing | `.github/workflows/ci.yml:53-61` | silent-failure-hunter | `[new in fix]` Mode-000 file rc 2, changing file rc 1, socket ignored; the only trace is the tar step's log. Fix: write tar's stderr into the keep dir, or say so. |
| LOW | The upload steps fire on any earlier failed step | `.github/workflows/ci.yml:53,56` | security-reviewer | `[still open from round 1 (P1R1-21)]` Now leaves an empty artifact instead of a warning. |
| LOW | The keep path is written four times | `.github/workflows/ci.yml:41,54,60`; `tests/00-harness.sh:76-77` | security-reviewer | `[still open from round 1 (P1R1-23)]` A literal change is caught; moving or commenting the env is not. |
| LOW | The artifact is a zip holding a `.tgz` | `.github/workflows/ci.yml:57-61` | code-reviewer, silent-failure-hunter, tdd-guide | `[new in fix]` v7 `archive` defaults to `true`; deferred on purpose. Fix: `compression-level: 0` or `archive: false`, after the red run. |
| LOW | Default retention, and the tarball now carries every `.git` | `.github/workflows/ci.yml:54-61` | code-reviewer, security-reviewer, penetration-tester, silent-failure-hunter, tdd-guide | `[still open from round 1 (P1R1-20)]` 90 days; 578 dot-path files the old upload dropped. Fix: `retention-days: 7`. |
| LOW | Mutable action tags; `checkout@v4` is still node20 | `.github/workflows/ci.yml:17,57` | code-reviewer, security-reviewer, penetration-tester, silent-failure-hunter, tdd-guide | `[still open from round 1 (P1R1-3 remainder)]` Manager's call: pin by SHA, bump checkout separately. |
| LOW | Fixed artifact name with `overwrite: false` | `.github/workflows/ci.yml:59` | code-reviewer, security-reviewer, penetration-tester, silent-failure-hunter, tdd-guide | `[still open from round 1 (P1R1-22)]` A re-run collision is unverified. Fix: `name: blast-off-tests-${{ github.run_attempt }}`. |
| LOW | The tarball carries the refused file names (two from the fix's own fixture) and absolute symlinks | `tests/00-harness.sh:81-84`; `.github/workflows/ci.yml:54` | penetration-tester, security-reviewer | `[new in fix]` PR-controlled content; nothing consumes it in a workflow. Fix: remove `rt` and `back` at the end of the block; extract into an empty dir. |
| LOW | Kept trees carry dead absolute paths | `tests/run:45` | silent-failure-hunter | `[missed by round 1]` 65 files name the pre-move work dir; one symlink points into the checkout. A header line would do. |
| LOW | A local kept tree holds copies of the owner's unit files and a journal extract | `tests/lib.sh:35-36`; kept `11-unit-smoke/cwd/units-saved/` | security-reviewer, code-reviewer | `[missed by round 1]` Names `/home/<user>` and the hostname, no secret; on a runner these are runner values. |
| LOW | CI no longer runs the unset path at top level; the local gate never runs the keep path | `.github/workflows/ci.yml:39-41`; `scripts/gate.sh:10` | security-reviewer, tdd-guide, silent-failure-hunter | `[still open from round 1 (open question)]` Accept and record, or one keep-set gate run on a quiet box. |
| LOW | Issue 30's own case is not served | `.github/workflows/ci.yml:53,56` | code-reviewer, silent-failure-hunter | `[still open from round 1 (open question)]` The issue's evidence is a green diagnostic run; upload happens only on red, as criterion 2 requires. |
| LOW | Comments and spec say more than is true | `.github/workflows/ci.yml:4-5,50-51`; `docs/spec.md:215`; `tests/00-harness.sh:73-74` | tdd-guide, penetration-tester, code-reviewer | `[new in fix]` "every scenario's work dir" is every finished one; "cannot drift apart" and "into the file the upload step names" do not hold; the zip-in-tgz is said nowhere. Reword after the MEDIUM fixes. |
| LOW | Fix-baton evidence gaps and statements that do not hold | `baton-runner/br-1115-issues/baton-phase-1-fix-1.md`; `fix-phase-1-iter-1/tests-run-keep.log` | silent-failure-hunter, tdd-guide, security-reviewer | `[new in fix]` `tests-run-keep.log` is byte-identical to `tests-run.log`; the header says uncommitted at 1e3d34d; RED 1 has inferred lines (reviewers reproduced them); RED 5 shows one of seven assertions; the token scan ran on nothing; "fixed as far as a local change can" and "fixed by test" overstate. |
| LOW | Test blocks share state | `tests/00-harness.sh:28-55` | tdd-guide | `[new in fix]` `keepfix.out`, `ok.out` and `tmp` are reused across checks. Optional: a private file per block. |
| LOW | A timed-out scenario's keep and a keep dir on another filesystem are not in the suite | `tests/00-harness.sh:22-56` | code-reviewer, security-reviewer, tdd-guide | `[still open from round 1 (P1R1-14)]` Both work by hand. |
| LOW | Reused keep dir: "dedicated dir" unstated, stale dirs of other scenarios stay, `mv` without `-T` | `tests/run:7-10,45` | code-reviewer, security-reviewer, penetration-tester, silent-failure-hunter, tdd-guide | `[still open from round 1 (P1R1-16, -17, -18)]` `mkdir -p` also accepts a dir someone else owns. |
| LOW | The user journal is not captured | `.github/workflows/ci.yml:52-61` | code-reviewer, security-reviewer, penetration-tester, silent-failure-hunter | `[still open from round 1 (P1R1-25)]` Outside issue 30; the two-line `if: failure()` pin blocks adding the step. |
| LOW | Runner bookkeeping in history has grown | `baton-runner/br-1115-issues/` | code-reviewer, security-reviewer, penetration-tester, silent-failure-hunter | `[still open from round 1 (P1R1-27)]` Manager's call. |
| LOW | Shellcheck download without checksum; checkout keeps its token; shellcheck verdict depends on cwd | `.github/workflows/ci.yml:17,22`; `tests/run:51-67` | code-reviewer (re-measured the cwd case), security-reviewer, penetration-tester, silent-failure-hunter | `[pre-existing, outside the diff (P1R1-28, -29, -30)]` Separate changes. |

## Coverage Report

Reviewers: 6/6 returned
Reviewed at: 97a4ebe8ee70581ea9c5182552ba74a464869644
Any commit after this one is unreviewed.

- **Confirmed:**
  - `00-harness` alone passes on `git archive HEAD` copies: `GATE: PASS passed=1 failed=0 shellcheck=skipped` (all six).
  - Full gate with the keep dir set as CI sets it: `GATE: PASS passed=18 failed=0 shellcheck=ok` (code-reviewer, 205 s; security-reviewer); 16 of 16 without scenarios 11 and 31 (penetration-tester); 8 scenarios twice (silent-failure-hunter); tdd-guide's run was 17 of 18, `11-unit-smoke` failing from the unit-file cross-talk.
  - Kept tree: 18 dirs each with `out` and `cwd/`, 85 `run.log`, 3 refused names, 578 files under `.git`, 4 symlinks, 0 sockets or FIFOs (code-reviewer, security-reviewer, tdd-guide).
  - The `ci.yml:54` tar line on a real kept tree: exit 0, untar plus `diff -r --no-dereference` 0 lines (all six; critical-thinking on a 00-harness tree).
  - Criterion 1 unset: HEAD and `origin/main` `tests/run` give identical output, exit code and `TMPDIR` leftovers on fixtures; empty value behaves as unset (code-reviewer, penetration-tester, tdd-guide).
  - Criterion 4: reverting `tests/run` to `origin/main` fails at "keep fixture verdict" (tdd-guide); `tests/run` mutants killed at the intended assertions: 14 of 21 (code-reviewer), 17 of 24 (tdd-guide), 15 (silent-failure-hunter), 14 of 19 (critical-thinking), R8-R17, R20, R21 (penetration-tester).
  - P1R1-4 on the keep branch: unwritable keep dir and undeletable stale dir give `FAIL keep <name>` and a verdict (five reviewers). P1R1-5: `bin/`, `lib/`, `tests`, absolute, `..` and symlink-into-`tests/` values refused (four reviewers). P1R1-7: the three stale-dir mutants die at "second run did not replace the kept dirs", line read (critical-thinking, code-reviewer, penetration-tester, tdd-guide).
  - P1R1-8, -9, -11, -15, -19, -24 resolved (security-reviewer). A timed-out scenario is kept with its output (penetration-tester, security-reviewer, tdd-guide, critical-thinking). A cross-filesystem move of the real tree works on a tmpfs (code-reviewer).
  - `upload-artifact` v7 from `gh api`: tag `v7` is commit `cf430e030ddbb5b0abf93d22962f4752f3646cd9`, v7.0.2 (2026-10-07), `using: node24`; inputs `name`, `path`, `if-no-files-found` exist; `overwrite` `false`, `include-hidden-files` `false`, `archive` `true`; `if-no-files-found` applies only at 0 files (`src/upload/upload-artifact.ts`); a single-file path gets its dirname as root and the hidden filter is basename-only (all six in part).
  - Refused characters `" : < > | * ? \r \n` (`actions/toolkit` `path-and-artifact-name-validation.ts`, default branch).
  - A step timeout sets `TaskResult.Failed`, a job cancel `Canceled` (`actions/runner` `StepsRunner.cs:322-330`, read by all six); `ScriptHandler.cs` passes `killProcessOnCancel: false` (security-reviewer).
  - `ci.yml` parses with PyYAML: env and `timeout-minutes: 25` on the gate step, `if: failure()` on tar and upload, `path` equal to the tar output (code-reviewer, penetration-tester, security-reviewer, silent-failure-hunter).
  - No secret reaches the kept tree: six canary values on a full 18-scenario keep run, 0 matches in files, log, `.git` objects and the nested `.tgz` (security-reviewer); eight canaries on 16 scenarios, 0 (penetration-tester); 0 token-shaped strings (code-reviewer, tdd-guide); the checkout token cannot reach the artifact (security-reviewer).
  - Criterion 3: `tests/run:7-10`, `docs/spec.md:215` (code-reviewer, tdd-guide). `shellcheck -S warning` clean (code-reviewer, penetration-tester). `lib/receipt.sh:6-9,31-38` reads only the last `GATE:` line and the `no_keep` verdict fits (code-reviewer).
  - The branch has never run on GitHub: no remote branch, no run, 0 artifacts (all six). The worktree is unchanged (all six).
- **Examined, inconclusive:**
  - `ci.yml:53-61` end to end on a runner (tar step, v7 upload, `if: failure()`, `if-no-files-found`): needs a pushed red run.
  - `ci.yml:38`: the step timeout making `failure()` true, read from default-branch runner source, not observed.
  - `ci.yml:57`: the upload succeeding on the 45-byte archive, read from v7 source, not run.
  - `ci.yml:59`: artifact name on a re-run attempt; README and `action.yml` do not settle it.
  - `tests/run:45` in CI: whether `/tmp` and `RUNNER_TEMP` share a filesystem.
  - The path validator was read at toolkit `main`, not in the v7 bundle.
  - The orphaned `tests/run` after a step timeout (security-reviewer): simulated only.
  - Secret-value scans by silent-failure-hunter and tdd-guide ran on nothing (no variable set); the canary runs above cover it.
- **Not examined:**
  - The upload-artifact bundle executed; `actionlint` (not installed).
  - A full keep run on a quiet box: every reviewer's full run overlapped another suite.
  - The full suite on the unset path at HEAD by a reviewer (all relied on `gate-phase-1-iter-2/tests-run.log`).
  - `lib/*.sh` and `bin/blast-off` beyond greps and `lib/receipt.sh:1-40`; the rest of `docs/spec.md`; scenarios 10 to 70 line by line.
  - Extraction of the tarball on NTFS or `/mnt/c`.

**Engagement check:** all five severity-using reviewers have substantive Confirmed lists; none is tagged `[DID NOT ENGAGE]`.

## Unstated Assumptions and Open Questions (from critical-thinking)

1. P1R1-1 is fixed locally and unproven on a runner: what observed result on a runner counts as proof, and does the merge wait for it?
2. P1R1-2 is reshaped: six "cannot drift apart" mutants and seven criterion-2 mutants pass. Which properties of the wiring is the test meant to guarantee?
3. P1R1-3 is half resolved: is a floating major tag the accepted pin policy for this repo?
4. P1R1-4 is resolved on the keep branch only: why is "no verdict line" fixed for the opt-in branch and left on the branch every local gate takes?
5. P1R1-5 is resolved for three dirs and tested for one: is the spec row meant to describe what the test checks, or what the code does?
6. P1R1-6 is reshaped: for a hung gate, which scenario's logs does the reader of the artifact need?
7. P1R1-7 is resolved; the fix baton's inferred lines are now read.
8. The `ci.yml:50-51` comment is false for the upload step (45-byte archive): what should a reader find when the job failed before `tests/run` started?
9. The test runs text taken from `ci.yml` as shell (`; echo …` appended passes): is executing the workflow line the intended design?
10. The `ci.yml` pins are format pins and phase 2 edits the same file: who is expected to learn of them before editing `ci.yml`?
11. The tally can exceed the scenario count (`passed=2 failed=4` for 3 scenarios): does `failed=` still mean scenarios?
12. An uncreatable keep dir fails before any scenario, an unwritable one after every scenario: why are the two handled at different times?
13. A failed keep can leave the work dir behind with no line; the `rm` half is untested: is "nothing stays in TMPDIR" a promise or a best effort?
14. "A kept tree elsewhere in the repo harms nothing" has a counter-case: `docs/kept` and `.` are accepted and `lib/receipt.sh:27-28` refuses a receipt on uncommitted paths. What happens to `blast-off receipt` with an in-repo keep dir?
15. `00-harness` adds its own refused names to every kept tree, and they cannot exist on NTFS: where is the downloaded artifact meant to be unpacked?
16. The 25-minute step timeout has no stated basis (exactly five 300 s scenario timeouts; two past runs as sample): what failure is it sized for?
17. Edge inputs: a keep dir name ending in a line feed is kept without it; `realpath -m` runs under `set -e` before `no_keep`. Is GNU coreutils a stated requirement of `tests/run`?
18. `docs/spec.md:215` says more than the test proves (three dirs, "unset leaves no work dir", "the file the upload step names"): test inventory or contract?
19. P1R1-13 still survives: is "not in TMPDIR" the same claim as "removed"?
20. P1R1-22 is unverified; 1 of 22 listed `ci` runs is an attempt 2 and it is red: what does the upload do on attempt 2?
21. P1R1-20 with a larger artifact (90 days, every `.git`): who has checked the full kept tree for content that should not be published?
22. P1R1-27 has grown (10 of 14 changed files are under `baton-runner/`): do these files belong in the PR for issue 30?
23. The 18 round-1 open questions are undispositioned; the sharpest stands: does this change help the green run that prompted the issue?
24. Other round-1 items unchanged at HEAD (P1R1-17, -18, -25, -28, -29, -30, the P1R1-14 remainder, P1R1-16, the passing `out` content, CI exercising only the keep path, the var named only in `docs/spec.md:215`, `tests/run` and `ci.yml`, no `actionlint`): which are accepted limits, and where is that recorded?
25. Process disclosure: two calls died to its own `pgrep -f` kill loop; it did not run the full suite; one probe batch stripped the variable; scratch dirs left under `/tmp/bo-r2.*`. Is a full keep run on a quiet box wanted before the next unit relies on the 1445-file figure?

## Reviewer Disagreements

- **Hung scenario missing from a step-timeout upload:** silent-failure-hunter MEDIUM, penetration-tester LOW ("narrow": needs about five scenario timeouts). Rendered MEDIUM (highest filed); it is a recorded limit of criterion 2, so fix the header wording now and decide `timeout -k` separately.
- **Refusal tested for one dir of three:** security-reviewer MEDIUM, four reviewers LOW. Rendered MEDIUM; the fix is a three-line loop either way.
- **Unit-file race in `tests/lib.sh`:** tdd-guide MEDIUM, three reviewers LOW. Rendered MEDIUM; all agree it is pre-existing and outside this diff.
- **P1R1-6 status:** critical-thinking and silent-failure-hunter say reshaped; the other four say partly or half resolved. Both describe the same facts: the step timeout yields a failed step (source read) and the scenario in flight is not kept.
- **P1R1-4 status:** penetration-tester and tdd-guide say resolved; the other four qualify it to the keep branch because the unset branch still aborts with no verdict (pre-existing).
- **How to fix the empty archive:** gate-step `id` plus `steps.<id>` condition (code-reviewer, silent-failure-hunter), `test -d … && tar …` (penetration-tester), `tar … || { [ -d … ] || rm -f …; false; }` (security-reviewer), a guard or `test -d` step (tdd-guide). Only security-reviewer's keeps the line starting with `tar` for the current harness regex; the others need the harness pins changed in the same commit. Pick one together with the step-parsing test.
- **`ci.yml` mutant tallies differ** (10 of 17, 14 of 15, 11 of 11, 11 of 21 survive): different mutant sets, same conclusion; no contradiction on any single mutant.
- **Full-tree figures:** 1445 files (fixer), 1448 (code-reviewer, security-reviewer), 1443 (tdd-guide); tar size 310,568 to 313,457 bytes. Run-to-run variance; no reviewer treats it as a defect.

## Recommended Changes (Prioritized)

1. Disposition the 21 open questions.
2. Owner: restore `~/.config/systemd/user/blast-off@.service` from the saved original and `systemctl --user daemon-reload` (see Notes), before deleting any `/tmp/bo-r2*` dir.
3. Stop the tar step leaving an archive when the keep dir is missing, and correct the `ci.yml:50-51` comment.
4. Replace the substring greps in `tests/00-harness.sh:75-80` with per-step assertions (parsed YAML or whole-line matches with order), tolerant of a third failure step and of `failure() || cancelled()`.
5. Push and force one deliberately red CI run; check the artifact holds `blast-off-tests.tgz` with `22-dirty-tree/cwd/`; check one green run and one re-run attempt.
6. Loop the refusal test over `bin/k`, `lib/k`, `tests/k` and bare `tests`.
7. Reword `ci.yml:4-5` to "every finished scenario", and the spec row and harness comment to what the tests prove.
8. Decide `timeout -k` (or a TERM trap) for the scenario in flight.
9. On a failed keep, leave `$work` and print its path; guard `realpath` with `|| no_keep`; check `[ -w ]` up front.
10. Tighten the remaining test gaps: passing `out` content, default keep dir when unset, the `rm` half, a `-k` value.
11. Set `retention-days` and a per-attempt artifact name; decide `archive: false`.
12. Separate changes: a lock in `tests/lib.sh` `install_units`/`restore_units`; count-and-continue on the unset branch; SHA-pin the actions; the pre-existing P1R1-28, -29, -30.

## Open Questions for the Author

- What observed result on a runner counts as proof of the tar-and-upload fix, and does the merge wait for one deliberately red run? — Disposition: PENDING
- Which properties of the CI wiring is the `00-harness` `ci.yml` block meant to guarantee? — Disposition: PENDING
- Is a floating major tag (`@v7`, `@v4`) the accepted pin policy for this repo? — Disposition: PENDING
- Why is "no verdict line" fixed for the keep branch and left on the unset branch every local gate takes? — Disposition: PENDING
- Is the `docs/spec.md:215` row a test inventory or a contract (three dirs, "unset leaves no work dir", "the file the upload step names")? — Disposition: PENDING
- For a hung gate, which scenario's logs does the reader of the artifact need? — Disposition: PENDING
- What should a reader find when the job failed before `tests/run` started (today: an empty artifact)? — Disposition: PENDING
- Is executing the workflow's `run: tar …` text as shell in the local gate the intended design? — Disposition: PENDING
- Who is expected to learn of the format pins (exactly two `if: failure()` lines, one-line `run: tar`) before phase 2 edits `ci.yml`? — Disposition: PENDING
- Does `failed=` still mean scenarios, now that a keep failure is counted on top? — Disposition: PENDING
- Why is an uncreatable keep dir refused before any scenario and an unwritable one only after every scenario? — Disposition: PENDING
- Is "nothing stays in TMPDIR" after a failed keep a promise or a best effort? — Disposition: PENDING
- What happens to `blast-off receipt` when blast-off builds itself with an in-repo keep dir (`lib/receipt.sh:27-28`)? — Disposition: PENDING
- Where is the downloaded artifact meant to be unpacked, given names that cannot exist on NTFS? — Disposition: PENDING
- What failure is the 25-minute step timeout sized for? — Disposition: PENDING
- Is GNU coreutils (`realpath -m`) a stated requirement of `tests/run`? — Disposition: PENDING
- Is "not in TMPDIR" the same claim as "removed" for criterion 1's unset half (P1R1-13)? — Disposition: PENDING
- What does the upload step do on attempt 2 after attempt 1 uploaded `blast-off-tests` (P1R1-22)? — Disposition: PENDING
- Has the full kept tree been checked for content that should not be published? — Disposition: ANSWERED — six canary values on a full 18-scenario keep run matched 0 files, log lines, `.git` objects and nested-tar entries, and no scenario copies `$REPO/.git`, per security-reviewer, `tests/lib.sh:10`
- What retention should the artifact have, now that it carries every `.git` (P1R1-20)? — Disposition: PENDING
- Do the `baton-runner/` files belong in the PR for issue 30 (P1R1-27)? — Disposition: PENDING
- Does this change help the green diagnostic run that prompted issue 30, and what becomes of the other 17 round-1 open questions? — Disposition: PENDING
- Which of the unchanged round-1 items (P1R1-14, -16, -17, -18, -25, -28, -29, -30) are accepted limits, and where is that recorded? — Disposition: PENDING
- Is a full keep run on a quiet box wanted before the next unit relies on the kept-tree figures? — Disposition: PENDING

## Notes

- The six rostered reviewers are parked only (`~/.claude/agents-parked/`), as in round 1; each ran as a `general-purpose` agent told to read its parked definition and adopt it, read-only, not as a registered `subagent_type`. The skill's own rule for a parked-only name is to hard-fail or ask for activation; this run deviated from it, on the caller's instruction, and says so here.
- The review ran inline inside a baton-runner review unit that is itself a subagent (no orchestrator layer), although `--inline` was not passed; `--yes` is a no-op on a `spec` target; `--high-cap off` was passed because the report feeds a gate.
- The round-1 findings and the fix's claims were given to every reviewer inside the MATERIALS block, not through `--prompt-prelude`.
- Reviewer checkpoints are in `baton-runner/br-1115-issues/review-phase-1-iter-2/` in the worktree, not the primary checkout's `.claude/reviews/` (the unit may write only under `baton-runner/br-1115-issues/`).
- Side effect of this review, reported by four reviewers (code-reviewer, penetration-tester, security-reviewer, tdd-guide) and confirmed by the dispatching unit at 17:46 PST: several reviewers ran the full suite on /tmp copies at the same time, `tests/lib.sh` `install_units`/`restore_units` raced, and the owner's installed `~/.config/systemd/user/blast-off@.service` now reads `ExecStart=/tmp/bo-r2.Bvv2iW/full/bin/blast-off run %f`. The original (sha256 36a57b047f79e0634b11b913d912f0a3712d200f6e72550e38666fab024697fa, `ExecStart=/home/alex/blast-off/.worktrees/blast-off-build/bin/blast-off run %f`) is saved at `/tmp/bo-r2.Bvv2iW/rt/blast-off-tests/11-unit-smoke/cwd/units-saved/blast-off@.service` and `/tmp/bo-r2-keep.As4kiZ/rt/blast-off-tests/11-unit-smoke/cwd/units-saved/blast-off@.service`. Nobody repaired it (outside every agent's write scope); the owner must restore it. The reviewer briefs allowed one full-suite run each; they should have allowed none.
- Containment slips reported by reviewers: code-reviewer and security-reviewer each had a mutant create a dir under `~/.cache` (both removed it); critical-thinking's `pgrep -f` loop killed its own shell twice and left fixture processes it then stopped by pid. Scratch dirs left under `/tmp` are listed in the reviewer outputs.
- silent-failure-hunter reports its advisor tool was rate-limited. Nobody executed the upload-artifact bundle (by instruction); every statement about the action is from source.
- The Executive Summary's "21 open questions are PENDING" counts the PENDING bullets as first drafted; the Open Questions list above holds 24 bullets, 23 PENDING and 1 ANSWERED. Read 23 for 21 in the summary and in Recommended Changes item 1.

## Report Audit

Task: audit the round-2 synthesized report (review-phase-1-iter-2.md) against the six reviewer outputs; return only the body of a `## Report Audit` section.

No reviewer filed a CRITICAL or HIGH, so the empty Critical and High buckets are faithful, and no merged row is rendered below or above the highest severity filed for it. The Executive Summary counts reconcile with the sections (6 MEDIUM rows, 37 LOW rows, 23 PENDING, 1 ANSWERED). The seven-row round-1 status table matches each reviewer's stated status. Five discrepancies, none touching the CRITICAL or HIGH count:

1. **A reviewer finding reached no section (class 6).** No line of the report says a cancel or a job timeout still uploads nothing (the only matches for "cancel" are the `failure() || cancelled()` pin, the `Canceled` task result, and a recommendation).
   - Report, P1R1-6 merged status: "partly resolved; critical-thinking and silent-failure-hunter say reshaped (the hung scenario is not in the artifact)".
   - Source, tdd-guide L7 (LOW, "Still open from round 1"): "Cancel or job timeout uploads nothing (P1R1-6 remainder)."
   - Source, code-reviewer P1R1-6 row: "Still true: a cancel or job timeout uploads nothing, and the scenario in flight is never kept."
   - Source, silent-failure-hunter P1R1-6 row: "Cancel and job timeout still upload nothing (recorded in ci.yml)."
   - penetration-tester L1 says the same. The step-timeout MEDIUM row covers only the scenario in flight.

2. **An Open Question is marked ANSWERED on a citation that does not settle it (class 4).**
   - Report: "Has the full kept tree been checked for content that should not be published? — Disposition: ANSWERED — six canary values on a full 18-scenario keep run matched 0 files … per security-reviewer, `tests/lib.sh:10`".
   - Source, security-reviewer Validated: "I exported six canary values. Four reach scenarios unmodified … The `GH_TOKEN` and `OPENROUTER_API_KEY` canaries prove nothing: every scenario exports a dummy `GH_TOKEN` and `tests/lib.sh:10` unsets the other."
   - The cited line is the reviewer's reason one canary proves nothing, not evidence that the tree was checked. The same reviewer's L21 also reports kept files naming `/home/<user>` and the hostname.
   - Under the template rule ("an answer with no citation stays PENDING") this entry is PENDING. That makes 24 PENDING, not the 23 in the Executive Summary and in Recommended Changes item 1. The recommended action (merge-with-fixes) is unaffected.

3. **Coverage inflation on the secret scan (class 5).**
   - Report, Confirmed: "No secret reaches the kept tree: six canary values on a full 18-scenario keep run, 0 matches in files, log, `.git` objects and the nested `.tgz` (security-reviewer)".
   - Report, Examined inconclusive: "the canary runs above cover it."
   - Source, security-reviewer: four effective canaries; two "prove nothing" (quoted in item 2).
   - Source, penetration-tester Not examined: "Scenarios 11 and 31 with a keep dir and canary values. I left them out on purpose … Scenario 11 passes `--setenv=GH_TOKEN` to a unit … so nobody has value-scanned these two."
   - The report's Not examined list omits that entry, and the only run that covers scenarios 11 and 31 is the one whose `GH_TOKEN` canary its own author discounts.

4. **Coverage attribution overstated (class 5).**
   - Report, Confirmed: "`00-harness` alone passes on `git archive HEAD` copies: `GATE: PASS passed=1 failed=0 shellcheck=skipped` (all six)."
   - Source: the baseline line is stated by code-reviewer ("`00-harness` alone passes in the copy (0.22 s)"), penetration-tester, silent-failure-hunter ("Baseline … 0.23 s") and tdd-guide.
   - The critical-thinking and security-reviewer outputs contain no 00-harness-alone baseline statement (no "baseline" line in critical-thinking's output; security-reviewer reports the full 18-scenario gate and mutant totals). Four reviewers, not six.

5. **One sub-finding lost in a merge (class 6, minor).**
   - Source, silent-failure-hunter L4 survivors: "`rm -rf "$work" || true` on the unset path" (the test does not notice a failed cleanup being ignored when the var is unset).
   - Report: the only `|| true` rows are the failed-keep branch ("`rm -rf "$work" \|\| true` after a failed keep can leave the work dir …"). The "Unset path" LOW row describes the abort behaviour, not this surviving mutant. The other four L4 survivors each reached a row.
