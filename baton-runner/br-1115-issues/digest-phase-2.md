# Digest: phase 2 (issue 31), reviewed CLEAN at 5062c7d on 2026-11-15

## Public surface added

- `BLAST_OFF_TEST_ONLY="<name>..."` for `tests/run` (`tests/run:11-16,39-40,46,61-63,85-91`): runs only the named scenarios, in suite order. Names split on commas and any whitespace (space, tab, newline), compared as text to scenario basenames without `.sh`; never a glob or a path.
- A filtered run's last line is `GATE-ONLY: PASS|FAIL passed=N failed=N shellcheck=X only=<names joined by commas>`. Exit status is still 0 on a pass, 1 on a fail.
- A name that is no scenario prints `FAIL only <name>: no such scenario in <dir>` after the matched scenarios have run, and counts as one failure.
- Unset, empty, or only separators: the whole suite and the unchanged `GATE:` line.
- `tests/run` unsets the variable before any scenario (`:40`), as it does `BLAST_OFF_TEST_KEEP`. Two scenarios now call `tests/run` themselves: `00-harness` and `40-receipt-required`.
- Shellcheck still runs on a filtered run of the real suite dir, so `shellcheck=ok|fail` appears in a `GATE-ONLY:` line.
- `.github/workflows/ci.yml:12-16`: `workflow_dispatch` input `only` (string, default `""`); `:51` passes it to the gate step as `BLAST_OFF_TEST_ONLY: ${{ inputs.only }}`. The `run:` script is unchanged.
- No new dependency.

## Pins later phases must honor

- `tests/00-harness.sh:108-110`: `ci.yml` must hold the exact line `BLAST_OFF_TEST_ONLY: ${{ inputs.only }}`, and the text `inputs.` on exactly one line. A comment or a `run-name:` that says `inputs.only` turns 00-harness red; change the pin in the same commit.
- Phase 1's pins still hold: two `if: failure()` lines, one one-line `run: tar`, the two literals (see `digest-phase-1.md`).
- `lib/receipt.sh:8,31,38,60` accept only a line starting `GATE: `. Keep any new verdict wording off that prefix unless it is the gate's.
- `docs/spec.md:216` (the `00-harness` row) documents harness behaviour; row `:227` (`40-receipt-required`) does not yet name the filtered-log refusal.

## For phase 3 (issue 26: `lib/ci.sh`, `tests/41-ci-wait.sh`)

- P2R1-1, open: `ci_wait` (`lib/ci.sh:19,29`) lists runs with `gh run list --commit <sha>`, no event filter, and records `{id, name, conclusion}` (`:35-41`). A dispatch run on a PR head is listed beside the `pull_request` run, both named `ci`. Since this phase a dispatch can be one scenario and still conclude `success`, so on a head with no `pull_request` run the record reads `success` where it read `absent`; a red filtered dispatch makes `ci-wait` exit 10. Reviewers' fix: read `event` and leave `workflow_dispatch` runs out of the verdict, with a `41-ci-wait` case (`tests/fakes/gh` has no event field today).
- The repo's history has PR heads with both events (`ed18476`: 1 `pull_request`, 2 `workflow_dispatch` runs), so this is live practice, not a corner.

## Known open at phase exit (see `baton-phase-2-review-1.md`)

- A filtered pass exits 0 and `scripts/gate.sh` passes an exported `BLAST_OFF_TEST_ONLY` through (P2R1-2). Check a gate log's last line starts `GATE: `, not only the exit status.
- Test gaps with surviving mutants: the `ci.yml` pin (P2R1-3), newline split (P2R1-4), filtered real-suite run (P2R1-5), whole-word unknown-name match (P2R1-12).
- `tests/run <scenario-dir>` still prints `GATE: PASS` for a subset (P2R1-6, pre-existing).
- Nothing in phase 1 or 2's `ci.yml` changes has run on GitHub with the input (P2R1-20).
- One full-suite run at a time per box still applies: `tests/lib.sh` saves and restores the owner's units with no lock.
