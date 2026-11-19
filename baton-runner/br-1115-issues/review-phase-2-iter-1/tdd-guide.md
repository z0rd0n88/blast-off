### Summary

I reviewed commit 5062c7d (the five-file diff against `feat/br-1115-issues/phase-1`) as the tests reviewer: are the new assertions real, what do they bind, what is left unbound. Static work only: no scenario, `tests/run`, `scripts/gate.sh` or `bin/blast-off` was run, on the repo or a copy. The filter in `tests/run` is correct for every input I traced, and the new assertions in `tests/00-harness.sh:22-50` and `tests/40-receipt-required.sh:60-67` are real: none is vacuous, and each kills the revert of the line it targets. I found no CRITICAL and no HIGH. The open items are binding gaps. (1) `blast-off ci-wait` counts a green filtered dispatch as a green CI run, which contradicts the work baton's "nothing gates on it"; I measured the listing on four commits. (2) The new `ci.yml` pin does not bind the `workflow_dispatch` input declaration or the step that carries the env line, and its "and nowhere else" claim is false; five mutants pass all five text pins. (3) No assertion filters the real suite dir, the only path CI takes. (4) The newline split, added on purpose, has no assertion. Eight LOW items follow. Every surviving mutant is listed with its exact edit for the dispatching unit to run.

### Findings

#### CRITICAL

None.

#### HIGH

None.

#### MEDIUM

- **`blast-off ci-wait` counts a green filtered dispatch as a green CI run; the work baton's "nothing gates on it" is false**
  - **Location:** `lib/ci.sh:19,29,40` (unchanged); `tests/run:88-89` (exit 0 on `GATE-ONLY: PASS`); `.github/workflows/ci.yml:12-16,51`; claim at `baton-runner/br-1115-issues/baton-phase-2-work.md` ("Dispatch runs are not PR checks, so nothing gates on it").
  - **Description:** `ci_wait` lists every run of the PR head with `gh run list --commit "$sha"` and calls the head green when every listed run concluded `success`, `skipped` or `neutral`. The list is not filtered by event. Measured read-only on z0rd0n88/blast-off: commit `ed18476125` lists 3 runs (1 `pull_request`, 2 `workflow_dispatch`), `acf9051a2e` lists 4 (1 and 3), `057313266d` lists 2 (both `workflow_dispatch`, both `failure`), `8bc31641ed` lists 1 (`workflow_dispatch`, `success`). All are named `ci`, so the record in `gate-logs/ci-pr-<n>.json` (`id`, `name`, `conclusion`) cannot tell a filtered run from the gate. Reach, stated exactly: `all()` at `lib/ci.sh:40` means a green filtered run cannot mask a red `pull_request` run. It stands alone on a PR head that has no `pull_request` run (GitHub documents that `pull_request` workflows do not run on a PR with a merge conflict; `[skip ci]` does the same); there, one green scenario gives `verdict: success` and exit 0 where the head had `absent` and exit 10 before. The runner's own `done` decision does not change on such a head, because `ci_check` already lets an `absent` record through (`lib/ci.sh:50-52,59`); what changes is the record (`success`, not `absent`, with no "not a pass" log line) and `ci-wait`'s exit status, which the child protocol in `templates/brief.md:136-146` acts on. The other direction also grew: a red diagnostic dispatch on a PR head (reproducing a failing scenario is this feature's purpose, and a typo'd name is red too) makes `ci-wait` record `failure` and `done` exit 10 until a new push. Before this diff every dispatch was the whole suite, so "every run green" meant the gate was green. The issue's caution (a filtered green read as the gate) is closed for `receipt` and open for `ci-wait`. No test covers it: `tests/fakes/gh` has no event field and `tests/41-ci-wait.sh` is unchanged.
  - **Suggested fix:** Outside this phase's five-file target set, so a decision for the manager. Smallest change: add `event` to the `--json` at `lib/ci.sh:19,29` and drop `workflow_dispatch` runs in the `jq`, with one `41-ci-wait` case (fake `gh` gains an event per run). Alternative: give filtered runs a `run-name:` and record it. At minimum, correct the baton claim and add one sentence to the `ci.yml` header.

