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

# a verdict line with no tally still writes the whole receipt, tally null (P4R2-1)
gate 6 'GATE: PASS'; rc=0; "$bo" receipt "$JOB" 6 > r8.out 2>&1 || rc=$?
[ "$rc" -eq 0 ] || fail "receipt on a bare GATE: PASS exit $rc: $(cat r8.out)"
gate 7 'GATE: FAIL'; rc=0; "$bo" receipt "$JOB" 7 > r9.out 2>&1 || rc=$?
[ "$rc" -eq 1 ] || fail "receipt on a bare GATE: FAIL exit $rc, want 1"
for kv in 6:PASS 7:FAIL; do
  jq -e --arg k "${kv%:*}" --arg v "${kv#*:}" --arg h "$head" '.phase == $k and .verdict == $v
    and .verdict_line == "GATE: \($v)" and .head_sha == $h
    and .tally == {"passed": null, "failed": null, "shellcheck": null}' "$JOB/gate-logs/phase-${kv%:*}.json" > /dev/null ||
    fail "bare verdict receipt $kv: $(cat "$JOB/gate-logs/phase-${kv%:*}.json" 2>&1)"
done

# no log, a log with no verdict line, a phase that is not a row key: exit 1, nothing written
rc=0; "$bo" receipt "$JOB" 3 > r3.out 2>&1 || rc=$?
[ "$rc" -eq 1 ] && [ ! -e "$JOB/gate-logs/phase-3.json" ] || fail "receipt with no log: exit $rc: $(cat r3.out)"
gate 4 $'PASS 00-harness\nall good'
rc=0; "$bo" receipt "$JOB" 4 > r4.out 2>&1 || rc=$?
[ "$rc" -eq 1 ] && [ ! -e "$JOB/gate-logs/phase-4.json" ] || fail "receipt with no verdict line: exit $rc: $(cat r4.out)"
rc=0; "$bo" receipt "$JOB" ../x > r5.out 2>&1 || rc=$?
[ "$rc" -eq 1 ] || fail "receipt for phase '../x' exit $rc, want 1"
# a filtered tests/run (BLAST_OFF_TEST_ONLY) is not the gate: its log, as tests/run wrote it, ends in no
# GATE: verdict, so one green scenario never receipts a phase. The fixture sits in the job dir: the tree stays clean.
mkdir "$JOB/onlyfix"; printf 'exit 0\n' > "$JOB/onlyfix/01-ok.sh"
BLAST_OFF_TEST_ONLY=01-ok BLAST_OFF_NO_SHELLCHECK=1 "$REPO/tests/run" "$JOB/onlyfix" > "$JOB/gate-logs/phase-8.log" 2>&1 ||
  fail "filtered fixture run failed: $(cat "$JOB/gate-logs/phase-8.log")"
rc=0; "$bo" receipt "$JOB" 8 > r10.out 2>&1 || rc=$?
[ "$rc" -eq 1 ] && [ ! -e "$JOB/gate-logs/phase-8.json" ] || fail "receipt on a filtered run's log: exit $rc: $(cat r10.out "$JOB/gate-logs/phase-8.log")"
grep -q 'receipt refused: the last line of .*phase-8.log is not a GATE: verdict' "$JOB/run.log" || fail "filtered-log refusal not logged: $(cat "$JOB/run.log")"

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
echo y > "$w/code.txt"; git -C "$w" add code.txt; git -C "$w" -c user.name=t -c user.email=t@t commit -q -m later  # code: row 1 (done before) differs from HEAD
gate 2 'GATE: PASS passed=1 failed=0 shellcheck=ok'; "$bo" receipt "$JOB" 2 > /dev/null
rc=0; "$bo" run "$JOB" > c4.out 2>&1 || rc=$?
[ "$rc" -eq 9 ] && grep -q "phase row 2 receipt is for $(git -C "$w" rev-parse HEAD), not" "$log" || fail "stale receipt: exit $rc: $(cat "$log")"
hh="$(git -C "$w" rev-parse HEAD)"  # P4R3-1: the advice clears exit 9 when followed literally (line below follows it)
grep -q "then make HEAD's commit the row's: the first 7 to 40 hex word in its Status cell counts, so replace, not append (the receipt names ${hh:0:7}; if that is HEAD, only the row needs it)" "$log" || fail "stale receipt advice: $(cat "$log")"
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
plan '| 1 | p1 | x | done (earlier) · no PR |'
rc=0; "$bo" run "$JOB" > g1.out 2>&1 || rc=$?
[ "$rc" -eq 0 ] || fail "non-git done row: exit $rc: $(cat "$JOB/run.log")"
grep -q 'receipt check off' "$JOB/run.log" || fail "receipt check off not logged: $(cat "$JOB/run.log")"

