---
source: runner
scope: br-1115-issues
parent_session: ""
---
# Pass-Baton: phase 2 work unit, issue 31 (`only` dispatch input, filtered tests/run) implemented

**Date:** 2026-11-15
**Scope:** br-1115-issues
**Branch:** feat/br-1115-issues/phase-2
**Worktree:** /home/alex/blast-off/.claude/worktrees/pending-items-53932d
**HEAD:** e35e47f chore(phase-1): zord-baton-runner STATE + log update (changes uncommitted; the manager owns git)

## Where things stand

All four acceptance criteria of issue 31 are implemented. The four scenarios that touch the change (00-harness, 40-receipt-required, 51-templates, 70-docs) pass one at a time, and `shellcheck -S warning` is clean on the three changed scripts. The full gate passes on this tree (see "Full gate" below). No new dependency. Nothing committed, pushed or dispatched; the workflow was only parsed locally with PyYAML.

Files changed (tracked, 5):
- `tests/run`: new env `BLAST_OFF_TEST_ONLY="<name>..."` (header documents it). Names are split on spaces, commas and newlines, compared as text to scenario basenames (never globbed, never made into a path), and the var is unset before any scenario. A name that is no scenario prints `FAIL only <name>: no such scenario in <dir>` and counts as a failure; matched names still run. A filtered run's verdict line is `GATE-ONLY: PASS|FAIL passed=N failed=N shellcheck=X only=<names joined by commas>`. Set but empty (or only separators) is the whole suite with the unchanged `GATE:` line. Shellcheck still runs on a filtered run of the real suite.
- `tests/00-harness.sh`: new block after the empty-fixture check (fixture `onlyfix`); one new pin in the ci.yml block: the line `BLAST_OFF_TEST_ONLY: ${{ inputs.only }}` exists and `inputs.` occurs exactly once in ci.yml.
- `tests/40-receipt-required.sh`: after the "no log / no verdict line" cases, a real filtered `tests/run` on a fixture writes `gate-logs/phase-8.log`; `blast-off receipt` must exit 1, write no `phase-8.json`, and log `receipt refused: the last line of ...phase-8.log is not a GATE: verdict`.
- `.github/workflows/ci.yml`: `workflow_dispatch.inputs.only` (string, default `""`); one more line in the gate step's existing `env:` block, `BLAST_OFF_TEST_ONLY: ${{ inputs.only }}`; header comment. The `run:` script is untouched. Phase 1's pins (two `if: failure()`, the one-line `run: tar`, the two literals) are untouched.
- `docs/spec.md`: section 6 intro sentence (line 206) and the `00-harness` row name the new behaviour.

`lib/receipt.sh` is unchanged: `receipt_verdict` already demands a last line starting `GATE: `, and `GATE-ONLY: ` does not, so the receipt is refused with nothing written (a line starting `GATE: ` that is not `GATE: PASS` would have had a FAIL receipt written, which is why the prefix differs for PASS and FAIL alike).

Untracked, planning only: `baton-runner/br-1115-issues/phase-2/{task_plan,findings,progress}.md`, this file.

## Evidence

