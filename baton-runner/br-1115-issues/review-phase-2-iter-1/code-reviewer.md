### Summary

I reviewed commit 5062c7d (`git diff feat/br-1115-issues/phase-1...HEAD`, 5 tracked files: `.github/workflows/ci.yml`, `docs/spec.md`, `tests/00-harness.sh`, `tests/40-receipt-required.sh`, `tests/run`) against issue 31, statically only: full reads of the five files plus `lib/receipt.sh`, `lib/ci.sh`, `scripts/gate.sh`, `tests/lib.sh`, the brief template lines, the work note, the task plan and the phase 1 digest; `bash -n`; shellcheck 0.11.0; a PyYAML parse; read-only `gh`; and standalone bash probes that execute no repo file. The four acceptance criteria hold on the code as written: the input reaches `tests/run` only through `env:`, names are compared as text, an unknown name fails by name, a filtered verdict starts `GATE-ONLY: ` and every reader in `lib/receipt.sh` refuses it. I found no CRITICAL or HIGH defect. The open points are three MEDIUM items: `blast-off ci-wait` reads a filtered dispatch run as CI of the PR head (the work note's claim that nothing gates on a dispatch run is false for this repo), a filtered pass exits 0 so exit-status readers such as `scripts/gate.sh` accept it, and the workflow half of criterion 1 is pinned by one text line that survives deleting the input declaration. The rest are LOW: one path where a filtered run still prints `GATE: FAIL`, a blank `only=` for the name `-n`, unpinned newline handling and lint behaviour, and doc drift.

### Findings

#### CRITICAL

None.

#### HIGH

None.

#### MEDIUM

- **Title:** `blast-off ci-wait` counts a filtered dispatch run as CI of the PR head; the work note's "Dispatch runs are not PR checks, so nothing gates on it" is false
- **Location:** `.github/workflows/ci.yml:12-16,51` (the change); reader `lib/ci.sh:19,29,36-40` (unchanged); claim at `baton-runner/br-1115-issues/baton-phase-2-work.md:134` ("Open questions / risks", second bullet).
- **Description:** `ci_wait` lists `gh run list --commit "$sha"` with no event filter and records only `id`, `name`, `conclusion` (`lib/ci.sh:36-37`). Measured on this repo: `gh run list --repo z0rd0n88/blast-off --commit ed18476125d4c429da1c1aea442c297b68d1ef03 --json databaseId,event,name,conclusion` returns 3 runs for one PR head: 1 `pull_request` (42954767619) and 2 `workflow_dispatch` (42954765163, 42954762391), all named `ci`. Before this diff every `ci` run on a head was the whole suite; after it a dispatch run can be one scenario and still conclude `success`. Three consequences, traced through the jq at `lib/ci.sh:36-40`:
  1. On a head with no `pull_request` run (expected GitHub behaviour, not measured here: none starts for a PR with a merge conflict or for a head commit carrying `[skip ci]`), one green `only=70-docs` dispatch turns the record from `absent` (ci-wait exit 10, "absent checks are not a pass") into `success` (exit 0). The record `{"name":"ci","conclusion":"success"}` cannot be told from the full gate. This is the receipt hole of issue 31 again, on the second machine reader of a gate result.
  2. A green filtered run cannot mask a red `pull_request` run: the verdict needs `all(...)` runs green. Confirmed correct.
  3. A red filtered run dispatched on a PR head (diagnosing a failing scenario on a branch is this input's stated use) makes the verdict `failure`, so `ci-wait` exits 10 and `done` is refused until the head moves or the run is deleted. A red full dispatch did the same before; this input makes such runs routine.
- **Suggested fix:** Pick one. (a) In `lib/ci.sh`, read `event` in the two `gh run list` calls and skip, or record and flag, `workflow_dispatch` runs; this file is outside the phase's target set and needs the owner's confirmation. (b) Give a filtered run a distinct `run-name:` built from the input so a person reading the run list can tell it apart; this alone does not change the record, because `ci_wait` stores `name`, which is the workflow name (`ci` for all three runs measured above), so `lib/ci.sh` would also have to read the title or the event; the pin at `tests/00-harness.sh:109` (`inputs\.` occurs once) must change with it. (c) At least state in the `ci.yml` header and `docs/spec.md` that `ci-wait` reads dispatch runs of a PR head, and delete the false sentence from the work note.

---

- **Title:** A filtered pass exits 0, and `scripts/gate.sh` passes both the environment and the exit status through
- **Location:** `tests/run:88-89`; `scripts/gate.sh:4,10` (unchanged reader).
- **Description:** Criterion 2 is met for readers of the line. Readers of the status are not covered. `scripts/gate.sh:10` runs `tests/run 2>&1 | tee` with the caller's environment and exits with its status; nothing clears `BLAST_OFF_TEST_ONLY`. With the variable left exported in the launching shell after a diagnosis, the baton-runner's "objective gate" runs the named scenarios only, exits 0, and its log ends `GATE-ONLY: PASS`; the header at `scripts/gate.sh:4` ("the last line is its GATE: PASS|FAIL verdict") is then wrong. The `blast-off receipt` path fails closed in the same situation (the child's log is refused), so the gap is `gate.sh` and the CI check colour only. Not reproduced by a run (runs forbidden in this review). Command for the dispatching unit, alone on the box: `BLAST_OFF_TEST_ONLY=70-docs scripts/gate.sh "$(mktemp -d)"; echo "rc=$?"`; expected last lines `GATE-ONLY: PASS passed=1 failed=0 shellcheck=ok only=70-docs` and `rc=0`.
- **Suggested fix:** `env -u BLAST_OFF_TEST_ONLY tests/run` in `scripts/gate.sh` (one line, outside the target set, needs confirmation), or have `gate.sh` fail when the last line does not start `GATE: `. If neither, name the limit in the `tests/run` header: the exit status of a filtered run is not a gate result.

---

- **Title:** The workflow half of criterion 1 is pinned by one text line; the `only` input declaration is not pinned at all
- **Location:** `tests/00-harness.sh:108-110`
- **Description:** The pin is `grep -qE '^ +BLAST_OFF_TEST_ONLY: \$\{\{ inputs\.only \}\}$'` plus `grep -c 'inputs\.' == 1`. Mutants of `ci.yml`, walked through those two greps (not run):
  - Delete `ci.yml:12-16` (the `inputs: only:` block): line 51 still matches, the count is still 1, the test passes. The dispatch then has no `only` input and criterion 1 is gone. Survives.
  - Move line 51 into another step's `env:`: passes; `tests/run` never sees the filter. Survives. This extends the phase 1 open item "the ci.yml test binds text, not steps".
  - Put `${{ inputs['only'] }}`, `${{ github.event.inputs['only'] }}`, `${{ toJSON(inputs) }}` or `${{ env.BLAST_OFF_TEST_ONLY }}` into a `run:` text: none contains `inputs.`, the count stays 1, the test passes. Each writes the input into script text, which is the injection the failure message says cannot happen ("and nowhere else"). Survives.
  - A comment that mentions `inputs.only` anywhere in the file: count 2, false red.
  - Killed, confirmed by trace: the env line commented out (the regex is anchored), `${{ inputs.only }}` or `${{ github.event.inputs.only }}` in a `run:` text (count 2).
- **Suggested fix:** Pin the declaration (`grep -qx '      only:' "$ci"`), count `inputs` without the dot (2 lines today: `ci.yml:12` and `:51`), and reject `env.BLAST_OFF_TEST_ONLY`. A per-step check from parsed YAML closes the rest together with the phase 1 item.

#### LOW

- **Title:** A refused keep dir prints `GATE: FAIL` on a filtered run; the spec says a filtered run never ends in a `GATE:` line
- **Location:** `tests/run:30` against `:39` and `:86-87`; `docs/spec.md:215` ("never a `GATE:` line")
- **Description:** `no_keep` hard-codes `GATE: FAIL passed=0 failed=1 shellcheck=skipped` and exits at line 30, nine lines before the filter is parsed. Trace: `BLAST_OFF_TEST_ONLY=01-a BLAST_OFF_TEST_KEEP=tests/kept tests/run` ends in `GATE: FAIL ...`, and `blast-off receipt` would write a FAIL receipt for that log instead of refusing it. Fail-safe, no test covers the combination, and CI's keep dir can always be made.
- **Suggested fix:** Parse `only` before the keep block and use `$gate` and `$tail` in `no_keep`, or weaken the spec sentence.

---

- **Title:** A sole name `-n`, `-e` or `-E` gives an empty `only=` in the verdict line
- **Location:** `tests/run:87` (`echo "${only[*]}"`)
- **Description:** Probe with the same two lines of code: input `-n` gives 1 name and tail `''`; input `-e` the same. The verdict reads `GATE-ONLY: FAIL passed=0 failed=1 shellcheck=ok only=`. The `FAIL only -n: ...` line above it still names the value.
- **Suggested fix:** `printf '%s' "${only[*]}"`.

---

- **Title:** Newline and tab separators are implemented, undocumented and unpinned
- **Location:** `tests/run:39` (comment "-d '': every line"); docs at `tests/run:11-12`, `docs/spec.md:215`, `ci.yml:14` say "spaces or commas"
- **Description:** Probe: `$'01-a\n09-x'` and `$'01-a\t02-b'` each split into 2 names. None of the 12 filter values in `tests/00-harness.sh:30-50` holds a newline or a tab, so the mutant that drops `-d ''` survives. Its effect is silent: names after the first line are dropped and the run passes having run fewer scenarios than asked, which is the direction the unknown-name rule exists to stop. The work note records a hand probe only.
- **Suggested fix:** Add `$'02-b\n01-a'` to the loop at `tests/00-harness.sh:33`; write "spaces, commas or line breaks" in the header.

---

- **Title:** "Shellcheck still runs on a filtered run of the real suite" is unpinned
- **Location:** `tests/run:66`; decision in `phase-2/task_plan.md`
- **Description:** Every filtered run in the tests uses a fixture dir with `BLAST_OFF_NO_SHELLCHECK=1`, so `shellcheck=skipped` either way. A mutant that skips the lint when `only` is set passes both scenarios.
- **Suggested fix:** In the `self/` block (`tests/00-harness.sh:89-94`), one run `BLAST_OFF_TEST_ONLY=01-ok self/tests/run`, expecting `GATE-ONLY: FAIL passed=1 failed=1 shellcheck=fail only=01-ok`.

---

- **Title:** The whole-word match of the unknown-name check is unpinned
- **Location:** `tests/run:62`
- **Description:** Mutant `*" $o "*` to `*"$o"*`: each unknown name in the tests (`09-nope`, `*`, `0?-a`, `../onlyfix/01-a`, `01-a.sh`) is compared with a `ran` that does not contain it as a substring, so every expected output is unchanged and the mutant survives. With it, `only='01-a 1-a'` would pass. The sibling mutant at `:46` is killed (`01-a.sh` would print `PASS 01-a`).
- **Suggested fix:** Add `'01-a 1-a'` beside `'01-a 09-nope'`, expecting `FAIL only 1-a: ...`.

---

- **Title:** A run in which no scenario ran uploads an archive with nothing in it
- **Location:** `tests/run:33` (the keep dir is made before any scenario); `ci.yml:62-71`; header `ci.yml:4-5`
- **Description:** With only unknown names the keep dir exists and is empty. Probe on a scratch dir: `tar -C rt -czf rt/blast-off-tests.tgz blast-off-tests` exits 0 and makes a 122-byte archive with one member, `blast-off-tests/`; the upload then goes green. This is a second route to the outcome of the phase 1 open item "empty archive still uploads green"; it does not change that item's own path (a missing dir, tar exit 2). The header sentence "every scenario's work dir" is also only true of an unfiltered run.
- **Suggested fix:** Nothing beyond the phase 1 fix; one clause in the `ci.yml` header.

---

- **Title:** A keep dir reused by a filtered local run holds stale entries from an earlier run beside the fresh ones
- **Location:** `tests/run:56-59`; header `tests/run:9`
- **Description:** Only `<dir>/<name>` of the scenarios that ran is replaced. CI is unaffected (a fresh `runner.temp`).
- **Suggested fix:** One header clause.

---

- **Title:** Names are printed raw: a trailing carriage return or a no-break space stays part of the name
- **Location:** `tests/run:62,87`
- **Description:** Probe: `$'01-a\r'` is 1 name `$'01-a\r'`; a no-break space joins two names into one. Both fail by name, so nothing passes silently, but the `FAIL only ...` line renders misleadingly (the CR returns the cursor) and escape bytes reach the log. Only someone with write access can dispatch.
- **Suggested fix:** `printf 'FAIL only %q: no such scenario in %s\n'`, or strip `\r` when splitting.

---

- **Title:** Docs outside the two named files still say `tests/run` ends in `GATE: PASS` or `GATE: FAIL` without condition
- **Location:** `docs/spec.md:24` (row K6), `README.md:148`, `.claude/big-next-job.md:5-6`, `scripts/gate.sh:4`; `docs/spec.md:227` (the `40-receipt-required` row)
- **Description:** Criterion 4 names `docs/spec.md` and the `tests/run` header, and both are met (`spec.md:206-207,215`, `tests/run:11-16`). The four lines above describe every `tests/run` as ending in a `GATE:` line. The spec row of test 40 does not name its new assertion (the work note says so). The header does not say a value of only separators runs the whole suite; the spec row does not either ("set but empty").
- **Suggested fix:** One clause in each, or accept.

---

- **Title:** The comment in test 40 claims more than the change delivers
- **Location:** `tests/40-receipt-required.sh:60-61` ("so one green scenario never receipts a phase")
- **Description:** `BLAST_OFF_NO_SHELLCHECK=1 tests/run <dir with one symlink>` still ends `GATE: PASS passed=1 failed=0 shellcheck=skipped` (pinned at `tests/00-harness.sh:12-13`), and `lib/receipt.sh:8` accepts that line. This route predates the diff, issue 31 names it as the local way to run one scenario, and the diff does not worsen it.
- **Suggested fix:** Narrow the comment to the `BLAST_OFF_TEST_ONLY` route.

---

- **Title:** Naming nits in the new lines
- **Location:** `tests/run:39,86`
- **Description:** `only` is assigned as a string and re-read as an array in one line; a variable is called `tail`. Both work (probed); both slow a reader.
- **Suggested fix:** `suffix` for `tail`; optional.

### Validated

**Confirmed correct**

- The input cannot become shell or YAML. PyYAML parse of `ci.yml`: `workflow_dispatch.inputs.only = {description, type: string, default: ""}`; the gate step's env is `{BLAST_OFF_TEST_KEEP: '${{ runner.temp }}/blast-off-tests', BLAST_OFF_TEST_ONLY: '${{ inputs.only }}'}`; the diff adds no line to any `run:` block. `grep -c 'inputs\.' ci.yml` = 1 (line 51). Inside `tests/run` the value is used at `:39` (parameter expansion and `read -r`, no glob, no eval), `:46` and `:62` (quoted right-hand sides in `[[ ]]`, so literal), and `:62,87` (double-quoted echo). No path is built from a name: the loop globs `$DIR` and compares basenames.
- Splitting, by probe of the line at `tests/run:39` under `set -euo pipefail`, bash 5.2.21: `''` and `' , '` give 0 names; `'02-b, 01-a,'` gives 2 and tail `02-b,01-a`; `*` stays 1 literal name; `01-a;02-b` is 1 name; `GATE: PASS` splits into `GATE:` and `PASS`. An empty array loops zero times under `set -u`.
- Glob names match nothing: probe of the `:46` and `:62` expressions with `only=(01-a "*" "0?-b")` runs `01-a` only and reports `*` and `0?-b` unmatched.
- A filtered run cannot forge a gate verdict. With one or more names the last line starts `GATE-ONLY: ` (`tests/run:86-91`); names hold no line break (they are split on it); a PASS needs every name found in `ran` (`:61-63`), so a passing tail holds real scenario basenames only.
- Every verdict reader refuses the line. `lib/receipt.sh:8` needs the prefix `GATE: ` (probe: `GATE-ONLY: PASS ...` refused); the refusal at `:24` comes before any write at `:30-36`; `jq -n --arg v "GATE-ONLY: PASS passed=1" '$v|startswith("GATE: PASS")'` prints `false`; `receipt_check` at `:60` needs `GATE: PASS` and an equal `receipt_verdict`. A grep of `bin/`, `lib/`, `scripts/`, `templates/`, `docs/`, `skills/`, `README.md`, `.claude/` and `.github/` for `GATE` finds no other parser: the rest is prose, and `tests/51-templates.sh:97-100` calls `receipt_verdict` on a fake gate.
- Empty input and pull requests run the suite as before, as far as `tests/run` goes: with 0 names `:46` short-circuits, `:61` does not loop, `:87` is not taken, and both verdict echoes expand to the old text. Pinned by `tests/00-harness.sh:47-50`.
- A filtered run never hits "no scenarios found" (`tests/run:64`): each name adds to `passed` or `failed`.
- The variable is hidden from scenarios (`tests/run:40`), pinned by the fixture at `tests/00-harness.sh:26`; removing the `unset` fails the assertion at `:30`.
- Mutants killed, by trace: `GATE-ONLY` back to `GATE` (`00-harness.sh:31`, and test 40 `:65-66`); no unknown-name loop (`:40`); no comma split (`:33-35`); tail from the raw value (`:35` with `' 02-b  01-a '`); FAIL keeping `GATE:` (`:38`); substring match at `tests/run:46` and `.sh` accepted (`:42-45`); separators-only treated as a filter (`:47-50`).
- Test 40's new block: `gate-logs/` exists (made by `gate 1` at `:21`); the fixture sits in the job dir; the reason is pinned by the `run.log` grep at `:67`; with the change reverted the receipt exits 0 (`lib/receipt.sh:38`), matching the RED in the work note.
- Phase 1 pins stand, counted with the test's own patterns on `ci.yml`: keep literal 1 (`:48`), upload path literal 1 (`:70`), `^ *if: failure()$` 2, one-line `run: tar` 1 (`:64`). On a filtered green run neither later step runs; on a filtered red run the kept tree holds the named scenarios.
- `bash -n` passes on `tests/run`, `tests/00-harness.sh`, `tests/40-receipt-required.sh`; `shellcheck -S warning` (0.11.0) is clean on the three.
- `tests/00-harness.sh` and `tests/40-receipt-required.sh` do not call `install_units` (grep: only `tests/11-unit-smoke.sh`, `tests/31-resume-after-reset.sh`, `tests/lib.sh`).
- 18 scenario files match `tests/[0-9][0-9]-*.sh`, the `passed=18` of the dispatcher's gate log.

**Examined, inconclusive**

- `.github/workflows/ci.yml:51` on GitHub: `gh run list --repo z0rd0n88/blast-off --commit 5062c7d...` returns `[]`, so neither event has run this file. I expect `inputs.only` to be `''` on `pull_request`; that needs a run. This extends the phase 1 open item "the CI steps never ran on GitHub". Commands and expected last lines of the `tests/run` step: a pull request run ends `GATE: PASS passed=18 failed=0 shellcheck=ok`; `gh workflow run ci --repo z0rd0n88/blast-off --ref feat/br-1115-issues/phase-2 -f only=70-docs` ends `GATE-ONLY: PASS passed=1 failed=0 shellcheck=ok only=70-docs`, green, no artifact; the same with `-f only=nope` prints `FAIL only nope: no such scenario in <checkout>/tests` and ends `GATE-ONLY: FAIL passed=0 failed=1 shellcheck=ok only=nope`, red, with an artifact holding an empty `blast-off-tests/`.
- The RED, GREEN and hand-probe outputs in `baton-phase-2-work.md`: read against the code and consistent with it; not re-run (forbidden).
- Whether a required check named `gate` could be satisfied by a dispatch run: `gh api repos/z0rd0n88/blast-off/branches/main/protection` and `.../rulesets` both return 403 "Upgrade to GitHub Pro or make this repository public", so I could not read any rule.
- How the zord-baton-runner judges `scripts/gate.sh` (status or last line): the plugin is outside the repo and I did not read it. The finding "A filtered pass exits 0, and `scripts/gate.sh` passes both the environment and the exit status through" is a false green only if the plugin trusts the status.

**Not examined**

- The bodies of the 16 other scenarios, and whether each passes when run alone in CI (the issue's own caution about timing).
- `lib/chain.sh`, `lib/child.sh`, `lib/units.sh`, `lib/preflight.sh`, `lib/usage.sh`, `lib/jev.sh`, beyond a grep showing none names `BLAST_OFF_TEST_ONLY` or `BLAST_OFF_TEST_KEEP`.
- The three `baton-runner/` files in the same commit (`STATE.md`, `log.md`, the work note as a tracked file).
- `actionlint` on `ci.yml` (not on the allowed list; the YAML was parsed with PyYAML only).

### Confidence

High on the `tests/run` logic, the receipt refusal and the test-gap traces (each is a quoted line plus a probe or a walked input); medium on what rests on behaviour outside the repo: GitHub's `inputs` on `pull_request`, when GitHub starts no `pull_request` run, and how the baton-runner reads `gate.sh`. One pull request run and one dispatch with `only=70-docs` would settle the first; the `gate.sh` command above would show the exit status, and reading the baton-runner plugin would show whether that status is trusted.
