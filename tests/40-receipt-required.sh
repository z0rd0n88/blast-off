#!/usr/bin/env bash
# 40-receipt-required: `blast-off receipt <job-dir> <phase>` turns the last GATE: line of
# gate-logs/phase-<n>.log into gate-logs/phase-<n>.json (F8). The runner refuses, with exit 9 and the
# status unchanged, a done Phase plan row that names no commit, has no receipt, has a FAIL receipt or a
# receipt for another commit; before child 1 and after every child. A workdir outside git is not checked.
source "$REPO/tests/lib.sh"
use_fakes
export CLAUDE_FLAGS="--model fake --effort low" GH_TOKEN=dummy-not-a-token JOB_CHILD_TIMEOUT=30
bo="$REPO/bin/blast-off"
repo() { # the job's workdir becomes a git repo with one commit; the job dir stays untracked
  local w; w="$(dirname "$JOB")"
  git -C "$w" init -q && git -C "$w" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
}
plan() { printf '\n## Phase plan\n| # | Phase | Done when | Status |\n|---|---|---|---|\n%s\n## Decisions\n' "$1" >> "$JOB/checkpoint.md"; }
gate() { mkdir -p "$JOB/gate-logs"; printf '%s\n' "$2" > "$JOB/gate-logs/phase-$1.log"; }

