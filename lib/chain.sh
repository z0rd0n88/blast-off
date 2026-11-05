# shellcheck shell=bash
# chain.sh: the loop. Relaunch children until checkpoint status is done or blocked.
# A crashed, killed or timed-out child costs only the work since its last checkpoint.

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

  child_server
  # systemctl stop on the runner's unit reaches only its own cgroup; the child scopes sit beside it.
  trap 'log "runner stopped by signal; stopping child scopes"; systemctl --user stop "$UNIT-child-*.scope" 2>/dev/null || true; exit 143' TERM INT

  while :; do
    s="$(cp_status)"
    case "$s" in
      done)    log "job done"; exit 0 ;;
      blocked) log "job blocked; see $JOB/checkpoint.md"; exit 3 ;;
    esac
    n=$((n+1)); [ "$n" -le "$maxc" ] || { log "child cap $maxc reached"; exit 4; }
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
      [ "$stalls" -lt 2 ] || { log "two stalls; stopping"; exit 5; }
    else
      stalls=0
    fi
  done
}
