#!/usr/bin/env bash
# 00-harness: the gate itself reports honestly, and the phase 0 scaffold is in place.
# shellcheck source=tests/lib.sh
source "$REPO/tests/lib.sh"

# --- the harness: pass, fail, and nothing-ran each give the right verdict and exit code ---
mkdir ok bad empty
printf 'exit 0\n' > ok/01-ok.sh
printf 'exit 0\n' > bad/01-ok.sh; printf 'echo boom; exit 1\n' > bad/02-bad.sh
run_gate() { BLAST_OFF_NO_SHELLCHECK=1 "$REPO/tests/run" "$1" > "$1.out" 2>&1; }

run_gate ok || fail "passing fixture exited non-zero"
grep -qx 'GATE: PASS passed=1 failed=0 shellcheck=skipped' ok.out || fail "passing fixture verdict: $(cat ok.out)"

if run_gate bad; then fail "failing fixture exited 0"; fi
grep -qx 'GATE: FAIL passed=1 failed=1 shellcheck=skipped' bad.out || fail "failing fixture verdict: $(cat bad.out)"
grep -q '  | boom' bad.out || fail "failing scenario output not shown"

if run_gate empty; then fail "empty fixture exited 0 (unrun is not passed)"; fi
grep -q '^GATE: FAIL' empty.out || fail "empty fixture verdict: $(cat empty.out)"

# --- BLAST_OFF_TEST_KEEP: each scenario's work dir (output and cwd) is kept under it; unset, none is left ---
# TMPDIR is pinned so "removed" is observable. A scenario must not see the var: this one runs tests/run
# itself, and its fixtures would land in the outer keep dir (CI's artifact).
mkdir keepfix tmp
printf '[ -z "${BLAST_OFF_TEST_KEEP:-}" ] || exit 1; echo mark > made\n' > keepfix/01-ok.sh
printf 'echo boom; exit 1\n' > keepfix/02-bad.sh
if TMPDIR="$PWD/tmp" BLAST_OFF_TEST_KEEP=kept run_gate keepfix; then fail "keep fixture exited 0"; fi
grep -qx 'GATE: FAIL passed=1 failed=1 shellcheck=skipped' keepfix.out || fail "keep fixture verdict: $(cat keepfix.out)"
grep -qx boom kept/02-bad/out 2>/dev/null || fail "failed scenario's output not kept: $(ls -R kept 2>&1)"
[[ -f kept/01-ok/out ]] || fail "passed scenario's output not kept: $(ls -R kept 2>&1)"
grep -qx mark kept/01-ok/cwd/made 2>/dev/null || fail "scenario's cwd not kept: $(ls -R kept 2>&1)"
TMPDIR="$PWD/tmp" BLAST_OFF_TEST_KEEP=kept run_gate keepfix || true
[[ -z $(compgen -G 'kept/01-ok/tmp.*') && -f kept/01-ok/out ]] || fail "second run nested into the kept dir: $(ls -R kept)"
[[ -z $(ls -A tmp) ]] || fail "kept work dirs also left in TMPDIR: $(ls -A tmp)"
if (unset BLAST_OFF_TEST_KEEP; TMPDIR="$PWD/tmp" run_gate keepfix); then fail "keep fixture exited 0 with the var unset"; fi
[[ -z $(ls -A tmp) ]] || fail "work dirs left with BLAST_OFF_TEST_KEEP unset: $(ls -A tmp)"

# --- the shellcheck skip holds only for a fixture dir, never for the suite tests/run lives beside ---
mkdir -p self/tests/fakes; cp "$REPO/tests/run" self/tests/run
printf '#!/usr/bin/env bash\nexit 0\n' > self/tests/01-ok.sh
printf '#!/usr/bin/env bash\nx=1\n' > self/tests/fakes/claude
BLAST_OFF_NO_SHELLCHECK=1 self/tests/run > self.out 2>&1 || true
if grep -q 'shellcheck=skipped' self.out; then fail "shellcheck skip honored on the real suite: $(cat self.out)"; fi
grep -q 'shellcheck=fail' self.out || fail "extensionless shell script under tests/ not linted: $(cat self.out)"

# --- D10: per-commit LLM plugin opted out in the repo's tracked settings ---
s="$REPO/.claude/settings.json"
[[ -f $s ]] || fail "missing .claude/settings.json"
[[ $(jq -r '.enabledPlugins["security-guidance@claude-plugins-official"]' "$s") == false ]] \
  || fail "security-guidance plugin not set to false in .claude/settings.json"

# --- job dirs never get staged ---
for p in .big-next-job/ .worktrees/; do
  grep -qx "$p" "$REPO/.gitignore" 2>/dev/null || fail ".gitignore lacks $p"
done

# --- per-repo job notes name the gate ---
grep -q 'tests/run' "$REPO/.claude/big-next-job.md" 2>/dev/null || fail ".claude/big-next-job.md missing or does not name tests/run"

# --- the spec maps every keep/fix item, CLI verb and exit code (guide §5 directives: test 70) ---
spec="$REPO/docs/spec.md"
[[ -f $spec ]] || fail "missing docs/spec.md"
cell='[^|]*[^ |][^|]*\|'
row() { grep -qE "^\| *$1 *\|$2 *\$" "$spec" || fail "spec has no filled row for $1"; }
for i in $(seq 1 10); do row "K$i" "$cell$cell$cell"; done
for i in $(seq 1 11); do row "F$i" "$cell$cell$cell"; done
for c in run start status stop logs resume install preflight receipt ci-wait; do row "\`$c\`" "$cell$cell"; done
for e in 0 3 4 5 6 7 8 9 10; do row "$e" "$cell$cell$cell"; done
