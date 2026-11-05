# shellcheck shell=bash
# tests/lib.sh: helpers every scenario sources. Scenarios run with cwd = a fresh temp dir and
# REPO = the repo root (exported by tests/run). Names of any tmux session or unit a scenario
# creates start with $TEST_ID so a scenario never touches what it did not start.
set -euo pipefail
: "${REPO:?run scenarios through tests/run}"
TEST_ID="blast-off-test-$$"
export TEST_ID

fail() { echo "FAIL: $*" >&2; exit 1; }

# Fakes first on PATH. They reach a child only through the runner's own tmux server (spec §4).
use_fakes() { PATH="$REPO/tests/fakes:$PATH"; export PATH; }

# new_job <suffix> <mode>...: sets JOB to a fresh job dir under workdir ./test-<pid>-<suffix>, so the
# runner's unit, tmux socket and child scopes are named $TEST_ID-<suffix>. Each mode is one line of
# fake-mode: line n drives child n, the last line repeats (see tests/fakes/claude).
SUFFIXES=()
new_job() {
  local s="$1"; shift
  JOB="$PWD/test-$$-$s/job"; mkdir -p "$JOB"
  printf '# brief\n' > "$JOB/brief.md"
  printf '# Checkpoint: test\n\nstatus: running\nphase: 1 of 1\n\n## Next action\nnone\n' > "$JOB/checkpoint.md"
  printf '%s\n' "$@" > "$JOB/fake-mode"
  SUFFIXES+=("$s")
}

# Stop only what this scenario started: units and scopes named $TEST_ID-*, and its own tmux sessions.
cleanup() {
  systemctl --user stop "$TEST_ID-*" 2>/dev/null || true
  local s; for s in "${SUFFIXES[@]}"; do tmux -L "$TEST_ID-$s" kill-session -t "job-test-$$-$s" 2>/dev/null || true; done
}
trap cleanup EXIT
