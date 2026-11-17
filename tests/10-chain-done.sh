#!/usr/bin/env bash
# 10-chain-done: `run` drives the fake child from running to done (0) and blocked (3); a child that
# hangs past JOB_CHILD_TIMEOUT is logged as timed out and the next launches; two unchanged
# checkpoints in a row give exit 5. The child sees GH_TOKEN through the runner's private tmux server.
source "$REPO/tests/lib.sh"
use_fakes
export CLAUDE_FLAGS="--model fake --effort low" GH_TOKEN=dummy-not-a-token JOB_CHILD_TIMEOUT=30
bo="$REPO/bin/blast-off"

# running -> done over two children; finished child 1's scope stop ends its HUP-ignoring grandchild
new_job ok bg-step 'done'
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
[ "$(grep -c '^claude_env=0$' "$JOB/fake-marker")" -eq 2 ] || fail "a child saw a CLAUDE* name (CLAUDE_FLAGS is exported above): $(cat "$JOB/fake-marker")"
grep -q '^child=2 .* prev_alive=no$' "$JOB/fake-marker" || fail "finished child 1 still alive when child 2 launched: $(cat "$JOB/fake-marker")"
grep -qx 'prev_gc_alive=no' "$JOB/fake-marker" || fail "finished child 1's HUP-ignoring grandchild alive when child 2 launched (scope not stopped): $(cat "$JOB/fake-marker")"
! tmux -L "$TEST_ID-ok" has-session 2>/dev/null || fail "runner left its tmux server running after exit"
# each child's settings dir is named for the job and removed once the child ends (P2-L1)
gone_dirs() {
  local d; d="$(sed -n 's/^settings=//p' "$JOB/fake-marker")"; [ -n "$d" ] || fail "no settings line: $(cat "$JOB/fake-marker")"
  while IFS= read -r d; do
    [[ $(basename "$(dirname "$d")") == "$TEST_ID-$1-child."* ]] || fail "child dir $d not named $TEST_ID-$1-child.*"
    [ ! -e "$(dirname "$d")" ] || fail "child dir $(dirname "$d") left after the run"
  done <<< "$(sed -n 's/^settings=//p' "$JOB/fake-marker")"
}
gone_dirs ok
grep -qx 'prev_dir=gone' "$JOB/fake-marker" || fail "child 1's dir still there when child 2 launched: $(cat "$JOB/fake-marker")"

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
grep -q '^child=2 .* prev_alive=no$' "$JOB/fake-marker" || fail "timed-out child 1 still alive when child 2 launched: $(cat "$JOB/fake-marker")"
grep -qx 'prev_gc_alive=no' "$JOB/fake-marker" || fail "timed-out child 1's grandchild alive when child 2 launched (scope not stopped): $(cat "$JOB/fake-marker")"
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
grep -q 'child cap 1 (hard: no Phase plan row the runner reads in checkpoint.md; done is refused (exit 10) until it has one)' "$JOB/run.log" || fail "hard cap source not logged: $(cat "$JOB/run.log")"
grep -q 'child cap 1 reached' "$JOB/run.log" || fail "no cap line: $(cat "$JOB/run.log")"
grep -q '^status: running$' "$JOB/checkpoint.md" || fail "hard cap changed the status"
grep -q '^child=1 ' "$JOB/fake-marker" 2>/dev/null || fail "cap 1 stopped the job before child 1 ran: $(cat "$JOB/run.log")"
grep -q 'child 2 launched' "$JOB/run.log" && fail "child 2 launched past the cap"
# the cap is per job, not per run (issue 22): a re-run at the same cap launches nothing, and one at
# cap 2 numbers its child 2, then stops at the cap counted over both runs
rc=0; JOB_MAX_CHILDREN=1 "$bo" run "$JOB" > cap2.out 2>&1 || rc=$?
[ "$rc" -eq 4 ] || fail "re-run at a reached cap exit $rc, want 4: $(cat cap2.out "$JOB/run.log")"
[ "$(grep -c 'child [0-9]* launched' "$JOB/run.log")" -eq 1 ] || fail "re-run at a reached cap launched a child: $(cat "$JOB/run.log")"
rc=0; JOB_MAX_CHILDREN=2 "$bo" run "$JOB" > cap3.out 2>&1 || rc=$?
[ "$rc" -eq 4 ] || fail "re-run at cap 2 exit $rc, want 4: $(cat cap3.out "$JOB/run.log")"
[ "$(grep -c 'child 1 launched' "$JOB/run.log")" -eq 1 ] || fail "child numbering restarted at 1 on a re-run: $(cat "$JOB/run.log")"
grep -q 'child 2 launched' "$JOB/run.log" || fail "re-run at cap 2 launched no child 2: $(cat "$JOB/run.log")"
grep -q 'child 3 launched' "$JOB/run.log" && fail "child 3 launched past cap 2 counted over two runs"
grep -q 'child cap 2 reached' "$JOB/run.log" || fail "no cap line after the re-run: $(cat "$JOB/run.log")"
# a child count file that is not two whole numbers stops the runner before any child; it never reads as 0
nbad=0; for bad in '' 'x' '1' '08 0' '1 2' '-1 0'; do
  new_job "badcount-$((++nbad))" step; printf '%s\n' "$bad" > "$JOB/child-count"
  rc=0; JOB_MAX_CHILDREN=1 "$bo" run "$JOB" > badcount.out 2>&1 || rc=$?
  [ "$rc" -eq 1 ] && [ ! -e "$JOB/fake-marker" ] && grep -q "$JOB/child-count" badcount.out || fail "child-count '$bad': exit $rc, want 1 before any child: $(cat badcount.out)"
  [ "$(cat "$JOB/child-count")" = "$bad" ] || fail "child-count '$bad' was rewritten"
