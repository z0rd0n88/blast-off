### Summary

I reviewed commit 5062c7d (`git diff feat/br-1115-issues/phase-1...HEAD` on the five named files) against issue 31, statically only: full reads of `tests/run`, `.github/workflows/ci.yml`, `tests/00-harness.sh`, `tests/40-receipt-required.sh`, `lib/receipt.sh`, `lib/ci.sh`, `scripts/gate.sh`, the baton and task plan, plus `shellcheck`, `bash -n`, a PyYAML parse, read-only `gh`, and self-contained bash probes of the splitting logic. No scenario, `tests/run`, `scripts/gate.sh` or repo file was executed. The core of the change is sound: the `only` input cannot inject shell or YAML (it reaches the script only as an env value, the `run:` text is unchanged), names are compared as text, a newline cannot survive into a name so a filtered run can never end in a line starting `GATE: `, and `lib/receipt.sh` is the only parser of verdict lines in the repo and refuses `GATE-ONLY:`. No CRITICAL or HIGH finding. Three MEDIUM findings: a filtered dispatch still concludes as a green `ci` run / `gate` check that `lib/ci.sh` counts as a pass (the baton's "nothing gates on it" is false, measured); the new ci.yml injection guard in `00-harness` passes 4 of 4 injection mutants written with another spelling; and the sibling "run a subset" path (`tests/run <dir>`) still prints `GATE: PASS`, which the new comments claim is closed. The rest is LOW. One side effect of my own to know about: I deleted a pre-existing scratch directory (`<scratchpad>/rt`, phase 1's kept tree) by mistake; details at the end of Validated.

### Findings

#### CRITICAL

None.

#### HIGH

None.

#### MEDIUM

**M1. A filtered dispatch is a green `ci` run and a green `gate` check; `lib/ci.sh` counts it as CI success, and the baton's claim that nothing gates on it is false**

- **Location:** `.github/workflows/ci.yml:20,51,56` (job `gate`, the env line, `tests/run`); `tests/run:88-89` (exit 0 on `GATE-ONLY: PASS`); reader `lib/ci.sh:19,29,35-41`; claim at `baton-runner/br-1115-issues/baton-phase-2-work.md` "Open questions / risks", second bullet.
- **Description:** Criterion 2 protects one reader (`blast-off receipt`). The other machine reader of "the gate passed" is `ci_wait`: `gh run list --commit "$sha"` (`lib/ci.sh:19,29`) lists every run of the PR head commit with no event filter, and `:40` calls the PR green when every run's conclusion is success/skipped/neutral. It records only `{id, name, conclusion}` (`:37`), and `name` is the workflow name `ci` for both kinds of run. A dispatch with `only=70-docs` exits 0 (`GATE-ONLY: PASS`, the implementer's own probe in the baton), so the run concludes `success` and the job posts a `gate` check on the head commit. Before this diff every green `ci` run meant the whole suite ran; after it, one cannot tell from the run, the check or `gate-logs/ci-pr-<n>.json`.
  Measured, read-only: run 42954765163 (`workflow_dispatch`, branch `fix/ci-dead-status`) and run 42954767619 (`pull_request`) both have `headSha` ed18476125d4c429da1c1aea442c297b68d1ef03, and that commit carries 3 check runs all named `gate` (`gh api repos/z0rd0n88/blast-off/commits/<sha>/check-runs`). So dispatch runs on PR heads are an existing practice here and land in the same list `ci_wait` reads. The baton sentence "Dispatch runs are not PR checks, so nothing gates on it" is contradicted by those two runs and by `lib/ci.sh:19`.
  Limits of the harm, stated exactly: a filtered green run cannot mask a red full run (`all(...)` at `:40`). It matters when it is the only run of the head (no `pull_request` run: a PR with a merge conflict, a `[skip ci]` commit, a push made with `GITHUB_TOKEN`), where the record then reads `verdict: success` and `ci PR #n at <sha>: success (ci success)` instead of `absent` ("not a pass", `lib/ci.sh:59`). `ci_check`'s exit code is the same in both cases (absent also passes), so this is an evidence-integrity loss, not a new exit-10 bypass. Branch protection is not available on this repo (`gh api .../branches/main/protection` and `.../rulesets` both return 403 "Upgrade to GitHub Pro"), so no required status check is bypassed today; if the repo ever gets one on `gate`, a filtered dispatch on the PR branch would post a green `gate` on the head commit.
