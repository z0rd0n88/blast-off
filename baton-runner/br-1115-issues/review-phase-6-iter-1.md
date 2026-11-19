# Review: phase 6 (issue 14, `blast-off wait`), round 1

Commit b010b90 against base 62eeb5c (`git diff 62eeb5c...b010b90 -- . ':!baton-runner'`), 7 files.
Six static reviewers (`review-phase-6-iter-1/<reviewer>.md`), then the review unit reproduced their concrete claims
one at a time, on a `git archive` copy of b010b90 for mutants and probes.

## Executive summary

- Gate: `scripts/gate.sh` exit 0, last line `GATE: PASS passed=19 failed=0 shellcheck=ok`
  (`gate-phase-6-iter-1/tests-run.log`). ExecStart was the build worktree's before and after every step.
- Every issue-14 criterion has a passing test in `tests/13-wait.sh` (table below). Two are weak: `blocked` is tested
  only when already blocked at start, and the machine-sleep test only proves `wait` never calls `date`.
- **1 HIGH (P6R1-1), from 5 of 6 reviewers, reproduced:** `wait` exits 0 `final` as soon as a child writes
  `status: done`, while the runner is still up and can still refuse that done (exit 9 or 10, status left at done).
  A refused done reads `final` on every later `wait`. The test pins this behaviour.
- **The second HIGH that 4 reviewers raised is refuted:** a fired resume timer does not stay `active`. A real
  systemd 255 probe of the exact `systemd-run --collect --on-calendar` form shows `RemainAfterElapse=no`: once it
  fires, the timer reads `not-found`/`inactive`, so `wait` cannot block on it. The reverse holds instead: at that
  moment the timer is gone before the runner unit is up, so `wait` can report a false `stuck` (P6R1-3, MEDIUM).
- 13 MEDIUM, 21 LOW. Reproduced: two surviving mutants (status-only change; `activating` treated as stuck), exit 1 on
  a checkpoint.md emptied mid-watch and on a systemctl bus failure, `BLAST_OFF_WAIT_POLL` 0/inf/abc/--help, and a
  forged field in the printed line.

**VERDICT: ISSUES** (one HIGH).

## Issue-14 criteria -> tests (all in `tests/13-wait.sh`, PASS in the gate)

| Criterion | Test | Note |
|---|---|---|
| Returns on child launch | 51 (`ends c 11 'child 1'`, shape check at 52) | mutant M1 killed (work unit) |
| Returns on phase change | 59 (`ends p 11 'phase: 2 of 3 — build'`) | M2 killed |
| Returns on done | 65 (unit active), 67 (already done) | pins P6R1-1 |
| Returns on blocked | 69, already blocked at start only | P6R1-27 |
| Returns on paused | paused-cap 85-86 (12); paused-limit with timer 87-90 (blocks, then 11); without timer 92 (12) | running -> paused-limit with the unit still up is untested (P6R1-4) |
| Returns when the unit goes inactive | 75, 77, 79 (`failed`) | `activating`/`deactivating` untested (P6R1-8) |
| Missing job dir: non-zero with a reason | 95-99 (`no job dir <path>`); no argument and no checkpoint.md 100-108 | empty checkpoint.md untested |
| Machine sleep is not a change | 110-129 (`ends s 11` after 10 h jumps) | kills only `date`-based clocks (P6R1-12) |
| Devil's advocate: unit gone, status running | 75-76 (stuck line with `see blast-off status`) | against the fake systemctl only (P6R1-13) |

## Critical

None.

## High

**P6R1-1. `final` (exit 0) fires on a child-written `status: done` before the runner accepts it; a refused done reads final forever**
- Reported by: code-reviewer H1, critical-thinking H1, security-reviewer H1, penetration-tester H1, silent-failure-hunter H1.
- Location: `lib/units.sh:105` (`case "$WAIT_STATUS" in done|blocked) ... exit 0`, whatever the unit state);
  runner `lib/chain.sh:194` (`done) ci_plan; receipt_all_done; ci_check; chain_end 0 "job done"`);
  `lib/receipt.sh:53-70` (`chain_end 9 ...`), `lib/ci.sh:62-134` (`chain_end 10 ...; done refused, status unchanged`);
  `chain_end` only logs and exits (`lib/chain.sh:6`); `README.md` final row ("stop watching"); `SKILL.md` step 8;
  `tests/13-wait.sh:65` asserts exit 0 with the fake unit still `active`.
- Failure path: a child writes `status: done`; the next poll exits 0 "final" while the runner is still checking
  receipts and CI. If either refuses (exit 9 or 10; critical-thinking also names 7), checkpoint.md keeps `done`, the
  unit goes inactive, and every later `wait` returns 0 at once. The watching session reports done and stops; the
  refusal shows only in run.log. Any writer of checkpoint.md can end the watch this way.