# --- receipt command ---
new_job cmd noop
repo
head="$(git -C "$(dirname "$JOB")" rev-parse HEAD)"
gate 1 $'PASS 00-harness\nGATE: FAIL passed=1 failed=1 shellcheck=ok\nPASS 00-harness\nGATE: PASS passed=11 failed=0 shellcheck=ok'
rc=0; "$bo" receipt "$JOB" 1 > r1.out 2>&1 || rc=$?
[ "$rc" -eq 0 ] || fail "receipt on a PASS log exit $rc: $(cat r1.out)"
r="$JOB/gate-logs/phase-1.json"
[ -s "$r" ] || fail "no receipt $r"
jq -e --arg h "$head" '.phase == "1" and .verdict == "PASS"
  and .verdict_line == "GATE: PASS passed=11 failed=0 shellcheck=ok"
  and .tally == {"passed": 11, "failed": 0, "shellcheck": "ok"}
  and .gate_log == "gate-logs/phase-1.log" and .head_sha == $h
  and (.utc | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"))
  and .written_by == "blast-off receipt"' "$r" > /dev/null || fail "receipt fields: $(cat "$r")"
grep -q "receipt phase 1: GATE: PASS passed=11 failed=0 shellcheck=ok at $head" "$JOB/run.log" || fail "receipt not logged: $(cat "$JOB/run.log")"

# a FAIL verdict is still written (evidence the runner can refuse with a reason), exit 1
gate 2 'GATE: FAIL passed=3 failed=2 shellcheck=fail'
rc=0; "$bo" receipt "$JOB" 2 > r2.out 2>&1 || rc=$?
[ "$rc" -eq 1 ] || fail "receipt on a FAIL log exit $rc, want 1"
jq -e '.verdict == "FAIL" and .tally.failed == 2' "$JOB/gate-logs/phase-2.json" > /dev/null || fail "FAIL receipt: $(cat "$JOB/gate-logs/phase-2.json" 2>&1)"

# no log, a log with no verdict line, a phase that is not a row key: exit 1, nothing written
rc=0; "$bo" receipt "$JOB" 3 > r3.out 2>&1 || rc=$?
[ "$rc" -eq 1 ] && [ ! -e "$JOB/gate-logs/phase-3.json" ] || fail "receipt with no log: exit $rc: $(cat r3.out)"
gate 4 $'PASS 00-harness\nall good'
rc=0; "$bo" receipt "$JOB" 4 > r4.out 2>&1 || rc=$?
[ "$rc" -eq 1 ] && [ ! -e "$JOB/gate-logs/phase-4.json" ] || fail "receipt with no verdict line: exit $rc: $(cat r4.out)"
rc=0; "$bo" receipt "$JOB" ../x > r5.out 2>&1 || rc=$?
[ "$rc" -eq 1 ] || fail "receipt for phase '../x' exit $rc, want 1"

# --- runner: exit 9 ---
new_job chain close-sha
repo
w="$(dirname "$JOB")"
plan $'| 1 | p1 | x | pending |\n| 2 | p2 | x | pending |'
log="$JOB/run.log" cp="$JOB/checkpoint.md"
# child 1 closes row 1 at the HEAD sha with no receipt -> exit 9, status unchanged, no child 2
rc=0; "$bo" run "$JOB" > c1.out 2>&1 || rc=$?
[ "$rc" -eq 9 ] || fail "done row without receipt: exit $rc, want 9: $(cat c1.out "$log")"
grep -q "phase row 1 is done at $(git -C "$w" rev-parse --short HEAD) but has no receipt" "$log" || fail "exit 9 reason: $(cat "$log")"
grep -q 'child 2 launched' "$log" && fail "child 2 launched after an unreceipted done row"
grep -q '^status: running$' "$cp" || fail "exit 9 changed the status"
# a re-run refuses before child 1
rc=0; "$bo" run "$JOB" > c1b.out 2>&1 || rc=$?
[ "$rc" -eq 9 ] && [ "$(grep -c '^child=' "$JOB/fake-marker")" -eq 1 ] || fail "re-run without receipt: exit $rc, children $(grep -c '^child=' "$JOB/fake-marker")"

# the receipt for row 1 lets the chain go on; child 1 of the re-run closes row 2 -> exit 9 on row 2
gate 1 'GATE: PASS passed=1 failed=0 shellcheck=ok'; "$bo" receipt "$JOB" 1 > /dev/null
rc=0; "$bo" run "$JOB" > c2.out 2>&1 || rc=$?
[ "$rc" -eq 9 ] && grep -q 'phase row 2 is done at .* but has no receipt' "$log" || fail "row 2: exit $rc: $(cat "$log")"

# a FAIL receipt is refused before child 1
gate 2 'GATE: FAIL passed=0 failed=1 shellcheck=ok'; "$bo" receipt "$JOB" 2 > /dev/null || true
rc=0; "$bo" run "$JOB" > c3.out 2>&1 || rc=$?
[ "$rc" -eq 9 ] && grep -q 'phase row 2 receipt .* verdict FAIL' "$log" || fail "FAIL receipt: exit $rc: $(cat "$log")"

# a receipt for another commit is refused
git -C "$w" -c user.name=t -c user.email=t@t commit -q --allow-empty -m later
gate 2 'GATE: PASS passed=1 failed=0 shellcheck=ok'; "$bo" receipt "$JOB" 2 > /dev/null
rc=0; "$bo" run "$JOB" > c4.out 2>&1 || rc=$?
[ "$rc" -eq 9 ] && grep -q "phase row 2 receipt is for $(git -C "$w" rev-parse HEAD), not" "$log" || fail "stale receipt: exit $rc: $(cat "$log")"
[ "$(grep -c '^child=' "$JOB/fake-marker")" -eq 2 ] || fail "a child ran past a refused receipt: $(cat "$JOB/fake-marker")"

# row 2 names the new commit: the receipt matches, child 1 finds nothing pending, done -> exit 0
sed -i "s/^\(| 2 | p2 | x | done (\)[0-9a-f]*/\1$(git -C "$w" rev-parse --short HEAD)/" "$cp"
rc=0; "$bo" run "$JOB" > c5.out 2>&1 || rc=$?
[ "$rc" -eq 0 ] || fail "all rows receipted: exit $rc: $(cat c5.out "$log")"

# a done row that names no commit -> exit 9 before child 1
new_job nosha 'done'
repo
plan '| 1 | p1 | x | done (earlier) |'
rc=0; "$bo" run "$JOB" > n1.out 2>&1 || rc=$?
[ "$rc" -eq 9 ] && grep -q 'phase row 1 is done but names no commit' "$JOB/run.log" || fail "row with no sha: exit $rc: $(cat "$JOB/run.log")"
[ ! -e "$JOB/fake-marker" ] || fail "a child ran with an unreceipted done row"

# a workdir outside git: no commit to match, check off and logged
new_job nogit 'done'
plan '| 1 | p1 | x | done (earlier) |'
rc=0; "$bo" run "$JOB" > g1.out 2>&1 || rc=$?
[ "$rc" -eq 0 ] || fail "non-git done row: exit $rc: $(cat "$JOB/run.log")"
grep -q 'receipt check off' "$JOB/run.log" || fail "receipt check off not logged: $(cat "$JOB/run.log")"
echo ok
