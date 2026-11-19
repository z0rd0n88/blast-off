# Review: phase 7 (issue 27, Jev's key reaches the unit; confidence threshold), round 2 (narrow)

Fix commit 096062b against 99ef3f6 (`git diff 99ef3f6..096062b -- . ':!baton-runner'`, 17 files), read against the
phase diff `git diff e924be8...096062b -- . ':!baton-runner'`. Two static lenses (`review-phase-7-iter-2/<lens>.md`,
saved verbatim from their hand-backs): code-reviewer (CR2-1..13) and silent-failure-hunter (SF2-1..11). Then the
review unit reproduced their concrete claims on a `git archive 096062b` copy in the scratchpad.

## Executive summary

- Gate: `scripts/gate.sh baton-runner/br-1115-issues/gate-phase-7-iter-2` exit 0, last line
  `GATE: PASS passed=19 failed=0 shellcheck=ok` (`gate-phase-7-iter-2/tests-run.log`).
- ExecStart was `ExecStart=/home/alex/blast-off/.worktrees/blast-off-build/bin/blast-off run %f` before the gate,
  after it, after each reproduction run, and at the end.
- Round 1: 21 findings closed, 4 partly closed (P7R1-4, P7R1-9, P7R1-16, P7R1-23), 2 refutations accepted (P7R1-24,
  P7R1-28; P7R1-12 needed no edit), 2 deferred by the owner (P7R1-22, P7R1-27). Every leftover is listed below as a
  P7R2 finding.
- 0 CRITICAL, 0 HIGH, 1 MEDIUM, 16 LOW.
  - The MEDIUM, P7R2-1: under `start`, a key that is not `sk-or-` is dropped by unit_env, and the runner then logs
    `no OPENROUTER_API_KEY in the runner environment`, while preflight says the key is not an sk-or- key.
    Reproduced.
- Most LOWs are wording that can mislead (preflight's level line, SKILL.md step 7, brief.md D1), the jev stderr temp
  file (holds an echoed key in clear and survives a TERM, reproduced), and test checks that cannot fail.

**VERDICT: CLEAN** (gate exit 0, zero CRITICAL/HIGH).

## Critical

None.

## High

None.

## Medium

**P7R2-1. Under `start`, a key that is not sk-or- is silently dropped, and the runner's reason says there is no key**
- Reported by: silent-failure-hunter SF2-1 (MEDIUM). Side effect of the P7R1-7 fix.
- Location: `lib/units.sh:23`, `lib/jev.sh:34-36`.
- Evidence:
  - `lib/units.sh:23`: `[ "${JOB_JEV:-1}" = 0 ] || [[ ${OPENROUTER_API_KEY:-} != sk-or-* ]] || UNIT_ENV+=(--setenv=OPENROUTER_API_KEY)`.
    `start` prints nothing when it drops the key.
  - The runner then has no key, so it logs `jev.sh:34`'s reason, never the accurate one at `:35-36`, which only a
    foreground `run` or `preflight` can reach.
  - So for one job, preflight says "not an sk-or- key" and run.log and decisions.tsv say "no key in the runner
    environment". That sends the owner to debug systemd env passing, not the key's prefix.
- Reproduced (probe scenario on the archive copy):
  - `unit_env` with `OPENROUTER_API_KEY=tsk-fake-probe`: OPENROUTER entries = 0.
  - preflight with that key: `level: phase 1: static CLAUDE_FLAGS under start (OPENROUTER_API_KEY is not an OpenRouter sk-or- key; Jev runs only through OpenRouter)`.
  - The runner without the key, which is what `start` gives it: `model level for phase 1: static CLAUDE_FLAGS (no OPENROUTER_API_KEY in the runner environment): --model fake --effort low`.
- Test gap: test 12's `tskey` case checks argv only.
- Suggested fix (owner question 1). Pick one:
  - (a) `unit_start` prints one terminal line when a set key is not passed, with the cause (not sk-or-, or `JOB_JEV=0`).
  - (b) Reword `jev.sh:34` to name the rule: "no OPENROUTER_API_KEY in the runner environment (start and the resume
    timer pass it only when it starts sk-or- and JOB_JEV is not 0)".

## Medium / Low

