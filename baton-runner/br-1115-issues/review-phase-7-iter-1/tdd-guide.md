# tdd-guide: phase 7 review, round 1 (static, read-only)

## Phase 7 test review (commit 514d0ef vs e924be8): issue 27, OPENROUTER_API_KEY by name plus the Jev confidence threshold

This was a static review. I wrote nothing, ran no tests and ran no git. Role: tdd-guide in review mode.

**Verdict.** The three criteria are tested well on the `run` path and the argv path. The real gaps are elsewhere:
- Nothing proves the key reaches a runner inside a real unit (C1 under `start`).
- Nothing checks that `JOB_JEV_MIN_CONF` is passed to the unit.
- Nothing checks that `decisions.tsv` records the confidence, the threshold or the fallback reason.

The other findings are LOW: edge values, vacuous helpers, isolation, and spec-row wording.

---

### 1. Criteria and the lines that pin them

**C1: with the key, Jev picks the model and the pick is logged.**
- `tests/12-start-env.sh:46` (`grep -qx -- '--setenv=OPENROUTER_API_KEY'`), `:47` (`key=set`) and `:48` (the printed launch line) pin `start`.
- `:66` pins `resume`, and `:76` pins the timer armed at the exit-75 pause.
- `:49` and `:77` check that the value is not on argv.
- Runner side: `tests/61-jev-pick.sh:23-37`:
  - flags replaced (`:32`)
  - pick line with confidence and threshold (`:34`)
  - row on stdin (`:29-31`)
  - TypeSafe route dropped (`:28`)
  - key value absent (`:26`)
- Preflight: `tests/60-preflight.sh:55-57` and `:76-78`.
- These catch realistic bugs: name not passed, value on the line (M10), timer path dropping the key (M3), preflight blanking the key (M8).
- **Not proven end to end.** No test shows a runner started by `start` or the timer actually holding the key and calling Jev. Test 12's stub swallows every non-`--scope` call, so the runner never starts under a unit there. Test 11, the only real-unit test, sets no key. See TG-1.
- **Is `key=set` enough?** It shows the variable was non-empty in systemd-run's own environment. That is exactly where real `systemd-run --setenv=NAME` reads the value from, so it covers the handoff. It does not prove the value is the right key, and it says nothing about what systemd hands the service (TG-11).

**C2: without the key, static flags, logged.**
- `12:52-59` checks that unset and empty pass no name. `:57` guards against an empty record set, so `:58` is not vacuous.
- `61:53` checks the runner's reason line and that Jev was called 0 times.
- `60:119` checks the preflight line `; start passes none`.
- Mutants M1 and M2 are killed.
- The fallback reason is not checked in `decisions.tsv` (TG-3).

**C3: a low-confidence pick keeps the static flags.**
- `61:65-66`: 0.55 is below 0.7, flags stay static and the reason is logged.
- `61:67-68`: 0.87 is below an override of 0.9.
- `61:69-70`: a confidence of `"high"` is not a number.
- `61:81-83`: picks are taken at 0.7 exactly, at 0.55 with a threshold of 0.5, and at 1 with a threshold of 1.0.
- `60:80-83`: preflight with a threshold of 0.9.
- These kill `<=` (M4), a missing low branch (M5) and a non-number being taken (M7).

**The owner's default and override.**
- Default 0.7 is pinned by `61:66` (fails if the default rises above 0.55 or drops to 0.55 or below; M12), `61:81` (fails if it rises above 0.7) and the literal `threshold 0.7` in `61:34` and `60:57`.
- The override is pinned under `run` and `preflight` by `61:68,82,83,85-91` and `60:80-87`.
- Under `start` and the timer, nothing pins the override (TG-2).

---

### 2. Findings

**TG-1 · MEDIUM · Nothing shows a runner started by `start` or the timer gets the key and asks Jev**
- Where: `tests/12-start-env.sh:31-78`; `tests/11-unit-smoke.sh` sets no key.
- Evidence:
  - The stub runs the real systemd-run only for `--scope` (`12:35`), so no test runs real systemd-run with an argv containing `--setenv=OPENROUTER_API_KEY`.
  - No test reads a unit runner's `run.log` for a Jev line.
  - The handoff rests on systemd's documented `--setenv=NAME` behaviour, shown only for GH_TOKEN (`11:39` `gh_token=set`).
  - A template change such as an `UnsetEnvironment=` or `Environment=` line copied in as `-p`, or a runner that cleans its environment, would pass every current test.
