#!/usr/bin/env bash
# 41-ci-wait: `blast-off ci-wait <job-dir> <pr>` watches every run of the PR's head commit with one
# blocking `gh run watch <id> --exit-status` each and records the conclusions in
# gate-logs/ci-pr-<pr>.json; exit 0 green, 10 red or no runs (absent is not a pass) (F7). At
# `status: done` the runner exits 10, status unchanged, while a PR the checkpoint names has no record
# or a red one; an absent record lets done through, logged as not a pass.
source "$REPO/tests/lib.sh"
use_fakes
export CLAUDE_FLAGS="--model fake --effort low" GH_TOKEN=dummy-not-a-token JOB_CHILD_TIMEOUT=30
export FAKE_GH="$PWD/gh" BLAST_OFF_CI_APPEAR=0
mkdir -p "$FAKE_GH"
bo="$REPO/bin/blast-off"
h7=1111111111111111111111111111111111111111 h8=2222222222222222222222222222222222222222
echo "$h7" > "$FAKE_GH/pr-7-head"; printf '11\n12\n' > "$FAKE_GH/runs-$h7"
echo success > "$FAKE_GH/run-11"; echo failure > "$FAKE_GH/run-12"
echo "$h8" > "$FAKE_GH/pr-8-head"; echo 21 > "$FAKE_GH/runs-$h8"; echo success > "$FAKE_GH/run-21"
echo 3333333333333333333333333333333333333333 > "$FAKE_GH/pr-9-head"

# --- ci-wait command ---
new_job cmd noop
rc=0; "$bo" ci-wait "$JOB" 7 > w7.out 2>&1 || rc=$?
[ "$rc" -eq 10 ] || fail "ci-wait on a red PR exit $rc, want 10: $(cat w7.out)"
grep -qx 'run watch 11 --exit-status' "$FAKE_GH/calls" && grep -qx 'run watch 12 --exit-status' "$FAKE_GH/calls" || fail "not one blocking watch per run: $(cat "$FAKE_GH/calls")"
r="$JOB/gate-logs/ci-pr-7.json"
jq -e --arg h "$h7" '.pr == 7 and .head_sha == $h and .verdict == "failure"
  and ([.runs[] | "\(.id) \(.conclusion)"] == ["11 success", "12 failure"])
  and (.utc | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"))' "$r" > /dev/null || fail "red record: $(cat "$r" 2>&1)"
grep -q "ci PR #7 at $h7: failure" "$JOB/run.log" || fail "ci-wait not logged: $(cat "$JOB/run.log")"

rc=0; "$bo" ci-wait "$JOB" 8 > w8.out 2>&1 || rc=$?
[ "$rc" -eq 0 ] && jq -e '.verdict == "success"' "$JOB/gate-logs/ci-pr-8.json" > /dev/null || fail "green PR: exit $rc: $(cat w8.out)"
rc=0; "$bo" ci-wait "$JOB" 9 > w9.out 2>&1 || rc=$?
[ "$rc" -eq 10 ] && jq -e '.verdict == "absent" and .runs == []' "$JOB/gate-logs/ci-pr-9.json" > /dev/null || fail "no runs: exit $rc: $(cat w9.out)"
rc=0; "$bo" ci-wait "$JOB" x > wx.out 2>&1 || rc=$?
[ "$rc" -eq 1 ] || fail "ci-wait for PR 'x' exit $rc, want 1"

# --- runner: exit 10 at done ---
new_job fin 'done'
printf -- '- phase 0 delivered as PR #7\n- phase 1: https://github.com/o/r/pull/9\n' >> "$JOB/checkpoint.md"
log="$JOB/run.log"
rc=0; "$bo" run "$JOB" > d1.out 2>&1 || rc=$?
[ "$rc" -eq 10 ] && grep -q 'PR #7 CI unread' "$log" || fail "done with unread CI: exit $rc: $(cat d1.out "$log")"
grep -q '^status: done$' "$JOB/checkpoint.md" || fail "exit 10 changed the status"
mkdir -p "$JOB/gate-logs"
cp "$JOB/../../test-$$-cmd/job/gate-logs/ci-pr-7.json" "$JOB/gate-logs/"
rc=0; "$bo" run "$JOB" > d2.out 2>&1 || rc=$?
[ "$rc" -eq 10 ] && grep -q 'PR #7 CI red' "$log" || fail "done with red CI: exit $rc: $(cat "$log")"
jq '.verdict = "success"' "$JOB/gate-logs/ci-pr-7.json" > ci7 && mv ci7 "$JOB/gate-logs/ci-pr-7.json"
rc=0; "$bo" run "$JOB" > d3.out 2>&1 || rc=$?
[ "$rc" -eq 10 ] && grep -q 'PR #9 CI unread' "$log" || fail "second PR unread: exit $rc: $(cat "$log")"
cp "$JOB/../../test-$$-cmd/job/gate-logs/ci-pr-9.json" "$JOB/gate-logs/"
rc=0; "$bo" run "$JOB" > d4.out 2>&1 || rc=$?
[ "$rc" -eq 0 ] || fail "green and absent records: exit $rc: $(cat d4.out "$log")"
grep -q 'PR #9: no CI runs (absent, not a pass)' "$log" || fail "absent not logged: $(cat "$log")"
[ "$(grep -c '^child=' "$JOB/fake-marker")" -eq 1 ] || fail "a child ran after done: $(cat "$JOB/fake-marker")"
echo ok
