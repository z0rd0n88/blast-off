#!/usr/bin/env bash
# 13-wait: `blast-off wait <job-dir>` blocks until the status line, the phase, the child number or the unit
# changes, then prints one line: exit 0 at done or blocked, 11 on a change while the job still runs or is
# scheduled, 12 when nothing runs or is scheduled but the status is not final (stopped, crashed, rebooted,
# paused-cap), 1 when there is nothing to watch. It compares state, never the clock (issue 14).
# systemctl is a fake local to this scenario: no real unit is read, started or installed.
# shellcheck source=tests/lib.sh
source "$REPO/tests/lib.sh"

# fake systemctl: `show <unit> ...` prints the state in $FAKE_SD/<unit>, inactive when none; all else is a no-op
mkdir -p sd/bin
cat > sd/bin/systemctl <<'EOF'
#!/usr/bin/env bash
[ "${2:-}" = show ] || exit 0
cat "$FAKE_SD/$3" 2>/dev/null || echo inactive
EOF
chmod +x sd/bin/systemctl
FAKE_SD="$PWD/sd"; export FAKE_SD
PATH="$PWD/sd/bin:$PATH"; export PATH
export BLAST_OFF_WAIT_POLL=0.1
# a failed check leaves no wait behind: TERM each background subshell's timeout (it passes TERM on), then the subshell
stop_bg() { local p; for p in $(jobs -p); do pkill -P "$p" 2>/dev/null || true; kill "$p" 2>/dev/null || true; done; }
trap 'stop_bg; cleanup' EXIT

# job <suffix>: a fresh job (status running, phase 1 of 1) whose runner unit reads active
job() {
  new_job "$1" ok
  UNIT="blast-off-test-$$-$1"
  echo active > "sd/$UNIT.service"
}
# bw <name> [env...]: blast-off wait on $JOB in the background; output to <name>.out, then its rc to <name>.rc
bw() {
  local n="$1"; shift
  rm -f "$n.out" "$n.rc"
  ( set +e; env "$@" timeout 30 "$REPO/bin/blast-off" wait "$JOB" > "$n.out" 2>&1; echo $? > "$n.rc" ) &
}
blocks() { sleep 1; [ ! -e "$1.rc" ] || fail "wait returned before any change ($2): rc $(cat "$1.rc"): $(cat "$1.out")"; }
# ends <name> <rc> <text> <why>: wait returned rc with one line holding text
ends() {
  wait_until 10 test -s "$1.rc" || fail "wait did not return ($4): $(cat "$1.out")"
  [ "$(cat "$1.rc")" = "$2" ] || fail "wait exit $(cat "$1.rc"), want $2 ($4): $(cat "$1.out")"
  [ "$(wc -l < "$1.out")" -eq 1 ] || fail "wait printed $(wc -l < "$1.out") lines, want 1 ($4): $(cat "$1.out")"
  grep -qF -- "$3" "$1.out" || fail "wait line lacks '$3' ($4): $(cat "$1.out")"
}
ck() { sed -i "s/^$1:.*/$1: $2/" "$JOB/checkpoint.md"; }

# --- returns on child launch (the runner writes child-count before each launch) ---
job child; echo '0 0' > "$JOB/child-count"
bw c; blocks c "child-count 0 0"
echo '1 0' > "$JOB/child-count"
ends c 11 'child 1' "child launch"
grep -qE '^wait: changed · status: running · phase: 1 of 1 · child 1 · unit active · timer inactive$' c.out \
  || fail "wait line not in its documented shape: $(cat c.out)"

# --- returns on a phase change ---
job phase
bw p; blocks p "phase 1 of 1"
ck phase '2 of 3 — build'
ends p 11 'phase: 2 of 3 — build' "phase change"

# --- done and blocked: exit 0, on the change and at once when already there ---
job fin
bw d; blocks d "running"
ck status "done"
ends d 0 'wait: final · status: done' "status done"
echo inactive > "sd/$UNIT.service"
bw d2; ends d2 0 'status: done' "already done at start"
ck status blocked
bw b; ends b 0 'wait: final · status: blocked' "already blocked at start"

