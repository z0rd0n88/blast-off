# code-reviewer: phase 7 review, round 1 (static, read-only)

## Code review: blast-off phase 7 (issue 27), commit 514d0ef vs e924be8

This was a static review only. I ran nothing and edited nothing. I read the diff in full, then the touched files: lib/units.sh, lib/jev.sh, lib/chain.sh (chain_nums, chain_run), lib/preflight.sh, lib/usage.sh (usage_arm), lib/child.sh (child_server, child_launch, child_screen), bin/blast-off, tests 12/60/61, tests/fakes/jev, tests/lib.sh, docs/spec.md, README.md, skills/blast-off/SKILL.md, and the phase-7 work notes and findings. To check the output shape and how errors are handled, I also read the real jev script (/home/alex/JevDev/bin/jev, which ~/.local/bin/jev points to). That file contains no secrets.

**Verdict: APPROVE with warnings.** There are no CRITICAL or HIGH findings. Two MEDIUM findings should be decided or fixed before merge.

---

### 1. Acceptance criteria and owner sign-off

- **C1 (key set: the model comes from Jev and is logged): met.**
  - Code:
    - `lib/units.sh:22` adds `--setenv=OPENROUTER_API_KEY` when the key is set and not empty.
    - `lib/usage.sh:69-71` builds the timer from the same `unit_env`.
    - `lib/jev.sh:69` logs the pick line, including the threshold.
  - Tests:
    - `tests/12-start-env.sh:43-50` covers start: the argv line, `key=set` in systemd-run's environment, and the printed launch line.
    - `:62-67` covers resume and `:69-78` covers the timer.
    - `tests/61-jev-pick.sh:23-35` checks the pick line in run.log with confidence and threshold.
  - The implementer's mutants M3, M8 and M10 are each killed by these tests.
  - Caveat: under a real unit the chain is only tested in pieces (see CR-9).
- **C2 (no key: static flags, logged): met.**
  - `lib/jev.sh:33`; test 61 `fallback nokey` (line 53) checks both run.log and decisions.tsv.
  - Test 12 `:52-59` checks that no name is passed when the key is unset or empty (mutants M1 and M2).
  - Test 60 `:117-119` checks the preflight line ends `; start passes none`.
- **C3 (low-confidence pick keeps static flags): met.**
  - `lib/jev.sh:46-50`.
  - Test 61 `:64-70`: low 0.55 < 0.7, high 0.87 < 0.9, nan `"high"`.
  - `:79-83`: exactly 0.7 is taken (kills `<=`), 0.55 with min 0.5 is taken, 1 with 1.0 is taken.
  - Test 60 `:79-83` covers the preflight form.
- **Owner sign-off:**
  - "Pass the key": met.
  - "Threshold 0.7": met and pinned (M12 is killed by `fallback low` and `picked at`).
  - "Overridable with JOB_JEV_MIN_CONF": met for `run` and `preflight`, but **not pinned under `start` or the timer** (CR-2).

### 2. Secret handling for OPENROUTER_API_KEY, end to end

| Where | Result | Evidence |
|---|---|---|
| systemd-run argv (start, resume, timer) | name only | units.sh:22 and :41; usage.sh:70-71; test 12:46-49, 66, 76-77 |
| Printed launch line | names only (`${args[*]}`) | units.sh:46; test 12:48 |
| run.log / decisions.tsv | key never logged | jev.sh:65-75 log only level, confidence, threshold and reason; test 61:27 |
| Preflight output | not printed | preflight.sh:23-29; test 60:78 |
| `status` output | no Environment shown | units.sh:75 and :79 use `-p ActiveState` only |
| Journal | runner stdout is the `log` lines, so no key; jev's stderr is captured to a file, not the journal | jev.sh:39-40 |
| jev's own stderr | jev sends the auth header through curl's stdin (`-H @-`) and prints only the response body or a curl error, so the 200-byte `jev failed:` reason should hold no key | JevDev/bin/jev:116-124 (unverified for every OpenRouter error body) |
| err temp file | mktemp gives mode 0600 in `$XDG_RUNTIME_DIR`; removed on both paths (jev.sh:40, :42). It is left behind only if the runner is killed during the call, and holds jev's stderr, not the key | |
| systemd transient unit files | the key's value is stored in the runner unit and in `<unit>.resume.service` under `$XDG_RUNTIME_DIR/systemd/transient/` (0644 file in a 0700 dir), and is readable through `systemctl --user show -p Environment`. This is the storage class D21 accepted. The resume service can hold it for days at a seven_day pause | |
| Children | **inherit it** through the job's tmux server | CR-1 |

