#!/usr/bin/env bash
# 31-resume-after-reset: `blast-off resume` refuses a paused-limit job before its reset (exit 8,
# nothing changed) and, after it, sets running and starts the runner unit; paused-cap resumes too;
# `run` continues a paused-limit job whose reset has passed. The resume timer armed at exit 8 fires
# for real at the reset, and the job it starts runs to done.
source "$REPO/tests/lib.sh"
use_fakes
export CLAUDE_FLAGS="--model fake --effort low" GH_TOKEN=dummy-not-a-token JOB_CHILD_TIMEOUT=30
export BLAST_OFF_STATE_DIR="$PWD/state" JOB_RESUME_MARGIN=0
mkdir -p "$BLAST_OFF_STATE_DIR"
bo="$REPO/bin/blast-off"
install_units
iso() { date -u -d "@$1" +%FT%TZ; }
pause() { sed -i "s/^status: .*/status: $1/" "$JOB/checkpoint.md"; }

# before the reset: exit 8, status and unit untouched
new_job early 'done'
until="$(iso $(( $(date +%s) + 3600 )))"; pause "paused-limit until $until"
rc=0; "$bo" resume "$JOB" > early.out 2>&1 || rc=$?
[ "$rc" -eq 8 ] || fail "resume before the reset exit $rc, want 8: $(cat early.out)"
grep -q "paused-limit until $until" early.out || fail "refusal does not say when: $(cat early.out)"
grep -qx "status: paused-limit until $until" "$JOB/checkpoint.md" || fail "early resume changed the status"
not_active "$TEST_ID-early.service" || fail "early resume started the runner"
# nothing paused: a usage error
pause running
rc=0; "$bo" resume "$JOB" > norun.out 2>&1 || rc=$?
[ "$rc" -eq 1 ] && grep -q "resume acts only on paused-cap or paused-limit" norun.out || fail "resume of a running job exit $rc: $(cat norun.out)"

# after the reset: running, the unit runs the job to done
new_job late 'done'
pause "paused-limit until $(iso $(( $(date +%s) - 10 )))"
# with GH_TOKEN unset it refuses before it changes anything
rc=0; env -u GH_TOKEN "$bo" resume "$JOB" > nogh.out 2>&1 || rc=$?
[ "$rc" -eq 1 ] && grep -q '^status: paused-limit until' "$JOB/checkpoint.md" || fail "resume with no GH_TOKEN exit $rc: $(cat nogh.out; head -4 "$JOB/checkpoint.md")"
"$bo" resume "$JOB" > late.out 2>&1 || fail "resume after the reset: $(cat late.out)"
wait_until 30 grep -q '^status: done$' "$JOB/checkpoint.md" || fail "resumed job not done: $(cat late.out "$JOB/run.log")"
grep -q "resume: starting $TEST_ID-late.service" "$JOB/run.log" || fail "resume not logged: $(cat "$JOB/run.log")"
grep -q 'status paused-limit -> running; the reset has passed' "$JOB/run.log" || fail "runner did not clear the pause: $(cat "$JOB/run.log")"
[ "$(sed -n 's/^status_at_start=//p' "$JOB/fake-marker")" = running ] || fail "child launched under $(cat "$JOB/fake-marker")"
wait_until 10 not_active "$TEST_ID-late.service" || fail "runner unit still active after done"

# D3-1: the timer can fire while the old runner unit is still stopping; resume waits for it, then
# starts. A start that fails leaves the job paused, never `running` with no runner.
new_job busy 'done'
pause "paused-limit until $(iso $(( $(date +%s) - 10 )))"
systemd-run --user --quiet --collect --unit="$TEST_ID-busy" sleep 4 || fail "busy stand-in unit did not start"
"$bo" resume "$JOB" > busy.out 2>&1 || fail "resume beside a stopping runner unit: $(cat busy.out)"
wait_until 30 grep -q '^status: done$' "$JOB/checkpoint.md" || fail "busy job not done: $(cat busy.out "$JOB/run.log")"
new_job nostart 'done'
pause "paused-limit until $(iso $(( $(date +%s) - 10 )))"
mkdir -p badrun; printf '#!/bin/sh\necho "fake systemd-run: refused" >&2; exit 1\n' > badrun/systemd-run; chmod +x badrun/systemd-run
rc=0; PATH="$PWD/badrun:$PATH" "$bo" resume "$JOB" > nostart.out 2>&1 || rc=$?
[ "$rc" -ne 0 ] || fail "resume with a failing start exit 0"
grep -q '^status: paused-limit until' "$JOB/checkpoint.md" || fail "failed start left status $(sed -n 's/^status: //p' "$JOB/checkpoint.md")"
grep -q "resume: start of $TEST_ID-nostart.service failed" "$JOB/run.log" || fail "failed start not logged: $(cat "$JOB/run.log")"

# paused-cap resumes the same way
new_job cap 'done'
pause paused-cap
"$bo" resume "$JOB" > cap.out 2>&1 || fail "resume of paused-cap: $(cat cap.out)"
wait_until 30 grep -q '^status: done$' "$JOB/checkpoint.md" || fail "paused-cap job not done after resume: $(cat cap.out "$JOB/run.log")"

# run on a paused-limit job whose reset has passed continues
new_job rerun 'done'
pause "paused-limit until $(iso $(( $(date +%s) - 10 )))"
rc=0; "$bo" run "$JOB" > rerun.out 2>&1 || rc=$?
[ "$rc" -eq 0 ] || fail "run after the reset exit $rc: $(cat rerun.out "$JOB/run.log")"
grep -q 'status paused-limit -> running; the reset has passed' "$JOB/run.log" || fail "run did not log the continue: $(cat "$JOB/run.log")"

# the timer fires for real: usage over the threshold with a reset 4 s ahead pauses the job (exit 8);
# at the reset the timer runs resume, which starts the runner unit, whose child finishes the job
new_job fire step
printf '{"five_hour":{"used_percentage":99,"resets_at":%s}}\n' $(( $(date +%s) + 4 )) > "$JOB/fake-usage"
rc=0; "$bo" run "$JOB" > fire.out 2>&1 || rc=$?
[ "$rc" -eq 8 ] || fail "fire run exit $rc, want 8: $(cat fire.out "$JOB/run.log")"
rm -f "$JOB/fake-usage"; echo 'done' > "$JOB/fake-mode"
wait_until 40 grep -q '^status: done$' "$JOB/checkpoint.md" || fail "timer never resumed the job: $(cat "$JOB/run.log"; journalctl --user -u "$TEST_ID-fire.resume.service" -n 20 --no-pager)"
grep -q "resume: starting $TEST_ID-fire.service" "$JOB/run.log" || fail "timer's resume not logged: $(cat "$JOB/run.log")"
wait_until 10 not_active "$TEST_ID-fire.service" || fail "resumed runner unit still active"
# `stop` ends a pending resume timer: a stopped job does not start again at its reset
new_job stop step
printf '{"five_hour":{"used_percentage":99,"resets_at":%s}}\n' $(( $(date +%s) + 3600 )) > "$JOB/fake-usage"
rc=0; "$bo" run "$JOB" > stop.out 2>&1 || rc=$?
[ "$rc" -eq 8 ] && is_active "$TEST_ID-stop.resume.timer" || fail "stop setup: exit $rc, timer $(unit_state "$TEST_ID-stop.resume.timer")"
"$bo" stop "$JOB" > stopped.out 2>&1 || fail "stop: $(cat stopped.out)"
not_active "$TEST_ID-stop.resume.timer" || fail "resume timer $(unit_state "$TEST_ID-stop.resume.timer") after stop"
echo ok
