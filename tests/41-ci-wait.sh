#!/usr/bin/env bash
# 41-ci-wait: `blast-off ci-wait <job-dir> <pr>` watches every run of the PR's head commit, bar the
# workflow_dispatch ones, with one blocking `gh run watch <id> --exit-status` each and records the
# conclusions in gate-logs/ci-pr-<pr>.json; exit 0 green, 10 red or no runs (absent is not a pass) (F7).
# At `status: done` the runner exits 10, status unchanged, unless every done Phase plan row's Status cell
# names the phase's PR or says `no PR` (a job with no done row is refused too; owner ruling 1), and while a
# PR named there has no record, a red one, or an absent one whose head commit has a workflow file or cannot
# be read. An absent record passes, logged as not a pass, only where the PR's head has no workflow file
# (issue 26, owner ruling 2). Nothing outside those cells is read; run.log says what was.
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
# (another cell) and PR #99 (prose, say another repo's) have no record and must not hold done back. Nor
# does PR #97 (a digit-keyed row under another heading, so prose): the Status cell is the last of five
# here, in `## Phase plan` only (P3R1-15 to 17). A row there the runner cannot read refuses done (P3R3-1, below)
printf '%s\n' '' '## Phase plan' '| # | Phase | Done when | Notes | Status |' '|---|---|---|---|---|' \
  '| 0 | a | b | c | done (abc1234) · pr#07 |' '| 1 | a | b | port of PR #98 | done (abc1234) https://github.com/o/r/pull/9 |' \
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
# owner ruling 2: outside git the PR's head commit cannot be read, so an absent record is refused, not passed
rc=0; "$bo" run "$JOB" > d4.out 2>&1 || rc=$?
[ "$rc" -eq 10 ] && grep -q 'PR #9 CI absent: no runs, and the workdir is in no git repo' "$log" || fail "absent record outside git: exit $rc: $(cat d4.out "$log")"
jq '.verdict = "success"' "$JOB/gate-logs/ci-pr-9.json" > ci9 && mv ci9 "$JOB/gate-logs/ci-pr-9.json"
rc=0; "$bo" run "$JOB" > d4b.out 2>&1 || rc=$?
[ "$rc" -eq 0 ] || fail "green records: exit $rc: $(cat d4b.out "$log")"
! grep -qE 'PR #9[7-9]' "$log" && ! grep -qE '^pr view 9[7-9]' "$FAKE_GH/calls" || fail "a PR named outside a Status cell was read: $(grep -E 'PR #9[6-9]' "$log")"
# what was read at done is in run.log
grep -q 'CI at done: PRs read: 7 9; rows that say no PR: none$' "$log" || fail "PRs read at done not logged: $(cat "$log")"
[ "$(grep -c '^child=' "$JOB/fake-marker")" -eq 1 ] || fail "a child ran after done: $(cat "$JOB/fake-marker")"
# P4R2-2: a gh pr view past BLAST_OFF_CI_HEAD is a failed call: unread, exit 10, status unchanged, fast
echo 30 > "$FAKE_GH/hang-pr-7"
SECONDS=0; rc=0; BLAST_OFF_CI_HEAD=1 "$bo" run "$JOB" > d5.out 2>&1 || rc=$?
[ "$rc" -eq 10 ] && [ "$SECONDS" -lt 10 ] && grep -q 'PR #7 CI unread for head unknown (gh pr view 7 failed)' "$log" || fail "stalled gh pr view: exit $rc after $SECONDS s: $(cat d5.out "$log")"
grep -q '^status: done$' "$JOB/checkpoint.md" || fail "a stalled gh pr view changed the status"
rm "$FAKE_GH/hang-pr-7"