- Suggested test, in test 11 or a new real-unit case:
  - Export `OPENROUTER_API_KEY=sk-or-test-…` and add one open Phase plan row.
  - After the run, require `run.log` to contain `model level for phase 1:` and NOT `no OPENROUTER_API_KEY in the runner environment`.
  - Cheapest version: `FAKE_JEV` is not passed into the unit, so the fake jev fails at `: "${FAKE_JEV:?}"`. The reason `jev failed: …FAKE_JEV…` then proves both that the key reached the runner and that jev was called under the unit.
  - Fuller version: let the fake jev use a default state dir when `FAKE_JEV` is unset, and assert a real `light (jev, confidence …, threshold 0.7)` line.

**TG-2 · MEDIUM · Nothing checks that `JOB_JEV_MIN_CONF` is passed to the unit**
- Where: `lib/units.sh:25`; no assertion anywhere. My grep found no `--setenv=JOB_JEV` check in any test; 11 checks only `BLAST_OFF_*`.
- Evidence: removing `JOB_JEV_MIN_CONF` (or `JOB_JEV`, which was already missing a test) from the `unit_env` loop survives. Under `start` and the timer the owner's override would then be silently ignored and the unit would use 0.7.
- Suggested test: in 12, `JOB_JEV_MIN_CONF=0.9 PATH=stub:… start` → `grep -qx -- '--setenv=JOB_JEV_MIN_CONF' <<<"$a"`. Do the same for `JOB_JEV=0`, and add one timer-path case.

**TG-3 · MEDIUM · The `why` column of `decisions.tsv` (confidence, threshold, fallback reason) is not checked**
- Where: `lib/jev.sh:71`; tests `61:37` and `61:50`.
- Evidence:
  - `61:37` greps only `\tphase-1\tmodel level light`, and `61:50` only `model level static`.
  - Spec K8 says each pick "with its level, confidence and threshold, or the fallback reason … goes to `run.log` and the job's `decisions.tsv`".
  - These mutants survive:
    - `why="${JEV_WHY:-jev choice, confidence $JEV_CONF}"` (threshold dropped)
    - `why="jev choice, confidence $JEV_CONF, threshold $JEV_MIN"` with no `JEV_WHY` (every fallback recorded as a Jev choice)
    - `why=""`
- Suggested test: in `fallback()`, `awk -F'\t' -v w="$why" '$2=="phase-1" && $4==w' "$JOB/decisions.tsv" | grep -q .`. In the pick run, require column 4 to equal `jev choice, confidence 0.87, threshold 0.7`.

**TG-4 · LOW-MEDIUM · A string-comparison mutant may survive (depends on the jq version, not checked)**
- Where: `lib/jev.sh:46`.
- Evidence: take the mutant `(.|tostring) < ($t|tostring)`.
  - Under jq 1.6, `1.0|tostring` gives `"1"`, so every current case gives the same result as the numeric compare: 0.55/0.7 low, 0.87/0.9 low, 0.7/0.7 ok, 0.55/0.5 ok, 1/1.0 ok, preflight 0.87/0.7 ok and 0.87/0.9 low.
  - Under jq 1.7, which keeps number literals as written, the `one` case (`"1"<"1.0"`) kills it.
  - A bash `[[ $JEV_CONF < $JEV_MIN ]]` mutant is killed by `one` either way.
  - I did not check the box's jq version (not allowed to run it).
- Cases where text order and number order disagree:
  - threshold `0.70` with confidence `0.7`: should be taken; the text compare says low
  - a confidence jq prints with an exponent, e.g. `0.00005` → `5e-05` against `0.7`: should be low; the text compare takes it
- Suggested test: `picked trail 0.7 0.70 JOB_JEV_MIN_CONF=0.70` and `fallback tiny 'jev picked light, confidence 5e-05 below 0.7'`. The second needs a confidence file of `0.00005`; check jq's printed form when you add it.

**TG-5 · LOW · Values the regex accepts are not tested; mutants that require decimals survive**
- Where: `lib/chain.sh:100`; tests `61:81-91`.
- Evidence:
  - Never tested: `0`, `1`, `0.000`, `1.000`, `0.70`.
  - `1` matters because the refusal message itself offers `1` as an example (`(0.7, 0.85, 1)`).
  - These survive:
    - `1(\.0{1,3})?` → `1\.0{1,3}` (refuses `1`)
    - `0(\.[0-9]{1,3})?` → `0\.[0-9]{1,3}` (refuses `0`)
