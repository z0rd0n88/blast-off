# shellcheck shell=bash
# preflight.sh: `blast-off preflight <job-dir> [workdir]`. One `name: value` line per thing a launch
# would use or meet (F2, F9, F10, K8, D1-7, Q2, P3Q3), then `preflight: ok` (exit 0) or
# `preflight: refused: <why>` (exit 1): brief.md missing, CLAUDE_FLAGS empty, a runtime dependency or gh
# missing, a garbled child-count, or a usage estimate over what is left of the seven_day window; a bad JOB_* count refuses
# before any other line. It writes nothing: log lines go to stdout only.

preflight_run() {
  local probs=() b row k
  # shellcheck disable=SC2034  # read by log()
  LOG=/dev/null  # usage_read logs an unreadable record; preflight writes no run.log
  test -s "$JOB/checkpoint.md" || die "missing $JOB/checkpoint.md"
  test -s "$JOB/brief.md" || probs+=("missing $JOB/brief.md")
  # no cap, count or left can be derived from a bad JOB_* count, so it refuses before any line (P5R1-4)
  chain_nums || { echo "preflight: refused: $NUMS_ERR"; exit 1; }
  [ -n "${CLAUDE_FLAGS:-}" ] || probs+=("CLAUDE_FLAGS is unset or empty")
  for b in $DEPS gh; do command -v "$b" > /dev/null || probs+=("$b not on PATH"); done

  echo "job: $JOB · workdir: $WORKDIR · unit: $UNIT.service"
  k="$(cp_open_rows | head -n 1)"; row="$([ -z "$k" ] || cp_row "$k")"
  # start's view: start and the resume timer pass OPENROUTER_API_KEY by name when Jev can use it (sk-or-, JOB_JEV not 0; issue 27), so
  # this asks Jev as the runner would, with this environment; the key's value is never printed
  jev_flags "$row"
  echo "flags: $CHILD_FLAGS"
  echo "model: $(pf_flag model) · effort: $(pf_flag effort)"
  if [ -z "$k" ]; then echo "level: no open Phase plan row; static CLAUDE_FLAGS"
  elif [ "$JEV_LEVEL" = static ]; then
    echo "level: phase $k: static CLAUDE_FLAGS under start ($JEV_WHY$([ -n "${OPENROUTER_API_KEY:-}" ] || echo '; start passes none'))"
  else echo "level: phase $k: $JEV_LEVEL under start (jev, confidence $JEV_CONF, threshold $JEV_MIN; start passes OPENROUTER_API_KEY by name)"; fi
  chain_cap
  echo "cap: $MAXC ($CAP_WHY)"
  # P4R1-3: what child-count holds and what is left under that cap; a paused-cap run under the soft cap
  # gets a fresh allotment (base moves to launched), as chain_run gives it. A garbled one refuses.
  if chain_count; then
    local b="$BASE"; [ -z "$CAP_SOFT" ] || [ "$(cp_status)" != paused-cap ] || b="$LAUNCHED"
    local left=$((MAXC - LAUNCHED + (CAP_SOFT ? b : 0)))
    echo "$COUNT_SAY; $((left > 0 ? left : 0)) left under cap $MAXC"
  else
    echo "child-count: $COUNT_ERR"; probs+=("$COUNT_ERR")
  fi
  echo "timeout: ${JOB_CHILD_TIMEOUT:-7200} s per child"
  pf_account
  echo "GH_TOKEN: $([ -n "${GH_TOKEN:-}" ] && echo set || echo 'unset (start refuses)')"
  pf_usage
  pf_estimate
  pf_slice
  echo "scope stop timeout: $(systemctl --user show -p DefaultTimeoutStopUSec --value 2>/dev/null || echo unknown) (user manager default: a child scope that ignores TERM is killed after it; owner question Q2)"
  pf_prs
  pf_behind
  if [ "${#probs[@]}" -eq 0 ]; then echo "preflight: ok"; return 0; fi
  local j; printf -v j '%s; ' "${probs[@]}"; echo "preflight: refused: ${j%; }"; exit 1
}

# pf_flag <name>: the value of --<name> in CHILD_FLAGS (`--name v` or `--name=v`); (none) without one.
pf_flag() {
  local v; v="$(sed -nE "s/(^|.*[[:space:]])--$1(=|[[:space:]]+)([^[:space:]]+).*/\\3/p" <<< "$CHILD_FLAGS")"
  echo "${v:-(none)}"
}

