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
  # shellcheck disable=SC2086
  env $scrub tmux -L "$UNIT" new-session -d -s "$SESSION" -c "$WORKDIR"
}

# Every child scope of this job and the job's tmux server.
child_stop_all() {
  systemctl --user stop "$UNIT-child-*.scope" 2>/dev/null || true
  tmux -L "$UNIT" kill-server 2>/dev/null || true
}

# child_launch <n>: CHILD_DIR (settings + done.json), CHILD_WIN, CHILD_SCOPE. tmux 3.4 moves each pane
# into a tmux-spawn scope outside the runner's unit; systemd-run --scope moves claude again, into
# blast-off.slice under a name the runner and `blast-off stop` can stop (spec §4).
child_launch() {
  local n="$1" q
  CHILD_DIR="$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/blast-off.XXXXXX")"
  sed "s|@DIR@|$CHILD_DIR|g" "$BLAST_OFF_HOME/templates/settings.child.json" > "$CHILD_DIR/settings.json"
  q="'$(printf '%s' "$PROMPT" | sed "s/'/'\\\\''/g")'"
  CHILD_SCOPE="$UNIT-child-$n.scope"
  CHILD_WIN=$(tmux -L "$UNIT" new-window -dP -t "$SESSION" -c "$WORKDIR" -e JOB_DIR="$JOB" -e JOB_CHILD="$n" \
    "systemd-run --user --scope --quiet --collect --slice=blast-off.slice --unit=$CHILD_SCOPE claude $CLAUDE_FLAGS --settings $CHILD_DIR/settings.json $q")
  log "child $n launched  window=$CHILD_WIN  (watch: tmux -L $UNIT attach -t $SESSION)"
}

# Wait for the child's Stop hook to write done.json; 0 when it did, 1 at the timeout.
# A folder Claude has not seen shows a trust dialog; the job's worktrees are owner-created, so every
# trust dialog is answered (owner decision 2026-10-28). The dialog appears only as claude starts, so the
# scrape runs only for the first BLAST_OFF_TRUST_SECONDS (default 60): later the same text can be on
# screen in a working child (this repo's own files hold it), and keys typed then would reach its session.
# ponytail: screen scrape (capture-pane is the only view of the dialog); replace if claude grows a --trust flag.
child_wait() {
  local i
  for ((i=0; i<TIMEOUT; i++)); do
    [ -s "$CHILD_DIR/done.json" ] && return 0
    if [ "$i" -lt "${BLAST_OFF_TRUST_SECONDS:-60}" ] &&
       [[ $(tmux -L "$UNIT" capture-pane -p -t "$CHILD_WIN" 2>/dev/null) == *"Yes, I trust this folder"* ]]; then
      tmux -L "$UNIT" send-keys -t "$CHILD_WIN" Down Enter; sleep 2
    fi
    sleep 1
  done
  return 1
}

# child_report <n>: the Stop payload into run.log, and its tail to stdout (the journal).
child_report() {
  python3 - "$CHILD_DIR/done.json" "$1" >> "$LOG" <<'PY'
import json, sys
ev = json.load(open(sys.argv[1]))
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
