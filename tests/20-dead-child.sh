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
grep -q 'child 1 left checkpoint.md unchanged (stall 1/2; it died)' "$log" || fail "a death's stall not labelled: $(cat "$log")"
grep -q '^child=2 .* prev_alive=no$' "$JOB/fake-marker" || fail "dead child 1 still alive at child 2: $(cat "$JOB/fake-marker")"
grep -q 'timed out' "$log" && fail "death reported as a timeout: $(cat "$log")"

# the owner's tmux config must not reach the job's server: a pane-died hook that closes the window
# would lose the dead child's screen (D2-2)
mkdir -p xdg/tmux; echo 'set-hook -g pane-died kill-pane' > xdg/tmux/tmux.conf
new_job ownconf die 'done'
rc=0; XDG_CONFIG_HOME="$PWD/xdg" "$bo" run "$JOB" > ownconf.out 2>&1 || rc=$?
[ "$rc" -eq 0 ] || fail "owner-config run exit $rc: $(cat ownconf.out)"
grep -q 'fake child 1: API Error: fake death' "$JOB/run.log" || fail "owner's tmux config closed the dead child's window: $(cat "$JOB/run.log")"

# a child whose window is closed (owner kills it, or a tmux hook does) is dead and seen within 10 s.
# Addressed by window index, a closed window's target fell back to the idle window 0 (pane_dead 0),
# so the death waited for the timeout; a pane id stops resolving (D2-1).
new_job winkill hang 'done'
"$bo" run "$JOB" > winkill.out 2>&1 & runner=$!
wait_until 20 grep -q '^child=1 ' "$JOB/fake-marker" || fail "winkill child never ran: $(cat winkill.out)"
tmux -L "$TEST_ID-winkill" kill-window -t "job-test-$$-winkill:1"
seen=0; wait_until 10 grep -q 'child 1 exited without its Stop hook' "$JOB/run.log" || seen=$?
kill -TERM "$runner" 2>/dev/null; wait "$runner" || true
[ "$seen" -eq 0 ] || fail "closed child window not seen as a death within 10 s: $(cat "$JOB/run.log")"

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

# child_wait alone, tmux stubbed: one failed `display` read (empty output) is not a death, but reads
# that keep failing (window or server gone) are; a Stop hook that lands between the loop's done.json
# check and a dead-pane read is a finish. Reads are counted in a file: $(tmux) is a subshell.
wait_stub() { # wait_stub <name> <read that writes done.json, 0 = none> <outputs per read; "" = failed; last repeats>
  ( source "$REPO/lib/child.sh"
    CHILD_DIR="$PWD/stub-$1"; mkdir -p "$CHILD_DIR"; echo 0 > "$CHILD_DIR/n"
    UNIT=stub CHILD_WIN=stub TIMEOUT=8 BLAST_OFF_TRUST_SECONDS=0
    done_at="$2" reads=("${@:3}")
    tmux() { # read n gets reads[n-1]
      local n; n=$(($(cat "$CHILD_DIR/n") + 1)); echo "$n" > "$CHILD_DIR/n"
      [ "$done_at" -eq 0 ] || [ "$n" -lt "$done_at" ] || echo '{}' > "$CHILD_DIR/done.json"
      local out="${reads[$((n <= ${#reads[@]} ? n - 1 : ${#reads[@]} - 1))]}"
      [ -n "$out" ] || return 1; echo "$out"
    }
    rc=0; child_wait || rc=$?; echo "$rc" )
}
[ "$(wait_stub transient 2 '' 0)" = 0 ] || fail "one failed pane_dead read counted as a death"
[ "$(wait_stub gone 0 '')" = 2 ] || fail "pane_dead reads that keep failing (window gone) not seen as a death"
[ "$(wait_stub racedone 1 1)" = 0 ] || fail "Stop hook done just before the dead-pane read counted as a death"
echo ok
