# Digest: phase 1 (issue 30), reviewed CLEAN at 97a4ebe on 2026-11-15

## Public surface added

- `BLAST_OFF_TEST_KEEP=<dir>` for `tests/run` (`tests/run:7-10,19-30,44-47`): each scenario's work dir is moved to `<dir>/<name>` (`out` = captured output, `cwd/` = what it left). A `<dir>/<name>` already there is replaced. Unset or empty: work dirs are removed as before.
- `tests/run` unsets the var before any scenario runs (`:21`), so a scenario that calls `tests/run` never sees it.
- Refusals before any scenario, each with a verdict line: `<dir>` under `bin/`, `lib/` or `tests/` of the repo, or `<dir>` that cannot be made. Output is `FAIL BLAST_OFF_TEST_KEEP=<value>: <reason>` then `GATE: FAIL passed=0 failed=1 shellcheck=skipped` (`:25`, hard-coded).
- A work dir that cannot be kept prints `FAIL keep <name>` and adds one to `failed` on top of the scenario's own result, so `passed + failed` can exceed the scenario count.
- `.github/workflows/ci.yml:35-61`: the `tests/run` step has `timeout-minutes: 25` and `BLAST_OFF_TEST_KEEP: ${{ runner.temp }}/blast-off-tests`; two `if: failure()` steps follow: a one-line `tar` into `$RUNNER_TEMP/blast-off-tests.tgz`, then `actions/upload-artifact@v7` (artifact `blast-off-tests`, `if-no-files-found: error`).
- New dependencies: `actions/upload-artifact@v7` (tag, node24); GNU `realpath -m`, `tar`, `diff --no-dereference`.

## What `tests/00-harness.sh` pins (phase 2 edits the same files)

- Verdict lines by exact whole-line match (`grep -qx`): `GATE: PASS passed=1 failed=0 shellcheck=skipped` (`:13`), `GATE: FAIL passed=1 failed=1 shellcheck=skipped` (`:16,28`), `GATE: FAIL passed=2 failed=2 shellcheck=skipped` (`:51`), and the two refusal outputs in full (`:55-56,68`). A filtered run whose verdict differs from `GATE: PASS` must leave these unfiltered lines byte-identical, or change the test in the same commit.
- `lib/receipt.sh:6-9,31-38` reads the last `GATE:` line and copies its tally; check it against any new verdict wording.
- `ci.yml` must contain exactly two lines matching `^ *if: failure()$` (`:78`). A third failure step, `failure() || cancelled()`, or `${{ failure() }}` turns 00-harness red.
- `ci.yml` must have the tar step as one line `run: tar ...` (`:79`); the test runs every such line with `bash -c` on a fixture (`:85`), so no second one-line `run: tar` step.
- These two literals must appear verbatim (`:76-77`): `BLAST_OFF_TEST_KEEP: ${{ runner.temp }}/blast-off-tests` and `path: ${{ runner.temp }}/blast-off-tests.tgz`.
- Adding an `only:` `workflow_dispatch` input does not touch these pins by itself; passing it to `tests/run` inside the gate step is fine as long as the env block and the two later steps stay as they are.

## Decisions and conventions to honor

- The upload is one tar file, never the tree: `upload-artifact` refuses a tree holding a file name with any of `" : < > | * ? CR LF`, drops dot files and follows symlinks.
- Criterion 2 of issue 30 says upload on failure only; a green run uploads nothing. A filtered green run therefore leaves no artifact.
- `docs/spec.md:215` (the `00-harness` row) is where harness behaviour is documented; extend that row for new harness behaviour.
- One full-suite run at a time per box: `tests/lib.sh:33-46` saves and restores the owner's installed units with no lock.

## Known open at phase exit (see `baton-phase-1-review-2.md`)

- The CI steps have never run on GitHub (P1R2-3). A missing keep dir still yields an empty archive and a green upload (P1R2-1). The `ci.yml` test binds text, not steps (P1R2-2).
