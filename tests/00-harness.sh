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
printf '[ -z "${BLAST_OFF_TEST_KEEP+x}" ] || exit 1; echo mark > made\n' > keepfix/01-ok.sh
printf 'echo boom; exit 1\n' > keepfix/02-bad.sh
keep_verdict() { grep -qx 'GATE: FAIL passed=1 failed=1 shellcheck=skipped' keepfix.out || fail "$1 verdict: $(cat keepfix.out)"; }
if TMPDIR="$PWD/tmp" BLAST_OFF_TEST_KEEP=kept run_gate keepfix; then fail "keep fixture exited 0"; fi
keep_verdict "keep fixture"
grep -qx boom kept/02-bad/out 2>/dev/null || fail "failed scenario's output not kept: $(ls -R kept 2>&1)"
[[ -f kept/01-ok/out ]] || fail "passed scenario's output not kept: $(ls -R kept 2>&1)"
grep -qx mark kept/01-ok/cwd/made 2>/dev/null || fail "scenario's cwd not kept: $(ls -R kept 2>&1)"
# a second run (the same dir, named by its absolute path as CI does) replaces what the first kept:
# nothing stale, nothing nested, one dir per scenario
touch kept/01-ok/stale
if TMPDIR="$PWD/tmp" BLAST_OFF_TEST_KEEP="$PWD/kept" run_gate keepfix; then fail "keep fixture exited 0 on its second run"; fi
keep_verdict "keep fixture's second run"
[[ $(ls -A kept/01-ok) == $'cwd\nout' && $(ls -A kept) == $'01-ok\n02-bad' ]] || fail "second run did not replace the kept dirs: $(ls -RA kept)"
[[ -z $(ls -A tmp) ]] || fail "kept work dirs also left in TMPDIR: $(ls -A tmp)"
if (unset BLAST_OFF_TEST_KEEP; TMPDIR="$PWD/tmp" run_gate keepfix); then fail "keep fixture exited 0 with the var unset"; fi
keep_verdict "keep fixture with the var unset"
[[ -z $(ls -A tmp) ]] || fail "work dirs left with BLAST_OFF_TEST_KEEP unset: $(ls -A tmp)"
# a work dir that cannot be kept is a failure with a name: the suite still runs to its verdict and nothing
# stays in TMPDIR. The first scenario swaps the keep dir for a file, which stops mv for root too.
mkdir nokeep
printf 'rm -rf %q; : > %q\n' "$PWD/kept2" "$PWD/kept2" > nokeep/01-ok.sh
printf 'exit 0\n' > nokeep/02-ok.sh
if TMPDIR="$PWD/tmp" BLAST_OFF_TEST_KEEP=kept2 run_gate nokeep; then fail "unkeepable work dirs exited 0"; fi
grep -qx 'FAIL keep 01-ok' nokeep.out && grep -qx 'FAIL keep 02-ok' nokeep.out || fail "unkeepable work dirs not named: $(cat nokeep.out)"
grep -qx 'GATE: FAIL passed=2 failed=2 shellcheck=skipped' nokeep.out || fail "unkeepable work dirs verdict: $(cat nokeep.out)"
[[ -z $(ls -A tmp) ]] || fail "unkeepable work dirs left in TMPDIR: $(ls -A tmp)"
# a keep dir that cannot be made (here: under a regular file) fails before any scenario, with a verdict
if BLAST_OFF_TEST_KEEP=ok.out/kept run_gate keepfix; then fail "uncreatable keep dir exited 0"; fi
[[ $(grep -v '^mkdir: ' keepfix.out) == $'FAIL BLAST_OFF_TEST_KEEP=ok.out/kept: cannot be made\nGATE: FAIL passed=0 failed=1 shellcheck=skipped' ]] \
  || fail "uncreatable keep dir: $(cat keepfix.out)"

# --- the shellcheck skip holds only for a fixture dir, never for the suite tests/run lives beside ---
mkdir -p self/tests/fakes; cp "$REPO/tests/run" self/tests/run
printf '#!/usr/bin/env bash\nexit 0\n' > self/tests/01-ok.sh
printf '#!/usr/bin/env bash\nx=1\n' > self/tests/fakes/claude
BLAST_OFF_NO_SHELLCHECK=1 self/tests/run > self.out 2>&1 || true
if grep -q 'shellcheck=skipped' self.out; then fail "shellcheck skip honored on the real suite: $(cat self.out)"; fi
grep -q 'shellcheck=fail' self.out || fail "extensionless shell script under tests/ not linted: $(cat self.out)"
# so a keep dir under bin/, lib/ or tests/ is refused before anything is made there: the scripts kept in it
# would fail that lint, and go on failing it after the var is unset
if (cd self && BLAST_OFF_TEST_KEEP=tests/kept tests/run > ../selfkeep.out 2>&1); then fail "keep dir under tests/ exited 0"; fi
[[ $(cat selfkeep.out) == "FAIL BLAST_OFF_TEST_KEEP=tests/kept: under a dir this gate lints"$'\n''GATE: FAIL passed=0 failed=1 shellcheck=skipped' && ! -e self/tests/kept ]] \
  || fail "keep dir under tests/ not refused: $(cat selfkeep.out; ls self/tests)"

# --- ci.yml: a red run's kept tree goes up as one tar file. upload-artifact refuses a whole tree for one
# file name holding any of " : < > | * ? CR LF (22-dirty-tree leaves a line feed), and drops dot files
# (every .git). The tar line is run here as CI runs it, on a tree named as the keep dir is, so the keep
# dir, the tar and the uploaded path cannot drift apart. ---
ci="$REPO/.github/workflows/ci.yml"
grep -qF 'BLAST_OFF_TEST_KEEP: ${{ runner.temp }}/blast-off-tests' "$ci" || fail "ci.yml does not keep work dirs in runner.temp/blast-off-tests"
grep -qF 'path: ${{ runner.temp }}/blast-off-tests.tgz' "$ci" || fail "ci.yml does not upload runner.temp/blast-off-tests.tgz"
[[ $(grep -c '^ *if: failure()$' "$ci") == 2 ]] || fail "ci.yml: the tar and the upload steps do not both run on failure()"
tarline="$(sed -n 's/^ *run: \(tar .*\)$/\1/p' "$ci")"
[[ -n $tarline ]] || fail "ci.yml has no one-line 'run: tar ...' step"
odd=$'" : < > | * ? \r \n'
mkdir -p rt/blast-off-tests/22-x/cwd/.git back
echo named > "rt/blast-off-tests/22-x/cwd/$odd"; echo hidden > rt/blast-off-tests/22-x/cwd/.git/HEAD
ln -s /nowhere rt/blast-off-tests/22-x/cwd/link
RUNNER_TEMP="$PWD/rt" bash -c "$tarline" || fail "ci.yml's tar line failed: $tarline"
tar -xzf rt/blast-off-tests.tgz -C back || fail "ci.yml's tar line made no readable rt/blast-off-tests.tgz: $(ls rt)"
diff -r --no-dereference rt/blast-off-tests back/blast-off-tests || fail "the tar file is not the kept tree"

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
