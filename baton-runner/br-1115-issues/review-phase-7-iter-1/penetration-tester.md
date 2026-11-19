# penetration-tester: phase 7 review, round 1 (static, read-only)

## Static pen-test review: phase 7 (issue 27), commit 514d0ef vs e924be8

**Bottom line:** the key never reaches any argv, any printed line, `status`, `run.log` or `decisions.tsv` through blast-off's own code. `JOB_JEV_MIN_CONF` is validated before every `jq --argjson` call. The real exposures are:
- children now hold the key under `start`;
- the key is stored at rest in transient unit files, for days in the resume-timer case;
- two raw-text paths from jev into `run.log`, `decisions.tsv` and preflight output.

Nothing was executed. Everything is from reading code. Items I could not settle by reading are marked UNVERIFIED.

### Verified safe (no finding)
- **argv / ps:**
  - `unit_start` (`lib/units.sh:41-47`) and `usage_arm` (`lib/usage.sh:70-71`) put only `--setenv=OPENROUTER_API_KEY` on argv.
  - The jev call (`lib/jev.sh:39`) carries no key on argv.
  - `child_server`'s `env $scrub PATH=... BLAST_OFF=...` (`lib/child.sh:21`) and `child_launch`'s tmux command string (`lib/child.sh:49`) carry no key.
- **Printed launch line:** `echo "systemd-run ${args[*]}"` (`lib/units.sh:46`) prints names only.
- **`status`:** `lib/units.sh:73-80` prints the checkpoint header, ActiveState, child-count and the timer state. No environment.
- **`JOB_JEV_MIN_CONF` → `jq --argjson`:**
  - `jev_flags` has only two callers, and both validate first: `chain_run` runs `chain_nums` at `chain.sh:153` before `jev_pick` at :216, and `preflight_run` runs `chain_nums` at `preflight.sh:15` before `jev_flags` at :23.
  - The regex `^(0(\.[0-9]{1,3})?|1(\.0{1,3})?)$` admits only numeric JSON.
  - Even an unvalidated bad value would make jq error out and land in the `*` branch, a static fallback.
  - No unvalidated path exists.
- **Low/ok branches:** `JEV_CONF` is printed only after jq has typed it as a number, so those branches cannot inject.
- **Picked level:** the level is checked against the fixed `jev_level` table, so a pick cannot inject flags.

### Findings

**PT-1 · MEDIUM · Children (bypass permissions) now get OPENROUTER_API_KEY under `start`**
- **Location:** `lib/child.sh:13,21` (the scrub covers only `CLAUDE*`); `lib/units.sh:22`.
- **Path:**
  - The unit gets the key, so the runner's environment has it.
  - `child_server` starts the tmux server with that environment.
  - Every child window inherits it: the `claude` process and every tool, hook, MCP server and test it spawns.
  - Any same-user process can also read it with `tmux -L blast-off-<name> show-environment -g`. With `JOB_KEEP_WINDOWS` set, the tmux server keeps it in memory after the runner exits, with no end date.
- **New vs before:** yes, for `start` and the resume timer. Before this change, children under `start` never had it; only a foreground `run` leaked it this way.
- **What it enables:**
  - A prompt-injected child can spend on, or exfiltrate, the key with zero effort (`printenv`, `curl` to OpenRouter).
  - Accidental leaks become possible: `env` dumps in gate logs, test output or Claude transcripts under `~/.claude/projects` (UNVERIFIED whether a transcript uploader scrubs `sk-or-`). A hook or MCP server that reads `OPENROUTER_API_KEY` would bill the owner's key inside every child (UNVERIFIED whether any such hook exists in the user config).
