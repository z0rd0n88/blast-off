# Review: phase 6 (issue 14, `blast-off wait`), round 2 (narrow)

Fix diff `git diff 174f873..d5e27e2 -- . ':!baton-runner'` (fixes for P6R1-1 HIGH and P6R1-2..-8, -10, -11), read
against the phase diff `git diff 62eeb5c...d5e27e2 -- . ':!baton-runner'`. Two static reviewers
(`review-phase-6-iter-2/{code-reviewer,silent-failure-hunter}.md`), a skill-sheriff audit of `SKILL.md`
(`review-phase-6-iter-2/skill-sheriff.md`), then the review unit checked the concrete claims: one probe of
`wait_logged` on crafted run.log files and one mutant run of 13-wait on a `git archive d5e27e2` copy.

## Executive summary

- Gate: `scripts/gate.sh` exit 0, last line `GATE: PASS passed=19 failed=0 shellcheck=ok`
  (`gate-phase-6-iter-2/tests-run.log`). ExecStart read the build worktree's line before and after the gate, after the
  mutant run and at the end.
- P6R1-1 is closed for the path round 1 found: a child's `status: done` no longer ends the watch while the runner checks
  receipts and CI. Both reviewers confirm an accepted done always ends run.log with the exact `job done` line in the
  runner's own path, and that `chain_exit` logs nothing after it.
- The anchor is weaker than the ruling's words. It takes run.log's last line that **starts with a timestamp**, not the
  last line **the runner wrote**. Child text that the runner copies raw into run.log can carry such a line (P6R2-1),
  and any later timestamped line hides a real end (P6R2-3). silent-failure-hunter rates P6R2-1 HIGH. The review unit
  rates it MEDIUM: it needs child text of an exact shape plus a poll in a short window (or the runner dying in it).
  It is owner question 1.
- New in this round: a read that never clears mid-watch (job dir deleted or moved, user bus gone) now retries
  forever with no output (P6R2-2). Round 1 exited 1 there.
- The `blocked` half of the ruling has no test that fails if it breaks. Reproduced: mutant "blocked is always final"
  PASSES 13-wait (P6R2-5).
- 0 CRITICAL, 0 HIGH, 5 MEDIUM, 14 LOW, plus 3 skill-sheriff Gaps (Recommended rules, all from before phase 6).

**VERDICT: CLEAN** (gate exit 0, no CRITICAL or HIGH, every issue-14 criterion has a passing test). CLEAN rests on
the review unit's MEDIUM for P6R2-1. If the owner takes silent-failure-hunter's HIGH, the verdict is ISSUES.

## Issue-14 criteria -> tests (all in `tests/13-wait.sh`, PASS in the gate)

| Criterion | Test (line) | Note |
|---|---|---|
| Returns on child launch | 62-64 (`ends c 11 'child 1'`) | |
| Returns on phase change | 70-72 (`ends p 11 'phase: 2 of 3 — build'`) | |
| Returns on done | 90-94 (blocks on an unlogged done with the unit up, then 0 once `job done` is logged); 96 (already done); 100 (refused done -> 12) | the ruling's done half |
| Returns on blocked | 101-103, already blocked at start and logged | no running -> blocked change (P6R1-27, open); a refused blocked is untested (P6R2-5) |
| Returns on paused | paused-cap 117-120 (12, with resume advice); paused-limit + timer 123-125 (11); no timer 127 (12); status-only change 131-133 (11) | |
| Returns when the unit goes inactive | 107-113 (`inactive`, `failed`); `activating` 137-139 is not stuck | `deactivating` as down untested (P6R2-8) |
| Missing job dir: non-zero with a reason | 155 (`no job dir <path>`), 159 (no argument) | at start only; mid-watch it retries forever (P6R2-2) |
| Machine sleep is not a change | 191-210 (10 h jumps, then `ends s 11`) | still kills only `date` clocks (P6R1-12, open) |
| Devil's advocate: unit gone, status running | 107-110 (stuck line says `blast-off status`) | fake systemctl only (P6R1-13, open) |

## Critical

None.

## High

None. (silent-failure-hunter filed P6R2-1 as HIGH; see P6R2-1 for why the review unit holds it at MEDIUM.)

## Medium

**P6R2-1. The anchor is run.log's last timestamped line, not the runner's: child text copied into run.log can end the watch `final`**
- Reported by: silent-failure-hunter HIGH-1 (HIGH), code-reviewer MEDIUM-2 (MEDIUM). Review unit: MEDIUM.
- Location: `lib/units.sh:145-152` (`wait_logged`: `grep -E '^<ts> ' run.log | tail -n 1`), `:108`; writers of child
  text: `lib/child.sh:106-120` (`child_report`: `last_assistant_message`, or a non-JSON payload's first 200
  characters, raw), `lib/child.sh:97-100` (`child_screen`: the pane); order `lib/chain.sh:212-230`; also
  `lib/chain.sh:75` (named uncommitted paths in one `log` line; a path holding a newline), per silent-failure-hunter.
