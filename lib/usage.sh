# shellcheck shell=bash
# usage.sh: the account's usage at each child's end, and the pause it triggers (F10, K10).
# ~/.claude/hooks/usage-limit-tee.sh writes the status line's rate_limits per session to
# usage-limits-<session_id>.json: {"five_hour":{"used_percentage":N,"resets_at":<epoch>},"seven_day":{...}},
# either key absent when the status line had no figure. The session id comes from the child's Stop
# or StopFailure payload. BLAST_OFF_STATE_DIR moves the directory (tests).

# shellcheck disable=SC2034  # LIMIT_EXIT: read by chain_run
LIMIT_EXIT=75  # the child exit code reserved for a usage-limit error (sysexits.h EX_TEMPFAIL)

# usage_read <session>: USAGE ("5h 96% 7d 40%", or "unknown"), USAGE_OVER (latest reset of the windows
# at or above JOB_USAGE_PAUSE whose reset is still ahead; empty when none) and USAGE_5H (the five_hour
# window's reset while ahead: what a rate-limited child waits for when no window is over).
# A window whose reset is past has already refilled and never pauses. Non-numeric fields are ignored.
usage_read() {
  USAGE=unknown USAGE_OVER='' USAGE_5H=''
  local f="${BLAST_OFF_STATE_DIR:-$HOME/.claude/state}/usage-limits-$1.json" out u o h
  [ -n "$1" ] && [ -s "$f" ] || return 0
  out="$(jq -r --argjson now "$(date +%s)" --argjson th "${JOB_USAGE_PAUSE:-95}" '
    [ ["five_hour","5h"], ["seven_day","7d"] ] as $names
    | [ $names[] as [$k,$l] | (.[$k] // null) | select(type == "object" and (.used_percentage | type) == "number")
        | {k: $k, l: $l, u: .used_percentage, r: (if (.resets_at | type) == "number" then .resets_at else null end)} ] as $w
    | ($w | map("\(.l) \(.u | floor)%") | join(" ")),
      ([ $w[] | select(.r != null and .r > $now and .u >= $th) | .r ] | max // ""),
      ([ $w[] | select(.k == "five_hour" and .r != null and .r > $now) | .r ] | first // "")' "$f" 2>/dev/null)" || return 0
  { read -r u; read -r o; read -r h; } <<< "$out" || true  # $(...) drops trailing empty lines
  # shellcheck disable=SC2034  # read by chain_run
  USAGE="${u:-unknown}" USAGE_OVER="${o%.*}" USAGE_5H="${h%.*}"
}

# usage_pause <reset epoch or empty> <why>: status paused-limit until the reset plus JOB_RESUME_MARGIN
# (at least 5 s ahead, so the timer is never armed in the past), the resume timer, exit 8. An unknown
# reset waits five hours, the five_hour window's length.
usage_pause() {
  local reset="$1" why="$2" now at until
  now=$(date +%s)
  [ -n "$reset" ] || { reset=$((now + 18000)); why+="; reset time unknown, five hours assumed"; }
  at=$((reset + ${JOB_RESUME_MARGIN:-60})); [ "$at" -ge $((now + 5)) ] || at=$((now + 5))
  until="$(date -u -d "@$at" +%FT%TZ)"
  cp_set_status "paused-limit until $until"
  usage_arm "$at"
  chain_end 8 "$why; status paused-limit until $until; blast-off resume $JOB after that (the timer does it)"
}

# usage_arm <epoch>: a transient timer <unit>-resume that runs `blast-off resume <job-dir>` at that
# wall-clock time. OnCalendar, not OnActiveSec: a calendar timer that elapses while the host sleeps
# fires on wake, a monotonic one pauses with the host (systemd.timer(5)). The user manager has no
# CLAUDE_FLAGS or GH_TOKEN, so the timer's service gets the same --setenv names as `start` (D21).
usage_arm() {
  local cal; cal="$(date -u -d "@$1" '+%F %T UTC')"
  # resume takes only the job dir, so it would pick the default workdir and another unit name (D3-2)
  if [ "$WORKDIR" != "$(dirname "$JOB")" ]; then
    log "no resume timer: workdir $WORKDIR is not the job dir's parent; run blast-off run $JOB $WORKDIR after $cal"; return 0
  fi
  if [ -z "${GH_TOKEN:-}" ]; then
    log "no resume timer: GH_TOKEN is unset, so its start would refuse; run blast-off resume $JOB after $cal"; return 0
  fi
  systemctl --user stop "$UNIT-resume.timer" "$UNIT-resume.service" 2>/dev/null || true
  unit_env
  if systemd-run --user --quiet --collect --unit="$UNIT-resume" --on-calendar="$cal" --timer-property=AccuracySec=1s \
       "${UNIT_ENV[@]}" "$BLAST_OFF_HOME/bin/blast-off" resume "$JOB" 2>> "$LOG"; then
    log "resume timer $UNIT-resume.timer armed for $cal"
  else
    log "resume timer not armed (systemd-run failed, above); run blast-off resume $JOB after $cal"
  fi
}

# usage_until: the paused-limit status's resume time in epoch seconds; empty when it has none.
usage_until() {
  local t; t="$(sed -n '/^status:/{s/^status: *paused-limit until \([0-9TZ:-]*\).*/\1/p;q}' "$JOB/checkpoint.md")"
  [ -z "$t" ] || date -u -d "$t" +%s 2>/dev/null || true
}