# --- unit gone but status still running (stop, crash, reboot): nothing will change on its own ---
job gone
bw g; blocks g "unit active"
echo inactive > "sd/$UNIT.service"
ends g 12 'wait: stuck · status: running' "unit went inactive"
grep -qF "blast-off status $JOB" g.out || fail "stuck line does not say what to run next: $(cat g.out)"
bw g2; ends g2 12 'unit inactive' "already stuck at start"
echo failed > "sd/$UNIT.service"
bw g3; ends g3 12 'unit failed' "a failed unit is not running"

# --- paused: paused-cap with nothing running needs the owner; paused-limit waits for its timer ---
job pause
bw pc; blocks pc "running"
echo inactive > "sd/$UNIT.service"; ck status paused-cap  # unit first: running or paused-cap, both are stuck
ends pc 12 'wait: stuck' "runner paused at the soft cap"
bw pc2; ends pc2 12 'wait: stuck · status: paused-cap' "already paused-cap at start"
ck status 'paused-limit until 2099-01-01T00:00:00Z'; echo active > "sd/$UNIT.resume.timer"
bw pl; blocks pl "paused-limit with its resume timer active"
echo active > "sd/$UNIT.service"
ends pl 11 'unit active · timer active' "the timer started the unit"
rm "sd/$UNIT.resume.timer"; echo inactive > "sd/$UNIT.service"
bw pl2; ends pl2 12 'status: paused-limit until 2099-01-01T00:00:00Z' "paused-limit with no timer"

# --- nothing to watch: exit 1 with the reason ---
set +e
out="$(timeout 10 "$REPO/bin/blast-off" wait "$PWD/no-such-job" 2>&1)"; rc=$?
set -e
[ "$rc" = 1 ] || fail "wait on a missing job dir exit $rc, want 1: $out"
grep -qF "no job dir $PWD/no-such-job" <<<"$out" || fail "missing job dir: no reason: $out"
set +e
out="$(timeout 10 "$REPO/bin/blast-off" wait 2>&1)"; rc=$?
set -e
[ "$rc" = 1 ] && grep -qF 'missing <job-dir>' <<<"$out" || fail "wait with no job dir: exit $rc: $out"
job nock; rm "$JOB/checkpoint.md"
set +e
out="$(timeout 10 "$REPO/bin/blast-off" wait "$JOB" 2>&1)"; rc=$?
set -e
[ "$rc" = 1 ] && grep -qF "missing $JOB/checkpoint.md" <<<"$out" || fail "wait with no checkpoint.md: exit $rc: $out"

# --- a machine sleep is no change: each poll sees the clock 10 h on, the state the same; wait keeps blocking ---
job sleep
mkdir -p clock
cat > clock/sleep <<'EOF'
#!/usr/bin/env bash
n=$(( $(cat "$CLOCK/polls" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$CLOCK/polls"
exec /usr/bin/env -u CLOCK PATH="$REAL_PATH" sleep 0.05
EOF
cat > clock/date <<'EOF'
#!/usr/bin/env bash
n=$(cat "$CLOCK/polls" 2>/dev/null || echo 0)
PATH="$REAL_PATH" exec date -d "@$(( 1800000000 + n * 36000 ))" "$@"
EOF
chmod +x clock/sleep clock/date
bw s CLOCK="$PWD/clock" REAL_PATH="$PATH" PATH="$PWD/clock:$PATH"
polled() { [ -e s.rc ] || [ "$(cat clock/polls 2>/dev/null || echo 0)" -ge 5 ]; }  # or wait ended
wait_until 10 polled || fail "wait did not poll through the fake sleep"
[ ! -e s.rc ] || fail "a 10 h clock jump per poll ended wait with no change: rc $(cat s.rc): $(cat s.out)"
echo '1 0' > "$JOB/child-count"
ends s 11 'child 1' "a change after the jumps"

echo "13-wait ok"
