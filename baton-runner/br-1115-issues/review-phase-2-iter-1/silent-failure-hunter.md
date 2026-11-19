### Summary

I reviewed commit 5062c7d (the five files of `git diff feat/br-1115-issues/phase-1...HEAD`) against issue 31, statically: every listed file read in full, `bash -n` and `shellcheck -S warning` (0.11.0) on the three scripts, a PyYAML parse of `ci.yml`, read-only `gh`, and self-contained bash probes of the splitting and matching expressions (bash 5.2.21). No scenario, `tests/run`, `scripts/gate.sh` or `bin/blast-off` was run. The receipt path does what the issue asked: `lib/receipt.sh:8` needs a last line starting `GATE: `, a filtered run prints `GATE-ONLY: `, and neither `receipt_write` nor `receipt_check` accepts it. Names are data everywhere (no glob, no path, no eval) and the input reaches the shell through `env:` only. No CRITICAL or HIGH finding. What the diff leaves open is the other half of "one green scenario must never read as a green suite": a filtered pass still exits 0 and is a green `ci` run, and the readers that look at status or conclusion instead of the verdict line (`lib/ci.sh`, `scripts/gate.sh`) cannot tell it from the gate. The work note's sentence "Dispatch runs are not PR checks, so nothing gates on it" is contradicted by `lib/ci.sh:19` and by this repo's own run history. The rest is test gaps (six mutants I can show survive without a run) and small doc and output mismatches.

### Findings

#### CRITICAL

None.

#### HIGH

None.

#### MEDIUM

- **Title:** A green filtered dispatch is recorded by `blast-off ci-wait` as CI success for the PR head
- **Location:** `.github/workflows/ci.yml:11-16,51,56` (new); reader `lib/ci.sh:19,29,35-41`; claim in `baton-runner/br-1115-issues/baton-phase-2-work.md:134`
- **Description:** A filtered pass exits 0 (`tests/run:88-89`), so the `tests/run` step and the `ci` run conclude `success`. `ci_wait` lists runs with `gh run list --commit "$sha"` (`lib/ci.sh:19,29`): no event filter, no workflow filter, and it records only `{id, name, conclusion}` (`:37`). A dispatch on a PR branch has the PR head as its head sha. Measured on this repo (`gh run list --repo z0rd0n88/blast-off --json event,headSha,conclusion -L 40`): 24 runs, 13 `workflow_dispatch`, 11 `pull_request`; 3 head shas carry both events (ed1847612, the head of merged PR 28, has 1 `pull_request` run and 2 dispatch runs; acf9051a2 has 1 and 3; 82cbae89d has 1 and 1). The query `ci_wait` itself makes, run for PR 28's head (`gh run list --repo z0rd0n88/blast-off --commit ed18476125d4c429da1c1aea442c297b68d1ef03 --limit 100 --json databaseId,event,conclusion,name`), returns 3 runs, all named `ci`, all `success`: 42954767619 (`pull_request`), 42954765163 and 42954762391 (both `workflow_dispatch`). So dispatch runs are listed for PR heads, and the work note's "Dispatch runs are not PR checks, so nothing gates on it" is false for `ci-wait`. Before this commit a green dispatch on a head sha was the whole suite. After it, `only=70-docs` on the head gives a run named `ci` with conclusion `success`, and `gate-logs/ci-pr-<n>.json` reads `verdict: success` with nothing to say one scenario ran. Reach: it changes the outcome only when the PR's own `pull_request` run is missing for that head (a PR with merge conflicts, a `[skip ci]` head commit, a head pushed with `GITHUB_TOKEN`: GitHub's documented behaviour, not verified in this session); a red `pull_request` run still makes the record `failure` (`:40`). In that case the record moves from `absent` (logged "no CI runs (absent, not a pass)", `lib/ci.sh:59`) to `success`, on one scenario. I rate it MEDIUM for that narrow reach, not because I could not run it. The other direction is not new in kind but is now cheaper: a red diagnostic dispatch or a typo name on a PR head is one more red run of that head, so `ci-wait` exits 10 while the PR's own run is green (history: 4 red dispatch runs on `fix/ci-dead-status` shas). No required status check is at risk today: `gh api repos/z0rd0n88/blast-off/branches/main/protection` and `.../rulesets` both answer 403 "Upgrade to GitHub Pro", so none can be configured. The listing half is measured above. The verdict half is UNREPRODUCED (runs forbidden in this review, and it needs a dispatch, which I may not make): on a PR head with no `pull_request` run, `gh workflow run ci.yml --ref <pr-branch> -f only=70-docs`, wait for green, then `blast-off ci-wait <job-dir> <pr>`; expected exit 0, a run.log line `ci PR #<pr> at <sha>: success (ci success)` and `"verdict": "success"` in `gate-logs/ci-pr-<pr>.json`.
- **Suggested fix:** Make the filtered run tellable at the level `ci-wait` reads. Smallest: `ci_wait` asks for `event` and drops (or records and does not count) `workflow_dispatch` runs. Alternative: a `run-name` or job name that differs when `only` is set, and `ci_wait` refusing that name. Either way correct the work note's claim.