# --- owner ruling 1: every done row says `PR #<n>` or `no PR`; nothing outside the Status cells is read ---
# done_job <suffix> <line>...: a job already at status done (no child runs) whose checkpoint ends in those lines
done_job() {
  local s="$1"; shift
  new_job "$s" noop; sed -i 's/^status: running$/status: done/' "$JOB/checkpoint.md"
  printf '%s\n' '' "$@" >> "$JOB/checkpoint.md"; log="$JOB/run.log"; mkdir -p "$JOB/gate-logs"
}
plan=('## Phase plan' '| # | Phase | Done when | Status |' '|---|---|---|---|')
rec() { cp "$JOB/../../test-$$-cmd/job/gate-logs/ci-pr-$1.json" "$JOB/gate-logs/"; }  # cmd's records: 7 red, 8 green
refused() { # <text wanted in run.log> <case>: exit 10, that text logged, status unchanged
  rc=0; "$bo" run "$JOB" > r.out 2>&1 || rc=$?
  [ "$rc" -eq 10 ] && grep -qF -- "$1" "$log" || fail "$2: exit $rc, want 10 and '$1': $(cat r.out "$log" 2>&1)"
  grep -q '^status: done$' "$JOB/checkpoint.md" || fail "$2: exit 10 changed the status"
}
passes() { rc=0; "$bo" run "$JOB" > r.out 2>&1 || rc=$?; [ "$rc" -eq 0 ] || fail "$1: exit $rc, want 0: $(cat r.out "$log" 2>&1)"; }
# no done row (P3R1-1): with no table nothing says which PR to read or that there is none, so done is
# refused; the PR in prose is not read
done_job nt '- shipped as PR #7'
refused 'status done but the Phase plan has no done row' "no table"
! grep -q 'PR #7' "$log" || fail "no table: the PR in prose was read: $(cat "$log")"
# a heading the runner does not read (capital P) hides its rows: the same refusal, not a pass
done_job hd '## Phase Plan' "${plan[@]:1}" '| 0 | a | b | done (abc1234) · no PR |'
refused 'status done but the Phase plan has no done row' "mis-typed heading"
# a table with no row (header only), no PR named anywhere: the same refusal, not "no PR to read"
done_job nr "${plan[@]}"
refused 'status done but the Phase plan has no done row' "table with no rows"
# a done row with neither, its PR only under Completed phases (the old template's shape): refused, with what to write
done_job np "${plan[@]}" '| 0 | a | b | done (abc1234) |' '## Completed phases' '- **Phase 0, a** (done). PR #7; CI read.'
refused 'phase row 0 is done but its Status cell says neither `PR #<n>` nor `no PR`: after the sha write `PR #<n>`' "done row with neither"
sed -i 's/^| 0 | a | b | done (abc1234) |$/| 0 | a | b | done (abc1234) · no PR |/' "$JOB/checkpoint.md"
passes "done row that says no PR"
grep -q 'CI at done: PRs read: none; rows that say no PR: 0$' "$log" || fail "no PR row not logged: $(cat "$log")"
# P3R2-1: one cell that names a PR does not excuse the next row. Row 1 has neither; its PR #7 (a red record
# is in the job) is named only in prose
done_job mx "${plan[@]}" '| 0 | a | b | done (abc1234) · PR #8 |' '| 1 | a | b | done (abc1234) |' \
  '## Completed phases' '- **Phase 1, a** (done). PR #7; CI read.'
rec 7; rec 8
refused 'phase row 1 is done but its Status cell says neither' "mixed rows, one with neither (P3R2-1)"
# ruling 1 as ruled: once row 1 says `no PR` nothing in prose is read, so PR #7's red record does not count
sed -i 's/^| 1 | a | b | done (abc1234) |$/| 1 | a | b | done (abc1234) · no PR · usage 7d 5% |/' "$JOB/checkpoint.md"
passes "PR #8 green, row 1 says no PR"
grep -q 'CI at done: PRs read: 8; rows that say no PR: 1$' "$log" && ! grep -q 'PR #7' "$log" || fail "mixed rows log: $(cat "$log")"
# P3R2-2: another repo's PR and /pull/ link in prose are never read as this repo's PR 99
n99="$(grep -c '^pr view 99' "$FAKE_GH/calls" || true)"
done_job lk "${plan[@]}" '| 0 | a | b | done (abc1234) · no PR |' '## Decisions' \
  '- copied from o/other PR #99, see https://github.com/o/other/pull/99'
passes "another repo's PR link in prose (P3R2-2)"
! grep -qE 'PR #99|pull/99' "$log" && [ "$(grep -c '^pr view 99' "$FAKE_GH/calls" || true)" = "$n99" ] || fail "another repo's PR 99 was read: $(cat "$log")"
# two rows with one key: each row's own cell counts, not the first row's for both
done_job dup "${plan[@]}" '| 1 | a | b | done (abc1234) · PR #8 |' '| 1 | a | b | done (abc1234) |'
rec 8
refused 'phase row 1 is done but its Status cell says neither' "second row of a duplicated key"
# a cell that says both is refused
done_job both "${plan[@]}" '| 0 | a | b | done (abc1234) · no PR · PR #8 |'
rec 8
refused 'phase row 0 Status cell says `no PR` and names PR #8' "no PR and a PR in one cell"
# P3R3-1 (owner direction): beside a readable done row (PR #8 green), a Phase plan line that holds a '|' and is
# not the header, the separator or a row the runner reads, or a second Phase plan heading, refuses done and
# names the line: a row the runner cannot read is never skipped. Its PR #7 is red, its key is no digit, it
# is indented, tab-led, has a tab after its pipe, no leading pipe, a `#` key holding a done Status, or it sits
# under a second heading (any level or case, ATX or setext, in or after the section)
i=0 r7='done (abc1234) · PR #7 |'
for l in "| P1 | a | b | $r7" "| **1** | a | b | $r7" "  | 1 | a | b | $r7" $'\t'"| 1 | a | b | $r7" \
  $'|\t'"1 | a | b | $r7" "1 | a | b | $r7" "| # | a | b | $r7" "| ~~1~~ | a | b | $r7" "<!-- | 1 | a | b | $r7 -->" \
  '| # | a | b | pending |' '| # | a | b | PR #7 · done (abc1234) |' "| 1 | a | b | done (abc1234) · PR #8 |\\r| 2 | a | b | $r7"; do
  done_job "ur$((++i))" "${plan[@]}" '| 0 | a | b | done (abc1234) · PR #8 |' "$(printf '%b' "$l")"
  rec 7; rec 8
  refused "checkpoint.md line 13 '$l' holds a '|' in the Phase plan and is not its header, separator or a row the runner reads" "unread line '$l'"
  ! grep -q 'PRs read' "$log" || fail "unread line '$l': PRs were read before the refusal: $(cat "$log")"
