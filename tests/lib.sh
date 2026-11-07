# shellcheck shell=bash
# tests/lib.sh: helpers every scenario sources. Scenarios run with cwd = a fresh temp dir and
# REPO = the repo root (exported by tests/run). Names of any tmux session or unit a scenario
# creates start with $TEST_ID so a scenario never touches what it did not start.
set -euo pipefail
: "${REPO:?run scenarios through tests/run}"
TEST_ID="blast-off-test-$$"
export TEST_ID

fail() { echo "FAIL: $*" >&2; exit 1; }