- **The `ci.yml` pin binds one line of text: the input declaration and the step are unbound, and "and nowhere else" is false (the known "binds text, not steps" item, extended by this diff)**
  - **Location:** `tests/00-harness.sh:108-110`; `.github/workflows/ci.yml:12-16,51`.
  - **Description:** The pin is a whole-line match of the env line plus a count of lines containing `inputs.` (1 at HEAD: line 51; line 12 `inputs:` has no dot). I ran all five `ci.yml` text pins (`00-harness.sh:106,107,109,111,112-113`) as greps on scratch copies. Five mutants keep all five green: (a) delete the `inputs:` block, lines 12-16, so the dispatch has no `only` input at all and criterion 1's deliverable is gone; (b) `type: boolean` with `default: "00-harness"`; (c) move the env line from the `tests/run` step to the `Dependencies` step, so the filter never reaches the gate; (d) `tests/run ${{ env.BLAST_OFF_TEST_ONLY }}` in the run script, which is the injection the pin's comment says it prevents, through the `env` context; (e) `echo '${{ toJSON(inputs) }}'` in the run script. Killed at line 109: `${{ inputs.only }}` and `${{ github.event.inputs.only }}` in the run script. Also killed, wrongly: a harmless comment line `# inputs.only is empty on a pull request` turns the gate red. All mutants are UNREPRODUCED (runs forbidden in this review) as end-to-end 00-harness runs; the greps themselves were run.
  - **Suggested fix:** Bind structure, not one line. Without a new dependency: ordered whole-line matches (`    inputs:` then `      only:` then `        type: string` under `workflow_dispatch:`; the env line inside the block that follows `- name: tests/run`), and a check that no line of any `run:` script contains `${{`. Or parse the YAML in the test and assert the same three things; `ci.yml:25` lists `python3` as shipped with the image but says nothing of PyYAML, so its presence on the runner is unverified. Either replaces the line count and its false positive.

- **No assertion filters the real suite dir, the only path a CI dispatch takes**
  - **Location:** `tests/00-harness.sh:25-50,89-99`; `tests/40-receipt-required.sh:62-63`; `tests/run:66,86-87`.
  - **Description:** All 11 filtered invocations in the diff (10 in `00-harness`, 1 in test 40) run a fixture dir with `BLAST_OFF_NO_SHELLCHECK=1`, so every pinned filtered verdict says `shellcheck=skipped`. The `self` fixture at `00-harness.sh:89-99` (the only place `DIR = HERE` is exercised) never sets the filter. CI always runs `DIR = HERE` with lint. Two mutants survive every assertion (UNREPRODUCED, runs forbidden): skipping lint on a filtered run (`tests/run:66` becomes `if [ ${#only[@]} -eq 0 ] && { [ -z "${BLAST_OFF_NO_SHELLCHECK:-}" ] || [ "$DIR" = "$HERE" ]; }; then`), and keeping the gate's prefix on the real suite (`tests/run:87` becomes `[ ${#only[@]} -eq 0 ] || [ "$DIR" = "$HERE" ] || { gate=GATE-ONLY; ...; }`), which prints `GATE: PASS passed=1` on a filtered CI run, the exact hole the issue names. The decision "shellcheck still runs on a filtered real-suite run" exists only in `phase-2/task_plan.md`; the header and `docs/spec.md:216` do not state it. The only evidence for the CI-path line `GATE-ONLY: PASS passed=1 failed=0 shellcheck=ok only=70-docs` is one hand run in the baton.
  - **Suggested fix:** One assertion on the existing `self` fixture: `BLAST_OFF_TEST_ONLY=01-ok BLAST_OFF_NO_SHELLCHECK=1 self/tests/run`, last line exactly `GATE-ONLY: FAIL passed=1 failed=1 shellcheck=fail only=01-ok`. It kills both mutants. Add "shellcheck still runs" to the header.

