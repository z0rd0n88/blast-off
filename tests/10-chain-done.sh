#!/usr/bin/env bash
# 10-chain-done: `run` drives the fake child from running to done (0) and blocked (3); a child that
# hangs past JOB_CHILD_TIMEOUT is logged as timed out and the next launches; two unchanged
# checkpoints in a row give exit 5. The child sees GH_TOKEN through the runner's private tmux server.
source "$REPO/tests/lib.sh"
use_fakes
export CLAUDE_FLAGS="--model fake --effort low" GH_TOKEN=dummy-not-a-token JOB_CHILD_TIMEOUT=30
bo="$REPO/bin/blast-off"

# running -> done over two children
new_job ok step 'done'
rc=0; "$bo" run "$JOB" > done.out 2>&1 || rc=$?
[ "$rc" -eq 0 ] || fail "done run exit $rc: $(cat done.out)"
grep -q '^status: done' "$JOB/checkpoint.md" || fail "checkpoint not done"
log="$JOB/run.log"
grep -q 'child 1 launched' "$log" && grep -q 'child 2 launched' "$log" || fail "launch lines missing: $(cat "$log")"
grep -q "(watch: tmux -L $TEST_ID-ok attach -t job-test-$$-ok)" "$log" || fail "watch line wrong: $(cat "$log")"
grep -q '^child 2 session=fake-2 transcript=/dev/null$' "$log" || fail "done.json not logged: $(cat "$log")"
grep -q '^fake child 2 did done$' "$log" || fail "last message not logged"
grep -q 'job done$' "$log" || fail "no 'job done' line"
[ "$(grep -c 'gh_token=set' "$JOB/fake-marker")" -eq 2 ] || fail "fake child marker: $(cat "$JOB/fake-marker" 2>&1)"
! tmux -L "$TEST_ID-ok" has-session 2>/dev/null || fail "runner left its tmux server running after exit"

# running -> blocked
new_job blocked blocked
rc=0; "$bo" run "$JOB" > blocked.out 2>&1 || rc=$?
[ "$rc" -eq 3 ] || fail "blocked run exit $rc: $(cat blocked.out)"
grep -q "job blocked; see $JOB/checkpoint.md" "$JOB/run.log" || fail "no blocked line: $(cat "$JOB/run.log")"
grep -q 'mode=blocked' "$JOB/fake-marker" || fail "fake child never ran"

# child 1 hangs past the timeout (stall 1), child 2 changes nothing (stall 2) -> exit 5
new_job stall hang noop
rc=0; JOB_CHILD_TIMEOUT=2 "$bo" run "$JOB" > stall.out 2>&1 || rc=$?
[ "$rc" -eq 5 ] || fail "stall run exit $rc: $(cat stall.out)"
log="$JOB/run.log"
grep -q 'child 1 timed out after 2s; killing it, next child resumes from checkpoint' "$log" || fail "no timeout line: $(cat "$log")"
grep -q 'child 2 launched' "$log" || fail "next child not launched after timeout"
grep -q 'child 1 left checkpoint.md unchanged (stall 1/2)' "$log" || fail "no stall 1 line"
grep -q 'two stalls; stopping' "$log" || fail "no two-stalls line"
hung="$(sed -n 's/^child=1 pid=\([0-9]*\) .*/\1/p' "$JOB/fake-marker")"
[ -n "$hung" ] || fail "hung child never ran"
! kill -0 "$hung" 2>/dev/null || fail "timed-out child $hung still alive"
grep -q 'child 3 launched' "$log" && fail "a third child launched after two stalls"
gc="$(sed -n 's/^grandchild=\([0-9]*\)$/\1/p' "$JOB/fake-marker")"
[ -n "$gc" ] || fail "hung child started no grandchild"
! kill -0 "$gc" 2>/dev/null || fail "timed-out child's HUP-ignoring grandchild $gc still alive (scope not stopped)"

