#!/usr/bin/env bash
# probes.sh: review round 4's own probes of receipt_all_done + ci_check (the done path of lib/chain.sh:160),
# with the libs sourced and log/chain_end/die stubbed. No suite, no systemd. Usage: bash probes.sh <tree>
# Each probe: a done job whose Phase plan holds a readable done row naming PR #8 (green record) plus the
# probe's lines, most naming PR #7 (red record). exit 0 = done let through; 9/10 = refused.
set -uo pipefail
W="${1:?tree}"
T="$(mktemp -d /tmp/p3r4-probe.XXXXXX)"; echo "tmp: $T"
H8=8888888888888888888888888888888888888888; H7=7777777777777777777777777777777777777777
mkdir -p "$T/gh"; export FAKE_GH="$T/gh"; echo "$H8" > "$T/gh/pr-8-head"; echo "$H7" > "$T/gh/pr-7-head"
PATH="$W/tests/fakes:$PATH"
mk() { # <name> <lines...> -> job dir with checkpoint
  local j="$T/$1"; shift; mkdir -p "$j/gate-logs"
  printf '%s\n' "# Checkpoint: p" '' 'status: done' '' '## Next action' 'x' '' "$@" '' '## Completed phases' '- x' > "$j/checkpoint.md"
  jq -n --arg h "$H8" '{pr: 8, head_sha: $h, verdict: "success", runs: []}' > "$j/gate-logs/ci-pr-8.json"
  jq -n --arg h "$H7" '{pr: 7, head_sha: $h, verdict: "failure", runs: []}' > "$j/gate-logs/ci-pr-7.json"
  echo "$j"
}
run() { # <name> <expect: pass|refuse> <lines...>
  local n="$1" want="$2"; shift 2; local j; j="$(mk "$n" "$@")"
  local out rc
  out="$( (JOB="$j" WORKDIR="$T" TOP=
     log() { echo "LOG: $*"; }; chain_end() { echo "END $1: $2"; exit "$1"; }; die() { echo "DIE: $*"; exit 1; }
     # shellcheck source=/dev/null
     source "$W/lib/checkpoint.sh"; source "$W/lib/receipt.sh"; source "$W/lib/ci.sh"
     receipt_all_done; ci_check; echo "END 0: job done") 2>&1)"; rc=$?
  local got=pass; [ "$rc" -eq 0 ] || got=refuse
  local tag=OK; [ "$got" = "$want" ] || tag=UNEXPECTED
  printf 'PROBE %-10s %-28s exit %-2s want %-6s | %s\n' "$tag" "$n" "$rc" "$want" "$(grep -E '^(END|DIE)' <<< "$out" | tail -1 | cut -c1-150)"
}
G='| 0 | a | b | done (abc1234) · PR #8 |'
P=('## Phase plan' '| # | Phase | Done when | Status |' '|---|---|---|---|' "$G")
R='| 1 | a | b | done (abc1234) · PR #7 |'
CMT=('<!-- Rules the runner enforces on this file (blast-off; keep this comment):' '- rule one' '- Over 150 lines the runner warns. -->')
echo "== baselines"
run base-green pass "${P[@]}"
run base-red refuse "${P[@]}" "$R"
echo "== fail-open hunt (want refuse: each hides a done row naming red PR #7)"
run html-table refuse "${P[@]}" '' '<table><tr><td>1</td><td>a</td><td>b</td><td>done (abc1234) · PR #7</td></tr></table>'
run html-table-ml refuse "${P[@]}" '' '<table>' '<tr><td>1</td><td>a</td><td>b</td><td>done (abc1234) · PR #7</td></tr>' '</table>'
run cmt-h2-then-table refuse "${P[@]}" '<!--' '## end of runner section' '-->' '| # | Phase | Done when | Status |' '|---|---|---|---|' "$R"
run fence-h2-then-table refuse "${P[@]}" '```' '## x' '```' '| # | Phase | Done when | Status |' '|---|---|---|---|' "$R"
run h2-visible-then-table refuse "${P[@]}" '## Later phases' '| # | Phase | Done when | Status |' '|---|---|---|---|' "$R"
run gfm-pipeless-cont refuse "${P[@]}" '1 a b done (abc1234) · PR #7'
run fullwidth-pipe refuse "${P[@]}" '｜ 1 ｜ a ｜ b ｜ done (abc1234) · PR #7 ｜'
run box-pipe refuse "${P[@]}" '│ 1 │ a │ b │ done (abc1234) · PR #7 │'
run blank-then-rows refuse "${P[@]}" '' "$R"
run trailing-text-pipe refuse "${P[@]}" '' 'see a | b'
run fenced-row refuse "${P[@]}" '```' "$R" '```'
run fenced-badrow refuse "${P[@]}" '```' '| P1 | a | b | done (abc1234) · PR #7 |' '```'
run crlf-file pass "${P[0]}"$'\r' "${P[1]}"$'\r' "${P[2]}"$'\r' "$G"$'\r'
run crlf-badrow refuse "${P[0]}"$'\r' "${P[1]}"$'\r' "${P[2]}"$'\r' "$G"$'\r' '| P1 | a | b | done (abc1234) · PR #7 |'$'\r'
run h3-phase-plan-2nd refuse "${P[@]}" '### phase PLAN' "$R"
run h1-phase-plan-2nd refuse "${P[@]}" '# Phase plan' "$R"
run setext-2nd refuse "${P[@]}" '' 'Phase plan' '----------' "$R"
run heading-trailing-hash refuse '## Phase plan ##' "${P[@]:1}" '## Phase Plan' "$R"
run phase-plans-heading refuse "${P[@]}" '## Phase plans (cont.)' "$R"
run sep-noleading-pipe refuse "${P[@]}" '---|---|---|---'
run key-1-space-a pass "${P[@]}" '| 1 a | a | b | done (abc1234) · PR #7 |'
run key-1paren refuse "${P[@]}" '| 1) | a | b | done (abc1234) · PR #7 |'
run status-not-last refuse "${P[@]}" '| 1 | a | done (abc1234) · PR #7 | b |'
run escaped-pipe refuse "${P[@]}" '| 1 | a \| x | b | done (abc1234) · PR #7 |'
run nbsp-key refuse "${P[@]}" $'|  1 | a | b | done (abc1234) · PR #7 |'
run tab-cell refuse "${P[@]}" $'|\t1 | a | b | done (abc1234) · PR #7 |'
run no-trailing-pipe refuse "${P[@]}" '| 1 | a | b | done (abc1234) · PR #7'
run done-in-header-pos refuse '## Phase plan' '| # | Phase | Done when | done (abc1234) · PR #7 |' '|---|---|---|---|' "$G"
run 2nd-sep-later refuse "${P[@]}" '|---|---|---|---|' "$R"
echo "== false-refusal hunt (want pass: lines a template-following checkpoint may hold)"
run tmpl-full pass "${P[@]}" '| 1 | a | b | done (abc1234) · no PR |' '| 2a | a | b | done (abc1234) · PR #8 · usage 5h 3% 7d 40% |' '' "${CMT[@]}"
run tmpl-aligned-sep pass '## Phase plan' '| # | Phase | Done when | Status |' '|:--|:--|:--|--:|' "$G"
run tmpl-sub-heading pass "${P[@]}" '### notes' 'all phases closed'
run tmpl-prose-noPipe pass "${P[@]}" '' 'Phase 2 was split into 2a and 2b.'
run hdr-5col pass '## Phase plan' '| # | Phase | Done when | Issue | Status |' '|---|---|---|---|---|' '| 0 | a | b | #26 | done (abc1234) · PR #8 |'
run hdr-digit refuse '## Phase plan' '| # | Phase | Done when (by 2026) | Status |' '|---|---|---|---|' "$G"
run hdr-key-cell-num refuse '## Phase plan' '| No. | Phase | Done when | Status |' '|---|---|---|---|' "$G"
run hdr-key-cell-phase refuse '## Phase plan' '| Phase | Name | Done when | Status |' '|---|---|---|---|' "$G"
run usage-unknown pass "${P[@]::3}" '| 0 | a | b | done (abc1234) · PR #8 · usage unknown |'
run status-done-date refuse "${P[@]::3}" '| 0 | a | b | done (abc1234) 2026-11-16 · PR #8 |'
run status-pr-link pass "${P[@]::3}" '| 0 | a | b | done (abc1234) · https://github.com/o/r/pull/8 |'
run status-md-link refuse "${P[@]::3}" '| 0 | a | b | done (abc1234) · [PR #8](https://github.com/o/r/pull/8) |'
run status-sha40 pass "${P[@]::3}" '| 0 | a | b | done (abcdef0123456789abcdef0123456789abcdef01) · PR #8 |'
run status-pr-draft pass "${P[@]::3}" '| 0 | a | b | done (abc1234) · PR #8 (draft) |'
run phase-plan-in-prose pass "${P[@]}" '' 'See the Phase plan above.'
run prose-line-phase-plan pass "${P[@]}" '' 'Phase plan notes: none' '---'
run nextaction-phase-plan pass '## Next action' 'Phase plan' '' "${P[@]}"
echo "== done"; echo "tmp left: $T"
