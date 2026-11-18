# shellcheck shell=bash
# units.sh: the systemd side. One naming rule for every job: the runner unit is
# blast-off-<name>.service (<name> = workdir basename), its children blast-off-<name>-child-<n>.scope.

UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
TEMPLATE="$BLAST_OFF_HOME/systemd/blast-off@.service"

units_install() {
  mkdir -p "$UNIT_DIR"
  sed "s|@BLAST_OFF@|$BLAST_OFF_HOME/bin/blast-off|" "$TEMPLATE" > "$UNIT_DIR/blast-off@.service"
  cp "$BLAST_OFF_HOME/systemd/blast-off.slice" "$UNIT_DIR/blast-off.slice"
  systemctl --user daemon-reload
  echo "installed $UNIT_DIR/blast-off@.service and blast-off.slice; daemon reloaded; not enabled"
}

# UNIT_ENV: the --setenv=NAME list of every unit blast-off starts (the runner, the resume timer's
# service). systemd-run reads each value from this environment, so no value is on the line (D14).
unit_env() {
  UNIT_ENV=(--setenv=PATH --setenv=GH_TOKEN --setenv=CLAUDE_FLAGS); local v
  for v in JOB_MAX_CHILDREN JOB_CAP_FACTOR JOB_CHILD_TIMEOUT JOB_SESSION JOB_KEEP_WINDOWS BLAST_OFF_TRUST_SECONDS \
           JOB_USAGE_PAUSE JOB_RESUME_MARGIN JOB_API_BACKOFF BLAST_OFF_STATE_DIR BLAST_OFF_CI_APPEAR BLAST_OFF_CI_WATCH \
           BLAST_OFF_CI_HEAD JOB_JEV; do
    [ -z "${!v+x}" ] || UNIT_ENV+=(--setenv="$v")
  done
}

# What `start` needs from the caller's environment and the job dir; checked before anything changes.
unit_check() {
  [ -n "${CLAUDE_FLAGS:-}" ] || die "CLAUDE_FLAGS is unset or empty; every child needs --model and --effort (K8, D8)"
  [ -n "${GH_TOKEN:-}" ] || die "GH_TOKEN is unset or empty; --setenv=GH_TOKEN would pass an empty value to the unit"
  test -s "$JOB/brief.md" && test -s "$JOB/checkpoint.md" || die "missing $JOB/brief.md or checkpoint.md"
}

# The transient form of the template: same [Service] directives as -p properties, names by --setenv.
unit_start() {
  unit_check
  unit_env
  local args=(--user --collect --unit="$UNIT" --working-directory="$WORKDIR" "${UNIT_ENV[@]}") p
  while IFS= read -r p; do
    case "$p" in ExecStart=*) ;; *) args+=(-p "$p") ;; esac
  done < <(sed -n '/^\[Service\]/,/^\[/{/^[A-Za-z]*=/p}' "$TEMPLATE")
  args+=("$BLAST_OFF_HOME/bin/blast-off" run "$JOB")
  echo "systemd-run ${args[*]}"
  systemd-run "${args[@]}" || return  # explicit: under resume's `unit_start ||` set -e is off
  echo "status: blast-off status $JOB · watch: tmux -L $UNIT attach -t $SESSION · stop: blast-off stop $JOB"
}

