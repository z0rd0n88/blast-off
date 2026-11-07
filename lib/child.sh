# shellcheck shell=bash
# child.sh: one child = one window on the job's own tmux server, running claude inside its own
# systemd scope. Ported from big-next-job's run-job lines 43 to 86.

# A private server per job (spec §4): its global environment is the runner's, so PATH, GH_TOKEN and
# JOB_* reach every child with no value on any command line (D14). The default server is the owner's
# and would hand children the owner's PATH and no GH_TOKEN. CLAUDE* names are scrubbed so a child does
# not inherit a parent session's state; CLAUDE_FLAGS is expanded by the runner, not read by the child.
# What an earlier run of this job left (its server holds a stale environment; its scopes hold the
# names child_launch reuses) is stopped first. Both the socket and the scopes belong to this job.
child_server() {
  local scrub
  scrub=$(env | command grep -o '^CLAUDE[A-Z_]*=' | sed 's/=$//; s/^/-u /' || true)
  child_stop_all
  # -f /dev/null: the owner's tmux.conf (hooks such as pane-died kill-pane, renumber-windows) never
  # reaches the job's server, so a dead child's pane and screen stay where child_wait looks (D2-2).
  # shellcheck disable=SC2086
  env $scrub tmux -f /dev/null -L "$UNIT" new-session -d -s "$SESSION" -c "$WORKDIR"
  # A child's pane outlives its claude (tmux(1) remain-on-exit), so child_wait sees the death as
  # #{pane_dead} and the last screen, the only record of why it died, is still there to log.
  tmux -L "$UNIT" set-option -g remain-on-exit on
}

# Every child scope of this job and the job's tmux server.
child_stop_all() {
  systemctl --user stop "$UNIT-child-*.scope" 2>/dev/null || true
  tmux -L "$UNIT" kill-server 2>/dev/null || true
}

# child_launch <n>: CHILD_DIR (settings + done.json), CHILD_WIN, CHILD_SCOPE. tmux 3.4 moves each pane
# into a tmux-spawn scope outside the runner's unit; systemd-run --scope moves claude again, into
# blast-off.slice under a name the runner and `blast-off stop` can stop (spec §4). tmux moves only the
# pane's own pid, after fork and without waiting, so '; exit' makes the shell fork systemd-run rather
# than exec it: a late tmux move lands on the shell, never on claude (else claude ends in a tmux-spawn
# scope the runner cannot name). CHILD_WIN is the pane id (%N): an index target (session:1.0) of a
# closed window resolves to another window on tmux 3.4 and would hide the death (D2-1).
child_launch() {
  local n="$1" q
  CHILD_DIR="$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/blast-off.XXXXXX")"
  sed "s|@DIR@|$CHILD_DIR|g" "$BLAST_OFF_HOME/templates/settings.child.json" > "$CHILD_DIR/settings.json"
  q="'$(printf '%s' "$PROMPT" | sed "s/'/'\\\\''/g")'"
  CHILD_SCOPE="$UNIT-child-$n.scope"
  CHILD_WIN=$(tmux -L "$UNIT" new-window -dP -F '#{pane_id}' -t "$SESSION" -c "$WORKDIR" -e JOB_DIR="$JOB" -e JOB_CHILD="$n" \
    "systemd-run --user --scope --quiet --collect --slice=blast-off.slice --unit=$CHILD_SCOPE claude $CLAUDE_FLAGS --settings $CHILD_DIR/settings.json $q; exit")
  log "child $n launched  window=$CHILD_WIN  (watch: tmux -L $UNIT attach -t $SESSION)"
}

# Wait for the child: 0 when its Stop hook wrote done.json, 1 past TIMEOUT seconds, 2 when it exited
# first (CHILD_AGE = seconds it lived). Polled once a second: a dead pane (`1`) is seen in about 1 s; a
# failed read (window or server gone, or a transient tmux error) counts only on the second in a row, so
# one bad read never stops a working child. done.json is read again after a death: the hook's mv ends
# before claude exits.
# Time is $SECONDS, not loop turns: capture-pane and the trust keys' sleep stretch a turn (P1R2-4).
# A folder Claude has not seen shows a trust dialog; the job's worktrees are owner-created, so every
# trust dialog is answered (owner decision 2026-10-28). The dialog appears only as claude starts, so the
# scrape runs only for the first BLAST_OFF_TRUST_SECONDS (default 60): later the same text can be on
# screen in a working child (this repo's own files hold it), and keys typed then would reach its session.
# ponytail: screen scrape (capture-pane is the only view of the dialog); replace if claude grows a --trust flag.
child_wait() {
  local start=$SECONDS el d miss=0
  while :; do
    el=$((SECONDS-start))
    [ -s "$CHILD_DIR/done.json" ] && return 0
    d=$(tmux -L "$UNIT" display -p -t "$CHILD_WIN" '#{pane_dead}' 2>/dev/null) || d=
    case "$d" in 0) miss=0 ;; 1) miss=2 ;; *) miss=$((miss+1)) ;; esac
    if [ "$miss" -ge 2 ]; then
      [ -s "$CHILD_DIR/done.json" ] && return 0
      # shellcheck disable=SC2034  # CHILD_AGE: read by chain_run
      CHILD_AGE=$el; return 2
    fi
    [ "$el" -le "$TIMEOUT" ] || return 1
    if [ "$el" -lt "${BLAST_OFF_TRUST_SECONDS:-60}" ] &&
       [[ $(tmux -L "$UNIT" capture-pane -p -t "$CHILD_WIN" 2>/dev/null) == *"Yes, I trust this folder"* ]]; then
      tmux -L "$UNIT" send-keys -t "$CHILD_WIN" Down Enter; sleep 2
    fi
    sleep 1
  done
}

# child_screen: the child's last 40 lines on screen, blank lines dropped, into run.log.
child_screen() {
  { echo "--- child's last screen ---"
    tmux -L "$UNIT" capture-pane -p -t "$CHILD_WIN" -S -40 2>/dev/null | sed '/^[[:space:]]*$/d' || echo "(window gone)"
    echo "---"; } >> "$LOG"
}

# child_report <n>: the Stop payload into run.log, and its tail to stdout (the journal).
child_report() {
  python3 - "$CHILD_DIR/done.json" "$1" >> "$LOG" <<'PY'
import json, sys
raw = open(sys.argv[1], errors="replace").read()
try:
    ev = json.loads(raw)
except ValueError:
    ev = None
if not isinstance(ev, dict):  # a bad payload is the child's fault; log it, never abort the runner (Q3)
    print(f"child {sys.argv[2]} Stop payload is not a JSON object: {raw[:200].strip()}")
    sys.exit(0)
print(f"child {sys.argv[2]} session={ev.get('session_id')} transcript={ev.get('transcript_path')}")
print("--- child's last message ---")
print(ev.get("last_assistant_message") or "(none)")
print("---")
PY
  sed -n "/^child $1 session=/,/^---$/p" "$LOG" | tail -n 40
}

# Stop the child's scope (claude and anything it started) and close its window. JOB_KEEP_WINDOWS
# keeps a finished child open; a timed-out child is always stopped (child_stop force).
child_stop() {
  [ -z "${JOB_KEEP_WINDOWS:-}" ] || [ "${1:-}" = force ] || return 0
  systemctl --user stop "$CHILD_SCOPE" 2>/dev/null || true
  tmux -L "$UNIT" kill-window -t "$CHILD_WIN" 2>/dev/null || true
}
