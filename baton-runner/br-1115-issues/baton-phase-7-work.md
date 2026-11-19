---
source: runner
scope: br-1115-issues
parent_session: ""
---
# Pass-Baton: phase 7 work unit, issue 27 (Jev's key reaches the unit; confidence threshold) implemented

**Date:** 2026-11-19
**Scope:** br-1115-issues
**Branch:** feat/br-1115-issues/phase-7
**Worktree:** /home/alex/blast-off/.claude/worktrees/pending-items-53932d
**HEAD:** e924be8 Merge pull request #43 (changes uncommitted; the manager owns git)

## Where things stand

Issue 27 is implemented test-first under the owner's sign-off (2026-11-15): the key is passed, `lib/jev.sh` stays, a
Jev pick below confidence 0.7 keeps the static `CLAUDE_FLAGS`, and `JOB_JEV_MIN_CONF` overrides the threshold, validated
and documented. All three acceptance criteria have tests, and named mutants were killed for each. Scenarios were run
alone, one at a time: 12-start-env, 60-preflight, 61-jev-pick and 70-docs all PASS. I did not run the full gate, 11, 30
or 31. `shellcheck -S warning` is clean on the 9 changed scripts. Nothing is committed. STATE.md and log.md are untouched.

Files changed (tracked, 11; `git diff --stat`: 153 insertions, 33 deletions):
- `lib/units.sh`: `unit_env` adds `--setenv=OPENROUTER_API_KEY` (the name only) when the key is set and not empty, and
  adds `JOB_JEV_MIN_CONF` to the JOB_* names. `unit_env` serves both `start` and the resume timer (`usage_arm`), so the
  timer's service carries the name, and its `blast-off resume` → `unit_start` passes it on.
- `lib/jev.sh`: `jev_flags` sets `JEV_MIN` (`JOB_JEV_MIN_CONF`, default 0.7). After a valid level it compares the
  confidence in jq. Below the threshold it keeps static with `jev picked <level>, confidence <c> below <t>`. When the
  confidence is not a number it keeps static with `jev picked <level>, confidence '<c>' is not a number`. The pick line
  reads `model level for phase <k>: <level> (jev, confidence <c>, threshold <t>): <flags>`, and decisions.tsv's why
  column also carries the threshold. Header comment updated (no more P6Q1).
- `lib/chain.sh`: `chain_nums` also refuses a `JOB_JEV_MIN_CONF` that does not match `^(0(\.[0-9]{1,3})?|1(\.0{1,3})?)$`:
  `JOB_JEV_MIN_CONF='<v>' is not a number from 0 to 1 with at most 3 decimals (0.7, 0.85, 1)`. Both `run` and
  `preflight` refuse it.
- `lib/preflight.sh`: no longer forces the key empty. It calls `jev_flags` with the caller's environment, which is what
  `start` now gives the unit, so preflight makes one Jev call when the key is set. The level line is now one of:
  - `level: phase <k>: <level> under start (jev, confidence <c>, threshold <t>; start passes OPENROUTER_API_KEY by name)`
  - `level: phase <k>: static CLAUDE_FLAGS under start (<why>[; start passes none])`
- `bin/blast-off`: env header gains `JOB_JEV_MIN_CONF=0.7`. The `OPENROUTER_API_KEY` line now says start and the
  resume timer pass it by name when it is set.
- `tests/fakes/jev`: the confidence comes from `$FAKE_JEV/confidence` (JSON, default 0.87).
- `tests/12-start-env.sh`: new section with a scenario-local stub `systemd-run`. The stub records argv plus `key=set`
  when the key reached its environment, and execs the real one only for `--scope` (child scopes). Cases:
  - `start` with a fake key passes `--setenv=OPENROUTER_API_KEY`; systemd-run gets the key from its environment.
  - The printed launch line names it.
  - Unset key and empty key: no such name.
  - `resume` of a paused-cap job passes it.
  - A die75 run arms the resume timer with it.
  - The fake value is on no argv, in no output and in no job file.
- `tests/60-preflight.sh`: the fake key is `sk-or-test-xxx-not-a-key-60`. Cases:
  - p1 expects deep (opus/xhigh), confidence 0.87, threshold 0.7, exactly one jev call about the first open row, and
    the key not printed.
  - New `JOB_JEV_MIN_CONF=0.9` case: static, `jev picked deep, confidence 0.87 below 0.9`.
  - New `JOB_JEV_MIN_CONF=2` case: refused.
  - The no-key line now ends `; start passes none)`.
