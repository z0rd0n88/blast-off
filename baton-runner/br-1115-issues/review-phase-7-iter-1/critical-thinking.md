# critical-thinking: phase 7 review, round 1 (static, read-only)

Static review of phase 7 (514d0ef vs e924be8), done in the critical-thinking role. I only read files. I ran no tests, no git and no systemd commands, and I did not read ~/.secrets or any settings.local.json. To check jev's real output shape I read /home/alex/JevDev/bin/jev (`~/.local/bin/jev` points to it).

**Verdict:** C1, C2 and C3 and the owner sign-off are each met in code and pinned by tests that would fail if broken. I found no CRITICAL or HIGH defect. Two MEDIUM items need an owner decision: children now inherit the key, and preflight's prediction can be wrong in the documented workflow. The rest are LOW.

## 1. Criteria and sign-off

- **C1 (key set: the model comes from Jev and is logged): met.**
  - Code: `lib/units.sh:22` adds the name only. `lib/jev.sh:46-53` takes the pick at or above the threshold. `lib/jev.sh:69` logs it with confidence and threshold, and `lib/jev.sh:71-75` writes it to decisions.tsv.
  - Tests:
    - `tests/12-start-env.sh:223-230` covers start's argv, the printed line, the key reaching systemd-run's environment, and the value appearing nowhere.
    - `:241-247` covers resume and `:250-258` the resume timer.
    - `tests/61-jev-pick.sh:22-37` covers the runner-side pick with `threshold 0.7` in run.log.
    - `tests/60-preflight.sh:292-294,303-305` covers preflight.
  - The implementer's notes list killed mutants M3, M8, M12 and M10.
  - Gap (CT-9): no test proves a unit-started runner actually receives the value.
- **C2 (no key: static, logged): met.**
  - Code: the condition at `lib/units.sh:22`, and `lib/jev.sh:33`.
  - Tests: `tests/12-start-env.sh:232-239` (unset and empty pass no name), `tests/61-jev-pick.sh:53` (`nokey` reason logged), `tests/60-preflight.sh:323`. Mutants M1 and M2 were killed.
- **C3 (low-confidence pick keeps static): met.**
  - Code: `lib/jev.sh:46-49`.
  - Tests:
    - `tests/61-jev-pick.sh:373-378` covers 0.55 < 0.7, 0.87 < 0.9, and a confidence that is not a number.
    - `:389-391` covers a pick exactly at 0.7 being taken (kills `<=`), at 0.55 with 0.5, and at 1 with 1.0.
    - `tests/60-preflight.sh:307-310` covers preflight.
- **Sign-off (pass the key; 0.7 default; `JOB_JEV_MIN_CONF` override): met.**
  - Default at `lib/jev.sh:30` and `lib/chain.sh:100`.
  - Override tested at `61:376,390-391` and `60:307`.
  - Validation at `lib/chain.sh:100-101`, tested at `61:393-399` and `60:312-314`.

## 2. Findings

**CT-1 · MEDIUM · Children now inherit OPENROUTER_API_KEY in the main (start and timer) mode** (`lib/child.sh:11-22`)
- Evidence:
  - `child_server` removes only `CLAUDE*` names (`:13`), so the tmux server's global environment carries the key to every child.
  - Children run as the owner's user with bypass permissions (README.md:149, docs/spec.md:105).
  - A dead child's last 40 screen lines go to run.log (`lib/child.sh:98-99`). So a child that runs `env` while debugging puts the key in run.log or its transcript, and a prompt-injected child can send it out or spend on it.
  - Before phase 7 this happened only in a foreground `run` with the key. Now it is the default for `start` and the timer.
  - spec.md:67 documents it ("as they inherit GH_TOKEN"), but the owner's sign-off covers passing the key to the unit, not to children. That is Q2, still open.
- Note: removing it is not a hard boundary. A same-user child can still read `/proc/<runner>/environ` or `systemctl --user show -p Environment`. It cuts accidental leaks only.
- Fix: add `-u OPENROUTER_API_KEY` to `child_server`'s `env` call (the runner keeps it; only the tmux server loses it), unless children are meant to use jev or ask-jev themselves.
- Why does a child need the key at all, when the runner makes every Jev call?

