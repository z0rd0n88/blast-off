# Review: phase 7 (issue 27, Jev's key reaches the unit; confidence threshold), round 1

Commit 514d0ef against base e924be8 (`git diff e924be8...514d0ef -- . ':!baton-runner'`), 11 files.
Six static reviewers (`review-phase-7-iter-1/<reviewer>.md`, saved verbatim from their hand-backs), then the review
unit reproduced their concrete claims one at a time on a `git archive 514d0ef` copy in the scratchpad.

## Executive summary

- Gate: `scripts/gate.sh` exit 0, last line `GATE: PASS passed=19 failed=0 shellcheck=ok`
  (`gate-phase-7-iter-1/tests-run.log`). ExecStart was the build worktree's before the gate, after it, after every
  scenario run below, and at the end.
- Every issue-27 criterion has a passing test (table below). No reviewer raised a CRITICAL or HIGH; I found none.
- 6 MEDIUM, 22 LOW. The MEDIUMs are as follows; P7R1-1 and P7R1-4 need owner decisions.
  - P7R1-1: children now hold the key under `start` (5 of 6 reviewers; open Q2).
  - P7R1-2: no test pins that `JOB_JEV_MIN_CONF` reaches the unit (mutant survives test 12, reproduced).
  - P7R1-3: no test pins decisions.tsv's `why` (mutant survives test 61, reproduced).
  - P7R1-4: preflight's level is a separate sample from preflight's own shell, and the docs and SKILL.md overclaim (Q1).
  - P7R1-5: `start` launches a unit with a bad threshold whose refusal reaches only the journal (reproduced).
  - P7R1-6: no real-unit test of C1 under `start`.
- Reproduced:
  - a jev string confidence forges a timestamped run.log line and breaks decisions.tsv's columns;
  - confidence 1.5 is taken;
  - a null confidence logs `confidence '?' is not a number`;
  - four surviving mutants: unit_env without `JOB_JEV_MIN_CONF`, why without the threshold, `${JOB_JEV_MIN_CONF-0.7}`,
    and a loosened regex;
  - preflight with `CLAUDE_FLAGS` unset dies on `set -u` (pre-existing).
- Refuted: three claims (see Notes).

**VERDICT: CLEAN** (gate exit 0, zero CRITICAL/HIGH, each criterion has a passing test).

## Issue-27 criteria -> tests (all PASS in the gate)

| Criterion | Test | Note |
|---|---|---|
| C1: key set, the phase's model comes from Jev and is logged | `tests/61-jev-pick.sh:22-37` (pick, run.log line with confidence and threshold, decisions.tsv); `tests/12-start-env.sh:42-50` (start passes `--setenv=OPENROUTER_API_KEY`, `key=set` in systemd-run's env), `:62-67` (resume), `:70-78` (timer); `tests/60-preflight.sh:55-57,76-78` | Runner side and argv side only; no real unit carries a key (P7R1-6). Work unit's M3, M8, M10, M12 killed |
| C2: no key, static flags, logged | `tests/61-jev-pick.sh` `fallback nokey` (reason in run.log, 0 jev calls); `tests/12-start-env.sh:52-59` (unset and empty: no name); `tests/60-preflight.sh:119` | M1, M2 killed; resume and timer unset cases untested (P7R1-20) |
| C3: a low-confidence pick keeps static flags | `tests/61-jev-pick.sh:65-70` (0.55<0.7, 0.87<0.9, `"high"`), `:81-83` (taken at 0.7, 0.55 with 0.5, 1 with 1.0); `tests/60-preflight.sh:80-83` | M4, M5, M7 killed |
| Sign-off: threshold 0.7, `JOB_JEV_MIN_CONF` overrides | default `61:66,81`; override `61:68,82-83`, `60:80`; validation `61:85-91`, `60:85-87` | Override not pinned under `start`/timer (P7R1-2) |

## Critical

None.

## High

None.

## Medium