- **Title:** A filtered pass exits 0, and `scripts/gate.sh` inherits an ambient `BLAST_OFF_TEST_ONLY`
- **Location:** `tests/run:39,88-89`; `scripts/gate.sh:4,10`; `.claude/big-next-job.md:5`
- **Description:** The filter is an environment variable read by every `tests/run`. `scripts/gate.sh` ("the objective gate a zord-baton-runner review unit runs") runs `tests/run 2>&1 | tee` and "exits with tests/run's status" (`:4,10`); it does not clear the variable. With `BLAST_OFF_TEST_ONLY=70-docs` left exported in a shell after a diagnosis, the gate script runs one scenario and exits 0. The last line says `GATE-ONLY: PASS`, but any consumer that reads the status passes it; `.claude/big-next-job.md:5` defines the gate as "`GATE: PASS ...` (exit 0)". The receipt reader is safe; the status readers are not. `scripts/gate.sh:4` ("the last line is its GATE: PASS|FAIL verdict") is no longer always true. UNREPRODUCED (runs forbidden in this review). Command: `BLAST_OFF_TEST_ONLY=70-docs scripts/gate.sh /tmp/x; echo $?`; expected last line `GATE-ONLY: PASS passed=1 failed=0 shellcheck=ok only=70-docs` and `0`. The work note records the same shape for `tests/run` itself (`baton-phase-2-work.md:116-122`, exit 0).
- **Suggested fix:** `unset BLAST_OFF_TEST_ONLY` at the top of `scripts/gate.sh` (it is the gate, never a diagnosis), or have it fail when the last line is not a `GATE: ` line. One line; `scripts/gate.sh` is outside this phase's target set, so it needs the owner's say.

- **Title:** No test has a newline or tab in a name list, so dropping `-d ''` survives, and that mutant skips named scenarios in silence
- **Location:** `tests/run:39`; `tests/00-harness.sh:30-50`
- **Description:** The work note gives the reason for `read -rd ''`: "a name on a second line is not dropped silently" (`baton-phase-2-work.md:59`). Nothing pins it. I ran all 12 name lists the harness block uses through the split with and without `-d ''`: 12 of 12 give the same array. Without `-d ''`, `$'01-a\n03-c'` yields 1 name (`01-a`), so the run would print `GATE-ONLY: PASS passed=1 ... only=01-a` and never run or mention `03-c`. The only evidence for newline handling is a hand probe in the work note.
- **Suggested fix:** One more case in the loop at `tests/00-harness.sh:33`: `$'02-b\n01-a'` (and `$'02-b\t01-a'`), same expected output.

- **Title:** The new `ci.yml` pin binds text, not steps, and misses three ways the input can go wrong (P1R2-2, extended to a new line)
- **Location:** `tests/00-harness.sh:108-110`; `.github/workflows/ci.yml:12-16,51`
- **Description:** This is the known P1R2-2 class, reported here because this commit adds a pin of the same kind and the comment above it claims more than it checks ("reaches the gate through env alone"). The pin is one whole-line regex plus `grep -c 'inputs\.'` equal to 1 (measured: 1, at `ci.yml:51`). It still passes when: (a) the `workflow_dispatch.inputs.only` declaration (`ci.yml:12-16`) is deleted, since `inputs:` does not match `inputs\.`; criterion 1's "has a `workflow_dispatch` input `only`" is then pinned by no test, and a dispatch that passes `only` is refused by GitHub (documented behaviour for an undeclared input, not verified in this session) while the suite stays green; (b) the env line sits on another step, so the gate step never sees the input and a dispatch with `only=x` runs the whole suite (fail-safe, but the input is dead); (c) the value is written into script text without the string `inputs.`: `${{ env.BLAST_OFF_TEST_ONLY }}`, `${{ inputs['only'] }}` or `${{ github.event.inputs['only'] }}` in a `run:` line. Case (c) is the injection the pin exists to stop. It also fails falsely if a comment ever says `inputs.only`.
- **Suggested fix:** Fold into the P1R2-2 fix (assert per step). Until then: add `grep -qx '      only:' "$ci"` for the declaration, and count `\$\{\{[^}]*(inputs|BLAST_OFF_TEST_ONLY)` occurrences instead of `inputs\.`.