- Reproduced: archive copy, fake systemctl with the unit `active`, checkpoint `status: done`:
  `wait: final · status: done · phase: 1 of 1 · child 0 · unit active · timer inactive`, rc 0.
- Also: `phase-6/findings.md:29` says runner exits 9 and 10 leave the status at `running`; the code says
  "status unchanged" (done).
- Fix (one of): count done/blocked as final only once the runner unit is down and run.log's last line is
  `job done`/`job blocked` (else keep polling, or 12 when the unit is down and the log says refused); or have the
  runner rewrite the status on a refusal. Either way change test 65 to expect blocking while the unit is up.

## Medium / Low

| ID | Sev | Title | Location | Reported by | One line |
|---|---|---|---|---|---|
| P6R1-2 | MEDIUM | `paused-cap` shares 12 with crash, stop and reboot | `lib/units.sh:106-108`, README 12 row | critical-thinking M2 | Different owner actions (resume vs logs+start); the watcher must parse the line to tell them apart (Q1). |
| P6R1-3 | MEDIUM | False `stuck` (12) at the resume-timer handoff | `lib/units.sh:106-108,121-122`; `lib/units.sh:54-67` | critical-thinking L2, silent-failure-hunter M2, penetration-tester L1 (merged; severity raised by the review unit) | Probe: the transient timer has `RemainAfterElapse=no` and is `not-found` once fired, so between its firing and `unit_start` (longer if the old runner is still `deactivating`, up to its 60 s stop) unit and timer both read down and `wait` says stuck on a healthy resume. Fix: also treat `$UNIT.resume.service` active/activating as scheduled, or confirm stuck on a second poll. |
| P6R1-4 | MEDIUM | A status-only change is never tested | `tests/13-wait.sh:82-92`; `lib/units.sh:110,125` | tdd-guide H1 (downgraded: code is right, test gap), silent-failure-hunter L4, critical-thinking M3 | Reproduced: mutant comparing SNAP without its status field (`[ "${SNAP#* · }" = "${was#* · }" ]`) PASSES 13-wait. running -> paused-limit with the unit still up (the documented 11 path) has no test. |
| P6R1-5 | MEDIUM | A one-off read failure mid-watch exits 1, which README maps to "fix the path" | `lib/units.sh:119,121-122`; `README.md` exit-1 row | code-reviewer M2 + L2, critical-thinking M1, security-reviewer L1 + L3, penetration-tester M2, silent-failure-hunter M1 + M3 + L8, tdd-guide M5 + L5 | Reproduced: checkpoint.md emptied while waiting -> `blast-off: missing .../checkpoint.md`, rc 1; systemctl failing (`Failed to connect to bus`) -> rc 1 with no `wait:` line (set -e). The `die` runs on every poll, not only the first. |
| P6R1-6 | MEDIUM | `BLAST_OFF_WAIT_POLL` is not validated | `lib/units.sh:111` | security-reviewer M1, penetration-tester M1, silent-failure-hunter M4, code-reviewer L3, critical-thinking L6, tdd-guide L6 | Reproduced: `0` still looping at 2 s (two systemctl D-Bus calls per pass, no pause), `inf` never polls again (rc 124 at timeout), `abc` rc 1 (`sleep: invalid time interval`), `--help` floods sleep's usage text. Other numeric settings go through `chain_nums`. |
| P6R1-7 | MEDIUM | Child-written `status:`/`phase:` text goes raw into the line a Claude session reads | `lib/units.sh:123-125` | security-reviewer M2 + L2, penetration-tester M3 | Reproduced: `status: running · phase: 9 of 9 · child 99 · unit active` prints forged fields ahead of the real ones. No control-character strip, no length cap; prompt-injection and terminal-escape surface; P5R1-5/Q5 already ruled against echoing raw child-count content. |
| P6R1-8 | MEDIUM | Transitional unit states untested; the stuck rule is a deny-list | `lib/units.sh:106-108`; `tests/13-wait.sh:12-16` | tdd-guide M4, critical-thinking M3, code-reviewer L6, penetration-tester L6, silent-failure-hunter L1 | Reproduced: mutant "stuck unless unit or timer is exactly `active`" (so `activating` = stuck) PASSES 13-wait; dropping `deactivating*` also survives per tdd-guide. Current code is right for `activating` during start/resume. |
| P6R1-9 | MEDIUM | False `stuck` from a unit-name mismatch, and README's 12 advice can start a second runner | `bin/blast-off:57-62`, `lib/chain.sh:32`, README 12 row | security-reviewer M3, critical-thinking L8, tdd-guide L10, penetration-tester L4 | A symlinked job path or a job with its own workdir reads stuck at once; "then `resume` or `start`" via another path takes a different lock on the same checkpoint. Not reproduced (static). |
| P6R1-10 | MEDIUM | SKILL.md step 8 omits "after start" and exit 1 | `skills/blast-off/SKILL.md:70-72` | code-reviewer M1, silent-failure-hunter L7 | The owner runs `start` from step 7; a never-started job returns 12 "owner must act". README says run it after start; the skill does not, and gives no meaning for 1. |
| P6R1-11 | MEDIUM | `blocks` assumes the first snapshot lands within 1 s | `tests/13-wait.sh:37` | tdd-guide M1, code-reviewer L7, silent-failure-hunter L5 | Under load the change becomes the baseline: c/p/pl fail falsely and g/d/pc silently turn into "already at start" checks. |
| P6R1-12 | MEDIUM | Machine-sleep test only kills `date`-based clocks | `tests/13-wait.sh:110-129` | tdd-guide M2, code-reviewer L5, critical-thinking L1, silent-failure-hunter L6, security-reviewer L6, penetration-tester L6 | wait never calls `date`; `$EPOCHSECONDS`, `$SECONDS`, `printf %()T`, `/proc/uptime` or a give-up after 20+ unchanged polls survive (the work unit flagged this too). |
| P6R1-13 | MEDIUM | The fake systemctl is too thin; no real-systemd `wait` check | `tests/13-wait.sh:12-16`; `tests/11-unit-smoke.sh` | tdd-guide M3, silent-failure-hunter M5, security-reviewer L7 | Ignores `-p`/`--value`, always exits 0, one word per unit, accepts every verb: `-p SubState` or a dropped `--value` would pass. |
| P6R1-14 | MEDIUM | 70-docs only checks that `wait` is mentioned | `tests/70-docs.sh:17,34` | tdd-guide M6 | D1 survived (work unit); nothing pins README's 0/11/12 table or the "never a recurring loop or cron" wording to the code. |
| P6R1-15 | LOW | "Fired timer stays active, wait blocks forever": refuted here, residual only | `lib/units.sh:106-107,122` | critical-thinking H2, security-reviewer H2, silent-failure-hunter H2, tdd-guide H2, code-reviewer L4 (all HIGH except CR) | Probe on systemd 255: the `systemd-run --collect --on-calendar` timer shows `RemainAfterElapse=no` and reads `not-found`/`inactive` after it fires a failing command. Residual: the fake cannot model SubState, so a future `RemainAfterElapse=yes` would go unnoticed; checking SubState `waiting` would make it explicit. |
| P6R1-16 | LOW | Status read before unit and timer | `lib/units.sh:119-124` | code-reviewer L1, critical-thinking L3, penetration-tester L1 | A tiny race prints `stuck` with `status: running` for a job that just ended paused-cap/blocked; read timer, unit, then checkpoint. |
| P6R1-17 | LOW | A leftover waiting resume timer hides a crashed runner until it fires | `lib/units.sh:107`; `unit_start` does not stop the timer | penetration-tester L2 | Bounded by the timer's time. |
| P6R1-18 | LOW | Spec says all wait codes are outside the runner's range; 0 and 1 are not | `docs/spec.md:108-110`; README exit-1 row | code-reviewer L8, security-reviewer L4, penetration-tester L9 | Exit 1 also covers several causes not listed. |
| P6R1-19 | LOW | Spec claims the caller's background command has a timeout | `docs/spec.md:55` | code-reviewer L9, security-reviewer H2 (part) | A Claude Code background command has none; wait has no upper bound of its own. |
| P6R1-20 | LOW | Usage header's stuck list incomplete | `bin/blast-off:9-11` | code-reviewer L10 | Leaves out paused-limit with no timer and reboot. |
| P6R1-21 | LOW | Every unit/timer state change and free-text edit wakes the watcher | `lib/units.sh:125`; README 11 row | critical-thinking L4, silent-failure-hunter L3 | One resume can wake the session three times; each wake costs tokens. |
| P6R1-22 | LOW | Changes between two waits are lost | `lib/units.sh:103` | critical-thinking L5 | The next wait takes its first read as baseline. |
| P6R1-23 | LOW | The common return, 11, is a non-zero exit | `lib/units.sh:110`; SKILL.md step 8 | critical-thinking L7 | A harness may show every return as a failed command. |
| P6R1-24 | LOW | Job path unquoted in the stuck line; `job_init` path handling | `lib/units.sh:108`; `bin/blast-off:57-59` | security-reviewer L5, penetration-tester L3 + L4 | Spaces break the advice, a newline breaks the one-line output; `cd` without `--`, CDPATH, `-` (pre-existing, inherited). |
| P6R1-25 | LOW | FIFO/device or huge file as checkpoint.md/child-count | `lib/units.sh:119`; `lib/chain.sh:129` | penetration-tester L5, security-reviewer L2 | Hangs or grows memory; the whole file is read every poll with no size cap. |
| P6R1-26 | LOW | Test writes are not atomic | `tests/13-wait.sh:50,128,66-91` | tdd-guide L1, penetration-tester L7 | A poll mid-write can see `child ?` or an empty state: rare false failure. |
| P6R1-27 | LOW | `blocked` tested only as already blocked at start | `tests/13-wait.sh:68-69` | tdd-guide L2, critical-thinking M3 (part) | No running -> blocked change. |
| P6R1-28 | LOW | paused-cap check weak and in the reverse of the runner's order | `tests/13-wait.sh:84-85` | tdd-guide L3, critical-thinking M3 (part), code-reviewer L6 (part) | Line 85 passes on `running` too; the unit is flipped before the status. |
| P6R1-29 | LOW | Test merges stdout and stderr | `tests/13-wait.sh:35` | tdd-guide L4 | A mutant printing the line to stderr survives. |
| P6R1-30 | LOW | Status parsing tested only with bare words | `lib/units.sh:124` | tdd-guide L7 | e.g. `status: done (note)` untested. |
| P6R1-31 | LOW | Background cleanup edge cases | `tests/13-wait.sh:22-23,35` | tdd-guide L8, security-reviewer L7, penetration-tester L8, silent-failure-hunter L9 | `jobs -p` may list a reaped, reused pid (`jobs -pr` skips them); inner `timeout 30` outside the outer process group; SIGKILL leaves waits up to 30 s. Cleanup works on failure paths. |
| P6R1-32 | LOW | 13-wait's ~24 s is mostly fixed sleeps | `tests/13-wait.sh:37`; `tests/lib.sh:63-66` | tdd-guide L9 | Six 1 s `blocks` sleeps plus ~13 `ends` that poll once a second. |
| P6R1-33 | LOW | `# Exit:` block lacks 11 and 12 | `bin/blast-off:37-42` | tdd-guide L11 | By design (usage line names them). |
| P6R1-34 | LOW | Garbled child-count shows `child ?` and drops COUNT_ERR | `lib/units.sh:120` | silent-failure-hunter L2 | Runner writes by rename, so no flapping found. |
| P6R1-35 | LOW | Runner times children by wall clock across a machine sleep | `lib/child.sh:69-72` (outside this diff) | critical-thinking L1 (part) | A long sleep kills the child on wake; wait then reports a real change. |