**CT-2 · MEDIUM · Preflight's "under start" level can contradict what start actually does** (`lib/preflight.sh:21-29`; `skills/blast-off/SKILL.md:52,59,85-88`)
- Evidence:
  - Preflight now predicts from the caller's environment.
  - In the skill's workflow, the session's Bash tool runs preflight (step 6). AGENTS.md says that tool does not source `~/.bashrc`. The owner often runs `start` in a terminal, which does.
  - jev's own error text says "export from ~/.secrets" (JevDev/bin/jev:116). If the key lives there, the terminal's `start` passes it while the session's preflight printed `static CLAUDE_FLAGS under start (...; start passes none)`, or the other way round. **Unverified:** I did not read ~/.secrets.
  - SKILL.md never mentions Jev, `OPENROUTER_API_KEY` or `JOB_JEV`. It says `CLAUDE_FLAGS` is "the owner's string, verbatim" (`:42`) and hands over `export GH_TOKEN CLAUDE_FLAGS=...` (`:59`). Under phase 7, a key present in the owner's shell silently replaces `--model`/`--effort` per phase.
- Fix: in SKILL.md step 4/7, say that Jev replaces `--model`/`--effort` when the key is in start's environment and that `JOB_JEV=0` opts out. Run preflight in the same environment as start, or have preflight say whose environment it read.

**CT-3 · LOW · `start` and `resume` do not validate `JOB_JEV_MIN_CONF`; the refusal reaches only the journal** (`lib/units.sh:31-35`; `lib/chain.sh:153`; `bin/blast-off:56`)
- Evidence:
  - `unit_check` does not call `chain_nums`. A bad value still creates the unit, which stores GH_TOKEN and the key in the transient file.
  - The runner then fails at `chain_nums || die`, and `die` writes to stderr only. run.log gets nothing, unlike `chain_count`'s refusal at `:155`, which goes to run.log too (P4R1-2). `wait` then reports `stuck`.
  - Bad `JOB_*` counts already behave this way, so this matches the existing pattern. The spec says only "run and preflight refuse", which is accurate.
  - The paused status is kept: the refusal happens before the lock.
- Fix: call `chain_nums || die "$NUMS_ERR"` in `unit_check`, or have the refusal at `chain.sh:153` go through `log` too.

**CT-4 · LOW · The key is passed and stored even when it cannot be used** (`lib/units.sh:22`)
- Evidence: with `JOB_JEV=0`, or a key that does not start `sk-or-`, start still stores the secret in the transient unit file, and children get it, though the runner never uses it (`jev.sh:32,34`).
- Fix: `[ "${JOB_JEV:-1}" != 0 ] && [[ ${OPENROUTER_API_KEY:-} == sk-or-* ]] && UNIT_ENV+=(...)`.

**CT-5 · LOW · Jev response text reaches run.log and decisions.tsv raw** (`lib/jev.sh:45,49,44`)
- Evidence:
  - `JEV_CONF` comes from `jq -r` of a non-number confidence: a string with a tab or newline, or an object, which prints over several lines. It is embedded in `JEV_WHY`, which goes to run.log and decisions.tsv.
  - Only `\r` is stripped (`:75`). A tab breaks the 6-column TSV that test 61:38 checks. A newline can forge a run.log line, the P5R1-5 class.
  - `level` has the same exposure at `:44`, which predates this change.
  - Low likelihood: the source is the OpenRouter API.
- Fix: strip control characters and cut to about 40 characters before logging, or log `.level.confidence | tojson` cut short.