#### LOW

- **Title:** A filtered run with a refused keep dir prints `GATE: FAIL`, which the spec says never happens
- **Location:** `tests/run:30` (hard-coded line, runs before the filter is parsed at `:39`); `docs/spec.md:216` ("never a `GATE:` line"); `tests/run:12-14`
- **Description:** `no_keep` exits with `GATE: FAIL passed=0 failed=1 shellcheck=skipped` whatever `BLAST_OFF_TEST_ONLY` holds. `blast-off receipt` on that log writes a FAIL receipt (`lib/receipt.sh:8,31`), the case the work note says the prefix exists to prevent "for PASS and FAIL alike" (`baton-phase-2-work.md:25`). Fail-closed, never a PASS; the spec sentence is wrong for this path and no test combines the two variables.
- **Suggested fix:** Parse `only` before the keep block and use `$gate` in `no_keep`, or soften the spec to "never a `GATE: PASS` line".

- **Title:** A dispatch whose names match nothing ends red with a green upload of an empty archive (a new route, not P1R2-1's missing dir)
- **Location:** `tests/run:33,61-63`; `.github/workflows/ci.yml:62-71`
- **Description:** `tests/run:33` makes the keep dir before any scenario. With `only=30-pause-limit` (a typo) no scenario runs, `FAIL only ...` is printed, exit 1, and both `if: failure()` steps run. Measured on an empty `blast-off-tests` dir with the tar line as written: exit 0, 123 bytes, 1 member (`blast-off-tests/`). The upload finds the file and goes green; the artifact `blast-off-tests` holds nothing. The step log does name the cause. Locally, a persistent keep dir also keeps stale `<dir>/<name>` dirs of scenarios the filter skipped, beside the fresh ones.
- **Suggested fix:** Accept and say so in the `ci.yml` comment, or fix with P1R2-1 (no upload when the keep dir is empty).

- **Title:** `only=` in the verdict line is blank when the single name is `-n`, `-e`, `-E` or a mix
- **Location:** `tests/run:87` (`echo "${only[*]}"`)
- **Description:** Measured: names `-n`, `-e`, `-E`, `-neE` each give `tail=< only=>`; `echo` takes the name as its option. The `FAIL only -n: no such scenario` line is still printed and the run still fails, so it is loud; only the verdict line loses the name.
- **Suggested fix:** `printf '%s' "${only[*]}"`.

- **Title:** Control characters in a name are printed raw into the log
- **Location:** `tests/run:62,87`
- **Description:** Measured: `$'01-a\r'` stays one name with the CR inside (CR is not in IFS). It fails by name, so it is loud, but the CR (or an ESC sequence) goes to the step log unescaped in both the `FAIL only` line and the verdict line, where it can overwrite what a reader sees. It cannot forge a receipt: a name cannot hold a space or a line feed, and `lib/receipt.sh:7-8` needs `GATE: ` at the start of a line-feed-delimited line. Whether a lone CR starts a new line for the Actions runner's workflow-command parser (`::error::`, `::add-mask::`) is unverified. Only someone with write access can dispatch.
- **Suggested fix:** Refuse a name that is not `^[0-9A-Za-z._-]+$` with `FAIL only <printf %q of it>`, as `receipt_write` does for a phase key (`lib/receipt.sh:21`).

- **Title:** A loosened unmatched-name check would survive the tests
- **Location:** `tests/run:62`; `tests/00-harness.sh:40-45`
- **Description:** The five unmatched names the tests use (`09-nope`, `*`, `0?-a`, `../onlyfix/01-a`, `01-a.sh`) are all rejected by a substring check `*"$o"*` too (measured, 5 of 5). No test names a prefix or part of a scenario that ran; `01` is accepted by the loosened check and rejected by the real one. A mutant that drops the two spaces at `:62` would let a truncated name pass in silence beside a full one.
- **Suggested fix:** Add `'01-a 01'` (expect `FAIL only 01`) to the loop at `tests/00-harness.sh:42`.

- **Title:** Shellcheck on a filtered real-suite run is a decision no test or doc states
- **Location:** `tests/run:66`; `tests/run:11-15`; `docs/spec.md:216`; decision at `phase-2/task_plan.md:18`
- **Description:** Every filtered test run uses a fixture dir with `BLAST_OFF_NO_SHELLCHECK=1`, so `shellcheck=skipped` in all of them. A mutant that skips the lint when `only` is set survives. Neither the header nor the spec row says a filtered run of the real suite still lints all 33 files and can end `GATE-ONLY: FAIL` on lint alone.
- **Suggested fix:** One clause in the header. A test needs the `self/` copy at `tests/00-harness.sh:89-94` run once with `BLAST_OFF_TEST_ONLY=01-ok`, expecting `shellcheck=fail` on a `GATE-ONLY: FAIL` line.

- **Title:** `|| true` after `read` swallows every failure of that line, not only the expected end-of-input status
- **Location:** `tests/run:39`
- **Description:** If the here-string redirect itself fails, `read` never runs and `only` stays a scalar. On bash 5.2.21 with `set -u`, `${#only[@]}` on a scalar prints `only: unbound variable` (measured). The run then misbehaves at `:46` instead of stopping with a reason. Reaching it needs the here-string to fail (fd exhaustion; short here-strings use a pipe), so this is close to unreachable.
- **Suggested fix:** `|| [ $? -eq 1 ]`, or `read -ra only <<< "$(tr ',\n' '  ' <<< "$only")"` with no status to swallow.

- **Title:** Docs outside the five files still say there are two verdicts; the separators are under-described
- **Location:** `README.md:107,148`; `templates/brief.md:61`; `scripts/gate.sh:4`; `.claude/big-next-job.md:5`; `tests/run:11-12`; `docs/spec.md:216,227`; `ci.yml:14`
- **Description:** `README.md:148` says `tests/run` "ends GATE: PASS or GATE: FAIL"; the same holds for the other four places. Criterion 4 names only the spec and the header, so this is not a miss against the criteria, but a reader of the README does not learn that the variable exists. The header, the spec row and the input description say "spaces or commas"; tabs and newlines split too (measured: `$'01-a\t02-b'` and `$'01-a\n09-x'` give 2 names each; the work note says "spaces, commas and newlines"). `docs/spec.md:227` (the `40-receipt-required` row) does not name the new assertion; the work note admits it.
- **Suggested fix:** One clause in `README.md:148`; "split by spaces, commas or line breaks" in the three places; add "a filtered run's log is refused" to row 40.

### Validated

- **Confirmed correct:**
  - The receipt refuses a filtered log. `lib/receipt.sh:8` requires `"GATE: "*`; `GATE-ONLY: ` does not match; `receipt_write` refuses at `:24` before anything is written; `receipt_check:60` requires `$l == "GATE: PASS"*`. `tests/run:86-87` sets `gate=GATE-ONLY` whenever the name array is non-empty, for PASS and FAIL lines alike (`:89,91`).
  - No other verdict-line reader accepts `GATE-ONLY:`. `command grep -rnE 'GATE|verdict'` over `bin lib scripts templates docs README.md .github`: the only code that parses the line is `lib/receipt.sh:8,31,38,60`; `lib/ci.sh` reads run conclusions, not the line; `tests/51-templates.sh:100` calls `receipt_verdict`.
  - No shell or YAML injection through `only`. PyYAML parse: the gate step's env is `{'BLAST_OFF_TEST_KEEP': ..., 'BLAST_OFF_TEST_ONLY': '${{ inputs.only }}'}`; `grep -c 'inputs\.' ci.yml` = 1 (line 51); the `run:` script has 0 changed lines in the diff. In `tests/run` the value meets only `read -a` (`:39`), the left side of `[[ == ]]` (`:46`), a quoted pattern part (`:62`) and `echo` (`:62,87`). Probe: `*`, `0?-a`, `a;b$(id)` and a backquoted `id` each stay one literal name; `[[ " * " == *" 01-a "* ]]` and `[[ " 01-a " == *" 0?-a "* ]]` are both false.
  - Empty and separator-only values run the whole suite with the gate's own line. Probe: `''` and `' , '` give 0 names; `declare -p only` after the read is `declare -a only=()`; an empty-array loop under `set -u` is fine on bash 5.2.21. Pinned by `tests/00-harness.sh:47-50`.
  - Several names and odd separators. Probe: `'02-b, 01-a,'` gives `[02-b] [01-a]` and `only=02-b,01-a`; tab and newline split.
  - An unknown name fails loudly, also when it is the only name: `tests/run:61-63` adds to `failed` before the zero-scenario check at `:64`, and exit 1 at `:91`.
  - The variable is hidden from scenarios (`tests/run:40`), for the empty value too: fixture `01-a` (`tests/00-harness.sh:26`) tests `${BLAST_OFF_TEST_ONLY+x}` and must pass in the `''` case at `:47-50`.
  - The harness assertions compare literally: `only_out` quotes `"$2"` (`tests/00-harness.sh:29`), so the `*` case at `:42-45` is not a glob match; stderr is in the compared text (`run_gate`, `:10`).
  - Reverting `tests/run` turns both tests red (the work note's RED 1 matches the code: unfiltered output differs at `tests/00-harness.sh:31`; `receipt` exits 0 at `tests/40-receipt-required.sh:66`). A mutant printing `GATE: ONLY ...` is killed by `[ ! -e phase-8.json ]` at `:66`, since a FAIL receipt would be written.
  - Test 40's new block does not call `install_units` and keeps its fixture inside the job dir (`:62`), which `receipt_write` excludes from the dirty check (`lib/receipt.sh:26-27`).
  - Phase 1's keep, tar and upload on an ordinary filtered run: the keep move (`tests/run:56-59`) sits after the filter's `continue` (`:46`), so only the named scenarios' work dirs are kept, each as `<dir>/<name>` as before; a skipped scenario makes no work dir (`mktemp` at `:48` is after `:46`). Both `if: failure()` steps are unchanged, so a green filtered run uploads nothing and a red one uploads the named scenarios' dirs. The zero-scenario case is the LOW finding above.
  - Phase 1's pins are untouched: 2 lines `if: failure()`, one `run: tar` line, both literals present (PyYAML step list; `ci.yml:48,63,64,66,70`). The commit changes only the 5 named tracked files plus baton notes (`git diff --stat`); `lib/receipt.sh` is unchanged.
  - `bash -n tests/run` passes; `shellcheck -S warning` (0.11.0) on `tests/run`, `tests/00-harness.sh`, `tests/40-receipt-required.sh` is clean.
  - The dispatcher's gate log ends `GATE: PASS passed=18 failed=0 shellcheck=ok` (`gate-phase-2-iter-1/tests-run.log`, last line).

- **Examined, inconclusive:**
  - `${{ inputs.only }}` on a `pull_request` event (`ci.yml:51`): I expect the empty string, and `tests/run` handles a set-but-empty value. It needs a run on GitHub to confirm; none of this workflow's new lines has run there.
  - Whether a lone CR in a name starts a workflow-command line in the Actions step log (`tests/run:62,87`): needs a dispatch with a CR in the input, or the runner's source.
  - Whether the dispatch form or `gh workflow run -f` can deliver a newline or tab in `only`: the split handles both; the delivery side needs GitHub.
  - The `ci-wait` and `scripts/gate.sh` findings are traced by reading (`lib/ci.sh:19-41`, `scripts/gate.sh:10`); the run listing for a PR head is measured, the resulting record and exit status are not executed; commands and expected output are in each finding.
  - When GitHub starts no `pull_request` run for a head (merge conflict, `[skip ci]`, a `GITHUB_TOKEN` push): taken from GitHub's documentation, not observed here; the first MEDIUM's reach rests on it.
  - The exact text of `FAIL only <name>: no such scenario in $PWD/onlyfix` against `$DIR` when `TMPDIR` is a symlinked path (`tests/00-harness.sh:41`, `tests/run:21`): the one full gate run passed, a symlinked `TMPDIR` was not tried.

- **Not examined:**
  - How the zord-baton-runner plugin reads `scripts/gate.sh` (status or last line): it lives under `~/.claude`, which I may not read.
  - `tests/70-docs.sh` and `tests/51-templates.sh` beyond their `GATE` lines; `lib/chain.sh`, `lib/checkpoint.sh`, `lib/units.sh`, `lib/usage.sh`, `lib/preflight.sh`, `lib/jev.sh`, `lib/child.sh` (no verdict-line reader by grep, not read in full).
  - `templates/brief.md` beyond lines 59-62 and 138-144.
  - The other reviewers' files in `review-phase-2-iter-1/` (left unread to stay independent).

### Confidence

High for the receipt path, the injection result and the surviving-mutant claims (each traced or probed with numbers); medium for the `ci-wait` and `scripts/gate.sh` findings until the dispatching unit runs the two commands given, and one real dispatch with `only` set on GitHub would settle the three inconclusive items.