| ID | Sev | Title | Location | Reported by | Evidence, reproduced or static | Suggested fix |
|---|---|---|---|---|---|---|
| P7R2-2 | LOW | Preflight's "start passes none" uses a different rule from unit_env; two comments still say "when it is set" | `lib/preflight.sh:21,28`; `tests/60-preflight.sh:4` | CR2-1, CR2-2, SF2-2 | **Reproduced:** with a `tsk-` key the level line ends `(... not an OpenRouter sk-or- key; ...)`; with `JOB_JEV=0` and an `sk-or-` key it ends `(JOB_JEV=0)`. Neither line has `; start passes none`, but start passes none in both cases. With no key the suffix does appear. The comments are **static**: :21 says `by name when it is set (issue 27)` | Test the unit_env predicate for the suffix; reword both comments to "when Jev can use it (sk-or-, JOB_JEV not 0)" |
| P7R2-3 | LOW | Preflight's level line states its forecast as fact about `start` | `lib/preflight.sh:26-29` | CR2-3 | **Static:** `static CLAUDE_FLAGS under start (no OPENROUTER_API_KEY in the runner environment; start passes none)`. In SKILL's flow, preflight runs in the agent's shell and `start` runs in the owner's, so "under start", "the runner environment" and "start passes none" can all be false. SKILL.md:67-68 calls this line a forecast | Word it as this shell's view, e.g. `static CLAUDE_FLAGS in this shell (...; a start from this shell passes none)`, :29 likewise. Wording only: the owner's Q1 ruling stands |
| P7R2-4 | LOW | SKILL.md step 7: the condition is missing `JOB_JEV`, "them" parses two ways, and the fallbacks are underclaimed | `skills/blast-off/SKILL.md:63-68` | CR2-4, SF2-11 | **Static:** (a) "`start` passes it to the unit by name" is false with `JOB_JEV=0` (units.sh:23). (b) In "its other flags stay; a pick below `JOB_JEV_MIN_CONF` ... keeps them", "them" can mean "its other flags", which is always true, or `CLAUDE_FLAGS`'s `--model`/`--effort`, which is the meaning. "its" can be read as Jev's or CLAUDE_FLAGS'. (c) "has `OPENROUTER_API_KEY`" must mean exported, but the hand-over exports only `GH_TOKEN CLAUDE_FLAGS`. (d) "(an OpenRouter `sk-or-` key)" reads as a description, not a condition, so a non-sk-or- key is silently not passed (P7R2-1). (e) Only low confidence is named as a fallback; jev missing, a jev failure, `other`, and a missing/null/out-of-range confidence keep CLAUDE_FLAGS too. (f) Nothing says run.log's `model level` line is where a fallback and its reason show. (g) "Step 6's `level` line is preflight's own Jev call" is not true when there is no call (no key, `JOB_JEV=0`, no open row) | "When `OPENROUTER_API_KEY` (only an `sk-or-` key counts) is exported in the shell that runs `start` and `JOB_JEV` is not 0, ...; a pick below `JOB_JEV_MIN_CONF` (default 0.7), or any Jev failure, keeps `CLAUDE_FLAGS`'s own `--model`/`--effort`; each pick or fallback, with its reason, is a `model level` line in run.log" |
| P7R2-5 | LOW | brief.md D1: "`JOB_JEV=0` keeps them" can mean Jev's picks | `templates/brief.md:18` | CR2-5 (SF found no finding: "hedged with may") | **Static:** `when the runner holds Jev's key, Jev may pick each phase's --model/--effort, and JOB_JEV=0 keeps them`. The nearest antecedent is the picks, which is the opposite of the meaning, and children quote this row. My read: it does parse two ways | "...; `JOB_JEV=0` keeps the launch line's `--model`/`--effort` for every phase" |
| P7R2-6 | LOW | The jev stderr temp file holds raw stderr, an echoed key included, and a TERM mid-call leaves it behind; spec:68 says no secret is written to any file | `lib/jev.sh:39-43`; `docs/spec.md:68` | CR2-8, SF2-5 (the signal half of P7R1-23) | **Reproduced:** probe J. A jev that echoes the key on stderr then sleeps; TERM to `preflight` 2 s in. After the jev exits, 1 `blast-off-jev.*` file is left in `$XDG_RUNTIME_DIR`, and it holds the key's value in clear. Static: masking applies only to the 200 bytes copied into `JEV_WHY`. Under the unit, `KillMode=control-group` kills jev too, but `rm` still never runs. The dir is 0700 tmpfs, and the real jev's curl errors are not known to echo the key | No temp file: capture stderr through a pipe or a process substitution with `head -c 200`; or `trap 'rm -f "$err"' RETURN` plus a cleanup in chain_exit. Either way, make spec:68 true (owner question 3) |
| P7R2-7 | LOW | mktemp's own error line lands in preflight's output | `lib/jev.sh:39` | CR2-9 | **Reproduced:** with `XDG_RUNTIME_DIR` set to a missing dir, the level line is right (`jev not asked: no temp file in ...`), but one stray `mktemp: failed to create file via template ...` line is printed, breaking preflight's one `name: value` line contract. Test 60's p-notmp checks only the level line | `mktemp ... 2>/dev/null` |
| P7R2-8 | LOW | A refused level is not length-capped and not key-masked | `lib/jev.sh:45` | CR2-10, SF2-6 | **Reproduced:** a 500-character answer gives a 579-byte preflight level line, and the same goes to run.log and decisions.tsv. An answer `sk-or-v1-probe-key-shaped-text` is printed in clear: `(jev answered 'sk-or-v1-probe-key-shaped-text', not a level)`. The stderr path cuts to 200 bytes and masks; this path does neither. It needs a hostile or garbled answer | Apply the stderr path's cut and `sk-or-` mask to `level`, or `level="${level:0:40}"` after the replace |
| P7R2-9 | LOW | "jev failed:" with an empty reason when jev dies silently (a timeout kill, a signal, OOM) | `lib/jev.sh:41` | SF2-3 | **Reproduced:** a jev that exits 124 with no stderr gives `level: phase 1: static CLAUDE_FLAGS under start (jev failed: )`. P7R1-24's refutation covers the curl path (curl `-m 30` prints its error), not a hang outside curl or a kill | Keep `rc=$?` and log `jev failed (exit $rc; 124 = timed out after 60 s): <stderr>` |
| P7R2-10 | LOW | A jq parse failure on jev's stdout reads as "jev answered 'nothing'" | `lib/jev.sh:44-45` | SF2-4 | **Static.** `2>/dev/null \|\| true` swallows a non-JSON or wrong-shape answer. This is the second half of P7R1-24, which was refuted for the real client (jev cannot exit 0 with non-JSON). SF calls it defence in depth only. My read: the refutation holds, and no action is needed unless the jev client changes | Optional: when `jq -e '.level \| type == "object"'` fails, log "jev output is not the expected JSON" |
| P7R2-11 | LOW | The 40-character cut on a non-number confidence is never exercised | `lib/jev.sh:46`; `tests/61-jev-pick.sh:84-85` | SF2-7 | **Reproduced:** `forgeconf`'s confidence is 37 characters after `tojson` (jq-1.7). Mutant `else tojson end` (cut dropped), with `BLAST_OFF_TEST_ONLY=61-jev-pick` -> `GATE-ONLY: PASS passed=1 failed=0`, so it survives. The jev.sh comment and spec row 61 claim a cut that nothing pins | Add a confidence string over 40 characters, and assert that the logged value is exactly 40 characters |
| P7R2-12 | LOW | `tojson` leaves C1 controls raw; a NaN confidence logs "confidence null is not from 0 to 1" | `lib/jev.sh:46-47` | CR2-11 | **Reproduced** at jq level (jq-1.7): `"\u009b31mX"` comes out with raw bytes `302 233` (8-bit CSI) in JEV_CONF. `NaN` gives case `range` and JEV_CONF `null`. The fallback is still correct. A 40-character cut can also leave a dangling `\`. Needs a hostile or garbled answer | Pass JEV_CONF through the `[![:print:]]` replace; map `isnan` to "nan" |
| P7R2-13 | LOW | Key-leak checks that cannot fail remain in tests 60 and 11 (rest of P7R1-16) | `tests/60-preflight.sh:78,94`; `tests/11-unit-smoke.sh:97-99` | CR2-6, CR2-7, SF2-8 | **Static:** `! grep -q -- "$key" p14.out` (full literal; passes on rc 2 and on a partial leak). In 11's keyjob the fake jev fails at `: "${FAKE_JEV:?...}"` (fakes/jev:12) before it could echo anything, so `! grep -q sk-or-fake-p7r1-6 "$JOB/run.log"` cannot fail through the jev path. Also, 11's `(jev failed: ` match accepts any jev failure | Use test 12's `nokey` form (12-char prefix and suffix, `-F`, rc must be 1) over the whole job dir; in 11, match `fake jev needs FAKE_JEV` so the test proves the fake ran |
| P7R2-14 | LOW | The run.log refusal line is bare and is written before the runner lock | `lib/chain.sh:154` | SF2-9 | **Reproduced:** after `JOB_JEV_MIN_CONF=.7 run`, run.log holds only `JOB_JEV_MIN_CONF='.7' is not a number from 0 to 1 with at most 3 decimals (0.7, 0.85, 1)`, with no "run refused" and no exit line. **Static:** :154 runs before `chain_lock` (:164), so a second `run` with a bad value appends into a live runner's run.log. chain_count's line at :155 has the same pre-existing shape | Prefix `run refused: ` (both :154 and :155) |
| P7R2-15 | LOW | `JOB_JEV` is unvalidated; `JOB_JEV=false` leaves Jev on and now stores the key in the unit | `lib/units.sh:23`; `lib/jev.sh:33` | SF2-10 | **Reproduced:** `unit_env` with `JOB_JEV=false` and an sk-or- key: OPENROUTER entries = 1. Only the literal `0` turns Jev off (`no`, `off`, `00` and `" 0"` too). This is new impact of an old gap (P5R2-14 / phase 5 Q8) | `[[ ${JOB_JEV:-1} =~ ^[01]$ ]]` in `chain_nums`, if the owner agrees (owner question 2) |
| P7R2-16 | LOW | Spec catalog rows miss the new cases; row 12 points to a row 11 claim that is not there | `docs/spec.md:240,241,255` | CR2-12 | **Static (verified):** row 11 does not mention the keyjob case, yet row 12 says "no real unit carries the key here; `11-unit-smoke` does". Row 61 omits `errkey` (an echoed key logged masked) and `forgelvl`. Row 12 says "unset or empty" but the test also covers `off` and `tskey` | One clause per case |
| P7R2-17 | LOW | Test 12's `tskey` value shares the 12-character suffix that `nokey` matches (fragile, info) | `tests/12-start-env.sh:34,71` | CR2-13 | **Verified:** `${key: -12}` is `not-a-key-27`, and `tsk-fake-not-a-key-27` contains it. Nothing runs `nokey` on that output today | Give the tskey value a different suffix |

## Round 1 closure (one line each)

- P7R1-1 closed: `child_server` runs `env $scrub -u OPENROUTER_API_KEY`; fake claude records `openrouter=`; 12 k4 asserts unset.
- P7R1-2 closed: k1 and k4 set and assert `--setenv=JOB_JEV_MIN_CONF`. `--setenv=JOB_JEV` is still unasserted, which is pre-existing and was noted in round 1.
- P7R1-3 closed: 61 pins column 4 for the pick and every fallback.
- P7R1-4 partly closed: spec and SKILL say forecast. Left: P7R2-2 comments, P7R2-3 preflight output wording, P7R2-4 SKILL wording.
- P7R1-5 closed: `unit_check` calls `chain_nums` before any systemd-run; `chain_run` logs to run.log; 12 b1-b3 cover it (wording leftover: P7R2-14).
- P7R1-6 closed: 11 keyjob under a real unit; key=set in k3 and k4; dead `FAKE_JEV` gone (weak leak line: P7R2-13).
- P7R1-7 closed: unit_env uses jev_flags's predicate; 12 `off` and `tskey` (side effects: P7R2-1, P7R2-2; spot-checked by probe C).
- P7R1-8 closed: `tojson` cut to 40 plus none/nan/range arms; `forgeconf` passes (leftovers: P7R2-11, P7R2-12).
- P7R1-9 partly closed: stderr masked and cleaned, level cleaned. Left: level not capped or masked (P7R2-8); raw stderr in the temp file (P7R2-6).
- P7R1-10 closed: `range` arm, `over` test.
- P7R1-11 closed: `none` arm, `null` test (a missing field takes the same branch, untested).
- P7R1-12 closed, no edit needed: unreachable behind `chain_nums`; the catch-all now reads "could not be checked".
- P7R1-13 closed: `picked empty ... JOB_JEV_MIN_CONF=`.
- P7R1-14 closed: 0 and 1.000 taken; 00.7, 0.1234 and `1.` refused (0.000 untried).
- P7R1-15 closed: p15 is one line, jev called twice (weak p14 key check: P7R2-13).
- P7R1-16 partly closed: fixed in 12 and 61; still weak in 60:78,94 and 11:99 (P7R2-13).
- P7R1-17 closed: `argv()` fails on more than one non-scope call.
- P7R1-18 closed: lib.sh unsets `JOB_JEV` and `JOB_JEV_MIN_CONF`.
- P7R1-19 closed: D14, D21, :203, deviations, README, the child.sh header and D1 updated (D1 ambiguity: P7R2-5).
- P7R1-20 closed: the 12 header and row match; k3 checks the value is not on argv (row 11 gap: P7R2-16).
- P7R1-21 closed (docs only, per ruling): spec :204-206 and README say the timer keeps the armed values.
- P7R1-22 deferred by the owner (follow-up issue); not re-raised.
- P7R1-23 partly closed: a mktemp failure falls back (tested). Left: the signal case (P7R2-6) and mktemp's stderr line (P7R2-7).
- P7R1-24 refutation accepted for the curl path; the silent-kill case is P7R2-9.
- P7R1-25 closed: `${CLAUDE_FLAGS:-}`; 60 `p-unset`.
- P7R1-26 closed: `@Q` quoting; 60 `p-nl`.
- P7R1-27 deferred by the owner (follow-up issue); not re-raised.
- P7R1-28 refutation accepted: real jev:129 prints `.answers`, which matches the fake's shape.

## Open owner questions

1. P7R2-1: under `start`, should a set key that is not passed (not sk-or-, or `JOB_JEV=0`) print a line on the
   terminal, or should the runner's no-key reason name start's rule? Recommendation: (b), one string in jev.sh.
2. P7R2-15: should `JOB_JEV` accept only 0 or 1 (refused by `chain_nums` like the threshold)? Phase 5's Q8 on the
   same var may still be open.
3. P7R2-6: is a jev stderr temp file that can hold an echoed key acceptable, given that spec:68 says blast-off writes
   no secret to any file? Recommendation: drop the temp file.
4. P7R2-5: the two lenses disagree on whether brief.md D1 is ambiguous. My read is that it is; a one-phrase rewording
   settles it.

## Notes and deviations

- Gate: the brief's command `bash scripts/gate.sh > .../tests-run.log` omits gate.sh's required `<log-dir>` argument.
  That first call exited 1 at `usage: scripts/gate.sh <log-dir>` before running any scenario. I then ran it once as
  round 1 did, `scripts/gate.sh baton-runner/br-1115-issues/gate-phase-7-iter-2`, alone, before any reviewer. gate.sh's
  own `tee` overwrote the usage line in `tests-run.log`. Exit 0.
- `baton-runner/br-1115-issues/STATE.md` showed ` M` in git status before the gate. That is the manager's own UPDATE
  (6), which I did not touch.
- Lens reports were saved verbatim from each agent's SubagentHandback. Severities in the tables are mine after
  dedupe; each lens's own severity is in its file. The lenses ran read-only, with no tests, no jev and no edits.
- Reproductions were all on a `git archive 096062b` copy in my scratchpad subdir, one named scenario per run:
  - `BLAST_OFF_TEST_ONLY=98-p7r2probe`: a probe scenario that exists only in the copy, covering cases A, B, B2, C, D,
    E, F, F2, G, I and J. Result: `GATE-ONLY: PASS passed=1`, with its results written to a file.
  - `BLAST_OFF_TEST_ONLY=61-jev-pick` with the P7R2-11 mutant: PASS (the mutant survives). The file was then restored
    and `cmp`-checked.
  - jq literal checks for P7R2-11 and P7R2-12; a string check for P7R2-17.
- The real jev and OpenRouter were never called: fakes or probe stubs were first on PATH, every key was a fake
  `sk-or-fake-probe*` or `tsk-fake-probe` value, and lib.sh unsets the real key. The probe started no runner
  unit and no timer: it ran `preflight`, and one foreground `run` whose fake child ran in a child scope, as test 61
  does.
- Static only: P7R2-3, P7R2-4, P7R2-5, P7R2-10, P7R2-13, P7R2-16, and the interleave half of P7R2-14.
