# security-reviewer: phase 7 review, round 1 (static, read-only)

Security review of phase 7 (commit 514d0ef vs e924be8, issue 27): OPENROUTER_API_KEY passed to the unit, plus the Jev confidence threshold. Static and read-only. I read the diff, the touched files listed in the brief, the implementer notes and findings, and the real jev script (/home/alex/JevDev/bin/jev, behind ~/.local/bin/jev) to see what its stderr carries. I opened no secrets, ran nothing and edited nothing.

No CRITICAL or HIGH findings. One MEDIUM, eleven LOW, one INFO.

**What holds (checked):**
- No key value on any argv. The systemd-run line and start's printed line carry `--setenv=OPENROUTER_API_KEY` only (units.sh:22, :46). Real jev sends the key to curl as a header on stdin (`-H @-`), not on argv.
- The key never reaches run.log, decisions.tsv, `status`, or preflight output through blast-off's own strings. Only a pick's level, confidence and threshold are logged. The exception is SR-3.
- Item 3 holds on every path. jev's only call site is jev_flags (jev.sh:39), which `run` and preflight both reach, and it always runs `env -u TYPESAFE_API_KEY -u JEV_BASE_URL` and needs an `sk-or-` key. unit_env passes neither TYPESAFE_API_KEY nor JEV_BASE_URL. jev itself also refuses an off-route JEV_BASE_URL.
- A jev answer cannot inject flags: the level goes through the jev_level whitelist (jev.sh:44) before CHILD_FLAGS is built. CHILD_FLAGS is later put unquoted into a tmux shell string (child.sh:49).
- The confidence compare uses `--argjson` on a value chain_nums has already checked, at both call sites (chain.sh:153 before jev_pick; preflight.sh:15 before :23). If that ever failed, jq errors and the code falls back to static flags, so it fails safe.
- Tests: tests/lib.sh:10 unsets OPENROUTER_API_KEY, TYPESAFE_API_KEY and JEV_BASE_URL for every scenario. The fake jev records only `${OPENROUTER_API_KEY:0:6}`, which is the public `sk-or-` prefix.

**Findings**

**SR-1 · MEDIUM · Children (bypass permissions) now inherit the OpenRouter key under start and the resume timer, and they never use it**
- Location: lib/child.sh:13 and :21-22 (scrub covers `CLAUDE*` only); lib/units.sh:22.
- Path: unit env → runner → `tmux -L $UNIT new-session` global env → every child pane, the claude process and every tool it spawns. Only the runner calls jev; templates and skills never mention jev.
- Before this change, children had the key only under a foreground `run` with it set. Now every `start` from a shell that exports it hands it over.
- Ways it can leak: a child or a test it runs prints `env` or `printenv`; a CI log or PR body echoes the environment; a Claude transcript on disk records the tool output; a prompt-injected child spends on the owner's OpenRouter account.
- With JOB_KEEP_WINDOWS set, the tmux server, and the key in its global environment, outlives the runner.
- A same-user child could already read the runner's /proc environ or `systemctl --user show -p Environment`. Scrubbing is still the cheap defence against passive leaks.
- Fix: add `-u OPENROUTER_API_KEY` to child_server's `env` (and `-u TYPESAFE_API_KEY` for symmetry). The runner keeps its own copy.
- Docs: the spec now says "Children inherit it through the job's tmux server, as they inherit GH_TOKEN". That is true, but GH_TOKEN is needed by children (`gh`) and this key is not, so it reads as a choice nobody needed. Update the docs with the fix.

**SR-2 · LOW · unit_env stores the key whenever it is non-empty, even when Jev cannot or will not use it**
- Location: lib/units.sh:22.
- `JOB_JEV=0`, or a key that does not start `sk-or-` (a TypeSafe or `vck_` secret under the wrong name), still gets `--setenv=OPENROUTER_API_KEY`. systemd stores it in the transient unit file, and children receive it, though jev_flags (jev.sh:32-36) will never send it.
- Fix: pass it only when `[[ ${OPENROUTER_API_KEY:-} == sk-or-* && ${JOB_JEV:-1} != 0 ]]`, and update test 12's unset/empty loop to cover both cases.