- **Suggested fix:** Smallest honest option, outside the phase's five-file set so it needs the manager's call: have `ci_wait` ask for `event` too (`--json databaseId,name,conclusion,event`), record it, and not let a `workflow_dispatch` run count toward `success` (treat a head with only dispatch runs as `absent`). Independently, make the filtered run look different on GitHub (`run-name:` carrying `only`, or a job name such as `gate-only` when the input is set; note `tests/00-harness.sh:109` pins exactly one `inputs.` line and would need to move with it). At minimum correct the baton sentence and add one clause to the ci.yml header: a filtered run's check is green and is not the gate.

**M2. The new ci.yml guard ("through env alone ... and nowhere else") passes when the input is interpolated into the run script under any other spelling**

- **Location:** `tests/00-harness.sh:108-110`.
- **Description:** The guard is `grep -qE '^ +BLAST_OFF_TEST_ONLY: \$\{\{ inputs\.only \}\}$'` plus `grep -c 'inputs\.' == 1`. It only counts the literal text `inputs.`. I ran the two greps (nothing else) against copies of ci.yml with line 56 mutated, in the scratchpad. Result: 4 of 4 real injection mutants pass the guard, 2 controls fail it as intended.
  - `tests/run ${{ env.BLAST_OFF_TEST_ONLY }}` : guard PASSES (this is the most likely future slip: the env name is right there)
  - `echo "${{ inputs['only'] }}"; tests/run` : guard PASSES
  - `echo "${{ github.event.inputs['only'] }}"; tests/run` : guard PASSES
  - `echo ${{ toJSON(inputs) }}; tests/run` : guard PASSES
  - `echo "${{ inputs.only }}"; tests/run` : guard fails (control)
  - `echo "${{ github.event.inputs.only }}"; tests/run` : guard fails (control)
  Each passing mutant puts dispatcher text into shell source, which is exactly what criterion 1 forbids and what the test's failure message says it rules out. A fifth mutant, the env line moved from the `tests/run` step to the `Dependencies` step (PyYAML confirms the gate step then has no `BLAST_OFF_TEST_ONLY`), also passes; that one is the already-tracked P1R2-2 class (text, not steps) and fails safe (the whole suite runs with a `GATE:` line), so I do not raise it separately.
- **Suggested fix:** One more count on the same line: `[[ $(grep -c '\${{' "$ci") == 3 ]]`. HEAD has exactly 3 expression lines (48, 51, 70; measured with `grep -c` and the YAML parse), each already pinned by a whole-string grep, so any new `${{ ... }}` anywhere, in any spelling, turns the test red.

**M3. Pre-existing, not introduced here, but the new comments claim it closed: `tests/run <scenario-dir>` still gives a subset a `GATE: PASS` line that `blast-off receipt` accepts**

- **Location:** claims at `tests/00-harness.sh:22-23` ("one green scenario must never read as a green suite") and `tests/40-receipt-required.sh:60-61` ("so one green scenario never receipts a phase"); code at `tests/run:21,66,86-89`; reader `lib/receipt.sh:8,38`.
- **Description:** The filter path is closed; the directory-argument path is not. `gate=GATE-ONLY` is set only when `only` is non-empty (`tests/run:87`); a run on a directory holding one symlinked scenario prints `GATE: PASS passed=1 ...`. Evidence without running anything: `tests/00-harness.sh:12-13` asserts exactly `GATE: PASS passed=1 failed=0 shellcheck=skipped` for a one-scenario dir; the baton's own GREEN block is `GATE: PASS passed=4 failed=0 shellcheck=skipped` from a symlink dir of four scenarios; and without `BLAST_OFF_NO_SHELLCHECK` the same run lints the whole repo (`tests/run:66`) and prints `shellcheck=ok`, differing from the real gate only in the count. `receipt_verdict` accepts any last line starting `GATE: ` and `receipt_write` any `GATE: PASS*` (`lib/receipt.sh:8,38`; `tests/40-receipt-required.sh:41-42` even receipts a bare `GATE: PASS`). Issue 31 names this exact technique as what the session used five times. So the invariant the two comments state is false for `tests/run` as a whole; this diff neither creates nor worsens the hole.
- **Suggested fix:** Reword the two comments to "a run filtered by BLAST_OFF_TEST_ONLY" (what the code does). Closing the directory path (a non-`GATE:` verdict whenever `$DIR != $HERE`) touches the pinned fixture verdicts in `00-harness` and is a separate decision for the owner; file it rather than fold it in here.

#### LOW

**L1. Names are not validated, so control characters and option-like names reach stdout and the verdict line**

