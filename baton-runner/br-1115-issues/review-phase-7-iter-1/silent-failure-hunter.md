# silent-failure-hunter: phase 7 review, round 1 (static, read-only)

Silent-failure review of phase 7 (514d0ef vs e924be8), issue 27 (Jev key passed to the unit; confidence threshold). This was a static review only: I ran nothing from the project, made no edits and ran no git commands. I read the diff and all the touched files, plus the real `jev` script (/home/alex/JevDev/bin/jev) to confirm its output shape. Severity tags are my own triage. Every finding is listed; nothing was filtered out.

## Findings

**SF-1 · MEDIUM · `start` and `resume` launch a unit with a bad `JOB_JEV_MIN_CONF`; the runner then dies with its reason on stderr only, and nothing reaches run.log**
- Location: lib/units.sh:31-35 (`unit_check` has no `chain_nums`); lib/chain.sh:153 (`chain_nums || die "$NUMS_ERR"`); bin/blast-off:56 (`die` writes to stderr only).
- Failure path: `JOB_JEV_MIN_CONF=.7 blast-off start <job>`
  - `unit_check` passes, `unit_env` passes `--setenv=JOB_JEV_MIN_CONF`, and `systemd-run` returns 0. `start` exits 0 and prints its usual "status/watch/stop" line.
  - Inside the unit, `chain_run` refuses at line 153. That is before `chain_lock` and before the EXIT trap (line 165), so run.log gets nothing, not even "runner exit 1 without a state". The reason exists only in the journal.
  - `wait` sees status `running` with the unit gone and says `stuck … see blast-off status`. `status` shows ActiveState inactive and no reason. Only `blast-off logs` (its journalctl tail) shows why.
  - A manual `resume` behaves the same way: it exits 0 and the job stays paused, so it is not corrupted, but the user is not told why.
- This breaks the project's own rule in the comment at chain.sh:154 (P4R1-2): "under start or the resume timer only the journal reads stderr, so the refusal goes to run.log too". `chain_count` follows that rule; `chain_nums` does not. The gap already existed for the `JOB_*` counts; this phase adds a new variable to it, and decimals like `.7` are easy to mistype.
- The resume-timer path is not affected: its value comes from a runner that already validated it.
- Fix:
  - Add `chain_nums || die "$NUMS_ERR"` to `unit_check`, so `start` and `resume` refuse before any unit exists.
  - In `chain_run`, use `chain_nums || { log "$NUMS_ERR" >&2; exit 1; }`, mirroring `chain_count`.
  - Add a test-12 case: `start` with `JOB_JEV_MIN_CONF=abc` exits 1 and creates no unit.

**SF-2 · LOW · Any failure of the threshold `jq` is reported as "confidence … is not a number"**
- Location: lib/jev.sh:46-49.
- Failure path: the `case` word is `$(jq … --argjson t "$JEV_MIN" … 2>/dev/null)`. If jq fails (invalid `--argjson`, jq crashes, a broken jq), the output is empty and the `*)` branch logs `jev picked light, confidence '0.87' is not a number`. That reason is false: the confidence was a number, and the threshold or jq was the problem.
- Today an invalid `JEV_MIN` cannot happen, because `chain_nums` runs first on both callers (chain.sh:153 before jev_pick at :216; preflight.sh:15 before :23). But `jev_flags` is documented as "never fails" and silently depends on that precondition: a future caller that skips `chain_nums` gets a wrong reason, not an error.
- I reasoned, but did not run, that `case "$(failing)"` does not trigger `set -e`.
- Fix: capture the result in a variable and give jq failure its own branch, e.g. `"") JEV_WHY="jev picked $level; threshold check failed (jq)"`. Or check `JEV_MIN` inside `jev_flags`.

**SF-3 · LOW · A missing, null or false confidence is logged as `confidence '?' is not a number`**
- Location: lib/jev.sh:45, :49.
- Failure path:
  - `.level.confidence // "?"` turns absent, `null` and `false` into the placeholder `?`. The comparison then says `nan`, and the log reads as if jev returned the string "?". So the comparison's "nan" and the logged "?" do not agree on what happened, and the message is misleading.
  - `|| echo '?'` runs after partial output too. For example, valid JSON followed by trailing garbage makes `JEV_CONF="0.87\n?"`. In that same case the `case` jq prints `ok` before failing, so the pick is taken and logged with a two-line confidence.
