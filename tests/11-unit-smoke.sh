#!/usr/bin/env bash
# 11-unit-smoke: `install` writes the template and slice; `start` runs the job as the transient unit
# blast-off-test-<pid>-job.service in blast-off.slice to done; the child runs in its own
# -child-<n> scope in that slice; the template instance for the job dir resolves the absolute path
# (loaded, never started); `stop` ends a hanging second run: runner, scope and child all gone.
source "$REPO/tests/lib.sh"
use_fakes
export CLAUDE_FLAGS="--model fake --effort low" GH_TOKEN=dummy-not-a-token BLAST_OFF_TRUST_SECONDS=45
bo="$REPO/bin/blast-off"
udir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"

install_units > install.out 2>&1 || fail "install: $(cat install.out)"
grep -qx "ExecStart=$REPO/bin/blast-off run %f" "$udir/blast-off@.service" || fail "template ExecStart: $(grep ExecStart "$udir/blast-off@.service" 2>&1)"
grep -qx 'Slice=blast-off.slice' "$udir/blast-off@.service" || fail "template not in blast-off.slice"
grep -qx 'MemoryAccounting=yes' "$udir/blast-off.slice" || fail "slice not installed"

new_job job slow-done
unit="$TEST_ID-job.service"
"$bo" start "$JOB" > start.out 2>&1 || fail "start: $(cat start.out)"
grep -q -- "--unit=$TEST_ID-job" start.out && grep -q -- '--setenv=GH_TOKEN ' start.out || fail "launch not printed: $(cat start.out)"
grep -q -- '--setenv=BLAST_OFF_TRUST_SECONDS ' start.out || fail "start does not pass BLAST_OFF_TRUST_SECONDS: $(cat start.out)"
! grep -q dummy-not-a-token start.out || fail "start printed a secret value"

wait_until 20 test -s "$JOB/fake-marker" || fail "child never ran: $(cat "$JOB/run.log" 2>&1); $(journalctl --user -u "$unit" -n 20 --no-pager 2>&1)"
pid="$(sed -n 's/^child=1 pid=\([0-9]*\) .*/\1/p' "$JOB/fake-marker")"
show="$(systemctl --user show "$unit" -p ActiveState,Slice,MemoryCurrent,ExecMainPID)"
echo "$show"
grep -qx 'Slice=blast-off.slice' <<<"$show" || fail "runner not in blast-off.slice: $show"
grep -qE '^MemoryCurrent=[0-9]+$' <<<"$show" || fail "no MemoryCurrent: $show"
cg="$(cat "/proc/$pid/cgroup")"; echo "$cg"
[[ $cg == */blast-off.slice/$TEST_ID-job-child-1.scope ]] || fail "child not in its scope: $cg"
grep -q 'gh_token=set' "$JOB/fake-marker" || fail "child did not see GH_TOKEN"
"$bo" status "$JOB" > status.out 2>&1 || fail "status: $(cat status.out)"
grep -q '^status: running' status.out && grep -q '^ActiveState=active' status.out || fail "status output: $(cat status.out)"

wait_until 30 not_active "$unit" || fail "runner unit still $(unit_state "$unit")"
grep -q '^status: done' "$JOB/checkpoint.md" || fail "job not done under the unit: $(cat "$JOB/run.log")"
grep -q 'job done$' "$JOB/run.log" || fail "no 'job done' in run.log"
"$bo" logs "$JOB" > logs.out 2>&1 || fail "logs: $(cat logs.out)"
grep -q 'job done$' logs.out || fail "logs lacks run.log tail: $(cat logs.out)"

inst="blast-off@$(systemd-escape --path "$JOB").service"
exec_start="$(systemctl --user show "$inst" -p ExecStart --value)"; echo "$exec_start"
[[ $exec_start == *"argv[]=$REPO/bin/blast-off run $JOB ;"* ]] || fail "template instance ExecStart: $exec_start"
not_active "$inst" || fail "template instance was started"

# start_hang: rerun the job with a hanging child; sets pid (fake claude) and gc (its HUP-ignoring grandchild,
# a stand-in for a background subagent).
start_hang() {
  sed -i 's/^status: .*/status: running/' "$JOB/checkpoint.md"; echo hang > "$JOB/fake-mode"; rm -f "$JOB/fake-marker"
  "$bo" start "$JOB" > "start-$1.out" 2>&1 || fail "start ($1): $(cat "start-$1.out")"
  wait_until 20 grep -q '^grandchild=' "$JOB/fake-marker" || fail "hanging child never ran ($1)"
  pid="$(sed -n 's/^child=1 pid=\([0-9]*\) .*/\1/p' "$JOB/fake-marker")"
  gc="$(sed -n 's/^grandchild=\([0-9]*\)$/\1/p' "$JOB/fake-marker")"
}
gone() { ! kill -0 "$1" 2>/dev/null; }
scope="$TEST_ID-job-child-1.scope"

# blast-off stop ends runner, scope, child and grandchild
start_hang stop
"$bo" stop "$JOB" > stop.out 2>&1 || fail "stop: $(cat stop.out)"
not_active "$unit" || fail "runner still $(unit_state "$unit") after stop"
not_active "$scope" || fail "child scope still $(unit_state "$scope")"
wait_until 5 gone "$pid" || fail "child $pid alive after stop"
wait_until 5 gone "$gc" || fail "grandchild $gc alive after stop"

# stopping the runner unit directly: the runner's TERM trap stops the scope
start_hang trap
systemctl --user stop "$unit"
wait_until 5 gone "$gc" || fail "grandchild $gc alive after systemctl stop of the runner (trap path)"
not_active "$scope" || fail "child scope still $(unit_state "$scope") after runner stop"

# runner killed without its trap: the scope outlives it; blast-off stop's glob still ends it
start_hang kill
systemctl --user kill -s KILL --kill-whom=main "$unit"
wait_until 10 not_active "$unit" || fail "runner unit still $(unit_state "$unit") after SIGKILL"
kill -0 "$gc" 2>/dev/null || fail "grandchild died with the runner; this case no longer tests stop's scope glob"
"$bo" stop "$JOB" > stop3.out 2>&1 || fail "stop after runner kill: $(cat stop3.out)"
wait_until 5 gone "$gc" || fail "grandchild $gc alive after stop (scope glob path)"
echo ok
