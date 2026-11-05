#!/usr/bin/env bash
# 20-dead-child: a child that exits without its Stop hook is seen within 10 s, not at the timeout;
# its last screen goes to run.log and the next child resumes. A child that exits right after its
# Stop hook counts as finished, and a non-JSON Stop payload is logged, not a runner abort.
source "$REPO/tests/lib.sh"
use_fakes
export CLAUDE_FLAGS="--model fake --effort low" GH_TOKEN=dummy-not-a-token JOB_CHILD_TIMEOUT=60
bo="$REPO/bin/blast-off"

# child 1 dies (no Stop hook), child 2 finishes
new_job dead die 'done'
t0=$SECONDS; rc=0; "$bo" run "$JOB" > dead.out 2>&1 || rc=$?; took=$((SECONDS-t0))
log="$JOB/run.log"
[ "$rc" -eq 0 ] || fail "dead-child run exit $rc: $(cat dead.out)"
line="$(grep 'child 1 exited without its Stop hook after' "$log")" || fail "death not logged: $(cat "$log")"
secs="$(sed 's/.* after \([0-9]*\)s.*/\1/' <<<"$line")"
[ "$secs" -le 10 ] || fail "death seen after ${secs}s, want <= 10: $line"
[ "$took" -lt 40 ] || fail "run took ${took}s; death waited for the 60 s timeout"
grep -q 'fake child 1: API Error: fake death' "$log" || fail "dead child's screen not in run.log: $(cat "$log")"
grep -q 'child 2 launched' "$log" || fail "next child not launched after a death"
grep -q '^child=2 .* prev_alive=no$' "$JOB/fake-marker" || fail "dead child 1 still alive at child 2: $(cat "$JOB/fake-marker")"
grep -q 'timed out' "$log" && fail "death reported as a timeout: $(cat "$log")"

# a child that exits straight after its Stop hook finished, it did not die
new_job hookexit done-exit
rc=0; "$bo" run "$JOB" > hookexit.out 2>&1 || rc=$?
[ "$rc" -eq 0 ] || fail "done-exit run exit $rc: $(cat hookexit.out)"
grep -q '^fake child 1 did done-exit$' "$JOB/run.log" || fail "Stop payload of an exiting child not logged: $(cat "$JOB/run.log")"
grep -q 'exited without its Stop hook' "$JOB/run.log" && fail "finished child reported dead: $(cat "$JOB/run.log")"

# a non-JSON Stop payload is logged and the chain goes on (Q3)
new_job badpayload bad-payload
rc=0; "$bo" run "$JOB" > bad.out 2>&1 || rc=$?
[ "$rc" -eq 0 ] || fail "bad-payload run exit $rc: $(cat bad.out; cat "$JOB/run.log")"
grep -q '^child 1 Stop payload is not a JSON object: not json$' "$JOB/run.log" || fail "bad payload not logged: $(cat "$JOB/run.log")"
grep -q 'without a state' "$JOB/run.log" && fail "bad payload aborted the runner"
echo ok
