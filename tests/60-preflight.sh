#!/usr/bin/env bash
# 60-preflight: `blast-off preflight <job-dir> [workdir]` prints, one `name: value` line each, what a
# launch would use and what stands against it (F2, F9, F10, K8): flags after the Jev pick, model and
# effort, the pick and its source, cap, timeout, account, current usage, usage estimate, slice
# (D1-7), scope stop timeout (Q2), open PRs on the brief's target set, behind-base count. It writes
# nothing. Exit 1, every line still printed, when the estimate is over what is left of the seven_day
# window or a launch would refuse (CLAUDE_FLAGS empty); no estimate or no usage record never refuses.
source "$REPO/tests/lib.sh"
use_fakes
unset JOB_CHILD_TIMEOUT JOB_CAP_FACTOR JOB_MAX_CHILDREN JOB_BASE JOB_JEV BLAST_OFF_ESTIMATE_FROM
export CLAUDE_FLAGS="--model fake --effort low --foo bar" OPENROUTER_API_KEY=sk-or-dummy GH_TOKEN=dummy-not-a-token
export FAKE_JEV="$PWD/jev" FAKE_GH="$PWD/gh" BLAST_OFF_STATE_DIR="$PWD/state"
mkdir -p "$FAKE_JEV" "$FAKE_GH" "$BLAST_OFF_STATE_DIR"; echo deep > "$FAKE_JEV/answer"
bo="$REPO/bin/blast-off"
g() { git -c user.name=t -c user.email=t@t "$@"; }
has() { grep -qE -- "$1" "$2" || fail "no line /$1/ in $2: $(cat "$2")"; }

new_job pf noop
w="$(dirname "$JOB")"
cat > "$JOB/brief.md" <<'EOF'
# brief
- **Target set** (the only tracked files this job may change): `lib/`, `README.md`,
  `docs/*.md`.
- **May widen to**: `other/`.
EOF
printf '\n## Phase plan\n| # | Phase | Done when | Status |\n|---|---|---|---|\n%s\n## Decisions\n' \
  $'| 1 | Spec | spec | done (abc1234) · usage 5h 3% 7d 20% |\n| 2 | Parser | parses | pending |\n| 3 | Docs | README | pending |' >> "$JOB/checkpoint.md"
# a previous job's rows: 7d 10 -> 30 -> 50, 20% a phase; a reset between rows (negative step) is skipped
prior="$PWD/prior-checkpoint.md"
printf '## Phase plan\n| # | Phase | Done when | Status |\n|---|---|---|---|\n%s\n' \
  $'| 0 | a | x | done · usage 5h 1% 7d 10% |\n| 1 | b | x | done · usage 5h 1% 7d 30% |\n| 2 | c | x | done · usage 5h 1% 7d 50% |\n| 3 | d | x | done · usage 5h 1% 7d 4% |\n| 4 | e | x | done · usage unknown |' > "$prior"
# the workdir is a clone one commit behind origin/main
g init -q --bare -b main origin.git
g -C "$w" init -q -b main && g -C "$w" commit -q --allow-empty -m one && g -C "$w" remote add origin "$PWD/origin.git" && g -C "$w" push -q origin main
g clone -q origin.git other && g -C other commit -q --allow-empty -m two && g -C other push -q origin main
# usage: an older record over the line, the newest at 7d 50% with its reset three days ahead
now=$(date +%s)
echo '{"seven_day":{"used_percentage":99,"resets_at":'$((now+3600))'}}' > "$BLAST_OFF_STATE_DIR/usage-limits-s1.json"
touch -d '-1 hour' "$BLAST_OFF_STATE_DIR/usage-limits-s1.json"
echo '{"five_hour":{"used_percentage":12.7,"resets_at":'$((now+600))'},"seven_day":{"used_percentage":50,"resets_at":'$((now+259200))'}}' > "$BLAST_OFF_STATE_DIR/usage-limits-s2.json"
cat > "$FAKE_GH/prs.json" <<'EOF'
[{"number":11,"title":"touches lib","headRefName":"feat/a","files":[{"path":"lib/x.sh"},{"path":"zz.txt"}]},
 {"number":12,"title":"elsewhere","headRefName":"feat/b","files":[{"path":"other/y.sh"}]},
 {"number":13,"title":"docs","headRefName":"feat/c","files":[{"path":"docs/a.md"}]},
 {"number":14,"title":"near miss","headRefName":"feat/d","files":[{"path":"README.md.bak"},{"path":"libx/z"}]}]
EOF
before="$(ls -A "$JOB" | tr '\n' ' ')"

