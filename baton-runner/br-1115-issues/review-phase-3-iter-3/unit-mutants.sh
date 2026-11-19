#!/usr/bin/env bash
# unit-mutants.sh: review round 3's own checks. Scenario 41 and 51 only, on a copy (no .git), one run at a time.
# Usage: bash unit-mutants.sh <worktree> <probe file>
set -uo pipefail
W="${1:?worktree}"; P="${2:?probes}"
pgrep -af '[t]ests/run' && { echo "another suite is running; not started"; exit 1; }
C="$(mktemp -d /tmp/p3r3-mut.XXXXXX)"; K="$(mktemp -d /tmp/p3r3-keep.XXXXXX)"
cp -r "$W"/bin "$W"/lib "$W"/tests "$W"/templates "$W"/docs "$W"/skills "$W"/scripts "$W"/README.md "$C"/
echo "copy: $C   keep: $K"
grep -c install_units "$C/tests/41-ci-wait.sh" "$C/tests/51-templates.sh"
run1() { (cd "$C" && BLAST_OFF_TEST_KEEP="$K" BLAST_OFF_TEST_ONLY="$1" tests/run 2>&1); }
first() { grep -m1 'FAIL:' | cut -c1-200; }
# scenario 41 plus probes: drop the final `echo ok`, append the probes (which end in echo ok)
sed -i '$d' "$C/tests/41-ci-wait.sh"; cat "$P" >> "$C/tests/41-ci-wait.sh"; bash -n "$C/tests/41-ci-wait.sh" || exit 1
echo "== baseline 41 (+probes)"
run1 41-ci-wait | grep -E '^(PASS|FAIL|GATE)| \| FAIL' | cut -c1-200
grep '^PROBE' "$K/41-ci-wait/out"
echo "== baseline 51"; run1 51-templates | grep -E '^(PASS|FAIL|GATE)' | cut -c1-160
mut() { # <scenario> <file rel> <name> <sed script>
  cp "$W/$2" "$C/$2"; sed -i "$4" "$C/$2"
  if cmp -s "$W/$2" "$C/$2"; then echo "$3: MUTATION NOT APPLIED"; return; fi
  case "$2" in *.sh) bash -n "$C/$2" || { echo "$3: SYNTAX ERROR"; cp "$W/$2" "$C/$2"; return; } ;; esac
  local out; out="$(run1 "$1")"
  if grep -q "^PASS $1" <<< "$out"; then echo "$3: SURVIVED"; else echo "$3: KILLED: $(first <<< "$out")"; fi
  cp "$W/$2" "$C/$2"
}
echo "== mutants, scenario 41"
mut 41-ci-wait lib/ci.sh "m1 C1: absent+workflow refusal dropped" 's/^        \[ -z "\$wf" \] || chain_end 10 .*$/        true/'
mut 41-ci-wait lib/ci.sh "m2 C2: absent pass not logged" 's/^        log "PR #\$pr: no CI runs and no workflow file.*$/        : ;;/'
mut 41-ci-wait lib/ci.sh "m3 no PR matched case-sensitively" 's/grep -qiE/grep -qE/'
mut 41-ci-wait lib/ci.sh "m4 both (no PR and a PR) refusal dropped" 's/^      \[ -z "\$n" \] || chain_end 10 "phase row \$k Status cell says.*$/      true/'
mut 41-ci-wait lib/ci.sh "m5 C4: dispatch filter dropped" 's/select(.event != "workflow_dispatch") | //'
mut 41-ci-wait lib/ci.sh "m6 absent: head check dropped" 's/absent) ci_head "\$pr"; h=/absent) h=/'
mut 41-ci-wait lib/ci.sh "m7 pathspec narrowed to ci.yml" 's#-- .github/workflows 2>/dev/null)" ||#-- .github/workflows/ci.yml 2>/dev/null)" ||#'
mut 41-ci-wait lib/ci.sh "m8 stray check without /pull/" "s~stray='#\\[0-9\\]|/pull/'~stray='#[0-9]'~"
mut 41-ci-wait lib/ci.sh "m9 C3: PRs read from the whole table section, not done cells" 's|prs="\$(ci_prs <<< "\$cells")"|prs="$(sed -n "/^## Phase plan/,/^## /p" "$JOB/checkpoint.md" \| ci_prs)"|'
mut 41-ci-wait lib/checkpoint.sh "m10 cells: whole row printed, not the Status cell" 's/if (d) print k "|" st/if (d) print k "|" $0/'
echo "== mutants, scenario 51"
mut 51-templates templates/checkpoint.md "t1 'only for a phase that opened no PR' cut from checkpoint.md" 's/ Write `no PR` only for a phase that opened no PR\.//'
mut 51-templates templates/checkpoint.md "t2 bypass sentence put back" 's/^- Over 150 lines/- A row closed without one gets no CI check.\n- Over 150 lines/'
mut 51-templates templates/brief.md "t3 brief: 'only for a phase that opened no PR' cut" 's/ only for a phase that/ for a phase that/'
mut 51-templates templates/brief.md "t4 brief: blocked-on-absent cut" 's/leave the row open, set `status: blocked`/go on/'
mut 51-templates templates/checkpoint.md "t5 'refuses done (exit 10) for a closed row with neither' cut" 's/The runner refuses done (exit 10)/The runner may refuse done/'
echo "== done"; pgrep -af '[t]ests/run'
grep ^ExecStart ~/.config/systemd/user/blast-off@.service