**P7R1-1. Children (bypass permissions) now inherit OPENROUTER_API_KEY under `start` and the resume timer, and they never use it**
- Reported by: penetration-tester PT-1, security-reviewer SR-1, critical-thinking CT-1, code-reviewer CR-1,
  silent-failure-hunter SF-9.
- Location: `lib/child.sh:13,21` (`env $scrub ... tmux new-session`; scrub removes only `CLAUDE*`); `lib/units.sh:22`.
- Path: unit env -> runner -> the job's tmux server global env -> every child pane and its tools. Only the runner calls
  jev. Before phase 7 this happened only under a foreground `run` with the key; now it is the default under `start`.
- How it could leak:
  - a child's `env` lands in its transcript;
  - a dead child's last 40 screen lines go to run.log (`lib/child.sh:96-99`);
  - a prompt-injected child can spend on the key or send it out;
  - with `JOB_KEEP_WINDOWS`, the tmux server keeps the key after the runner exits.
- Not a hard boundary: a same-user child can still read `/proc/<runner>/environ`. Scrubbing stops accidental leaks.
- Spec documents it ("Children inherit it ... as they inherit GH_TOKEN"). The owner's sign-off covers the unit, not
  children: open Q2.
- Fix (if the owner agrees): `-u OPENROUTER_API_KEY` in `child_server`'s `env`, and record `openrouter=set|unset` in
  fake-marker to pin the decision (TG-18).
- Verified by reading `lib/child.sh:11-22`.

**P7R1-2. No test pins that `JOB_JEV_MIN_CONF` is passed to the unit or the timer**
- Reported by: code-reviewer CR-2, tdd-guide TG-2.
- Location: `lib/units.sh:25`; `tests/12-start-env.sh` never sets it.
- Reproduced: archive copy, `JOB_JEV_MIN_CONF` removed from unit_env's loop, `BLAST_OFF_TEST_ONLY=12-start-env` ->
  `GATE-ONLY: PASS passed=1 failed=0`. The owner's override would be silently ignored under `start`. `JOB_JEV` is
  equally unpinned (pre-existing).
- Fix: in test 12's k1 and k4 cases set `JOB_JEV_MIN_CONF=0.9` and `grep -qx -- '--setenv=JOB_JEV_MIN_CONF'`.

**P7R1-3. decisions.tsv's `why` column (confidence, threshold, fallback reason) is not asserted**
- Reported by: tdd-guide TG-3.
- Location: `lib/jev.sh:71`; `tests/61-jev-pick.sh:37,50` grep only the decision column.
- Reproduced: archive copy, `why="${JEV_WHY:-jev choice, confidence $JEV_CONF}"` (threshold dropped),
  `BLAST_OFF_TEST_ONLY=61-jev-pick` -> PASS. Spec K8 promises the threshold and reason in decisions.tsv.
- Fix: in the pick run require column 4 `jev choice, confidence 0.87, threshold 0.7`; in `fallback()` require column 4 to
  equal the reason.

**P7R1-4. Preflight's level is a separate Jev sample from preflight's own shell. The docs say it is "the level `start` gives", and SKILL.md never mentions the key (Q1)**
- Reported by: critical-thinking CT-2 (MEDIUM), CT-7; code-reviewer CR-7, CR-8, CR-14; silent-failure-hunter SF-14;
  penetration-tester PT-8; security-reviewer SR-8.
- Location: `lib/preflight.sh:21-29`; `docs/spec.md` K8 and the preflight row ("asking Jev as the runner would");
  `skills/blast-off/SKILL.md:42,52,59,85-88`.
- Evidence:
  - The runner asks Jev again at child 1, so near 0.7 the two can differ.
  - SKILL step 6 runs preflight in the session's Bash tool, which does not source `~/.bashrc`. Step 7 hands `start` to
    the owner's terminal, which does. One may have the key and the other not.
  - SKILL.md hands over `export GH_TOKEN CLAUDE_FLAGS=...` and calls `CLAUDE_FLAGS` "the owner's string, verbatim". With
    the key in the owner's shell, Jev now replaces `--model`/`--effort` per phase, and nothing tells the owner
    `JOB_JEV=0` opts out.
  - Each preflight now makes one paid OpenRouter call (up to 60 s) and sends the row text off the machine, even when
    preflight will refuse anyway. A jev failure still ends `preflight: ok`.