done

# a Stop payload written slowly is read only once complete
new_job slowhook slow-hook
rc=0; "$bo" run "$JOB" > slowhook.out 2>&1 || rc=$?
[ "$rc" -eq 0 ] || fail "slow-hook run exit $rc: $(cat slowhook.out; cat "$JOB/run.log")"
grep -q '^fake child 1 did slow-hook$' "$JOB/run.log" || fail "slow payload not logged whole"

# a scope left by an earlier run of the same job is stopped before child 1 reuses its name
systemd-run --user --scope --quiet --collect --unit="$TEST_ID-stray-child-1.scope" sleep 600 & stray=$!
wait_until 5 is_active "$TEST_ID-stray-child-1.scope" || fail "stray scope never started"
new_job stray 'done'
stale="${XDG_RUNTIME_DIR:-/tmp}/$TEST_ID-stray-child.stale"; mkdir -p "$stale"  # a SIGKILLed runner's dir
rc=0; "$bo" run "$JOB" > stray.out 2>&1 || rc=$?
[ "$rc" -eq 0 ] && grep -q '^child=1 .*mode=done' "$JOB/fake-marker" || fail "run beside a stale scope: exit $rc: $(cat "$JOB/run.log")"
grep -q 'child 2 launched' "$JOB/run.log" && fail "child 1 failed to start beside a stale scope: $(cat "$JOB/run.log")"
[ ! -e "$stale" ] || fail "an earlier run's child dir $stale left after a re-run"
wait_until 5 eval "! kill -0 $stray 2>/dev/null" || fail "stale scope's process $stray still alive"