- Failure path: a child writes `status: done`, then its last message (or its screen) holds a line like
  `2026-11-17T09:00:00Z job done`. `child_report` copies it into run.log. Until `log "child $n usage"` (after
  `child_stop`, a synchronous scope stop, and `usage_read`), that line is run.log's last timestamped line. A poll in
  that window prints `wait: final` and exits 0 before receipt and CI checks run. If the runner dies in the window
  (reboot, OOM, SIGKILL), the false final stays.
- Reproduced (review unit, `wait_logged` alone on crafted run.log files): a forged line inside a child's last-message
  block -> final (rc 0); the same file with the runner's `child 3 usage` line appended -> not final.
- Why MEDIUM, not HIGH: a benign child has no reason to write that exact line at column 0, and the window is short
  (one scope stop plus a `jq` read) against a 5 s poll. It is reachable by a prompt-injected or careless child (for
  instance one quoting an earlier run's run.log), the same surface round 1 rated MEDIUM in P6R1-7.
- Also: `wait_logged`'s comment ("a child cannot end the watch, unless the runner is killed between the two") is
  false; the window exists in normal operation. `phase-6/findings.md:51-52` and the fix notes record the same claim
  (P6R2-19).
- Fix (one of): prefix child text in run.log (for example `  | `) and flatten newlines in `log()`; or have the runner
  write its end to a separate file (`run.end`) and anchor on that; or also require the unit to be down before final.

**P6R2-2. A read that never clears mid-watch blocks forever with no output (regression from the P6R1-5 fix)**
- Reported by: code-reviewer MEDIUM-1, silent-failure-hunter MEDIUM-3.
- Location: `lib/units.sh:123` (`until wait_snap; do sleep "$p"; done`), `:131`, `:133-135`; docs `README.md:112`,
  `docs/spec.md:55`, SKILL.md step 8.
- Failure path: the job dir is deleted or moved, checkpoint.md is left empty, or the user bus goes for good (logout
  without linger). `wait_snap` fails every poll, `down` never moves (it is updated only after a good read), so neither
  `stuck` nor an error prints, and systemctl's stderr is dropped. Round 1 exited 1 here. P6R1-19 (a background
  command has no timeout) makes this an unbounded hang. The docs only say "retried".
- Confirmed by reading; not run.
- Fix: give up after N failed polls in a row (exit 1 with the last `WAIT_ERR`, or 12), document it, and test a job
  dir deleted mid-watch.

**P6R2-3. Any timestamped line after `job done`/`job blocked` turns an accepted end into a permanent `stuck` that reads as refused**
- Reported by: silent-failure-hunter MEDIUM-2 (MEDIUM), code-reviewer LOW-1 (LOW, part). Review unit: MEDIUM.
- Location: `lib/units.sh:148-152`; writers after the end: `blast-off receipt` (`lib/receipt.sh:12`, `:37`),
  `blast-off ci-wait` (`lib/ci.sh:27`, `:34`, `:45`), a child left running under `JOB_KEEP_WINDOWS`
  (`lib/chain.sh:17`, `lib/child.sh:143`).
- Failure path: the owner (or a kept child) runs `receipt` or `ci-wait` on a finished job. Its timestamped line is now
  the last, so every later `wait` reads `stuck · status: done; see blast-off status`, which README maps to a refused
  done.
- Reproduced (review unit, `wait_logged` alone): run.log `job done` then a later timestamped line -> not final.
- Fix: anchor on the last line that ends or starts a run, or on an end file the runner writes.

**P6R2-4. The two-poll stuck rule counts polls, not time: at a low poll value, or a slow resume, the timer handoff reads `stuck`**
- Reported by: silent-failure-hunter MEDIUM-4 (MEDIUM), code-reviewer LOW-4 (LOW). Review unit: MEDIUM.
- Location: `lib/units.sh:109-121`; `lib/units.sh:62-64` (resume waits up to 90 s for an old unit to read inactive).
- Failure path: the fired timer reads gone before the runner unit is up. At `BLAST_OFF_WAIT_POLL=0.1`, which the docs
  allow, `blast-off resume`'s own start-up takes longer than two polls, so a healthy resume returns 12. At the default
  5 s it needs a resume longer than one poll (an old runner still `deactivating`).