- Suggested test: a loop that `run` accepts `0 1 0.000 1.000 0.70`: exit 0, a child launched, and a log line with `threshold <v>`.

**TG-6 · LOW · Values the regex refuses are only partly tested**
- Where: `lib/chain.sh:100`; test `61:85`.
- Evidence: `00.7`, `1.0001`, `1,0`, `1.`, `0.`, `0.1234` and ` 0.7` are never tried. These survive:
  - `{1,3}` → `{1,4}` (accepts `0.1234`)
  - `0` → `0+` or `0*` (accepts `00.7`)
  - the second `\.` → `.` (accepts `1,0`; jq then rejects it with `--argjson`, so every pick falls to the "not a number" fallback with a misleading reason)
  - `0{1,3}` → `0*` (accepts `1.`)
- The tested `0,7` kills the first `\.` mutant only.
- Suggested test: add `00.7 1.0001 1,0 1. 0. 0.1234 ' 0.7'` to the `61:85` refusal loop.

**TG-7 · LOW · What an empty `JOB_JEV_MIN_CONF` means is not tested**
- Where: `lib/jev.sh:30`, `lib/chain.sh:100`, `lib/units.sh:26`.
- Evidence:
  - D-P7-3 says empty means the default.
  - `chain_nums` reads `${…:-0.7}`, so empty passes validation.
  - Mutant `JEV_MIN="${JOB_JEV_MIN_CONF-0.7}"` (no colon) survives. With `JOB_JEV_MIN_CONF=` it gives `--argjson t ""`, jq errors, and every pick silently falls back with `confidence '0.87' is not a number`.
  - `unit_env` passes a set-but-empty value on to the unit.
- Suggested test: `picked empty 0.87 0.7 JOB_JEV_MIN_CONF=` (pick taken, logged `threshold 0.7`).

**TG-8 · LOW · A null or missing confidence is not tested**
- Where: `lib/jev.sh:45-49`.
- Evidence: only `"high"` (a string) is tested. Mutant `type == "string"` instead of `type != "number"` survives: null goes to `null < 0.7`, which is low, giving `confidence ? below 0.7` instead of the not-a-number reason. The fallback is still safe, but the reason is wrong. A missing `confidence` key is the realistic shape from a real tool.
- Suggested test: confidence file containing `null` → `fallback null "jev picked light, confidence '?' is not a number" 1 …`.

**TG-9 · LOW · The exit-75 timer case proves argv only, and its `FAKE_JEV` setting is dead**
- Where: `12:70-78`.
- Evidence:
  - `new_job keytimer die75` has no Phase plan row, so `jev_flags` returns at "no open Phase plan row" and Jev is never asked.
  - `FAKE_JEV="$PWD/jev"` names a directory that does not exist and is never used. A reader would think a pick happens.
  - The chain "timer service → `resume` → `unit_start` passes the key" holds only because 12:66 tests resume separately.
  - Not vacuous: rc 8 plus `--on-calendar` in argv requires that `usage_arm` reached systemd-run.
- Suggested test: drop `FAKE_JEV`, or add a Phase plan row with the fake answering `light` and assert the run's `run.log` pick line before the pause. That covers C1 on the pause path too.

**TG-10 · LOW · `argv()` merges every recorded call, so per-call assertions can be met by different calls**
- Where: `12:39`, `12:45-47`, `12:74-77`.
- Evidence:
  - `cat stub/argv-*` joins all records, so `--on-calendar` and `--setenv=OPENROUTER_API_KEY` could come from two different systemd-run calls. Today each step makes exactly one non-scope call, so it holds, but nothing asserts that.
  - Records are named `argv-$$`, so a reused PID would overwrite an earlier record.
  - The window between `cat` and `rm` cannot lose a record today: scope calls exec the real binary and record nothing, and nothing runs in the background after the step.
- Suggested test: assert exactly one record file per step (`ls stub/argv-* | wc -l` = 1), or grep the one file that holds `--on-calendar` for the setenv line.

