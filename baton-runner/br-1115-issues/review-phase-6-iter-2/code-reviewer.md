# code-reviewer: phase 6 (issue 14, `blast-off wait`), review round 2 (narrow)

Fix diff `git diff 174f873..d5e27e2 -- . ':!baton-runner'`, read against the full phase diff
`62eeb5c...d5e27e2`. Static only: no tests, gate or blast-off runs.

## Summary

The fix does what owner ruling P6R1-1 asks in normal operation. An accepted `done`/`blocked` always ends run.log
with the exact runner line, the runner's refusals all log after the child's text, and the 0/11/12/1 contract holds.
Nothing here is HIGH. Four things are weaker than the code and notes claim:

1. The retry added for P6R1-5 turns any permanent read failure into a silent hang with no end. That includes a
   job dir that was deleted or moved, an empty checkpoint.md, or a user bus that is gone. A dead job behind that
   failure is never reported as `stuck`. This makes open P6R1-19 (no caller timeout) worse.
2. The anchor comment in `wait_logged` (and the same claim in the fix notes and phase-6/findings.md) is wrong. The
   window between the child's text reaching run.log and the runner's next timestamped line is open in normal
   operation, not only when the runner is killed. `wait` polls during that window.
3. Only the `done` half of the new done/blocked pairing has a test that fails if it breaks.
4. Small doc drift.

Verdict: WARNING (0 CRITICAL, 0 HIGH, 3 MEDIUM, 5 LOW).

## Focus questions