### 3. Resume-timer path

usage_arm runs inside the runner (usage.sh:69). Its `unit_env` reads the runner's own environment, which holds the key only if `start` passed it. The timer's service gets `--setenv=OPENROUTER_API_KEY`. `blast-off resume` then calls `unit_start`, whose `unit_env` (units.sh:40) passes the name again, so **the key does reach the final runner.**

- **Key unset at arm time, set later:** the timer never has it. Exporting it in a shell afterwards changes nothing. The owner must `stop` the job and then run `resume`/`start` from a shell that has the key. A manual `resume` before the `until` time exits 8 (units.sh:61-62); one after it starts with the key and stops the pending timer.
- **Key set at arm time, unset or rotated later:** the pending timer keeps the old value in its stored unit file. A revoked key makes jev fail, the run falls back to static, and the failure is logged. Nothing breaks, but the stale value stays on tmpfs until the service is collected.
- Neither case is documented (part of CR-10).

### 4. Preflight's real Jev call (Q1)

- **Cost:** one OpenRouter request per preflight whenever the key is set and `JOB_JEV` is not 0. It also sends the first open Phase plan row's text to OpenRouter at preflight time.
- **Latency:** jev's curl has `-m 30` and blast-off wraps it in `timeout 60`, so up to about 30 s and at most 60 s.
- **Failure modes:** a jev failure, `other`, low confidence or a non-numeric confidence each print a static level line. None of them refuses the launch. A new abort path is in CR-8.
- **Still writes nothing:** yes in the job dir. `LOG=/dev/null` (preflight.sh:11) and `jev_flags` never writes decisions.tsv; only `jev_pick` does. The only write is the err temp file, which is removed. jev writes nothing to disk (JevDev/bin/jev).
- **Leaks:** none of the key. Up to 200 bytes of jev's error body can go to stdout.
- **Determinism:** preflight's pick is a separate sample. See CR-7.

### 5. Threshold compare and validation

- **The regex `^(0(\.[0-9]{1,3})?|1(\.0{1,3})?)$` (chain.sh:100):**
  - Accepts 0, 0.x through 0.xxx, 1, 1.0, 1.00 and 1.000.
  - Refuses `.7`, `0.`, `1.`, `00.5`, `01`, ` 0.7`, `1e0`, `0.1234`, `-0`, `0,7` and `abc`.
  - Every accepted value is valid JSON for `--argjson`.
- **Empty value:** treated as the default in both chain_nums (`:-0.7`) and jev_flags (jev.sh:30), so they agree. It is not tested (CR-11).
- **Where validation runs:** run (chain.sh:153) and preflight (preflight.sh:15), not start or resume (CR-3).
- **Is chain_nums always called before jev_flags?** Yes. jev_flags is called only from `preflight_run` (after line 15) and `jev_pick`, and `jev_pick` is called only from chain_run:216, after chain_nums at :153.
  - If JEV_MIN were ever invalid, `jq --argjson` would fail, the case word would be empty, and the run would fall back to static with the misleading reason "confidence '0.87' is not a number". That fails safe, but today the path is unreachable.
- **Confidence values:**
  - A number at or above the threshold is taken; below it falls back.
  - null, missing, false, a string, an object or an array go to the nan branch and fall back (`JEV_CONF` shows `?` or the raw text).
  - A negative number is "low" and falls back.
  - **A value above 1 (e.g. 87, 1e300) is taken** (CR-6).
  - Exponent forms such as `7e-1` compare correctly as numbers and are printed normalized.
  - A `nan` literal (jq parses it as a number, and jq sorts it below every number) should be "low" and print `confidence null`. This is unverified and depends on the jq version.

---

## Findings

**CR-1 · MEDIUM · Under `start`, children now get OPENROUTER_API_KEY by default (Q2)**
- **Location:** lib/child.sh:13 and :21 (`env $scrub ... tmux ... new-session`; `scrub` removes only `^CLAUDE[A-Z_]*`); docs/spec.md:69 ("Children inherit it ... as they inherit GH_TOKEN").
- **Evidence:**
  - Before this change, under start the children had no key. Now every child (a Claude session with bypass permissions, reading repo content that may carry prompt injection) has it in its environment, though only the runner needs it to call jev.
  - Concrete ways the value can reach a file:
    - A child that runs `env` or `printenv` while debugging puts the value in its session transcript (`~/.claude/projects/*.jsonl`).
    - If that child then dies, `child_screen` (child.sh:96-99) copies its last 40 screen lines into run.log.
  - GH_TOKEN has the same exposure, but children need GH_TOKEN; they do not need OPENROUTER_API_KEY to run blast-off.
  - With `JOB_KEEP_WINDOWS`, the tmux server, and with it the key, stays alive after the job exits.