done
for h in '## Phase plan' '## Phase Plan' '### Phase plan' '# phase  plan (cont.)'; do
  done_job "uh$((++i))" "${plan[@]}" '| 0 | a | b | done (abc1234) · PR #8 |' '## Decisions' "$h" "${plan[@]:1}" "| 1 | a | b | $r7"
  rec 7; rec 8
  refused "checkpoint.md line 14 '$h' is a second Phase plan heading" "second heading '$h'"
done
done_job "uh$((++i))" "${plan[@]}" '| 0 | a | b | done (abc1234) · PR #8 |' "${plan[@]}" "| 1 | a | b | $r7"
rec 7; rec 8
refused "checkpoint.md line 13 '## Phase plan' is a second Phase plan heading" "second heading right after the table"
done_job "uh$((++i))" "${plan[@]}" '| 0 | a | b | done (abc1234) · PR #8 |' '## Decisions' 'Phase plan' '----------' "${plan[@]:1}" "| 1 | a | b | $r7"
rec 7; rec 8
refused "checkpoint.md line 14 'Phase plan' is a second Phase plan heading" "setext second heading"
# what may stay: CRLF lines, an aligned separator, a sub-heading and prose lines with no '|' in the section
done_job ok "${plan[@]::2}" '|:--|---|:-:|--:|' '### detail' 'Rows below are phases 0 and 1.' '| 0 | a | b | done (abc1234) · PR #8 |' \
  $'| 1 | a | b | done (abc1234) · no PR |\r' '## Decisions'
rec 8
passes "a Phase plan with only rows, header, separator and lines with no '|'"
# P3R2-6: a PR written a way the runner does not read is refused, never passed as "no PR named"
i=0
# P3R3-3: past `done (<sha>)` only PR tokens and `no PR` may hold a number or the word PR (a whitelist)
for c in 'PR #8, #7' 'PRs #7, #8' 'PR 7' '#7' 'PR: #7' 'PR  #7' 'no PR (#7 dropped)' \
  'no PR, see PR 7' 'PR #8, 7' 'PR #8,234' 'PR 7 · no PR checks failed' '(see PR 7) no PR' 'no PRs' 'PR #8 see /pull/x'; do
  done_job "sp$((++i))" "${plan[@]}" "| 0 | a | b | done (abc1234) · $c |"
  rec 8
  refused 'phase row 0 ' "Status cell '$c'"
done
done_job nc "${plan[@]}" '| 0 | a | b | done (abc1234) · No PR |'
passes "\`No PR\`, any case (P3R3-21)"
# P3R2-5: a NUL byte in the Status cell neither hides its PR nor lets done through (9: the row reads as open)
done_job nul "${plan[@]}"; printf '| 0 | a | b | done (abc1234)\0 · PR #7 |\n' >> "$JOB/checkpoint.md"
rc=0; "$bo" run "$JOB" > r.out 2>&1 || rc=$?
[ "$rc" -eq 10 ] || [ "$rc" -eq 9 ] || fail "NUL in a Status cell: exit $rc, want 9 or 10: $(cat r.out "$log" 2>&1)"