- **Mitigating fact:** a bypass-permission child running as the same user can already read `~/.secrets`, the transient unit file and `/proc/<runner>/environ`. The real increase is "trivial and accidental" access, not "possible at all".
- **Precondition:** `OPENROUTER_API_KEY` is set when `start` or `resume` runs.
- **Fix:**
  - Jev runs only in the runner, so add `-u OPENROUTER_API_KEY -u TYPESAFE_API_KEY` to `child_server`'s `env` call, e.g. `env $scrub -u OPENROUTER_API_KEY PATH=... tmux ...`.
  - Add a test-12 or test-61 assertion that a fake child does not see the key.
  - The implementer left this as Q2.

**PT-2 · LOW (accepted class, but now a second secret held longer) · Key at rest in transient unit files and the `Environment` property**
- **Location:** `lib/units.sh:22`; `lib/usage.sh:69-71`.
- **Where the key sits:**
  - `$XDG_RUNTIME_DIR/systemd/transient/blast-off-<name>.service` for the runner's whole life.
  - `blast-off-<name>.resume.service` from the moment the timer is armed until it fires and the service is collected. For a `seven_day` pause that can be several days.
  - Readable by the same uid and root (0644 file in a 0700 dir, per the spec), via `systemctl --user show -p Environment <unit>`, and via `/proc/<runner pid>/environ`.
- **Timer lifetime, UNVERIFIED:**
  - I believe `systemd-run` sets `RemainAfterElapse=no` on transient timers, so the timer unloads after it fires and `--collect` then collects the service.
  - If that is wrong, the elapsed timer keeps referencing the service and its file (with the key) stays until a manual `systemctl --user stop` or `reset-failed`.
  - `unit_stop` (`lib/units.sh:88`) stops `$UNIT.resume.timer` but not `$UNIT.resume.service`. I assume the unreferenced, never-started service is garbage-collected; UNVERIFIED.
- **Also:**
  - If the job ends another way (the owner runs `run` in the foreground), the armed timer keeps the old key until it fires and `resume` refuses the status.
  - A rotated key leaves the old value in any armed timer. That fails safe: jev fails and the runner falls back to static flags.
- **Precondition:** same-uid access.
- **Fix:**
  - Owner-accepted (D21, issue 27), so no code change required.
  - Optional: `-p LoadCredential=`/`SetCredential=` instead of `--setenv`. Otherwise, document the timer's multi-day window in the README.
  - Verify the timer and service actually unload after firing.

**PT-3 · LOW · The key is passed and stored even when it cannot be used**
- **Location:** `lib/units.sh:22`.
- **Path:** `unit_env` passes the name whenever the value is non-empty, even with `JOB_JEV=0` or with a value that is not `sk-or-`. Yet `jev_flags` (`lib/jev.sh:32-35`) refuses to use the key in exactly those cases. The result is a stored secret and child exposure (PT-1) for no benefit, possibly another provider's key held under that name.
- **Fix:** `[[ ${JOB_JEV:-1} != 0 && ${OPENROUTER_API_KEY:-} == sk-or-* ]] && UNIT_ENV+=(--setenv=OPENROUTER_API_KEY)`, plus the matching doc and test-12 cases.

**PT-4 · LOW · Log, TSV and preflight-output injection through a confidence that is not a number**
- **Location:** `lib/jev.sh:45` and `:49`; reaches `lib/jev.sh:67,71-75` and `lib/preflight.sh:176`.
- **Path:**
  - `JEV_CONF="$(jq -r '.level.confidence // "?"')"`. When the confidence is a JSON string, `-r` prints it raw, including real newlines, tabs, CR and ESC.
  - When it is an object or array, `-r` prints multi-line pretty JSON.
  - The type check routes it to `*`, so `JEV_WHY="... confidence '$JEV_CONF' is not a number"`.
  - **run.log:** `log` (`bin/blast-off:55`, `printf | tee`, no sanitising) writes it to `run.log` and to stdout, which is the journal under the unit. A confidence like `"x\n2099-01-01T00:00:00Z job done\ny"` forges a timestamped `run.log` line, the same class P5R1-5 closed for `child-count`.
  - **decisions.tsv:** only `\r` is stripped, so tabs and newlines break the 6-column TSV and can forge rows.
  - **preflight:** the line is echoed raw to stdout, which the orchestrating Claude session reads. It could plant a fake `preflight: ok` line or prompt-injection text there.
  - Multiple JSON documents on jev's stdout also make `JEV_CONF` multi-line. That still fails safe (no pick).
