## Silent-failure review of commit 096062b (phase 7 round 1 fixes, issue 27)

I found 11 issues: 1 MEDIUM and 10 LOW. Nothing is CRITICAL or HIGH. I made no edits. I did not run jev, tests/run or gate.sh. I checked the two central claims with a pure-bash simulation that sources lib/units.sh and lib/jev.sh and calls no jev (snippet in SF2-1).

What the fix gets right: the round 1 items I could check hold up. mktemp failure, null, out-of-range and non-number confidences, stderr masking, the newline-forgery guards, the start/resume refusal before any unit, children having no key, and the argv() one-call guard are all fixed. Their tests discriminate old from new behaviour, with the exceptions in SF2-7 and SF2-8.

---

**SF2-1 · MEDIUM · lib/jev.sh:34 together with lib/units.sh:23. The fallback reason is misleading when the key is set but is not sk-or-.**
- **Issue:** `unit_env` now drops the key silently:
  - lib/units.sh:23: `[ "${JOB_JEV:-1}" = 0 ] || [[ ${OPENROUTER_API_KEY:-} != sk-or-* ]] || UNIT_ENV+=(--setenv=OPENROUTER_API_KEY)`
  - So the runner never sees the key, and jev.sh:34 logs `JEV_WHY="no OPENROUTER_API_KEY in the runner environment"`.
  - The accurate reason at jev.sh:35-36 ("OPENROUTER_API_KEY is not an OpenRouter sk-or- key...") cannot be reached under `start` or the resume timer. Only a foreground `run` or `preflight` can reach it.
  - `start` prints nothing on the terminal about dropping the key.
- **Impact:** an owner who exported a key (a TypeSafe one, or one with a stray quote or space in front) gets two different reasons:
  - preflight says "not an sk-or- key".
  - run.log and decisions.tsv for the real job say "no OPENROUTER_API_KEY in the runner environment".
  - That second reason sends the owner to debug systemd environment passing, not the key's prefix. The fallback is safe, but its stated cause is wrong.
- **Reproduce** (read-only, verified):
  ```bash
  cd <repo> && bash -c 'BLAST_OFF_HOME=$PWD; source lib/units.sh; source lib/jev.sh
  export OPENROUTER_API_KEY=tsk-fake; unit_env; printf "%s\n" "${UNIT_ENV[@]}" | grep -c OPENROUTER   # 0
  CLAUDE_FLAGS=x jev_flags row; echo "$JEV_WHY"     # preflight: "...is not an OpenRouter sk-or- key..."
  unset OPENROUTER_API_KEY; CLAUDE_FLAGS=x jev_flags row; echo "$JEV_WHY"'   # runner under start: "no OPENROUTER_API_KEY in the runner environment"
  ```
  - Test gap: tests/12-start-env.sh's `tskey` case checks argv only. Nothing checks the runner's reason for this case.
- **Fix:** either one works.
  - (a) Have `unit_start` print one terminal line when the key is set but not passed, with the cause ("OPENROUTER_API_KEY not passed: not sk-or-" / "JOB_JEV=0").
  - (b) Reword jev.sh:34 to "no OPENROUTER_API_KEY in the runner environment (start and the resume timer pass it only when it starts sk-or- and JOB_JEV is not 0)".
  - Pin it with a `tskey` run under the real unit in test 11, or with a unit_env + jev_flags check.

**SF2-2 · LOW · lib/preflight.sh:21 and :28. The forecast does not say "start passes none" for a non-sk-or- key or for JOB_JEV=0.**
- **Issue:**
  - :21 still says start passes the key "by name when it is set (issue 27)", which is stale after P7R1-7.
  - :28 adds `'; start passes none'` only when `[ -n "${OPENROUTER_API_KEY:-}" ]` is false, so the condition does not match `unit_env`.
- **Impact:** with `OPENROUTER_API_KEY=tsk-…` or `JOB_JEV=0` plus a key, preflight prints the right local reason but not that start will pass no key. Combined with SF2-1, preflight and run.log give different reasons for the same job.
- **Reproduce:** `OPENROUTER_API_KEY=tsk-x blast-off preflight <job>`. The level line has no "; start passes none".
- **Fix:** derive the suffix from the same test as unit_env (key not sk-or- or JOB_JEV=0), and fix the :21 comment.
  - tests/60-preflight.sh:4's header has the same stale "when it is set".

