#!/usr/bin/env bash
# 13-wait: `blast-off wait <job-dir>` blocks until the status line, the phase, the child number or the unit
# changes, then prints one line: exit 0 at a done or blocked the runner logged in run.log, 11 on a change while
# the job still runs or is scheduled, 12 when on two polls nothing runs or is scheduled and the runner logged no
# end (stopped, crashed, rebooted, done refused, paused-cap), 1 when it cannot start watching. It compares state,
# never the clock (issue 14).
# systemctl is a fake local to this scenario: no real unit is read, started or installed.
# shellcheck source=tests/lib.sh
source "$REPO/tests/lib.sh"

# fake systemctl: `show <unit> ...` prints the state in $FAKE_SD/<unit>, inactive when none, and logs the unit to
# $FAKE_SD/calls; all else is a no-op. $FAKE_SD/fail makes it fail as with no user bus. $FAKE_SD/next runs once,
# right after a resume timer reads inactive: the timer's resume starting the unit, one poll later.
mkdir -p sd/bin
cat > sd/bin/systemctl <<'EOF'
#!/usr/bin/env bash
[ "${2:-}" = show ] || exit 0
[ ! -e "$FAKE_SD/fail" ] || { echo 'Failed to connect to bus: No such file or directory' >&2; exit 1; }
s="$(cat "$FAKE_SD/$3" 2>/dev/null || echo inactive)"; echo "$s"
echo "$3" >> "$FAKE_SD/calls"
[[ $s != inactive || $3 != *.resume.timer || ! -e $FAKE_SD/next ]] || { bash "$FAKE_SD/next"; rm "$FAKE_SD/next"; }
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
  rm -f "$n.out" "$n.rc"; : > sd/calls
  ( set +e; env "$@" timeout 30 "$REPO/bin/blast-off" wait "$JOB" > "$n.out" 2>&1; echo $? > "$n.rc" ) &
}
# polls: snapshots wait has taken (each reads the resume timer last); snapped <name> <n>: n taken, or wait returned
polls() { grep -c 'resume\.timer$' sd/calls || true; }
snapped() { [ -e "$1.rc" ] || [ "$(polls)" -ge "$2" ]; }
# blocks <name> <why>: wait took three more snapshots, so compared at least twice, and did not return
blocks() {
  wait_until 10 snapped "$1" $(( $(polls) + 3 )) || fail "wait took no 3 snapshots in 10 s ($2): $(cat "$1.out")"
  [ ! -e "$1.rc" ] || fail "wait returned before any change ($2): rc $(cat "$1.rc"): $(cat "$1.out")"
}
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

# --- child-written text: the status word (and a paused-limit's until) only; the phase with no control characters,
# no field separator, at most 80 characters (P6R1-7) ---
job esc
printf '# Checkpoint: test\n\nstatus: running · phase: 9 of 9 · child 99 · unit active\nphase: 1 of 1 \033[31mred\033]0;t\007 · child 9 %s\n' \
  "$(printf 'x%.0s' {1..200})" > "$JOB/checkpoint.md"
bw e; blocks e "running"
echo '1 0' > "$JOB/child-count"
ends e 11 'wait: changed · status: running · phase: 1 of 1 [31mred]0;t - child 9 xx' "child-written text"
l="$(cat e.out)"; f="${l#*phase: }"; f="phase: ${f%% · child 1 ·*}"
[[ $l != *[[:cntrl:]]* ]] || fail "a control character reached the line: $(cat -v e.out)"
[ "${#f}" -le 80 ] || fail "phase field is ${#f} characters, want at most 80: $f"
[[ $l =~ ^'wait: changed · status: running · phase: 1 of 1 [31mred]0;t - child 9 'x+' · child 1 · unit active · timer inactive'$ ]] ||
  fail "child-written fields reached the line: $l"

