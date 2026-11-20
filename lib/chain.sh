# shellcheck shell=bash
# chain.sh: the loop. Relaunch children until checkpoint status is done or blocked.
# A crashed, killed or timed-out child costs only the work since its last checkpoint.

# chain_end <code> <message>: the runner's only exits that report a state (spec §3).
chain_end() { CHAIN_END=1; log "$2"; exit "$1"; }
# chain_accept <done|blocked>: the end the runner accepted, `<word> <utc>`, to $JOB/runner-end by rename, before
# chain_end logs it; `wait` reads this file, never run.log, which holds child text (owner ruling P6R2-1). Each run
# deletes it once it holds the lock (chain_run), so a job that run refuses or re-opens never shows an earlier run's
# end; a run that exits before the lock leaves it, and a signal between this and chain_end leaves it with no end line.
chain_accept() { echo "$1 $(date -u +%FT%TZ)" > "$JOB/runner-end.tmp" && mv -f "$JOB/runner-end.tmp" "$JOB/runner-end"; }

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
  # after the stop: a runner that takes the lock sooner would lose its server to this kill-server (D2-4)
  [ "$(cat "$LOCK" 2>/dev/null)" != "$LOCK_ME" ] || rm -f "$LOCK" || true
  [ -z "${CHAIN_END:-}" ] || return 0
  log "runner exit $rc without a state; its error is on stderr (the journal under the unit)" || true
  [ "$rc" -ge 128 ] || exit 1
}

# One runner per job unit (D1-6): two would share the tmux server and the child scope names, and the
# second's child_server would kill the first's child, so this runs before it and before the EXIT trap.
# LOCK holds the runner's pid and start time; noclobber makes its creation atomic. The lock is held
# while that pid is alive with that start time; a dead pid or a reused one (other start time) is stale
# and taken over. No name match: a runner started through a symlink is still a runner (D2-3).
# ponytail: takeover of a stale lock is not atomic; two runners racing for one stale lock both proceed.
chain_lock() {
  LOCK="${XDG_RUNTIME_DIR:-/tmp}/$UNIT.lock" LOCK_ME="$$ $(pid_start $$)"
  (set -o noclobber; echo "$LOCK_ME" > "$LOCK") 2>/dev/null && return 0
  local pid='' start=''
  { read -r pid start < "$LOCK"; } 2>/dev/null || true
  if [[ $pid =~ ^[0-9]+$ && -n $start && $(pid_start "$pid") == "$start" ]]; then
    die "runner $pid already drives $UNIT (lock $LOCK); blast-off stop <job-dir>, or wait for it"
  fi
  echo "$LOCK_ME" > "$LOCK"
}

# pid_start <pid>: start time in clock ticks since boot (proc(5) /proc/<pid>/stat field 22, counted
# after the parenthesised comm, which may hold spaces); empty when the pid is gone.
pid_start() {
  local st; st="$(cat "/proc/$1/stat" 2>/dev/null)" || return 0
  read -ra st <<< "${st##*) }"; echo "${st[19]}"
}

