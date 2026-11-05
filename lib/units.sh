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

# The transient form of the template: same [Service] directives as -p properties, names passed with
# --setenv=NAME so systemd-run reads each value from this environment and no value is on the line (D14).
unit_start() {
  [ -n "${CLAUDE_FLAGS:-}" ] || die "CLAUDE_FLAGS is unset or empty; every child needs --model and --effort (K8, D8)"
  [ -n "${GH_TOKEN:-}" ] || die "GH_TOKEN is unset or empty; --setenv=GH_TOKEN would pass an empty value to the unit"
  test -s "$JOB/brief.md" && test -s "$JOB/checkpoint.md" || die "missing $JOB/brief.md or checkpoint.md"
  local args=(--user --collect --unit="$UNIT" --working-directory="$WORKDIR"
    --setenv=PATH --setenv=GH_TOKEN --setenv=CLAUDE_FLAGS) v p
  for v in JOB_MAX_CHILDREN JOB_CHILD_TIMEOUT JOB_SESSION JOB_KEEP_WINDOWS BLAST_OFF_TRUST_SECONDS; do
    [ -z "${!v+x}" ] || args+=(--setenv="$v")
  done
  while IFS= read -r p; do
    case "$p" in ExecStart=*) ;; *) args+=(-p "$p") ;; esac
  done < <(sed -n '/^\[Service\]/,/^\[/{/^[A-Za-z]*=/p}' "$TEMPLATE")
  args+=("$BLAST_OFF_HOME/bin/blast-off" run "$JOB")
  echo "systemd-run ${args[*]}"
  systemd-run "${args[@]}"
  echo "status: blast-off status $JOB · watch: tmux -L $UNIT attach -t $SESSION · stop: blast-off stop $JOB"
}

unit_status() {
  sed -n '1,/^## /p' "$JOB/checkpoint.md" | sed '$d'
  systemctl --user show "$UNIT.service" -p ActiveState
}

# Stopping the runner fires its TERM trap; the child scopes sit outside its cgroup, so stop them too.
unit_stop() {
  systemctl --user stop "$UNIT.service" "$UNIT-child-*.scope" || true # not loaded = already stopped
  local s; s="$(systemctl --user show "$UNIT.service" -p ActiveState --value)"
  [ "$s" != active ] || die "$UNIT.service still active"
  echo "stopped $UNIT.service ($s); the next start resumes from the checkpoint"
}

unit_logs() {
  tail -n 40 "$LOG" 2>/dev/null || echo "(no $LOG yet)"
  journalctl --user -u "$UNIT.service" -n 40 --no-pager || true
}
