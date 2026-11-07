# shellcheck shell=bash
# chain.sh: the loop. Relaunch children until checkpoint status is done or blocked.
# A crashed, killed or timed-out child costs only the work since its last checkpoint.

# chain_end <code> <message>: the runner's only exits that report a state (spec §3).
chain_end() { CHAIN_END=1; log "$2"; exit "$1"; }

# The EXIT trap. Child scopes sit outside the runner's cgroup, so no exit of the runner (state,
# set -e abort, signal) reaches them unless this does; JOB_KEEP_WINDOWS leaves everything for
# inspection. An exit chain_end did not make is logged, and an abort's own status (a failed sed
# exits 4, the cap code) becomes 1 so it never reads as a state; a signal's 128+n stands.
# Signals are ignored from here on (owner Q6): a second one would exit inside this trap, skip
# kill-server and replace the status. The scope stop and the unit's TimeoutStopSec bound the wait.
chain_exit() {
  local rc="$1"
  trap '' HUP INT TERM
  [ -n "${JOB_KEEP_WINDOWS:-}" ] || child_stop_all
  [ -z "${CHAIN_END:-}" ] || return 0
  log "runner exit $rc without a state; its error is on stderr (the journal under the unit)" || true
  [ "$rc" -ge 128 ] || exit 1
}

chain_run() {
  [ -n "${CLAUDE_FLAGS:-}" ] || die "CLAUDE_FLAGS is unset or empty; every child needs --model and --effort (K8, D8)"
  local b; for b in claude tmux python3 systemd-run systemctl; do command -v "$b" >/dev/null || die "$b not on PATH"; done
  test -s "$JOB/brief.md" || die "missing $JOB/brief.md"
  test -s "$JOB/checkpoint.md" || die "missing $JOB/checkpoint.md"
  TIMEOUT="${JOB_CHILD_TIMEOUT:-7200}"
  local maxc="${JOB_MAX_CHILDREN:-12}" n=0 stalls=0 s before

  # The child's whole instruction. The brief and checkpoint carry everything else, so this stays
  # constant and the chain never depends on a hand-written handoff.
  # shellcheck disable=SC2034  # read by child_launch
  PROMPT="Continue the job in $JOB. Read $JOB/checkpoint.md first, then $JOB/brief.md, then follow the brief's Child protocol section exactly. Work from $WORKDIR."

  # Bash runs the EXIT trap on HUP and INT by itself, but with a stale $?; their traps pass the
  # signal's status to chain_exit so run.log records it.
  trap 'chain_exit $?' EXIT
  trap 'log "runner stopped by signal; stopping child scopes"; exit 143' TERM
  trap 'exit 129' HUP
  trap 'exit 130' INT
  child_server

  while :; do
    s="$(cp_status)"
    case "$s" in
      done)    chain_end 0 "job done" ;;
      blocked) chain_end 3 "job blocked; see $JOB/checkpoint.md" ;;
    esac
    n=$((n+1)); [ "$n" -le "$maxc" ] || chain_end 4 "child cap $maxc reached"
    before="$(cp_fingerprint)"

    child_launch "$n"
    if child_wait; then
      child_report "$n"
      child_stop
    else
      log "child $n timed out after ${TIMEOUT}s; killing it, next child resumes from checkpoint"
      child_stop force
    fi

    if [ "$(cp_fingerprint)" = "$before" ]; then
      stalls=$((stalls+1)); log "child $n left checkpoint.md unchanged (stall $stalls/2)"
      [ "$stalls" -lt 2 ] || chain_end 5 "two stalls; stopping"
    else
      stalls=0
    fi
  done
}