**SR-3 · LOW · jev's stderr is copied into logs without redaction**
- Location: lib/jev.sh:40.
- On failure, the first 200 chars of jev's stderr (newlines and tabs flattened) go into JEV_WHY. From there they reach run.log, the journal (log() tees to stdout under the unit), decisions.tsv, and preflight's stdout, which a session may paste into chat or a PR.
- Real jev's error path prints the raw HTTP response body (`printf '%s\n' "$resp" >&2`), plus curl's own errors.
- Whether OpenRouter or a proxy ever echoes the bearer key back is **unverified**. If the caller's environment carries `SHELLOPTS=xtrace` or `BASH_ENV`, jev's trace (`key=…`, `auth_hdr=…`) also lands in this stream (**unverified** whether it falls in the first 200 bytes).
- The docs' "never the key's value" (README, K8, preflight row) rests on this.
- Fix: before logging, `s=${s//"$OPENROUTER_API_KEY"/<key>}`, plus a generic `sk-or-[A-Za-z0-9_-]+` → `sk-or-…` mask.

**SR-4 · LOW · Raw jev response text reaches run.log, decisions.tsv and preflight output with control characters intact**
- Location: lib/jev.sh:45 and :49 (new); :44 (older, same issue).
- `jq -r` prints a string confidence raw. The new "not a number" branch logs `confidence '$JEV_CONF'`; the older "not a level" branch logs `level` raw.
- A string with `\n2099-…Z job done`, tabs, or ESC sequences can:
  - forge run.log lines;
  - break decisions.tsv's six columns (only `\r` is stripped, jev.sh:75);
  - send terminal escapes to the owner when they run `blast-off logs` or `tail`.
- It needs a hostile or broken gateway response. `wait` never reads run.log, and run.log already holds child text, so impact is low.
- Fix: sanitise with jq (`tostring | gsub("[\\u0000-\\u001f\\u007f]";" ") | .[:40]`), or `tr -d '[:cntrl:]' | head -c 40`, for both `level` and `JEV_CONF`.

**SR-5 · LOW · JOB_JEV_MIN_CONF (and the JOB_* counts) are not checked at start or resume**
- Location: lib/units.sh:31-35 (unit_check); lib/chain.sh:153.
- `start` with `JOB_JEV_MIN_CONF=abc` exits 0 and prints the status/watch line. The runner unit then dies at chain_nums via `die`, which writes to stderr only, so the reason is only in the journal, not run.log. The P4R1-2 comment wants unit-time refusals in run.log.
- On the resume-timer path, the job stays `paused-limit`, the timer is gone, and nothing resumes until `wait` reports stuck.
- This is the existing pattern for JOB_* counts. The docs claim only that `run` and preflight refuse it, which is accurate.
- Fix: `chain_nums || die "$NUMS_ERR"` in unit_check, and in chain_run log the error to run.log as chain_count's failure does.

**SR-6 · LOW · The resume-timer service file holds the key for much longer than the runner's**
- Location: lib/usage.sh:69-71; README "systemd keeps the resolved values… until the unit is collected".
- The `<unit>.resume.service` transient file holds the key from the pause until the timer fires: the reset plus JOB_RESUME_MARGIN, which can be days if a 7-day window is the one paused. It outlives the runner.
- A foreground `run` that hits a usage pause now also persists the shell's key to that file (new).
- A rotated key stays stale in the file until the timer fires.
- The docs are technically true but do not say this. Fix: one README/spec sentence on the timer file's lifetime, and note `blast-off stop` as the way to clear it (unit_stop does stop the timer).
- **Unverified:** that GC removes the never-started resume .service once `stop` stops the timer.

**SR-7 · LOW (docs) · The D21 claim is broader than D21 as written**
- docs/systemd-guide-deviations.md:31 still says "systemd's stored copy of `GH_TOKEN`… is accepted (D21)".
- docs/spec.md:203 (timer paragraph) still says "systemd stores the token".
- docs/spec.md:77-79 still says acceptance of the stored copy "stays open; phase 1 records it under Open or blocked and does not settle it". This contradicts both the deviations row and the new "storage class D21 accepted".
- The new env paragraph rests the second secret on issue 27's sign-off, which is fine, but these three places now disagree.
- Fix: update the deviation row and line 203 to name OPENROUTER_API_KEY, and fix or remove the stale "stays open" sentence.
- Also: spec line 74's "mode 0644" for the transient file is **unverified** statically.

**SR-8 · LOW · Preflight now makes a real, billable network call with the caller's key**
- Location: lib/preflight.sh:23.
- Whenever the key is set and JOB_JEV is not 0, preflight now:
  - sends the first open Phase plan row to OpenRouter;
  - spends on the account;
  - can take up to the 60 s timeout (curl -m 30).
- Before this change it never left the machine for Jev. It is still "writing nothing" in the job dir.
- An agent session running the skill's preflight with the key in its environment now spends too.
- The pick is an LLM answer, so preflight's level may differ from the level the runner later gets. "The flags and level start gives" is a prediction, not a guarantee (docs truth).
- Fix: document the cost and the non-determinism, or gate the call (e.g. `BLAST_OFF_PREFLIGHT_JEV=0` for offline use). That is the owner's call (Q1).