# SIGHUP (terminal closed) on a foreground runner: child, grandchild and tmux server all end
new_job hup hang
"$bo" run "$JOB" > hup.out 2>&1 & runner=$!
wait_until 20 grep -q '^grandchild=' "$JOB/fake-marker" || fail "hup child never ran"
hung="$(sed -n 's/^child=1 pid=\([0-9]*\) .*/\1/p' "$JOB/fake-marker")"
gc="$(sed -n 's/^grandchild=\([0-9]*\)$/\1/p' "$JOB/fake-marker")"
kill -HUP "$runner"; rc=0; wait "$runner" || rc=$?
[ "$rc" -eq 129 ] || fail "runner exit after SIGHUP: $rc"
grep -q 'runner exit 129 without a state' "$JOB/run.log" || fail "SIGHUP not logged: $(cat "$JOB/run.log")"
wait_until 5 eval "! kill -0 $hung 2>/dev/null && ! kill -0 $gc 2>/dev/null" || fail "child $hung or grandchild $gc alive after runner SIGHUP"
! tmux -L "$TEST_ID-hup" has-session 2>/dev/null || fail "tmux server alive after runner SIGHUP"
gone_dirs hup
# the count is saved before a child launches: child 1, cut off by the runner's end (a reboot), counts
rc=0; JOB_MAX_CHILDREN=1 "$bo" run "$JOB" > hup2.out 2>&1 || rc=$?
[ "$rc" -eq 4 ] || fail "re-run after a runner cut off child 1, cap 1: exit $rc, want 4: $(cat hup2.out "$JOB/run.log")"
[ "$(grep -c 'child [0-9]* launched' "$JOB/run.log")" -eq 1 ] || fail "a child launched past cap 1 after a relaunch: $(cat "$JOB/run.log")"

# a runner abort is logged and never reads as a state: a python3 that exits 4 fails child_report
# with the cap's code under set -e; the runner exits 1 and run.log ends with the abort line
new_job abort 'done'
mkdir -p badpy; printf '#!/bin/sh\nexit 4\n' > badpy/python3; chmod +x badpy/python3
rc=0; PATH="$PWD/badpy:$PATH" "$bo" run "$JOB" > abort.out 2>&1 || rc=$?
[ "$rc" -eq 1 ] || fail "runner abort exit $rc, want 1: $(cat abort.out)"
tail -n 1 "$JOB/run.log" | grep -q 'runner exit 4 without a state' || fail "abort not logged: $(cat "$JOB/run.log")"
! tmux -L "$TEST_ID-abort" has-session 2>/dev/null || fail "tmux server alive after runner abort"

# a second signal while chain_exit stops the child scopes is ignored: the job's tmux server still ends,
# the exit is logged and the first signal's code stands; a slow systemctl holds that cleanup open
new_job sig2 hang
mkdir -p slowctl
printf '#!/bin/sh\ncase "$*" in *"-child-*.scope"*) touch %s/stopping; sleep 3 ;; esac\nexec %s "$@"\n' \
  "$PWD" "$(command -v systemctl)" > slowctl/systemctl; chmod +x slowctl/systemctl
PATH="$PWD/slowctl:$PATH" "$bo" run "$JOB" > sig2.out 2>&1 & runner=$!
wait_until 20 grep -q '^grandchild=' "$JOB/fake-marker" || fail "sig2 child never ran"
rm -f stopping
kill -HUP "$runner"
wait_until 5 test -e stopping || fail "runner cleanup never reached the scope stop"
kill -TERM "$runner"; rc=0; wait "$runner" || rc=$?
[ "$rc" -eq 129 ] || fail "runner exit after SIGHUP then SIGTERM during cleanup: $rc, want 129"
grep -q 'runner exit 129 without a state' "$JOB/run.log" || fail "SIGHUP exit not logged: $(cat "$JOB/run.log")"
! tmux -L "$TEST_ID-sig2" has-session 2>/dev/null || fail "tmux server alive after a second signal during cleanup"

# the trust dialog is answered only while a child starts (the default window: unset here, so the
# default is what is tested); its text later on screen gets no keys (a 2 s window; the fake shows it at 3 s)
new_job trustearly trust-early
env -u BLAST_OFF_TRUST_SECONDS "$bo" run "$JOB" > te.out 2>&1 || fail "trust-early run: $(cat te.out)"
grep -q '^keys=yes$' "$JOB/fake-marker" || fail "trust dialog at start not answered: $(cat "$JOB/fake-marker")"
new_job trustlate trust-late
BLAST_OFF_TRUST_SECONDS=2 "$bo" run "$JOB" > tl.out 2>&1 || fail "trust-late run: $(cat tl.out)"
grep -q '^keys=no$' "$JOB/fake-marker" || fail "keys typed into a working child: $(cat "$JOB/fake-marker")"
echo ok
