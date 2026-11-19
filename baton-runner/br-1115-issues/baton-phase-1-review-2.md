---
source: runner
scope: br-1115-issues
parent_session: ""
---
# Pass-Baton: phase 1 review 2, issue 30: VERDICT CLEAN (0 CRITICAL, 0 HIGH); owner's systemd unit needs restoring

**Date:** 2026-11-15
**Scope:** br-1115-issues
**Branch:** feat/br-1115-issues/phase-1
**Worktree:** /home/alex/blast-off/.claude/worktrees/pending-items-53932d
**HEAD:** 97a4ebe fix(phase-1): address review findings (iter 1)

## Owner action first (side effect of this review, not of the change)

`~/.config/systemd/user/blast-off@.service` line 15 now reads `ExecStart=/tmp/bo-r2.Bvv2iW/full/bin/blast-off run %f` (checked 17:56 PST). Several reviewers ran the full suite on /tmp copies at once and `tests/lib.sh:33-46` (`install_units`/`restore_units`, no lock) saved and restored each other's files. My reviewer briefs allowed one full-suite run each; that was my mistake. I did not repair it (outside this unit's write scope).
- Original (sha256 `36a57b04...97fa`, `ExecStart=/home/alex/blast-off/.worktrees/blast-off-build/bin/blast-off run %f`) is copied to `baton-runner/br-1115-issues/review-phase-1-iter-2/owner-units-saved/blast-off@.service`. `blast-off.slice` is byte-identical to its saved copy.
- Restore, only while no `tests/run` is running (a gate in flight that runs scenario 11 or 31 puts the stale file back over the repair): `cp /home/alex/blast-off/.claude/worktrees/pending-items-53932d/baton-runner/br-1115-issues/review-phase-1-iter-2/owner-units-saved/blast-off@.service ~/.config/systemd/user/ && systemctl --user daemon-reload`, or `blast-off install` from the checkout the owner wants.
- `owner-units-saved/` is a recovery copy, not run bookkeeping: do not commit it.
- At 17:58 PST no `tests/run` process was running and `systemctl --user list-units 'blast-off*' --all` showed only `blast-off.slice` (active): no reviewer unit was left behind.

## Where things stand

**VERDICT: CLEAN** by the contract's rule: gate exit 0, the synthesized report has 0 CRITICAL and 0 HIGH, and every acceptance criterion is met. It is not a clean bill: 6 MEDIUM and 39 LOW are open, and the CI half has still never run on GitHub. No product code was changed by this unit. Digest written: `baton-runner/br-1115-issues/digest-phase-1.md`.

