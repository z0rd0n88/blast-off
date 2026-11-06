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
# Line-anchored: the mode bullets, step 3, and the hand-over block (3-space indent) under step 7.
for s in '^- \*\*Prompt-only\*\*' '^- \*\*Run\*\*' '^3\. \*\*Confirm the Target set\*\* .*own question' \
  '^   export GH_TOKEN CLAUDE_FLAGS=' '^   blast-off start <job-dir>( |$)' '^   blast-off status <job-dir>( |$)' \
  '^   tmux -L blast-off-<name> attach -t job-<name>( |$)' '^   blast-off stop <job-dir>( |$)'; do
  grep -qE "$s" "$skill" || fail "SKILL.md has no line matching '$s'"
done
for s in "blast-off preflight <job-dir>" "\`CLAUDE_FLAGS\` is the owner's string, verbatim"; do
  grep -qF "$s" "$skill" || fail "SKILL.md does not say '$s'"
done
! grep -qE '^ +systemctl --user start' "$skill" || fail "SKILL.md hands over a systemctl line, not blast-off start"

# --- README: every subcommand, every exit code the CLI prints, the big-next-job note ---
readme="$REPO/README.md"
[[ -f $readme ]] || fail "missing README.md"
for c in run start status stop logs resume install preflight receipt ci-wait; do
  grep -qE "blast-off $c( |\`|$)" "$readme" || fail "README does not show 'blast-off $c'"
done
codes="$(sed -n '/^# Exit:/,/^set -/p' "$REPO/bin/blast-off" | grep -oE '(^#|Exit:|·) +[0-9]+ ' | grep -oE '[0-9]+')"
[[ $(wc -w <<<"$codes") -eq 10 ]] || fail "bin/blast-off header lists $(wc -w <<<"$codes") exit codes, expected 10: $codes"
for e in $codes; do
  grep -qE "^\| *$e *\|" "$readme" || fail "README exit-code table has no row for $e"
done
grep -q 'big-next-job' "$readme" || fail "README does not say how big-next-job can call blast-off"

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