# --- everything printed, nothing written ---
rc=0; BLAST_OFF_ESTIMATE_FROM="$prior" "$bo" preflight "$JOB" > p1.out 2>&1 || rc=$?
[ "$rc" -eq 0 ] || fail "preflight exit $rc: $(cat p1.out)"
has '^flags: --model opus --effort xhigh --foo bar$' p1.out
has '^model: opus · effort: xhigh$' p1.out
has '^level: phase 2: deep \(jev, confidence 0\.87\)$' p1.out
has '^cap: 9 \(soft: 3 Phase plan rows x JOB_CAP_FACTOR 3\)$' p1.out
has '^timeout: 7200 s per child$' p1.out
has '^account: fake@example\.com \(max, Fake Org\)$' p1.out
has '^GH_TOKEN: set$' p1.out
has '^usage: 5h 12% 7d 50% \(usage-limits-s2\.json, [0-9]+ s old\)$' p1.out
has "^estimate: 40% of the seven_day window for 2 open phase rows \\(20% a phase from $prior\\); 50% left\$" p1.out
has '^slice: blast-off\.slice (loaded from /|not installed)' p1.out
has '^scope stop timeout: [0-9]' p1.out
has '^open PRs on the target set: 2$' p1.out
has '^  #11 feat/a: touches lib \(lib/x\.sh\)$' p1.out
has '^  #13 feat/c: docs \(docs/a\.md\)$' p1.out
grep -qE '#12|#14' p1.out && fail "a PR outside the target set listed: $(cat p1.out)"
has '^behind: 1 \(git rev-list --count HEAD\.\.origin/main\)$' p1.out
has '^preflight: ok$' p1.out
[ "$(ls -A "$JOB" | tr '\n' ' ')" = "$before" ] || fail "preflight wrote into the job dir: $(ls -A "$JOB")"
[ "$(wc -l < "$FAKE_JEV/calls")" -eq 1 ] || fail "want one jev call: $(cat "$FAKE_JEV/calls")"

# --- an estimate over what is left of the seven_day window refuses ---
echo '{"seven_day":{"used_percentage":70,"resets_at":'$((now+259200))'}}' > "$BLAST_OFF_STATE_DIR/usage-limits-s3.json"
rc=0; BLAST_OFF_ESTIMATE_FROM="$prior" "$bo" preflight "$JOB" > p2.out 2>&1 || rc=$?
[ "$rc" -eq 1 ] || fail "estimate over the window left: exit $rc, want 1: $(cat p2.out)"
has '^estimate: 40% .*; 30% left; over it: refused$' p2.out
has '^preflight: refused: estimate 40% over 30% left$' p2.out
has '^behind: ' p2.out  # every line still printed

# a seven_day window whose reset is past has refilled: all of it is left
echo '{"seven_day":{"used_percentage":70,"resets_at":'$((now-60))'}}' > "$BLAST_OFF_STATE_DIR/usage-limits-s3.json"
rc=0; BLAST_OFF_ESTIMATE_FROM="$prior" "$bo" preflight "$JOB" > p3.out 2>&1 || rc=$?
[ "$rc" -eq 0 ] || fail "reset passed: exit $rc: $(cat p3.out)"
has '; 100% left$' p3.out

# --- no estimate source, no usage record: printed, never refused ---
mkdir -p empty-state
rc=0; BLAST_OFF_STATE_DIR="$PWD/empty-state" "$bo" preflight "$JOB" > p4.out 2>&1 || rc=$?
[ "$rc" -eq 0 ] || fail "no record: exit $rc: $(cat p4.out)"
has "^usage: no usage records in $PWD/empty-state: usage pause is off until ~/\\.claude/hooks/usage-limit-tee\\.sh writes one$" p4.out
has '^estimate: no estimate \(fewer than two 7d figures in the Phase plan rows of ' p4.out

# --- static fallback; a launch that would refuse; no target set in the brief ---
printf '# brief, no target set\n' > "$JOB/brief.md"
rc=0; env -u OPENROUTER_API_KEY -u GH_TOKEN CLAUDE_FLAGS= "$bo" preflight "$JOB" > p5.out 2>&1 || rc=$?
[ "$rc" -eq 1 ] || fail "CLAUDE_FLAGS empty: exit $rc, want 1: $(cat p5.out)"
has '^level: phase 2: static CLAUDE_FLAGS \(no OPENROUTER_API_KEY in the runner environment\)$' p5.out
has '^GH_TOKEN: unset \(start refuses\)$' p5.out
has '^preflight: refused: CLAUDE_FLAGS is unset or empty$' p5.out
has '^open PRs on the target set: 4 \(no Target set bullet in brief\.md; every open PR\)$' p5.out