# --- done and blocked: exit 0 only once the runner logged the job's end in run.log (owner ruling P6R1-1) ---
job fin
bw d; blocks d "running"
ck status "done"
blocks d "status done the runner has not logged: it may still refuse it (receipts, CI)"
echo "$(date -u +%FT%TZ) job done" >> "$JOB/run.log"
ends d 0 'wait: final · status: done' "the runner logged job done"
echo inactive > "sd/$UNIT.service"
bw d2; ends d2 0 'status: done' "already done at start"
# refused (exit 9 or 10, status left done): the runner's last line is the refusal; a child's text after it has
# no timestamp. Nothing will move: stuck, never final.
{ echo "$(date -u +%FT%TZ) phase row 1 is done but names no commit; fix it"; echo 'job done'; } >> "$JOB/run.log"
bw d3; ends d3 12 'wait: stuck · status: done' "done refused by the runner"
ck status blocked
echo "$(date -u +%FT%TZ) job blocked; see $JOB/checkpoint.md" >> "$JOB/run.log"
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
grep -qF "; paused-cap: run blast-off resume $JOB" pc2.out || fail "paused-cap line does not say to resume: $(cat pc2.out)"
ck status 'paused-limit until 2099-01-01T00:00:00Z'; echo active > "sd/$UNIT.resume.timer"
bw pl; blocks pl "paused-limit with its resume timer active"
echo active > "sd/$UNIT.service"
ends pl 11 'unit active · timer active' "the timer started the unit"
rm "sd/$UNIT.resume.timer"; echo inactive > "sd/$UNIT.service"
bw pl2; ends pl2 12 'status: paused-limit until 2099-01-01T00:00:00Z' "paused-limit with no timer"

# --- a status-only change with the unit up (usage_pause writes paused-limit before it arms the timer): 11 ---
job st
bw st; blocks st "running"
ck status 'paused-limit until 2099-01-01T00:00:00Z'
ends st 11 'wait: changed · status: paused-limit until 2099-01-01T00:00:00Z · phase: 1 of 1 · child' "status only"

# --- a unit still activating (start or resume under way) is not stuck ---
job act; echo activating > "sd/$UNIT.service"
bw a; blocks a "unit activating"
echo active > "sd/$UNIT.service"
ends a 11 'unit active · timer inactive' "the unit came up"

# --- the resume timer's handoff: it reads gone one poll before its runner is up; not stuck (P6R1-3) ---
job hand; ck status 'paused-limit until 2099-01-01T00:00:00Z'
echo inactive > "sd/$UNIT.service"; echo active > "sd/$UNIT.resume.timer"
bw h; blocks h "paused-limit with its resume timer active"
echo "echo active > '$PWD/sd/$UNIT.service'" > sd/next  # runs right after the first poll that reads the timer gone
rm "sd/$UNIT.resume.timer"
ends h 11 'unit active · timer inactive' "one poll with the timer gone and the unit not up yet"
[ ! -e sd/next ] || fail "no poll read the timer gone: the handoff was not exercised"

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
job bus; touch sd/fail
set +e
out="$(timeout 10 "$REPO/bin/blast-off" wait "$JOB" 2>&1)"; rc=$?
set -e
rm sd/fail
[ "$rc" = 1 ] && grep -qF "systemctl --user show $UNIT" <<<"$out" || fail "wait with systemctl failing at start: exit $rc: $out"
for v in 0 inf abc 0.05 3601 --help; do  # the unit is up, so a wait that took the value would block
  set +e
  out="$(BLAST_OFF_WAIT_POLL="$v" timeout 10 "$REPO/bin/blast-off" wait "$JOB" 2>&1)"; rc=$?
  set -e
  [ "$rc" = 1 ] && [ "$out" = "blast-off: BLAST_OFF_WAIT_POLL='$v' is not a number of seconds from 0.1 to 3600" ] ||
    fail "BLAST_OFF_WAIT_POLL=$v: exit $rc, want 1 before watching: $out"
done

# --- a read that fails mid-watch (checkpoint.md empty mid-rewrite, systemctl failing) is retried, not exit 1 ---
job retry
bw r; blocks r "running"
: > "$JOB/checkpoint.md"; sleep 1
[ ! -e r.rc ] || fail "an empty checkpoint.md mid-watch ended wait: rc $(cat r.rc): $(cat r.out)"
printf '# Checkpoint: test\n\nstatus: running\nphase: 1 of 1\n\n## Next action\nnone\n' > "$JOB/checkpoint.md"
touch sd/fail; sleep 1
[ ! -e r.rc ] || fail "systemctl failing mid-watch ended wait: rc $(cat r.rc): $(cat r.out)"
rm sd/fail; blocks r "reads back, nothing changed"
echo '1 0' > "$JOB/child-count"
ends r 11 'wait: changed · status: running · phase: 1 of 1 · child 1' "a change after failed reads"

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
