# shellcheck shell=bash
# tests/lib.sh: helpers every scenario sources. Scenarios run with cwd = a fresh temp dir and
# REPO = the repo root (exported by tests/run). Names of any tmux session or unit a scenario
# creates start with $TEST_ID so a scenario never touches what it did not start.
set -euo pipefail
: "${REPO:?run scenarios through tests/run}"
TEST_ID="blast-off-test-$$"
export TEST_ID
# No scenario may reach a real Jev key or route: a runner under test calls only the fake jev, with a dummy key.
unset OPENROUTER_API_KEY TYPESAFE_API_KEY JEV_BASE_URL

fail() { echo "FAIL: $*" >&2; exit 1; }

# Every directive of the systemd guide's §5 template (spec §5, docs/systemd-guide-deviations.md).
# shellcheck disable=SC2034  # read by tests 00 and 70
GUIDE_DIRECTIVES=(Description Documentation After Wants Type User Group NoNewPrivileges WorkingDirectory
  EnvironmentFile ExecStart Restart RestartSec StartLimitIntervalSec StartLimitBurst
  TimeoutStartSec TimeoutStopSec CPUQuota CPUSchedulingPolicy Nice MemoryHigh MemoryMax
  MemorySwapMax TasksMax LimitNOFILE PrivateTmp ProtectSystem ProtectHome ReadWritePaths
  StandardOutput StandardError SyslogIdentifier KillMode KillSignal FinalKillSignal WantedBy)

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

# install_units: the real `blast-off install` (unit and slice must be loaded to test them), with the
# owner's installed files saved first and put back by cleanup, so a scenario never leaves them changed.
UNITS_SAVED=
install_units() {
  local d="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user" f
  UNITS_SAVED="$PWD/units-saved"; mkdir -p "$UNITS_SAVED"
  for f in blast-off@.service blast-off.slice; do [ ! -e "$d/$f" ] || cp "$d/$f" "$UNITS_SAVED/"; done
  "$REPO/bin/blast-off" install
}
restore_units() {
  [ -n "$UNITS_SAVED" ] || return 0
  local d="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user" f
  for f in blast-off@.service blast-off.slice; do
    if [ -e "$UNITS_SAVED/$f" ]; then cp "$UNITS_SAVED/$f" "$d/$f"; else rm -f "$d/$f"; fi
  done
  systemctl --user daemon-reload
}

# Stop only what this scenario started: units and scopes named $TEST_ID-*, and its own tmux sessions.
cleanup() {
  systemctl --user stop "$TEST_ID-*" 2>/dev/null || true
  local s; for s in "${SUFFIXES[@]}"; do
    tmux -L "$TEST_ID-$s" kill-session -t "job-test-$$-$s" 2>/dev/null || true
    rm -f "${TMUX_TMPDIR:-/tmp}/tmux-$(id -u)/$TEST_ID-$s"
    # a runner killed by SIGKILL (test 11) leaves its lock behind
    rm -f "${XDG_RUNTIME_DIR:-/tmp}/$TEST_ID-$s.lock"
    rm -rf "${XDG_RUNTIME_DIR:-/tmp}/$TEST_ID-$s-child."*  # and its child dirs
  done
  restore_units
}
trap cleanup EXIT

# wait_until <seconds> <command...>: poll once a second; 0 as soon as the command succeeds.
wait_until() {
  local i n="$1"; shift
  for ((i=0; i<n; i++)); do "$@" && return 0; sleep 1; done
  return 1
}
# unit_state <unit>: ActiveState, "inactive" once a --collect unit is gone.
unit_state() { systemctl --user show "$1" -p ActiveState --value; }
is_active() { [ "$(unit_state "$1")" = active ]; }
not_active() { case "$(unit_state "$1")" in inactive|failed) return 0 ;; *) return 1 ;; esac; }