- `tests/61-jev-pick.sh`: the pick run uses key `sk-or-test-xxx-not-a-key-61` and asserts the value is absent from
  pick.out and the job dir (run.log, decisions.tsv). The pick line expects the threshold. Cases:
  - New fallbacks: low (0.55 < 0.7), high (0.87 < `JOB_JEV_MIN_CONF=0.9`), nan (`"high"`).
  - New picks: at 0.7 exactly, at 0.55 with min 0.5, at 1 with min 1.0.
  - Seven bad `JOB_JEV_MIN_CONF` values are refused with exit 1 and no child.
- `docs/spec.md`: K8 row (threshold, the log shapes, start and the timer pass the key, preflight asks Jev), the
  preflight row, the env paragraph (`JOB_JEV_MIN_CONF`; `OPENROUTER_API_KEY` passed by name under D21's storage class;
  children inherit it), and test rows 12, 60, 61.
- `README.md`: Requirements (threshold), and Check-then-start (start passes the key when set, the log line shape, the
  timer passes the same names, systemd stores the secrets).

Untracked: `baton-runner/br-1115-issues/phase-7/{task_plan,findings,progress}.md` and this file.

## Decisions (also in `phase-7/findings.md`)

- D-P7-1: the key is passed only when it is set and not empty. The JOB_* names are passed whenever set, even empty, but
  an empty `--setenv=OPENROUTER_API_KEY` would only hand the unit an empty key.
- D-P7-2: the comparison runs in jq, which is already a dependency. A pick exactly at the threshold is taken; only a
  confidence below it keeps static. A non-numeric confidence keeps static, with its own reason.
- D-P7-3: `JOB_JEV_MIN_CONF` must be 0 to 1, with at most 3 decimals and a leading digit (`.7` is refused). This
  follows BLAST_OFF_WAIT_POLL's 3-decimal rule and `chain_nums`' "no garbage" style. Empty means the default, as for the
  other JOB_* names.
- D-P7-4: preflight now asks Jev (one call) with the caller's environment. The earlier "no jev call" rested only on
  `start` passing no key.
- D-P7-5: a low-confidence fallback keeps `JEV_LEVEL=static`, so decisions.tsv records `model level static` with the
  reason.

## Evidence

RED, GREEN and mutant runs were each `BLAST_OFF_TEST_ONLY=<one scenario> tests/run`, one at a time. For each mutant the
file was copied aside, changed with sed, the scenario run, the copy restored, and `cmp` reported equal every time.

