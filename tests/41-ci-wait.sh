#!/usr/bin/env bash
# 41-ci-wait: `blast-off ci-wait <job-dir> <pr>` watches every run of the PR's head commit, bar the
# workflow_dispatch ones, with one blocking `gh run watch <id> --exit-status` each and records the
# conclusions in gate-logs/ci-pr-<pr>.json; exit 0 green, 10 red or no runs (absent is not a pass) (F7).
# At `status: done` the runner exits 10, status unchanged, while a PR a Phase plan Status cell names has
# no record, a red one, or an absent one where HEAD has a workflow file; an absent record lets done
# through, logged as not a pass, only where HEAD has none (issue 26). With no PR in any Status cell the
# PRs named anywhere in the checkpoint are read instead, and run.log says what was read (P3R1-1).
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
h13=8888888888888888888888888888888888888888; echo "$h13" > "$FAKE_GH/pr-13-head"; echo 51 > "$FAKE_GH/runs-$h13"
echo success > "$FAKE_GH/run-51"; echo 30 > "$FAKE_GH/hang-run-51"
# P2R1-1: 61 is a green workflow_dispatch run on a head with no other run; 72 and 73 (listed late) are red ones
h14=9999999999999999999999999999999999999999; echo "$h14" > "$FAKE_GH/pr-14-head"; echo 61 > "$FAKE_GH/runs-$h14"
echo success > "$FAKE_GH/run-61"; echo workflow_dispatch > "$FAKE_GH/event-61"
h15=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa; echo "$h15" > "$FAKE_GH/pr-15-head"; printf '71\n72\n' > "$FAKE_GH/runs-$h15"
echo 73 > "$FAKE_GH/later-$h15"; echo success > "$FAKE_GH/run-71"
for i in 72 73; do echo failure > "$FAKE_GH/run-$i"; echo workflow_dispatch > "$FAKE_GH/event-$i"; done
# P3R1-14: 81 is a red push run, the only run of its head
h16=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb; echo "$h16" > "$FAKE_GH/pr-16-head"; echo 81 > "$FAKE_GH/runs-$h16"
echo failure > "$FAKE_GH/run-81"; echo push > "$FAKE_GH/event-81"

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
# P4R2-3: a watch past BLAST_OFF_CI_WATCH ends; the run is recorded as it stands (not success) and logged
SECONDS=0; rc=0; BLAST_OFF_CI_WATCH=1 "$bo" ci-wait "$JOB" 13 > w13.out 2>&1 || rc=$?
[ "$rc" -eq 10 ] && [ "$SECONDS" -lt 10 ] || fail "stuck run: exit $rc after $SECONDS s: $(cat w13.out)"
jq -e '.verdict == "failure" and ([.runs[] | "\(.id) \(.conclusion)"] == ["51 "])' "$JOB/gate-logs/ci-pr-13.json" > /dev/null || fail "stuck run record: $(cat "$JOB/gate-logs/ci-pr-13.json" 2>&1)"
grep -q 'ci PR #13: run 51 watch timed out after 1 s' "$JOB/run.log" && [ "$(grep -c '^run watch 51 ' "$FAKE_GH/calls")" -eq 1 ] || fail "stuck run not logged once: $(cat "$JOB/run.log")"
# P2R1-1: a workflow_dispatch run (a diagnostic; with ci.yml's `only` input, maybe one scenario) is not the
# PR's CI: a green one alone leaves the record absent, a red one beside a green pull_request run leaves it
# success; neither is watched or recorded
rc=0; "$bo" ci-wait "$JOB" 14 > w14.out 2>&1 || rc=$?
[ "$rc" -eq 10 ] && jq -e '.verdict == "absent" and .runs == []' "$JOB/gate-logs/ci-pr-14.json" > /dev/null || fail "green dispatch run counted: exit $rc: $(cat "$JOB/gate-logs/ci-pr-14.json" w14.out 2>&1)"
rc=0; "$bo" ci-wait "$JOB" 15 > w15.out 2>&1 || rc=$?
[ "$rc" -eq 0 ] && jq -e '.verdict == "success" and ([.runs[].id] == [71])' "$JOB/gate-logs/ci-pr-15.json" > /dev/null || fail "red dispatch runs counted: exit $rc: $(cat "$JOB/gate-logs/ci-pr-15.json" w15.out 2>&1)"
! grep -qE '^run (watch|view) (61|72|73) ' "$FAKE_GH/calls" || fail "a dispatch run was watched or viewed: $(grep -E '^run (watch|view)' "$FAKE_GH/calls")"
# P3R1-14: only workflow_dispatch is left out; a run of any other event (here push) counts
rc=0; "$bo" ci-wait "$JOB" 16 > w16.out 2>&1 || rc=$?
[ "$rc" -eq 10 ] && jq -e '.verdict == "failure" and ([.runs[].id] == [81])' "$JOB/gate-logs/ci-pr-16.json" > /dev/null || fail "red push run not counted: exit $rc: $(cat "$JOB/gate-logs/ci-pr-16.json" w16.out 2>&1)"
# D4-7: ci-wait [workdir]: gh runs in that workdir, whose remote names the repo
wd="$PWD/wd"; mkdir -p "$wd"
"$bo" ci-wait "$JOB" 8 "$wd" > /dev/null 2>&1 && grep -qx "cwd=$wd" "$FAKE_GH/calls" || fail "ci-wait did not run gh in its workdir $wd"