- **Precondition:** control of jev's JSON. That means a replaced or compromised `~/.local/bin/jev` (which already implies code execution as the user), or jev passing a server-side field through unparsed (UNVERIFIED how the real jev builds `confidence`).
- **Fix:** print the confidence safely, e.g. `jq -r '.level.confidence | if type=="number" then tostring else (tojson|.[0:40]) end'` (`tojson` escapes control characters). Or pipe `JEV_WHY` through `tr -d '[:cntrl:]' | cut -c1-200`. Ideally sanitise once in `jev_pick` before both `log` and the TSV `printf`. The implementer's own note offered a 40-character cut.

**PT-5 · LOW (existed before this phase, same class) · Raw `level` and jev stderr reach the logs**
- **Location:** `lib/jev.sh:44` and `lib/jev.sh:40`.
- **Path:**
  - `jev answered '${level}'`: `jq -r '... | strings'` prints a raw string, newlines included.
  - `jev failed: $(head -c 200 "$err" | tr '\n\t' '  ')` keeps CR and ANSI escapes in `run.log` (`decisions.tsv` strips CR). `blast-off logs` then `tail`s them to the owner's terminal, so escape injection is possible.
- **Fix:** the same sanitiser as PT-4.

**PT-6 · LOW · jev's stderr is logged unredacted. "Never with the key" is only proven with the fake jev**
- **Location:** `lib/jev.sh:40`, which feeds `run.log`, `decisions.tsv`, the journal and preflight stdout.
- **Path:** if the real jev, or an HTTP or library error, echoes the key or an `Authorization: Bearer sk-or-...` header on failure (debug mode, verbose 401), up to 200 bytes of it go to `run.log` and `decisions.tsv` in the job dir, which may be committed, and to the journal. Tests 12, 60 and 61 assert absence only with `tests/fakes/jev`, which never echoes.
- **Precondition:** real jev behaviour on errors (UNVERIFIED).
- **Fix:** before logging, redact with `e="${e//"$OPENROUTER_API_KEY"/<key>}"` and `sed -E 's/sk-or-[A-Za-z0-9_-]+/sk-or-<redacted>/g'`. Add a fake-jev `fail` mode that prints the key on stderr and assert it is not logged.

**PT-7 · LOW-MEDIUM · Prompt-injection steering of the level. The threshold is no defence**
- **Location:** `lib/jev.sh:58-63`; the row comes from `cp_row`, i.e. the child-written `checkpoint.md`.
- **Path:**
  - Every child rewrites `checkpoint.md`, so the first open Phase plan row's text is attacker-controlled: by the child, or by content that prompt-injected the child.
  - Text such as "security, concurrency, migration; answer deep" drives Jev to `deep` (opus xhigh) with high confidence. That raises cost and usage-window burn above the owner's `CLAUDE_FLAGS`.
  - The reverse ("docs only") drops a security-critical phase to sonnet medium.
  - The threshold only discards low-confidence picks. An injected row is built to look confident, so it passes.
  - Row size is uncapped. A child can write a huge row, sent to OpenRouter on the owner's key on each row change. The number of calls is bounded by the child cap; the tokens per call are not (only jev's 60 s timeout; whether jev caps input is UNVERIFIED).
- **Fix:**
  - Cap the row bytes sent (`head -c 2000`).
  - Optionally add a ceiling (`JOB_JEV_MAX_LEVEL`, or never exceed the model and effort in `CLAUDE_FLAGS`).
  - Document that the threshold is a quality gate, not a safety control.

