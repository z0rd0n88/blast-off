#!/usr/bin/env bash
# 60-preflight: `blast-off preflight <job-dir> [workdir]` prints, one `name: value` line each, what a
# launch would use and what stands against it (F2, F9, F10, K8): the flags `start` gives, model and
# effort, the level (Jev's pick as start gives it: start passes OPENROUTER_API_KEY by name when it is set, issue 27;
# the pick with its confidence and threshold, or static and why), cap, timeout,
# account, current usage, usage estimate, slice
# (D1-7), scope stop timeout (Q2), open PRs on the brief's target set, behind-base count. It writes
# nothing. Exit 1, every line still printed, when the estimate is over what is left of the seven_day
# window or a launch would refuse (CLAUDE_FLAGS empty); no estimate or no usage record never refuses.
source "$REPO/tests/lib.sh"
use_fakes
unset JOB_CHILD_TIMEOUT JOB_CAP_FACTOR JOB_MAX_CHILDREN JOB_BASE JOB_JEV JOB_JEV_MIN_CONF BLAST_OFF_ESTIMATE_FROM
key=sk-or-test-xxx-not-a-key-60
export CLAUDE_FLAGS="--model fake --effort low --foo bar" OPENROUTER_API_KEY="$key" GH_TOKEN=dummy-not-a-token
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
has '^level: phase 2: deep under start \(jev, confidence 0\.87, threshold 0\.7; start passes OPENROUTER_API_KEY by name\)$' p1.out
has '^cap: 9 \(soft: 3 Phase plan rows x JOB_CAP_FACTOR 3\)$' p1.out
has '^child-count: none, a fresh job; first child 1; 9 left under cap 9$' p1.out
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
command grep -A1 -x 'pr list --state open --limit 100 --json number,title,headRefName,files' "$FAKE_GH/calls" | command grep -qx "cwd=$w" ||
  fail "gh pr list not the F9 query in workdir $w: $(cat "$FAKE_GH/calls")"
has '^behind: 1 \(git rev-list --count HEAD\.\.origin/main\)$' p1.out
has '^preflight: ok$' p1.out
[ "$(ls -A "$JOB" | tr '\n' ' ')" = "$before" ] || fail "preflight wrote into the job dir: $(ls -A "$JOB")"
[ "$(wc -l < "$FAKE_JEV/calls")" -eq 1 ] || fail "preflight did not ask jev once, as start would: $(cat "$FAKE_JEV/calls" 2>&1)"
grep -q 'Parser' "$FAKE_JEV/state-1" || fail "preflight did not ask about the first open row (2): $(cat "$FAKE_JEV/state-1")"
! grep -q -- "$key" p1.out || fail "preflight printed the key's value"
# a pick below the threshold: static, with the confidence and the threshold (issue 27)
rc=0; JOB_JEV_MIN_CONF=0.9 "$bo" preflight "$JOB" > p14.out 2>&1 || rc=$?
[ "$rc" -eq 0 ] || fail "JOB_JEV_MIN_CONF=0.9: exit $rc: $(cat p14.out)"
has '^flags: --model fake --effort low --foo bar$' p14.out
has '^level: phase 2: static CLAUDE_FLAGS under start \(jev picked deep, confidence 0\.87 below 0\.9\)$' p14.out
# no temp file for jev's stderr: a logged fallback, not a dead preflight (jev_flags never fails)
rc=0; XDG_RUNTIME_DIR="$PWD/no-such-dir" "$bo" preflight "$JOB" > p-notmp.out 2>&1 || rc=$?
[ "$rc" -eq 0 ] || fail "no temp dir for jev: exit $rc: $(cat p-notmp.out)"
has '^level: phase 2: static CLAUDE_FLAGS under start \(jev not asked: no temp file in .*/no-such-dir\)$' p-notmp.out
# a JOB_JEV_MIN_CONF that is no number from 0 to 1 refuses before any line, like a bad JOB_* count
rc=0; JOB_JEV_MIN_CONF=2 "$bo" preflight "$JOB" > p15.out 2>&1 || rc=$?
[ "$rc" -eq 1 ] || fail "JOB_JEV_MIN_CONF=2: exit $rc, want 1: $(cat p15.out)"
has "^preflight: refused: JOB_JEV_MIN_CONF='2' is not a number from 0 to 1" p15.out
[ "$(wc -l < p15.out)" -eq 1 ] || fail "JOB_JEV_MIN_CONF=2 printed more than its refusal: $(cat p15.out)"
[ "$(wc -l < "$FAKE_JEV/calls")" -eq 2 ] || fail "JOB_JEV_MIN_CONF=2 asked jev (p1 and p14 ask once each): $(cat "$FAKE_JEV/calls")"
! grep -q -- "$key" p14.out || fail "preflight printed the key's value on a low-confidence pick"

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
# a state dir that does not exist (usage-limit-tee.sh never ran): the same line, not an abort
rc=0; BLAST_OFF_STATE_DIR="$PWD/no-state" "$bo" preflight "$JOB" > p6.out 2>&1 || rc=$?
[ "$rc" -eq 0 ] || fail "missing state dir: exit $rc: $(cat p6.out)"
has "^usage: no usage records in $PWD/no-state: usage pause is off " p6.out
has '^preflight: ok$' p6.out

