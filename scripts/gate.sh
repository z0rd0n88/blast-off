#!/usr/bin/env bash
# scripts/gate.sh <log-dir>: the objective gate a zord-baton-runner review unit runs. It runs this
# repo's own gate, tests/run (every scenario, or those BLAST_OFF_TEST_ONLY names, then shellcheck),
# tees the output to <log-dir>/tests-run.log and exits with tests/run's status; the last line is its
# GATE: (GATE-ONLY: under BLAST_OFF_TEST_ONLY) PASS|FAIL verdict.
set -euo pipefail
dir="${1:?usage: scripts/gate.sh <log-dir>}"
mkdir -p "$dir"
dir="$(cd "$dir" && pwd)"
cd "$(dirname "$0")/.."
tests/run 2>&1 | tee "$dir/tests-run.log"
