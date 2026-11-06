#!/usr/bin/env bash
# 32-usage-per-phase: when a child closes a Phase plan row (its Status cell turns done), the runner
# appends the usage at that child's end to the cell: " · usage 5h 30% 7d 12%", or "usage unknown" with
# no record. A row done before the run, and a child that closes nothing, add nothing.
source "$REPO/tests/lib.sh"
use_fakes
export CLAUDE_FLAGS="--model fake --effort low" GH_TOKEN=dummy-not-a-token JOB_CHILD_TIMEOUT=30
export BLAST_OFF_STATE_DIR="$PWD/state"
mkdir -p "$BLAST_OFF_STATE_DIR"
bo="$REPO/bin/blast-off"
now=$(date +%s)

new_job rows close step close close close
printf '\n## Phase plan\n| # | Phase | Done when | Status |\n|---|---|---|---|\n| 0 | p0 | x | pending |\n| 1 | p1 | x | pending |\n| 2 | p2 | x | pending |\n| 5 | old | x | done (earlier) |\n\n## Decisions\n' >> "$JOB/checkpoint.md"
printf '{"five_hour":{"used_percentage":30.6,"resets_at":%s},"seven_day":{"used_percentage":12,"resets_at":%s}}\n' $((now + 3600)) $((now + 86400)) > "$JOB/fake-usage-1"
printf '{"seven_day":{"used_percentage":44,"resets_at":%s}}\n' $((now + 86400)) > "$JOB/fake-usage-2"
printf '{"seven_day":{"used_percentage":50,"resets_at":%s}}\n' $((now + 86400)) > "$JOB/fake-usage-3"
rc=0; "$bo" run "$JOB" > rows.out 2>&1 || rc=$?
cp="$JOB/checkpoint.md"
[ "$rc" -eq 0 ] || fail "rows run exit $rc: $(cat rows.out "$JOB/run.log")"
grep -qx '| 0 | p0 | x | done · usage 5h 30% 7d 12% |' "$cp" || fail "row 0: $(grep '^| 0 ' "$cp")"
grep -qx '| 1 | p1 | x | done · usage 7d 50% |' "$cp" || fail "row 1 (closed by child 3, not child 2): $(grep '^| 1 ' "$cp")"
grep -qx '| 2 | p2 | x | done · usage unknown |' "$cp" || fail "row 2 (no record): $(grep '^| 2 ' "$cp")"
grep -qx '| 5 | old | x | done (earlier) |' "$cp" || fail "row done before the run was marked: $(grep '^| 5 ' "$cp")"
[ "$(grep -c '· usage' "$cp")" -eq 3 ] || fail "usage marks: $(grep -c '· usage' "$cp"), want 3"
grep -q 'phase row 0 done; usage 5h 30% 7d 12%' "$JOB/run.log" || fail "row close not logged: $(cat "$JOB/run.log")"
echo ok