# resume: `start` a paused-cap job, or a paused-limit one once its reset has passed. Before the reset it
# exits 8 and changes nothing; the resume timer runs it at the reset (lib/usage.sh). The status is not
# touched here: the runner clears the pause once it holds the job's lock (chain_run), so a start that
# fails leaves the job paused, never `running` with no runner (D3-1). The timer can fire while the old
# runner unit still stops (its EXIT trap, TimeoutStopSec=60), when systemd-run would refuse the name,
# so resume waits for it first. A pending timer is stopped once the start succeeded.
unit_resume() {
  local s until; s="$(cp_status)"
  case "$s" in paused-cap|paused-limit) ;; *) die "status is '$s'; resume acts only on paused-cap or paused-limit" ;; esac
  until="$([ "$s" != paused-limit ] || usage_until)"
  if [ -n "$until" ] && [ "$until" -gt "$(date +%s)" ]; then
    echo "blast-off: paused-limit until $(date -u -d "@$until" +%FT%TZ); resume then ($UNIT.resume.timer does it)" >&2; exit 8
  fi
  unit_check
  local i; for ((i = 0; i < 90; i++)); do
    [ "$(systemctl --user show "$UNIT.service" -p ActiveState --value)" != inactive ] || break; sleep 1
  done
  log "resume: starting $UNIT.service (status $s)"
  unit_start || { log "resume: start of $UNIT.service failed, status kept; why: stderr above, or journalctl --user -u $UNIT.resume.service when the timer ran it"; exit 1; }
  systemctl --user stop "$UNIT.resume.timer" 2>/dev/null || true
}

unit_status() {
  sed -n '1,/^## /p' "$JOB/checkpoint.md" | sed '$d'
  systemctl --user show "$UNIT.service" -p ActiveState
  # no "left under the cap": the unit's JOB_* env, which sets the cap, is not this shell's (P4R1-3)
  if chain_count; then echo "$COUNT_SAY"; else echo "child-count: $COUNT_ERR"; fi
  # the resume timer is transient: a reboot or user-manager exit deletes it and nothing resumes (spec §4)
  local t u; t="$(systemctl --user show "$UNIT.resume.timer" -p ActiveState --value)"; u="$(usage_until)"
  echo "resume timer: $t"
  # status takes only the job dir, so it cannot tell a job run with its own workdir (P3R3-1, P3Q9)
  [ -z "$u" ] || [ "$t" = active ] || echo "no resume timer: run blast-off resume $JOB after $(date -u -d "@$u" +%FT%TZ) (a job run with its own workdir: blast-off run $JOB <workdir>)"
}

# Stopping the runner fires its TERM trap; the child scopes sit outside its cgroup, so stop them too.
unit_stop() {
  # the resume timer too: a stopped job must not start again at its reset
  systemctl --user stop "$UNIT.service" "$UNIT-child-*.scope" "$UNIT.resume.timer" || true # not loaded = already stopped
  local s; s="$(systemctl --user show "$UNIT.service" -p ActiveState --value)"
  [ "$s" != active ] || die "$UNIT.service still active"
  echo "stopped $UNIT.service ($s); the next start resumes from the checkpoint"
}

unit_logs() {
  tail -n 40 "$LOG" 2>/dev/null || echo "(no $LOG yet)"
  journalctl --user -u "$UNIT.service" -n 40 --no-pager || true
}

