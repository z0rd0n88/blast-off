# Code review: commit 096062b (phase 7 round 1 fixes, issue 27)

**Verdict: APPROVE.** No CRITICAL or HIGH findings, 0 MEDIUM, 13 LOW.

Of the 28 round 1 findings, 21 are closed and 4 are partly closed. 2 were refuted or left as already handled, and I agree with both. 2 are deferred by the owner.

## What I did
- Read `git diff 99ef3f6..096062b` and the whole phase diff.
- Read every touched file in full: `lib/{jev,units,chain,child,preflight,usage}.sh`, `bin/blast-off`, `tests/{lib.sh,11,12,60,61}`, `tests/fakes/{jev,claude}`.
- Checked the SKILL.md, brief.md, spec.md, README and deviations wording against the code.
- Read-only probes:
  - `bash -n` on all 13 touched scripts: all clean.
  - `${!v@Q}` and the threshold regex on bash 5.2.21, with literal values only.
  - jq 1.7 on literal JSON for the confidence expressions.
  - Read real `~/.local/bin/jev` (same bytes as JevDev's), lines 115-136, without running it.
- I ran no tests, no gate, no jev and no OpenRouter call, and wrote nothing.

Verified correct:
- `${!v@Q}` puts a value holding a newline on one line (`$'0.7\nx'`).
- The regex rejects `0.7\n`.
- `unit_env`'s key rule matches `jev_flags`'s three checks exactly.
- `child_server` drops the key from the tmux server's global environment. `new-window` passes only `-e JOB_DIR`/`JOB_CHILD`, so children cannot get it.
- Every new test can fail on the old code: `p-nl`, `p-unset`, `forgeconf`, `forgelvl`, `errkey`, `null`, `over`, `badconf b1-b3`, the k4 `openrouter=unset` check and the 61 why-column checks.
- `nokey` now needs grep rc 1, so a missing path (rc 2) fails it.

## Findings

[LOW] CR2-1: preflight's "start passes none" uses a different rule from `unit_env` (a regression from the P7R1-7 fix)
File: lib/preflight.sh:28
- Evidence: `echo "level: phase $k: static CLAUDE_FLAGS under start ($JEV_WHY$([ -n "${OPENROUTER_API_KEY:-}" ] || echo '; start passes none'))"`
- Since P7R1-7, `start` also passes no key when `JOB_JEV=0` or the key is not `sk-or-` (units.sh:23). The suffix still only checks for an empty key.
- Result:
  - `JOB_JEV=0 OPENROUTER_API_KEY=sk-or-x blast-off preflight <job>` prints `(JOB_JEV=0)` with no "start passes none", though start passes none.
  - Same for `OPENROUTER_API_KEY=tsk-x`.
  - The reverse case is fine: with `sk-or-` set and jev missing, the line says `(jev not on PATH)` and start does pass the key.
- Fix: test the same predicate as unit_env, e.g. `{ [ "${JOB_JEV:-1}" = 0 ] || [[ ${OPENROUTER_API_KEY:-} != sk-or-* ]]; } && echo '; start passes none'`, or share one helper.

[LOW] CR2-2: two comments still say the key is passed "when it is set" (stale after P7R1-7)
Files: lib/preflight.sh:21, tests/60-preflight.sh:4
- Evidence: `# start's view: start and the resume timer pass OPENROUTER_API_KEY by name when it is set (issue 27)`
- Evidence: `# ... start passes OPENROUTER_API_KEY by name when it is set, issue 27;`
- The fixer's notes say these were left out on purpose, but they are now false.
- Fix: change both to "when Jev can use it (sk-or-, JOB_JEV not 0)".

[LOW] CR2-3: preflight's level line states facts about `start` that the docs now call a forecast
File: lib/preflight.sh:26-29 (wording only; I am not re-raising the owner's decision to keep the call)
- Evidence: `level: phase 2: static CLAUDE_FLAGS under start (no OPENROUTER_API_KEY in the runner environment; start passes none)`.
- SKILL.md:67-68 says the line is "a forecast: the runner asks again with the environment `start` passes from the owner's shell, so the two can differ".
- In the flow SKILL describes (preflight from the agent's Bash tool, which has no key; `start` from the owner's terminal, which has one), "under start", "the runner environment" and "start passes none" are all false statements printed as fact.
- Fix: word it as preflight's own view, e.g. `level: phase 2: static CLAUDE_FLAGS in this shell (...; a start from this shell passes none)`. Line 29 likewise.

[LOW] CR2-4: SKILL.md step 7 says `start` passes the key without the JOB_JEV condition, and "them" can be read two ways
File: skills/blast-off/SKILL.md:63-66
- Evidence: `when the shell that runs start has OPENROUTER_API_KEY (an OpenRouter sk-or- key), start passes it to the unit by name and Jev then picks ... (its other flags stay; a pick below JOB_JEV_MIN_CONF, default 0.7, keeps them); JOB_JEV=0, exported before start, keeps CLAUDE_FLAGS for every phase.`
- (a) With `JOB_JEV=0`, `start` does not pass the key (units.sh:23). The first clause says it does.
- (b) "keeps them": the nearest plural is "its other flags", so one reading is "a low pick keeps the other flags", which is always true and says nothing. The intended reading is "keeps CLAUDE_FLAGS's --model/--effort".
- (c) "has OPENROUTER_API_KEY" means exported. The hand-over block exports only `GH_TOKEN CLAUDE_FLAGS`, and a non-exported shell variable never reaches blast-off.
- (d) "Step 6's level line is preflight's own Jev call" is not always true: with no key, `JOB_JEV=0` or no open row, there is no call.
- Fix: "when `OPENROUTER_API_KEY` (an `sk-or-` key) is exported in the shell that runs `start` and `JOB_JEV` is not 0, ...; a pick below `JOB_JEV_MIN_CONF` (default 0.7) keeps `CLAUDE_FLAGS`'s own `--model`/`--effort`".

[LOW] CR2-5: brief.md D1 "keeps them" can be read two ways
File: templates/brief.md:18
- Evidence: `when the runner holds Jev's key, Jev may pick each phase's --model/--effort, and JOB_JEV=0 keeps them`
- "them" follows "Jev may pick each phase's `--model`/`--effort`", so "JOB_JEV=0 keeps [Jev's picks]" is a valid reading and the opposite of the meaning. Children read this row and are told to quote it.
- "Jev's key" also does not say it must be `sk-or-`.
- Fix: "...; `JOB_JEV=0` keeps the launch line's `--model`/`--effort` for every phase".

[LOW] CR2-6: preflight key-leak checks still use the weak form P7R1-16 fixed elsewhere; the p14 check cannot fail
File: tests/60-preflight.sh:78, :94
- Evidence: `! grep -q -- "$key" p14.out || fail "preflight printed the key's value on a low-confidence pick"`
- These are full-literal and `! grep -q` form. A missing file (rc 2) passes, and a partial leak passes.
- The low-confidence path never prints the key or any key-derived text, so no realistic regression makes :94 fail. It adds coverage in name only (P7R1-15's third part).
- Fix: use the 12/61 helper: 12-char prefix and suffix with `-F`, and require rc 1.

[LOW] CR2-7: the new real-unit test's leak check cannot fail, and its jev-failed match is loose
File: tests/11-unit-smoke.sh:97-99
- Evidence: `! grep -q sk-or-fake-p7r1-6 "$JOB/run.log"`. The fake jev fails at `: "${FAKE_JEV:?...}"` (fakes/jev:12) before it could echo anything, so the key can never reach run.log here.
- `grep -q '... (jev failed: '` accepts any jev failure. The fake is first on PATH and `--setenv=PATH` carries that, so it is fine today.
- Fix: match `fake jev needs FAKE_JEV` so the test shows the fake ran. Drop the leak line or turn on `echo-key`, though echo-key needs `FAKE_JEV`, so in practice drop it.

[LOW] CR2-8: the jev stderr temp file holds the raw, unmasked stderr, contrary to the new spec wording; a signal mid-call leaves it behind (rest of P7R1-23)
Files: lib/jev.sh:39-43, docs/spec.md:68
- Evidence: `if ! out="$(... jev -q "$JEV_Q" level 2> "$err")"; then` / `rm -f "$err"`. Masking applies only to the 200 bytes copied into `JEV_WHY`.
- spec:68 now reads `blast-off writes no secret (GH_TOKEN, OPENROUTER_API_KEY) to any file`.
- In the exact case the fix was built for (an error that echoes the bearer key, fakes/jev `echo-key`), the key goes to `$XDG_RUNTIME_DIR/blast-off-jev.XXXXXX` until `rm`. A TERM to the runner, or Ctrl-C in preflight, during the up to 60 s call leaves the file. The directory is 0700, so the exposure is small.
- Fix: no temp file at all, e.g. `out="$(... 2>&1 >&3)"` style capture, or `{ ... } 2> >(head -c 200 ...)`. Or add a `trap 'rm -f "$err"' RETURN` and reword spec:68 to "beyond a jev stderr temp file removed after the call".

[LOW] CR2-9: mktemp's own error line goes into preflight's output
File: lib/jev.sh:39
- Evidence: `err="$(mktemp "${XDG_RUNTIME_DIR:-/tmp}/blast-off-jev.XXXXXX")" || { JEV_WHY="jev not asked: ..."; return 0; }` with no `2>/dev/null`.
- To reproduce: `XDG_RUNTIME_DIR=/nonexistent blast-off preflight <job>` (the p-notmp case). The output gains a bare `mktemp: failed to create file via template ...` line, breaking preflight's "one `name: value` line each" contract (spec preflight row). The test only checks the level line, so it passes.
- Under the unit, the line goes to the journal, which is harmless.
- Fix: `mktemp ... 2>/dev/null`.

[LOW] CR2-10: a refused level is cleaned of control characters but not length-capped (confidence is capped at 40)
File: lib/jev.sh:45
- Evidence: `level="${level//[![:print:]]/ }"; JEV_WHY="jev answered '${level:-nothing}', not a level"`
- A 10 KB `choice` string from a garbled or hostile answer becomes a 10 KB run.log line and decisions.tsv field, and is echoed by preflight. It forges no lines (good), but it does not match the 40-character cap the fix put on confidence.
- Fix: `level="${level:0:40}"` after the replace.

[LOW] CR2-11: tojson does not escape C1 controls; a NaN confidence gets a misleading reason (info)
File: lib/jev.sh:46-47
- Evidence on jq-1.7: `{"confidence":"\u009b31mX"}` | `tojson|.[:40]` outputs the raw bytes `302 233` (U+009B, 8-bit CSI) in the logged reason. The `level` and stderr paths do strip these (`[![:print:]]`, `tr -c`).
- `{"confidence":NaN}` (jq accepts it) gives case word `range` and JEV_CONF `null`, so it logs "confidence null is not from 0 to 1". The fallback is still correct.
- The 40-character cut can also leave a dangling `\`.
- Only a hostile or garbled answer triggers any of this.
- Fix (optional): pipe JEV_CONF through the same `[![:print:]]` replace. Use `isnan` → "nan" before the range test.

[LOW] CR2-12: spec catalog rows miss the new cases
File: docs/spec.md:240, :255
- The 11-unit-smoke row does not mention the new keyjob case (a real unit carries the fake key; the runner reaches jev). Row 12 at :241 says "no real unit carries the key here; `11-unit-smoke` does", which row 11 does not back up.
- The 61-jev-pick row does not list `errkey` (an error echoing the key is logged masked as `sk-or-...`) or `forgelvl` (a multi-line answer stays one run.log line).
- Row 12 lists "unset or empty", but the test now also covers `JOB_JEV=0` and a `tsk-` key (`off`, `tskey`). This one understates, which is harmless.
- Fix: add one clause per case.

[LOW] CR2-13: test 12's tskey value shares the 12-character suffix `nokey` matches on (fragile, info)
File: tests/12-start-env.sh:34, :71
- Evidence: `key=sk-or-test-xxx-not-a-key-27` and `tskey) set -- OPENROUTER_API_KEY=tsk-fake-not-a-key-27`. `${key: -12}` is `not-a-key-27`, which the tskey value contains.
- Nothing runs `nokey` on k2.out or the keyed job today, so nothing fails now. A future `nokey k2.out` would fail falsely.
- Fix: give the tskey value a different suffix, e.g. `tsk-fake-ts-27`.

## Round 1 closure

| ID | Status | Notes |
|---|---|---|
| P7R1-1 | closed | `env $scrub -u OPENROUTER_API_KEY` (child.sh:22); fakes/claude records `openrouter=`; 12 k4 asserts `openrouter=unset`. Spec :67/:129 and README updated. |
| P7R1-2 | closed | k1 and k4 set `JOB_JEV_MIN_CONF=0.9` and assert `--setenv=JOB_JEV_MIN_CONF`. `--setenv=JOB_JEV` is still not asserted (pre-existing; the `off` case passes it but never greps for it). |
| P7R1-3 | closed | 61 checks column 4 for the pick row and in `fallback()`. |
| P7R1-4 | partly closed | spec K8, the preflight row and SKILL.md now say forecast. Left: stale comments (CR2-2); preflight's own output still states facts about start (CR2-3); SKILL wording (CR2-4). |
| P7R1-5 | closed | `unit_check` calls `chain_nums` (units.sh:37, before any systemd-run); chain_run logs to run.log (chain.sh:154); 12 b1-b3 cover start, resume and run. status/wait not showing it was decided. |
| P7R1-6 | closed | 11 keyjob under a real unit; key=set checked in k3 and k4; dead `FAKE_JEV` removed. 11's leak line is weak (CR2-7). |
| P7R1-7 | closed | units.sh:23 uses the same predicate as jev_flags; 12 `off`/`tskey` cases. Side effect: preflight suffix is now out of step (CR2-1). |
| P7R1-8 | closed | tojson cut to 40; none/nan/range arms; forgeconf checks no `^2099` line and 6 columns. Small leftover: C1 controls (CR2-11). |
| P7R1-9 | closed | stderr has non-printables replaced and `sk-or-` masked; level has non-printables replaced; errkey and forgelvl tests. Leftovers: no length cap on level (CR2-10); raw stderr in the temp file (CR2-8). |
| P7R1-10 | closed | `range` arm; `over` (1.5) test. |
| P7R1-11 | closed | `none` arm (`. == null` covers missing and null); `null` test. Missing-field case untested but takes the same branch. |
| P7R1-12 | closed (no edit needed) | Agree it cannot be reached (both callers run `chain_nums`, and the regex admits only valid JSON numbers). The catch-all wording is now accurate ("could not be checked"). |
| P7R1-13 | closed | `picked empty ... JOB_JEV_MIN_CONF=`. |
| P7R1-14 | closed | 0 and 1.000 accepted; 00.7, 0.1234 and `1.` refused. `0.000` not tried (minor). |
| P7R1-15 | closed | p15 checked to be one line; jev call count checked as 2 (p-notmp makes no call, so that count is right). The p14 key check is weak (CR2-6). |
| P7R1-16 | partly closed | 12 and 61 fixed (prefix/suffix with `-F`, rc must be 1). Left: 60:78/:94 and 11:99 still use `! grep -q` with the full key. |
| P7R1-17 | closed | `argv()` fails on more than one recorded call. |
| P7R1-18 | closed | lib.sh unsets `JOB_JEV` and `JOB_JEV_MIN_CONF`. |
| P7R1-19 | closed | D14, D21 (true: decision-log row 33 shows D21 accepted), :203, deviations :31, README, child.sh header and brief D1 all updated. Ambiguity in D1 (CR2-5). |
| P7R1-20 | closed | header and row 12 now match the scenario; k3 checks no value on argv. Unset/empty still tested for start only, and the row says so honestly. Row 11 gap (CR2-12). |
| P7R1-21 | closed | documented in spec :204-206 and README. |
| P7R1-22 | deferred | Owner decision; not re-raised. |
| P7R1-23 | partly closed | mktemp failure now falls back (tested). Left: signal leaves the temp file, which holds raw unmasked stderr (CR2-8); mktemp's stderr line in preflight output (CR2-9). |
| P7R1-24 | not changed, refutation accepted | Read real jev:121-123: curl `-sS --fail-with-body -m 30` writes curl's error or the body to stderr, so a timeout inside curl gives a non-empty reason. |
| P7R1-25 | closed | `${CLAUDE_FLAGS:-}` at jev.sh:31 and :55; 60 `p-unset`, run with the key set, so both lines are exercised. |
| P7R1-26 | closed | `${!v@Q}` / `${JOB_JEV_MIN_CONF@Q}`; 60 `p-nl` would fail on the old code. |
| P7R1-27 | deferred | Owner decision; not re-raised. |
| P7R1-28 | not changed, refutation accepted | Real jev:129 prints `.answers` for raw `-q`, so the fake's `{level:{choice,confidence}}` shape matches. |

## Review Summary

| Severity | Count | Status |
|----------|-------|--------|
| CRITICAL | 0 | pass |
| HIGH | 0 | pass |
| MEDIUM | 0 | info |
| LOW | 13 | note |

Verdict: APPROVE. The code fixes are correct and their tests can fail. What is left is wording that can mislead (CR2-1, CR2-3, CR2-4, CR2-5) and weak or missing test and doc coverage.