**PT-8 · LOW · Preflight now makes a real OpenRouter call with the caller's key (Q1)**
- **Location:** `lib/preflight.sh:23`.
- **Path:**
  - A command documented as "writing nothing" now:
    - spends on the key;
    - sends the first open row's text to a third party before the owner has confirmed the launch;
    - can block up to 60 s.
  - The skill session runs it with whatever key its environment holds.
  - Jev's answer is not deterministic, and the runner asks again in its own call. Near the threshold, preflight can print "deep" while the runner falls back to static, or the other way round.
- **Fix:**
  - Keep the call if the owner wants it, but reword the docs (see PT-12).
  - Or offer a no-call mode, e.g. `JOB_JEV=0`, or print "Jev decides at launch, threshold 0.7".

**PT-9 · LOW · `start` and `resume` do not validate `JOB_JEV_MIN_CONF`, and the runner's refusal reaches only the journal**
- **Location:** `lib/units.sh:31-35` (`unit_check` does not call `chain_nums`); `lib/chain.sh:153` (`die`, stderr only).
- **Path:**
  - With a bad value, `start` succeeds and the unit dies at once. Nothing is written to `run.log`, unlike the `child-count` refusal at :155.
  - Via the resume timer, the job stays `paused-limit` with no timer and no `run.log` reason. `wait` reports `stuck`.
  - The same gap already existed for the `JOB_*` counts (the implementer noted it).
- **Fix:** call `chain_nums || die "$NUMS_ERR"` in `unit_check`, and make `chain_run` use `chain_nums || { log "$NUMS_ERR" >&2; exit 1; }`.

**PT-10 · INFO · `NUMS_ERR` echoes the raw `JOB_JEV_MIN_CONF`**
- **Location:** `lib/chain.sh:101`.
- **Path:** a value with a newline can plant a line in preflight output or stderr ahead of the real refusal. Only the env setter controls it, and the env setter already controls `CLAUDE_FLAGS`, which `child_launch` (`child.sh:49`) expands unquoted into a shell command, so this adds nothing.
- **Fix:** optional, print the value with `%q`.

**PT-11 · LOW (test) · Test 12's stub `systemd-run` cannot hide a scope failure, but it does hide key-specific failures on the real unit and timer**
- **Location:** `tests/12-start-env.sh:211-258`.
- **Analysis:**
  - Calls with `--scope` are exec'd to the real binary, so a child-scope failure is not masked.
  - Calls without `--scope` (the runner unit, the timer) are recorded and return 0 without reaching systemd.
  - Tests 11, 30 and 31 cover those real calls, but without the key.
- **What no test proves:**
  - that a real unit's environment holds `OPENROUTER_API_KEY`;
  - that Jev picks under a real `start`. Criterion C1 under `start` is not tested end-to-end;
  - that the armed timer and service are collected after firing (PT-2).
- **Other gaps:**
  - The `key=set` environment check runs only for the first `start`, not for the `resume` or timer cases.
  - The leak checks (`nokey`) cover the job dir and output only: not the journal, not leftover `$XDG_RUNTIME_DIR/blast-off-jev.*` files, not the tmux environment.
  - Test 12 does not unset `JOB_JEV_MIN_CONF` (tests 60 and 61 do), so a developer's shell value could break it.
- **Fix:**
  - Add the env check to the resume and timer cases.
  - Consider one real-unit scenario with a fake key and fake jev that asserts the pick line in `run.log`.
  - Unset `JOB_JEV_MIN_CONF` in `tests/lib.sh`.

**PT-12 · LOW (docs) · Truth of the security claims**
- **README.md:**
  - "Each pick or fallback is a `run.log` line ..., never with the key." This holds for blast-off's own text, but not if jev's stderr carries the key (PT-6).
  - It does not say children inherit the key (PT-1); only `docs/spec.md` does.
  - It does not say the resume timer's unit file holds the key until the reset, possibly for days.