- Fix: owner's choice on Q1 (keep the call, or print "Jev decides at launch, threshold t"). Either way, reword K8 and the
  preflight row as a forecast, and add the key, Jev and `JOB_JEV=0` to SKILL.md's hand-over.

**P7R1-5. `start` and `resume` launch a unit with a bad `JOB_JEV_MIN_CONF`; the runner's refusal reaches only the journal**
- Reported by: silent-failure-hunter SF-1 (MEDIUM); critical-thinking CT-3, code-reviewer CR-3, penetration-tester PT-9,
  security-reviewer SR-5, tdd-guide TG-20 (LOW). Also in the implementer's notes.
- Location: `lib/units.sh:31-35` (`unit_check` has no `chain_nums`); `lib/chain.sh:153` (`chain_nums || die`, stderr only).
- Reproduced (archive copy, probe scenario):
  - `JOB_JEV_MIN_CONF=abc start` through a stub systemd-run gives rc 0, with `--setenv=JOB_JEV_MIN_CONF` passed.
  - `JOB_JEV_MIN_CONF=abc run` gives rc 1, and the reason is on stderr only. run.log is not even created.
- Under `start`, `wait` says `stuck` and `status` shows no reason. This breaks the rule in the comment at `chain.sh:154`
  (P4R1-2), which `chain_count` follows. Bad `JOB_*` counts already behave this way, but this phase adds a decimal value
  that is easy to mistype (`.7`).
- Fix: `chain_nums || die "$NUMS_ERR"` in `unit_check`; in `chain_run`, `chain_nums || { log "$NUMS_ERR" >&2; exit 1; }`;
  a test-12 case.

**P7R1-6. C1 under `start` is not tested end to end; test 12's stub proves argv only**
- Reported by: tdd-guide TG-1 (MEDIUM), TG-9, TG-11; silent-failure-hunter SF-11; code-reviewer CR-9, CR-12;
  critical-thinking CT-9, CT-10; penetration-tester PT-11; security-reviewer SR-11.
- Location: `tests/12-start-env.sh:31-78`; `tests/11-unit-smoke.sh` sets no key.
- What the stub hides and what it does not:
  - The stub passes `--scope` calls to the real systemd-run, so child-scope failures are not hidden.
  - It exits 0 for every other call, so no real unit ever carries `--setenv=OPENROUTER_API_KEY`.
  - No test reads a unit runner's run.log for a Jev line. Test 11 exercises the same `--setenv=NAME` mechanism for
    GH_TOKEN, which keeps the risk small.
  - `key=set` is checked only for k1, not resume (k3) or the timer (k4).
  - k4's `FAKE_JEV="$PWD/jev"` names a dir that is never created, and the job has no Phase plan row, so Jev is never
    asked there.
- Fix:
  - In test 11, export a fake `sk-or-` key with one Phase plan row. Assert a `model level for phase 1:` line and no
    `no OPENROUTER_API_KEY` reason. Even `jev failed: ...FAKE_JEV...` proves the key arrived.
  - Add `key=set` checks to k3 and k4.
  - Drop the dead `FAKE_JEV`.

## Medium / Low