# --- runner: exit 10 at done ---
# The scenario dir is in no git repo, so the done rows below need no receipt (P3R1-37).
new_job fin 'done'
# D4-5, D4-17: any case, no space, leading 0. Issue 26: only a Status cell names this job's PRs; PR #98
# (another cell) and PR #99 (prose, say another repo's) have no record and must not hold done back. Nor do
# PR #96 (a row whose key is no digit) and PR #97 (a digit-keyed row under another heading): the Status
# cell is the last of five here, of the rows the runner sees, in `## Phase plan` only (P3R1-15 to 17)
printf '%s\n' '' '## Phase plan' '| # | Phase | Done when | Notes | Status |' '|---|---|---|---|---|' \
  '| 0 | a | b | c | done (abc1234) · pr#07 |' '| 1 | a | b | port of PR #98 | done (abc1234) https://github.com/o/r/pull/9 |' \
  '| P1 | a | b | c | done (abc1234) · PR #96 |' \
  '## Decisions' '- copied from o/other PR #99, see https://github.com/o/other/pull/99' \
  '| 3 | a | b | c | done (abc1234) · PR #97 |' >> "$JOB/checkpoint.md"
log="$JOB/run.log"
rc=0; "$bo" run "$JOB" > d1.out 2>&1 || rc=$?
[ "$rc" -eq 10 ] && grep -q 'PR #7 CI unread' "$log" || fail "done with unread CI: exit $rc: $(cat d1.out "$log")"
grep -q '^status: done$' "$JOB/checkpoint.md" || fail "exit 10 changed the status"
mkdir -p "$JOB/gate-logs"
cp "$JOB/../../test-$$-cmd/job/gate-logs/ci-pr-7.json" "$JOB/gate-logs/"
rc=0; "$bo" run "$JOB" > d2.out 2>&1 || rc=$?
[ "$rc" -eq 10 ] && grep -q 'PR #7 CI red' "$log" || fail "done with red CI: exit $rc: $(cat "$log")"
grep -q "PR #7 CI red or unfinished at $h7 (gate-logs/ci-pr-7.json); fix and push if red, then blast-off ci-wait <job-dir> 7" "$log" || fail "red CI names no head or action: $(cat "$log")"  # P4R3-2
jq '.verdict = "success"' "$JOB/gate-logs/ci-pr-7.json" > ci7 && mv ci7 "$JOB/gate-logs/ci-pr-7.json"
rc=0; "$bo" run "$JOB" > d3.out 2>&1 || rc=$?
[ "$rc" -eq 10 ] && grep -q 'PR #9 CI unread' "$log" || fail "second PR unread: exit $rc: $(cat "$log")"
# D4-2: a record for another PR does not count, even when both PRs share a head (the head check alone passes)
cp "$JOB/../../test-$$-cmd/job/gate-logs/ci-pr-8.json" "$JOB/gate-logs/ci-pr-9.json"; echo "$h8" > "$FAKE_GH/pr-9-head"
rc=0; "$bo" run "$JOB" > d3b.out 2>&1 || rc=$?
[ "$rc" -eq 10 ] && grep -q 'PR #9 CI unread: no readable record for PR 9' "$log" || fail "PR 8's record for PR 9: exit $rc: $(cat "$log")"
echo 3333333333333333333333333333333333333333 > "$FAKE_GH/pr-9-head"
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
! grep -qE 'PR #9[6-9]' "$log" || fail "a PR named outside a Status cell was read: $(grep -E 'PR #9[6-9]' "$log")"
# P3R1-1, P3R1-2: what was read at done is in run.log, and so is every PR named elsewhere and left unread
grep -q 'CI read for the PRs Phase plan Status cells name: 7 9; named elsewhere in checkpoint.md and not read: 96 97 98 99$' "$log" || fail "PRs read at done not logged: $(cat "$log")"
grep -q 'PR #9: no CI runs and no workflow file at HEAD (absent, not a pass)' "$log" || fail "absent not logged: $(cat "$log")"
[ "$(grep -c '^child=' "$JOB/fake-marker")" -eq 1 ] || fail "a child ran after done: $(cat "$JOB/fake-marker")"
# P4R2-2: a gh pr view past BLAST_OFF_CI_HEAD is a failed call: unread, exit 10, status unchanged, fast
echo 30 > "$FAKE_GH/hang-pr-7"
SECONDS=0; rc=0; BLAST_OFF_CI_HEAD=1 "$bo" run "$JOB" > d5.out 2>&1 || rc=$?
[ "$rc" -eq 10 ] && [ "$SECONDS" -lt 10 ] && grep -q 'PR #7 CI unread for head unknown (gh pr view 7 failed)' "$log" || fail "stalled gh pr view: exit $rc after $SECONDS s: $(cat d5.out "$log")"
grep -q '^status: done$' "$JOB/checkpoint.md" || fail "a stalled gh pr view changed the status"
rm "$FAKE_GH/hang-pr-7"