- Fix: count `$UNIT.resume.service` `active`/`activating` as scheduled, or require a minimum down time, not a poll
  count.

**P6R2-5. The `blocked` half of the ruling has no test that fails if it breaks**
- Reported by: code-reviewer MEDIUM-3; silent-failure-hunter LOW-13 (part).
- Location: `lib/units.sh:108`, `:121`, `:148-152`; `tests/13-wait.sh:101-103`.
- Reproduced (review unit, `git archive d5e27e2` copy): mutant "`blocked` is final whatever run.log says"
  (`case "$WAIT_STATUS" in blocked) echo "wait: final · $SNAP"; exit 0 ;; done) ...`) gives
  `PASS 13-wait` / `GATE-ONLY: PASS passed=1 failed=0 shellcheck=ok only=13-wait`. code-reviewer names two more
  survivors, statically: `blocked` dropped from the change hold at `:121`, and `done` accepting a `job blocked; see`
  line.
- It matters: the runner can refuse a child's `blocked` (receipt check exit 9 at `lib/chain.sh:189`, dirty tree exit 7).
- Fix: add an unlogged-`blocked` case that blocks while the unit is up and reads stuck once it is down, and a
  `done` + `job blocked; see` case that is not final.

## Low

| ID | Sev | Title | Location | Reported by | One line |
|---|---|---|---|---|---|
| P6R2-6 | LOW | TERM between `log "job done"` and `trap ''` leaves `runner stopped by signal` after the end | `lib/chain.sh:6`, `:16`, `:159` | silent-failure-hunter LOW-5, code-reviewer LOW-1 (part) | The TERM trap logs after the end line, so an accepted done reads stuck forever. Fix: ignore signals in `chain_end` before it logs. |
| P6R2-7 | LOW | A failed `tee` in `chain_end` drops the end line with no trace | `bin/blast-off:52`; `lib/chain.sh:6`, `:20` | silent-failure-hunter LOW-6 | ENOSPC or EPIPE exits under set -e with CHAIN_END already set, so nothing logs; an accepted done reads stuck. |
| P6R2-8 | LOW | `deactivating` counted as down is still untested | `lib/units.sh:111` | code-reviewer LOW-2 | P6R1-8 half done: only `activating` got a test. |
| P6R2-9 | LOW | README, spec, usage and SKILL describe 12 and the line in ways the code no longer matches | `README.md:99-113`; `docs/spec.md:55`; `bin/blast-off:12-14` | code-reviewer LOW-3, silent-failure-hunter LOW-7 | An unlogged `blocked` is held like `done` but docs name only done; a refused `blocked` is not among the stuck causes; stuck means "no end matching the status", not "no end"; run.log is missing from what wait reads; the status field can reach about 135 characters, not 80; every `·` is replaced, not only ` · `; the `resume` advice does not fit a refused done. |
| P6R2-10 | LOW | spec's 13-wait row says 12 comes "at once" on an already stuck job | `docs/spec.md:234` | silent-failure-hunter LOW-8 | 12 now comes one poll later. |
| P6R2-11 | LOW | SKILL step 8 says never rerun an exit 1 unchanged, but a transient read at start also exits 1 | SKILL.md step 8; `lib/units.sh:106`, `:131` | silent-failure-hunter LOW-9 | An empty-mid-rewrite checkpoint.md or a bus hiccup at start is fixed by an unchanged rerun; the message says "missing" for an empty file. |
| P6R2-12 | LOW | The stuck line for `done`/`blocked` gives no reason; run.log read errors are swallowed | `lib/units.sh:115-116`, `:151` | silent-failure-hunter LOW-10 | Refused, displaced (P6R2-3), deleted and unreadable run.log all print the same line. Fix: add the last runner line. |
| P6R2-13 | LOW | P6R1-17 made worse: an unlogged done/blocked plus a leftover waiting resume timer blocks until the timer fires | `lib/units.sh:108-121`, `:35-46`, `:67` | silent-failure-hunter LOW-11 | The hold hides every change while the timer is active, which can be days for a seven_day reset. |
| P6R2-14 | LOW | The P6R1-7 cleaning leaves lookalike separators and Unicode format characters | `lib/units.sh:142-143` | silent-failure-hunter LOW-12 | `⋅ ‧ ・ •`, bidi and zero-width characters can still forge fields; a C locale can split a multibyte character at 80. |
| P6R2-15 | LOW | 13-wait does not cover the new failure modes | `tests/13-wait.sh:88-102`, `:179-187` | silent-failure-hunter LOW-13 | No test for a forged timestamped `job done`, a line after `job done`, a failure that never clears, or a gap longer than two polls. |
| P6R2-16 | LOW | A change past character 80, or after the status word, is not a change | `lib/units.sh:137`, `:143` | silent-failure-hunter LOW-14 | The fixer noted it. Fix: compare a hash of the full phase line. |
| P6R2-17 | LOW | At-start error messages guess the cause and drop the real error | `lib/units.sh:131`, `:133-135` | silent-failure-hunter LOW-15 | An unreadable or empty file reads "missing"; any systemctl failure reads "no user bus?". |
| P6R2-18 | LOW | `BLAST_OFF_WAIT_POLL=.5` (and `1.`) is refused though within 0.1 to 3600 | `lib/units.sh:104-105` | silent-failure-hunter LOW-16; code-reviewer (noted, not filed) | The regex wants a digit before and after the point. |
| P6R2-19 | LOW | The fix notes and `phase-6/findings.md:51` record the false anchor claim as a decision | `baton-runner/br-1115-issues/phase-6/findings.md:51-52`; `baton-phase-6-fix-1.md` | code-reviewer LOW-5 | Same claim as `wait_logged`'s comment (P6R2-1). |

