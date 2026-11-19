---
source: runner
scope: br-1115-issues
parent_session: ""
---
# Pass-Baton: phase 1 work unit, issue 30 (tests/run keep dir) implemented, gate green

**Date:** 2026-11-15
**Scope:** br-1115-issues
**Branch:** feat/br-1115-issues/phase-1
**Worktree:** /home/alex/blast-off/.claude/worktrees/pending-items-53932d
**HEAD:** d5172eb Merge pull request #33 from z0rd0n88/chore/gate-script (changes uncommitted; the manager owns git)

## Where things stand

All four acceptance criteria of issue 30 are met and the full gate passes. Nothing is committed. No new dependency.

Files changed (tracked):
- `tests/run`: header documents `BLAST_OFF_TEST_KEEP`; the keep dir is made and made absolute before the loop; the var is unset so scenarios never see it; per scenario the work dir is moved to `<keep>/<name>` (stale one cleared first), else removed as before.
- `tests/00-harness.sh`: new block after the empty-fixture check (fixture `keepfix`, pinned `TMPDIR`).
- `.github/workflows/ci.yml`: step-level `env: BLAST_OFF_TEST_KEEP: ${{ runner.temp }}/blast-off-tests` on the `tests/run` step; new last step `actions/upload-artifact@v4` with `if: failure()`.
- `docs/spec.md`: section 6 `00-harness` row names the new behaviour. The spec does not document tests/run env vars, so nothing else there.

Untracked, planning only: `baton-runner/br-1115-issues/phase-1/{task_plan,findings,progress}.md`, this file.

## Evidence

RED (test written first, `tests/run` unchanged; `BLAST_OFF_NO_SHELLCHECK=1 tests/run <dir with a symlink to 00-harness.sh>`):

```
FAIL 00-harness
  | FAIL: keep fixture verdict: FAIL 01-ok
  | FAIL 02-bad
  |   | boom
  | GATE: FAIL passed=0 failed=2 shellcheck=skipped
GATE: FAIL passed=0 failed=1 shellcheck=skipped
exit=1
```

That red is the isolation assertion (the fixture saw the var). The other assertions were shown red by reverting one piece of the implementation at a time, then restoring it:

```
--- keep branch only removes (no mv)
  | FAIL: failed scenario's output not kept: kept:
--- unset branch leaves the work dir (no rm)
  | FAIL: work dirs left with BLAST_OFF_TEST_KEEP unset: tmp.ktybDsk0xQ
  | tmp.yPKwlw7Uzk
--- no clearing of a stale kept dir
  | FAIL: second run nested into the kept dir: kept: ... kept/01-ok/tmp.6FabPAIa5N ...
```

The "unset removes work dirs" half was green before the change too (existing behaviour); the middle mutation above is what shows the assertion can fail.

GREEN:
- single scenario: `PASS 00-harness` / `GATE: PASS passed=1 failed=0 shellcheck=skipped`, with the var unset and with it set in the outer env (keep dir then held only `00-harness`, no fixture dirs).
- full gate, var unset: `GATE: PASS passed=18 failed=0 shellcheck=ok` (33 files shellchecked).
- full gate, `BLAST_OFF_TEST_KEEP=<dir>` (the CI configuration): same verdict; 18 subdirs, one per scenario, 8.4M, no sockets or FIFOs, no file names with `":<>|*?`.
- `python3 -c 'import yaml...'` parses ci.yml; last step has `if: failure()`.

## Next steps

1. Review unit: `git diff` in the worktree (4 tracked files), then `scripts/gate.sh` or `tests/run`.
2. Manager: commit the 4 tracked files, PR with `Closes #30`.

## Open questions / risks

- The upload step has not run on GitHub (no push allowed here). It only runs on an already-red job, so a mistake in it cannot turn a green run red. `include-hidden-files` is left at its default (false): on the kept tree of the full KEEP run, `find <keep> -path '*/.*' -type f -not -path '*/.git/*'` printed nothing, so only `.git` contents are left out of the artifact. `if-no-files-found` is at its default (warn). The last gate run predates the removal of one `with:` line from ci.yml; no test reads ci.yml (`grep -rl 'ci\.yml' tests/` is empty) and the YAML was re-parsed.
- A relative `BLAST_OFF_TEST_KEEP` resolves against the caller's cwd.
- Kept dirs are mode 0700 (from `mktemp -d`); fine for the same runner user.

## References

- Issues: z0rd0n88/blast-off #30
- Code: `tests/run:7-8,17-21,33-34`, `tests/00-harness.sh:22-38`, `.github/workflows/ci.yml:34-48`, `docs/spec.md:215`
- Plan: `baton-runner/br-1115-issues/phase-1/task_plan.md`
