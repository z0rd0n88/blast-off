#!/usr/bin/env bash
# 70-docs: the skill, README and deviations table stay in step with the CLI and the guide (phase 7).
# shellcheck source=tests/lib.sh
source "$REPO/tests/lib.sh"

# --- SKILL.md: frontmatter, description under the 1024-char ceiling, the hand-over commands ---
skill="$REPO/skills/blast-off/SKILL.md"
[[ -f $skill ]] || fail "missing skills/blast-off/SKILL.md"
front="$(awk 'NR==1 && /^---$/ {f=1; next} f && /^---$/ {c=1; exit} f {print} END {exit !c}' "$skill")" \
  || fail "SKILL.md frontmatter does not open and close with ---"
grep -qx 'name: blast-off' <<<"$front" || fail "SKILL.md frontmatter name is not blast-off"
desc="$(sed -n 's/^description: //p' <<<"$front")"
[[ $desc =~ ^[A-Za-z] ]] || fail "SKILL.md description is not one plain line: $desc"
(( ${#desc} <= 1024 )) || fail "SKILL.md description is ${#desc} chars, over 1024"
# Line-anchored: the mode bullets, step 3, and the hand-over blocks (3-space indent) under step 7.
for s in '^- \*\*Prompt-only\*\*' '^- \*\*Run\*\*' '^3\. \*\*Confirm the Target set\*\* .*own question' \
  '^   export GH_TOKEN CLAUDE_FLAGS=' '^   blast-off start <job-dir>( |$)' '^   blast-off wait <job-dir>( |$)' '^   blast-off status <job-dir>( |$)' \
  '^   tmux -L blast-off-<name> attach -t job-<name>( |$)' '^   blast-off stop <job-dir>( |$)'; do
  grep -qE "$s" "$skill" || fail "SKILL.md has no line matching '$s'"
done
for s in "blast-off preflight <job-dir>" "\`CLAUDE_FLAGS\` is the owner's string, verbatim" "Type it bare, \`blast-off start <job-dir>\`" \
  "! CLAUDE_FLAGS='<owner flags>' blast-off start <job-dir>" "step 7's export and start lines in a terminal"; do
  grep -qF "$s" "$skill" || fail "SKILL.md does not say '$s'"
done
# The fenced block holding the start line holds no stop line: pasted whole, it would stop the job it started.
startblock="$(awk '/^ *```/ {if (f && b ~ /blast-off start <job-dir>/) print b; f = !f; b = ""; next} f {b = b $0 "\n"}' "$skill")"
[[ -n $startblock ]] || fail "SKILL.md has no fenced block holding 'blast-off start <job-dir>'"
! grep -q 'blast-off stop' <<<"$startblock" || fail "SKILL.md's start block also runs blast-off stop: $startblock"
! grep -qE '^ +systemctl --user start' "$skill" || fail "SKILL.md hands over a systemctl line, not blast-off start"

# --- README: every subcommand, every exit code the CLI prints, the big-next-job note ---
readme="$REPO/README.md"
[[ -f $readme ]] || fail "missing README.md"
for c in run start status stop logs resume wait install preflight receipt ci-wait; do
  grep -qE "blast-off $c( |\`|$)" "$readme" || fail "README does not show 'blast-off $c'"
done
codes="$(sed -n '/^# Exit:/,/^set -/p' "$REPO/bin/blast-off" | grep -oE '(^#|Exit:|·) +[0-9]+ ' | grep -oE '[0-9]+')"
[[ $(wc -w <<<"$codes") -eq 10 ]] || fail "bin/blast-off header lists $(wc -w <<<"$codes") exit codes, expected 10: $codes"
for e in $codes; do
  grep -qE "^\| *$e *\|" "$readme" || fail "README exit-code table has no row for $e"
done
grep -q 'big-next-job' "$readme" || fail "README does not say how big-next-job can call blast-off"
for s in "types the bare line" "! CLAUDE_FLAGS='<flags>' blast-off start <job-dir>"; do
  grep -qF "$s" "$readme" || fail "README does not say '$s'"
done
# P3R3-7: the done rules as the owner and the skill read them (flat: however the lines wrap)
R="$(tr '\n' ' ' < "$readme" | tr -s ' ')" K="$(tr '\n' ' ' < "$skill" | tr -s ' ')"
for s in "refuses \`status: done\` (exit 10) while a done row's Status cell says neither \`PR #<pr>\` nor \`no PR\`" \
  'or the file has a second Phase plan heading' 'PRs are read only from those cells, never from prose' \
  '`done (<sha>) · PR #<pr>`' '`done (<sha>) · no PR`' 'row keys (0, 1, 2a)'; do  # P3R5-32, P3R5-22
  [[ $R == *"$s"* ]] || fail "README does not say '$s'"
done
# owner ruling 3 of phase 3: the done gate's threat model, in the spec and beside the README's exit 10
P="$(tr '\n' ' ' < "$REPO/docs/spec.md" | tr -s ' ')"
for s in 'The done gate defends against a child that is lazy or confused, not one that crafts Markdown or HTML to hide a PR from it' \
  "children run as the owner's user with bypass permissions" 'is never refused for its format and never slips the gate'; do
  [[ $R == *"$s"* ]] || fail "README does not say '$s'"
  [[ $P == *"$s"* ]] || fail "docs/spec.md does not say '$s'"
done
for s in 'a phase that opens no PR says `no PR` in brief §5 and closes its row with `no PR`' "logged \"absent, not a pass\", only where that PR's head commit has no file under" \
  'refused at `done` with no override and that `no PR` is no way out'; do
  [[ $K == *"$s"* ]] || fail "SKILL.md does not say '$s'"
done
# A '!' start line without CLAUDE_FLAGS exits 1 (lib/units.sh unit_check).
! grep -qF '! blast-off start' "$skill" "$readme" || fail "SKILL.md or README hands over '! blast-off start' with no CLAUDE_FLAGS"
# #21: the launching session starts in the target repo; the original launcher prompt is kept in docs/
s='inside the target repo (the repo the job changes)'
[[ $R == *"$s"* ]] || fail "README does not say '$s'"
[[ $K == *"$s"* ]] || fail "SKILL.md does not say '$s'"
grep -qx '# Prompt: build the standalone unattended job launcher' "$REPO/docs/2026-11-04-large-job-launcher-prompt.md" || fail "docs/2026-11-04-large-job-launcher-prompt.md does not hold the launcher prompt"
grep -qF '(docs/2026-11-04-large-job-launcher-prompt.md)' "$readme" || fail "README does not link docs/2026-11-04-large-job-launcher-prompt.md"

# --- deviations: one row per guide §5 directive, a disposition and a filled verified cell ---
# Every directive of the systemd guide's §5 template .
GUIDE_DIRECTIVES=(Description Documentation After Wants Type User Group NoNewPrivileges WorkingDirectory
  EnvironmentFile ExecStart Restart RestartSec StartLimitIntervalSec StartLimitBurst
  TimeoutStartSec TimeoutStopSec CPUQuota CPUSchedulingPolicy Nice MemoryHigh MemoryMax
  MemorySwapMax TasksMax LimitNOFILE PrivateTmp ProtectSystem ProtectHome ReadWritePaths
  StandardOutput StandardError SyslogIdentifier KillMode KillSignal FinalKillSignal WantedBy)
dev="$REPO/docs/systemd-guide-deviations.md"
[[ -f $dev ]] || fail "missing docs/systemd-guide-deviations.md"
cell='[^|]*[^ |][^|]*\|'
for d in "${GUIDE_DIRECTIVES[@]}"; do
  line="$(grep -E "^\| *\`$d=\` *\|" "$dev")" || fail "deviations table has no row for $d="
  [[ $line =~ ^\|[^|]+\|\ *(adopted|changed|dropped)\ *\|$cell$cell$ ]] \
    || fail "deviations row for $d= lacks disposition, why or verified: $line"
  verified="${line%|}"; verified="${verified##*|}"
  [[ ${verified,,} =~ ^\ *(yes|partly|n/a|not\ verified)(:|\ *$) ]] \
    || fail "deviations row for $d= verified cell is not yes, partly, n/a or not verified: $line"
done
