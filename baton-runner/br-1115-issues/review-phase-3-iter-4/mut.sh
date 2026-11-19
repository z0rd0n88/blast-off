#!/usr/bin/env bash
# mut.sh: review round 4's real-runner probes, base comparison and mutants. Scenarios 41, 51, 70 only
# (none calls install_units), on a /tmp copy with no .git, one run at a time. Usage: bash mut.sh <worktree>
set -uo pipefail
W="${1:?worktree}"; D="$(dirname "$(readlink -f "$0")")"
pgrep -af '[t]ests/run' && { echo "another suite is running; not started"; exit 1; }
C="$(mktemp -d /tmp/p3r4-mut.XXXXXX)"; K="$(mktemp -d /tmp/p3r4-keep.XXXXXX)"; B="$(mktemp -d /tmp/p3r4-base.XXXXXX)"
cp -r "$W"/bin "$W"/lib "$W"/tests "$W"/templates "$W"/docs "$W"/skills "$W"/scripts "$W"/README.md "$C"/
echo "copy: $C   keep: $K   base: $B"
grep -c install_units "$C/tests/41-ci-wait.sh" "$C/tests/51-templates.sh" "$C/tests/70-docs.sh"
run1() { (cd "$C" && BLAST_OFF_TEST_KEEP="$K" BLAST_OFF_TEST_ONLY="$1" tests/run 2>&1); }
first() { grep -m1 'FAIL' | cut -c1-220; }

echo "== real runner: escapes appended to scenario 41"
cp "$C/tests/41-ci-wait.sh" "$C/41.orig"
sed -i '$d' "$C/tests/41-ci-wait.sh"
cat >> "$C/tests/41-ci-wait.sh" <<'EOF'
echo "$h7" > "$FAKE_GH/pr-7-head"; echo "$h8" > "$FAKE_GH/pr-8-head"
q() { local n="$1"; shift; done_job "$n" "${plan[@]}" '| 0 | a | b | done (abc1234) · PR #8 |' "$@"; rec 7; rec 8
  rc=0; "$bo" run "$JOB" > q.out 2>&1 || rc=$?; echo "PROBE $n exit $rc: $(tail -1 "$log" | cut -c1-170)"; }
q green-only
q red-row '| 1 | a | b | done (abc1234) · PR #7 |'
q html-table '' '<table><tr><td>1</td><td>a</td><td>b</td><td>done (abc1234) · PR #7</td></tr></table>'
q cmt-h2-then-table '<!--' '## end' '-->' '| # | Phase | Done when | Status |' '|---|---|---|---|' '| 1 | a | b | done (abc1234) · PR #7 |'
q fence-h2-then-table '```' '## x' '```' '| # | Phase | Done when | Status |' '|---|---|---|---|' '| 1 | a | b | done (abc1234) · PR #7 |'
q gfm-pipeless-cont '1 a b done (abc1234) · PR #7'
echo ok
EOF
bash -n "$C/tests/41-ci-wait.sh" || exit 1
run1 41-ci-wait | grep -E '^(PASS|FAIL|GATE)' | cut -c1-200
grep '^PROBE' "$K/41-ci-wait/out"
cp "$C/41.orig" "$C/tests/41-ci-wait.sh"

echo "== phase-2 base: the same unit probes"
git -C "$W" archive feat/br-1115-issues/phase-2 | tar -x -C "$B"
bash "$D/probes.sh" "$B" 2>&1 | grep -E 'html-table|cmt-h2|fence-h2|gfm-pipeless|base-'

echo "== mutants (each must be KILLED)"
mut() { # <scenario> <file rel> <name> <sed script>
  cp "$W/$2" "$C/$2"; sed -i "$4" "$C/$2"
  if cmp -s "$W/$2" "$C/$2"; then echo "$3: MUTATION NOT APPLIED"; return; fi
  case "$2" in *.sh) bash -n "$C/$2" || { echo "$3: SYNTAX ERROR"; cp "$W/$2" "$C/$2"; return; } ;; esac
  local out; out="$(run1 "$1")"
  if grep -q "^PASS $1" <<< "$out"; then echo "$3: SURVIVED"; else echo "$3: KILLED: $(first <<< "$out")"; fi
  cp "$W/$2" "$C/$2"
}
mut 41-ci-wait lib/ci.sh "u1 cp_unread call dropped" 's/^  u="\$(cp_unread)" || chain_end 10 .*$/  u=/'
mut 41-ci-wait lib/checkpoint.sh "u2 second-heading refusal dropped" 's/if (h++) {/if (0) {/'
mut 41-ci-wait lib/checkpoint.sh "u3 mid-line CR guard dropped" 's#if (!/\\r/ && (#if ((#'
mut 41-ci-wait lib/checkpoint.sh "u4 header may be any later line" 's/if (!f++ \&\& /if (/'
mut 41-ci-wait lib/checkpoint.sh "u5 header may hold done" 's/ \&\& tolower(st) !~ \/done\/) next/) next/'
mut 41-ci-wait lib/ci.sh "w1 P3R3-3 whitelist dropped" 's/^    \[\[ ! \${rest,,} =~ .*\]\] ||$/    true ||/'
mut 41-ci-wait lib/ci.sh "m1 C1: absent+workflow refusal dropped" 's/^        \[ -z "\$wf" \] || chain_end 10 .*$/        true/'
mut 41-ci-wait lib/ci.sh "m2 C2: absent pass not logged" 's/^        log "PR #\$pr: no CI runs and no workflow file.*$/        : ;;/'
mut 41-ci-wait lib/ci.sh "m5 C4: dispatch filter dropped" 's/select(.event != "workflow_dispatch") | //'
mut 51-templates templates/checkpoint.md "t1 a literal pipe back in the template comment" 's/^- One `## Phase plan` heading and one table under it:/- One `## Phase plan` heading (a | b) and one table under it:/'
mut 70-docs README.md "d1 README second-heading clause cut" 's/^file has a second Phase plan heading/file has two Phase plan headings/'
mut 70-docs skills/blast-off/SKILL.md "d2 SKILL 'no way out' cut" 's/that `no PR` is no way out/that `no PR` is fine/'
mut 70-docs README.md "d3 README 'only from those cells' cut" 's/PRs are read only from those/PRs are read from those/'
echo "== done"; pgrep -af '[t]ests/run'
grep ^ExecStart ~/.config/systemd/user/blast-off@.service