- Fix: one jq call that returns a tagged result, e.g. `if .level.confidence == null then "missing" elif (.level.confidence|type) != "number" then "nan" …`. Log `jev gave no confidence` for the missing case. Drop the `|| echo` append.

**SF-4 · LOW-MEDIUM · The non-number branch writes jev's raw confidence into run.log and decisions.tsv without cleaning it**
- Location: lib/jev.sh:45, :49, :67, :74-75; bin/blast-off:55 (`log` does no cleaning).
- Failure path:
  - A string confidence holding `\n2099-01-01T00:00:00Z job done` is printed raw by `jq -r`. It becomes a forged, timestamped run.log line: the same class as P5R1-5, which the project already treats as a defect.
  - A tab in the value breaks decisions.tsv's 6 columns, since only `\r` is stripped.
  - An object confidence is pretty-printed by `-r` over several lines.
- Before this phase, `JEV_CONF` was logged only on the pick path. That path now requires a number (`ok`), so this branch is the only unsanitised one, and it is new.
- The value comes from the OpenRouter/Jev response, which is semi-trusted.
- Fix: in that branch, log `($JEV_CONF|tojson)[0:40]`, or strip it to `[0-9A-Za-z.?+-]`.

**SF-5 · LOW (already existed) · Output from jev that is not JSON is reported as "jev answered 'nothing', not a level"**
- Location: lib/jev.sh:43-44 (`jq … 2>/dev/null || true`).
- A parse error is reported as an empty answer, and jq's error is thrown away.
- Fix: test `jq -e . <<<"$out" >/dev/null` first and log `jev output is not JSON`.

**SF-6 · LOW (already existed, now reachable in more places) · A jev timeout leaves no reason**
- Location: lib/jev.sh:39-40.
- When `timeout 60` kills jev (exit 124) with empty stderr, `JEV_WHY` is `jev failed:` with nothing after it. The exit status is never recorded; inside `if ! …` the `$?` is the negated one.
- This is now reachable from preflight and from under the unit, where before it was only reachable in a foreground run.
- Fix: run `out="$(…)" || rc=$?`, and log `jev failed (exit $rc[, timed out after 60 s]): …`.

**SF-7 · LOW (already existed, newly reachable in preflight) · The "never fails" comment is not true**
- Location: lib/jev.sh:38 (`err="$(mktemp …)"`), under `set -euo pipefail`.
- If `XDG_RUNTIME_DIR` (or /tmp) cannot be written, the assignment aborts the runner ("runner exit 1 without a state") or preflight. Preflight then dies with no `preflight: refused:` line.
- Before this phase, preflight forced the key empty and returned before reaching mktemp.
- Fix: `err="$(mktemp …)" || { JEV_WHY="cannot make a temp file for jev's stderr"; return 0; }`.

**SF-8 · LOW · The confidence range is never checked**
- Location: lib/jev.sh:46.
- A confidence above 1 (for example 87 on a percent scale) passes any threshold. A negative one always falls back.
- Jev documents calibrated probabilities from 0 to 1, but the gate does not enforce that.
- Fix: in jq, `elif . < 0 or . > 1 then "nan"`.

**SF-9 · MEDIUM (security, least privilege; documented in the spec, but worth an owner decision) · Under `start`, every child now inherits OPENROUTER_API_KEY**
- Location: lib/child.sh:13, :21. The tmux server environment is the runner's, and only `CLAUDE*` names are scrubbed.
- Before this phase, children under `start` had no key. Now every LLM child session has it in its environment, even though only the runner calls jev.
- How it could leak: run.log captures a dead child's last screen, and children write commits and PR text. The tests' no-key checks use a fake child that never prints its environment, so they cannot catch a leak.
- Fix: add `-u OPENROUTER_API_KEY` to the `env` in `child_server`. The runner's own jev call is unaffected.

**SF-10 · LOW · The key is passed and stored even when it can never be used**
- Location: lib/units.sh:22.
- The name is passed whenever the key is non-empty, including with `JOB_JEV=0` or a key that is not `sk-or-`. `jev_flags` refuses both, yet the secret is still stored in the transient runner and timer unit files and handed to the children.
- Fix: pass it only when `${JOB_JEV:-1} != 0` and the key starts with `sk-or-`. Otherwise print one line at `start`, e.g. `OPENROUTER_API_KEY not passed: …`.

