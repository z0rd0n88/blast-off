#!/usr/bin/env bash
# mutants-41.sh: fix round 2's own check of scenario 41, on a /tmp copy of the worktree, one run at a time.
#   1. baseline: the copy as it is passes (and what the NUL case ends in)
#   2. RED for the case added by the continuing unit ("table with no rows"): HEAD's lib/ci.sh and
#      lib/checkpoint.sh under the new tests, fail() not exiting
#   3. six mutants of the new lib/ci.sh, one change each; each must be killed
# Usage: bash mutants-41.sh <worktree>     Output: stdout. Leaves its temp dirs in place.
set -uo pipefail
W="${1:?worktree}"
pgrep -af '[t]ests/run' && { echo "another suite is running; not started"; exit 1; }
C="$(mktemp -d /tmp/p3f2-mut.XXXXXX)"; K="$(mktemp -d /tmp/p3f2-keep.XXXXXX)"
cp -r "$W"/bin "$W"/lib "$W"/tests "$W"/templates "$W"/docs "$W"/skills "$W"/scripts "$W"/README.md "$C"/
echo "copy: $C   keep: $K"
run41() { (cd "$C" && BLAST_OFF_TEST_KEEP="$K" BLAST_OFF_TEST_ONLY=41-ci-wait tests/run 2>&1); }
first() { grep -m1 'FAIL:' | cut -c1-170; }

echo "== baseline"
run41 | grep -E '^(PASS|FAIL|GATE)' | cut -c1-120
echo "NUL case, last run.log line: $(tail -n 1 "$K"/41-ci-wait/cwd/test-*-nul/job/run.log | cut -c1-160)"

echo "== RED: HEAD's lib/ci.sh and lib/checkpoint.sh, new tests, fail() not exiting"
git -C "$W" show HEAD:lib/ci.sh > "$C/lib/ci.sh"; git -C "$W" show HEAD:lib/checkpoint.sh > "$C/lib/checkpoint.sh"
sed -i 's/^fail() { echo "FAIL: \$\*" >&2; exit 1; }$/fail() { echo "FAIL: $*" >\&2; }/' "$C/tests/lib.sh"
grep -q '^fail() { echo "FAIL: \$\*" >&2; }$' "$C/tests/lib.sh" || echo "fail() NOT PATCHED"
run41 > /dev/null
echo "FAIL lines: $(grep -c '^FAIL:' "$K/41-ci-wait/out")"
grep '^FAIL: \(table with no rows\|no table\|mis-typed heading\)' "$K/41-ci-wait/out" | cut -c1-170
cp "$W/tests/lib.sh" "$C/tests/lib.sh"

mut() { # <name> <expect> <sed script>
  cp "$W/lib/ci.sh" "$C/lib/ci.sh"; cp "$W/lib/checkpoint.sh" "$C/lib/checkpoint.sh"
  sed -i "$3" "$C/lib/ci.sh"
  if cmp -s "$W/lib/ci.sh" "$C/lib/ci.sh"; then echo "$1: MUTATION NOT APPLIED"; return; fi
  bash -n "$C/lib/ci.sh" || { echo "$1: SYNTAX ERROR, not a valid mutant"; return; }
  local out; out="$(run41)"
  if grep -q '^PASS 41-ci-wait' <<< "$out"; then echo "$1: SURVIVED (wanted: $2)"
  else echo "$1: KILLED: $(first <<< "$out")"; fi
}
echo "== mutants of the new lib/ci.sh"
mut "mA no-done-row refusal dropped" "no table" '/Phase plan has no done row/d'
mut "mB neither refusal dropped" "done row with neither" 's/^      \[ -n "\$n" \] || chain_end 10 "phase row \$k is done but.*$/      [ -n "$n" ] || true/'
mut "mC PRs read from the whole file again" "a PR outside a Status cell read" 's|prs="\$(ci_prs <<< "\$cells")"|prs="$(ci_prs < "$JOB/checkpoint.md")"|'
mut "mD workdir HEAD read, not the record head" "workflow file at HEAD, none at the PR's head" 's|"\$h^{commit}"|HEAD|'
mut "mE stray #<n> check dropped" "Status cell 'PR #8, #7'" '/=~ \$stray \]\] ||/,+1d'
mut "mF unreadable head commit passes" "head not in the workdir's repo" 's#-- .github/workflows 2>/dev/null)" ||#-- .github/workflows 2>/dev/null || true)" ||#'
echo "== done"
grep ^ExecStart ~/.config/systemd/user/blast-off@.service