**TG-11 · LOW · `key=set` shows the key was present, not that it was the right value**
- Where: `12:36`, `12:47`.
- Evidence: `${OPENROUTER_API_KEY:+set}` would also pass if a bug replaced the value, e.g. exported a redacted or empty-prefix value before systemd-run.
- Suggested test: have the stub record `key=$([ "$OPENROUTER_API_KEY" = "$EXPECT_KEY" ] && echo same || echo other)`, with `EXPECT_KEY` exported by the test. That compares without printing the value.

**TG-12 · LOW · The key-absence checks pass silently on a missing path, and are mostly vacuous in the start and resume cases**
- Where: `12:40` (`nokey`), `61:26`.
- Evidence:
  - `! grep -qr -- "$key" …`: grep exits 2 on a missing path, `!` turns that into success, and the check passes.
  - Every path exists today.
  - In the `start` and `resume` cases no runner ever runs (the stub), so `run.log`, `decisions.tsv` and any pick line never exist. `nokey "$JOB"` there checks only `checkpoint.md`, `brief.md`, `fake-mode` and resume's one log line.
  - The meaningful leak check is `61:26`, after a real pick.
- Suggested test: `grep -rqs -- "$key" "$@"; [ $? -eq 1 ] || fail …`, so exit 2 fails.

**TG-13 · LOW · Spec row 12 promises more than the test checks**
- Where: `docs/spec.md` row `12-start-env`; `12:61-67`.
- Evidence:
  - The row says the value is "on no argv" for start, resume and the timer. Resume has no `grep -q -- "$key" <<<"$a" && fail`.
  - The row says "unset or empty, no such name" without limiting it to start, but only `start` is tested unset and empty. Resume and the timer are not.
- Suggested test: add the argv value check after `:66`, and one unset-key timer case (`! grep -q OPENROUTER`). Or narrow the row.

**TG-14 · LOW · "Refused before any other line" is not checked for `JOB_JEV_MIN_CONF=2`**
- Where: `60:85-87`.
- Evidence: `has` matches anywhere in the output. Moving `chain_nums` after `jev_flags` and the `flags:` echo in `preflight_run` would still print the refused line and exit 1, and would also make a Jev call. The test checks neither a missing `flags:` line nor an unchanged jev call count. The same was already true of `60:159-163`.
- Suggested test: `! grep -q '^flags:' p15.out` and the jev `calls` line count unchanged across p15.

**TG-15 · LOW · Test isolation: `JOB_JEV_MIN_CONF` and `JOB_JEV` are not unset for every scenario**
- Where: `tests/lib.sh:10`; `tests/run` does not clean the environment.
- Evidence:
  - lib.sh unsets `OPENROUTER_API_KEY TYPESAFE_API_KEY JEV_BASE_URL` for every scenario, which is good.
  - `JOB_JEV_MIN_CONF` and `JOB_JEV` are unset only in 60 (`:12`) and 61 (`:11`).
  - `chain_nums` validates `JOB_JEV_MIN_CONF` on every `run`. An invalid value in the box or CI environment (`.8`, `0.75 `) would fail every scenario that drives `run` (10, 11, 20, 21, 30…) with a confusing refusal.
  - A valid value changes no result, because no other scenario has a key.
  - Other `JOB_*` names were already leaking in the same way.
- Could the real jev be called? Not as far as I can see statically:
  - No real key in any scenario.
  - The fakes come first on PATH via `use_fakes` in 12, 60 and 61.
  - 61's `nojev` drops every PATH directory that holds an executable `jev`.
  - 12's exit-75 run has no Phase plan row.
- Not checked: whether the user's `grep` shell function, which wraps ugrep, reaches scenarios through an exported function or `BASH_ENV`. If it did, `-r` on ignored files could skip them, which matters for `nokey`.
- Suggested fix: `unset … JOB_JEV JOB_JEV_MIN_CONF` in `tests/lib.sh:10`.

**TG-16 · LOW · The key-not-printed check covers only one preflight output**
- Where: `60:78`.
- Evidence: only `p1.out` is checked. The key is exported for the whole scenario, including p14 (the below-threshold static line), p2 to p4 and p6. 61 checks only the pick run. A mutant that prints the key only on the static or below-threshold line survives.
- Suggested test: `! grep -rq -- "$key" p*.out`, or the same check after p14.