# wait: block until the job changes, then print one line (issue 14): exit 0 at a done or blocked the runner logged
# (P6R1-1), 11 on a change while it still runs or is scheduled, 12 when on two polls in a row nothing runs or is
# scheduled (runner and resume timer down) and the runner logged no end: stopped, crashed, rebooted, done refused,
# paused-cap or an unarmed paused-limit, which never change on their own. 1 when it cannot start watching. It compares state, never the clock, so a machine sleep is one more poll, not a stall.
# ponytail: polls every BLAST_OFF_WAIT_POLL (5) s, no inotify (not a dependency); one process, no tokens
unit_wait() {
  local p="${BLAST_OFF_WAIT_POLL:-5}" ms='' was down=0
  # 0.1 to 3600 s, at most 3 decimals: 0 spins on systemctl, inf never polls again, a word is sleep's error (P6R1-6)
  if [[ $p =~ ^([0-9]{1,4})(\.([0-9]{1,3}))?$ ]]; then ms="${BASH_REMATCH[3]}000"; ms=$((10#${BASH_REMATCH[1]}${ms:0:3})); fi
  [ -n "$ms" ] && [ "$ms" -ge 100 ] && [ "$ms" -le 3600000 ] || die "BLAST_OFF_WAIT_POLL='$p' is not a number of seconds from 0.1 to 3600"
  wait_snap || die "$WAIT_ERR"; was="$SNAP"
  while :; do
    case "$WAIT_STATUS" in done|blocked) ! wait_logged "$WAIT_STATUS" || { echo "wait: final · $SNAP"; exit 0; } ;; esac
    case "$WAIT_UNIT $WAIT_TIMER" in
      *' active') down=0 ;;
      inactive*|failed*|deactivating*) down=$((down + 1)) ;;
      *) down=0 ;;
    esac
    if [ "$down" -ge 2 ]; then  # paused-cap shares 12 (owner Q1), so the line says its own next step (P6R1-2)
      [ "$WAIT_STATUS" = paused-cap ] && echo "wait: stuck · $SNAP; paused-cap: run blast-off resume $JOB" ||
        echo "wait: stuck · $SNAP; see blast-off status $JOB"
      exit 12
    fi
    # Not on the first poll with both down: a fired resume timer is gone before its runner is up (P6R1-3). Nor on a
    # done or blocked the runner has not logged: it may still refuse it, and then its unit goes down (stuck).
    [ "$down" = 1 ] || [[ $WAIT_STATUS =~ ^(done|blocked)$ ]] || [ "$SNAP" = "$was" ] || { echo "wait: changed · $SNAP"; exit 11; }
    sleep "$p"
    until wait_snap; do sleep "$p"; done  # mid-watch a failed read is retried (P6R1-5)
  done
}
# SNAP: the status and phase lines, the last child's number (child-count), the runner unit's and resume timer's
# state; WAIT_STATUS: the status word, as cp_status reads it, from the same read of checkpoint.md. A failed read
# returns 1 with WAIT_ERR.
wait_snap() {
  local cp c='?' s
  cp="$(cat "$JOB/checkpoint.md" 2>/dev/null)" && [ -n "$cp" ] || { WAIT_ERR="missing $JOB/checkpoint.md"; return 1; }
  if chain_count; then c="$LAUNCHED"; fi
  WAIT_UNIT="$(systemctl --user show "$UNIT.service" -p ActiveState --value 2>/dev/null)" &&
    WAIT_TIMER="$(systemctl --user show "$UNIT.resume.timer" -p ActiveState --value 2>/dev/null)" ||
    { WAIT_ERR="systemctl --user show $UNIT.service or .resume.timer failed (no user bus?)"; return 1; }
  s="$(sed -n '/^status:/{p;q}' <<<"$cp")"
  WAIT_STATUS="$(sed 's/^status: *\([a-z-]*\).*/\1/' <<<"$s")"
  # child-written text reaches a session's context (P6R1-7): of the status line only its word and a paused-limit's
  # `until <time>`; the phase line with no control characters and no ` · ` field separator; each cut to 80 characters
  local re='^status: *[a-z-]+ +(until [0-9TZ:.+-]{1,40})' u='' ph
  [[ ! $s =~ $re ]] || u=" ${BASH_REMATCH[1]}"
  ph="$(sed -n '/^phase:/{p;q}' <<<"$cp")"; ph="${ph//[[:cntrl:]]/}"; ph="${ph//·/-}"
  SNAP="status: ${WAIT_STATUS:0:80}$u · ${ph:0:80} · child $c · unit $WAIT_UNIT · timer $WAIT_TIMER"
}
# wait_logged <done|blocked>: run.log's last runner line (a timestamp first, as log writes it) is the runner's end
# for that status, `job done` or `job blocked; see ...` (P6R1-1). A child's text in run.log has a runner line after
# it (`child <n> usage`, chain_run), so a child cannot end the watch, unless the runner is killed between the two.
wait_logged() {
  local t='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z ' e='job done$' l
  [ "$1" = 'done' ] || e='job blocked; see '
  l="$(grep -E "$t" "$LOG" 2>/dev/null | tail -n 1)" || return 1
  [[ $l =~ $t$e ]]
}