**CT-6 · LOW · A pick with no confidence now falls back (a behaviour change, not tested)** (`lib/jev.sh:45-49`)
- Evidence:
  - A null or missing `.level.confidence` gives `jev picked X, confidence '?' is not a number`, so static. In phase 6 such a pick was taken.
  - The real jev reads `.confidence` from choice answers (JevDev/bin/jev:135), so the field almost certainly exists. **Unverified** against a live response.
  - Other values, checked by reading the jq logic:
    - Values above 1 are taken.
    - Negatives fall back as "low".
    - Exponent forms (7e-1) are numbers and compare normally.
    - JSON cannot hold NaN. If a jq version accepted it, NaN sorts below every number, so it would fall back as "low" and print as `null`. **Unverified.**
- Fix: none needed. Optionally add a missing-confidence case to test 61.

**CT-7 · LOW · Preflight's Jev call: cost, latency, and how faithful the prediction is** (`lib/preflight.sh:15-23`; `lib/jev.sh:38-42`)
- Evidence:
  - Each preflight with the key now makes one paid OpenRouter call, bounded by jev's `curl -m 30` and blast-off's `timeout 60`.
  - The call happens even when preflight will refuse anyway (empty `CLAUDE_FLAGS` or a missing dependency, `:16-17`).
  - The runner asks Jev again at child 1, so preflight shows a sample, not the pick start will use. A confidence near 0.7 can flip between the two calls.
  - "Writes nothing" holds for the job dir. A temp err file is made in `$XDG_RUNTIME_DIR` and removed. If `mktemp` fails, `set -e` aborts preflight with no `preflight: refused` line. This path was unreachable in preflight before.
  - Leak check: jev sends the key in a header via stdin (`jev:119-123`), and its stderr on failure is curl's error or the HTTP body. I see no path that prints the key. **Unverified:** whether an OpenRouter error body ever repeats it.
- Fix: skip the Jev call when `probs` is already non-empty. Optionally mark the level line "sample".

**CT-8 · LOW (pre-existing, in a touched function) · Preflight with `CLAUDE_FLAGS` unset crashes under `set -u`** (`lib/jev.sh:30`; `bin/blast-off:47`)
- Evidence: `CHILD_FLAGS="$CLAUDE_FLAGS"` gives "unbound variable", exit 1, with no refusal line. The spec promises "`CLAUDE_FLAGS` unset or empty" is refused with every line printed. Test 60's p5 uses empty, never unset.
- Fix: `${CLAUDE_FLAGS:-}` in `jev_flags` (also `:51`).

**CT-9 · LOW · Test gaps**
- C1 under a real unit is pinned only by stub argv plus "key=set". No scenario shows a unit-started runner seeing the value. This relies on systemd's `-E NAME` semantics, which test 11 exercises for GH_TOKEN.
- The negative case (unset or empty key: no name passed) is tested for `start` only. Spec row 12 implies resume and the timer too.
- An empty `JOB_JEV_MIN_CONF` meaning the default (D-P7-3) is not tested.
- The key-not-printed check covers preflight's p1 only, not p14. The key cannot reach that path anyway.
- The implementer ran single scenarios, not the full gate, 11, 30 or 31. `gate-phase-7-iter-1/` exists but I did not read it, so whether the full gate passed is **unverified**.

**CT-10 · LOW · Test 12's stub systemd-run** (`tests/12-start-env.sh:214-219`)
- It hides no current real failure:
  - Real `start` is still covered by test 11, without the key.
  - `unit_start` does not check that the unit came up.
  - Child scopes pass through to the real binary.
  - It leaves no real unit or timer behind, which is good.
- Risks:
  - Any future non-`--scope` systemd-run call (for example `--wait`) silently returns 0.
  - In the k4 timer case, `FAKE_JEV="$PWD/jev"` is never created, so that case does not show Jev ran. It is not trying to.
  - If the stub ever fell off PATH, the real systemd-run would start a real unit holding the fake key. `argv()` would then come back empty and the test would fail, so this shows itself.
- Fix: optional. Have the stub fail loudly on any flag set it does not expect.

