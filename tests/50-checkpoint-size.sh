#!/usr/bin/env bash
# 50-checkpoint-size: before each child launch the runner warns in run.log when checkpoint.md is over
# 150 lines (F3: a successor must read it in one go); at 150 or fewer it says nothing. The check is
# per launch, so a checkpoint a child grows is caught before the next child, not only before child 1.
source "$REPO/tests/lib.sh"
use_fakes
export CLAUDE_FLAGS="--model fake --effort low" GH_TOKEN=dummy-not-a-token JOB_CHILD_TIMEOUT=30
bo="$REPO/bin/blast-off"
pad() { local i; for ((i = 0; i < $1; i++)); do echo "- pad $i"; done >> "$JOB/checkpoint.md"; }

# at exactly 150 lines: no warning
new_job small 'done'
pad $((150 - $(wc -l < "$JOB/checkpoint.md")))
[ "$(wc -l < "$JOB/checkpoint.md")" -eq 150 ] || fail "small setup: $(wc -l < "$JOB/checkpoint.md") lines"
rc=0; "$bo" run "$JOB" > small.out 2>&1 || rc=$?
[ "$rc" -eq 0 ] || fail "small run exit $rc: $(cat small.out "$JOB/run.log")"
grep -q '^child=1 ' "$JOB/fake-marker" || fail "small: no fake child ran"
! grep -q 'over 150' "$JOB/run.log" || fail "150 lines warned: $(grep 'over 150' "$JOB/run.log")"

# 151 lines before child 1: warned before it, with the count
new_job big 'done'
pad $((151 - $(wc -l < "$JOB/checkpoint.md")))
rc=0; "$bo" run "$JOB" > big.out 2>&1 || rc=$?
[ "$rc" -eq 0 ] || fail "big run exit $rc: $(cat big.out "$JOB/run.log")"
grep -q '^child=1 ' "$JOB/fake-marker" || fail "big: no fake child ran"
grep -q 'checkpoint.md is 151 lines, over 150' "$JOB/run.log" || fail "151 lines not warned: $(cat "$JOB/run.log")"
[ "$(grep -c 'over 150' "$JOB/run.log")" -eq 1 ] || fail "big: warned $(grep -c 'over 150' "$JOB/run.log") times, want 1"

# a child grows it past 150: warned before child 2, not before child 1
new_job grow step-pad 'done'
pad $((140 - $(wc -l < "$JOB/checkpoint.md")))
rc=0; "$bo" run "$JOB" > grow.out 2>&1 || rc=$?
[ "$rc" -eq 0 ] || fail "grow run exit $rc: $(cat grow.out "$JOB/run.log")"
[ "$(grep -c '^child=' "$JOB/fake-marker")" -eq 2 ] || fail "grow: children $(grep -c '^child=' "$JOB/fake-marker"), want 2"
n="$(sed -n 's/.*checkpoint.md is \([0-9]*\) lines, over 150.*/\1/p' "$JOB/run.log")"
[ -n "$n" ] && [ "$n" -gt 150 ] || fail "grown checkpoint not warned: $(cat "$JOB/run.log")"
w="$(grep -n 'over 150' "$JOB/run.log" | cut -d: -f1)" c2="$(grep -n 'child 2 launched' "$JOB/run.log" | head -n 1 | cut -d: -f1)"
[ "$w" -lt "$c2" ] || fail "warning after child 2 started: $(cat "$JOB/run.log")"
echo ok