# progress resets the stall count: noop (1), step (reset), noop (1), noop (2) -> exit 5 at child 4
new_job reset noop step noop noop
rc=0; "$bo" run "$JOB" > reset.out 2>&1 || rc=$?
[ "$rc" -eq 5 ] || fail "reset run exit $rc: $(cat reset.out)"
grep -q 'child 4 launched' "$JOB/run.log" || fail "stall count not reset by progress: $(cat "$JOB/run.log")"
grep -q 'child 5 launched' "$JOB/run.log" && fail "child 5 launched after two stalls in a row"

# hard child cap: JOB_MAX_CHILDREN=1, child 1 makes progress -> exit 4 before child 2
new_job cap step
rc=0; JOB_MAX_CHILDREN=1 "$bo" run "$JOB" > cap.out 2>&1 || rc=$?
[ "$rc" -eq 4 ] || fail "cap run exit $rc: $(cat cap.out)"
grep -q 'child cap 1 reached' "$JOB/run.log" || fail "no cap line: $(cat "$JOB/run.log")"
grep -q 'child 2 launched' "$JOB/run.log" && fail "child 2 launched past the cap"

# a Stop payload written slowly is read only once complete
new_job slowhook slow-hook
rc=0; "$bo" run "$JOB" > slowhook.out 2>&1 || rc=$?
[ "$rc" -eq 0 ] || fail "slow-hook run exit $rc: $(cat slowhook.out; cat "$JOB/run.log")"
grep -q '^fake child 1 did slow-hook$' "$JOB/run.log" || fail "slow payload not logged whole"

# a scope left by an earlier run of the same job is stopped before child 1 reuses its name
systemd-run --user --scope --quiet --collect --unit="$TEST_ID-stray-child-1.scope" sleep 600 & stray=$!
wait_until 5 test "$(unit_state "$TEST_ID-stray-child-1.scope")" = active || fail "stray scope never started"
new_job stray 'done'
rc=0; "$bo" run "$JOB" > stray.out 2>&1 || rc=$?
[ "$rc" -eq 0 ] && grep -q 'mode=done' "$JOB/fake-marker" || fail "run beside a stale scope: exit $rc: $(cat "$JOB/run.log")"
wait_until 5 eval "! kill -0 $stray 2>/dev/null" || fail "stale scope's process $stray still alive"

# SIGHUP (terminal closed) on a foreground runner: child, grandchild and tmux server all end
new_job hup hang
"$bo" run "$JOB" > hup.out 2>&1 & runner=$!
wait_until 20 grep -q '^grandchild=' "$JOB/fake-marker" || fail "hup child never ran"
hung="$(sed -n 's/^child=1 pid=\([0-9]*\) .*/\1/p' "$JOB/fake-marker")"
gc="$(sed -n 's/^grandchild=\([0-9]*\)$/\1/p' "$JOB/fake-marker")"
kill -HUP "$runner"; rc=0; wait "$runner" || rc=$?
[ "$rc" -eq 129 ] || fail "runner exit after SIGHUP: $rc"
wait_until 5 eval "! kill -0 $hung 2>/dev/null && ! kill -0 $gc 2>/dev/null" || fail "child $hung or grandchild $gc alive after runner SIGHUP"
! tmux -L "$TEST_ID-hup" has-session 2>/dev/null || fail "tmux server alive after runner SIGHUP"

# the trust dialog is answered only while a child starts; its text later on screen gets no keys
export BLAST_OFF_TRUST_SECONDS=2
new_job trustearly trust-early
"$bo" run "$JOB" > te.out 2>&1 || fail "trust-early run: $(cat te.out)"
grep -q '^keys=yes$' "$JOB/fake-marker" || fail "trust dialog at start not answered: $(cat "$JOB/fake-marker")"
new_job trustlate trust-late
"$bo" run "$JOB" > tl.out 2>&1 || fail "trust-late run: $(cat tl.out)"
grep -q '^keys=no$' "$JOB/fake-marker" || fail "keys typed into a working child: $(cat "$JOB/fake-marker")"
echo ok