**CT-11 · LOW · Doc truth**
- docs/spec.md:68-71 still says "blast-off writes no secret (`GH_TOKEN`)" and "the token included", singular. There are now two secrets.
- docs/spec.md:26 cites "P6Q7", which appears nowhere else in the repo or the phase-6 notes, so it cannot be traced.
- README.md:63-67 does not say children inherit the key (the spec does), and does not say the timer freezes the key's value at arm time.
- templates/brief.md:18 (D1: child model "`CLAUDE_FLAGS` from the launch line") no longer describes start with the key.
- Spec row 12 overstates the unset/empty coverage (see CT-9).
- No stale "start passes no key" or open-P6Q1 wording remains in code, README, spec, SKILL.md, templates or scripts. The only hits are the historical `docs/decision-log/build-2026-11-04.tsv:140,145`, which are fine.
- The bin/blast-off header (lines 36-40) and the comments in `lib/jev.sh`, `lib/units.sh` and `lib/preflight.sh` match the code.
- The log line shapes quoted in README and spec match `lib/jev.sh:48,69`.

**CT-12 · LOW · Resume timer: the key is fixed when the timer is armed** (`lib/usage.sh:69-71`)
- Evidence:
  - The path works end to end: runner env, then `usage_arm`, then `unit_env`, then the timer service's env, then `resume`, `unit_start` and `unit_env` again, then the new runner. JOB_JEV_MIN_CONF flows the same way.
  - Key unset at arm and exported later: the timer's runner stays static until the owner runs `stop` then `start`.
  - Key set at arm and later rotated or revoked: the stale value is used, jev fails, and the fallback is logged (safe).
  - The value sits on tmpfs in the timer service's transient file for up to the 7-day pause. That is D21's accepted class, but longer than a run.
  - systemd-run's stderr is appended to run.log (`:71`). It carries names, not values; **unverified** for a malformed value.
- Fix: one README or spec sentence on the snapshot behaviour.

**CT-13 · INFO · Things checked and found sound**
- `chain_nums` runs before `jev_flags` on every path: `chain.sh:153` before `:216`, `preflight.sh:15` before `:23`, and there is no other caller. So `--argjson t "$JEV_MIN"` always gets valid JSON. If it ever did not, jq would fail into the "not a number" fallback: a misleading reason, but safe.
- The regex at `chain.sh:100` takes 0, 0.x to 0.xxx, 1, 1.0 to 1.000, and refuses .7, 1.5, -0.1, 0,7, 0.7x, 00.7, exponents and whitespace.
- Validation and use both read `${JOB_JEV_MIN_CONF:-0.7}`, so they agree.
- The `case "$(jq ...)"` is safe under `set -e`.
- The threshold is printed from the env string, not from jq, so `1.0` stays `1.0`.
- The key is never on argv or the printed launch line, and `status` prints no unit environment (`units.sh:73-83`).

## 3. Open questions for the owner

1. Q2: should children see OPENROUTER_API_KEY? Do any child workflows (ask-jev, hyper-jev) need it, or can `child_server` remove it?
2. Which environment is "start's" for preflight when a session runs preflight and the owner runs start in a terminal? Should SKILL.md tell the owner that Jev may replace `--model`/`--effort`, and that `JOB_JEV=0` opts out?
3. Was 0.7 checked against Jev's real confidence on this 4-way choice, which includes "other"? If most real picks come in under 0.7, every phase pays for a Jev call and still gets static flags. Do you want a look at decisions.tsv after the first real job?
4. Should a pick with a missing or null confidence fall back, which is new, or be taken as it was in phase 6?
5. Should the key be stored at all when `JOB_JEV=0`, or when it is not an `sk-or-` key?
6. Should `start` and `resume` refuse a bad `JOB_JEV_MIN_CONF` (and bad `JOB_*` counts) before creating a unit, instead of the runner refusing into the journal only?
7. What is P6Q7, which spec K8 says issue 27 settled?
8. Is it acceptable that a key exported after the timer is armed is not picked up, and that a rotated key is used stale until the timer fires?

**Unverified items, collected:** live Jev's response shape and confidence distribution; whether OpenRouter error bodies ever repeat the key; jq's handling of NaN or Infinity input; whether OPENROUTER_API_KEY is in the owner's shell from ~/.secrets (not read); systemd journal or stderr content for a malformed value; whether the full gate passed for phase 7.