**TG-17 · LOW (not checked) · The confidence field is read from a shape only the fake defines**
- Where: `lib/jev.sh:45-46`, `tests/fakes/jev:9,16-17`.
- Evidence:
  - The threshold now gates on `.level.confidence` being a JSON number. Before, the field was only logged.
  - The only contract for that field is the fake (`{level:{choice,confidence,probabilities}}`). Its comment, "the .answers object", hints the real output may be shaped differently.
  - I found no recorded real jev output in the repo.
  - If real `jev -q … level` does not put a numeric `confidence` under `.level`, every real pick becomes "not a number" static, the whole feature quietly does nothing, and every test still passes.
- Suggested test: save one real `jev -q` output (key-free, from the owner) as a fixture and replay it through the fake, or have the fake take its output from that fixture.

**TG-18 · LOW · The spec says children inherit the key through tmux; nothing tests it**
- Where: `docs/spec.md` env paragraph; `tests/fakes/claude:48`, which records only `gh_token`.
- Evidence: the claim is unpinned. There is also the open Q2: whether children should see the key at all.
- Suggested test: whichever way the owner decides Q2, record `openrouter=set|unset` in fake-marker and assert it.

**TG-19 · LOW · `unit_env` passes a non-`sk-or-` key, or one set with `JOB_JEV=0`, into the unit file; untested**
- Where: `lib/units.sh:22`, `lib/preflight.sh:28`.
- Evidence:
  - `unit_env` checks only that the key is non-empty. A `tsk-` (TypeSafe) value in `OPENROUTER_API_KEY` is stored in the transient unit file, although the runner will never use it. That is the very secret class K8 says never goes to TypeSafe.
  - Preflight's `tskey` static line omits that `start` will still pass it.
  - No test pins either behaviour.
- Suggested test: once the owner decides, `OPENROUTER_API_KEY=tsk-dummy start` → assert the name is passed, or assert it is not.

**TG-20 · LOW · `start` does not validate `JOB_JEV_MIN_CONF`; untested**
- Where: `lib/units.sh:31-35` (`unit_check`).
- Evidence: the implementer already noted this. A bad value starts the unit, and the runner then dies in `chain_nums` with the reason on stderr only (the journal), not in `run.log`. That matches how bad `JOB_*` counts already behave, and the spec says only that "`run` and `preflight` refuse". No test pins it either way.
- Suggested test: if the owner wants `start` to refuse, add `JOB_JEV_MIN_CONF=abc start` → exit 1 and no unit, as `12:21-27` does.

**TG-21 · LOW · Repeated `new_job bad` reuses one job dir**
- Where: `61:85-91`.
- Evidence: all 7 iterations share `test-$$-bad/job`, and its `run.log` and `child-count` carry over. This is harmless now because the refusal comes before `chain_count`. If a refusal ever moved after `chain_count`, a stale `fake-marker` would only show up as the iteration that launched it.
- Suggested test: `new_job "bad$i"` for each value.

---

### 3. Mutants beyond M1-M12: will they survive? (reasoned statically, none run)

| Mutant | Survives? | Why |
|---|---|---|
| jq `tostring` text compare | jq 1.6: yes; jq 1.7: killed by `one` | TG-4 |
| bash `[[ $JEV_CONF < $JEV_MIN ]]` | killed | `one`: `"1" < "1.0"` |
| integer-truncated compare (`${c%.*}`) | killed | `low`: 0 < 0 is false, so the pick is taken |
| `--argjson t` → `--arg t` (string threshold) | killed | number < string is always true, so every pick is low; `at` and `pick` fail |
| `JEV_MIN` default dropped, `${JOB_JEV_MIN_CONF:-}` | killed | jq error → nan reason; `low` expects "below 0.7" |
| `JEV_MIN` default `:-` → `-` | **survives** | TG-7 |
| `chain_nums` default changed to another valid value | survives, no effect | only the regex reads it |
| `JOB_JEV_MIN_CONF` dropped from `unit_env` | **survives** | TG-2 |
| `JOB_JEV` dropped from `unit_env` | **survives** (already missing a test) | TG-2 |
| `unit_env` uses `${OPENROUTER_API_KEY+x}` (set, not non-empty) | killed | empty case `12:58` (M2) |
| preflight no-key suffix condition inverted | killed | `60:83` and `60:119`, anchored |
| preflight pick line without `threshold` | killed | `60:57` |
| `decisions.tsv` why without threshold, or ignoring `JEV_WHY` | **survives** | TG-3 |
| nan branch → `type == "string"` | **survives** | TG-8, null untested |
| nan branch removed | killed | the `"high"` case is taken → `nan` fails |
| `JEV_CONF` assigned after the case | killed | `low` expects "confidence 0.55" |
| `low)` branch without `return 0` | killed | `low` flags check |
| regex: `0` alone or `1` alone refused | **survives** | TG-5 |
| regex: `{1,3}` → `{1,4}`; `0` → `0+`; second `\.` → `.`; `0{1,3}` → `0*` | **survive** | TG-6 |
| regex: `{1,3}` → `+`; `^` or `$` dropped; first `\.` → `.`; 1-branch any decimals | killed | `0.12345`, `-0.1`, `0.7x`, `0,7`, `1.5` |
| preflight `chain_nums` moved after `jev_flags` | **survives** | TG-14 |
| preflight prints the key only on the static line | **survives** | TG-16 |
| jq `--argjson t 1.0` vs `1` | no bug | jq parses both as a number and `1 < 1.0` is false; the `one` case covers it |

