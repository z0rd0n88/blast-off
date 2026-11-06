#!/usr/bin/env bash
# 30-paused-limit: at each child's end the runner reads that session's usage record. A window at or
# above JOB_USAGE_PAUSE (default 95) with a reset still ahead, a StopFailure rate_limit, or child exit
# 75 writes `status: paused-limit until <ISO>`, arms <unit>-resume.timer and exits 8. A window that
# already reset, any other API error, and a child that finished the job do not pause.
source "$REPO/tests/lib.sh"
use_fakes
export CLAUDE_FLAGS="--model fake --effort low" GH_TOKEN=dummy-not-a-token JOB_CHILD_TIMEOUT=30
export BLAST_OFF_STATE_DIR="$PWD/state" JOB_RESUME_MARGIN=0
mkdir -p "$BLAST_OFF_STATE_DIR"
bo="$REPO/bin/blast-off"
now=$(date +%s)
iso() { date -u -d "@$1" +%FT%TZ; }
# fake session ids (fake-<n>) repeat across jobs, so every job starts with an empty state dir
fresh() { rm -f "$BLAST_OFF_STATE_DIR"/*; new_job "$@"; }
usage() { # usage <json>: the status line's record every child of the current job writes
  printf '%s\n' "$1" > "$JOB/fake-usage"
}

# five_hour at 96%: paused until its reset, timer armed for that time, no child 2
r=$((now + 3600))
fresh over step 'done'
usage "{\"five_hour\":{\"used_percentage\":96,\"resets_at\":$r},\"seven_day\":{\"used_percentage\":40,\"resets_at\":$((now + 86400))}}"
rc=0; "$bo" run "$JOB" > over.out 2>&1 || rc=$?
log="$JOB/run.log"
[ "$rc" -eq 8 ] || fail "over threshold exit $rc, want 8: $(cat over.out "$log")"
grep -qx "status: paused-limit until $(iso "$r")" "$JOB/checkpoint.md" || fail "status not paused-limit until $(iso "$r"): $(head -4 "$JOB/checkpoint.md")"
grep -q 'child 1 usage: 5h 96% 7d 40%' "$log" || fail "usage not logged: $(cat "$log")"
grep -q "status paused-limit until $(iso "$r")" "$log" || fail "reset time not in run.log: $(cat "$log")"
grep -q 'child 2 launched' "$log" && fail "child 2 launched past the limit"
timer="$TEST_ID-over-resume.timer"
is_active "$timer" || fail "resume timer $timer $(unit_state "$timer")"
cal="$(systemctl --user show "$timer" -p TimersCalendar --value)"
[[ $cal == *"$(date -u -d "@$r" '+%F %T') UTC"* ]] || fail "timer calendar $cal, want $(date -u -d "@$r" '+%F %T') UTC"
grep -q "resume timer $timer armed" "$log" || fail "timer not logged: $(cat "$log")"
# a run before the reset refuses at once: exit 8, no child, status kept
rc=0; "$bo" run "$JOB" > again.out 2>&1 || rc=$?
[ "$rc" -eq 8 ] || fail "run before the reset exit $rc, want 8: $(cat again.out)"
[ "$(grep -c '^child=' "$JOB/fake-marker")" -eq 1 ] || fail "a child ran before the reset: $(cat "$JOB/fake-marker")"
grep -q "still paused-limit until $(iso "$r")" "$log" || fail "refusal not logged: $(cat "$log")"
grep -qx "status: paused-limit until $(iso "$r")" "$JOB/checkpoint.md" || fail "refusal changed the status"

# seven_day over the threshold and five_hour under it: paused until the seven_day reset
r7=$((now + 86400))
fresh week step
usage "{\"five_hour\":{\"used_percentage\":10,\"resets_at\":$((now + 600))},\"seven_day\":{\"used_percentage\":97.5,\"resets_at\":$r7}}"
rc=0; JOB_RESUME_MARGIN=60 "$bo" run "$JOB" > week.out 2>&1 || rc=$?
[ "$rc" -eq 8 ] || fail "seven_day over exit $rc, want 8: $(cat week.out)"
grep -qx "status: paused-limit until $(iso $((r7 + 60)))" "$JOB/checkpoint.md" || fail "seven_day pause + margin: $(head -4 "$JOB/checkpoint.md")"

# under the threshold, and over it with the reset already past: no pause, the chain goes on
fresh under step 'done'
usage "{\"seven_day\":{\"used_percentage\":50,\"resets_at\":$((now + 86400))}}"
rc=0; "$bo" run "$JOB" > under.out 2>&1 || rc=$?
[ "$rc" -eq 0 ] || fail "under threshold exit $rc, want 0: $(cat under.out "$JOB/run.log")"
grep -q 'child 1 usage: 7d 50%' "$JOB/run.log" || fail "usage not logged: $(cat "$JOB/run.log")"
fresh stale step 'done'
usage "{\"five_hour\":{\"used_percentage\":100,\"resets_at\":$((now - 60))}}"
rc=0; "$bo" run "$JOB" > stale.out 2>&1 || rc=$?
[ "$rc" -eq 0 ] || fail "past reset exit $rc, want 0: $(cat stale.out "$JOB/run.log")"
# JOB_USAGE_PAUSE moves the threshold
fresh knob step
usage "{\"seven_day\":{\"used_percentage\":50,\"resets_at\":$((now + 86400))}}"
rc=0; JOB_USAGE_PAUSE=50 "$bo" run "$JOB" > knob.out 2>&1 || rc=$?
[ "$rc" -eq 8 ] || fail "JOB_USAGE_PAUSE=50 at 50% exit $rc, want 8: $(cat knob.out)"
# a child that finished the job is done, not paused
fresh fin 'done'
usage "{\"five_hour\":{\"used_percentage\":99,\"resets_at\":$r}}"
rc=0; "$bo" run "$JOB" > fin.out 2>&1 || rc=$?
[ "$rc" -eq 0 ] && grep -q '^status: done$' "$JOB/checkpoint.md" || fail "done child at 99% exit $rc: $(head -4 "$JOB/checkpoint.md")"
# no record (no status line figure): logged unknown, no pause
fresh none step 'done'
rc=0; "$bo" run "$JOB" > none.out 2>&1 || rc=$?
[ "$rc" -eq 0 ] && grep -q 'child 1 usage: unknown' "$JOB/run.log" || fail "no record exit $rc: $(cat "$JOB/run.log")"

# StopFailure rate_limit under the threshold: the child is not waited out; paused until the five_hour
# reset; with no five_hour figure (often absent), five hours from now
r5=$((now + 1200))
fresh rl ratelimit 'done'
usage "{\"five_hour\":{\"used_percentage\":60,\"resets_at\":$r5},\"seven_day\":{\"used_percentage\":20,\"resets_at\":$((now + 86400))}}"
t0=$SECONDS; rc=0; "$bo" run "$JOB" > rl.out 2>&1 || rc=$?
[ "$rc" -eq 8 ] || fail "rate_limit exit $rc, want 8: $(cat rl.out "$JOB/run.log")"
[ $((SECONDS - t0)) -lt 20 ] || fail "rate_limit child waited out ($((SECONDS - t0))s)"
grep -q 'child 1 hit a usage limit (StopFailure rate_limit)' "$JOB/run.log" || fail "limit not logged: $(cat "$JOB/run.log")"
grep -qx "status: paused-limit until $(iso "$r5")" "$JOB/checkpoint.md" || fail "rate_limit pause time: $(head -4 "$JOB/checkpoint.md")"
fresh rl7 ratelimit
usage "{\"seven_day\":{\"used_percentage\":20,\"resets_at\":$((now + 86400))}}"
rc=0; "$bo" run "$JOB" > rl7.out 2>&1 || rc=$?
until="$(sed -n 's/^status: paused-limit until //p' "$JOB/checkpoint.md")"
d=$(( $(date -d "$until" +%s) - now - 18000 ))
[ "$rc" -eq 8 ] && [ "$d" -ge 0 ] && [ "$d" -lt 60 ] || fail "rate_limit, no five_hour: exit $rc until $until, want now+5h"
grep -q 'reset time unknown' "$JOB/run.log" || fail "unknown reset not logged: $(cat "$JOB/run.log")"

# any other API error is a death: logged, the next child resumes
fresh api apierr 'done'
rc=0; "$bo" run "$JOB" > api.out 2>&1 || rc=$?
[ "$rc" -eq 0 ] || fail "apierr exit $rc, want 0: $(cat api.out "$JOB/run.log")"
grep -q 'child 1 ended on API error overloaded' "$JOB/run.log" || fail "API error not logged: $(cat "$JOB/run.log")"

# child exit 75 (the reserved limit code), no record, no GH_TOKEN: paused five hours, no timer
fresh x75 die75
rc=0; env -u GH_TOKEN "$bo" run "$JOB" > x75.out 2>&1 || rc=$?
[ "$rc" -eq 8 ] || fail "exit 75 child exit $rc, want 8: $(cat x75.out "$JOB/run.log")"
grep -q 'child 1 hit a usage limit (exit 75)' "$JOB/run.log" || fail "exit 75 not logged: $(cat "$JOB/run.log")"
grep -q 'no resume timer: GH_TOKEN is unset' "$JOB/run.log" || fail "timer without GH_TOKEN: $(cat "$JOB/run.log")"
not_active "$TEST_ID-x75-resume.timer" || fail "timer armed with no GH_TOKEN"
# a non-numeric threshold is a usage error before any child
fresh badp 'done'
rc=0; JOB_USAGE_PAUSE=9x "$bo" run "$JOB" > badp.out 2>&1 || rc=$?
[ "$rc" -eq 1 ] && [ ! -e "$JOB/fake-marker" ] || fail "JOB_USAGE_PAUSE=9x exit $rc, want 1 before any child"
echo ok