- **The newline split (`read -d ''`) has no assertion; without it a named scenario is dropped silently**
  - **Location:** `tests/run:39`; `tests/00-harness.sh:33`.
  - **Description:** The three multi-name cases (`'02-b,01-a'`, `' 02-b  01-a '`, `'02-b, 01-a,'`) are all one line. Measured with a self-contained probe of the idiom (bash 5.2.21): `read -rd '' -a` gives 2 names for `$'01-a\n03-c'`; `read -ra` gives 1 (`01-a`). So the mutant `read -rd '' -a only` to `read -ra only` at `tests/run:39` passes every assertion (UNREPRODUCED end to end, runs forbidden), and under it `BLAST_OFF_TEST_ONLY=$'01-a\n03-c'` would run `01-a` alone and print `GATE-ONLY: PASS ... only=01-a`: the failing `03-c` is neither run nor named. The baton records this behaviour as a hand probe only. A tab separator is likewise unasserted (same mechanism as the space).
  - **Suggested fix:** Add `$'02-b\n01-a'` (and a tab form) to the list at `00-harness.sh:33`.

#### LOW

- **A filtered run can end in a `GATE:` line: the keep-dir refusal fires before the filter is read**
  - **Location:** `tests/run:30` (hard-coded `GATE: FAIL passed=0 failed=1 shellcheck=skipped`, exit at line 30) runs before `tests/run:39`; `docs/spec.md:216` ("never a `GATE:` line, so `blast-off receipt` refuses the log"); `tests/run:13-14`.
  - **Description:** With both variables set and a keep dir that is refused, the run prints the gate's own FAIL line. `receipt` would write a FAIL receipt, not refuse. The outcome is still a failure, so the harm is a false sentence in the spec and header. No assertion sets `BLAST_OFF_TEST_KEEP` and `BLAST_OFF_TEST_ONLY` together, though CI always sets both. UNREPRODUCED (runs forbidden): `f=$(mktemp); BLAST_OFF_TEST_ONLY=01-a BLAST_OFF_TEST_KEEP="$f/kept" BLAST_OFF_NO_SHELLCHECK=1 tests/run <fixture dir>` (the keep path sits under a regular file, so `mkdir -p` fails) should print one `mkdir:` error line, then `FAIL BLAST_OFF_TEST_KEEP=<that path>: cannot be made`, then `GATE: FAIL passed=0 failed=1 shellcheck=skipped`.
  - **Suggested fix:** Move lines 39-40 above the keep block and use `$gate`/`$tail` in `no_keep`, or reword the spec to "never `GATE: PASS`". Add one combined case.

- **Two mutants of the unknown-name check survive: every odd-name case runs with nothing matched**
  - **Location:** `tests/run:62`; `tests/00-harness.sh:40-45`.
  - **Description:** The pattern and path cases (`'*'`, `'0?-a'`, `'../onlyfix/01-a'`, `'01-a.sh'`) are each given alone, so `ran` is `' '` when line 62 runs. Probe of the idiom: with `$o` unquoted (`[[ $ran == *" "$o" "* ]]`), `ran=' '` gives no match for `*` and `0?-a` (same output as HEAD), while `ran=' 01-a '` matches both. With a substring test (`[[ $ran == *"$o"* ]]`), `ran=' 01-a '` matches `1-a`. Both mutants pass the suite (UNREPRODUCED end to end). Under them `only='01-a 0?-a'` or `only='01-a 1-a'` ends `GATE-ONLY: PASS` with an unmatched name unreported. "Names are text, never patterns" is pinned for the filter line (46) only.
  - **Suggested fix:** Add `only '01-a 0?-a'` and `only '01-a 1-a'`, each expecting `FAIL only <name>` beside `PASS 01-a`.

- **A lone name `-n`, `-e` or `-E` vanishes from the verdict line**
  - **Location:** `tests/run:87` (`echo "${only[*]}"`).
  - **Description:** Measured with the idiom: `-n` and `-e` each give `tail=[]`, so the line ends `only=` with no name. The run still fails by name (`FAIL only -n: ...`), so this is cosmetic. `-n,01-a` prints intact.
  - **Suggested fix:** `printf '%s' "${only[*]}"` (measured: prints `-n`).

