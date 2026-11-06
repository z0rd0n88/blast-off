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
h10=4444444444444444444444444444444444444444 h11=5555555555555555555555555555555555555555
echo "$h10" > "$FAKE_GH/pr-10-head"; echo 31 > "$FAKE_GH/runs-$h10"; echo 32 > "$FAKE_GH/later-$h10"
echo success > "$FAKE_GH/run-31"; echo failure > "$FAKE_GH/run-32"
echo "$h11" > "$FAKE_GH/pr-11-head"; echo 41 > "$FAKE_GH/appear-$h11"; echo success > "$FAKE_GH/run-41"
h12=7777777777777777777777777777777777777777; echo "$h12" > "$FAKE_GH/pr-12-head"
echo 42 > "$FAKE_GH/appear-$h12"; echo success > "$FAKE_GH/run-42"

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
# D4-9: one watch per run, each before its conclusion is read (the fake reports none before a watch)
[ "$(grep -c '^run watch 11 ' "$FAKE_GH/calls")" -eq 1 ] && [ "$(grep -c '^run watch 21 ' "$FAKE_GH/calls")" -eq 1 ] || fail "watches per run: $(grep '^run watch' "$FAKE_GH/calls")"
# D4-6: a run listed only after the first is watched (a late or chained workflow) is watched and counted
rc=0; "$bo" ci-wait "$JOB" 10 > w10.out 2>&1 || rc=$?
[ "$rc" -eq 10 ] && jq -e '.verdict == "failure" and ([.runs[].id] == [31, 32])' "$JOB/gate-logs/ci-pr-10.json" > /dev/null || fail "late run: exit $rc: $(cat "$JOB/gate-logs/ci-pr-10.json" w10.out 2>&1)"
grep -q '^run watch 32 ' "$FAKE_GH/calls" || fail "late run 32 not watched"
# runs listed only from the third read (after the re-list a missing wait would make): ci-wait waits up to
# BLAST_OFF_CI_APPEAR for them, and with 0 records absent (P4R1-3)
rc=0; BLAST_OFF_CI_APPEAR=10 "$bo" ci-wait "$JOB" 11 > w11.out 2>&1 || rc=$?
[ "$rc" -eq 0 ] && jq -e '.verdict == "success" and .runs[0].id == 41' "$JOB/gate-logs/ci-pr-11.json" > /dev/null || fail "runs that appear late: exit $rc: $(cat w11.out)"
rc=0; BLAST_OFF_CI_APPEAR=0 "$bo" ci-wait "$JOB" 12 > w12.out 2>&1 || rc=$?
[ "$rc" -eq 10 ] && jq -e '.verdict == "absent" and .runs == []' "$JOB/gate-logs/ci-pr-12.json" > /dev/null || fail "BLAST_OFF_CI_APPEAR=0 still waited: exit $rc: $(cat w12.out)"
# D4-7: ci-wait [workdir]: gh runs in that workdir, whose remote names the repo
wd="$PWD/wd"; mkdir -p "$wd"
"$bo" ci-wait "$JOB" 8 "$wd" > /dev/null 2>&1 && grep -qx "cwd=$wd" "$FAKE_GH/calls" || fail "ci-wait did not run gh in its workdir $wd"

# --- runner: exit 10 at done ---
new_job fin 'done'
printf -- '- phase 0 delivered as pr#07\n- phase 1: https://github.com/o/r/pull/9\n' >> "$JOB/checkpoint.md"  # D4-5, D4-17: any case, no space, leading 0
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
# D4-2: a record for another PR does not count
cp "$JOB/../../test-$$-cmd/job/gate-logs/ci-pr-8.json" "$JOB/gate-logs/ci-pr-9.json"
rc=0; "$bo" run "$JOB" > d3b.out 2>&1 || rc=$?
[ "$rc" -eq 10 ] && [ "$(grep -c 'PR #9 CI unread' "$log")" -eq 2 ] || fail "PR 8's record for PR 9: exit $rc: $(cat "$log")"
cp "$JOB/../../test-$$-cmd/job/gate-logs/ci-pr-9.json" "$JOB/gate-logs/"
# P4R1-1: a record of an older head is unread once the PR head moved, and so is one gh cannot check
echo 6666666666666666666666666666666666666666 > "$FAKE_GH/pr-7-head"
rc=0; "$bo" run "$JOB" > d3c.out 2>&1 || rc=$?
[ "$rc" -eq 10 ] && grep -q 'PR #7 CI unread for head 6666666666666666666666666666666666666666' "$log" || fail "green record of an old head: exit $rc: $(cat "$log")"
echo "$h7" > "$FAKE_GH/pr-7-head"; rm "$FAKE_GH/pr-9-head"
rc=0; "$bo" run "$JOB" > d3d.out 2>&1 || rc=$?
[ "$rc" -eq 10 ] && grep -q 'PR #9 CI unread for head unknown' "$log" || fail "absent record gh could not check: exit $rc: $(cat "$log")"
echo 3333333333333333333333333333333333333333 > "$FAKE_GH/pr-9-head"
rc=0; "$bo" run "$JOB" > d4.out 2>&1 || rc=$?
[ "$rc" -eq 0 ] || fail "green and absent records: exit $rc: $(cat d4.out "$log")"
grep -q 'PR #9: no CI runs (absent, not a pass)' "$log" || fail "absent not logged: $(cat "$log")"
[ "$(grep -c '^child=' "$JOB/fake-marker")" -eq 1 ] || fail "a child ran after done: $(cat "$JOB/fake-marker")"
echo ok