# Whose usage the job spends: `claude auth status --json` (claude 2.1.316: email, orgName, subscriptionType).
pf_account() {
  local a; a="$(timeout 30 claude auth status --json 2>/dev/null)" || a=
  a="$(jq -r 'select(.loggedIn == true) | "\(.email // "?") (\(.subscriptionType // "?"), \(.orgName // "?"))"' <<< "$a" 2>/dev/null)" || a=
  echo "account: ${a:-unavailable (claude auth status gave no signed-in account)}"
}

# The newest usage record in the state dir is the account's latest figure: every session of one
# account writes the same windows. None means usage-limit-tee.sh is not in the status line (P3Q3) and
# the usage pause cannot work. PF_7D_LEFT: what is left of the seven_day window (all of it once its
# reset passed); empty when the record has no seven_day figure.
pf_usage() {
  local dir="${BLAST_OFF_STATE_DIR:-$HOME/.claude/state}" f
  PF_7D_LEFT=
  f="$(find "$dir" -maxdepth 1 -name 'usage-limits-*.json' -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -n 1 | cut -d' ' -f2-)" || true  # no dir: find exits 1
  if [ -z "$f" ]; then
    echo "usage: no usage records in $dir: usage pause is off until ~/.claude/hooks/usage-limit-tee.sh writes one"; return 0
  fi
  local s="${f##*/usage-limits-}"; usage_read "${s%.json}"
  echo "usage: $USAGE (${f##*/}, $(( $(date +%s) - $(stat -c %Y "$f") )) s old)"
  PF_7D_LEFT="$(jq -r --argjson now "$(date +%s)" '.seven_day | select(type == "object" and (.used_percentage | type) == "number")
    | if (.resets_at | type) == "number" and .resets_at <= $now then 100 else 100 - .used_percentage | floor end' "$f" 2>/dev/null)" || PF_7D_LEFT=
}

# F10: a job's seven_day spend estimated from Phase plan rows that carry ` · usage ... 7d N%` (the
# runner writes them at each close): the mean of the positive steps between consecutive figures (a
# window reset between two rows gives a negative step, skipped) times this job's open rows. Source:
# BLAST_OFF_ESTIMATE_FROM (a previous job's checkpoint.md), else this job's own rows. Over what is left
# of the seven_day window: refused. The five_hour window is bridged by paused-limit, never refused.
pf_estimate() {
  local src="${BLAST_OFF_ESTIMATE_FROM:-$JOB/checkpoint.md}" per open est
  per="$(cp_rows "$src" 2>/dev/null |
    sed -n 's/.* · usage .*7d \([0-9][0-9]*\)%.*/\1/p' |
    awk 'NR > 1 && $1 > p { s += $1 - p; n++ } { p = $1 } END { if (n) printf "%d", (s + n - 1) / n }')"
  if [ -z "$per" ]; then echo "estimate: no estimate (fewer than two 7d figures in the Phase plan rows of $src)"; return 0; fi
  open="$(cp_open_rows | wc -l)"; est=$((per * open))
  local line="estimate: $est% of the seven_day window for $open open phase rows ($per% a phase from $src)"
  if [ -z "$PF_7D_LEFT" ]; then echo "$line; seven_day left unknown, not checked"
  elif [ "$est" -gt "$PF_7D_LEFT" ]; then echo "$line; $PF_7D_LEFT% left; over it: refused"; probs+=("estimate $est% over $PF_7D_LEFT% left")
  else echo "$line; $PF_7D_LEFT% left"; fi
}

# D1-7: --slice=blast-off.slice on a slice with no unit file makes an implicit one with no limits.
pf_slice() {
  local p; p="$(systemctl --user show blast-off.slice -p FragmentPath --value 2>/dev/null)" || p=
  if [ -n "$p" ]; then echo "slice: blast-off.slice loaded from $p"
  else echo "slice: blast-off.slice not installed (an implicit slice has no limits): blast-off install"; fi
}

# F9: open PRs whose files touch the brief's target set: the backticked entries of its first bullet
# that starts `Target set` or `**Target set**` (the line and its indented continuation lines). An entry ending in '/' is a directory prefix, one
# with * ? or [ a glob (bash pattern, * crosses '/'), any other the file itself or a directory.
pf_prs() {
  local targets=() t prs num head title f hit note='' lines=() n=0 files
  while IFS= read -r t; do targets+=("$t"); done < <(
    sed -n '/^[[:space:]]*-[[:space:]]*\(\*\*\)\{0,1\}Target set/{:a;p;n;/^[[:space:]][[:space:]]*[^-[:space:]]/ba;q}' "$JOB/brief.md" 2>/dev/null |
      command grep -o '`[^`]*`' | tr -d '`' | sed -n 's/^[[:space:]]*//; /./p')
  [ "${#targets[@]}" -gt 0 ] || note=" (no Target set bullet in brief.md; every open PR)"
  if ! prs="$(cd "$WORKDIR" && timeout 60 gh pr list --state open --limit 100 --json number,title,headRefName,files 2>&1)"; then
    echo "open PRs on the target set: unavailable (gh pr list failed: $(head -c 200 <<< "$prs" | tr '\n' ' '))"; return 0
  fi
  while IFS=$'\t' read -r num head title files; do
    hit=()
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      if [ "${#targets[@]}" -eq 0 ]; then hit+=("$f"); continue; fi
      for t in "${targets[@]}"; do
        # shellcheck disable=SC2053  # $t unquoted: a glob entry matches as a pattern
        if [[ $t == */ && $f == "$t"* ]] || [[ $t == *[*?[]* && $f == $t ]] || [[ $f == "$t" || $f == "$t"/* ]]; then hit+=("$f"); break; fi
      done
    done < <(tr '\036' '\n' <<< "$files")
    [ "${#hit[@]}" -gt 0 ] || [ "${#targets[@]}" -eq 0 ] || continue
    n=$((n + 1)); lines+=("  #$num $head: $title (${hit[*]})")
  done < <(jq -r '.[] | [.number, .headRefName, (.title | gsub("[\t\n]"; " ")), ([.files[]?.path] | join("\u001e"))] | @tsv' <<< "$prs" 2>/dev/null)
  echo "open PRs on the target set: $n$note"
  [ "$n" -eq 0 ] || printf '%s\n' "${lines[@]}"
}

# F9: commits on origin/<JOB_BASE, default main> that HEAD lacks, after fetching that one branch.
pf_behind() {
  local base="${JOB_BASE:-main}" c note=''
  if ! git -C "$WORKDIR" rev-parse --git-dir > /dev/null 2>&1; then echo "behind: workdir not in git"; return 0; fi
  timeout 60 git -C "$WORKDIR" fetch -q origin "$base" 2>/dev/null || note="; fetch failed, last fetched origin/$base"
  if c="$(git -C "$WORKDIR" rev-list --count "HEAD..origin/$base" 2>/dev/null)"; then
    echo "behind: $c (git rev-list --count HEAD..origin/$base$note)"
  else
    echo "behind: no origin/$base to count against"
  fi
}
