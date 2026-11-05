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
echo ok
