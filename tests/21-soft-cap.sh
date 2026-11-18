#!/usr/bin/env bash
# 21-soft-cap: the child cap is the checkpoint's Phase plan rows times JOB_CAP_FACTOR (default 3),
# or JOB_MAX_CHILDREN when set; reaching it writes `status: paused-cap` and exits 6, and a re-run
# continues the chain. No Phase plan table keeps the hard cap: exit 4, status unchanged, except that a
# `paused-cap` already reads `running` by then (owner ruling P4R2-4; test 10).
source "$REPO/tests/lib.sh"
use_fakes
export CLAUDE_FLAGS="--model fake --effort low" GH_TOKEN=dummy-not-a-token JOB_CHILD_TIMEOUT=30
bo="$REPO/bin/blast-off"
plan() { # plan <rows>: a Phase plan table with <rows> phases, then another section
  local i; printf '\n## Phase plan\n| # | Phase | Done when | Status |\n|---|---|---|---|\n' >> "$JOB/checkpoint.md"
  for ((i=0; i<$1; i++)); do printf '| %s | p%s | x | pending |\n' "$i" "$i" >> "$JOB/checkpoint.md"; done
  printf '\n## Decisions\n| 9 | not a phase row |\n' >> "$JOB/checkpoint.md"
}

# 2 phases x factor 1: two children make progress, the third would pass the cap -> paused-cap, exit 6
new_job soft step
plan 2
rc=0; JOB_CAP_FACTOR=1 "$bo" run "$JOB" > soft.out 2>&1 || rc=$?
log="$JOB/run.log"
[ "$rc" -eq 6 ] || fail "soft cap run exit $rc, want 6: $(cat soft.out; cat "$log")"
grep -q '^status: paused-cap$' "$JOB/checkpoint.md" || fail "status not paused-cap: $(head -4 "$JOB/checkpoint.md")"
grep -q 'child cap 2 (soft: 2 Phase plan rows x JOB_CAP_FACTOR 1)' "$log" || fail "cap source not logged: $(cat "$log")"
grep -q 'soft cap 2 reached; status paused-cap; run again to continue' "$log" || fail "no soft cap line: $(cat "$log")"
grep -q 'child 2 launched' "$log" || fail "cap 2 stopped before child 2"
grep -q 'child 3 launched' "$log" && fail "child 3 launched past the soft cap"
# the paused-cap resume saves its new base itself (P4R1-8): at cap 0 it pauses again before any launch, so
# only that save can make the file '2 2' (a run from base == launched, P4R1-9: the `base` job below)
rc=0; JOB_MAX_CHILDREN=0 "$bo" run "$JOB" > zero.out 2>&1 || rc=$?
[ "$rc" -eq 6 ] && [ "$(cat "$JOB/child-count")" = "2 2" ] && [ "$(grep -c 'child [0-9]* launched' "$log")" -eq 2 ] ||
  fail "paused-cap resume at cap 0: exit $rc, child-count '$(cat "$JOB/child-count")', want 6 and '2 2': $(cat zero.out "$log")"
# back to the first pause's '2 0', so the re-run below must move the in-memory base itself, not only the file (P4R2-2)
printf '2 0\n' > "$JOB/child-count"

printf 'done\n' > "$JOB/fake-mode"; sed -i 's/| pending |$/| done · no PR |/' "$JOB/checkpoint.md"  # done needs every row done (D4-4), each with its PR or `no PR`
printf 'done\n' > "$JOB/fake-mode"
rc=0; JOB_CAP_FACTOR=1 "$bo" run "$JOB" > rerun.out 2>&1 || rc=$?
[ "$rc" -eq 0 ] || fail "re-run after paused-cap exit $rc: $(cat rerun.out; cat "$log")"
grep -q 'status paused-cap -> running; the chain continues' "$log" || fail "re-run did not log the resume: $(cat "$log")"
[ "$(sed -n 's/^status_at_start=//p' "$JOB/fake-marker" | tail -n 1)" = running ] || fail "status at re-run start not running: $(cat "$JOB/fake-marker")"
grep -q '^status: done$' "$JOB/checkpoint.md" || fail "re-run did not finish the job"
# the re-run gets a fresh allotment of 2, but its child is child 3: numbering goes on (issue 22)
grep -q 'child 3 launched' "$log" && [ "$(grep -c 'child 1 launched' "$log")" -eq 1 ] || fail "child numbering did not go on after paused-cap: $(cat "$log")"