**Q1. Does the run.log anchor close P6R1-1? Can a child-written line read as the runner's last line?**
In normal operation, no false `final` occurs unless child-written text contains a line in the runner's exact form
`YYYY-MM-DDTHH:MM:SSZ job done` (or `... job blocked; see ...`). So the ruling holds for ordinary output. But the
guarantee in the comment (`lib/units.sh:146-147`) is false. Order in `chain_run`:
`child_report` (`lib/chain.sh:214`/`217`) or `child_screen` (`:226`) -> `child_stop` / `child_stop force`
(`systemctl --user stop` of the scope: as long as the scope's stop timeout when claude ignores TERM) ->
`usage_read` -> `log "child $n usage"` (`:230`). The status is `done` from the moment the child wrote it, and
`wait` polls every 5 s through this whole window, so a forged last line is read in normal operation. A killed
runner is not required. See MEDIUM-2 for every child-controlled source. `git status --porcelain -uall >> "$LOG"`
(`lib/chain.sh:79`) cannot forge a line: porcelain v1 lines begin with two status characters and a space, and
names holding a newline or control character are C-quoted. `usage.sh:33` flattens newlines and `receipt_refuse`
(`lib/receipt.sh:12`) does too.

**Q2. Does an accepted done always end run.log with that exact line?**
Yes in the runner's own path. `chain_end 0 "job done"` (`lib/chain.sh:194`, `:6`) sets `CHAIN_END`, logs, then
exits. `chain_exit` (`:14-23`) ignores HUP/INT/TERM first, then `child_stop_all` (`lib/child.sh:29-33`, no
`log`), then removes the lock, then returns at `CHAIN_END` without its "runner exit" line. The resume timer's
`blast-off resume` on a done job dies to its own journal (`lib/units.sh:56`) without writing run.log, and
`usage_arm`'s `2>> "$LOG"` only runs at arm time. The exceptions are in LOW-1:
- a TERM in the instants between `log "job done"` and `trap ''` in `chain_exit`;
- the owner running `blast-off receipt` or `ci-wait` on the finished job, which log afterwards.

A failing `tee` aborts before the line is written, so `wait` reads stuck. That is consistent with the ruling.

**Q3. Forever-blocks and false wakes.**
- The two-poll counter `down` (`lib/units.sh:109-113`) is correct for every state I traced: `activating` resets
  it, `failed`/`deactivating` advance it, and a `*' active'` timer resets it.
- An unlogged `done`/`blocked` hides every change (`:121`), but the stuck path still fires, so the job cannot hang
  on it. The worst case is a hang bounded by CI watching inside the runner's done path, which is the intended
  behaviour.
- `was` is never updated. That is correct, because every reported change exits, and the two suppressions (first
  down poll, unlogged final status) compare against the start snapshot on purpose.
- `until wait_snap; do sleep; done` (`:123`) **does** block forever on a permanent failure: MEDIUM-1.
- The resume handoff can still read as a false `stuck` when the resume service needs more than one poll: LOW-4.

**Q4. The 0/11/12/1 contract.** No regression found.
- `BLAST_OFF_WAIT_POLL` validation (`:104-105`) is correct: `5` gives 5000 ms, `0.1` gives 100, `3600` gives
  3600000, and `0100` (= 100 s), `0.05`, `3601`, `inf`, `abc` and `--help` are refused before any read.
  `.5` and `1.` are refused too, though they are inside the stated range (not filed: the message gives the format).
- The at-start errors all `die` (exit 1). An already-stuck job now takes one poll before 12, and the docs say so.

**Q5. Docs truth.** Mostly accurate. The drift is in LOW-3. The silent forever-retry is not documented anywhere a
watcher reads (MEDIUM-1).

**Issue-14 criteria -> a test that fails if the behaviour breaks** (`tests/13-wait.sh`):
- child launch: `c`, 61-66;
- phase change: `p`, 69-72;
- done: `d`, which now blocks and then goes final on the logged line, plus `d2` and `d3`; mutants M1/M1b/M1c
  were killed per the fix notes;
- blocked: `b`, already blocked at start only (P6R1-27, open), and the blocked pairing has no killing test
  (MEDIUM-3);
- paused: `pc`/`pc2`/`pl`/`pl2`/`st`;
- unit inactive/failed: `g`/`g2`/`g3`;
- missing job dir / no checkpoint.md / bad poll / bus at start: the exit-1 block;
- machine sleep: `s` (P6R1-12, open);
- devil's-advocate stuck: `g`.

Every criterion still has a test. Only the blocked one is weak.

## Findings

### MEDIUM-1. A permanent read failure mid-watch hangs `wait` silently forever and hides a dead job

- Location: `lib/units.sh:123` (`until wait_snap; do sleep "$p"; done`), `lib/units.sh:131`, `:133-135`;
  `README.md:112` ("a failed read later is retried at the next poll"); `docs/spec.md:55` ("a read that fails later
  is retried at the next poll" ... "No timeout of its own: the caller's background command has one");
  `skills/blast-off/SKILL.md:70-76`.
- Failure path: any read that keeps failing makes the `until` loop spin with no output and no exit. While reads
  fail, `down` never advances, because it is only computed after a successful snapshot. So even when the runner is
  dead, the `stuck` that issue 14's devil's advocate case exists for is never printed. Triggers:
  1. The job dir is deleted or moved while watched, for example the workdir's worktree removed after a merge, or
     the job dir renamed. `cat` fails on every poll.
  2. `checkpoint.md` is left empty. For example, a child killed by `JOB_CHILD_TIMEOUT` mid-rewrite, after which
     the runner later exits (two stalls, exit 5) and the unit goes inactive.
  3. The user manager or bus is gone for good (`systemctl --user` fails on every call).

  Round 1 exited 1 in these cases. Now the watching session never wakes. A Claude Code background command has no
  timeout (P6R1-19, open, and still claimed in spec:55), so nothing ends it. The fix notes (baton-phase-6-fix-1.md
  "New limits") and phase-6/findings.md:64 record this limit, but README, spec and SKILL.md, which a watcher reads,
  only say "retried".
- Suggested fix: bound the retry and keep exit 1 for "cannot watch". For example, count consecutive failed reads
  and `die "$WAIT_ERR"` after N polls or about 60 s:
  `local bad=0; until wait_snap; do bad=$((bad+1)); [ "$bad" -lt 12 ] || die "$WAIT_ERR (for $bad polls)"; sleep "$p"; done`.
  Then state the bound in README:112, spec:55 and SKILL step 8. Add a test: delete the job dir mid-watch and
  expect exit 1 within the bound.

### MEDIUM-2. The anchor's guarantee is false: the window between a child's text and the next runner line is open in normal operation, and `wait` polls through it

- Location: comment `lib/units.sh:146-147` ("A child's text in run.log has a runner line after it ... so a child
  cannot end the watch, unless the runner is killed between the two"). The same claim appears in
  `baton-phase-6-fix-1.md` Decisions ("before the status is read") and `phase-6/findings.md:51`. Code:
  `lib/child.sh:105-122` (`child_report` prints `session_id`, `transcript_path`, `error`,
  `last_assistant_message` and, for a non-JSON payload, `raw[:200]` unquoted into run.log);
  `lib/child.sh:97-101` (`child_screen`, pane text unquoted); `lib/chain.sh:214-230` (report or screen, then
  `child_stop`, then `usage_read`, then `log "child $n usage"`); `lib/ci.sh:45` (child-run `ci-wait` logs workflow
  run names unflattened).
- Failure path: the status is already `done` when the child's Stop hook fires, because the child writes it as its
  last act. `child_report` appends the child's last message. If any line of that message has the form
  `2026-11-18T10:00:00Z job done`, for example a child quoting an earlier run.log of a re-opened job in its final
  summary, then until `log "child $n usage"` runs, `wait_logged done` reads that line as the runner's last line.
  The next poll prints `wait: final` with exit 0. The runner then runs `receipt_check`/`ci_plan`/`ci_check` and may
  refuse (exit 9/10, status left `done`): exactly P6R1-1's failure.

  The window is not a kill race. It lasts as long as `child_stop`: about 1 s normally, and up to the scope's stop
  timeout when claude ignores TERM. A dead child's screen (`child_screen`, `:226`) is in the same window.

  A second, wider window: the child runs `blast-off ci-wait` and then writes `done`. From that write until the
  runner's next line, the last runner line is `ci-wait`'s `lib/ci.sh:45`. A workflow `name:`/`run-name:` holding a
  newline puts a line of the child's choosing there. That is a narrower trigger, since the child must author such
  a name.

  Not HIGH: an ordinary child does not emit a line in the runner's exact format. But the comment tells the next
  maintainer that the ordering prevents this, and it does not.
- Suggested fix (one of):
  - (a) Quote child-written text in run.log so no line of it can start with a digit. For example, in
    `child_report` print each line of the message, the payload and the ids with a two-space or `| ` prefix, keeping
    the `child $n session=` and `---` markers that `child_report`'s own `sed` uses. Prefix `child_screen`'s lines
    the same way, and flatten newlines in `ci.sh:45`'s run names, as `receipt_refuse` does.
  - (b) Also require the unit not `active`/`activating` for `final`. The runner logs `job done` and exits seconds
    later, and the whole child window has the unit up. That keeps the ruling's semantics and costs one or two
    polls.

  Either way, correct the comment and notes. Add a test: a `done` job whose run.log ends with the child's last
  message holding a timestamped `job done`, with the unit active, must block.

### MEDIUM-3. The `blocked` half of the new done/blocked pairing has no test that fails if it breaks

- Location: `lib/units.sh:108`, `:121` (`[[ $WAIT_STATUS =~ ^(done|blocked)$ ]]`), `:148-152` (`e='job blocked; see '`);
  `tests/13-wait.sh:101-103` (only `ck status blocked` plus a logged `job blocked; see`, then `b` already final at
  start).
- Failure path: these mutants all survive 13-wait, by inspection of every `blocked` use in the file:
  - `blocked)` made unconditionally final (`case ... blocked) echo final; exit 0`);
  - `blocked` dropped from the change suppression at `:121`, so a child-written `blocked` exits 11;
  - `e` widened to `job (done|blocked)`, so `done` pairs with a `job blocked; see` line and the reverse.

  `blocked` can be refused like `done`: `receipt_check` runs before the status check (`lib/chain.sh:189`) and
  exits 9 with the status left `blocked`. So this logic matters as much as the done half. Round 1's P6R1-27 (LOW,
  open) covered only "blocked tested at start". The fix added logic for `blocked` without tests, which raises the
  stakes of that gap.
- Suggested fix: three short cases on the `fin` job.
  - `running` -> `blocked` with the unit active and run.log not ending `job blocked; see` blocks. Appending that
    line then goes final.
  - `status: done` with run.log's last runner line `job blocked; see ...` and the unit inactive gives 12.
  - `status: blocked` with the last line `job done` gives 12.

### LOW-1. An accepted end can still turn into a permanent `stuck`

- Location: `lib/chain.sh:6`, `:14-16`, `:159`; `lib/receipt.sh:12`, `:37`; `lib/ci.sh:27`, `:34`, `:45`.
- Failure path, three cases:
  - (a) A TERM (`blast-off stop`, or the user manager stopping) that arrives after `log "job done"` and before
    `trap '' HUP INT TERM` in `chain_exit` runs the TERM trap. It logs `runner stopped by signal; stopping child
    scopes` and exits 143 inside the EXIT trap, which also skips `child_stop_all`. The status is `done`, the last
    runner line is not `job done`, and every later `wait` reports stuck. The window is a few instructions wide.
  - (b) The owner runs `blast-off receipt <job> <phase>` or `blast-off ci-wait <job> <pr>` on a finished job.
    Each logs a timestamped line after `job done`, so a later `wait` on that accepted job says `stuck ...; see
    blast-off status`.
  - (c) `wait_logged` keys on the last runner line of any kind, not the last chain-end line.
- Suggested fix: match the last chain-end line instead of the last runner line (`job done`, `job blocked; see`,
  the refusals, `runner exit`, `runner stopped by signal`). Or document (b) in README's 12 row. For (a), move
  `trap '' HUP INT TERM` into `chain_end` before its `log`.

### LOW-2. `deactivating` counted as down still has no test (P6R1-8 only half fixed)

- Location: `lib/units.sh:111`; `tests/13-wait.sh` (no `deactivating` anywhere; `act` covers `activating` only).
- Failure path: dropping `deactivating*` from `:111` sends it to `*) down=0`. A unit stuck in `deactivating`
  (a stop waiting out `TimeoutStopSec` on a scope that ignores TERM) would then never read as stuck. No test fails.
  The fix notes list P6R1-8 as fixed.
- Suggested fix: one case with the unit `deactivating`, the timer inactive and the status `running`, expecting 12.

### LOW-3. Doc drift against the code

- Location: `README.md:99-104`, `:108`, `:111`; `docs/spec.md:55`.
- Evidence:
  - README:108 says "A `done` it has not logged yet keeps `wait` waiting". The code holds an unlogged `blocked` the
    same way (`units.sh:121`).
  - README:111 and spec:55 list "a refused `done`" among the stuck causes, but not a refused `blocked` (exit 9
    with status `blocked`).
  - spec:55 says stuck needs "the runner logged no end". The code's test is "no end *matching the status*": a
    `done` whose last line is `job blocked; see` is stuck, and so is a `running` job whose run.log ends `job done`.
  - README:99-101 lists what `wait` reads every poll and leaves out run.log.
  - README:103-104 and spec:55 say "each [is] at most 80 characters". The status field is the word cut to 80 plus
    ` until <up to 40>` (`units.sh:140-143`), so it can reach about 135. The phase field's 80 includes `phase: `.
  - The docs say ` · ` is removed. The code replaces every `·` with `-` (`units.sh:142`).
- Suggested fix: reword those clauses to the code.

### LOW-4. A false `stuck` at the resume handoff remains when the resume service needs more than one poll

- Location: `lib/units.sh:109-118`; `lib/units.sh:62-64` (resume waits up to 90 s for the old unit);
  `baton-phase-6-fix-1.md` Decisions (acknowledged).
- Failure path: the timer fires and goes `inactive`/`not-found`. `blast-off resume` waits for an old runner that
  is still `deactivating`, or is slow for another reason, for more than `BLAST_OFF_WAIT_POLL` seconds. Two
  down polls follow, and `wait` prints `stuck` exit 12 while a start is under way. The notes argue that the old
  runner is long gone at a usage reset. That holds for the timer, but not for an owner `resume` racing a stopping
  unit. A watcher started after `resume` returns does not hit it, since `resume` returns after `unit_start`.
- Suggested fix: count `$UNIT.resume.service` `activating`/`active` as scheduled (one more `systemctl show`
  property). P6R1-3 originally proposed this.

### LOW-5. The fix notes and findings repeat the false anchor claim as a decision

- Location: `baton-runner/br-1115-issues/baton-phase-6-fix-1.md` (Decisions: "A child's text ... is always
  followed by the runner's timestamped `child <n> usage` line before the status is read. So only a runner killed
  between the two can leave a forged timestamped line last."); `phase-6/findings.md:51`.
- Evidence: "before the status is read" holds for the runner's own `cp_status`, not for `wait`, which reads the
  status independently every poll (MEDIUM-2).
- Suggested fix: correct both records with MEDIUM-2's fix, so the claim is not carried into later phases.

## Review Summary

| Severity | Count | Status |
|----------|-------|--------|
| CRITICAL | 0     | pass   |
| HIGH     | 0     | pass   |
| MEDIUM   | 3     | info   |
| LOW      | 5     | note   |

Verdict: WARNING. No blocker. MEDIUM-1 is a regression introduced by this round, a silent forever-hang where
round 1 exited 1, and is worth fixing before merge.

## Open questions for the owner

1. MEDIUM-1: after how many consecutive failed reads should `wait` give up, and with exit 1 ("cannot watch") or
   12 ("stuck")? Should a failed read also count toward `down`?
2. MEDIUM-2: close the window by quoting child text in run.log (runner change), or by also requiring the unit not
   up for `final` (wait-only change, final a poll or two later)?
3. LOW-1(b): should owner-run `receipt`/`ci-wait` after `job done` be able to turn a finished job into `stuck`, or
   should `wait` anchor on the last chain-end line rather than the last runner line?
4. LOW-4: is reading `$UNIT.resume.service` acceptable as a third `systemctl show` per poll?
