# shellcheck shell=bash
# jev.sh: each phase's model level, chosen by Jev (D9: ~/.local/bin/jev, through OpenRouter, never
# TypeSafe) with CLAUDE_FLAGS unchanged as the fallback. One choice question per open Phase plan row:
# the row's text goes to jev on stdin (never on argv), the answer names a level, and the level's
# --model/--effort replace CLAUDE_FLAGS's own; every other flag stays.

# claude 2.1.316 --help: --model takes an alias (sonnet, opus); --effort low|medium|high|xhigh|max.
jev_level() {
  case "$1" in
    light) echo "--model sonnet --effort medium" ;;
    standard) echo "--model opus --effort high" ;;
    deep) echo "--model opus --effort xhigh" ;;
    *) return 1 ;;
  esac
}

# Every choice gets an `other` (ask-jev rule); `other` falls back.
JEV_Q='{"level":{"type":"choice","instructions":"The state is one row of a multi-phase coding job plan (key, phase name, done-when, status). Which model level do the coding sessions that build this phase need?","criteria":{"light":"Docs, templates, config or small mechanical edits that existing tests cover","standard":"Ordinary feature, fix or test work in code the job already has","deep":"A new subsystem, concurrency, process control, security, money, migrations or hard debugging","other":"None of these, or the row is too vague to judge"}}}'

# jev_flags <row>: CHILD_FLAGS (the flags children of that row get), JEV_LEVEL (a level, or static),
# JEV_CONF, JEV_MIN (the confidence threshold) and JEV_WHY (why static). Never fails: every problem is a
# logged fallback. A pick whose confidence is below JOB_JEV_MIN_CONF (default 0.7; chain_nums checks it is a
# number from 0 to 1), or not a number, keeps CLAUDE_FLAGS (owner, issue 27).
# The key must be OpenRouter's (sk-or-): jev routes by key prefix and reads TYPESAFE_API_KEY first, so
# that name and JEV_BASE_URL are dropped from its environment. The runner reads no secret file (D21):
# the key is whatever OPENROUTER_API_KEY the runner was given; `start` and the resume timer pass it by
# name when it is set (unit_env, issue 27). Its value is never logged.
jev_flags() {
  local row="$1" out err level pair rest
  CHILD_FLAGS="$CLAUDE_FLAGS" JEV_LEVEL=static JEV_CONF='' JEV_WHY='' JEV_MIN="${JOB_JEV_MIN_CONF:-0.7}"
  if [ -z "$row" ]; then JEV_WHY="no open Phase plan row"; return 0; fi
  if [ "${JOB_JEV:-1}" = 0 ]; then JEV_WHY="JOB_JEV=0"; return 0; fi
  if [ -z "${OPENROUTER_API_KEY:-}" ]; then JEV_WHY="no OPENROUTER_API_KEY in the runner environment"; return 0; fi
  if [[ $OPENROUTER_API_KEY != sk-or-* ]]; then
    JEV_WHY="OPENROUTER_API_KEY is not an OpenRouter sk-or- key; Jev runs only through OpenRouter"; return 0
  fi
  command -v jev > /dev/null || { JEV_WHY="jev not on PATH"; return 0; }
  err="$(mktemp "${XDG_RUNTIME_DIR:-/tmp}/blast-off-jev.XXXXXX")"
  if ! out="$(printf '%s\n' "$row" | env -u TYPESAFE_API_KEY -u JEV_BASE_URL timeout 60 jev -q "$JEV_Q" level 2> "$err")"; then
    JEV_WHY="jev failed: $(head -c 200 "$err" | tr '\n\t' '  ' | sed 's/ *$//')"; rm -f "$err"; return 0
  fi
  rm -f "$err"
  level="$(jq -r '.level.choice // empty | strings' <<< "$out" 2>/dev/null || true)"
  if ! pair="$(jev_level "$level")"; then JEV_WHY="jev answered '${level:-nothing}', not a level"; return 0; fi
  JEV_CONF="$(jq -r '.level.confidence // "?"' <<< "$out" 2>/dev/null || echo '?')"
  case "$(jq -r --argjson t "$JEV_MIN" '.level.confidence | if type != "number" then "nan" elif . < $t then "low" else "ok" end' <<< "$out" 2>/dev/null)" in
    ok) ;;
    low) JEV_WHY="jev picked $level, confidence $JEV_CONF below $JEV_MIN"; return 0 ;;
    *) JEV_WHY="jev picked $level, confidence '$JEV_CONF' is not a number"; return 0 ;;
  esac
  rest="$(sed -E 's/(^|[[:space:]])--(model|effort)(=|[[:space:]]+)[^[:space:]]+//g; s/^[[:space:]]+//' <<< "$CLAUDE_FLAGS")"
  # shellcheck disable=SC2034  # CHILD_FLAGS: read by child_launch
  CHILD_FLAGS="$pair${rest:+ $rest}" JEV_LEVEL="$level"
}

# jev_pick <n>: before child n, ask again only when the first open Phase plan row changed, so every child
# of one phase gets one pick; each pick goes to run.log and the job's decisions.tsv.
jev_pick() {
  local k row why
  k="$(cp_open_rows | head -n 1)"
  [ "$k" != "${JEV_KEY-none-yet}" ] || return 0
  JEV_KEY="$k" row="$([ -z "$k" ] || cp_row "$k")"
  jev_flags "$row"
  if [ -z "$k" ]; then
    log "model level: no open Phase plan row; static CLAUDE_FLAGS: $CHILD_FLAGS"
  elif [ "$JEV_LEVEL" = static ]; then
    log "model level for phase $k: static CLAUDE_FLAGS ($JEV_WHY): $CHILD_FLAGS"
  else
    log "model level for phase $k: $JEV_LEVEL (jev, confidence $JEV_CONF, threshold $JEV_MIN): $CHILD_FLAGS"
  fi
  why="${JEV_WHY:-jev choice, confidence $JEV_CONF, threshold $JEV_MIN}"
  # the six columns of the job's decision log (show-me-your-work's header): ts, phase, decision, why, evidence, result
  [ -e "$JOB/decisions.tsv" ] || printf 'ts\tphase\tdecision\twhy\tevidence\tresult\n' > "$JOB/decisions.tsv"
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$(date -u +%FT%TZ)" "phase-${k:-none}" "model level $JEV_LEVEL: $CHILD_FLAGS" \
    "$why" "blast-off jev_pick; run.log" "child $1" | tr -d '\r' >> "$JOB/decisions.tsv"
}
