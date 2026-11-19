# Context pack
- `tests/run` l.19-25: per scenario `work=$(mktemp -d)`, `$work/cwd` is the scenario cwd, `$work/out` the captured output, `rm -rf "$work"` after.
- `tests/00-harness.sh` l.7-20: fixture dirs ok/bad/empty, `run_gate` runs `BLAST_OFF_NO_SHELLCHECK=1 tests/run <dir>`.
- Job logs sit at `<cwd>/test-<pid>-<s>/job/run.log` (tests/lib.sh new_job): no dot dirs, so upload-artifact's default hidden-file exclusion does not hide them.
- docs/spec.md does not document tests/run env vars (no BLAST_OFF_TEST_TIMEOUT / NO_SHELLCHECK there); only the §6 `00-harness` row (l.215) names what the scenario proves.
- `receipt` needs the `GATE:` line last: tests/run must print nothing new after it.
- PyYAML 6.0.1 present.