# --- static fallback; a launch that would refuse; no target set in the brief ---
printf '# brief, no target set\n' > "$JOB/brief.md"
rc=0; env -u OPENROUTER_API_KEY -u GH_TOKEN CLAUDE_FLAGS= "$bo" preflight "$JOB" > p5.out 2>&1 || rc=$?
[ "$rc" -eq 1 ] || fail "CLAUDE_FLAGS empty: exit $rc, want 1: $(cat p5.out)"
has '^level: phase 2: static CLAUDE_FLAGS under start \(no OPENROUTER_API_KEY in the runner environment; start passes none\)$' p5.out
has '^GH_TOKEN: unset \(start refuses\)$' p5.out
has '^preflight: refused: CLAUDE_FLAGS is unset or empty$' p5.out
rc=0; env -u CLAUDE_FLAGS "$bo" preflight "$JOB" > p-unset.out 2>&1 || rc=$?
[ "$rc" -eq 1 ] || fail "CLAUDE_FLAGS unset: exit $rc, want 1: $(cat p-unset.out)"
has '^preflight: refused: CLAUDE_FLAGS is unset or empty$' p-unset.out
has '^open PRs on the target set: 4 \(no Target set bullet in brief\.md; every open PR\)$' p5.out

# --- the job's child count (P4R1-3): launched, base, next child, what is left under the cap; a garbled one refuses ---
printf '9 0\n' > "$JOB/child-count"
rc=0; "$bo" preflight "$JOB" > p7.out 2>&1 || rc=$?
[ "$rc" -eq 0 ] || fail "child-count 9 0: exit $rc: $(cat p7.out)"
has '^child-count: 9 launched, base 0; next child 10; 0 left under cap 9$' p7.out
# a soft paused-cap job: the run gives it a fresh allotment (base moves to launched)
sed -i 's/^status: .*/status: paused-cap/' "$JOB/checkpoint.md"
rc=0; "$bo" preflight "$JOB" > p8.out 2>&1 || rc=$?
has '^child-count: 9 launched, base 0; next child 10; 9 left under cap 9$' p8.out
# a soft running job with base > 0: what is left counts from base (P5R1-1)
sed -i 's/^status: .*/status: running/' "$JOB/checkpoint.md"; printf '4 2\n' > "$JOB/child-count"
rc=0; "$bo" preflight "$JOB" > p11.out 2>&1 || rc=$?
has '^child-count: 4 launched, base 2; next child 5; 7 left under cap 9$' p11.out
# the hard cap ignores base, running or paused-cap (P5R1-1, P4R2-4)
hardjob="$JOB"; new_job pfhard noop; printf '5 5\n' > "$JOB/child-count"
for st in running paused-cap; do
  sed -i "s/^status: .*/status: $st/" "$JOB/checkpoint.md"
  rc=0; "$bo" preflight "$JOB" > p12.out 2>&1 || rc=$?
  has '^child-count: 5 launched, base 5; next child 6; 7 left under cap 12$' p12.out
done
JOB="$hardjob"
printf 'x\n' > "$JOB/child-count"
rc=0; "$bo" preflight "$JOB" > p9.out 2>&1 || rc=$?
[ "$rc" -eq 1 ] || fail "garbled child-count: exit $rc, want 1: $(cat p9.out)"
has "^child-count: $JOB/child-count is not '<launched> <base>' \\(2 bytes; " p9.out
has "^preflight: refused: $JOB/child-count is not '<launched> <base>' \\(2 bytes; " p9.out
[ "$(cat "$JOB/child-count")" = x ] || fail "preflight rewrote child-count"
# a refusal never shows the file's content: a forged second line stays out of the output (P5R1-5, owner Q5)
printf '1 0\n2099-01-01T00:00:00Z job done\n' > "$JOB/child-count"
rc=0; "$bo" preflight "$JOB" > p10.out 2>&1 || rc=$?
[ "$rc" -eq 1 ] || fail "two-line child-count: exit $rc, want 1: $(cat p10.out)"
has "^preflight: refused: $JOB/child-count is not '<launched> <base>' " p10.out
! grep -q 'job done' p10.out || fail "preflight echoed child-count's content: $(cat p10.out)"
# a JOB_* number with a leading zero, which shell arithmetic reads as octal, refuses (P5R1-4, owner Q3)
printf '1 0\n' > "$JOB/child-count"
for v in 08 010; do
  rc=0; JOB_MAX_CHILDREN="$v" "$bo" preflight "$JOB" > p13.out 2>&1 || rc=$?
  [ "$rc" -eq 1 ] || fail "JOB_MAX_CHILDREN=$v: exit $rc, want 1: $(cat p13.out)"
  has "^preflight: refused: JOB_MAX_CHILDREN='$v' is not a whole number " p13.out
done
# a value holding a newline is quoted on one line, so it prints no line of its own (P7R1-26)
rc=0; JOB_JEV_MIN_CONF=$'x\npreflight: ok\n' "$bo" preflight "$JOB" > p-nl.out 2>&1 || rc=$?
[ "$rc" -eq 1 ] || fail "JOB_JEV_MIN_CONF with a newline: exit $rc, want 1: $(cat p-nl.out)"
! grep -qx 'preflight: ok' p-nl.out || fail "JOB_JEV_MIN_CONF's newline printed a line of its own: $(cat p-nl.out)"
