#!/usr/bin/env bash
# Reviewer round 2: own mutants + one end-to-end probe, scenario 41 only, in a /tmp copy, one run at a time.
set -uo pipefail
WT=/home/alex/blast-off/.claude/worktrees/pending-items-53932d
S="$(dirname "$0")"
if pgrep -af 'tests/run' | grep -v pgrep | grep -q .; then echo "ANOTHER SUITE RUNNING; nothing started"; pgrep -af 'tests/run'; exit 3; fi
grep -q install_units "$WT/tests/41-ci-wait.sh" && { echo "41 calls install_units; stop"; exit 3; }
C="$(mktemp -d "$S/copy.XXXXXX")"
git -C "$WT" archive HEAD | tar -x -C "$C"
cp "$C/lib/ci.sh" "$S/ci.sh.pristine"; cp "$C/tests/41-ci-wait.sh" "$S/41.pristine"
run41() { ( cd "$C" && BLAST_OFF_TEST_ONLY=41-ci-wait tests/run 2>&1 ) > "$S/out-$1.log"; local rc=$?
  echo "== $1: rc=$rc $(grep -E '^(PASS|FAIL) 41' "$S/out-$1.log" | head -1) :: $(grep -m1 'FAIL:' "$S/out-$1.log" | cut -c1-230)"; }
SECONDS=0
run41 baseline; echo "   (one run takes $SECONDS s)"
mut() { # name, sed expr
  cp "$S/ci.sh.pristine" "$C/lib/ci.sh"; sed -i "$2" "$C/lib/ci.sh"
  if cmp -s "$S/ci.sh.pristine" "$C/lib/ci.sh"; then echo "== $1: MUTATION DID NOT APPLY"; return; fi
  run41 "$1"; cp "$S/ci.sh.pristine" "$C/lib/ci.sh"; }
mut C1-pathspec-typo 's#HEAD -- \.github/workflows)#HEAD -- .github/workflowz)#'
mut C2-absent-pass-not-logged 's#^        log "PR \#\$pr: no CI runs and no workflow file at HEAD#        : "PR \#$pr: no CI runs and no workflow file at HEAD#'
mut C3-whole-row-not-last-cell 's#{ print \$(NF-1) }#{ print $0 }#'
mut C4-dispatch-counted-push-dropped 's#select(.event != "workflow_dispatch")#select(.event != "push")#'
# End-to-end on the UNMUTATED code: row 0 names PR #8 (green record), row 1 is closed with no PR token and
# its PR #7 (red record) is named only under Completed phases. Reported through an unconditional fail.
cp "$S/41.pristine" "$C/tests/41-ci-wait.sh"
sed -i '$d' "$C/tests/41-ci-wait.sh"   # drop the final `echo ok`
cat >> "$C/tests/41-ci-wait.sh" <<'EOF'
new_job mx 'done'; log="$JOB/run.log"
printf '%s\n' '' '## Phase plan' '| # | Phase | Done when | Status |' '|---|---|---|---|' \
  '| 0 | a | b | done (abc1234) · PR #8 |' '| 1 | a | b | done (abc1234) |' \
  '## Completed phases' '- **Phase 1, a** (done). PR #7; CI read.' >> "$JOB/checkpoint.md"
mkdir -p "$JOB/gate-logs"
cp "$JOB/../../test-$$-cmd/job/gate-logs/ci-pr-8.json" "$JOB/../../test-$$-cmd/job/gate-logs/ci-pr-7.json" "$JOB/gate-logs/"
rc=0; "$bo" run "$JOB" > mx.out 2>&1 || rc=$?
fail "E2E-MIXED exit=$rc; record7=$(jq -c '{pr,verdict}' "$JOB/gate-logs/ci-pr-7.json"); log: $(grep -E 'CI read|PR #|job done' "$log" | tr '\n' ';')"
EOF
run41 e2e-mixed
grep 'E2E-MIXED' "$S/out-e2e-mixed.log" | cut -c1-600
echo "total $SECONDS s; copy at $C (left in place)"
pgrep -af 'tests/run' | grep -v pgrep || echo "no suite left running"
grep ^ExecStart ~/.config/systemd/user/blast-off@.service