# chain_dirty <when>: exit 7 when the workdir's repo has uncommitted paths checkpoint.md does not name
# (F5: a child's unexplained edits must not become the next child's). Porcelain v1 paths are relative
# to the repo root (git-status(1)); -z keeps odd names whole. A rename or copy, in the index (X) or the
# work tree (Y, `git add -N`), is followed by a field holding its old name, which is skipped.
# -uall lists untracked files one by one, so the job dir's own files (run.log) are skipped by prefix.
# A path counts as named when checkpoint.md holds it whole (cp_names), from the repo root or from the
# workdir. The porcelain goes to a file first: a failing git status must not read as a clean tree.
# ponytail: one grep per uncommitted path; an unignored cache dir of 100k files is slow and floods run.log.
chain_dirty() {
  [ -n "$TOP" ] || return 0
  local e p skip='' unnamed=() named=() st
  st="$(mktemp "${XDG_RUNTIME_DIR:-/tmp}/blast-off-status.XXXXXX")"
  git -C "$WORKDIR" status --porcelain -z -uall > "$st" || { rm -f "$st"; die "git status failed in $WORKDIR"; }
  while IFS= read -r -d '' e; do
    if [ -n "$skip" ]; then skip=; continue; fi
    [[ ${e:0:2} != *[RC]* ]] || skip=1
    p="${e:3}"
    [[ -n $JOBREL && $p == "$JOBREL"/* ]] && continue
    if cp_names "$p" || { [ "$WORKREL" != . ] && [[ $p == "$WORKREL"/* ]] && cp_names "${p#"$WORKREL"/}"; }; then
      named+=("$p")
    else
      unnamed+=("$p")
    fi
  done < "$st"
  rm -f "$st"
  if [ "${#unnamed[@]}" -eq 0 ]; then
    [ "${#named[@]}" -eq 0 ] || log "tree $1: uncommitted, named in checkpoint.md: ${named[*]}"
    return 0
  fi
  log "dirty tree $1: checkpoint.md does not name ${unnamed[*]}; git status --porcelain:"
  git -C "$WORKDIR" status --porcelain -uall >> "$LOG"
  chain_end 7 "dirty tree; commit, revert or name those paths in checkpoint.md (a name with no '/' or '.' in backticks), then run again"
}

# What the runner needs on PATH (preflight checks the same list, and gh).
DEPS="claude tmux python3 jq systemd-run systemctl git realpath"

# chain_nums: return 1 with NUMS_ERR on a JOB_* count that is not a whole number of at most 9 digits
# (P4R2-9: a longer one overflows the arithmetic, or makes the cap test an error that reads as false, so
# no cap) or has a leading zero (P5R1-4, owner Q3: shell arithmetic reads 010 as 8 and 08 as an error).
chain_nums() {
  local v
  for v in JOB_MAX_CHILDREN JOB_CAP_FACTOR JOB_CHILD_TIMEOUT JOB_USAGE_PAUSE JOB_RESUME_MARGIN JOB_API_BACKOFF; do
    [[ ${!v:-0} =~ ^(0|[1-9][0-9]{0,8})$ ]] ||
      { NUMS_ERR="$v=${!v@Q} is not a whole number of at most 9 digits with no leading zero"; return 1; }
  done
  # Jev's confidence threshold (issue 27): 0 to 1, at most 3 decimals, a leading digit (jq reads it as JSON)
  [[ ${JOB_JEV_MIN_CONF:-0.7} =~ ^(0(\.[0-9]{1,3})?|1(\.0{1,3})?)$ ]] ||
    { NUMS_ERR="JOB_JEV_MIN_CONF=${JOB_JEV_MIN_CONF@Q} is not a number from 0 to 1 with at most 3 decimals (0.7, 0.85, 1)"; return 1; }
}

# chain_cap: MAXC, CAP_WHY and CAP_SOFT (empty for the hard cap). The soft cap (F2): the checkpoint's
# phase count times JOB_CAP_FACTOR, or JOB_MAX_CHILDREN. Reaching it pauses the job (paused-cap, exit 6)
# and a re-run continues. With no Phase plan row the runner reads there is no phase count, the soft cap is
# disabled, and the cap is the hard one of phase 1 (exit 4, status kept, but a paused-cap one already reads
# running: the run sets it before the cap check, owner ruling P4R2-4). Such a job ends done only once a
# child adds its rows: ci_check wants a done row (exit 10). CAP_WHY says so at start and in preflight (P3R3-12).
chain_cap() {
  local phases; phases="$(cp_phases)"
  CAP_SOFT=1
  if [ -n "${JOB_MAX_CHILDREN:-}" ] && [ "$phases" -gt 0 ]; then
    MAXC="$JOB_MAX_CHILDREN" CAP_WHY="soft: JOB_MAX_CHILDREN"
  elif [ "$phases" -gt 0 ]; then
    MAXC=$((phases * ${JOB_CAP_FACTOR:-3})) CAP_WHY="soft: $phases Phase plan rows x JOB_CAP_FACTOR ${JOB_CAP_FACTOR:-3}"
  else
    MAXC="${JOB_MAX_CHILDREN:-12}" CAP_WHY="hard: no Phase plan row the runner reads in checkpoint.md; done is refused (exit 10) until it has one" CAP_SOFT=
  fi
}

# chain_count: LAUNCHED (children this job has launched, so the last one's number) and BASE (LAUNCHED at
# the last paused-cap -> running under the soft cap; the hard cap ignores it) from $JOB/child-count, so the
# cap and run.log's numbering survive a relaunch (issue 22), and COUNT_SAY, one line on it. No file is a
# fresh job, 0 0: deleting it is the owner's one reset (P4R2-11). Anything else but two whole numbers of at
# most 9 digits with BASE <= LAUNCHED, a dangling symlink among them (P4R1-5), returns 1 with COUNT_ERR:
# a garbled count must not reset the cap to 0, and a huge one must not wrap the counter negative (P4R1-6).
# COUNT_ERR names the file and, when it can be read, its size and the shape it wants, never the
# content: it reaches run.log, status and preflight, and a second line could forge a run.log line or a
# link show a secret (P5R1-5, owner Q5).
chain_count() {
  local f="$JOB/child-count" c
  LAUNCHED=0 BASE=0 COUNT_ERR='' COUNT_SAY="child-count: none, a fresh job; first child 1"
  [ -e "$f" ] || [ -L "$f" ] || return 0
  c="$(cat "$f" 2>/dev/null)" || {
    COUNT_ERR="cannot read $f (a dangling link, a directory, or no read permission); fix it, or delete it to count this job's children from 0 again"
    return 1; }
  [[ $c =~ ^(0|[1-9][0-9]{0,8})\ (0|[1-9][0-9]{0,8})$ ]] && [ "${BASH_REMATCH[2]}" -le "${BASH_REMATCH[1]}" ] || {
    COUNT_ERR="$f is not '<launched> <base>' ($(stat -Lc %s "$f") bytes; want two whole numbers of at most 9 digits, no leading zero, base <= launched; content not shown); fix it, or delete it to count this job's children from 0 again"
    return 1; }
  LAUNCHED="${BASH_REMATCH[1]}" BASE="${BASH_REMATCH[2]}"
  COUNT_SAY="child-count: $LAUNCHED launched, base $BASE; next child $((LAUNCHED+1))"
}
# chain_count_set: LAUNCHED and BASE to $JOB/child-count by rename, so a reboot mid-write leaves one or the other.
chain_count_set() { echo "$LAUNCHED $BASE" > "$JOB/child-count.tmp" && mv -f "$JOB/child-count.tmp" "$JOB/child-count"; }

chain_run() {
  [ -n "${CLAUDE_FLAGS:-}" ] || die "CLAUDE_FLAGS is unset or empty; every child needs --model and --effort (K8, D8)"
  local b; for b in $DEPS; do command -v "$b" >/dev/null || die "$b not on PATH"; done
  test -s "$JOB/brief.md" || die "missing $JOB/brief.md"
  test -s "$JOB/checkpoint.md" || die "missing $JOB/checkpoint.md"
  TIMEOUT="${JOB_CHILD_TIMEOUT:-7200}"
  local n stalls=0 s u before after rows w limited back=
  # under start or the resume timer only the journal reads stderr, so a refusal goes to run.log too (P4R1-2)
  chain_nums || { log "$NUMS_ERR" >&2; exit 1; }
  chain_count || { log "$COUNT_ERR" >&2; exit 1; }

  # The child's whole instruction. The brief and checkpoint carry everything else, so this stays
  # constant and the chain never depends on a hand-written handoff.
  # shellcheck disable=SC2034  # read by child_launch
  PROMPT="Continue the job in $JOB. Read $JOB/checkpoint.md first, then $JOB/brief.md, then follow the brief's Child protocol section exactly. Work from $WORKDIR."

  # Bash runs the EXIT trap on HUP and INT by itself, but with a stale $?; their traps pass the
  # signal's status to chain_exit so run.log records it.
  chain_lock
  trap 'chain_exit $?' EXIT
  trap 'log "runner stopped by signal; stopping child scopes"; exit 143' TERM
  trap 'exit 129' HUP
  trap 'exit 130' INT
  rm -f "$JOB/runner-end"  # this run has not ended the job (chain_accept); after the lock: a live runner's end stays
  child_server

  chain_cap
  log "child cap $MAXC ($CAP_WHY)"
  log "$COUNT_SAY"  # the count this run starts from: a missing file reads as a fresh job (P4R1-5)
  # Only "not a git repository" turns the dirty-tree check off; any other git failure (dubious
  # ownership, a broken repo) is an error, not a reason to skip it.
  if ! TOP="$(LC_ALL=C git -C "$WORKDIR" rev-parse --show-toplevel 2>&1)"; then
    [[ $TOP == *"not a git repository"* ]] || die "git rev-parse in $WORKDIR failed: $TOP"
    TOP=; log "workdir $WORKDIR is not in a git repo; dirty-tree check off, receipt check off"
  fi
  JOBREL="$([ -z "$TOP" ] || realpath --relative-to="$TOP" "$JOB")"
  [[ $JOBREL != ..* ]] || JOBREL=
  WORKREL="$([ -z "$TOP" ] || realpath --relative-to="$TOP" "$WORKDIR")"
  case "$(cp_status)" in
    paused-cap) [ -z "$CAP_SOFT" ] || { BASE="$LAUNCHED"; chain_count_set; }  # the soft cap's fresh allotment (P4-22a); numbering goes on
      cp_set_status running; log "status paused-cap -> running; the chain continues" ;;
    paused-limit) # before the reset nothing may start; the timer (or the owner) runs resume after it
      local until; until="$(usage_until)"
      [ -z "$until" ] || [ "$until" -le "$(date +%s)" ] ||
        chain_end 8 "still paused-limit until $(date -u -d "@$until" +%FT%TZ); nothing started"
      cp_set_status running; log "status paused-limit -> running; the reset has passed" ;;
  esac

  chain_dirty "before child 1"
  rows="$(cp_done_rows | tr '\n' ' ')"  # rows done before child 1 are not the last child's (receipt_check)
  while :; do
    receipt_check "$rows"
    s="$(cp_status)"
    # P3R5-13: mid-run a line done would refuse silently stops the rows after it being read; say so each pass
    [ "$s" = "done" ] || { u="$(cp_unread)"; [ -z "$u" ] || log "checkpoint.md $u; the Phase plan rows from there on are not read, and done is refused, until it is fixed"; }
    case "$s" in
      done)    ci_plan; receipt_all_done; ci_check; chain_accept 'done'; chain_end 0 "job done" ;;
      blocked) chain_accept blocked; chain_end 3 "job blocked; see $JOB/checkpoint.md" ;;
    esac
    n=$((LAUNCHED+1))
    # base is the soft cap's alone; the hard cap counts every child of the job and never resets (P4-22a),
    # unless the owner deletes child-count (P4R2-11)
    if [ $((n - (CAP_SOFT ? BASE : 0))) -gt "$MAXC" ]; then
      [ -n "$CAP_SOFT" ] || chain_end 4 "child cap $MAXC reached ($LAUNCHED children launched for this job, $JOB/child-count); a larger JOB_MAX_CHILDREN goes on"
      cp_set_status paused-cap; chain_end 6 "soft cap $MAXC reached; status paused-cap; run again to continue"
    fi
    # after the exits above, so no state waits on it; `& wait` lets a signal through at once
    if [ -n "$back" ]; then sleep "$back" & wait $!; back=; fi
    before="$(cp_fingerprint)" rows="$(cp_done_rows | tr '\n' ' ')"
    cp_size_warn
    jev_pick "$n"

    LAUNCHED="$n"; chain_count_set  # before the launch: a child cut off by a reboot still counts
    child_launch "$n"
    w=0 limited=; child_wait || w=$?
    case "$w" in
      0) child_report "$n"; child_stop ;;
      1) log "child $n timed out after ${TIMEOUT}s; killing it, next child resumes from checkpoint"
         child_stop force ;;
      3) child_report "$n" failed.json; child_stop force
         case "$(child_field error)" in
           rate_limit) limited="StopFailure rate_limit" ;;
           # errors that clear on their own wait JOB_API_BACKOFF (P3R2-3, a build choice; owner question P3Q7)
           overloaded|server_error|unknown) back="${JOB_API_BACKOFF:-600}"
             log "child $n ended on API error $(child_field error); next child in ${back}s, from checkpoint" ;;
           *) log "child $n ended on API error $(child_field error); next child resumes from checkpoint" ;;
         esac ;;
      *) log "child $n exited without its Stop hook after ${CHILD_AGE}s (exit ${CHILD_RC:-?}${CHILD_NOSTATUS:+; its pane is dead but neither its shell nor tmux gave a status, tmux may not have reaped it, issue #29}); its screen follows, next child resumes from checkpoint"
         child_screen; child_stop force
         [ "${CHILD_RC:-}" != "$LIMIT_EXIT" ] || limited="exit $LIMIT_EXIT" ;;
    esac
    usage_read "$(child_field session_id)"
    log "child $n usage: $USAGE"
    child_clean
    after="$(cp_fingerprint)"  # before the runner's own edit below, which is not the child's progress
    cp_mark_usage "$rows" "$USAGE"
    chain_dirty "after child $n"
    # A limit pauses the chain (F10) unless the child finished it: done and blocked are final.
    if [ -n "$limited$USAGE_OVER" ] && [[ ! $(cp_status) =~ ^(done|blocked)$ ]]; then
      usage_pause "${USAGE_OVER:-$USAGE_5H}" "${limited:+child $n hit a usage limit ($limited); }usage $USAGE${USAGE_OVER:+, at or above JOB_USAGE_PAUSE ${JOB_USAGE_PAUSE:-95}%}"
    fi

    if [ "$after" = "$before" ]; then
      stalls=$((stalls+1)); log "child $n left checkpoint.md unchanged (stall $stalls/2$([ "$w" != 2 ] || echo '; it died'))"
      [ "$stalls" -lt 2 ] || chain_end 5 "two stalls; stopping"
    else
      stalls=0
    fi
  done
}
