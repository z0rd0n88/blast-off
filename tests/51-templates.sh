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
! grep -q '^## Decisions' "$t" || fail "checkpoint template keeps a Decisions table; F3 puts decisions in decisions.tsv, not the checkpoint"
# the template names no file a repo may hold: an uncommitted Makefile or decisions.tsv must not count as
# named in every job built from it (P5R1-1)
for f in Makefile decisions.tsv; do ! cp_names "$f" || fail "template names $f; an uncommitted $f skips exit 7"; done
# a Status cell written the way the template says is read back: done row, its sha, no other hex word first
sed -i '0,/^\(| 0 |.*| \)pending |$/s//\1done (abc1234) · PR #7 |/' "$JOB/checkpoint.md"
[ "$(cp_done_rows)" = 0 ] || fail "done row as the template writes it not read: $(grep '^| 0 ' "$JOB/checkpoint.md")"
[ "$(cp_row_sha 0)" = abc1234 ] || fail "row sha: '$(cp_row_sha 0)', want abc1234"
for s in 'done (<sha>)' 'PR #<n>' 'replace' '· usage' 'backticks' 'phases/phase-<n>.md' \
         'gate-logs/phase-<n>' 'Hand-backs' 'children <a>-<b>'; do
  has "$t" "$s"
done

# the brief's bare `blast-off receipt` and `ci-wait` resolve in a child: the job's tmux server, whose
# environment every child inherits, has this checkout's bin/ first on PATH (P5Q6)
# shellcheck source=../lib/child.sh
source "$REPO/lib/child.sh"
# shellcheck disable=SC2034  # SESSION, WORKDIR, BLAST_OFF_HOME: read by child_server
UNIT="$TEST_ID-path" SESSION="$TEST_ID-path" WORKDIR="$PWD" BLAST_OFF_HOME="$REPO"; SUFFIXES+=(path)  # cleanup removes its socket
child_server
cpath="$(tmux -L "$UNIT" show-environment -g PATH || true)"; tmux -L "$UNIT" kill-server
[ "$( PATH="${cpath#PATH=}"; command -v blast-off || true )" = "$REPO/bin/blast-off" ] || fail "blast-off not on a child's PATH: $cpath"

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
  'merge the base in before the gate' 'Per-commit LLM hooks and plugins' 'usage-checkpoint' \
  'gate-logs/phase-<n>.log' 'blast-off receipt <job-dir> <n>' 'blast-off ci-wait <job-dir> <pr>' \
  'replace, not append' 'PR #<n>' 'Unrun is not passed'; do
  has "$b" "$s"
done
has "$b" '| D2 | Codex lanes | off'

# Rule sentences, not keywords, so a rule turned around fails (P5R1-9). flat: the text on one line,
# spaces squeezed, so a sentence matches however it wraps.
flat() { tr '\n' ' ' | tr -s ' '; }
C="$(flat < "$t")"
for s in 'Children write only running, done or blocked there.' "paused-cap and paused-limit are the runner's" \
         '-uall' "means this job's own PR" '<job-dir>/decisions.tsv'; do
  [[ $C == *"$s"* ]] || fail "checkpoint.md lacks: $s"
done
S9="$(sed -n '/^## 9\. Child protocol/,$p' "$b" | flat)"
for s in 'gh pr list' 'rev-list --count HEAD..origin/' 'git fetch origin' 'git status --porcelain -uall' \
         'Write only running, done or blocked in the `status:` line' \
         '`paused-cap` and `paused-limit` belong to the runner' 'leave the status as it is' 'Do not try to exit 75'; do
  [[ $S9 == *"$s"* ]] || fail "brief section 9 lacks: $s"
done
# the close order the runner checks: commit, gate, receipt, PR, ci-wait, then the done cell
S4="${S9#*"**Close the phase**"}"; [ "$S4" != "$S9" ] || fail "brief section 9 has no Close the phase step"
last=-1
for s in 'commit; run the gate' 'blast-off receipt <job-dir> <n>' 'draft PR' 'blast-off ci-wait <job-dir> <pr>' 'done (<sha>)'; do
  [[ $S4 == *"$s"* ]] || fail "Close the phase lacks: $s"
  x="${S4%%"$s"*}"; [ "${#x}" -gt "$last" ] || fail "Close the phase: '$s' comes before the step it must follow"
  last="${#x}"
done
# the cut-off gate re-run line, filled with a shell-list gate holding quotes and a job dir with a space,
# saves the gate's whole output to the log, ending in the verdict the receipt reads (P5R2-1)
# shellcheck source=../lib/receipt.sh
source "$REPO/lib/receipt.sh"
rr="${S9#*'Run a cut-off gate again as `'}"; [ "$rr" != "$S9" ] || fail "brief section 9 has no cut-off gate re-run line"
rr="${rr%%'`'*}"; gd="$PWD/re run"; mkdir -p "$gd/gate-logs"
gc="echo out; echo err >&2 && echo 'GATE: PASS' || echo 'GATE: FAIL'"; rr="${rr//"<gate command>"/"$gc"}"
rr="${rr//"<job-dir>"/"$gd"}"; pid="$(eval "${rr//"<n>"/9}")"; gl="$gd/gate-logs/phase-9.log"
timeout 20 tail --pid="$pid" -f /dev/null || fail "re-run gate line gave no pid to wait on: $pid"
[ "$(receipt_verdict "$gl")" = 'GATE: PASS' ] && grep -qx out "$gl" && grep -qx err "$gl" ||
  fail "re-run gate line lost the gate's output or verdict: $(cat "$gl" 2>&1)"
[ "$(grep -c 'git fetch origin <base>' "$b")" -ge 3 ] || fail "brief fetches origin/<base> on fewer than 3 lines (launch count, phase-start count, merge; F9)"
! grep -qi 'about a third' "$b" || fail "brief hands back on an estimate ('about a third'); F3 wants step boundaries"
has "$b" '`decisions.tsv`, wherever named, are in the job dir'
has "$t" '## Pointers (in the job dir, beside this file)'
echo ok