---

### 4. Test 12's stub, `argv()`, and the exit-75 case (question 3)

- **Can the stub hide a real failure?**
  - It records any call without ` --scope ` and returns 0. So `start`, `resume` and the timer all report success whether or not real systemd-run would accept that argv with the extra name.
  - Child scopes pass through to the real binary. The implementer reports the exit-75 child scope really launched.
  - The real-launch risk is low because GH_TOKEN uses the same `--setenv=NAME` form and test 11 runs it for real, but nothing tests the new name on a real launch (TG-1).
  - The ` --scope ` match on `" $* "` fits the child launch string in `lib/child.sh:49`.
- **`argv()`**: no realistic race today. It does merge all calls and uses PID file names (TG-10).
- **Exit-75 timer case**: not vacuous. It needs rc 8 plus a recorded `--on-calendar` with the setenv line. But it shows argv only, and its `FAKE_JEV` is dead (TG-9).

### 5. Vacuous assertions (question 4)

- `has` (`60:19`): `grep -qE` on a file. A missing file exits 2 and fails, so it is not vacuous. It matches anywhere in the output, though (TG-14).
- `! grep -qr` (`12:40`, `61:26`): passes on a missing path (TG-12).
- `wc -l < calls` (`61:27`, `60:76`): a missing file breaks the redirect, `[ "" -eq N ]` errors, and the test fails. Not vacuous.
- `cat calls | wc -l` (`61:49`): a missing file gives 0, which is correct when 0 calls are wanted.
- `61:28` (`grep -qv … && fail`) would pass on a missing file, but `:27` runs first and fails in that case.
- The negative greps on `$a` (`12:49,58,77`) each come after a positive check on the same `$a`. Not vacuous.

### 6. Spec test rows vs the tests (question 6)

- **Row 12**: accurate except that resume has no value-on-argv check and unset/empty are tested only for `start` (TG-13).
- **Row 60**: every listed item is asserted. "Refused before any other line" (spec text elsewhere) is not, for value 2 (TG-14). "The key's value not printed" holds for p1 only (TG-16).
- **Row 61**: every listed case is present and asserted. K8's claim that `decisions.tsv` carries the confidence, threshold or reason is not asserted (TG-3).

---

### Open questions for the owner

1. Should the confidence threshold have a test under `start` (TG-2), and should a real-unit test prove the key reaches the runner (TG-1)? I recommend both. Each is a few lines in 12 or 11.
2. Is an empty `JOB_JEV_MIN_CONF` the default (as now, D-P7-3), or a refusal? TG-7's survivor turns on this.
3. Should `unit_env` pass the key only when it starts `sk-or-`, and not when `JOB_JEV=0`, so a TypeSafe or unused key never lands in the unit file (TG-19)?
4. Should children under `start` inherit `OPENROUTER_API_KEY` (implementer's Q2)? Whatever you decide, fake-marker should pin it (TG-18).
5. Can you supply one real, key-free `jev -q … level` output as a fixture, so the `.level.confidence` shape is checked against the real tool (TG-17)?
6. Should `start` refuse a bad `JOB_JEV_MIN_CONF` up front, rather than the unit dying with the reason only in the journal (TG-20)?

Not checked statically:
- The box's jq version (TG-4).
- Whether the user's ugrep `grep` function reaches scenarios (TG-15).
- Real jev's output shape (TG-17).
- How jq parses `00.7` and `1.` if the regex were loosened (TG-6).