- **A typo'd name uploads an artifact with nothing in it (a new trigger beside the known empty-archive item)**
  - **Location:** `tests/run:33` (keep dir made before the loop); `.github/workflows/ci.yml:62-71`.
  - **Description:** When no named scenario exists the run is red, the keep dir exists and is empty, and the tar step succeeds. Measured on a scratch dir: `tar -C rt -czf rt/blast-off-tests.tgz blast-off-tests` exits 0, 122 bytes, 1 member (`blast-off-tests/`). The upload goes green and `if-no-files-found: error` cannot fire. The known item covers a missing keep dir (tar exits 2); here tar exits 0, so that item's suggested fix would not cover it. Otherwise phase 1's steps hold on a filtered run: a red filtered run keeps the dirs of the scenarios that ran, a green one uploads nothing.
  - **Suggested fix:** Accept and note it in the `ci.yml` comment, or skip the tar when the dir is empty.

- **`scripts/gate.sh` passes an inherited `BLAST_OFF_TEST_ONLY` through and exits 0 on `GATE-ONLY: PASS`**
  - **Location:** `scripts/gate.sh:4,10`; `tests/run:88-89`.
  - **Description:** A filtered pass exits 0. `gate.sh` runs `tests/run` with the caller's environment and returns its status, and its header says the last line is the `GATE: PASS|FAIL` verdict. A review unit that judges "gate exit 0" would accept a one-scenario run if the variable were exported in its shell. No scenario references `gate.sh` (grep: 0 hits under `tests/`).
  - **Suggested fix:** `env -u BLAST_OFF_TEST_ONLY tests/run` in `gate.sh`, or have it refuse when the variable is set. Outside the target set.

- **A filtered FAIL log is never put through `receipt`**
  - **Location:** `tests/40-receipt-required.sh:62-67`.
  - **Description:** Test 40 proves the refusal for a `GATE-ONLY: PASS` log only. The FAIL side holds by reading (`lib/receipt.sh:8` refuses both) and the FAIL prefix is pinned by `00-harness.sh:38,41,44`, so no mutant survives; the claim "refuses the log" for a FAIL log rests on two tests read together.
  - **Suggested fix:** Optional: a second fixture scenario that fails, same three checks.

- **Docs and header say less, or other, than the code**
  - **Location:** `tests/run:11-16`; `docs/spec.md:24,216,227`; `README.md:148`; `.claude/big-next-job.md:5-6`; `scripts/gate.sh:4`.
  - **Description:** (1) "split by spaces or commas": the code splits on any whitespace, tab and newline included. (2) "empty runs the whole suite": so does a value of only separators (`' , '`, pinned at `00-harness.sh:47`, absent from the spec row). (3) The `40-receipt-required` row (`docs/spec.md:227`) does not name its new assertion; the baton admits this. (4) `docs/spec.md:24`, `README.md:148`, `.claude/big-next-job.md:5-6` and `scripts/gate.sh:4` still say `tests/run` ends `GATE: PASS` or `GATE: FAIL`, with no filtered exception. (5) Nothing says how to dispatch (`gh workflow run ci -f only=<name>`). `tests/70-docs.sh` pins none of this (grep: no `tests/run`, `GATE` or `BLAST_OFF_TEST` in it). Criterion 4 is met as worded.
  - **Suggested fix:** One clause each in the header and row 216; one clause in row 227.

- **Nits in the new test block**
  - **Location:** `tests/00-harness.sh:28-50`.
  - **Description:** All 12 `only` calls write the same `onlyfix.out`. A repeated name (`01-a,01-a`: runs once, tail `only=01-a,01-a`, measured on the idiom) is unpinned. A name with a carriage return fails by name and prints the raw byte into the log.
  - **Suggested fix:** Optional.

#### Surviving mutants for the dispatching unit (all UNREPRODUCED, runs forbidden in this review)

Run each alone, one at a time, on a copy: `C=$(mktemp -d); git -C <worktree> archive HEAD | tar -x -C "$C"`; apply one edit in `$C`; `d=$(mktemp -d); ln -s "$C/tests/00-harness.sh" "$d/"; BLAST_OFF_NO_SHELLCHECK=1 "$C/tests/run" "$d"`. `00-harness` does not call `install_units` (grep: only `tests/11-unit-smoke.sh` and `tests/31-resume-after-reset.sh` do). Expected for a survivor: `PASS 00-harness` then `GATE: PASS passed=1 failed=0 shellcheck=skipped`.