# --- P3R1-1: no Status cell names a PR: done fails closed on every PR the checkpoint names ---
# no Phase plan table (a supported job: hard cap, no receipts), PR in prose, no record
new_job nt 'done'; log="$JOB/run.log"
echo '- shipped as PR #7' >> "$JOB/checkpoint.md"
rc=0; "$bo" run "$JOB" > n1.out 2>&1 || rc=$?
[ "$rc" -eq 10 ] && grep -q 'PR #7 CI unread' "$log" || fail "no table, PR in prose, no record: exit $rc: $(cat n1.out "$log")"
grep -q 'no Phase plan Status cell names a PR; CI read for every PR checkpoint.md names instead: 7 (' "$log" || fail "whole-file read not logged: $(cat "$log")"
grep -q '^status: done$' "$JOB/checkpoint.md" || fail "exit 10 with no table changed the status"
# a done row with no PR in its Status cell, the PR only under Completed phases (the template's own shape)
new_job np 'done'; log="$JOB/run.log"
printf '%s\n' '' '## Phase plan' '| # | Phase | Done when | Status |' '|---|---|---|---|' '| 0 | a | b | done (abc1234) |' \
  '## Completed phases' '- **Phase 0, a** (done). PR #7; CI read.' >> "$JOB/checkpoint.md"
rc=0; "$bo" run "$JOB" > n2.out 2>&1 || rc=$?
[ "$rc" -eq 10 ] && grep -q 'PR #7 CI unread' "$log" || fail "done row with no PR, PR named below: exit $rc: $(cat n2.out "$log")"
# no PR named at all: done goes through, and run.log says no CI was read
sed -i 's/ PR #7;//' "$JOB/checkpoint.md"
rc=0; "$bo" run "$JOB" > n3.out 2>&1 || rc=$?
[ "$rc" -eq 0 ] && grep -q 'no PR named in checkpoint.md; CI not read$' "$log" || fail "done with no PR named: exit $rc: $(cat n3.out "$log")"

# --- issue 26: an absent record passes only where HEAD has no workflow file ---
new_job wf 'done'
w="$(dirname "$JOB")"; log="$JOB/run.log"
# P3R1-18: files at HEAD beside .github/workflows, in the root and under .github, are no workflow files
mkdir -p "$w/.github" "$w/sub"; echo x > "$w/README.md"; echo 'version: 2' > "$w/.github/dependabot.yml"
git -C "$w" init -q && git -C "$w" add README.md .github && git -C "$w" -c user.name=t -c user.email=t@t commit -q -m init
printf '%s\n' '' '## Phase plan' '| # | Phase | Done when | Status |' '|---|---|---|---|' \
  "| 1 | a | b | done ($(git -C "$w" rev-parse --short HEAD)) · PR #14 |" '## Decisions' >> "$JOB/checkpoint.md"