- **Fix:** `env $scrub -u OPENROUTER_API_KEY PATH=... tmux ...` in child_server. The runner keeps the key in its own environment, so `jev_flags` still works.
- **Trade-off for the owner:** children that use an `ask-jev`-style skill themselves would lose the key. Add a test that the fake child does not see the key.

**CR-2 · MEDIUM · No test pins that `JOB_JEV_MIN_CONF` reaches the unit or the timer**
- **Location:** lib/units.sh:25; tests/12-start-env.sh:43-77.
- **Evidence:**
  - The owner sign-off makes the threshold overridable, and `start` is the main way jobs run.
  - Removing `JOB_JEV_MIN_CONF` from the `unit_env` loop would pass every test: test 12 never sets it, and tests 60 and 61 drive preflight and foreground `run` only.
  - The override would then be silently ignored under start and the timer: the unit would use 0.7.
- **Fix:** in test 12's k1 and k4 cases, set `JOB_JEV_MIN_CONF=0.9` and assert `grep -qx -- '--setenv=JOB_JEV_MIN_CONF'`.

**CR-3 · LOW · `start` and `resume` do not validate JOB_JEV_MIN_CONF**
- **Location:** lib/units.sh:31-35 (unit_check); lib/chain.sh:153.
- **Evidence:**
  - `JOB_JEV_MIN_CONF=abc blast-off start <job>` creates the unit and exits 0. The runner then dies in chain_nums through `die`, so the reason goes to stderr and the journal only, not run.log.
  - `wait` reports `stuck` after 10 s, and `status` shows no reason.
  - This copies the existing behaviour for bad JOB_* counts (the implementer noted it). chain_count's refusal, by contrast, also writes run.log (P4R1-2).
- **Fix:** call `chain_nums || die "$NUMS_ERR"` in unit_check, which also covers resume and the timer.

**CR-4 · LOW · The key is passed even when it is not an `sk-or-` key**
- **Location:** lib/units.sh:22 versus lib/jev.sh:34-36.
- **Evidence:** any non-empty value is stored in the transient unit file and handed to children, though jev_flags will never use a value that does not start `sk-or-`. A mistyped or TypeSafe-style value in OPENROUTER_API_KEY becomes a stored secret for nothing.
- **Fix:** `[[ ${OPENROUTER_API_KEY:-} == sk-or-* ]] && UNIT_ENV+=(--setenv=OPENROUTER_API_KEY)`, plus a test-12 case with `tsk-dummy`.

**CR-5 · LOW · A non-numeric confidence is printed raw into run.log, decisions.tsv and preflight output**
- **Location:** lib/jev.sh:45 and :49; jev.sh:75 (`tr -d '\r'` only).
- **Evidence:**
  - `jq -r '.level.confidence // "?"'` prints a string confidence as-is, and an object or array as multi-line JSON.
  - A string with `\n2099-01-01T00:00:00Z job done` would forge a run.log line, which is the risk P5R1-5 guards against.
  - A tab or newline breaks the 6-column decisions.tsv row. Test 61:42 only checks the column count on the pick job.
  - The source is the OpenRouter response, which is semi-trusted.
- **Fix:** `jq -r '.level.confidence // "?" | tostring' | tr -d '[:cntrl:]' | cut -c1-40`, or print `tojson` on the nan branch.

**CR-6 · LOW · A confidence above 1 is accepted as passing**
- **Location:** lib/jev.sh:46.
- **Evidence:** the compare checks only `. < $t`. Values like 87 (a percentage scale) or 1e300 are taken. An out-of-range confidence suggests a malformed answer, and fails open toward Jev's pick.
- **Fix:** `elif . < $t then "low" elif . > 1 then "nan" else "ok" end`. Make the "not a number" reason say "not a number from 0 to 1". Add a 61 case with confidence 1.5.

**CR-7 · LOW · Preflight's level is a separate Jev sample and may come from a different environment than the one `start` will run in**
- **Location:** lib/preflight.sh:21-29; docs/spec.md:26 ("prints the flags and level `start` gives, asking Jev as the runner would") and :61; skills/blast-off/SKILL.md:56-60.
- **Evidence:**
  - The runner asks Jev again (jev_pick caches per runner only), so near the threshold, or on another sample, the runner's level or static choice can differ from what preflight printed.
  - SKILL step 6 runs preflight in the agent's session, while step 7 hands `start` to the owner's terminal. These are different environments, so one may have the key and the other not.
