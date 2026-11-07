#!/usr/bin/env bash
# 12-start-env: every entry point refuses a child with no CLAUDE_FLAGS (K8, D8): `run` exits 1
# before the first child and launches nothing.
source "$REPO/tests/lib.sh"
use_fakes
export GH_TOKEN=dummy-not-a-token
bo="$REPO/bin/blast-off"

new_job run 'done'
rc=0; env -u CLAUDE_FLAGS "$bo" run "$JOB" > run.out 2>&1 || rc=$?
[ "$rc" -eq 1 ] || fail "run without CLAUDE_FLAGS exit $rc: $(cat run.out)"
grep -q CLAUDE_FLAGS run.out || fail "refusal does not name CLAUDE_FLAGS: $(cat run.out)"
[ ! -e "$JOB/fake-marker" ] || fail "a child launched without CLAUDE_FLAGS"
rc=0; CLAUDE_FLAGS='' "$bo" run "$JOB" > run2.out 2>&1 || rc=$?
[ "$rc" -eq 1 ] || fail "run with empty CLAUDE_FLAGS exit $rc"
[ ! -e "$JOB/fake-marker" ] || fail "a child launched with empty CLAUDE_FLAGS"


# start refuses before creating any unit: --setenv=NAME would turn an unset name into an empty value
new_job start 'done'
rc=0; env -u CLAUDE_FLAGS "$bo" start "$JOB" > s1.out 2>&1 || rc=$?
[ "$rc" -eq 1 ] && grep -q CLAUDE_FLAGS s1.out || fail "start without CLAUDE_FLAGS: exit $rc: $(cat s1.out)"
rc=0; CLAUDE_FLAGS="--model fake --effort low" GH_TOKEN='' "$bo" start "$JOB" > s2.out 2>&1 || rc=$?
[ "$rc" -eq 1 ] && grep -q GH_TOKEN s2.out || fail "start with empty GH_TOKEN: exit $rc: $(cat s2.out)"
rc=0; CLAUDE_FLAGS="--model fake --effort low" env -u GH_TOKEN "$bo" start "$JOB" > s3.out 2>&1 || rc=$?
[ "$rc" -eq 1 ] && grep -q GH_TOKEN s3.out || fail "start without GH_TOKEN: exit $rc: $(cat s3.out)"
[ "$(systemctl --user show "$TEST_ID-start.service" -p LoadState --value)" = not-found ] || fail "a refused start left a unit"
[ ! -e "$JOB/fake-marker" ] || fail "a refused start launched a child"
echo ok