| Mutant (exact edit) | Assertion I expected to catch it |
|---|---|
| `ci.yml`: delete lines 12-16 (the `inputs:` block) | `00-harness.sh:109-110` |
| `ci.yml:15-16`: `type: boolean`, `default: "00-harness"` | `00-harness.sh:109-110` |
| `ci.yml`: move line 51 under a new `env:` on the `Dependencies` step | `00-harness.sh:109-110` |
| `ci.yml:56`: `tests/run ${{ env.BLAST_OFF_TEST_ONLY }}` | `00-harness.sh:109-110` ("and nowhere else") |
| `ci.yml:56`: `echo '${{ toJSON(inputs) }}'; tests/run` | `00-harness.sh:109-110` |
| `tests/run:39`: `read -rd '' -a only` to `read -ra only` | `00-harness.sh:33-36` |
| `tests/run:62`: `*" $o "*` to `*" "$o" "*` | `00-harness.sh:42-45` |
| `tests/run:62`: `*" $o "*` to `*"$o"*` | `00-harness.sh:40-45` |
| `tests/run:66`: prefix the condition with `[ ${#only[@]} -eq 0 ] &&` (group the rest in braces) | none exists; nearest `00-harness.sh:89-94` |
| `tests/run:87`: insert `\|\| [ "$DIR" = "$HERE" ]` before the brace group | `00-harness.sh:31`, `40-receipt-required.sh:65-66` (both use fixture dirs) |

### Validated

- **Confirmed correct:**
  - No shell injection path in `tests/run`: the value is read once into an array by `read` from a here-string (`:39`), then used only as the quoted left side of `[[ == ]]` (`:46`), quoted on the right side (`:62`), in `echo` arguments (`:62,87`) and as a count (`:46,87`). No `eval`, no arithmetic on the value, no path built from it.
  - No YAML injection: `python3 yaml.safe_load` of `ci.yml` gives `workflow_dispatch.inputs.only = {description, type: string, default: ''}`, the `tests/run` step's env holds both variables, and its `run` text is the four lines it was at phase 1. The expression sits in an `env:` value, evaluated after the YAML is parsed.
  - Split behaviour, measured on the idiom (bash 5.2.21): `''` and `' , '` give 0 names; `'02-b, 01-a,'` gives 2, tail `02-b,01-a`; newline and tab split; `'01-a;02-b'`, `'*'`, `'\x41'`, `'a\'` stay one literal name; an empty array expands safely under `set -u`.
  - Names are text on the filter line: `'*'`, `'0?-a'`, `'01-a.sh'`, `'01'` all skip scenario `01-a` (probe of `:46`).
  - The variable is hidden from scenarios: `unset` at `:40` precedes the loop at `:43`; pinned for a set value (`00-harness.sh:26,30`) and for set-but-empty (`:47-49`, expected output has `PASS 01-a`).
  - Unfiltered lines are byte-identical: with 0 names `gate=GATE` and `tail` is empty (`:86-91`); phase 1's exact-line pins (`00-harness.sh:13,16,58,81,85,98`) are untouched by the diff, and the dispatcher's gate log shows 18 passes and `GATE: PASS passed=18 failed=0 shellcheck=ok`.
  - `receipt` refuses a filtered log: `lib/receipt.sh:8` needs the prefix `GATE: ` and `GATE-ONLY: ` differs at the fifth character; the file is not in the diff. All four comparisons in it (`:8,31,38,60`) need `GATE: `.
  - Other verdict-line readers: `lib/receipt.sh` is the only code that reads one; `tests/51-templates.sh:100` calls `receipt_verdict`; the rest is prose (`bin/blast-off:13`, `scripts/gate.sh:4`, `templates/brief.md:61,142`, `README.md:107,148`, `skills/blast-off/SKILL.md:33,85`, `.claude/big-next-job.md:5-6`, `docs/spec.md:24,57,96`). None accepts `GATE-ONLY:`. `lib/ci.sh` reads run conclusions, not lines (first MEDIUM).
  - Killed mutants, by trace: no filter at `:46` dies at `00-harness.sh:31`; no `unset` at `:40` dies at `:30`; no comma replacement dies at `:34-35`; prefix revert dies at `:31` and at `40-receipt-required.sh:65-66` (receipt exits 0); no tail dies at `:31`; no unknown-name loop dies at `:40` and `:43-44` (output becomes `FAIL no scenarios found`); empty treated as filtered dies at `:49`; a substring filter (`*"$name"*`) dies at `:44` for `'01-a.sh'`; `lib/receipt.sh:8` loosened to `"GATE"*` dies at the `! -e phase-8.json` check (`40-receipt-required.sh:66`, a FAIL receipt gets written).
  - Test 40's refusal is for the right reason: the verdict check (`lib/receipt.sh:24`) runs before the dirty-tree check (`:27-28`), the fixture sits in the excluded job dir, and `:67` pins the logged reason for `phase-8.log` by name.
  - The work baton's RED outputs match a static trace of the old `tests/run` against the new tests (old code leaves the variable set, so `01-a` fails, and runs all three scenarios).
  - Phase 1 pins hold at HEAD: all five text pins green on `ci.yml` (two `if: failure()` lines, one `run: tar` line unchanged, both literals).
  - `shellcheck` 0.11.0 `-S warning` is clean and `bash -n` passes on `tests/run`, `tests/00-harness.sh`, `tests/40-receipt-required.sh`.
  - No required status check can be satisfied by a filtered run: `gh api .../branches/main/protection` and `.../rulesets` both return 403 "Upgrade to GitHub Pro", so the repo has no branch protection.
  - The new nested `tests/run` calls (`00-harness.sh:28`, `40-receipt-required.sh:63`) run fixture scenarios only; neither file calls `install_units`.