C1, with the key set: the phase's model comes from Jev and is logged (now under `start` too).
- RED (12-start-env, before unit_env changed): `FAIL: start does not pass --setenv=OPENROUTER_API_KEY: --user`
- GREEN: `GATE-ONLY: PASS passed=1 failed=0 shellcheck=ok only=12-start-env`
- RED (61, the pick line with its threshold): `FAIL: pick not in run.log: 2026-11-19T21:18:52Z child cap 6 (soft: 2 Phase plan rows x JOB_CAP_FACTOR 3)`
- RED (60, preflight's start view): `FAIL: no line /^flags: --model opus --effort xhigh --foo bar$/ in p1.out: job: ...`
- GREEN: `GATE-ONLY: PASS passed=1 failed=0 shellcheck=ok only=61-jev-pick` and `... only=60-preflight`
- Mutants:
  - M3 (the timer path drops the key, `OPENROUTER_API_KEY= unit_env` in usage_arm): `FAIL: the resume timer does not pass --setenv=OPENROUTER_API_KEY: --user`
  - M8 (preflight forces the key empty again): `FAIL: no line /^flags: --model opus --effort xhigh --foo bar$/ in p1.out: ...`
  - M12 (default threshold 0.5): `FAIL: pick not in run.log: ...`

C2, without the key: static flags, logged.
- The runner-side fallback was already tested (61 `nokey`: `no OPENROUTER_API_KEY in the runner environment`) and still
  passes. New in 12: with the key unset or empty, start passes no such name. New in 60: the no-key line ends
  `; start passes none)`.
- Mutants:
  - M1 (key always passed): `FAIL: start with the key unset passes it: --user`
  - M2 (passed when set but empty): `FAIL: start with the key empty passes it: --user`

C3, a low-confidence pick keeps the static flags.
- RED (61, with only the log change in place): `FAIL: low: child flags '--model sonnet --effort medium --foo bar', want static`
- RED (validation): `FAIL: JOB_JEV_MIN_CONF=abc: exit 0, want 1: 2026-11-19T21:21:00Z child cap 3 (soft: 1 Phase plan rows x JOB_CAP_FACTOR 3)`
- GREEN: `GATE-ONLY: PASS passed=1 failed=0 shellcheck=ok only=61-jev-pick`
- Mutants:
  - M4 (`<=`): `FAIL: at: child flags '--model fake --effort low --foo bar', want light's`
  - M5 (no low branch): `FAIL: low: child flags '--model sonnet --effort medium --foo bar', want static`
  - M7 (non-number taken): `FAIL: nan: child flags '--model sonnet --effort medium --foo bar', want static`
  - M6 (validation regex loosened): `FAIL: JOB_JEV_MIN_CONF=abc: exit 0, want 1: ...`

Secret handling:
- The tests use only fake keys (`sk-or-test-xxx-not-a-key-27/-60/-61`); `tests/lib.sh` unsets any real
  OPENROUTER_API_KEY for every scenario. I never read `~/.secrets` or settings.local.json, and the real jev was never
  called (fake jev first on PATH).
- 12 asserts the stub's argv holds the line `--setenv=OPENROUTER_API_KEY` exactly, holds no value, and that the stub got
  the key from its environment. It also asserts the value is absent from start's, resume's and run's output and from
  every file in the job dir (run.log included), for start, resume and the timer.
- 60 asserts the value is not in preflight output. 61 asserts it is not in the run output or the job dir.
- Mutants:
  - M10 (value on argv, `--setenv=OPENROUTER_API_KEY="$OPENROUTER_API_KEY"`): `FAIL: start does not pass --setenv=OPENROUTER_API_KEY: --user`
  - M9 (preflight prints the key): `FAIL: preflight printed the key's value`
  - M11 (the runner logs the key) first SURVIVED, because 61 never checked run.log for the value. I added the check;
    after that: `FAIL: the key's value is in pick.out`.

Docs: `GATE-ONLY: PASS passed=1 failed=0 shellcheck=ok only=70-docs`. Final single runs, after all edits: 70-docs,
12-start-env, 60-preflight and 61-jev-pick each `GATE-ONLY: PASS`. `shellcheck -S warning` on lib/jev.sh, lib/units.sh,
lib/chain.sh, lib/preflight.sh, bin/blast-off, tests/12-start-env.sh, tests/60-preflight.sh, tests/61-jev-pick.sh and
tests/fakes/jev printed nothing.

ExecStart check: before the first run and after every run (each RED, GREEN and mutant run), always
`ExecStart=/home/alex/blast-off/.worktrees/blast-off-build/bin/blast-off run %f`. No scenario I ran installs units. The
12 die75 case launches one real child scope through the stub's pass-through, as test 30 does. Its timer call is stubbed,
so no real timer is armed.

## Open questions / risks

- Q1 (default applied): preflight now makes one real Jev/OpenRouter call whenever the caller has the key, at a small
  cost per preflight, and it can take up to jev's 60 s timeout. The alternative is no call, printing "Jev picks under
  start, threshold 0.7" without a level. I took the call because the brief asks for the level it would use.
- Q2 (default applied, not changed): children inherit OPENROUTER_API_KEY through the job's tmux server, as they inherit
  GH_TOKEN, and as they already did under a foreground run with the key. `child_server` scrubs only `CLAUDE*`. Adding
  `-u OPENROUTER_API_KEY` there would keep the key away from bypass-permission children, but it changes foreground
  behaviour, so I left it for the owner.
- Q3 (default applied): `JOB_JEV_MIN_CONF` allows at most 3 decimals and needs a leading digit; `0.12345` and `.7` are
  refused.
- `start` (`unit_check`) does not validate `JOB_JEV_MIN_CONF`. A bad value starts the unit, and the runner then dies
  in `chain_nums` with the message on stderr (journal) only. Bad JOB_* counts already behave this way. preflight refuses
  it.
- The not-a-number reason prints jev's confidence field uncut into run.log. jev is a local trusted tool; cut it to 40
  chars if the review wants.
- SKILL.md's hand-over (`export GH_TOKEN CLAUDE_FLAGS=...`) does not mention exporting OPENROUTER_API_KEY. I left it
  alone because it was not in the brief's doc list. The owner gets Jev under start only when the key is already in the
  terminal's environment.
- docs/decision-log/build-2026-11-04.tsv row 140 still records the original "start does NOT pass it" decision. It is a
  historical log, so I did not edit it.
- At start, STATE.md and log.md showed as modified in git status; at the end they no longer did. I never touched them.

## Next step for the review unit

Run the full gate alone (`scripts/gate.sh`) and check ExecStart afterwards. 11, 30 and 31 go through `unit_env` and
`chain_nums`; they set neither name, so they should not change. Then review `git diff e924be8` on the 11 tracked files.
Check:
- Q1 (preflight's Jev call) and Q2 (children see the key).
- That the stub in 12 cannot mask a real `--scope` failure.
- The wording of the spec's K8, env and preflight changes.