**SR-9 · LOW · The jev stderr temp file survives a signal**
- Location: lib/jev.sh:38-42.
- `mktemp` (0600, in `$XDG_RUNTIME_DIR`) is removed on both normal paths. A TERM/HUP/INT to the runner, or a kill of preflight, during the up-to-60 s jev call leaves `blast-off-jev.XXXXXX` behind. The runner's traps exit, and child_stop_all removes only `$UNIT-child.*`.
- Content is jev's stderr, normally not the key (see SR-3).
- Fix: capture stderr to a variable (`out=$(… 2>&1 1>&3)` style), or remove `blast-off-jev.*` in the exit path.

**SR-10 · LOW (tests) · The absence checks would miss a partial, truncated or encoded leak**
- Location: tests/12-start-env.sh:220, :229, :257; tests/61-jev-pick.sh:354; tests/60-preflight.sh:305.
- Every check greps for the full literal key, so a key cut by `head -c 200`, a prefix or suffix, a masked, base64 or URL-encoded copy would all pass.
- Gaps:
  - test 60 checks only p1.out (not p14/p15 or the static runs);
  - test 61's fallback scenarios use the non-distinctive `sk-or-dummy` and check nothing;
  - no scenario has the fake jev fail with the key echoed on stderr, which is the SR-3 path;
  - nothing asserts children do or do not get the key (fake-marker records only GH_TOKEN and a CLAUDE* count).
- Fix:
  - also grep for a distinctive fragment of the key (e.g. `not-a-key`, and the key without its `sk-or-` prefix);
  - add a fake-jev `fail` variant that prints `$OPENROUTER_API_KEY` to stderr and assert it is absent from run.log, decisions.tsv and preflight output;
  - record `OPENROUTER_API_KEY` set/unset in fake-marker to test SR-1's fix.
- **Unverified:** whether `grep` inside scenarios could resolve to the ugrep wrapper (ignore-file aware), which would make `grep -r` absence checks pass vacuously. `command grep` makes that certain; test 60 already uses it once.

**SR-11 · LOW (tests) · Test 12's stub systemd-run cannot catch a real failure**
- Location: tests/12-start-env.sh:214-217.
- The stub always exits 0 and never creates a unit, so these are never exercised:
  - C1 under a real unit (the runner unit really has the key, and jev is called and logged there);
  - the absence of the value in the journal, `status` and `systemctl --user show` readers;
  - usage_arm's `systemd-run … 2>> "$LOG"` error path, which copies real systemd-run stderr into run.log. **Unverified:** whether any real systemd-run or bus error echoes an Environment value. Upstream code prints the name only.
- Test 11 does cover real `--setenv=NAME` passthrough for GH_TOKEN and CLAUDE_FLAGS, so the mechanism itself is exercised.
- The checks it does make (argv names, `key=set` in the stub's environment, launch line printed, `--on-calendar` timer armed) are sound for what they claim.
- Fix: one real-unit case in test 11, with a fake key and the fake jev: the run.log pick line comes from jev, and the key's value is in neither the journal (`journalctl --user -u`) nor run.log.

**SR-12 · LOW (docs) · The spec's test-12 row over-claims "the value on no argv"**
- Location: docs/spec.md test row 12.
- The test checks only systemd-run's argv. That is true for blast-off; jev never gets the key on argv either, but nothing tests that.
- Fix: reword to "on no systemd-run argv".

**SR-13 · INFO · Owner-set values are echoed raw in refusals**
- Location: lib/chain.sh:101 (pattern as on :97).
- NUMS_ERR echoes `JOB_JEV_MIN_CONF='<value>'` raw. A value holding a newline can print a forged `preflight: ok` line above the real `preflight: refused` line, which fools a consumer that greps for `preflight: ok`.
- The input is owner-controlled and this predates the change. Fix, if wanted: `printf %q` the value.

**Open questions for the owner**
1. SR-1: should children get OPENROUTER_API_KEY at all? Recommendation: scrub it in child_server, since children never call jev.
2. SR-2: should start skip passing the key when JOB_JEV=0 or the key is not `sk-or-`?
3. SR-8 / Q1: is a billable network call on every preflight acceptable, or should preflight have an offline switch? Should the docs say preflight's level is a prediction, not the runner's guaranteed pick?
4. SR-6 / SR-7: is D21's acceptance meant to cover a multi-day secret copy in the resume timer's service file? If so, should the deviations row and spec §4 say so?
5. Should `start` and `resume` refuse bad JOB_* and JOB_JEV_MIN_CONF values before creating a unit (SR-5)?