## Open owner questions

1. P6R1-1: should `final` require the runner to have ended with `job done`/`job blocked` (unit down, run.log), or
   should the runner rewrite the status when it refuses done?
2. Q1 / P6R1-2: keep paused-cap at 12 (code-reviewer, security-reviewer agree), or give it its own code?
3. Q2 / P6R1-9: is "jobs started with `start`, under the job dir's parent" an acceptable documented limit? Should
   README's 12 row stop saying `start`, or should lock and unit be keyed on the physical path?
4. P6R1-7: may the line carry child-written text, or only derived values (status word, `<n> of <N>`)?
5. P6R1-6: bounds for `BLAST_OFF_WAIT_POLL`?
6. P6R1-5: retry a failed read for a few polls, or a separate exit code?
7. P6R1-19: should wait get an optional upper bound, given background commands have no timeout?
8. P6R1-13: is one real-systemd `wait` check in 11-unit-smoke acceptable?
9. P6R1-12: is a static grep for clock reads acceptable as the machine-sleep mutant killer?
10. P6R1-35 (outside the diff): is the runner's wall-clock child timeout across a machine sleep intended?

## Notes and deviations

- The first `scripts/gate.sh` call was made without its `<log-dir>` argument and stopped at the usage check
  (exit 1, no scenario ran). The gate was then run once, correctly; that is the run recorded above.
- Real-systemd probe (one transient user timer `p6probe-<pid>.resume` running `/bin/false`, never a blast-off unit):
  before firing `RemainAfterElapse=no`, `ActiveState=active`, `SubState=waiting`; after, timer and service
  `LoadState=not-found`, `ActiveState=inactive`; the journal shows the service ran and failed. A second probe
  (timer state during a 3 s service run) was denied by the auto-mode classifier and not retried, so P6R1-3's window
  is from code plus the first probe, not measured.
- Mutants and probes ran on `git archive b010b90` under the scratchpad (`rev6.ZEBa`, `rev6-w`), one at a time:
  mutant A (status dropped from the compare) PASS = survives; mutant B (`activating` as stuck) PASS = survives (a
  first try matched `activating` with `active*` and was discarded). ExecStart was unchanged after each.
- Severity changes by the review unit: P6R1-15 HIGH -> LOW (refuted by the probe), P6R1-3 LOW/MEDIUM -> MEDIUM,
  P6R1-4 HIGH -> MEDIUM (code correct, test gap only).
