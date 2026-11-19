### Summary

Reviewed commit 5062c7d (`git diff feat/br-1115-issues/phase-1...HEAD`, the 5 named files; the commit also touches 3 `baton-runner/` bookkeeping files, not reviewed) against issue 31, static only: reading, `shellcheck`, `bash -n`, a PyYAML parse, read-only `gh`, a standalone re-statement of `tests/run:39,46,61-63,86-91` and a re-typed copy of the `00-harness.sh:109` pin applied to scratch copies of `ci.yml`. No repo file was executed. The injection surface is closed: the input reaches bash only as an env value, is split by `read`, and is only ever compared as quoted text; no value I tried globbed, expanded or produced a line starting `GATE: `. All four acceptance criteria are met on paper. No CRITICAL, no HIGH. What is left: the filter changes what a green `ci` run and a zero exit from `tests/run` mean, and only the receipt reader was taught the difference (2 MEDIUM); the test that guards "env only, never script text" passes with the input interpolated straight into the run script in four different spellings (1 MEDIUM); and 9 LOW.

### Findings

#### CRITICAL

None.

#### HIGH

None.

#### MEDIUM

- **Title:** PT-1. `ci-wait` cannot tell a filtered dispatch from the gate: it counts it as a `ci` run, green or red
- **Location:** `lib/ci.sh:19,29` (lists runs by `--commit <sha>`, no event filter), `:35-41` (verdict from `conclusion` only, records `name` = `ci`); `.github/workflows/ci.yml:11-16,51`; claim at `baton-phase-2-work.md:134` ("Dispatch runs are not PR checks, so nothing gates on it")
- **Description:** The claim is false for this repo's own CI reader. Measured with read-only gh: `gh run list --repo z0rd0n88/blast-off --commit ed18476125d4c429da1c1aea442c297b68d1ef03 --json databaseId,event,conclusion,name` returns 3 runs for PR 28's head: `42954767619 pull_request`, `42954765163 workflow_dispatch`, `42954762391 workflow_dispatch`, all `name: ci`. `ci_wait` watches all three and scores `all(conclusion in success|skipped|neutral)`. Before this commit every `ci` run on a commit was the whole suite. After it:
  - Red direction: a diagnostic dispatch on a PR head that ends red for a reason that says nothing about the code (a typo'd name gives `FAIL only <name>`, exit 1, by design) makes `ci-wait` record `failure` and exit 10, and `ci_check` (`lib/ci.sh:60`) refuses `done` with "PR #N CI red". The run stays listed for that head, so the refusal holds until the run is deleted or a new commit moves the head.
  - Green direction: on a head with no `pull_request` run (GitHub documents that it starts none while a PR has a merge conflict; recalled from its docs, not observed here), one `only=70-docs` dispatch turns `ci-wait` from `absent` (exit 10) into `success` (exit 0), and `gate-logs/ci-pr-<n>.json` shows `{"name":"ci","conclusion":"success"}`, identical to a full gate. Commit `03261303b3c1449bf3b996279f8c441ca21ac9b0` shows a commit in this repo whose only run is a dispatch run; `commits/<sha>/pulls` lists no PR for it, so it shows that such commits exist, not that a PR head was ever one. It cannot mask a red full run (`all(...)` at `:40`), and `ci_check` already lets `absent` through at `done` (`:59`), so the gain to a child is the `ci-wait` exit code and a record that reads as a pass.
- **Suggested fix:** Record `event` in `ci_wait` and leave `workflow_dispatch` runs out of the verdict (two `jq` selects at `:19` and `:29`), or label filtered runs with `run-name:` and record `displayTitle`. The second needs the `inputs\.` count pin at `tests/00-harness.sh:109` relaxed (see PT-3). At minimum correct the baton's claim and say in `docs/spec.md` that a dispatched `ci` run's conclusion is not the gate's.

- **Title:** PT-2. A filtered pass exits 0, and `scripts/gate.sh` passes the variable through: every reader of the exit status takes one scenario for the gate. UNREPRODUCED (runs forbidden in this review)
- **Location:** `tests/run:88-89` (exit 0 on `GATE-ONLY: PASS`), pinned by `tests/00-harness.sh:30`; `scripts/gate.sh:4,10`; `baton-runner/br-1115-issues/baton-phase-1-review-2.md:24` ("VERDICT: CLEAN by the contract's rule: gate exit 0")
- **Description:** Only the verdict line changed; the exit status of a green filtered run is 0. `scripts/gate.sh:10` runs `tests/run 2>&1 | tee` with the caller's environment (no `unset`, no `env -u`; `grep -n 'env\|unset\|BLAST_OFF' scripts/gate.sh` matches only the shebang), and its header at `:4` still promises "the last line is its GATE: PASS|FAIL verdict". With `BLAST_OFF_TEST_ONLY` left exported in the shell that runs the review unit's gate, `scripts/gate.sh` runs the named scenario plus shellcheck and exits 0. The same file already treats this class of hazard the other way: `BLAST_OFF_NO_SHELLCHECK` is "ignored on the real suite" (`tests/run:5,66`) so an ambient variable cannot weaken the real gate. The new comment at `tests/00-harness.sh:22-23` ("one green scenario must never read as a green suite") holds for `blast-off receipt` only. The CI job conclusion is the same exit status (PT-1).
  Command for the dispatching unit (70-docs starts no unit per the work baton; check before running): `BLAST_OFF_TEST_ONLY=70-docs scripts/gate.sh /tmp/pt2; echo rc=$?`. Expected: `PASS 70-docs`, `PASS shellcheck (33 files)`, `GATE-ONLY: PASS passed=1 failed=0 shellcheck=ok only=70-docs`, `rc=0`. The work baton (`baton-phase-2-work.md:116-122`) records the same three lines and exit 0 for `BLAST_OFF_TEST_ONLY=70-docs tests/run`.
- **Suggested fix:** One line in `scripts/gate.sh`: `env -u BLAST_OFF_TEST_ONLY tests/run 2>&1 | tee ...` (or refuse to start when it is set), and fix the `:4` comment. If the owner wants every exit-status reader safe, a filtered pass can exit a distinct non-zero code; that makes each diagnostic dispatch red and makes PT-1's red direction permanent, so it is the owner's call.

- **Title:** PT-3. The `ci.yml` pin for "env only, never script text" passes with the input written straight into the run script; 9 of 11 mutants survive
- **Location:** `tests/00-harness.sh:108-110`; claim in `docs/spec.md:216` ("passed through `env`") and criterion 1
- **Description:** The pin is one whole-line grep plus `grep -c 'inputs\.' == 1`. I applied 11 mutants to scratch copies of `ci.yml` (each still parses with PyYAML) and re-typed the two greps (GNU grep). Survivors (the test stays green):
  1. the whole `workflow_dispatch.inputs` block deleted (criterion 1's "has an input `only`" is untested);
  2. the input renamed to `scenarios` while env still reads `inputs.only`;
  3. `tests/run ${{ env.BLAST_OFF_TEST_ONLY }}` in the run script (the dispatch text becomes shell: the exact injection the comment at `:108` names);
  4. `${{ inputs['only'] }}` in the run script;
  5. `${{ github.event.inputs['only'] }}` in the run script;
  6. `${{ toJSON(inputs) }}` in the run script;
  7. the env line moved to the Dependencies step (`tests/run` never sees it; a dispatch with `only` silently runs the whole suite);
  8. the input's `default` changed to `70-docs` (every plain dispatch becomes filtered);
  9. `eval "tests/run $BLAST_OFF_TEST_ONLY"` in the run script.
  Killed: `${{ inputs.only }}` and `${{ github.event.inputs.only }}` in the run script. This is a new instance of the P1R2-2 class (text, not steps), on a security property this time. The count also forbids any second legitimate use of the input, such as the `run-name:` label that would fix PT-1.
- **Suggested fix:** Pin every expression in the file instead of one substring: `ci.yml` has exactly three lines holding `${{` today (`:48`, `:51`, `:70`; measured). Assert that the set of lines matching `\$\{\{` equals those three literals. That kills survivors 3 to 6 in one assertion. Add `grep -A1 '^    inputs:$' | grep -qx '      only:'` for 1 and 2. Survivors 7 to 9 need step binding (P1R2-2's fix).

#### LOW

- **Title:** PT-4. A filtered run can still end in a `GATE:` line: the keep-dir refusal is hard-coded and runs before the filter is parsed
- **Location:** `tests/run:30` (`no_keep` prints `GATE: FAIL passed=0 failed=1 shellcheck=skipped`) vs `:39` (filter parsed) and `:87`; `docs/spec.md:216` ("never a `GATE:` line"); `tests/run:12-14`; `baton-phase-2-work.md:25`
- **Description:** With both variables set and a keep dir that is refused, the run ends `GATE: FAIL ...`, with no `only=`. `blast-off receipt` would write a FAIL receipt for it (`lib/receipt.sh:8,31`), which is the outcome the baton says the `GATE-ONLY: FAIL` prefix exists to prevent. It fails closed (never a PASS). UNREPRODUCED. Command: `F=$(mktemp -d); printf 'exit 0\n' > "$F/01-ok.sh"; BLAST_OFF_TEST_ONLY=01-ok BLAST_OFF_TEST_KEEP="$F/01-ok.sh/k" BLAST_OFF_NO_SHELLCHECK=1 tests/run "$F"; echo rc=$?`. Expected: a `mkdir:` error line, `FAIL BLAST_OFF_TEST_KEEP=<path>: cannot be made`, `GATE: FAIL passed=0 failed=1 shellcheck=skipped`, `rc=1`.
- **Suggested fix:** Move the `only=` parse above the keep block and let `no_keep` print `$gate`/`$tail`, or drop "never a `GATE:` line" from the spec row.

- **Title:** PT-5. Names are echoed raw into the CI log: a dispatcher can inject runner workflow commands and hide the verdict line of their own red run. UNREPRODUCED on a runner
- **Location:** `tests/run:62` (`echo "FAIL only $o: ..."`), `:87,91` (`only=<names>` in the verdict)
- **Description:** A name may hold any byte except space, tab, line feed and comma. From the runner's source (`actions/runner` default branch, read with `gh api`, not observed on a runner): `OutputManager.cs:82-90` hands any output line holding `##[` or `::` to `TryProcessCommand` and returns without printing it when a command was processed; `ActionCommand.cs:62-63` accepts a line that starts `::` after trimming; `ActionCommand.cs:132` (`message.IndexOf("##[")`) accepts the old `##[cmd]` form anywhere in a line, with everything after the `]` as its data, and `ActionCommandManager.TryProcessCommand` tries it when the `::` parse fails. `ProcessInvoker.cs:513` reads output with `StreamReader.ReadLine()`; that a bare CR ends a line there is .NET's documented `ReadLine` behaviour, not something this file shows. So `only='x##[error]boom'` (no CR needed, typeable in the dispatch form) turns both the `FAIL only` line and the verdict line into error annotations, and with `x##[add-mask]q` both lines are consumed as `add-mask` commands (`ActionCommandManager.cs:420-440`: `OmitEcho => true`, `SecretMasker.AddValue(command.Data)`), so neither is printed and `q` is masked in later output. With a CR, `only=$'x\r::error::spoof'` does the same through the `::` form; my probe shows the CR passes through unchanged (`FAIL only zz^M::error::spoofed: ...`). A CR plus no-break spaces also draws `GATE: PASS passed=18 ...` over the verdict in a terminal, while the receipt still refuses the line (probe: `REFUSE`). Bounds: the name can never match a scenario, so the run is always red; a dispatch needs write access; the job has `contents: read` and no secrets. Local command (do not run against GitHub): `BLAST_OFF_TEST_ONLY='x##[error]boom' BLAST_OFF_NO_SHELLCHECK=1 tests/run "$F"`. Expected: `FAIL only x##[error]boom: no such scenario in $F`, `GATE-ONLY: FAIL passed=0 failed=1 shellcheck=skipped only=x##[error]boom`.
- **Suggested fix:** One guard after the split, in the style of `lib/receipt.sh:21`: a name that is not `^[0-9A-Za-z._-]+$` is a failure printed with `%q`. It also closes PT-6.

- **Title:** PT-6. `echo` eats a name of `-n`, `-e` or `-E`: the verdict ends in an empty `only=`
- **Location:** `tests/run:87` (`$(IFS=,; echo "${only[*]}")`)
- **Description:** Probe output for `only=-n`, `-e`, `-neE`: `GATE-ONLY: FAIL passed=0 failed=1 shellcheck=sc only=`. The `FAIL only -n` line above it is right; the verdict's own record of the filter is blank. With a second name the joined string is no longer an option and prints. Command: `BLAST_OFF_TEST_ONLY=-n BLAST_OFF_NO_SHELLCHECK=1 tests/run "$F"`; expected last line `GATE-ONLY: FAIL passed=0 failed=1 shellcheck=skipped only=`.
- **Suggested fix:** `printf '%s' "${only[*]}"` instead of `echo`.

- **Title:** PT-7. A dispatch whose names all match nothing uploads a green artifact that holds one empty directory
- **Location:** `tests/run:33` (keep dir made before the filter at `:39`), `:61-63`; `.github/workflows/ci.yml:62-71`
- **Description:** No scenario runs, the step exits 1, both `failure()` steps run. The keep dir exists and is empty, so tar exits 0. Reproduced the tar half on my own fixture with the `ci.yml:64` line: exit 0, 1 member (`blast-off-tests/`), 122 bytes; the upload then finds its file. This is not P1R2-1 (missing dir, tar exits 2): it is a second, easier way to a contentless green upload, reached by a typo. `ci.yml:4-5` ("every scenario's work dir") also no longer holds on a filtered run.
- **Suggested fix:** Accept and reword `ci.yml:4-5` to "every scenario that ran", or fix with P1R2-1.

- **Title:** PT-8. Line-feed and tab separators are untested; dropping `-d ''` survives and silently drops every name after the first line
- **Location:** `tests/run:39` (comment "-d '': every line"); `tests/00-harness.sh:33,42,47` (every tested value is one line)
- **Description:** Measured: `read -ra only <<< $'70-docs\n10-chain-done'` gives `([0]="70-docs")`; with `-d ''` it gives both. No value in the 00-harness block holds a line feed or a tab (count 0), so that mutant stays green and a two-line `only` sent through the API would run and report only the first line as `GATE-ONLY: PASS ... only=70-docs`. The work baton probed this by hand only (`baton-phase-2-work.md:84`).
- **Suggested fix:** Add `$'02-b\n01-a'` and `$'02-b\t01-a'` to the loop at `tests/00-harness.sh:33`.

- **Title:** PT-9. The new comments claim more than the change delivers: one green scenario still receipts a phase through `tests/run <dir>`
- **Location:** `tests/00-harness.sh:22-23`, `tests/40-receipt-required.sh:60-61` ("so one green scenario never receipts a phase")
- **Description:** Pre-existing and out of this diff's scope, raised because the diff's comments assert the opposite. `tests/run <dir holding one scenario>` prints `GATE: PASS passed=1 failed=0 shellcheck=ok` (the issue's own Evidence section uses this), `tests/00-harness.sh:13` pins the `passed=1` line, and `lib/receipt.sh:8,31-34` reads only the prefix and copies the tally unchecked; `tests/40-receipt-required.sh:86` receipts `GATE: PASS passed=1 failed=0 shellcheck=ok`. This diff closes the door it opened, not the older one beside it.
- **Suggested fix:** Reword both comments to "a run filtered by BLAST_OFF_TEST_ONLY"; file the scenario-dir case as its own issue.

- **Title:** PT-10. Other docs still say the last line is `GATE: PASS` or `GATE: FAIL`; the spec row of test 40 does not name its new case
- **Location:** `scripts/gate.sh:4`; `README.md:107,148`; `.claude/big-next-job.md:5-6`; `docs/spec.md:24` (K6); `templates/brief.md:61`; `skills/blast-off/SKILL.md:33`; `docs/spec.md:227` (`40-receipt-required` row: "done phase without a matching receipt; exit 9")
- **Description:** Criterion 4 binds only `docs/spec.md` §6 and the `tests/run` header, and both are updated, so the criterion is met. `grep -rn 'BLAST_OFF_TEST_ONLY\|GATE-ONLY'` outside `tests/` matches only `ci.yml` and `docs/spec.md:207,216`. The header and spec also say "spaces or commas" where tabs and line feeds split too, and neither says shellcheck still runs on a filtered run of the real suite.
- **Suggested fix:** One clause in `scripts/gate.sh:4` and `docs/spec.md:24`; extend the `:227` row.

- **Title:** PT-11. `|| true` at `tests/run:39` hides a failed here-string; the run then dies with no verdict line
- **Location:** `tests/run:39`, then `:46`
- **Description:** If the `<<<` redirection itself fails, `read` never runs and `only` stays a scalar. Measured on this box (bash 5.2.21): `set -u; x=abc; echo ${#x[@]}` aborts with `x: unbound variable`, so `tests/run` would stop at `:46` with exit 1 and no `GATE` line. Fail closed. I did not reach it through `tests/run`; it needs the here-string to fail (a value too large for a pipe with an unwritable `TMPDIR`).
- **Suggested fix:** None needed beyond PT-5's guard; or `mapfile`/`declare -a only` first so the variable is always an array.

- **Title:** PT-12. Filter behaviour with no test: shellcheck on a filtered real-suite run, and keep plus filter together
- **Location:** `tests/run:66` (shellcheck branch does not read the filter), `:56-59`; `tests/00-harness.sh:22-50` (every filtered run is a fixture dir with shellcheck skipped and no keep dir)
- **Description:** A mutant that skips shellcheck when a filter is set, or that skips the keep step for filtered runs, stays green. CI's filtered path is exactly this untested combination (real suite, keep dir set, filter set). Duplicate names print twice in the tail (`only=01-a,01-a`), cosmetic.
- **Suggested fix:** One case in the keep block: `BLAST_OFF_TEST_ONLY=01-ok BLAST_OFF_TEST_KEEP=kept3 run_gate keepfix`, assert `kept3` holds `01-ok` only.

### Validated

- **Confirmed correct:**
  - The commit touches the 5 named files plus `baton-runner/br-1115-issues/{STATE.md,baton-phase-2-work.md,log.md}`: `git diff --stat feat/br-1115-issues/phase-1...HEAD` (8 files, 224 insertions, 9 deletions).
  - The input reaches the shell only through `env:`. `ci.yml:51` is the one use; `grep -c 'inputs\.' ci.yml` = 1; the only lines holding `${{` are `:48`, `:51`, `:70`; the PyYAML parse of the gate step's `run` holds no expression and the diff has no hunk in it. The scalar parses as the plain string `${{ inputs.only }}` (PyYAML), so the file itself holds no input text.
  - No shell injection or globbing in `tests/run`. Traced `:39` (`read -r`, quoted here-string), `:46` and `:62` (name inside quotes on the pattern side of `[[ == ]]`), `:87` (quoted). Standalone probe, values `$(id)`, `` `id` ``, `01-a;id`, `*`, `[0-9][0-9]-*`, `01-a\`, `01`, `01-A`: each printed literally as `FAIL only <value>: no such scenario`, verdict `GATE-ONLY: FAIL`, nothing ran.
  - Empty, `' , '` and `$'\t,\n'` give an empty list and the unchanged `GATE:` line (probe; `tests/00-harness.sh:47-50` pins the first two). `IFS` is not taken from the environment (`IFS=x bash -c 'printf %q "$IFS"'` prints `$' \t\n'`).
  - Several names: comma, space, tab and line feed all split (probe); order follows the suite, not the list (`:43` loop).
  - An unknown name fails by name and the run exits 1, beside names that matched (`tests/run:61-63,91`; probe `-n,01-a` and `a b`).
  - No value can make the last line start `GATE: `: the line always starts with `$gate: ` and a line feed is a separator, never part of a name. My copy of `receipt_verdict` (`sed | tail -n 1`, `[[ $v == "GATE: "* ]]`) refused `GATE-ONLY: PASS ...`, a name holding `\rGATE: PASS`, and a value holding `\nGATE: PASS passed=18 ...` (it became `only=x,GATE:,PASS,...` on one line); it accepted only the unfiltered line.
  - `lib/receipt.sh` is the only parser of a verdict line: `grep -rn GATE bin lib scripts templates docs skills README.md .claude/big-next-job.md` finds code only at `lib/receipt.sh:8,24,31,38,60`; every one needs the prefix `GATE: `. `tests/51-templates.sh:100` calls `receipt_verdict` on its own fake. `lib/ci.sh` reads run conclusions, not lines (PT-1).
  - The variable is hidden from scenarios: `tests/run:40`; the fixture at `tests/00-harness.sh:26` fails if it is set, including set-but-empty.
  - Phase 1's pins are untouched: two `if: failure()` lines (`ci.yml:63,66`), one `run: tar` line (`:64`), the two literals (`:48,70`). Keep handling (`tests/run:56-59`) does not read the filter, so a filtered run keeps exactly the scenarios that ran.
  - Mutants of `tests/run` killed on paper by the new assertions: verdict prefix back to `GATE:` (00-harness `:31`, and test 40 `:66`, matching the baton's RED at `baton-phase-2-work.md:41`); `GATE-ONLY` on PASS only (`:38`); no `unset` (`:26` fixture); substring, prefix or suffix matching (`:42-45`, values `01-a.sh` and `../onlyfix/01-a`); unquoted word-split with globbing (`:42`, value `*`); no unmatched-name loop (`:40-41`); set-but-empty treated as a filter (`:47-50`); commas not split (`:33`). A `receipt.sh` mutant accepting `"GATE"*` is killed by test 40 `:66` (a FAIL receipt would be written, the test wants no file).
  - `shellcheck -S warning` and `bash -n` are clean on `tests/run`, `tests/00-harness.sh`, `tests/40-receipt-required.sh`.
  - No required status check exists for a dispatch run to satisfy: `gh api repos/z0rd0n88/blast-off/branches/main/protection` and `/rulesets` both answer 403 "Upgrade to GitHub Pro or make this repository public". Default workflow token permission is `read`; the job declares `contents: read`.
  - A dispatch run does not replace the pull request's check in the commit rollup, on this repo's history: GraphQL `statusCheckRollup` for `acf9051a` (three dispatch runs created after the `pull_request` run), `ed184761` and `82cbae89` each lists one `gate` context, the `pull_request` run's. All were green, so this shows which run is listed, not what a red one would do.

- **Examined, inconclusive:**
  - `ci.yml:51` on a `pull_request` event: `inputs.only` should evaluate to an empty string and `tests/run:39` then runs the whole suite. Blocker: no run of this workflow revision exists on GitHub (P1R2-3 class); needs one PR run whose log ends `GATE: PASS passed=18`.
  - PT-5 on a real runner: read `OutputManager.cs:82-90`, `ProcessInvoker.cs:513`, `ActionCommand.cs:62-63,132`, `ActionCommandManager.cs` `TryProcessCommand` and `:420-440`. Blocker: needs a dispatch on GitHub, which this review may not send.
  - That the runner substitutes `${{ inputs.only }}` into the env value after the YAML is parsed, so a value holding YAML syntax cannot change the workflow (`ci.yml:51`). This is how expressions are documented to work; nothing here observed it. Blocker: needs a runner.
  - The new assertions passing at HEAD: taken from `gate-phase-2-iter-1/tests-run.log` (`PASS 00-harness`, `PASS 40-receipt-required`, `GATE: PASS passed=18 failed=0 shellcheck=ok`). Blocker: runs forbidden; I did not re-run either scenario.
  - Whether zord-baton-runner reads only the gate's exit status (PT-2): `baton-phase-1-review-2.md:24` says "gate exit 0". Blocker: the skill's own code is outside the materials and was not read.
  - Tar and upload on a filtered red run on a runner: `tests/run:33,56-59` read, tar line run on my own fixture only. Blocker: needs a red dispatch on GitHub.

- **Not examined:**
  - `lib/chain.sh`, `lib/child.sh`, `lib/units.sh`, `lib/preflight.sh`, `lib/jev.sh`, `lib/usage.sh`, `lib/checkpoint.sh` beyond the grep for `GATE`.
  - `tests/51-templates.sh` and `tests/70-docs.sh` beyond the grep for what they pin in `ci.yml`, `tests/run` and the spec.
  - `docs/spec.md` outside §6 and the rows found by grep; `baton-runner/br-1115-issues/log.md`; the other reviewers' files in `review-phase-2-iter-1/`.
  - The dispatch form's own handling of the value (trimming, length limit) and `gh workflow run` quoting.

### Confidence

High that the input cannot inject shell in `tests/run` and that no filtered run can be receipted as a pass (traced line by line and probed with 23 values); medium on the YAML side, PT-1's green direction and PT-5, which rest on GitHub behaviour read from docs, runner source and this repo's run history. One PR run and one `only=70-docs` dispatch of this revision on GitHub, plus the four local commands given above, would settle the rest.