**SF2-3 · LOW · lib/jev.sh:41. "jev failed:" has no exit status, so a timeout or silent failure logs an empty reason.**
- **Issue:** `JEV_WHY="jev failed: $(head -c 200 "$err" | ...)"`. When `timeout 60` kills jev (rc 124), or jev dies to a signal or OOM with empty stderr, the reason is just `jev failed:`.
- **Impact:** the fallback is safe, but the cause is invisible. It is not "timed out after 60 s" and not "exit 137".
- **Context:** the fixer refuted P7R1-24 because the real jev's curl `-m 30` fires first and its errors are printed. That is right for the network path. It does not cover a hang outside curl, or a kill.
- **Reproduce:** a fake jev that runs `sleep 70` and prints nothing, run with `OPENROUTER_API_KEY=sk-or-x`. run.log shows `static CLAUDE_FLAGS (jev failed: )`.
- **Fix:** capture `rc=$?` and log `jev failed (exit $rc${rc==124: timed out after 60 s}): <stderr>`. This is one variable.

**SF2-4 · LOW · lib/jev.sh:44-45. A jq failure on jev's stdout is logged as "jev answered 'nothing'".**
- **Issue:** `level="$(jq -r '.level.choice // empty | strings' <<< "$out" 2>/dev/null || true)"` swallows the parse error. Non-JSON stdout, or a `.level` that is a string or array (jq "Cannot index"), becomes `jev answered 'nothing', not a level`.
- **Impact:** a shape change in jev's output reads like an empty answer, not like a format problem.
  - The fixer showed the current real jev cannot exit 0 with non-JSON, so this is defence in depth only.
- **Fix:** when `jq -e . <<<"$out"` fails, or `.level` is not an object, log "jev output is not the expected JSON".

**SF2-5 · LOW · lib/jev.sh:39-43. A signal during the jev call leaves the stderr temp file (the signal half of P7R1-23 was not addressed).**
- **Issue:** the TERM trap does `exit 143` once the command substitution returns. `rm -f "$err"` at :41/:43 never runs, and no trap removes it.
  - The unit uses KillMode=control-group, so `blast-off stop` kills jev and the runner together.
- **Impact:** `$XDG_RUNTIME_DIR/blast-off-jev.XXXXXX` stays behind with jev's raw, unmasked stderr. It is mode 0600 on tmpfs, so the exposure is small. Files pile up over repeated stops during the up-to-60 s call window.
- **Reproduce:** a fake jev that runs `sleep 30`, `run`, then `kill -TERM <runner>` during the call. `ls $XDG_RUNTIME_DIR/blast-off-jev.*` shows the file left behind.
- **Fix:** remove `$err` in `chain_exit` (keep its name in a global), or skip the file: `2> >(head -c 200 ...)`.

**SF2-6 · LOW · lib/jev.sh:45. The "not a level" reason is masked for non-printables only. Its length is unbounded and key-shaped text is not masked.**
- **Issue:** `level="${level//[![:print:]]/ }"; JEV_WHY="jev answered '${level:-nothing}', not a level"`.
  - The stderr path (:41) is cut to 200 bytes and masks `sk-or-…`. This path does neither.
- **Impact:**
  - A long or garbage `.level.choice` makes an arbitrarily long run.log line and decisions.tsv `why` cell.
  - Text containing a key is logged in clear. This is speculative with the real jev.
- **Fix:** apply the same `head -c 200` and `sed 's/sk-or-[^[:space:]"]*/sk-or-.../g'` to `level` before logging.

**SF2-7 · LOW · tests/61-jev-pick.sh:84-85. The 40-character cut on a non-number confidence is never exercised.**
- **Issue:** the forged confidence `"x\n2099-01-01T00:00:00Z job done\ty"` is 37 characters after `tojson`. I checked this with `jq -nr '... | tojson | length'`, which gives 37. So `.[:40]` at jev.sh:46 never truncates anything in any test.
- **Impact:** a mutant that drops `| .[:40]` passes 61. The comment at jev.sh:23-24 and the spec catalog row claim a cut that nothing pins.
- **Fix:** add a case with a confidence string over 40 characters, and assert that the logged value is exactly 40 characters of JSON.