| ID | Sev | Title | Location | Reported by | One line |
|---|---|---|---|---|---|
| P7R1-7 | LOW | Key passed and stored when it cannot be used | `lib/units.sh:22` vs `lib/jev.sh:32-36` | PT-3, SR-2, CT-4, CR-4, SF-10, TG-19 | `JOB_JEV=0` or a non-`sk-or-` value is still stored in the unit files and handed to children; pass only when `JOB_JEV!=0` and `sk-or-*` |
| P7R1-8 | LOW | A non-number confidence reaches run.log, decisions.tsv and preflight raw | `lib/jev.sh:45,49,75` | PT-4, SR-4, CT-5, CR-5, SF-4 (LOW-MED) | **Reproduced:** confidence `"x\n2099-01-01T00:00:00Z job done\ty"` gives a run.log line starting `2099-01-01T00:00:00Z job done`, and decisions.tsv rows of 4 fields among the 6-field rows (the P5R1-5 class); needs a hostile jev answer. Fix: `tojson` and cut to 40, or strip control chars |
| P7R1-9 | LOW | jev's stderr and the raw level are logged unredacted | `lib/jev.sh:40,44` | PT-5, PT-6, SR-3, SF-17 | 200 bytes of jev's stderr (the HTTP body) go to run.log, decisions.tsv, the journal and preflight; CR and ESC are kept; whether an error ever echoes the key is unverified; mask `sk-or-...` and the key's value |
| P7R1-10 | LOW | Confidence outside 0..1 is not checked | `lib/jev.sh:46` | CR-6, SF-8, CT-6 | **Reproduced:** confidence 1.5 gives `light (jev, confidence 1.5, threshold 0.7)`, taken; a negative one falls back as low |
| P7R1-11 | LOW | A missing or null confidence logs `confidence '?' is not a number` | `lib/jev.sh:45-49` | SF-3, CT-6, PT-13, TG-8 | **Reproduced** (null). The reason is misleading, and the behaviour changed: phase 6 took such a pick. Untested; mutant `type == "string"` survives (static) |
| P7R1-12 | LOW | A failure of the threshold jq is reported as "confidence ... is not a number" | `lib/jev.sh:46-49` | SF-2, CR-13 | **Reproduced** at jq level: an invalid `--argjson t` gives an empty case word, hence the `*)` branch; unreachable today (chain_nums runs first on both callers) |
| P7R1-13 | LOW | Empty `JOB_JEV_MIN_CONF` meaning the default is untested | `lib/jev.sh:30`, `lib/chain.sh:100` | TG-7, CR-11, CT-9, SF-15 | **Reproduced:** mutant `${JOB_JEV_MIN_CONF-0.7}` passes 61; with `JOB_JEV_MIN_CONF=` every pick would fall back as "not a number" |
| P7R1-14 | LOW | Threshold regex edge values untested | `lib/chain.sh:100`; `tests/61-jev-pick.sh:85` | TG-5, TG-6, CR-11 | **Reproduced:** `^(0+(\.[0-9]{1,4})?\|1(\.0*)?)$` (accepts `00.7`, `0.1234`, `1.`) passes 60 and 61; `0`, `1`, `0.000`, `1.000` are never tried as accepted values |
| P7R1-15 | LOW | Preflight refusal order and key check are only partly asserted | `tests/60-preflight.sh:78,85-87` | TG-14, TG-16, SR-10, CT-9 | "refused before any other line" is not checked for `JOB_JEV_MIN_CONF=2` (no `! grep '^flags:'`, jev call count unchecked); the key's absence is checked on p1.out only |
| P7R1-16 | LOW | Key-absence checks are weak | `tests/12-start-env.sh:40`; `tests/61-jev-pick.sh:26` | SR-10, SF-13, TG-12 | They grep the full literal key only (a truncated or encoded leak passes); `! grep -qr` passes on grep exit 2 (missing path); there is no fake-jev `fail` case that echoes the key on stderr; in the start and resume cases no runner runs, so `nokey "$JOB"` checks little |
| P7R1-17 | LOW | `argv()` merges all records; PID-named files | `tests/12-start-env.sh:36,39` | SF-12, TG-10 | Two non-scope calls in one step could each satisfy a different grep; one call per step today |
| P7R1-18 | LOW | Test isolation: `JOB_JEV_MIN_CONF` and `JOB_JEV` not unset for every scenario | `tests/lib.sh:10`; `tests/12-start-env.sh` | TG-15, PT-11 | A bad value in the box or CI env would fail every scenario that drives `run`, confusingly; unset them in lib.sh |
| P7R1-19 | LOW | Docs: the secret wording names only GH_TOKEN, and the D21 status contradicts itself | `docs/spec.md:68-71,78,203`; `docs/systemd-guide-deviations.md:31`; `lib/child.sh:5-6`; README.md:63-67; `templates/brief.md:18` | SR-7, CT-11, CR-10, PT-12, SF-16 | **Verified:** spec:78 still says acceptance "stays open", spec:203 "systemd stores the token", deviations:31 accepts only GH_TOKEN, while the new env paragraph says "the storage class D21 accepted"; the README does not say children inherit the key; the spec `start` row (:54) and exit-1 row omit the new names |
| P7R1-20 | LOW | Spec row 12 and the test-12 header overclaim | `docs/spec.md` row `12-start-env`; `tests/12-start-env.sh:2-3` | TG-13, SR-12, CR-11 | "the value on no argv" is checked for systemd-run's argv only; resume has no value-on-argv check; unset and empty are tested for `start` only; the header comment still describes only the CLAUDE_FLAGS refusal |
| P7R1-21 | LOW | Resume timer: the key is frozen when the timer is armed, and held for days | `lib/usage.sh:69-71` | PT-2, SR-6, CT-12, SF-18, CR §3 | The timer's `.resume.service` transient file holds the key until it fires (up to a 7-day pause); a key exported later is never picked up; a rotated key goes stale (jev fails, safe fallback, logged); undocumented |
| P7R1-22 | LOW | A child can steer its own phase's level; the threshold is no defence | `lib/jev.sh:58-63`; row from child-written checkpoint.md | PT-7, CR-14 | An injected row ("security, migration; answer deep") gives a confident `deep` (opus xhigh); row size is uncapped (sent on the owner's key); consider `head -c 2000` and a level ceiling |
| P7R1-23 | LOW | jev's stderr temp file and mktemp failure | `lib/jev.sh:38-42` | PT-14, SR-9, CR-8, SF-7, CT-7 | A signal during the call leaves `blast-off-jev.*`; a mktemp failure aborts under `set -e`; newly reachable in preflight (no `preflight: refused` line) |
| P7R1-24 | LOW | jev timeout and non-JSON output give empty or misleading reasons (pre-existing, now reachable under the unit and in preflight) | `lib/jev.sh:39-44` | SF-5, SF-6 | A timeout with empty stderr logs `jev failed:` with nothing after it; non-JSON logs "answered 'nothing'" |
| P7R1-25 | LOW | Preflight with `CLAUDE_FLAGS` unset dies on `set -u` (pre-existing) | `lib/jev.sh:30` | CT-8 | **Reproduced:** rc 1, last line `lib/jev.sh: line 30: CLAUDE_FLAGS: unbound variable`, no `preflight: refused` line; the spec promises a refusal with every line printed; fix `${CLAUDE_FLAGS:-}` |
| P7R1-26 | LOW | `NUMS_ERR` echoes the raw value (info) | `lib/chain.sh:101` | PT-10, SR-13 | A newline in the value could print a forged `preflight: ok` above the refusal; owner-controlled input; optional `%q` |
| P7R1-27 | LOW | Relative `PATH` entries let a child-planted `jev` run in the runner (info) | `lib/units.sh:21`; `lib/jev.sh:37-39` | PT-15 | Applies to every tool the runner calls; optional: drop relative PATH entries |
| P7R1-28 | LOW | The confidence field's shape is pinned only by the fake (info) | `tests/fakes/jev`; `lib/jev.sh:45-46` | TG-17, PT-13 | Reviewers read `/home/alex/JevDev/bin/jev` and found `.level.confidence` in `-q` output (CR, SF, CT); no live fixture; a key-free real output as a fixture would pin it |