- **Location:** `tests/run:39,62,87`.
- **Description:** Splitting is on space, tab and newline only (bash resets `IFS`: `IFS=x bash -c 'printf %q "$IFS"'` prints `$' \t\n'`). Everything else is kept verbatim and echoed twice. Measured with a self-contained copy of lines 39 and 87:
  - `-n`, `-e`, `-neE` as the only name: `echo "${only[*]}"` swallows it, the verdict ends `only=` with no name (the `FAIL only -n: ...` line still names it).
  - a name made of `x`, a carriage return, `GATE:`, a no-break space (U+00A0) and `PASS`: the verdict is `GATE-ONLY: ... only=x<CR>GATE:<NBSP>PASS`; a terminal draws the text after the carriage return over the start of the line. `receipt_verdict`'s test on that string prints `refused`, so the receipt is not fooled; the run also exits 1 because the name is no scenario.
  - `$'\e[2K\rGATE:'`: escape sequences pass through raw.
  - UNREPRODUCED (runs forbidden in this review; I must not dispatch): the GitHub runner reads step output with .NET `StreamReader.ReadLine`, which ends a line at a bare CR, so `only=$'x\r::notice::injected'` should be parsed as a workflow command. Command for the dispatching unit, on a throwaway branch: `gh workflow run ci --repo z0rd0n88/blast-off --ref <branch> -f only=$'x\r::notice::injected'`. Expected if the runner splits on CR: the run fails (`FAIL only ...`) and its summary shows a notice annotation "injected"; expected otherwise: the log shows the raw text on one line. Severity stays LOW either way: a dispatch needs write access, the same actor can push a workflow, the job has `contents: read` and no secrets, so no privilege boundary is crossed.
- **Suggested fix:** One guard after the split, the same class `receipt_write` uses for phase keys (`lib/receipt.sh:21`): a name not matching `^[0-9A-Za-z._-]+$` is `FAIL only <printf %q of it>: not a scenario name` and is dropped from the list; build the tail with `printf` instead of `echo`. That removes all four cases.

**L2. A filtered run can still end in a `GATE:` line, which the spec says never happens**

- **Location:** `tests/run:30` (runs before `:39`); `docs/spec.md:216` ("ends `GATE-ONLY: PASS` or `GATE-ONLY: FAIL` ... never a `GATE:` line").
- **Description:** `no_keep` hard-codes `GATE: FAIL passed=0 failed=1 shellcheck=skipped` and exits before `BLAST_OFF_TEST_ONLY` is read. With `BLAST_OFF_TEST_ONLY=x` and a keep dir under `tests/` or one that cannot be made, the last line is a `GATE:` line and `blast-off receipt` would write a FAIL receipt for a filtered run. Fail-safe direction (FAIL only), so LOW; the spec sentence is wrong as written.
- **Suggested fix:** Move the `only` parse above the keep block and use `$gate`/`$tail` in `no_keep`, or weaken the spec to "never a `GATE: PASS` line".

**L3. A filtered run that matches no scenario uploads an archive with no scenario in it**

- **Location:** `tests/run:33,61-63`; `.github/workflows/ci.yml:62-71`.
- **Description:** The keep dir is made at `tests/run:33` before the filter, so on `only=<typo>` the run fails, `tar` succeeds on an empty `blast-off-tests/` and the upload is green with a file holding one directory entry (measured with the ci.yml tar command typed by hand on an empty dir in a private temp dir: rc 0, one member `blast-off-tests/`, 122 bytes). This is a new, easy way into the state P1R2-1 already tracks (an artifact that holds no evidence); it does not make P1R2-1's own case worse, and the run itself is red with the name printed. No change needed beyond P1R2-1's fix; recorded so the phase 1 item's reach is known.
- **Suggested fix:** None in this phase; when P1R2-1 is fixed, cover "keep dir exists but is empty".

**L4. Header, spec and input description say less than the code does**

- **Location:** `tests/run:11-15`; `docs/spec.md:216,227`; `.github/workflows/ci.yml:14`.
- **Description:** (a) "split by spaces or commas": tabs and newlines split too (measured: `$'01-a\n09-x'` and `$'01-a\t02-b'` each give 2 names). (b) "run only the named scenarios": on the real suite shellcheck still runs over all 33 files (`tests/run:66`, `$DIR = $HERE`), can fail a filtered run, and puts `shellcheck=ok` in the `GATE-ONLY:` line; only the baton says so. (c) A value of only separators (`,`, spaces) is a whole-suite run with the real `GATE:` line; the header says "empty" only (the spec row and the test at `00-harness:47-50` cover `' , '`). (d) `docs/spec.md:227`, the `40-receipt-required` row, does not name the new assertion (the baton admits this). (e) Matched scenarios run before an unknown name is reported at the end; not stated.
- **Suggested fix:** One clause each in the header; add "a filtered run's log is refused" to row 40.