**SF-11 · LOW-MEDIUM · Test 12's stub proves the argv only, never what happens; C1 under `start` is not tested end to end**
- Location: tests/12-start-env.sh:214-216, 250-252.
- The stub runs the real `systemd-run` only for `--scope` and always exits 0 otherwise. A real `systemd-run` that rejects the argument list, or a `--setenv` placed after the command, would still pass. No test shows the value reaching a real unit's environment, or a Jev pick logged by a unit started with `start`.
- In the die75 case, `FAKE_JEV="$PWD/jev"` points at a directory that was never created, and the job has no Phase plan. So Jev is never asked in that run; only the timer's argv is checked.
- Fix: in test 11 (real unit), export a fake `sk-or-` key and a `FAKE_JEV` with a Phase plan row, then check run.log for `(jev, confidence 0.87, threshold 0.7)`. Remove or fix the dead `FAKE_JEV` in the k4 case.

**SF-12 · LOW · `argv()` merges every record, so it cannot tell which call carried which flag**
- Location: tests/12-start-env.sh:219.
- `cat stub/argv-*; rm -f` concatenates all records in a section. If one section ever has two non-scope calls, `grep -qx --setenv=OPENROUTER_API_KEY` passes when either call has it. A reused PID would overwrite a record.
- Today each section has exactly one non-scope call, so nothing is lost yet.
- Fix: name the files with a counter (`mktemp stub/argv.XXXX`), and check the record that holds `--on-calendar` on its own.

**SF-13 · LOW · The "key absent" checks can pass without checking anything**
- Location: tests/12-start-env.sh:220 (`nokey`); tests/61-jev-pick.sh:26.
- `! grep -qr -- "$key" …` treats grep's exit 2 (missing or unreadable path) as "absent".
- The paths exist today, so this is latent.
- Fix: `grep -rq … ; [ $? -eq 1 ] || fail`, or assert the paths exist first.

**SF-14 · LOW · Preflight's level line, and the docs that describe it, claim more than preflight can know**
- Location: lib/preflight.sh:21-29; docs/spec.md K8 ("`preflight` prints the flags and level `start` gives, asking Jev as the runner would") and the preflight row.
- Problems:
  - Jev is a model call. The runner asks again and may get another level or confidence, so `deep under start` is a forecast, not what `start` will give.
  - It reflects only the shell preflight runs in. A `start` from a shell with a different key or `JOB_JEV*` differs.
  - A jev failure in preflight (for example a revoked key, where every pick under the unit will also be static) still ends `preflight: ok`. It is visible only inside the level line's parentheses.
  - Each preflight now costs a paid OpenRouter call and can block for up to 60 s.
- Fix: word it as "Jev's pick now (the runner asks again)". Consider a warning line when jev fails while the key is set.

**SF-15 · LOW · Untested paths**
- A confidence that is missing or `null` (the `'?'` path in SF-3).
- Preflight with a failing or timed-out jev.
- `start` or `resume` with a bad `JOB_JEV_MIN_CONF` (SF-1).
- p15 does not assert the spec's "refused at once, before any other line": nothing checks that no `job:` or `flags:` line appears.
- `JOB_JEV_MIN_CONF=''` (set but empty, silently the default) is not covered either way.

**SF-16 · LOW · The spec's secrets paragraph is out of date**
- Location: docs/spec.md:68-74.
- It says "blast-off writes no secret (`GH_TOKEN`) to any file" and "the token included", naming one secret. There are now two.
- "Until the unit is collected" understates how long the key lives for the resume timer. The timer's transient `.resume.service` file and its `Environment` property (readable with `systemctl --user show`) keep the key until the timer fires, which can be days for a 7-day `paused-limit`. The README's "until the unit is collected" has the same gap.
- Fix: name both secrets and state the timer's lifetime.

**SF-17 · LOW, unverified · jev's error text goes into run.log, decisions.tsv and preflight output**
- Location: lib/jev.sh:40.
- On an HTTP failure, `jev` prints the response body to stderr (JevDev/bin/jev, the `curl … || { printf '%s\n' "$resp" >&2; exit 2; }` line). Its first 200 bytes go to all three places.
- The "never the key's value" claim depends on OpenRouter error bodies never echoing the key. I could not verify that statically.
- `\r` and escape characters are not stripped from run.log (only `\n` and `\t` are turned into spaces).
- Fix: also strip control characters (`tr -d '\000-\037'` after the newline-to-space step), and consider masking anything that matches `sk-or-[A-Za-z0-9-]+`.

