# Phase 7 finding-fixer (round 1 findings)

Workflow wf_9117e623-7cc: 3 read-only adjudicators, 1 writer. Skipped: none. coverage.unreported: none.
Verify (writer, and re-run by the manager): `GATE-ONLY: PASS passed=7 failed=0 shellcheck=ok` (11, 12, 20, 51, 60, 61, 70); ExecStart unchanged.

| ID | Verdict | Result |
|---|---|---|
| P7R1-1 | fix-here | applied: child_server's env now has -u OPENROUTER_API_KEY, so the job's tmux server and every child start without the key. Header comment added. The fake claude records openrouter=set/unset. k4 in 12-start-env pins it. spec.md :67 and section 4 now say children never get the key. |
| P7R1-7 | fix-here | applied: unit_env passes --setenv=OPENROUTER_API_KEY only when JOB_JEV is not 0 and the value starts sk-or-, the same tests jev_flags uses. Comments, --help, spec :67, README and the 12 comment updated. The 12 loop gains the off and tskey cases. One extra edit to keep the docs consistent: the K8 row in spec.md said 'by name when it is set (issue 27)' and now says 'when Jev can use it (issue 27)'. Also, P7R1-4.2's replacement text says 'when Jev can use it' rather than 'when it is set', for the same reason. |
| P7R1-9 | fix-here | applied: The jev-failed reason replaces every non-printable byte with a space and masks sk-or-[^[:space:]"]* as sk-or-.... A refused level has its non-printable characters replaced before it is logged. The fake jev gains an echo-key mode, and 61 gains errkey and the multi-line level case. That case was renamed from forge to forgelvl, because P7R1-8 also adds a fallback named forge. Two fallbacks with the same name would share jev-forge/calls and break the call count, so P7R1-8's case is now forgeconf. |
| P7R1-16 | fix-here | applied: nokey in 12, and the pick-run key check in 61, now grep -F for the key's first and last 12 characters and require grep rc 1, so a partial leak or a missing path fails. Mutations (1) and (2) were applied together and then reverted. Mutation (2) used a set -u safe form, $(printf %.12s "${OPENROUTER_API_KEY:-}"), because the literal ${OPENROUTER_API_KEY:0:12} aborts under set -u in 12's unset-key start. Mutation (3), a missing path, was not run. |
| P7R1-19 | fix-here | applied: spec.md: D14 now names both secrets; the D21 status says it is settled and extends to the key; :203 says 'secrets'; the start row names --setenv=OPENROUTER_API_KEY; the exit-1 row names the JOB_JEV_MIN_CONF refusal. Also edited: the deviations row, README children sentence, and templates/brief.md D1. P7R1-19.6 and P7R1-5.6 change the same text on spec row 94, so they were applied as one edit: '(shell arithmetic reads `010` as 8, owner question Q3), a `JOB_JEV_MIN_CONF` that is not a number from 0 to 1 with at most 3 decimals and a leading digit (`run` logs either refusal in `run.log` too), `git rev-parse`'. The row keeps its existing 'also logged in run.log' for child-count. |
| P7R1-21 | real-but-decided-elsewhere | applied: Documentation only. spec :203 and the README start paragraph now say the timer keeps the values it had when it was armed, so a key exported or rotated later never reaches it and a stale key falls back with a log line. |
| P7R1-27 | real-but-decided-elsewhere | no edit: lib/units.sh:21 `UNIT_ENV=(--setenv=PATH ...)` passes the caller's PATH unchanged, and unit_start runs the runner with `--working-directory="$WORKDIR"` (units.sh:41), which children write to. lib/jev.sh:37 `command -v jev` and :39 `... timeout 60 jev -q ...` resolve jev through that PATH. If the owner's PATH has a relative or empty entry ('.', '::', a trailing ':') ahead of ~/.local/bin, a jev planted in the workdir by a child would run in the runner with the key. This needs the owner's PATH to hold such an entry, and, as the finding says, it applies to every tool the runner calls, not only jev. The manager default (house rule 6) says no edit; a follow-up issue owns it. |
| P7R1-3 | fix-here | applied: 61 now pins column 4 (why) of decisions.tsv for the pick row and for every fallback row. The spec catalog row is updated to match. |
| P7R1-8 | fix-here | applied: A confidence that is not a number is shown as tojson cut to 40 characters. The case gains a none arm (null or missing) and a range arm (outside 0 to 1), and the catch-all arm now says 'its confidence could not be checked'. Header comment, K8 and the catalog row updated. The nan case's expected text changed, and the forged-confidence case was added, named forgeconf (see P7R1-9). Its own red never showed, because the nan case fails earlier in the same run. It passes after the edit. |
| P7R1-10 | fix-here | applied: New fallback 'over' (confidence 1.5) expects static flags and 'confidence 1.5 is not from 0 to 1'. The code is the range arm in P7R1-8's edit. |
| P7R1-11 | fix-here | applied: New fallback 'null' expects 'jev picked light, no confidence'. The code is the none arm in P7R1-8's edit. |
| P7R1-12 | already-handled | no edit: The misreport needs `--argjson t "$JEV_MIN"` to fail, and both callers validate the threshold before jev_flags runs. lib/chain.sh:153 `chain_nums // die "$NUMS_ERR"` runs before any child, and so before jev_pick. lib/preflight.sh:15 `chain_nums // { echo "preflight: refused: $NUMS_ERR"; exit 1; }` runs before jev_flags at :22. chain_nums at lib/chain.sh:100 `[[ ${JOB_JEV_MIN_CONF:-0.7} =~ ^(0(\.[0-9]{1,3})?/1(\.0{1,3})?)$ ]]` admits only strings that are valid JSON numbers, and jev.sh:30 uses the same `:-0.7` default. $out has already parsed as JSON for `.level.choice` at :43, or the function returned at :44. The reviewer agrees it is "unreachable today (chain_nums runs first on both callers)". P7R1-8's edit gives the `nan` case its own arm. The `*)` arm then reads `its confidence could not be checked`, so even an unreachable failure would no longer be labelled "not a number". |
| P7R1-13 | fix-here | applied: Added `picked empty 0.87 0.7 JOB_JEV_MIN_CONF=`. The catalog row is updated. |
| P7R1-14 | fix-here | applied: Added `picked zero` (threshold 0) and `picked full` (threshold 1.000). The bad-value loop gains 00.7, 0.1234 and 1.. The catalog row names them. The regex is unchanged. |
| P7R1-22 | real-but-decided-elsewhere | no edit: The risk is real. lib/jev.sh:58-63: jev_pick sends `cp_row "$k"` (the first open row of the child-written checkpoint.md) to jev with no size cap, and nothing caps the level (deep = `--model opus --effort xhigh`, jev.sh:12). A row worded to call for deep work gets a confident `deep`, which the threshold does not stop. Owner/manager ruling, item 6: "P7R1-22 (level ceiling, row cap) ... = no edit; verdict real-but-decided-elsewhere, owner: a follow-up issue." |
| P7R1-23 | fix-here | applied: If mktemp fails, jev_flags now falls back with 'jev not asked: no temp file in <dir>' instead of dying under set -e. 60 pins this under preflight, and the catalog row is updated. |
| P7R1-24 | refuted | no edit: The real jev, read only (/home/alex/JevDev/bin/jev, byte-identical to ~/.local/bin/jev by cmp), does not produce either case. (1) Timeout: its request is `resp=$(curl -q -sS --fail-with-body -m 30 ...) // { printf '%s\n' "$resp" >&2; exit 2; }` (jev:121-123). curl's own `-m 30` fires well inside blast-off's `timeout 60` (lib/jev.sh:39), and `-sS` writes curl's error to stderr, so a network timeout logs `jev failed: curl: (28) ...`, not an empty reason. The 60 s timeout only fires if jev hangs outside curl, and after curl jev runs only local jq. (2) Non-JSON: jev runs `set -euo pipefail` (jev:5), and for -q it runs `[ "$type" = raw ] && { printf '%s\n' "$resp" / jq '.answers'; exit 0; }` (jev:129). A body that is not JSON makes jq fail inside the final && block, so jev exits nonzero with jq's message. That gives `jev failed: jq: ...`, never exit 0 with non-JSON stdout. A null `.answers` prints `null` and logs `jev answered 'nothing', not a level`, which is accurate. Each fallback is safe either way: static flags, logged. |
| P7R1-25 | fix-here | applied: jev_flags now reads ${CLAUDE_FLAGS:-} at :30 and on the pick path, so preflight with CLAUDE_FLAGS unset reaches its refusal line. 60 pins it with the key set, and the catalog row says 'empty or unset'. |
| P7R1-26 | fix-here | applied: NUMS_ERR now quotes the value with ${!v@Q} and ${JOB_JEV_MIN_CONF@Q}, so a value holding a newline stays on one line. Every refusal message that 21, 60 and 61 grep for still matches. 60 gains the p-nl case, and the catalog row is updated. |
| P7R1-28 | refuted | no edit: The risk (the fake's shape could differ from the real one) is contradicted by the real client. /home/alex/JevDev/bin/jev (read only, never run; byte-identical to ~/.local/bin/jev) prints the API's `.answers` object unchanged for -q: `[ "$type" = raw ] && { printf '%s\n' "$resp" / jq '.answers'; exit 0; }` (jev:129). Its own choice path reads the same fields from the API answer: `a=$(printf '%s\n' "$resp" / jq '.answers.q')` and `choice) jq -r '"\(.choice)\t(confidence \(.confidence))"' <<<"$a"` (jev:131,135). So for question key `level` the real -q output is `{"level":{"choice":...,"confidence":...}}`, which is the shape tests/fakes/jev:16-17 emits and lib/jev.sh:43-46 reads. The proposed key-free real fixture cannot exist: `-n` prints only the request body (jev:115), so any real answer needs the key, which this run must not use. |
| P7R1-2 | fix-here | applied: k1 and k4 set JOB_JEV_MIN_CONF=0.9 and assert --setenv=JOB_JEV_MIN_CONF for start and for the timer. The dead FAKE_JEV on the k4 line is gone (P7R1-6). |
| P7R1-4 | fix-here | applied: The K8 preflight clause and the preflight row now call preflight's level a separate sample, a forecast that can differ from the runner's (owner ruling Q1). In the preflight row, the adjudicated text's 'when it is set' became 'when Jev can use it' to match P7R1-7. SKILL.md step 7's hand-over now covers the key, the per-phase Jev pick, JOB_JEV_MIN_CONF and JOB_JEV=0. Not edited: preflight.sh:20-21 and the 60 header, which the adjudicator left out of scope. |
| P7R1-5 | fix-here | applied: unit_check calls chain_nums, so start and resume refuse a bad JOB_* number on the terminal before any systemd-run. chain_run logs the refusal to run.log. 12 gains the badconf block. spec's start and resume rows say so, and README lists the case. P7R1-5.6 was merged into P7R1-19.6 (same spec text). status and wait still do not show the refusal. Only run.log, which `blast-off logs` shows, has it, as the adjudicator decided. The anchor for the 12 block was the nokey line as P7R1-16 left it. |
| P7R1-6 | fix-here | applied: 12's k3 and k4 assert key=set for resume's and the timer's systemd-run. 11 gains a keyjob under a real unit: the runner gets the fake key and reaches the fake jev, which fails because the unit has no FAKE_JEV. |
| P7R1-15 | fix-here | applied: After the JOB_JEV_MIN_CONF=2 refusal, 60 asserts that p15.out is one line and the fake jev was called exactly twice, and that p14.out does not hold the key. |
| P7R1-17 | fix-here | applied: argv() now fails when one step made more than one non-scope systemd-run call. |
| P7R1-18 | fix-here | applied: tests/lib.sh also unsets JOB_JEV and JOB_JEV_MIN_CONF, so a bad value in the caller's shell cannot fail a scenario. |
| P7R1-20 | fix-here | applied: The 12 header names every case the scenario covers, k3 checks that the key's value is not on resume's argv, and spec row 12-start-env describes exactly what the scenario checks. The adjudicator's mutation is caught at k1 first, so for the red I used a resume-only mutation placed after unit_start's echo line: args+=(--setenv=OPENROUTER_API_KEY="$OPENROUTER_API_KEY") when FUNCNAME[1] is unit_resume. The current test missed it, and the new k3 line caught it. |

## Red runs (test failing before each edit)

### P7R1-1
```
12-start-env before the child.sh edit:
  | FAIL: a child saw OPENROUTER_API_KEY: child=1 pid=2415824 mode=die75 gh_token=set prev_alive=no
  | status_at_start=running
  | settings=/run/user/1000/blast-off-test-2415586-keytimer-child.JehTvS/settings.json
  | claude_env=0
  | openrouter=set
  | flags=--model fake --effort low
GATE-ONLY: FAIL passed=0 failed=1 shellcheck=ok only=12-start-env
```

### P7R1-7
```
12-start-env before the units.sh edit:
  | FAIL: start with the key off passes it: --user   | --collect   | --unit=blast-off-test-2418009-keyed   | --working-directory=/tmp/tmp.WoqBoSdvjU/cwd/test-2418009-keyed ...
GATE-ONLY: FAIL passed=0 failed=1 shellcheck=ok only=12-start-env
```

### P7R1-9
```
Run 1, tests added, jev.sh unchanged:
  | FAIL: errkey: reason 'jev failed: Authorization: Bearer sk-or-... {"error":"fake failure"}' not logged: 2026-11-19T22:26:10Z model level for phase 1: static CLAUDE_FLAGS (jev failed: Authorization: Bearer sk-or-fake-echo-not-a-key-61 {"error":"fake failure"}): --model fake --effort low --foo bar
GATE-ONLY: FAIL passed=0 failed=1 shellcheck=ok only=61-jev-pick
Run 2, after the :40 mask edit and before the :44 edit:
  | FAIL: forgelvl: reason 'jev answered 'x 2099-01-01T00:00:00Z forged', not a level' not logged: 2026-11-19T22:26:34Z model level for phase 1: static CLAUDE_FLAGS (jev answered 'x
GATE-ONLY: FAIL passed=0 failed=1 shellcheck=ok only=61-jev-pick
```

### P7R1-16
```
Mutants jev.sh:69 '+ $(printf %.14s "${OPENROUTER_API_KEY:-}")' and units.sh echo '+ $(printf %.12s "${OPENROUTER_API_KEY:-}")', run against the current tests:
PASS 12-start-env
PASS 61-jev-pick
GATE-ONLY: PASS passed=2 failed=0 shellcheck=ok only=12-start-env,61-jev-pick
The same mutants against the new checks:
FAIL 12-start-env
  | FAIL: grep rc 0: the key, or 12 chars of it, is in k1.out
FAIL 61-jev-pick
  | FAIL: grep rc 0: the key, or 12 chars of it, is in pick.out
GATE-ONLY: FAIL passed=0 failed=2 shellcheck=ok only=12-start-env,61-jev-pick
Both mutants were then reverted from backups (grep count 0).
```

### P7R1-19
```
n/a - docs; 70-docs and 51-templates PASS in the final run. Ledger re-checked on the applied brief.md D1 line: '| D1 | Child model and flags | `CLAUDE_FLAGS` from the launch line (`--model <m> --effort <e>`; when the runner holds Jev's key, Jev may pick each phase's `--model`/`--effort`, and `JOB_JEV=0` keeps them); children never change or widen it |'. Checks: D1 id preserved. 'Child model and flags' preserved. '`CLAUDE_FLAGS` from the launch line' preserved. '(`--model <m> --effort <e>`' preserved. 'children never change or widen it' preserved. Added 'when the runner holds Jev's key, Jev may pick each phase's `--model`/`--effort`' holds. Added '`JOB_JEV=0` keeps them' holds. No other difference.
```

### P7R1-21
```
n/a - prose only; 70-docs PASS in the final run.
```

### P7R1-3
```
Mutant lib/jev.sh:71 why="${JEV_WHY:-jev choice, confidence $JEV_CONF}", run against the current test:
PASS 61-jev-pick
GATE-ONLY: PASS passed=1 failed=0 shellcheck=ok only=61-jev-pick
The same mutant against the new lines:
  | FAIL: phase 1 why is not its confidence and threshold: ts	phase	decision	why	evidence	result
GATE-ONLY: FAIL passed=0 failed=1 shellcheck=ok only=61-jev-pick
The mutant was then reverted (line 71 checked).
```

### P7R1-8
```
61-jev-pick, tests added, jev.sh unchanged:
  | FAIL: nan: reason 'jev picked light, confidence "high" is not a number' not logged: 2026-11-19T22:29:21Z model level for phase 1: static CLAUDE_FLAGS (jev picked light, confidence 'high' is not a number): --model fake --effort low --foo bar
GATE-ONLY: FAIL passed=0 failed=1 shellcheck=ok only=61-jev-pick
```

### P7R1-10
```
61-jev-pick before the P7R1-8 code edit:
  | FAIL: over: child flags '--model sonnet --effort medium --foo bar', want static
GATE-ONLY: FAIL passed=0 failed=1 shellcheck=ok only=61-jev-pick
```

### P7R1-11
```
61-jev-pick before the P7R1-8 code edit:
  | FAIL: null: reason 'jev picked light, no confidence' not logged: 2026-11-19T22:30:30Z model level for phase 1: static CLAUDE_FLAGS (jev picked light, confidence '?' is not a number): --model fake --effort low --foo bar
GATE-ONLY: FAIL passed=0 failed=1 shellcheck=ok only=61-jev-pick
```

### P7R1-13
```
Mutants jev.sh:30 ${JOB_JEV_MIN_CONF-0.7} and the P7R1-14 regex, run against the current tests:
PASS 61-jev-pick
GATE-ONLY: PASS passed=1 failed=0 shellcheck=ok only=61-jev-pick
The same mutants against the new lines:
  | FAIL: empty: child flags '--model fake --effort low --foo bar', want light's
GATE-ONLY: FAIL passed=0 failed=1 shellcheck=ok only=61-jev-pick
The jev.sh mutant was then reverted (default form checked).
```

### P7R1-14
```
The loosened regex ^(0+(\.[0-9]{1,4})?|1(\.0*)?)$ survived the current tests (the PASS run shared with P7R1-13 above). With the P7R1-13 mutant reverted and only this one left, against the new lines:
  | FAIL: JOB_JEV_MIN_CONF=00.7: exit 0, want 1: 2026-11-19T22:33:20Z child cap 3 (soft: 1 Phase plan rows x JOB_CAP_FACTOR 3)
GATE-ONLY: FAIL passed=0 failed=1 shellcheck=ok only=61-jev-pick
The mutant was then reverted from backup (regex checked).
```

### P7R1-23
```
60-preflight before the jev.sh edit:
  | FAIL: no temp dir for jev: exit 1: job: /tmp/tmp.WmkR9QF9VA/cwd/test-2518411-pf/job · workdir: /tmp/tmp.WmkR9QF9VA/cwd/test-2518411-pf · unit: blast-off-test-2518411-pf.service
  | mktemp: failed to create file via template '/tmp/tmp.WmkR9QF9VA/cwd/no-such-dir/blast-off-jev.XXXXXX': No such file or directory
GATE-ONLY: FAIL passed=0 failed=1 shellcheck=ok only=60-preflight
```

### P7R1-25
```
60-preflight before the jev.sh edit:
  | FAIL: no line /^preflight: refused: CLAUDE_FLAGS is unset or empty$/ in p-unset.out: job: /tmp/tmp.68EdNZGrxa/cwd/test-2517446-pf/job · workdir: ... · unit: blast-off-test-2517446-pf.service
  | /home/alex/blast-off/.claude/worktrees/pending-items-53932d/lib/jev.sh: line 31: CLAUDE_FLAGS: unbound variable
GATE-ONLY: FAIL passed=0 failed=1 shellcheck=ok only=60-preflight
```

### P7R1-26
```
60-preflight before the chain.sh edit:
  | FAIL: JOB_JEV_MIN_CONF's newline printed a line of its own: preflight: refused: JOB_JEV_MIN_CONF='x
  | preflight: ok
  | ' is not a number from 0 to 1 with at most 3 decimals (0.7, 0.85, 1)
GATE-ONLY: FAIL passed=1 failed=1 shellcheck=ok only=60-preflight,61-jev-pick
```

### P7R1-2
```
The units.sh loop without JOB_JEV_MIN_CONF survived the current tests (shared mutant PASS run: PASS 11-unit-smoke, PASS 12-start-env, PASS 60-preflight; GATE-ONLY: PASS passed=3 failed=0). With the P7R1-17 mutant reverted, against the new lines:
  | FAIL: start does not pass --setenv=JOB_JEV_MIN_CONF: --user
GATE-ONLY: FAIL passed=0 failed=1 shellcheck=ok only=12-start-env
The mutant was then reverted (loop checked).
```

### P7R1-4
```
n/a - docs; 70-docs PASS. Ledger re-checked on the applied SKILL.md. The start line '   blast-off start <job-dir>          # transient unit blast-off-<name>.service' is unchanged, and so is its comment. The closing fence '   ```' is unchanged and still sits between the first and second block. Step 7's lines 55-56 are untouched. Added, as an indented paragraph after the fence: 'Tell the owner with it:' holds. 'when the shell that runs `start` has `OPENROUTER_API_KEY` (an OpenRouter `sk-or-` key)' holds. '`start` passes it to the unit by name' holds. 'Jev then picks `--model` and `--effort` for each phase in place of those in `CLAUDE_FLAGS`' holds. '(its other flags stay; a pick below `JOB_JEV_MIN_CONF`, default 0.7, keeps them)' holds. '`JOB_JEV=0`, exported before `start`, keeps `CLAUDE_FLAGS` for every phase.' holds. 'Step 6's `level` line is preflight's own Jev call from your environment, a forecast:' holds. 'the runner asks again with the environment `start` passes from the owner's shell, so the two can differ.' holds. Nothing was dropped, and there is no other difference.
```

### P7R1-5
```
12-start-env, test added, code unchanged:
  | FAIL: start with JOB_JEV_MIN_CONF=.7: exit 0: systemd-run --user --collect --unit=blast-off-test-2545512-badconf ... --setenv=JOB_JEV_MIN_CONF -p Type=exec ...
GATE-ONLY: FAIL passed=0 failed=1 shellcheck=ok only=12-start-env
After the units.sh edit only, before chain.sh:
  | FAIL: run with JOB_JEV_MIN_CONF=.7: exit 1, run.log: cat: /tmp/tmp.1A6PjDPKoP/cwd/test-2545859-badconf/job/run.log: No such file or directory
GATE-ONLY: FAIL passed=0 failed=1 shellcheck=ok only=12-start-env
```

### P7R1-6
```
Mutants (1) chain_run first line '[ -z "${INVOCATION_ID:-}" ] || unset OPENROUTER_API_KEY' and (2) usage.sh 'env -u OPENROUTER_API_KEY systemd-run ...' survived the current tests (the shared PASS run). Against the new lines:
FAIL 11-unit-smoke
  | FAIL: the runner under the unit did not get the key: 2026-11-19T22:36:33Z model level for phase 1: static CLAUDE_FLAGS (no OPENROUTER_API_KEY in the runner environment): --model fake --effort low
With only mutant (2) left (the others reverted one at a time):
  | FAIL: the timer's systemd-run did not get the key in its environment: --user
GATE-ONLY: FAIL passed=0 failed=1 shellcheck=ok only=12-start-env
Both mutants were then reverted (git diff of usage.sh is clean).
```

### P7R1-15
```
Mutant: lib/preflight.sh's chain_nums refusal moved below the job: echo. It survived the current tests (PASS 60-preflight in the shared run). Against the new lines:
  | FAIL: JOB_JEV_MIN_CONF=2 printed more than its refusal: job: /tmp/tmp.E86nSCFPKn/cwd/test-2541349-pf/job · workdir: /tmp/tmp.E86nSCFPKn/cwd/test-2541349-pf · unit: blast-off-test-2541349-pf.service
GATE-ONLY: FAIL passed=0 failed=3 ...
The mutant was then reverted from backup (git diff of preflight.sh is clean).
```

### P7R1-17
```
Mutant: 'systemd-run --user --quiet true 2>/dev/null || true' inserted before unit_start's systemd-run. It survived the current tests (PASS 12-start-env in the shared run). Against the new argv():
  | FAIL: 2 systemd-run calls in one step: --user
The mutant was then reverted.
```

### P7R1-18
```
JOB_JEV_MIN_CONF=.7 in the caller's env, after P7R1-5 and before the lib.sh edit:
  | FAIL: start with the key unset: exit 1: blast-off: JOB_JEV_MIN_CONF='.7' is not a number from 0 to 1 with at most 3 decimals (0.7, 0.85, 1)
GATE-ONLY: FAIL passed=0 failed=1 shellcheck=ok only=12-start-env
```

### P7R1-20
```
The resume-only mutant survived the current tests (PASS 12-start-env in the shared run). With the P7R1-17 and P7R1-2 mutants reverted, against the new k3 line:
  | FAIL: the key's value is on resume's systemd-run argv
GATE-ONLY: FAIL passed=0 failed=1 shellcheck=ok only=12-start-env
The mutant was then reverted (diff of units.sh against HEAD shows only the P7R1-7 change at that point).
```
