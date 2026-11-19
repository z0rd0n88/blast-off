#!/usr/bin/env bash
# probes2.sh: false-refusal hunt on the real templates/checkpoint.md (comment verbatim), closed as brief
# step 4 says, through receipt_all_done + ci_check with the libs sourced (no suite). Usage: bash probes2.sh <tree>
set -uo pipefail
W="${1:?tree}"
T="$(mktemp -d /tmp/p3r4-probe2.XXXXXX)"; echo "tmp: $T"
H8=8888888888888888888888888888888888888888
mkdir -p "$T/gh"; export FAKE_GH="$T/gh"; echo "$H8" > "$T/gh/pr-8-head"; PATH="$W/tests/fakes:$PATH"
# <name> <want> <status cell for row 0> [sed script applied to the file] [crlf]
run() {
  local n="$1" want="$2" cell="$3" extra="${4:-}" j="$T/$1"; mkdir -p "$j/gate-logs"
  sed -e 's/^status: running/status: done/' \
      -e "s/^| 0 | <name> | <acceptance> | pending |\$/| 0 | a | b | ${cell//\//\\/} |/" \
      -e 's/^| 1 | <name> | <acceptance> | pending |$/| 1 | a | b | done (abc1234) · no PR · usage 5h 3% 7d 41% |/' \
      -e 's/^| 2 | <name> | <acceptance> | pending |$/| 2 | a | b | done (abcdef0) · PR #8 · usage unknown |/' \
      "$W/templates/checkpoint.md" > "$j/checkpoint.md"
  [ -z "$extra" ] || sed -i "$extra" "$j/checkpoint.md"
  [ "${5:-}" != crlf ] || sed -i 's/$/\r/' "$j/checkpoint.md"
  jq -n --arg h "$H8" '{pr: 8, head_sha: $h, verdict: "success", runs: []}' > "$j/gate-logs/ci-pr-8.json"
  local out rc
  out="$( (JOB="$j" WORKDIR="$T" TOP=
     log() { echo "LOG: $*"; }; chain_end() { echo "END $1: $2"; exit "$1"; }; die() { echo "DIE: $*"; exit 1; }
     # shellcheck source=/dev/null
     source "$W/lib/checkpoint.sh"; source "$W/lib/receipt.sh"; source "$W/lib/ci.sh"
     receipt_all_done; ci_check; echo "END 0: job done") 2>&1)"; rc=$?
  local got=pass; [ "$rc" -eq 0 ] || got=refuse; local tag=OK; [ "$got" = "$want" ] || tag=UNEXPECTED
  printf 'PROBE %-10s %-26s exit %-2s want %-6s | %s\n' "$tag" "$n" "$rc" "$want" "$(grep -E '^(END|DIE)' <<< "$out" | tail -1 | cut -c1-140)"
}
run tmpl-as-brief pass 'done (abc1234) · PR #8 · usage 5h 3% 7d 40%'
run tmpl-crlf pass 'done (abc1234) · PR #8 · usage 5h 3% 7d 40%' '' crlf
run tmpl-ci-green pass 'done (abc1234) · PR #8 · CI green'
run tmpl-two-prs pass 'done (abc1234) · PR #8 · PR #08'
run tmpl-Done-caps pass 'Done (abc1234) · PR #8'
run tmpl-sha-backtick refuse 'done (`abc1234`) · PR #8'
run tmpl-sha-noparen refuse 'done abc1234 · PR #8'
run tmpl-sha-space refuse 'done (abc1234 ) · PR #8'
run tmpl-ci-count refuse 'done (abc1234) · PR #8 · CI 3/3 green'
run tmpl-pr-merged-date refuse 'done (abc1234) · PR #8 merged 11-16'
run tmpl-h3-completed refuse 'done (abc1234) · PR #8' '/^## Completed phases/a ### Phase plan changes'
run tmpl-row-notes-pipe refuse 'done (abc1234) · PR #8' '/^| 2 | a/a | | | | |'
echo "tmp left: $T"