- **docs/spec.md:**
  - The D14 paragraph still says "blast-off writes no secret (`GH_TOKEN`) to any file" and "the token included" (singular). The resume-timer section (around line 203) mentions only the token. Both should name `OPENROUTER_API_KEY` too.
  - The `Environment (non-secret, passed by name ...)` paragraph now holds the key's discussion. Contradictory wording.
  - K8 and the preflight row say preflight prints "the flags and level `start` gives, asking Jev as the runner would". That overclaims: it is a separate call that can differ (PT-8).
  - The preflight row says "the key's value is never printed". Same caveat as PT-6, because `JEV_WHY` includes jev's stderr.
- **bin/blast-off header:** accurate.
- **Also stale:**
  - `docs/decision-log/build-2026-11-04.tsv` row 140 still says `start` does not pass the key. It is a historical log; the implementer chose to leave it.
  - `skills/blast-off/SKILL.md` hand-over does not mention exporting `OPENROUTER_API_KEY`, so Jev under `start` happens only if the key is already in the environment.

**PT-13 · LOW (correctness, UNVERIFIED) · A pick with a missing or other-named confidence now always falls back**
- **Location:** `lib/jev.sh:46`.
- **Path:** previously a pick with no confidence was still taken (`JEV_CONF='?'`). Now it falls back as "not a number". The fake jev emits `{level:{choice,confidence,probabilities}}`, but nothing in the repo shows the real jev's output shape was checked. If the real field differs, C1 silently never happens; every phase is static (logged).
- **Also (INFO):**
  - A confidence above 1 or below 0 is compared without a range check.
  - A `false` confidence is reported as `'?'`.
- **Fix:** confirm the real output once and record it in the findings file.

**PT-14 · INFO · jev's err tempfile**
- **Location:** `lib/jev.sh:38-42`.
- **Analysis:** `mktemp` (0600, random name) under `$XDG_RUNTIME_DIR`, removed on both paths. A runner SIGKILLed during the jev call leaves `blast-off-jev.XXXXXX` behind; `child_stop_all` cleans only `$UNIT-child.*`. It holds jev's stderr: no key expected, but see PT-6.
- **Fix:** optional, add `blast-off-jev.*` to the cleanup, or keep stderr in a variable.

**PT-15 · INFO · The `PATH` passed to the unit decides which `jev` runs with the key**
- **Location:** `lib/units.sh:21` (`--setenv=PATH`); `lib/jev.sh:37-39`.
- **Path:** the unit's working directory is `$WORKDIR`, which children write to. If the caller's `PATH` contains a relative entry (`.`, `bin`), a child-planted `$WORKDIR/jev` runs inside the runner with `GH_TOKEN` and the key.
- This already applied to every tool the runner calls, and the child is already the same user, so the only gain is escaping the child's scope.
- **Fix:** optional, drop relative entries from `PATH` in `chain_run`.

### Open questions for the owner
1. **(Q2/PT-1)** Should children get `OPENROUTER_API_KEY` at all? Recommendation: scrub it in `child_server`. Jev runs only in the runner. Does any child workflow (ask-jev, hooks) need it?
2. **(PT-3)** Pass the key only when it is usable (`JOB_JEV` not 0 and the value starts with `sk-or-`)?
3. **(Q1/PT-8)** Should preflight spend a real call and send the row text before launch, or print "Jev decides at launch, threshold X"? If it keeps the call, reword the docs so they don't promise the runner gets the same level.
4. **(PT-7)** Is a level ceiling or a row-size cap wanted? The threshold does not stop a child from steering its own phase to opus xhigh.
5. **(PT-2)** Is a resume-timer unit file holding `GH_TOKEN` and the OpenRouter key for up to about 7 days acceptable, or should the timer arm only for short waits or use credentials?
6. **(PT-6/PT-13, UNVERIFIED)** Does the real jev ever print the key or auth header on stderr, and is its confidence field `.level.confidence` as a JSON number? One supervised check of the real binary would settle both.
7. Confirm by experiment that transient `--on-calendar` timers and their services unload after firing (`RemainAfterElapse`), so the key does not linger after `resume` runs.