- **Fix:** reword the docs and the preflight line to "what start would likely give; the runner asks Jev again". Make SKILL step 7 export OPENROUTER_API_KEY, or say it is optional.

**CR-8 · LOW · New preflight abort path, plus latency and cost**
- **Location:** lib/jev.sh:38 (`err="$(mktemp ...)"`, under `set -e` from bin/blast-off:47); lib/preflight.sh:23.
- **Evidence:**
  - Preflight used to force the key empty and never reached mktemp. Now, with the key set and `$XDG_RUNTIME_DIR` set but missing or unwritable, mktemp fails and `set -e` aborts preflight without a `preflight: refused` line. This contradicts jev_flags' "Never fails" comment; the same pre-existing gap is in the runner.
  - Each preflight with the key adds up to about 30-60 s and one paid call.
  - Not documented in spec.md:61 or the README.
- **Fix:** `err="$(mktemp ...)" || { JEV_WHY="mktemp failed"; return 0; }`. Mention the call's cost and latency in the preflight docs, or let `JOB_JEV=0 blast-off preflight` skip it.

**CR-9 · LOW · Test 12's stub systemd-run: what it can and cannot hide**
- **Location:** tests/12-start-env.sh:33-37.
- **What it cannot hide:**
  - It execs the real binary for every `--scope` call, so child-scope failures are not masked: the k4 die75 child runs for real.
  - It also prevents a real resume timer from being armed and firing hours later on a deleted temp dir.
- **What it can hide:**
  1. The real systemd-run never runs with `--setenv=OPENROUTER_API_KEY`, and no scenario proves that a real unit's runner receives the key and logs a Jev pick. The mechanism is the same one test 11 already exercises for GH_TOKEN, so the risk is small.
  2. The stub always exits 0, so `start`'s rc and the timer's "armed" log line cannot fail under it. The real start is covered only by test 11, without the key.
  3. `key=set` (that the value actually reached systemd-run's environment) is asserted only for k1, not for k3 (resume) or k4 (timer).
  4. The timer → `resume` → start chain is tested only in pieces (k3 plus k4).
- **Fix:**
  - Add `grep -qx key=set` to k3 and k4.
  - Optionally, in test 11 or 31, run one real `start` with a fake key and the fake jev, and assert run.log has `model level for phase 1: ... (jev, confidence 0.87, threshold 0.7)`.

**CR-10 · LOW · Docs gaps and stale text**
- docs/spec.md:54 (`start` row) lists `--setenv=PATH --setenv=GH_TOKEN --setenv=CLAUDE_FLAGS` and the JOB_* names, but not the conditional `--setenv=OPENROUTER_API_KEY`.
- docs/spec.md:94 (exit-1 row) lists bad `JOB_*` counts but not a bad `JOB_JEV_MIN_CONF`.
- docs/spec.md:68 and :71 ("writes no secret (`GH_TOKEN`)", "the token included") and docs/systemd-guide-deviations.md:31 ("systemd's stored copy of `GH_TOKEN` ... is accepted (D21)") still name only GH_TOKEN as a stored secret. There are now two.
- docs/spec.md:130 and lib/child.sh:5-8 ("PATH, GH_TOKEN and JOB_* reach every child") do not mention OPENROUTER_API_KEY reaching children.
- skills/blast-off/SKILL.md:59 (`export GH_TOKEN CLAUDE_FLAGS=...`) and :85-88 do not mention exporting OPENROUTER_API_KEY. Without it, issue 27 does nothing for a skill-driven start.
- tests/12-start-env.sh:2-3: the header comment still describes only the CLAUDE_FLAGS refusal.
- docs/spec.md:26 cites "P6Q7". That ID appears nowhere else in the tracked repo. Unverified; it may be in issue 27 or outside the repo.
- Nothing documents that a key rotated after arming stays in the pending timer, or that a key exported later never reaches it (section 3).
- No stale "start passes no key" or "P6Q1 open" text remains in README, bin/blast-off, lib/, skills/ or templates/. docs/decision-log/build-2026-11-04.tsv:140 keeps the old decision; it is a historical log.
- The README pick-line example, the bin header and the spec's K8 and env paragraphs match the code exactly (jev.sh:48, :49, :69; chain.sh:101).

**CR-11 · LOW · Test gaps on edge values and one claim**
- No test for `JOB_JEV_MIN_CONF=''`, which should mean the default, or for `0`, which takes any non-negative number.
- docs/spec.md:238 says "the value on no argv", but test 12 checks only systemd-run's argv. The code puts the value on no other argv either (child_launch's command line holds `$CHILD_FLAGS`, not the key), but that is not asserted.