**SF-18 · LOW · The key is frozen at `start`**
- Location: lib/units.sh:22 together with lib/usage.sh:69-71.
- The runner unit and every resume timer it arms carry the key value from `start` time. After a rotation or revocation, every later pick, including those after a timer resume, logs `jev failed: …` and runs static until a fresh `start`.
- This is logged, not silent. It is not documented.

## Direct answers to the brief's questions

1. **jev_flags**
   - Output that is not JSON: "answered 'nothing'" (SF-5).
   - A jq failure in the threshold check: misreported as "not a number" (SF-2).
   - Confidence absent or null: logged as "confidence '?' is not a number". That is not accurate: the "?" is a placeholder (SF-3).
   - An invalid `JEV_MIN` cannot reach jq today, because `chain_nums` always runs first.
2. **Validation order**
   - `chain_nums` runs before every `jev_flags` call in `run` (chain.sh:153 before :216) and in `preflight` (:15 before :23). The timer path inherits a value that was already validated.
   - `start` and `resume` do not validate, so the runner dies with its reason only in the journal: SF-1.
3. **Timer environment**
   - The timer's `blast-off resume` runs in the user manager's environment plus the `--setenv` names, whose values are captured from the runner's environment when the timer is armed (usage.sh:69-71). The runner's environment came from `start`.
   - So the key reaches the resume iff the runner had it. The owner's shell at fire time does not matter.
   - If the key is absent, the resumed runner logs `static CLAUDE_FLAGS (no OPENROUTER_API_KEY in the runner environment)`. It is logged, not silent.
   - Edge cases: a timer armed by a pre-phase-7 runner still in memory carries no key; and the stale key of SF-18.
4. **Preflight's Jev call**
   - A failure is reported in the level line, but preflight still says `ok`.
   - A timeout gives an empty reason (SF-6).
   - A mktemp failure aborts preflight (SF-7).
   - The printed level reflects only preflight's own shell and one sample of Jev (SF-14).
5. **Test-12 stub**
   - Yes: it always exits 0, so a broken real `systemd-run` argument list would pass (SF-11).
   - `argv()` loses attribution, and a reused PID could overwrite a record. No record is lost in the current sections (SF-12).
6. **Tests that could pass without checking anything**
   - `nokey` and 61:26, through grep's exit 2 (SF-13).
   - The `wc -l < missing` checks fail properly; they do not pass vacuously.
   - The `! grep OPENROUTER` loop is guarded by the GH_TOKEN record check.
   - The dead `FAKE_JEV` in the die75 case (SF-11).
7. **Docs**
   - The K8 and preflight "level `start` gives" wording (SF-14).
   - The spec says only `run` and `preflight` refuse a bad `JOB_JEV_MIN_CONF`, and is silent on `start` and `resume` starting a unit that dies (SF-1).
   - The secrets paragraph and the timer's storage lifetime (SF-16).
   - The "never the key's value" claim depends on jev's error text (SF-17).

## Open questions for the owner

1. Should children get `OPENROUTER_API_KEY` at all (SF-9), or should `child_server` scrub it, since only the runner uses it?
2. Should `start` and `resume` refuse a bad `JOB_JEV_MIN_CONF` and bad `JOB_*` counts before creating a unit (SF-1)?
3. Should the key be passed when `JOB_JEV=0` or when it is not `sk-or-` (SF-10)?
4. Should a jev failure while the key is set give a separate warning line in preflight, or stay inside the level line's parentheses (SF-14)?
5. Is a stored key living days in the timer's transient unit file (7-day pause) acceptable under the D21 sign-off (SF-16)?
6. Should confidences outside 0 to 1 fall back (SF-8)?

## Unverified

- Whether `case "$(failing cmd)"` can trigger `set -e`: reasoned only, I ran nothing.
- Whether OpenRouter error bodies can echo the key (SF-17).
- How a real `systemd-run` treats the stubbed argument lists (SF-11).
- I checked against the real jev source (JevDev/bin/jev line 135) that `.level.confidence` is present for a choice question in raw `-q` mode, so the threshold does not disable Jev in production.
