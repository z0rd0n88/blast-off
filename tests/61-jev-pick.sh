#!/usr/bin/env bash
# 61-jev-pick: before a child, the runner asks Jev one choice question per open Phase plan row (D9):
# the first open row's text on stdin, OpenRouter only (TYPESAFE_API_KEY and JEV_BASE_URL dropped, a
# key that is not sk-or-* never sent). The level's --model/--effort replace CLAUDE_FLAGS's own, other
# flags kept; every child of that row gets the same pick; the pick goes to run.log and decisions.tsv.
# Fallback to CLAUDE_FLAGS unchanged, logged with its reason: JOB_JEV=0, no OpenRouter key, jev not on
# PATH, jev failing, an answer that is not a level, no open row.
source "$REPO/tests/lib.sh"
use_fakes
unset JOB_JEV
export CLAUDE_FLAGS="--model fake --effort low --foo bar" JOB_CHILD_TIMEOUT=30 FAKE_JEV
bo="$REPO/bin/blast-off"
plan() { printf '\n## Phase plan\n| # | Phase | Done when | Status |\n|---|---|---|---|\n%s\n## Decisions\n' "$1" >> "$JOB/checkpoint.md"; }
flags() { sed -n 's/^flags=//p' "$JOB/fake-marker" | sed -n "${1}p"; }
static="--model fake --effort low --foo bar"

# --- a pick per open row, OpenRouter only ---
new_job pick step close close close
plan $'| 1 | Parser | parses the secret-phase-text | pending |\n| 2 | Docs | README | pending |'
FAKE_JEV="$PWD/jev-pick"; mkdir -p "$FAKE_JEV"; echo light > "$FAKE_JEV/answer"
rc=0; OPENROUTER_API_KEY=sk-or-dummy TYPESAFE_API_KEY=ts-dummy JEV_BASE_URL=https://api.typesafe.ai \
  "$bo" run "$JOB" > pick.out 2>&1 || rc=$?
[ "$rc" -eq 0 ] || fail "pick run exit $rc: $(cat pick.out)"
[ "$(wc -l < "$FAKE_JEV/calls")" -eq 2 ] || fail "want one jev call per open row (2): $(cat "$FAKE_JEV/calls")"
grep -qv 'typesafe= base= key=sk-or-$' "$FAKE_JEV/calls" && fail "jev saw TypeSafe route or no OpenRouter key: $(cat "$FAKE_JEV/calls")"
grep -q 'secret-phase-text' "$FAKE_JEV/state-1" || fail "row 1 text not in jev's state: $(cat "$FAKE_JEV/state-1")"
grep -q '| 2 | Docs |' "$FAKE_JEV/state-2" || fail "row 2 text not in the second call's state: $(cat "$FAKE_JEV/state-2")"
grep -q 'secret-phase-text' "$FAKE_JEV/calls" && fail "row text on jev's argv"
for i in 1 2 3; do [ "$(flags $i)" = "--model sonnet --effort medium --foo bar" ] || fail "child $i flags '$(flags $i)'"; done
[ "$(flags 4)" = "$static" ] || fail "child 4 (no open row) flags '$(flags 4)', want static"
grep -q 'model level for phase 1: light (jev, confidence 0.87): --model sonnet --effort medium --foo bar' "$JOB/run.log" || fail "pick not in run.log: $(cat "$JOB/run.log")"
grep -q 'model level for phase 2: light (jev' "$JOB/run.log" || fail "phase 2 pick not in run.log"
grep -q 'no open Phase plan row; static CLAUDE_FLAGS' "$JOB/run.log" || fail "no-row fallback not logged"
[ "$(grep -c $'\tphase-1\tmodel level light' "$JOB/decisions.tsv")" -eq 1 ] || fail "phase 1 pick not once in decisions.tsv: $(cat "$JOB/decisions.tsv" 2>&1)"
awk -F'\t' 'NF != 6 { exit 1 }' "$JOB/decisions.tsv" || fail "decisions.tsv rows not 6 tab fields: $(cat -A "$JOB/decisions.tsv")"

# --- fallbacks: CLAUDE_FLAGS unchanged, reason logged ---
fallback() { # <suffix> <want reason> <want jev calls> [env...]
  local s="$1" why="$2" calls="$3"; shift 3
  new_job "$s" close; plan '| 1 | Only | x | pending |'
  FAKE_JEV="$PWD/jev-$s"; mkdir -p "$FAKE_JEV"; [ ! -e "$PWD/jev-setup-$s" ] || cp -r "$PWD/jev-setup-$s/." "$FAKE_JEV/"
  rc=0; env "$@" "$bo" run "$JOB" > "$s.out" 2>&1 || rc=$?
  [ "$rc" -eq 0 ] || fail "$s run exit $rc: $(cat "$s.out")"
  [ "$(flags 1)" = "$static" ] || fail "$s: child flags '$(flags 1)', want static"
  grep -qF "model level for phase 1: static CLAUDE_FLAGS ($why)" "$JOB/run.log" || fail "$s: reason '$why' not logged: $(grep 'model level' "$JOB/run.log")"
  [ "$(cat "$FAKE_JEV/calls" 2>/dev/null | wc -l)" -eq "$calls" ] || fail "$s: jev calls $(cat "$FAKE_JEV/calls" 2>/dev/null | wc -l), want $calls"
  grep -q $'\tphase-1\tmodel level static' "$JOB/decisions.tsv" || fail "$s: fallback not in decisions.tsv"
}
fallback off 'JOB_JEV=0' 0 OPENROUTER_API_KEY=sk-or-dummy JOB_JEV=0
fallback nokey 'no OPENROUTER_API_KEY in the runner environment' 0
fallback tskey 'OPENROUTER_API_KEY is not an OpenRouter sk-or- key; Jev runs only through OpenRouter' 0 OPENROUTER_API_KEY=tsk-dummy
mkdir -p jev-setup-err; touch jev-setup-err/fail
fallback err 'jev failed: {"error":"fake failure"}' 1 OPENROUTER_API_KEY=sk-or-dummy
mkdir -p jev-setup-other; echo other > jev-setup-other/answer
fallback other "jev answered 'other', not a level" 1 OPENROUTER_API_KEY=sk-or-dummy
# jev not on PATH: every PATH dir holding a jev dropped, fake claude kept through its own dir
mkdir -p nojev; ln -s "$REPO/tests/fakes/claude" nojev/claude
p="$PWD/nojev"; IFS=: read -ra dirs <<< "$PATH"; for d in "${dirs[@]}"; do [ -x "$d/jev" ] || p+=":$d"; done
fallback nojev 'jev not on PATH' 0 OPENROUTER_API_KEY=sk-or-dummy PATH="$p"