**CR-12 · LOW (nit) · Dead setting in test 12's k4**
- **Location:** tests/12-start-env.sh:71.
- **Evidence:** `FAKE_JEV="$PWD/jev"` points at a directory that is never created. The die75 job has no Phase plan, so jev is never called. It is harmless but misleading.
- **Fix:** drop it.

**CR-13 · LOW (info) · Misleading reason if the threshold is ever invalid inside jev_flags**
- **Location:** lib/jev.sh:46 and :49.
- **Evidence:** jq's `--argjson` fails, the case word is empty, and the reason reads "confidence '0.87' is not a number". This is unreachable today (see section 5) and fails safe.
- **Fix (optional):** say "threshold '<t>' unreadable" when `jq --argjson` itself fails.

**CR-14 · LOW (info) · Phase plan text now goes to a third party by default under `start`**
- **Evidence:** with the key in the start environment and `JOB_JEV` at its default of 1, every phase's Phase plan row (text the children write) is sent to OpenRouter. Before this change that happened only for a foreground `run`.
- A child could also word a row to push Jev toward `deep` (opus, xhigh), which costs more. The threshold and the fixed set of levels bound this.
- This is intended by the sign-off. It is noted here for awareness only; `JOB_JEV=0` turns it off.

**Checked and clean:**
- Quoting and `set -e` in the new code:
  - `[ -z ... ] || UNIT_ENV+=(...)` returns 0 when the key is empty.
  - The `case "$(jq ...)"` subject cannot trip `set -e`.
  - In test 12, `grep -q ... && fail` is not the last command of the script, so `set -e` does not exit there.
  - preflight.sh:28's `$([ -n ... ] || echo ...)` is safe.
- shellcheck: the gate runs at `-S warning`. The single-quoted `$*` and `${...}` in the stub's printf (test 12:35-36) would be SC2016, which is info level, so the gate does not report it.
- Style matches the repo: the NUMS_ERR message shape, the `${v:-default}` pattern, and the comment style.
- The real jev's `-q` output shape (`.answers`, i.e. `{"level":{"choice","confidence"}}`) matches the fake's and what jev.sh parses (JevDev/bin/jev:129).

---

## Review Summary

| Severity | Count | Status |
|----------|-------|--------|
| CRITICAL | 0 | pass |
| HIGH | 0 | pass |
| MEDIUM | 2 (CR-1, CR-2) | info |
| LOW | 12 (CR-3 to CR-14) | note |

Verdict: APPROVE. No CRITICAL or HIGH. CR-1 needs an owner decision and CR-2 is a one-line test addition; I recommend both before merge.

## Open questions for the owner

1. **Q2 / CR-1:** should `child_server` scrub OPENROUTER_API_KEY so children never see it? That costs children their own Jev use through ask-jev-type skills. Or do you accept the inheritance as you did for GH_TOKEN?
2. **Q1 / CR-7 / CR-8:** should preflight make a real, paid, up-to-60-s Jev call, or print "Jev picks under start (threshold t)" without calling? If it calls, should the docs say the runner asks again and may pick differently?
3. **CR-4:** should a key that does not start `sk-or-` be passed to the unit at all?
4. **CR-6:** should a confidence above 1 count as a malformed answer (static) rather than a pass?
5. **CR-3:** should `start` and `resume` refuse a bad `JOB_JEV_MIN_CONF` (and bad `JOB_*` counts) before creating the unit?
6. **CR-10:** should SKILL.md's hand-over export OPENROUTER_API_KEY, so a skill-driven start actually uses Jev?
7. Does the threshold apply to a key rotated or revoked during a long pause? It falls back safely today; should the docs say a stop plus resume is needed to refresh the key?
8. "P6Q7" in spec K8: which question is that? I could not find it in the repo (unverified).

**Not verifiable statically:**
- That `systemd-run --setenv=NAME` with no value carries this key under a real unit (inferred from the GH_TOKEN precedent).
- How jq treats a `nan` literal.
- Whether OpenRouter error bodies never echo key material.
- When the transient unit files are removed after `stop` or `--collect`.