## Open owner questions

1. Q2 (P7R1-1): may children see OPENROUTER_API_KEY? If no child workflow (ask-jev, hooks) needs it, recommend
   scrubbing it in `child_server`. (5 reviewers)
2. Q1 (P7R1-4): should preflight spend a real Jev call and send the row text before launch, or print "Jev decides at
   launch, threshold t"? If the call stays, may the docs call the level a forecast? Should SKILL.md's hand-over export
   the key and mention `JOB_JEV=0`?
3. P7R1-5: should `start` and `resume` refuse a bad `JOB_JEV_MIN_CONF` (and bad `JOB_*` counts) before creating a unit?
4. P7R1-7: pass the key only when `JOB_JEV` is not 0 and the value starts `sk-or-`?
5. P7R1-10 and P7R1-11: should a confidence outside 0..1 fall back? Should a missing or null confidence fall back
   (new) or be taken (phase 6)?
6. P7R1-21: is a resume-timer unit file that holds GH_TOKEN and the key for up to about 7 days within D21? If so, may
   spec:78, spec:203 and deviations:31 say so?
7. P7R1-22: is a level ceiling or a row-size cap wanted?
8. Q3 (implementer): the threshold format (0 to 1, at most 3 decimals, a leading digit). No reviewer objected.
9. Was 0.7 checked against Jev's real confidence on this 4-way choice? If most real picks come in under 0.7, every
   phase pays for a call and stays static. (critical-thinking)