RED 1 (criteria 1 to 3: the filter itself, which criterion 1's input drives, the verdict line and the receipt refusal; both tests written first, `tests/run` unchanged; `BLAST_OFF_NO_SHELLCHECK=1 tests/run <dir with symlinks to 00-harness.sh and 40-receipt-required.sh>`):

```
FAIL 00-harness
  | FAIL: one named scenario exited non-zero: FAIL 01-a
  | PASS 02-b
  | FAIL 03-c
  |   | boom
  | GATE: FAIL passed=1 failed=2 shellcheck=skipped
FAIL 40-receipt-required
  | FAIL: receipt on a filtered run's log: exit 0: 2026-11-16T02:04:31Z receipt phase 8: GATE: PASS passed=1 failed=0 shellcheck=skipped at ebf6cad54773ac0a0f8c9f871af7d243690a8fec
  | PASS 01-ok
  | GATE: PASS passed=1 failed=0 shellcheck=skipped
GATE: FAIL passed=0 failed=2 shellcheck=skipped
rc=1
```

The second failure is the issue's caution reproduced: a one-scenario run was receipted as a PASS.

RED 1b (first implementation split with `IFS=', ' read`, which yields an empty name for `' , '`; the test caught it):

```
FAIL 00-harness
  | FAIL: only=' , ': FAIL only : no such scenario in /tmp/tmp.uk5EKzQdM6/cwd/onlyfix
  | GATE-ONLY: FAIL passed=0 failed=1 shellcheck=skipped only=
PASS 40-receipt-required
```

Fixed by turning commas into spaces and splitting on whitespace (`read -rd '' -a`, so a name on a second line is not dropped silently).

RED 2 (criterion 1, the workflow side only; ci.yml pin written first, `tests/run` done, ci.yml unchanged):

```
FAIL 00-harness
  | FAIL: ci.yml does not pass inputs.only to tests/run as env BLAST_OFF_TEST_ONLY, and nowhere else
PASS 40-receipt-required
GATE: FAIL passed=1 failed=1 shellcheck=skipped
rc=1
```

GREEN (after ci.yml and spec; four scenarios through the symlink dir):

```
PASS 00-harness
PASS 40-receipt-required
PASS 51-templates
PASS 70-docs
GATE: PASS passed=4 failed=0 shellcheck=skipped
rc=0
```

YAML parsed locally (`yaml.safe_load`): `on.workflow_dispatch` = `{'inputs': {'only': {'description': ..., 'type': 'string', 'default': ''}}}`; the gate step's env = `{'BLAST_OFF_TEST_KEEP': '${{ runner.temp }}/blast-off-tests', 'BLAST_OFF_TEST_ONLY': '${{ inputs.only }}'}`; its `run` text is byte-identical to before.

Hand probe, a newline-separated value: `BLAST_OFF_TEST_ONLY=$'01-a\n09-x'` gives `PASS 01-a`, `FAIL only 09-x: no such scenario in ...`, `GATE-ONLY: FAIL passed=1 failed=1 shellcheck=skipped only=01-a,09-x`.

## Full gate

One full `tests/run` on the final tree (no other suite running), exit 0:

```
PASS 00-harness
PASS 10-chain-done
PASS 11-unit-smoke
PASS 12-start-env
PASS 20-dead-child
PASS 21-soft-cap
PASS 22-dirty-tree
PASS 23-runner-lock
PASS 30-paused-limit
PASS 31-resume-after-reset
PASS 32-usage-per-phase
PASS 40-receipt-required
PASS 41-ci-wait
PASS 50-checkpoint-size
PASS 51-templates
PASS 60-preflight
PASS 61-jev-pick
PASS 70-docs
PASS shellcheck (33 files)
GATE: PASS passed=18 failed=0 shellcheck=ok
```

After it, `grep ^ExecStart ~/.config/systemd/user/blast-off@.service` prints
`ExecStart=/home/alex/blast-off/.worktrees/blast-off-build/bin/blast-off run %f`: the owner's unit still names the build worktree.

The path a CI dispatch takes (the real suite dir, filter, lint, verdict), run once after the full gate, alone: `BLAST_OFF_TEST_ONLY=70-docs tests/run`, exit 0 (70-docs starts no unit and no tmux session):

```
PASS 70-docs
PASS shellcheck (33 files)
GATE-ONLY: PASS passed=1 failed=0 shellcheck=ok only=70-docs
```

`ExecStart` read again after it: unchanged.

## Next steps

1. Review unit: `git diff` in the worktree (5 tracked files above), against issue 31 (`gh issue view 31`).
2. Manager: commit the 5 tracked files; the planning files and this note per the runner's convention.

## Open questions / risks

- Never run on GitHub: the `only` input and the env line are checked by a local YAML parse and a text pin only. On `pull_request` the `inputs` context is empty, so the var is exported as `''`, which the 00-harness block pins as a full run.
- A filtered CI run that passes shows a green check on the dispatch run. Its log ends `GATE-ONLY: PASS`, but the check colour does not differ from a full gate's. Dispatch runs are not PR checks, so nothing gates on it; not changed (outside the criteria).
- Decisions the reviewer may want to challenge (all in `phase-2/task_plan.md`): matched scenarios still run when another name is unmatched (the run fails by name at the end, not before the first scenario); a name with a `.sh` suffix is not accepted (fails by name); shellcheck still runs on a filtered real-suite run; a value of only separators counts as empty (full suite, `GATE:` line).
- `docs/spec.md:227` (the `40-receipt-required` row) does not name the new assertion; the `00-harness` row points to test 40 instead.
- The issue's second caution stands: a timing-dependent failure may not reproduce with one scenario alone. The ci.yml header calls a filtered run a diagnosis.

## References

- Issues: z0rd0n88/blast-off issue 31
- Docs: `baton-runner/br-1115-issues/digest-phase-1.md`, `baton-runner/br-1115-issues/phase-2/task_plan.md`, `docs/spec.md` §6
- Code: `tests/run:11-16` (header), `tests/run` filter before the loop and verdict at the end, `lib/receipt.sh:6-9`
