#!/usr/bin/env bash
# 23-runner-lock: one runner per job unit (D1-6). A second `run` of a job whose runner is alive exits 1
# before it touches anything, so the first runner's child lives on; a lock left by a dead runner, or
# naming a pid that is no blast-off runner, is taken over.
source "$REPO/tests/lib.sh"
use_fakes
export CLAUDE_FLAGS="--model fake --effort low" GH_TOKEN=dummy-not-a-token JOB_CHILD_TIMEOUT=60
bo="$REPO/bin/blast-off"

new_job lock hang
lock="${XDG_RUNTIME_DIR:-/tmp}/$TEST_ID-lock.lock"
"$bo" run "$JOB" > first.out 2>&1 & first=$!
wait_until 20 grep -q '^grandchild=' "$JOB/fake-marker" || fail "first runner's child never ran: $(cat first.out)"
child="$(sed -n 's/^child=1 pid=\([0-9]*\) .*/\1/p' "$JOB/fake-marker")"
[ "$(cut -d' ' -f1 "$lock")" = "$first" ] || fail "lock $lock does not hold the first runner's pid $first: $(cat "$lock" 2>&1)"
rc=0; "$bo" run "$JOB" > second.out 2>&1 || rc=$?
[ "$rc" -eq 1 ] || fail "second runner exit $rc, want 1: $(cat second.out)"
grep -q "runner $first already drives $TEST_ID-lock" second.out || fail "no lock message: $(cat second.out)"
kill -0 "$child" 2>/dev/null || fail "second runner killed the first runner's child $child"
[ "$(grep -c '^child=' "$JOB/fake-marker")" -eq 1 ] || fail "second runner launched a child"
kill -TERM "$first"; wait "$first" || true
[ ! -e "$lock" ] || fail "runner exit left its lock: $(cat "$lock")"

# a runner started through a symlink of another name holds the lock just the same (D2-3)
new_job link hang
ln -s "$bo" ./bo-link
./bo-link run "$JOB" > link1.out 2>&1 & first=$!
wait_until 20 grep -q '^child=1 ' "$JOB/fake-marker" || fail "symlinked runner's child never ran: $(cat link1.out)"
rc=0; "$bo" run "$JOB" > link2.out 2>&1 || rc=$?
kill -TERM "$first"; wait "$first" || true
[ "$rc" -eq 1 ] || fail "second runner beside a symlink-started one exit $rc, want 1: $(cat link2.out)"
[ "$(grep -c '^child=' "$JOB/fake-marker")" -eq 1 ] || fail "second runner launched a child beside a symlink-started one"

# a stale lock (dead pid) and a lock naming some other live process are both taken over
new_job stale 'done'
lock="${XDG_RUNTIME_DIR:-/tmp}/$TEST_ID-stale.lock"
true & dead=$!; wait "$dead"; echo "$dead" > "$lock"
rc=0; "$bo" run "$JOB" > stale.out 2>&1 || rc=$?
[ "$rc" -eq 0 ] || fail "run over a dead runner's lock exit $rc: $(cat stale.out)"
sleep 600 & other=$!; echo "$other" > "$lock"
sed -i 's/^status: .*/status: running/' "$JOB/checkpoint.md"
rc=0; "$bo" run "$JOB" > other.out 2>&1 || rc=$?
kill "$other"
[ "$rc" -eq 0 ] || fail "run over a lock naming a non-runner pid exit $rc: $(cat other.out)"
[ ! -e "$lock" ] || fail "lock left after a clean exit"
echo ok