# --- issue 26, owner ruling 2: an absent record passes only where the PR's own head commit has no workflow file ---
new_job wf 'done'
w="$(dirname "$JOB")"; log="$JOB/run.log"
commit() { git -C "$w" -c user.name=t -c user.email=t@t commit -q -m "$1"; git -C "$w" rev-parse HEAD; }
# P3R1-18: files at the head beside .github/workflows, in the root and under .github, are no workflow files
mkdir -p "$w/.github" "$w/sub"; echo x > "$w/README.md"; echo 'version: 2' > "$w/.github/dependabot.yml"
git -C "$w" init -q && git -C "$w" add README.md .github; c1="$(commit init)"
printf '%s\n' '' "${plan[@]}" "| 1 | a | b | done (${c1:0:7}) · PR #17 |" '## Decisions' >> "$JOB/checkpoint.md"
mkdir -p "$JOB/gate-logs"; echo 'GATE: PASS passed=1 failed=0 shellcheck=ok' > "$JOB/gate-logs/phase-1.log"
"$bo" receipt "$JOB" 1 > /dev/null 2>&1 || fail "fixture receipt refused"  # a done row in a git workdir needs one (exit 9)
# absent17 <sha>: PR 17's head is that commit and its only run a workflow_dispatch (61): ci-wait's own absent record (P3R1-20)
absent17() {
  echo "$1" > "$FAKE_GH/pr-17-head"; echo 61 > "$FAKE_GH/runs-$1"
  rc=0; "$bo" ci-wait "$JOB" 17 > wf17.out 2>&1 || rc=$?
  [ "$rc" -eq 10 ] && jq -e --arg h "$1" '.verdict == "absent" and .runs == [] and .head_sha == $h' "$JOB/gate-logs/ci-pr-17.json" > /dev/null || fail "dispatch-only head $1: exit $rc: $(cat wf17.out)"
}
absent17 "$c1"
passes "absent CI, no workflow file at the PR's head"
grep -q "PR #17: no CI runs and no workflow file at its head ${c1:0:7} (no CI configured; absent, not a pass)" "$log" || fail "absent pass not logged: $(cat "$log")"
# ruling 2: a workflow file at the workdir's HEAD that the PR's head lacks does not make runs due on the PR
mkdir -p "$w/.github/workflows"; echo 'on: pull_request' > "$w/.github/workflows/release.yaml"
git -C "$w" add .github; c2="$(commit workflow)"
passes "workflow file at HEAD, none at the PR's head"
[ "$(grep -c 'PR #17: no CI runs and no workflow file at its head' "$log")" -eq 2 ] || fail "workflow file at HEAD only: $(cat "$log")"
# the PR's head moves to the commit that has the file (any name under .github/workflows): runs were due
absent17 "$c2"
refused "PR #17 CI absent: no runs, but its head ${c2:0:7} has a workflow file (.github/workflows/release.yaml)" "absent CI, workflow file at the PR's head"
# P3R1-22, P3R2-3: the way out is a push (an absent record has no run to re-run), then ci-wait; a PR no
# workflow can start on has no way out but the owner
grep -q 'PR #17 CI absent: .*; push to the PR branch for a run that is not a workflow_dispatch, then blast-off ci-wait <job-dir> 17, then run again; if no workflow can start on this PR (a branch or path filter), there is no override: ask the owner' "$log" || fail "absent refusal names no way out: $(cat "$log")"
# P3R1-11: the read is of the repo, also when the workdir is a subdirectory of it
rc=0; "$bo" run "$JOB" "$w/sub" > a3.out 2>&1 || rc=$?
[ "$rc" -eq 10 ] && [ "$(grep -c 'PR #17 CI absent' "$log")" -eq 2 ] || fail "workdir a subdirectory of the repo: exit $rc: $(cat a3.out "$log")"
# P3R2-7, P3R1-13: the PR's head commit is read, not HEAD or the working tree: a later commit that removes
# the file leaves the PR's head still due its run
git -C "$w" rm -q .github/workflows/release.yaml; commit 'workflow removed' > /dev/null
rc=0; "$bo" run "$JOB" > a4.out 2>&1 || rc=$?
[ "$rc" -eq 10 ] && [ "$(grep -c 'PR #17 CI absent' "$log")" -eq 3 ] || fail "workflow file at the PR's head, removed at HEAD: exit $rc: $(cat a4.out "$log")"
# P3R1-19: the workflow file refuses only an absent record; a green one of the same head passes
jq '.verdict = "success"' "$JOB/gate-logs/ci-pr-17.json" > ci17 && mv ci17 "$JOB/gate-logs/ci-pr-17.json"
passes "green record with a workflow file at the PR's head"
[ "$(grep -c 'PR #17 CI absent' "$log")" -eq 3 ] || fail "green record refused as absent: $(cat "$log")"
# a head that is no commit of the workdir's repo: whether runs were due cannot be read, so absent is refused
echo "$h8" > "$FAKE_GH/pr-17-head"
jq --arg h "$h8" '.verdict = "absent" | .head_sha = $h' "$JOB/gate-logs/ci-pr-17.json" > ci17 && mv ci17 "$JOB/gate-logs/ci-pr-17.json"
refused "PR #17 CI absent: no runs, and its head $h8 is no commit git can read in" "absent CI, head not in the workdir's repo"
echo ok