- **Examined, inconclusive:**
  - `inputs.only` on a `pull_request` event (`ci.yml:51`): the test pins set-but-empty locally (`00-harness.sh:47-50`), but no run exists for 5062c7d (newest listed run is for `e35e47f`). Blocker: needs one real `pull_request` run; every PR run from this commit on depends on it. Expected: the step's env shows `BLAST_OFF_TEST_ONLY:` empty and the log ends `GATE: PASS passed=18 failed=0 shellcheck=ok`.
  - A dispatch with the input (`ci.yml:12-16`): never run on GitHub. Blocker: dispatch is forbidden here. Command for the dispatching unit: `gh workflow run ci --ref feat/br-1115-issues/phase-2 -f only=70-docs`; expected last line `GATE-ONLY: PASS passed=1 failed=0 shellcheck=ok only=70-docs`, no artifact. It needs the phase-2 branch on the remote, and it leaves exactly the filtered green run on a PR head that the first MEDIUM describes.
  - Raw names echoed into the Actions log (`tests/run:62,89,91`): whether the runner acts on a `##[...]` sequence inside a line is not verified. A dispatch needs write access, so no privilege boundary is crossed.
  - Tests-first order: tests and code are one commit (5062c7d), so history cannot show it; only the baton's RED text does.
  - Every surviving mutant in the table: traced and probed as idioms, not run end to end.
  - Reach of the `ci-wait` item on a PR head with no `pull_request` run: the listing is measured; the merge-conflict and `[skip ci]` triggers are GitHub's documented behaviour, not observed here (`8bc31641ed`, the measured dispatch-only commit, is on `main`).

- **Not examined:**
  - `tests/51-templates.sh` and `tests/70-docs.sh` beyond greps; `bin/blast-off` beyond its header and line 68; `templates/brief.md` beyond lines 55-64 and 136-146; `docs/spec.md` outside section 6 and rows 24, 57, 96.
  - The diff's `STATE.md` and `log.md` changes.
  - What `zord-baton-runner` reads from `scripts/gate.sh` (exit status or log line): outside the repo.
  - Whether phase 1's upload step has yet run red on GitHub (a known open item; the green path has now run for `e35e47f` and `d21232d`).

### Confidence

High for the static claims (each has a line trace, a grep count or a probe output); medium for the mutant table until the dispatching unit runs the ten mutants, and one `pull_request` run plus one `only=70-docs` dispatch would settle the two GitHub-side unknowns.