- Gate: `scripts/gate.sh` exit 0, `GATE: PASS passed=18 failed=0 shellcheck=ok`. Log: `baton-runner/br-1115-issues/gate-phase-1-iter-2/tests-run.log`. It finished before any reviewer was dispatched.
- Review report: `baton-runner/br-1115-issues/review-phase-1-iter-2.md` (`Reviewers: 6/6 returned`, `Reviewed at: 97a4ebe8ee70581ea9c5182552ba74a464869644`, ends with `## Report Audit`). Verbatim reviewer outputs: `baton-runner/br-1115-issues/review-phase-1-iter-2/<reviewer>.json`.
- The multi-agent review ran. Deviations (also in the report's `## Notes`): inline from this unit; the six rostered agents (critical-thinking, code-reviewer, penetration-tester, security-reviewer, silent-failure-hunter, tdd-guide) are parked only, so each ran as a `general-purpose` agent reading its parked definition, read-only, as in round 1; `--high-cap off`; `--yes` is a no-op on `spec`. Synthesizer and report auditor ran as forks.

## Acceptance criteria

| # | Met? | Evidence |
|---|---|---|
| 1 keep when set, remove when unset | yes | Test `tests/00-harness.sh:22-43`, passing in the gate log. My mutants on a /tmp copy (00-harness only, full output read): `tests/run` reverted to origin/main, kept dir without `out`, without `cwd`, no `unset`, keep only failed, `cp` for `mv`, unset branch not removing: all killed at the intended `FAIL:` line. Reviewers: full keep run `GATE: PASS passed=18`, 18 dirs each with `out` and `cwd/`; HEAD and origin/main identical on unset fixtures. |
| 2 ci.yml env + upload only on failure | yes, on paper | `.github/workflows/ci.yml:39-41` (env on the gate step), `:52-54` (tar, `if: failure()`), `:55-61` (`actions/upload-artifact@v7`, `if: failure()`). YAML parses; both steps follow the gate step. **Unproven on a runner until a red CI run**: no remote branch, 0 artifacts in the repo. |
| 3 header + spec | yes | `tests/run:7-10`; `docs/spec.md:215`. |
| 4 test proves criterion 1 both ways | yes | `tests/00-harness.sh:22-43`: 13 of 14 of my `tests/run` mutants killed, reverting `tests/run` to origin/main goes red at "keep fixture verdict"; survivor is a default keep dir when unset (P1R2-14). |

Workflow checks (step 3): `v7` tag exists, commit `cf430e030ddbb5b0abf93d22962f4752f3646cd9` = v7.0.2 (2026-10-07, latest release); `action.yml` at v7: `using: node24`; `name`, `path`, `if-no-files-found` are valid inputs; `archive` defaults `true`, so `name` applies and the download is a zip holding the `.tgz`. Runner: the v6.0.0 release notes (the major that moved to node24) say it "requires a minimum Actions Runner version of 2.327.1" and to update self-hosted runners first; v7.0.0's notes add only the move to ESM. This workflow uses GitHub-hosted `ubuntu-24.04`, which GitHub keeps current; which runner version it has today was not observed. `failure()` after a failed gate step: both steps are bare `if: failure()` and come after it. Step timeout: `actions/runner` `StepsRunner.cs:322-330` sets `TaskResult.Failed` (read, not observed). My ci.yml mutants: revert to 10d228d, revert to origin/main, tar `--exclude=.git`, `-h`, other file name, other dir name, upload `if: always()`, tar `if` removed, env removed: all killed. Survive: `@v4`, no `if-no-files-found`, no `timeout-minutes`.

## Findings (MEDIUM; none CRITICAL or HIGH)

| ID | File:line | Failure path | Suggested fix |
|---|---|---|---|
| P1R2-1 | `.github/workflows/ci.yml:50-54,61` | New in fix. With no keep dir (a step before the gate failed, or the env drifted) tar exits 2 but leaves a 45-byte, 0-member `.tgz` (I reproduced it); the upload finds one file, goes green, and `if-no-files-found: error` cannot fire. The comment "Both steps also run, and fail" is false. | Stop tar leaving the file (`tar ... \|\| { [ -d "$RUNNER_TEMP/blast-off-tests" ] \|\| rm -f ...tgz; false; }` keeps the harness's one-line pin), fix the comment, add the missing-dir case to the test. |
| P1R2-2 | `tests/00-harness.sh:71-87` (claim `:73-74`); `docs/spec.md:215` | New in fix. `grep -qF` substring matches plus a file-wide count of `if: failure()`: env commented out, moved or suffixed, upload path suffixed, upload step deleted or reordered, `@v4`, no `if-no-files-found`, no timeout all pass. "Cannot drift apart" is false. | Assert per step (parsed YAML, or whole-line matches with order): env on the gate step, tar then upload, both on failure, `with.path` = tar output, pinned `uses`. |
| P1R2-3 | `.github/workflows/ci.yml:35-61` | Open from P1R1-2. Nothing here has run on GitHub: keep path on a runner, tar step, v7 upload, `failure()`, step timeout. | Push, force one red run, check the artifact holds `22-dirty-tree/cwd/`; check one green run and one re-run. |
| P1R2-4 | `.github/workflows/ci.yml:36-38`; `tests/run:36-37,44-47` | Open from P1R1-6. A gate killed by the step timeout uploads only finished scenarios; the hung one's `out` stays in `TMPDIR` and is never printed. `timeout` has no `-k`. A cancel or job timeout still uploads nothing (the report dropped this line; audit item 1). | `timeout -k 10`, or trap TERM/INT and move `$work`; reword `ci.yml:4-5` to "every finished scenario". |
| P1R2-5 | `tests/00-harness.sh:65-69`; `tests/run:26-27`; `docs/spec.md:215` | New in fix. Refusal is tested for relative `tests/kept` only; dropping the `bin/` and `lib/` arms, the trailing slash, or symlink resolution passes. Behaviour is right by hand. (security-reviewer MEDIUM, four others LOW.) | Loop the assertion over `bin/k`, `lib/k`, `tests/k`, bare `tests`. |
| P1R2-6 | `tests/lib.sh:30-46`; `tests/11-unit-smoke.sh:13,51` | Pre-existing, outside the diff, missed by round 1. Two suites on one account corrupt the owner's installed unit (observed, see top). (tdd-guide MEDIUM, three others LOW.) | Separate change: `flock` around install-to-restore, or a per-scenario `XDG_CONFIG_HOME`. |

## Findings (LOW)

| ID | File:line | Failure path | Suggested fix |
|---|---|---|---|
| P1R2-7 | `tests/run:36,44` | Pre-existing: unset branch, an unremovable work dir or failed `mktemp` ends with no `GATE:` line; CI always takes the keep path now. | Count and continue there too. |
| P1R2-8 | `tests/run:45-46` | A failed keep deletes the fresh work dir and can leave a truncated or stale `<dir>/<name>`. | Leave `$work`, print its path. |
| P1R2-9 | `tests/run:46` | `rm -rf "$work" \|\| true` can leave the work dir with no line. | Echo the path on failure. |
| P1R2-10 | `tests/run:38,46`; `tests/00-harness.sh:51` | A keep failure is counted on top of the scenario result (`passed=2 failed=2` for 2 scenarios); `lib/receipt.sh:33` copies the tally. | Say so in the header. |
| P1R2-11 | `tests/run:28` | An existing unwritable keep dir is found only after the whole suite. | `[ -w "$abs" ] \|\| no_keep`. |
| P1R2-12 | `tests/run:45`; `tests/00-harness.sh:44-52` | The `rm` half of the keep step is untested (`rm ...; mv` survives). | Undeletable-stale-dir case. |
| P1R2-13 | `tests/run:29` | `KEEP="$abs"` unpinned (matters for values starting `-`). | One `-k` assertion or accept. |
| P1R2-14 | `tests/00-harness.sh:41-43` | P1R1-13 open: a default keep dir when unset survives (my mutant too). | Snapshot cwd around the unset run. |
| P1R2-15 | `tests/00-harness.sh:32` | A passing scenario's kept `out` content is not asserted. | Print a mark in `01-ok`, `grep -qx` it. |
| P1R2-16 | `tests/00-harness.sh:41-42` | The unset-run verdict assertion (P1R1-12) has no shown red. | One mutant. |
| P1R2-17 | `tests/00-harness.sh:78-80,85` | Format pins: exactly two `if: failure()` lines rejects `failure() \|\| cancelled()` or a third step; every one-line `run: tar ...` is run with `bash -c`; a trailing `; cmd` on that line runs too. | As P1R2-2. |
| P1R2-18 | `tests/run:26` | Missing or failing `realpath` (GNU `-m`): exit 127 or 1, no verdict. | `\|\| no_keep "cannot be resolved"`. |
| P1R2-19 | `tests/run:7-10` | Header does not say an unkept work dir is deleted. | One clause. |
| P1R2-20 | `tests/run:26` | A trailing line feed in the value is dropped. | Nit. |
| P1R2-21 | `tests/run:26-27` | A repo whose `tests/`, `bin/` or `lib/` is a symlink bypasses the refusal. | Compare against `realpath "$REPO/tests"` too. |
| P1R2-22 | `tests/run:27`; `scripts/gate.sh:9` | A keep dir elsewhere in the repo (`.`, `docs/kept`) is accepted; `lib/receipt.sh:27-28` refuses a receipt on uncommitted paths. | Header sentence. |
| P1R2-23 | `.github/workflows/ci.yml:35-38,52-54` | After a step timeout `tests/run` may run on as an orphan while tar runs (simulated only). | `exec tests/run`, or record. |
| P1R2-24 | `.github/workflows/ci.yml:53-61` | A non-zero tar exit still uploads, no marker of what is missing. | Tar stderr into the keep dir. |
| P1R2-25 | `.github/workflows/ci.yml:53,56` | P1R1-21 open: both steps fire on any earlier failed step. | See P1R2-1. |
| P1R2-26 | `.github/workflows/ci.yml:41,54,60`; `tests/00-harness.sh:76-77` | P1R1-23 open: the keep path is written four times. | See P1R2-2. |
| P1R2-27 | `.github/workflows/ci.yml:57-61` | The artifact is a zip holding a `.tgz`. | `archive: false` or `compression-level: 0`. |
| P1R2-28 | `.github/workflows/ci.yml:54-61` | P1R1-20 open: 90-day retention; the tarball now carries every `.git` (578 files). | `retention-days: 7`. |
| P1R2-29 | `.github/workflows/ci.yml:17,57` | P1R1-3 remainder: mutable tags; `checkout@v4` is node20. | Manager's call. |
| P1R2-30 | `.github/workflows/ci.yml:59` | P1R1-22 open: fixed artifact name, `overwrite: false`, re-run unverified. | `-${{ github.run_attempt }}`. |
| P1R2-31 | `tests/00-harness.sh:81-84`; `ci.yml:54` | The tarball carries refused file names (two from this fix's fixture) and absolute symlinks; cannot unpack on NTFS. | Remove `rt` and `back` at block end. |
| P1R2-32 | `tests/run:45` | Kept trees carry dead absolute paths (65 files). | Header line. |
| P1R2-33 | `tests/lib.sh:35-36` | A local kept tree holds copies of the owner's unit files and a journal extract (no secret). | Know before sharing. |
| P1R2-34 | `ci.yml:39-41`; `scripts/gate.sh:10` | CI runs only the keep path at top level, the local gate only the unset path. | Record, or one keep-set gate run. |
| P1R2-35 | `ci.yml:53,56` | Issue 30's own case (a green diagnostic run) is not served; criterion 2 says failure only. | Later `workflow_dispatch` input. |
| P1R2-36 | `ci.yml:4-5,50-51`; `docs/spec.md:215`; `tests/00-harness.sh:73-74` | Comments and spec say more than is true. | Reword after P1R2-1, -2, -5. |
| P1R2-37 | `baton-phase-1-fix-1.md`; `fix-phase-1-iter-1/tests-run-keep.log` | Fix-baton gaps: keep log byte-identical to the unset log; header says uncommitted; "fixed by test" overstates. | Record. |
| P1R2-38 | `tests/00-harness.sh:28-55` | Test blocks share `keepfix.out`, `ok.out`, `tmp`. | Optional. |
| P1R2-39 | `tests/00-harness.sh:22-56` | P1R1-14 open: timed-out scenario keep and cross-filesystem keep untested (both work by hand). | Add the timeout case. |
| P1R2-40 | `tests/run:7-10,45` | P1R1-16, -17, -18 open: "dedicated dir" unstated, stale dirs of other scenarios stay, `mv` without `-T`. | Header; `mv -T`. |
| P1R2-41 | `ci.yml:52-61` | P1R1-25 open: user journal not captured (and P1R2-17 blocks adding the step). | After P1R2-2. |
| P1R2-42 | `baton-runner/br-1115-issues/` | P1R1-27 grown: runner bookkeeping in history. | Manager's call. |
| P1R2-43 | `ci.yml:17,22`; `tests/run:51-67` | P1R1-28, -29, -30 pre-existing (no checksum, token kept, cwd-dependent lint). | Separate changes. |
| P1R2-44 | `tests/00-harness.sh:41-43` | Lost in the report merge (audit item 5): `rm -rf "$work" \|\| true` on the unset path survives. | With P1R2-7. |
| P1R2-45 (mine) | `review-phase-1-iter-2.md:207-240` | Report audit, about the report only: one open question marked ANSWERED on a citation that does not settle it (24 PENDING, not 23); the secret-scan coverage overstates (scenarios 11 and 31 were value-scanned only by the run whose `GH_TOKEN` canary proves nothing); "all six" baseline is four. | Read the audit before quoting the report. |

## Round-1 HIGH and MEDIUM status

| ID | Status at HEAD |
|---|---|
| P1R1-1 HIGH | Resolved locally (tar round trip on real kept trees, 0 lines of diff); unproven on a runner. Not open as HIGH. |
| P1R1-2 | **Open**, reshaped: P1R2-2, P1R2-3. |
| P1R1-3 | Partly: node24 confirmed; tag still mutable (P1R2-29). |
| P1R1-4 | Resolved for the keep branch (mutants killed); unset branch pre-existing (P1R2-7). |
| P1R1-5 | Resolved in code; test covers one dir of three (P1R2-5). |
| P1R1-6 | **Partly open**: step timeout gives a failed step (source read); cancel and job timeout upload nothing; hung scenario not kept (P1R2-4). |
| P1R1-7 | Resolved (stale-dir mutants die at "second run did not replace the kept dirs"). |

Round-1 LOWs: resolved P1R1-8, -9 (I re-verified both by mutant), -10, -11, -15, -19, -24 (per security-reviewer, not re-verified by me); open -13, -14, -16, -17, -18, -20, -21, -22, -23, -25, -27, -28, -29, -30; -12 fixed without a shown red; -26, -31, -32 need nothing.

## New dependencies (for the owner)

- `actions/upload-artifact@v7` (`.github/workflows/ci.yml:57`): tag-pinned, not SHA-pinned; `v7` = `cf430e030ddbb5b0abf93d22962f4752f3646cd9` (v7.0.2), `using: node24`. New in this phase (round 1 had `@v4`).
- GNU `realpath -m` in `tests/run:26`; GNU `tar` and `diff --no-dereference` in `tests/00-harness.sh:85-87`. All ship with `ubuntu-24.04`; nothing installed.

## Next steps

1. Owner: restore the unit file (top section) before deleting any `/tmp/bo-r2*` dir.
2. Manager: decide whether P1R2-1 and P1R2-2 are fixed before merge (the report recommends merge-with-fixes) and whether to force one red CI run (P1R2-3); 24 open questions in the report are PENDING.
3. Manager: in every later review unit's brief, tell reviewers not to run the full suite (scenario 00-harness or fixture dirs only, on /tmp copies); only the unit's own gate runs it, alone. Otherwise P1R2-6 repeats in each of the seven phases left.
4. Phase 2 (issue 31) reads `baton-runner/br-1115-issues/digest-phase-1.md` first: `tests/00-harness.sh:78-79` pins the shape of `ci.yml`.

## Open questions / risks

- critical-thinking's 25 items carry no severity and are not in the tables above; they are in the report's "Unstated Assumptions and Open Questions" section. The one with no twin among the findings: the 25-minute step timeout has no stated basis (it equals five 300 s scenario timeouts; two past runs are the only sample).
- Every reviewer's full keep run overlapped another suite; no full keep run on a quiet box exists at HEAD. The gate log covers the unset path only.
- Nobody executed the upload-artifact bundle; every statement about the action is from source.
- Reviewer slips: two mutants created dirs under `~/.cache` (removed by the reviewers); scratch dirs are left under `/tmp` (`bo-r2.*`, `bo-r2-keep.As4kiZ`, `bo-r2-x.PNzY9U`, mine: `bo-r2-mut.9pglh6lg`, `bo-r2-own.*`), some with mode 555 dirs.

## References

- Issues: z0rd0n88/blast-off #30 (no open PR for this branch)
- Gate log: `baton-runner/br-1115-issues/gate-phase-1-iter-2/tests-run.log`
- Review report: `baton-runner/br-1115-issues/review-phase-1-iter-2.md`
- Earlier batons: `baton-phase-1-work.md`, `baton-phase-1-review-1.md`, `baton-phase-1-fix-1.md`
- Code: `tests/run:19-30,44-47`, `tests/00-harness.sh:22-56,65-87`, `.github/workflows/ci.yml:35-61`, `docs/spec.md:215`