**SF2-8 · LOW · tests/11-unit-smoke.sh:99. The key-leak check under the real unit cannot fail through the jev path.**
- **Issue:** `! grep -q sk-or-fake-p7r1-6 "$JOB/run.log"`. The fake jev fails here on `${FAKE_JEV:?…}` and never prints the key. The only logged jev text cannot contain it, so masking is never exercised under the unit.
  - decisions.tsv and the journal are not checked either.
- **Impact:** it is a weak guard. It does catch a regression that logs `$OPENROUTER_API_KEY` directly. It cannot catch a mask regression on the real-unit path. 61's `errkey` covers masking under foreground `run` only.
- **Fix:** grep `-rF` over `"$JOB"` (decisions.tsv included), and use rc==1 as `nokey` does in test 12. Optionally use `journalctl --user -u "$UNIT"` too.

**SF2-9 · LOW · lib/chain.sh:154. The run.log refusal line does not say the runner refused or exited. It is written before the lock.**
- **Issue:** `chain_nums || { log "$NUMS_ERR" >&2; exit 1; }`. run.log gets a bare `<ts> JOB_JEV_MIN_CONF='.7' is not a number from 0 to 1 …`.
  - No "run refused" or "runner exit 1" line follows, because the EXIT trap is installed later.
  - It runs before `chain_lock`, so a second `run` with a bad value appends that line into a live runner's run.log.
- **Impact:** someone reading run.log sees a validation message that looks like a warning, not like "this runner never started". On a live job it is interleaved and looks like it came from the running runner.
- **Fix:** prefix with `run refused: … ; exit 1` (chain_count's line at :155 has the same shape).

**SF2-10 · LOW · lib/units.sh:23 and lib/jev.sh:33. JOB_JEV is still unvalidated, and the impact is new in this phase (P5R2-14 / Q8 is still open from phase 5).**
- **Issue:** only the literal `0` turns Jev off. `JOB_JEV=false`, `no`, `off`, `00` or `" 0"` leave Jev on.
  - Since P7R1-7, `unit_env` then also stores the key in the transient unit file, and the row text goes to OpenRouter.
- **Impact:** an owner who meant "off" gets Jev on and the key stored. run.log does record the picks, so it is visible after the fact but not prevented.
- **Reproduce** (verified): `JOB_JEV=false OPENROUTER_API_KEY=sk-or-fake` then `unit_env` puts `--setenv=OPENROUTER_API_KEY` in UNIT_ENV.
- **Fix:** add `[[ ${JOB_JEV:-1} =~ ^[01]$ ]]` to `chain_nums`, so start, resume, run and preflight all refuse it. Raise it as Q8 if the owner has not ruled.

**SF2-11 · LOW · skills/blast-off/SKILL.md:63-68. Step 7 overclaims "Jev then picks" and names no place where a fallback shows.**
- **Issue:** "when the shell that runs `start` has `OPENROUTER_API_KEY` (an OpenRouter `sk-or-` key), `start` passes it … and Jev then picks `--model` and `--effort` for each phase … (… a pick below `JOB_JEV_MIN_CONF`, default 0.7, keeps them)".
  - Only low confidence is named as a fallback. Jev not on the unit's PATH, a jev failure (including a stale key under the resume timer), `other`, a missing, null or out-of-range confidence, and no open Phase plan row all keep CLAUDE_FLAGS too.
  - "(an OpenRouter sk-or- key)" reads as a description, not a condition. A non-sk-or- key is silently not passed (SF2-1).
  - Nothing tells the owner that run.log, and decisions.tsv's `why` column, is the only place a fallback and its reason appear.
- **Fix:** "…Jev may pick … ; any failure or a pick below the threshold keeps CLAUDE_FLAGS; each pick or fallback, with its reason, is a `model level` line in run.log". Say outright that a key not starting `sk-or-` is not passed.
- templates/brief.md D1 ("when the runner holds Jev's key, Jev may pick … and `JOB_JEV=0` keeps them") is hedged with "may" and holds no false claim. No finding.

---

Outside this diff (pre-existing, for context only): under the resume timer, a `unit_check` refusal (missing brief.md, CLAUDE_FLAGS, GH_TOKEN) reaches only the resume service's journal, not run.log. The newly added `chain_nums` in `unit_check` cannot fail there, because the timer inherits values the runner already validated. So this commit adds no new silent path.

I did not re-raise anything the owner decided or deferred.