## Notes and deviations

- Line numbers are file lines of 514d0ef. Some reviewer files (critical-thinking) cite test lines by their position in
  the saved diff instead (e.g. `61:373` = file line 66).
- Gate ran once, alone, before any reviewer. `tests-run.log` was written both by my redirect and by gate.sh's own
  `tee` to the same path; the file is intact (21 lines, same shape as phase 6's).
- Reviewer reports were saved verbatim from each agent's SubagentHandback, extracted from its transcript (no
  retyping). Severities in the table are mine after dedupe; each reviewer's own severity is in its file. MEDIUM vs
  LOW splits:
  - P7R1-5 was LOW for five reviewers and MEDIUM for SF. I took MEDIUM: reproduced, and it breaks the P4R1-2 rule.
  - P7R1-6 was MEDIUM for TG. I kept MEDIUM: it is the issue's own launch path.
- Refuted:
  - TG-4 (a text-compare mutant may survive): this box has jq-1.7. `jq -n '(1|tostring) < (1.0|tostring)'` gives true
    while the numeric compare gives false, so 61's `picked one 1 1.0` kills it.
  - CT-11 and CR-10 ("P6Q7 cannot be traced"): issue 27's body says "Related P6Q7: below a confidence threshold, keep the
    static flags".
  - SR-10 and TG-15 (the ugrep `grep` function might reach scenarios): `bash -c 'type grep'` gives `/usr/bin/grep`, so
    scripts get GNU grep.
- Reproductions, all on a `git archive 514d0ef` copy, one at a time, each file restored and `cmp`-checked:
  - A probe scenario (`98-p7probe`, copy only, since deleted): forged line, null, 1.5, bad threshold under `run` and under
    `start` (stub systemd-run, no real unit), preflight with `CLAUDE_FLAGS` unset. The probe's own shellcheck failure is
    irrelevant.
  - Four mutants: unit_env without `JOB_JEV_MIN_CONF` (12 PASS), why without the threshold (61 PASS),
    `${JOB_JEV_MIN_CONF-0.7}` (61 PASS), loosened regex (60 and 61 PASS).
  - One earlier regex-mutant run was void: the sed did not match and diff showed no change. It was redone with an exact
    replace.
- No real systemd unit or timer was created by me; the real Jev/OpenRouter was never called (fake jev first on PATH;
  `tests/lib.sh` unsets the key). ExecStart was unchanged after every run.
- Not reproduced (static only): P7R1-1 (code read), P7R1-9 (whether real errors echo the key), P7R1-21 (timer and file
  lifetime), P7R1-22.