**L5. Test gaps on the new behaviour**

- **Location:** `tests/00-harness.sh:25-50`; `tests/40-receipt-required.sh:62-67`.
- **Description:** (a) No case for a tab- or newline-separated value (hand-probed in the baton only); dropping `-d ''` from the `read` would lose every name after the first line with no test going red. (b) No case for a filtered run on the suite `tests/run` lives beside (`$DIR = $HERE`): the only place `GATE-ONLY:` meets the shellcheck branch is the implementer's one hand run. (c) No case for `BLAST_OFF_TEST_ONLY` together with `BLAST_OFF_TEST_KEEP`, which is the only combination CI ever uses on a dispatch (see L2 for the one place they interact). (d) Duplicate names are accepted and echoed (`only=01-a,01-a`, measured); unpinned, harmless.
- **Suggested fix:** Add `$'02-b\n01-a'` to the loop at `00-harness:33`; one `self/tests` run with `BLAST_OFF_TEST_ONLY=01-ok` asserting `GATE-ONLY:` and no `shellcheck=skipped`; one keep-plus-only run asserting only the named dir is kept.

### Validated

**Confirmed correct**

- The diff is what the brief says: read in full (186 diff lines, 5 files). `bash -n` clean on `tests/run`, `tests/00-harness.sh`, `tests/40-receipt-required.sh`; `shellcheck -S warning` (0.11.0, the pinned version) clean on the same three; bash here is 5.2.21.
- No shell or YAML injection from the input at HEAD. PyYAML parse of `.github/workflows/ci.yml`: `on.workflow_dispatch.inputs.only = {description, type: string, default: ''}`; the gate step's env is `{BLAST_OFF_TEST_KEEP: '${{ runner.temp }}/blast-off-tests', BLAST_OFF_TEST_ONLY: '${{ inputs.only }}'}`; `'${{' in run` is False for all 6 steps; exactly 3 lines hold `${{` (48, 51, 70) and exactly 1 holds `inputs.` (51). The expression result is assigned as a string value, not re-parsed as YAML or as an expression. `permissions: contents: read` unchanged, no secret referenced, no new action.
- A filtered run cannot end in a line starting `GATE: ` through the name list. `tests/run:39` splits on all whitespace: probes give n=2 for `$'01-a\n09-x'`, so no name holds a newline; `tests/run:87-91` prints `$gate:` last with `gate=GATE-ONLY` iff `${#only[@]} != 0`. The only exception is the `no_keep` early exit (L2), which prints FAIL.
- Empty and separator-only values run the whole suite with the gate's own line: probes give n=0 and `GATE:` for `''` and `' , '` under `set -euo pipefail` (no unbound-variable error on the empty array in bash 5.2); pinned by `tests/00-harness.sh:47-50`.
- Names are text, never patterns or paths. `tests/run:46` and `:62` quote `$name` and `$o` on the right of `==`; probe with `only=('*' '0?-a')` against `01-a` prints "no match" for both the membership and the `ran` test; `$o` is never used in a file name. Pinned by `tests/00-harness.sh:42-45` (`*`, `0?-a`, `../onlyfix/01-a`, `01-a.sh`).
- Odd separators fail loudly instead of being guessed: `a;b` is one name (n=1) and so reaches `FAIL only a;b: no such scenario` at `tests/run:62`; unknown names add to `failed` and force exit 1 (`:62,90-91`).
- Every reader of a verdict line: `grep -rn GATE` over `bin lib scripts templates docs README.md .github` plus `skills/` and `.claude/`. The only code that parses one is `lib/receipt.sh:8` (`[[ $v == "GATE: "* ]]`), `:31,38` (`GATE: PASS` prefix) and `:60` (`$l == "GATE: PASS"*` and equality with the log). `GATE-ONLY: ` matches none of them. `bin/blast-off:13`, `scripts/gate.sh:4`, `templates/brief.md:61,142`, `README.md:107,148`, `skills/blast-off/SKILL.md:33,85`, `.claude/big-next-job.md:5-6` are prose; `tests/51-templates.sh:100` calls `receipt_verdict` on its own fake gate. None accepts a `GATE-ONLY:` line. `lib/ci.sh` reads run conclusions, not verdict lines (M1).
- The variable is hidden from scenarios: `tests/run:40` unsets it before the loop; `onlyfix/01-a.sh` (`tests/00-harness.sh:26`) exits 1 if it is set at all, and every expected output in the block needs `PASS 01-a`.
- New assertions would go red on a revert or mutation (traced, not run): reverting `tests/run` makes `only 01-a` run all three fixtures (matches the baton's RED 1 text); a `GATE:` prefix on PASS is killed by `00-harness:31` and by `40:66` (rc 0, `phase-8.json` written); a `GATE:` prefix kept on FAIL only is killed by `00-harness:38`; dropping the unknown-name loop is killed by `:41`; set-means-filtered is killed by `:47-50`. Test 40's refusal is bound to the right reason by the `run.log` grep at `:67`, and its fixture sits inside `$JOB` so the dirty-tree check cannot produce the exit 1 instead.
- Phase 1 pins untouched: two `if: failure()` lines, one one-line `run: tar`, the two literals (`ci.yml:48,63,64,66,70`). On a filtered red run the kept tree holds only the named scenarios (`tests/run:46` skips before `mktemp`), so tar and upload behave as in phase 1; on a filtered green run neither step runs.
- The gate log the dispatcher supplied: 18 `PASS NN-` lines, 18 scenario files, last line `GATE: PASS passed=18 failed=0 shellcheck=ok`.
- Commit 5062c7d is not on any remote branch (`git branch -r --contains 5062c7d` prints nothing) and the only open PR is 34 (phase 1), so nothing in this diff has run on GitHub.

**Examined, inconclusive**

- `inputs.only` on a `pull_request` event (`ci.yml:51`): by GitHub's documented rules the `inputs` context is empty there and the expression yields `''`, which `tests/run:39` treats as unfiltered. Blocker: needs one real pull_request run of this commit; none exists. Same blocker as P1R2-3, now covering lines 12-16 and 51.
- Whether the Actions runner treats a bare CR in step output as a line end (L1, fourth bullet). Blocker: needs a dispatch, which is forbidden here; command and expected output are given.
- How GitHub resolves several same-named `gate` check runs on one commit for a required check (M1). Blocker: no branch protection exists on this plan (403 from the API), so there is nothing to observe; I measured only that 3 such check runs coexist on ed18476.
- A filtered run on the real suite dir with a keep dir (the exact CI dispatch path, `tests/run:33,46,66,87`): traced by reading and matches the baton's one hand run of `BLAST_OFF_TEST_ONLY=70-docs tests/run`; not run by me (forbidden).

**Not examined**

- `bin/blast-off` beyond its `GATE` line (13); `templates/brief.md` beyond lines 58-63 and 138-144; `tests/lib.sh` beyond `fail` and the `install_units` location; `tests/51-templates.sh` and `tests/70-docs.sh` beyond their `GATE` lines (whether they pin spec wording touched here).
- `baton-runner/br-1115-issues/phase-2/progress.md` (not read); `findings.md` read in part.
- The body of the gate log, beyond its last five lines and a count of its `PASS NN-` lines.
- Behaviour on bash older than 4.4 (`"${only[@]}"` on an empty array under `set -u` at `tests/run:61`); CI is ubuntu-24.04 and this box is 5.2.21.

**Side effect of this review (my error, not a finding about the diff)**

- I deleted a scratch directory I did not create. For the L3 probe I ran `mkdir -p <scratchpad>/rt/blast-off-tests`, the tar command, then `rm -rf <scratchpad>/rt`, assuming the name was free. It was not: `<scratchpad>/rt/blast-off-tests` already held the kept work-dir tree of phase 1's keep run (`baton-phase-1-fix-1.md:18` names that path; the tar listing showed scenario dirs of a full keep run, among them `11-unit-smoke`, `21-soft-cap`, `32-usage-per-phase`, `40-receipt-required`, `50-checkpoint-size` and `60-preflight`, about 2,100 entries, 311,979 bytes when packed). The tree and any `blast-off-tests.tgz` beside it are gone and cannot be restored. `<scratchpad>` is `/tmp/claude-1000/-home-alex-blast-off--claude-worktrees-pending-items-53932d/60b15296-819e-491a-8ffe-34b3bd988f86/scratchpad`. Nothing in the repo, the worktree, `~/.claude`, `~/.config` or any other scratch entry was touched (`back`, `keep`, `copy`, `c1.yml` to `c8.yml` and the rest are still listed). The phase 1 record that cites the run, `fix-phase-1-iter-1/tests-run-keep.log`, lives in the worktree and is intact. If a parallel reviewer reads `<scratchpad>/rt` from about 18:28 PST on (the scratchpad's mtime after the deletion) it will find it missing. I redid the probe in a `mktemp -d` dir of my own and removed only that.

### Confidence

High on the injection, splitting, verdict-line and reader findings (each measured or traced to a line); medium on M1's GitHub-side consequences and on L1's runner behaviour, which one pushed branch with a pull_request run, one filtered dispatch and the CR dispatch above would settle.
