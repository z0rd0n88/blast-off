#!/usr/bin/env bash
# 51-templates: templates/checkpoint.md parses with lib/checkpoint.sh as a fresh job (status running,
# every Phase plan row open with a digit key, nothing the runner would refuse), stays far under the
# 150-line warning, and carries the rules the runner enforces on what children write into it.
source "$REPO/tests/lib.sh"
JOB="$PWD/job"; mkdir -p "$JOB"
log() { echo "$*" >> "$JOB/run.log"; }
# shellcheck source=../lib/checkpoint.sh
source "$REPO/lib/checkpoint.sh"
has() { grep -qF -- "$2" "$1" || fail "$(basename "$1") lacks: $2"; }

t="$REPO/templates/checkpoint.md"
[ -s "$t" ] || fail "missing templates/checkpoint.md"
cp "$t" "$JOB/checkpoint.md"
[ "$(cp_status)" = running ] || fail "template status: '$(cp_status)', want running"
p="$(cp_phases)"
[ "$p" -ge 3 ] || fail "template Phase plan rows: $p, want 3 or more"
[ -z "$(cp_done_rows)" ] || fail "template has done rows (exit 9 on an unedited job): $(cp_done_rows)"
[ "$(cp_open_rows | wc -l)" -eq "$p" ] || fail "open rows $(cp_open_rows | wc -l) of $p"
cp_open_rows | while read -r k; do [[ $k =~ ^[0-9] ]] || fail "row key '$k' does not start with a digit"; done
[ "$(wc -l < "$t")" -le 100 ] || fail "template is $(wc -l < "$t") lines; it must leave a job room under 150"
cp_size_warn; [ ! -s "$JOB/run.log" ] || fail "template warned: $(cat "$JOB/run.log")"
# a Status cell written the way the template says is read back: done row, its sha, no other hex word first
sed -i '0,/^\(| 0 |.*| \)pending |$/s//\1done (abc1234) · PR #7 |/' "$JOB/checkpoint.md"
[ "$(cp_done_rows)" = 0 ] || fail "done row as the template writes it not read: $(grep '^| 0 ' "$JOB/checkpoint.md")"
[ "$(cp_row_sha 0)" = abc1234 ] || fail "row sha: '$(cp_row_sha 0)', want abc1234"
for s in 'done (<sha>)' 'PR #<n>' 'replace' '· usage' 'paused-' 'backticks' 'phases/phase-<n>.md' \
         'gate-logs/phase-<n>' 'Hand-backs' 'children <a>-<b>'; do
  has "$t" "$s"
done

# templates/brief.md carries the fixed child protocol (spec §1 K1-K10, F1-F11; phase 5 done-when)
b="$REPO/templates/brief.md"
[ -s "$b" ] || fail "missing templates/brief.md"
grep -q '^## .*Child protocol' "$b" || fail "brief has no Child protocol section (the runner's prompt names it)"
for s in \
  'wiring file' 'test dir' 'build file' 'every file a gate or CI check reads' 'May widen to' \
  'confirmed as its own question' \
  'step boundary' 'never on an estimate' \
  'at most 3 rounds' 'LOW findings are recorded, never fixed in the loop' 'at most 3 reviewers' \
  'lenses change every round' 'nothing above LOW closes the phase' 'doubt pass' 'mutation probe' \
  'no Edit, no Write, no process-starting Bash, no servers, no ports; read and grep only' \
  'Never end a turn with a background task' 'even when a harness notice' 'EXIT, TERM and INT' \
  'gh pr list' 'rev-list --count HEAD..origin/' 'merge the base in before the gate' \
  'Per-commit LLM hooks and plugins' 'Codex lanes' \
  'running, done or blocked' 'paused-limit' 'exit 75' 'usage-checkpoint' \
  'gate-logs/phase-<n>.log' 'blast-off receipt <job-dir> <n>' 'blast-off ci-wait <job-dir> <pr>' \
  'replace, not append' 'PR #<n>' 'backticks' 'Unrun is not passed'; do
  has "$b" "$s"
done
! grep -qi 'about a third' "$b" || fail "brief hands back on an estimate ('about a third'); F3 wants step boundaries"
echo ok