# --- doubt pass fixes (D4-1..D4-8) ---
new_job later close-sha-later
repo
w="$(dirname "$JOB")" log="$JOB/run.log"
plan '| 1 | p1 | x | pending |'
gate 1 'GATE: PASS passed=1 failed=0 shellcheck=ok'; "$bo" receipt "$JOB" 1 > /dev/null
# D4-1: the child names the receipted commit, then commits more code: the row's commit is not HEAD's code
rc=0; "$bo" run "$JOB" > l1.out 2>&1 || rc=$?
[ "$rc" -eq 9 ] && grep -q 'phase row 1 is done at [0-9a-f]* but code changed after it' "$log" || fail "code after the receipted commit: exit $rc: $(cat "$log")"
grep -q 'name the receipted commit' "$log" && fail "exit 9 advice names the bypass: $(cat "$log")"
# D4-1: a row commit outside HEAD's history (another branch) is refused
new_job side noop
repo
w="$(dirname "$JOB")" log="$JOB/run.log"
git -C "$w" checkout -q -b side && git -C "$w" -c user.name=t -c user.email=t@t commit -q --allow-empty -m side
gate 1 'GATE: PASS passed=1 failed=0 shellcheck=ok'; "$bo" receipt "$JOB" 1 > /dev/null
s7="$(git -C "$w" rev-parse --short HEAD)"; git -C "$w" checkout -q -
plan "| 1 | p1 | x | done ($s7) |"
rc=0; "$bo" run "$JOB" > s1.out 2>&1 || rc=$?
[ "$rc" -eq 9 ] && grep -q "phase row 1 commit $s7 is not in HEAD's history" "$log" || fail "row commit off HEAD: exit $rc: $(cat "$log")"
# D4-2: the receipt says PASS but its gate log now ends FAIL; a receipt with no gate log
new_job relog noop
repo
log="$JOB/run.log"; s7="$(git -C "$(dirname "$JOB")" rev-parse --short HEAD)"
plan "| 1 | p1 | x | done ($s7) |"
gate 1 'GATE: PASS passed=1 failed=0 shellcheck=ok'; "$bo" receipt "$JOB" 1 > /dev/null
gate 1 'GATE: FAIL passed=0 failed=1 shellcheck=ok'
rc=0; "$bo" run "$JOB" > g2.out 2>&1 || rc=$?
[ "$rc" -eq 9 ] && grep -q 'phase row 1 receipt does not match its gate log' "$log" || fail "receipt vs gate log: exit $rc: $(cat "$log")"
jq '.gate_log = null' "$JOB/gate-logs/phase-1.json" > hand.json && mv hand.json "$JOB/gate-logs/phase-1.json"
gate 1 'GATE: PASS passed=1 failed=0 shellcheck=ok'
rc=0; "$bo" run "$JOB" > g3.out 2>&1 || rc=$?
[ "$rc" -eq 9 ] && [ "$(grep -c 'receipt does not match its gate log' "$log")" -eq 2 ] || fail "receipt with no gate log: exit $rc: $(cat "$log")"
# D4-8: the newest run in an appended log died before its verdict: the earlier PASS is not the verdict
gate 5 $'GATE: PASS passed=1 failed=0 shellcheck=ok\nPASS 00-harness\n'
rc=0; "$bo" receipt "$JOB" 5 > r6.out 2>&1 || rc=$?
[ "$rc" -eq 1 ] && [ ! -e "$JOB/gate-logs/phase-5.json" ] || fail "verdict not the last line: exit $rc: $(cat r6.out)"
grep -q 'receipt refused: the last line of .*phase-5.log is not a GATE: verdict' "$JOB/run.log" || fail "no-verdict refusal not logged: $(cat "$JOB/run.log")"
gate 5 $'GATE: PASS passed=1 failed=0 shellcheck=ok\n\n'
"$bo" receipt "$JOB" 5 > /dev/null || fail "trailing blank lines after the verdict refused"
# D4-3: a receipt is refused while the tree has uncommitted paths outside the job dir
echo x > "$(dirname "$JOB")/wip.txt"
rc=0; "$bo" receipt "$JOB" 5 > r7.out 2>&1 || rc=$?
[ "$rc" -eq 1 ] && grep -q 'wip.txt' r7.out || fail "receipt on a dirty tree: exit $rc: $(cat r7.out)"
grep -q 'receipt refused: uncommitted paths outside the job dir.* wip.txt' "$JOB/run.log" || fail "dirty-tree refusal not logged: $(cat "$JOB/run.log")"
jq -e '.verdict == "PASS"' "$JOB/gate-logs/phase-5.json" > /dev/null || fail "a refused receipt changed the earlier one"
rm "$(dirname "$JOB")/wip.txt"
# D4-4: done with a row still pending is refused; `Done` and a dotted key are done rows too
new_job open 'done'
repo
log="$JOB/run.log"; s7="$(git -C "$(dirname "$JOB")" rev-parse --short HEAD)"
plan "| 1 | p1 | x | done ($s7) · no PR |"$'\n'"| 2 | p2 | x | pending |"
gate 1 'GATE: PASS passed=1 failed=0 shellcheck=ok'; "$bo" receipt "$JOB" 1 > /dev/null
rc=0; "$bo" run "$JOB" > o1.out 2>&1 || rc=$?
[ "$rc" -eq 9 ] && grep -q 'status done but phase row 2 is not done' "$log" || fail "done with a pending row: exit $rc: $(cat "$log")"
grep -q '^status: done$' "$JOB/checkpoint.md" || fail "exit 9 at done changed the status"
sed -i "s/^| 2 | p2 | x | pending |$/| 2.5 | p2 | x | Done ($s7) · no PR |/" "$JOB/checkpoint.md"
rc=0; "$bo" run "$JOB" > o2.out 2>&1 || rc=$?
[ "$rc" -eq 9 ] && grep -q "phase row 2.5 is done at $s7 but has no receipt" "$log" || fail "Done row 2.5: exit $rc: $(cat "$log")"
gate 2.5 'GATE: PASS'; "$bo" receipt "$JOB" 2.5 > /dev/null  # a bare verdict, no tally, receipts a done row too (P4R2-1)
rc=0; "$bo" run "$JOB" > o3.out 2>&1 || rc=$?
[ "$rc" -eq 0 ] || fail "all rows done and receipted: exit $rc: $(cat "$log")"
# D4-7: receipt [workdir]: the job dir outside the repo it gates
new_job wd noop
wd="$PWD/wd-$$"; mkdir -p "$wd"; git -C "$wd" init -q && git -C "$wd" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
gate 1 'GATE: PASS passed=1 failed=0 shellcheck=ok'
rc=0; "$bo" receipt "$JOB" 1 "$wd" > w1.out 2>&1 || rc=$?
[ "$rc" -eq 0 ] && jq -e --arg h "$(git -C "$wd" rev-parse HEAD)" '.head_sha == $h' "$JOB/gate-logs/phase-1.json" > /dev/null || fail "receipt with a workdir: exit $rc: $(cat w1.out)"
echo ok