## Skill-sheriff (`skills/blast-off/SKILL.md`)

`review-phase-6-iter-2/skill-sheriff.md`. Docs fetched 2026-11-18 (platform overview and best practices, Claude Code
skills page); `sheriff.py quotes` verified all 57 quotes. Summary: 0 Fail, 3 Gap, 43 Pass, 4 N/A, 3 Can't verify (of
53 rows). No verdict changed since the phase-3 audit; none of the three Gaps comes from phase 6.

| ID | Kind | Rule | Evidence | Fix |
|---|---|---|---|---|
| P6R2-S1 | Gap (Recommended on Claude Code; Required on the platform) | Description says what the skill does and when to use it | `SKILL.md:3` is one when-clause | Put a what-clause first: "Writes a blast-off job dir (brief.md and checkpoint.md), runs preflight and hands the owner the start line. Use when ..." |
| P6R2-S2 | Gap (Recommended) | Table of contents in reference files over 100 lines | `README.md` 182 lines, `templates/brief.md` 192 lines, no contents list; sent there by `SKILL.md:13-14`, `:76` | Add a contents list, or name the exact README sections in `SKILL.md` |
| P6R2-S3 | Gap (Recommended) | At least three evaluations; with/without-skill baseline | skill folder holds only `SKILL.md` | Three scenarios: brief-only request, run request with hand-over and `wait`, a quick edit that must not trigger it |

Borderline N/A the auditor flagged: `disable-model-invocation` (the workflow creates a worktree; arguable as a Gap).

## Round-1 findings left open, not re-filed

P6R1-9, -12, -13, -14 and the LOWs P6R1-15..-35 stay as round 1 filed them. Made worse by this fix: P6R1-17
(P6R2-13), P6R1-19 (P6R2-2). Half fixed: P6R1-8 (P6R2-8).

## Open owner questions

1. P6R2-1: HIGH (silent-failure-hunter) or MEDIUM (review unit)? If it must close now: prefix child text in run.log
   and flatten newlines in `log()`, write the end to a separate file, or also require the unit to be down before final?
2. P6R2-3: may `receipt` or `ci-wait` run after `job done` turn a finished job into stuck? If not, anchor on the last
   end-or-start line, or on an end file?
3. P6R2-2: bound the mid-watch retry (after how many polls, exit 1 or 12), or keep it unbounded and document it?
   Should a failed read count toward `down`?
4. P6R2-4: read the resume service's state (a third `systemctl show` per poll), use a minimum down time, or raise the
   poll floor?
5. P6R2-6/-7: should `chain_end` ignore signals before logging and write the file before stdout?

## Notes and deviations

- Gate run once, alone, before any reviewer.
- Review unit's own runs, one at a time: one bash probe of `wait_logged` (extracted from `lib/units.sh`) on three
  crafted run.log files; one `BLAST_OFF_TEST_ONLY=13-wait tests/run` on a `git archive d5e27e2` copy with the
  blocked mutant. ExecStart checked after it: unchanged. Both copies were under the session scratchpad and deleted.
- The skill-sheriff audit ran in a subagent. The harness refused that subagent's report-file write, so it piped its
  quotes to `sheriff.py quotes <workdir> -` (exit 0, 57 verified) and returned the text, which this unit saved; `sheriff.py quotes` on the saved file: 57 verified, 0 failed, exit 0. The
  auditor also ran one read-only `git log -3` against its "no git ops" brief; nothing depends on it.
- The advisor was rate-limited; no second read of this synthesis.
- No tracked file changed, no git operation, `STATE.md` and `log.md` untouched.