mkdir -p "$JOB/gate-logs"; echo 'GATE: PASS passed=1 failed=0 shellcheck=ok' > "$JOB/gate-logs/phase-1.log"
"$bo" receipt "$JOB" 1 > /dev/null 2>&1 || fail "fixture receipt refused"  # a done row in a git workdir needs one (exit 9)
# P3R1-20: the record is ci-wait's own, of a head whose only run is a workflow_dispatch (PR 14): absent
rc=0; "$bo" ci-wait "$JOB" 14 > wf14.out 2>&1 || rc=$?
[ "$rc" -eq 10 ] && jq -e '.verdict == "absent" and .runs == []' "$JOB/gate-logs/ci-pr-14.json" > /dev/null || fail "dispatch-only head in the wf job: exit $rc: $(cat wf14.out)"
rc=0; "$bo" run "$JOB" > a1.out 2>&1 || rc=$?
[ "$rc" -eq 0 ] && grep -q 'PR #14: no CI runs and no workflow file at HEAD (absent, not a pass)' "$log" || fail "absent CI, no workflow at HEAD: exit $rc: $(cat a1.out "$log")"
mkdir -p "$w/.github/workflows"; echo 'on: pull_request' > "$w/.github/workflows/ci.yml"
git -C "$w" add .github && git -C "$w" -c user.name=t -c user.email=t@t commit -q -m workflow
rc=0; "$bo" run "$JOB" > a2.out 2>&1 || rc=$?
[ "$rc" -eq 10 ] && grep -q 'PR #14 CI absent: no runs, but HEAD has a workflow file (.github/workflows/ci.yml)' "$log" || fail "absent CI with a workflow at HEAD: exit $rc: $(cat a2.out "$log")"
# P3R1-22: the way out is a push (an absent record has no run to re-run), then ci-wait
grep -q 'PR #14 CI absent: .*; push to the PR branch for a run that is not a workflow_dispatch, then blast-off ci-wait <job-dir> 14, then run again' "$log" || fail "absent refusal names no way out: $(cat "$log")"
grep -q '^status: done$' "$JOB/checkpoint.md" || fail "exit 10 on absent CI changed the status"
# P3R1-11: the workflow read is of the repo, also when the workdir is a subdirectory of it
rc=0; "$bo" run "$JOB" "$w/sub" > a3.out 2>&1 || rc=$?
[ "$rc" -eq 10 ] && [ "$(grep -c 'PR #14 CI absent' "$log")" -eq 2 ] || fail "workdir a subdirectory of the repo: exit $rc: $(cat a3.out "$log")"
# P3R1-13: HEAD is read, not the working tree: the file deleted on disk and not committed is still due its run
rm "$w/.github/workflows/ci.yml"; echo '- .github/workflows/ci.yml deleted on disk, not committed' >> "$JOB/checkpoint.md"
rc=0; "$bo" run "$JOB" > a4.out 2>&1 || rc=$?
[ "$rc" -eq 10 ] && [ "$(grep -c 'PR #14 CI absent' "$log")" -eq 3 ] || fail "workflow at HEAD, deleted on disk: exit $rc: $(cat a4.out "$log")"
# P3R1-19: the workflow file refuses only an absent record; a green one of the same head passes
jq '.verdict = "success"' "$JOB/gate-logs/ci-pr-14.json" > ci14 && mv ci14 "$JOB/gate-logs/ci-pr-14.json"
rc=0; "$bo" run "$JOB" > a5.out 2>&1 || rc=$?
[ "$rc" -eq 0 ] && [ "$(grep -c 'PR #14 CI absent' "$log")" -eq 3 ] || fail "green record with a workflow at HEAD: exit $rc: $(cat a5.out "$log")"
# P3R1-12: a failing ls-tree (a repo with no commit yet) is the runner's error (exit 1), never "no workflow
# file". No done row can stand in such a repo (exit 9), so the PR is named in prose, read by P3R1-1's rule
new_job ub 'done'; w="$(dirname "$JOB")"
git -C "$w" init -q; echo '- shipped as PR #9' >> "$JOB/checkpoint.md"
mkdir -p "$JOB/gate-logs"; cp "$JOB/../../test-$$-cmd/job/gate-logs/ci-pr-9.json" "$JOB/gate-logs/"
rc=0; "$bo" run "$JOB" > u1.out 2>&1 || rc=$?
[ "$rc" -eq 1 ] && grep -q 'git ls-tree HEAD failed' u1.out || fail "ls-tree failing at done: exit $rc: $(cat u1.out "$JOB/run.log")"
echo ok