# a soft relaunch with status running reads `base` back from child-count: from '2 2' at cap 2 it launches
# child 3 and child 4, then pauses (P4R2-1)
new_job base step
plan 2
printf '2 2\n' > "$JOB/child-count"
rc=0; JOB_CAP_FACTOR=1 "$bo" run "$JOB" > base.out 2>&1 || rc=$?
[ "$rc" -eq 6 ] && grep -q 'child 3 launched' "$JOB/run.log" && grep -q 'child 4 launched' "$JOB/run.log" && ! grep -q 'child 5 launched' "$JOB/run.log" &&
  [ "$(cat "$JOB/child-count")" = "4 2" ] || fail "soft run from '2 2' at cap 2: exit $rc, child-count '$(cat "$JOB/child-count")', want 6, children 3 and 4, '4 2': $(cat base.out "$JOB/run.log")"

# a relaunch that is no paused-cap re-run keeps the count (issue 22): two stalls end the first run at
# cap 2's last child, so the re-run pauses before launching one
new_job relaunch noop
plan 2
rc=0; JOB_CAP_FACTOR=1 "$bo" run "$JOB" > rl.out 2>&1 || rc=$?
[ "$rc" -eq 5 ] || fail "two-stall run exit $rc, want 5: $(cat rl.out "$JOB/run.log")"
rc=0; JOB_CAP_FACTOR=1 "$bo" run "$JOB" > rl2.out 2>&1 || rc=$?
[ "$rc" -eq 6 ] && [ "$(grep -c 'child [0-9]* launched' "$JOB/run.log")" -eq 2 ] || fail "relaunch past soft cap 2: exit $rc, want 6 and no child: $(cat rl2.out "$JOB/run.log")"

# default factor 3 over one phase row: cap 3
new_job dflt step
plan 1
rc=0; env -u JOB_CAP_FACTOR "$bo" run "$JOB" > dflt.out 2>&1 || rc=$?
[ "$rc" -eq 6 ] || fail "default factor run exit $rc, want 6: $(cat dflt.out)"
grep -q 'child cap 3 (soft: 1 Phase plan rows x JOB_CAP_FACTOR 3)' "$JOB/run.log" || fail "default factor not 3: $(cat "$JOB/run.log")"
grep -q 'child 3 launched' "$JOB/run.log" && ! grep -q 'child 4 launched' "$JOB/run.log" || fail "default cap 3 not applied: $(cat "$JOB/run.log")"

# JOB_MAX_CHILDREN overrides the derived cap and stays soft
new_job over step
plan 5
rc=0; JOB_MAX_CHILDREN=1 "$bo" run "$JOB" > over.out 2>&1 || rc=$?
[ "$rc" -eq 6 ] || fail "override run exit $rc, want 6: $(cat over.out)"
grep -q 'child cap 1 (soft: JOB_MAX_CHILDREN)' "$JOB/run.log" || fail "override not logged: $(cat "$JOB/run.log")"

# a non-numeric factor is a usage error before any child
new_job badf step
plan 1
rc=0; JOB_CAP_FACTOR=x "$bo" run "$JOB" > badf.out 2>&1 || rc=$?
[ "$rc" -eq 1 ] || fail "JOB_CAP_FACTOR=x exit $rc, want 1"
[ ! -e "$JOB/fake-marker" ] || fail "a child ran with a bad JOB_CAP_FACTOR"
# so are a non-numeric child cap and timeout (P2R3-4), and a count past 9 digits, which would turn the
# cap off or overflow it (P4R2-9), and a leading zero, which shell arithmetic reads as octal (P5R1-4, owner Q3)
nbad=0; for bad in JOB_MAX_CHILDREN=2O JOB_CHILD_TIMEOUT=x JOB_MAX_CHILDREN=99999999999999999999 JOB_CAP_FACTOR=1000000000 JOB_MAX_CHILDREN=08 JOB_MAX_CHILDREN=010 JOB_CAP_FACTOR=03; do
  new_job "bad-$((++nbad))" 'done'
  rc=0; env "$bad" "$bo" run "$JOB" > bad.out 2>&1 || rc=$?
  [ "$rc" -eq 1 ] && [ ! -e "$JOB/fake-marker" ] && grep -q 'is not a whole number' bad.out || fail "$bad exit $rc, want 1 before any child: $(cat bad.out)"
done
echo ok
