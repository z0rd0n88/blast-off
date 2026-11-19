# silent-failure-hunter: phase 6 review round 2 (fix diff 174f873..d5e27e2)

Static review only: no test, scenario, gate, blast-off, systemctl or tmux was run.

## Summary

The run.log anchor does not fully close P6R1-1. Its safety argument (`wait_logged`'s comment, findings.md:51-52,
fix-1 notes) says "a child's text in run.log has a runner line after it before the status is read". But `wait`
reads the status itself, and the child wrote `status: done` into checkpoint.md before its Stop hook fired. So
while the runner is between `child_report` and `log "child $n usage"` (it is still stopping the child's scope),
`wait` sees status `done` and a run.log whose last timestamped line is child text. A last message with a line
`<ts> job done` reads as `final` in normal operation, not only when the runner is killed. A reboot, OOM or SIGKILL
in that window makes the false `final` permanent (HIGH-1).

The reverse also holds: an accepted done is not guaranteed to stay "last runner line = `job done`". Any later
timestamped line turns it into a permanent `stuck`, and the stuck line reads as a refused done. Sources:
`blast-off receipt` and `ci-wait` run after the end, processes left by `JOB_KEEP_WINDOWS`, a TERM racing
`chain_end`, or a failed `tee` (MEDIUM-2, LOW-5, LOW-6).

P6R1-5's retry turned a permanent read failure mid-watch, such as a removed job dir, into a silent infinite
block (MEDIUM-3). P6R1-3's two-poll debounce counts polls, not state or time, so it fails at the low poll values
the docs allow (MEDIUM-4). The docs' wording on 12 and 1 has drifted from the code (LOW-7 to LOW-9).

Answers to the focus questions:
1. Not fully. Child text that can start with a timestamp reaches run.log through three paths:
   - child_report's last message (lib/child.sh:120) and its non-JSON payload (lib/child.sh:114, `raw[:200]` keeps
     newlines)
   - child_screen (lib/child.sh:97-100)
   - path lists with embedded newlines in chain_dirty's `log` lines (lib/chain.sh:75, 78)

   `git status --porcelain` at lib/chain.sh:79 is safe: v1 lines start with `XY `, and paths with odd characters
   are C-quoted. systemd-run stderr (lib/usage.sh:71) starts with `Failed`. The comment at lib/units.sh:145-147 is
   inaccurate (HIGH-1).
2. No. The runner logs nothing after `job done` on the normal path: chain_exit with CHAIN_END set returns
   silently (lib/chain.sh:20), and child_stop_all does not log. But the TERM trap race (LOW-5), a failed tee
   (LOW-6) and outside writers (MEDIUM-2) can each leave another line last.
3. Yes:
   - A permanent failure mid-watch hangs forever with no output (MEDIUM-3).
   - An unlogged done/blocked combined with a leftover waiting timer blocks for the timer's life, which makes
     P6R1-17 worse (LOW-11).
   - The `down` counter is poll-based (MEDIUM-4).
   - `was` never being updated is correct, because every allowed exit compares against the start and a
     suppressed poll does not lose a net change.
   - `wait_logged` swallows grep errors, so an unreadable or missing run.log reads as "no end" with no reason
     given (LOW-10).
4. No new break in 0/11 except HIGH-1. 12 is now one poll late on an already stuck job, against spec.md:234
   (LOW-8). 1 is now at-start only; mid-watch the code never exits (MEDIUM-3). The `BLAST_OFF_WAIT_POLL` check is
   correct at its bounds: 0.1 and 3600 pass, 0.0999, 3600.001, 0, inf and words fail. It rejects `.5` (LOW-16).
5. Mostly true, with drift: README's 12 advice (`resume`) does not work on a refused done, a refused `blocked`
   is unlisted, spec.md's "at once" claim is wrong, SKILL's "do not run it again unchanged" is wrong for a
   transient read at start, and "logged no end" is wrong when the end was logged and then followed by another
   line (LOW-7, LOW-8, LOW-9).

## Findings

### HIGH-1. A child-written `<ts> job done` line reads as the runner's end in normal operation (P6R1-1 not closed)
- Location: lib/units.sh:145-152 (`wait_logged` and its comment); lib/units.sh:108; lib/child.sh:105-122
  (`print(ev.get("last_assistant_message"))` raw at :120, non-JSON payload `raw[:200]` at :114); lib/child.sh:97-100
  (`child_screen`); lib/chain.sh:212-230 (window); lib/chain.sh:75,78 (path lists); findings.md:51-52.
- Failure path / evidence:
  1. The child writes `status: done` to checkpoint.md during its turn, then stops. Its Stop hook writes
     done.json, and `child_wait` returns 0 (lib/child.sh:72).
  2. `child_report` appends the last message raw to run.log (lib/chain.sh:214). Any line of it that starts
     `YYYY-MM-DDTHH:MM:SSZ ` and ends `job done` matches `wait_logged`'s `$t$e`.
  3. The runner then runs `child_stop`, a synchronous `systemctl --user stop` of the scope (lib/child.sh:144).
     That stop takes as long as claude and its MCP servers and background shells need to die, and up to the
     scope's stop timeout. Then `usage_read`, and only then `log "child $n usage"` (lib/chain.sh:230).
  4. Throughout that window `wait` reads status `done` (lib/units.sh:131-137) and the forged line as run.log's
     last timestamped line (lib/units.sh:151), and prints `wait: final`, exit 0 (lib/units.sh:108). This
     happens before receipt_check, ci_plan and ci_check (lib/chain.sh:189,194) have run, which is the P6R1-1
     failure itself.
  5. The same window exists on the StopFailure path (lib/chain.sh:217-223, `rate_limit` logs nothing until
     :230) and the dead-child path (child_screen at :226, before `child_stop force` and :230).
  6. Chain_dirty's `log "tree $1: ... named ...: ${named[*]}"` and `log "dirty tree ..."` put git `-z` paths raw
     into one `log` call (lib/chain.sh:75,78). A path holding a newline then starts a new physical line the
     child controls. That line stays last until `log "CI at done"` (lib/ci.sh:103) for named paths, or until
     after the full `git status` dump (lib/chain.sh:79) for unnamed ones.
  7. If the machine reboots, the OOM killer fires, or the runner is SIGKILLed inside the window, the forged line
     stays last for good. Status stays `done` with no check, and every later `wait` says `final`.

  `wait_logged`'s comment ("a child cannot end the watch, unless the runner is killed between the two") and
  findings.md:51-52 ("before the status is read") reason about the runner reading the status, not `wait`. In
  benign runs the precondition is a child quoting a timestamped `job done` line at the start of a line. That is
  uncommon, but possible in a reopened job whose old run.log holds one. The guarantee P6R1-1 asked for does not
  hold.
- Suggested fix: make it impossible for any line the runner did not write to start with a timestamp. Indent
  child text: in child_report, print each line of the message and of `raw[:200]` with a fixed prefix such as
  `  | `; in child_screen, `sed 's/^/  | /'`. Flatten newlines in `log()` itself
  (`printf '%s %s\n' "$(date ...)" "${*//$'\n'/ }"`), which also covers every path list and future caller. Then
  correct the comment and findings.md. Add a 13-wait case: status `done`, unit active, run.log ends with a child
  block holding `<ts> job done`, and wait must block.

### MEDIUM-2. Any timestamped line after `job done` turns an accepted done into a permanent `stuck` that reads as "refused"
- Location: lib/units.sh:148-152 (last runner line only); lib/receipt.sh:12,37 (`receipt` logs); lib/ci.sh:27,34,45
  (`ci-wait` logs); lib/chain.sh:17 and lib/child.sh:143 (`JOB_KEEP_WINDOWS` skips stopping children);
  lib/units.sh:115-116 (stuck line); README.md wait table rows for 12.
- Failure path / evidence:
  1. The job ends `job done` and the unit goes inactive.
  2. Any of these then appends a runner-format line to run.log:
     - the owner or the watching session runs `blast-off receipt <job> <k>` to re-check a phase (receipt.sh:37,
       or `receipt refused` at :12)
     - someone runs `blast-off ci-wait <job> <pr>` to see the merged PR's CI (ci.sh:45)
     - under `JOB_KEEP_WINDOWS` a kept child's background `ci-wait` finishes (chain_exit never stops the
       scopes, and ci-wait can watch for up to 3600 s per run)
  3. Every later `wait` reads status `done`, last runner line `receipt phase ...` or `ci PR #...`, so not
     logged. Unit and timer are down, so after two polls it prints `wait: stuck · status: done ...; see
     blast-off status`, exit 12.
  4. README/spec/usage map 12 with status done to "a refused `done`". The watching session (SKILL step 8: "12
     means ... the owner must act") reports a successful job as refused. The run.log end line is still there,
     one line up.
- Suggested fix: anchor on the last runner end-or-start line, not the last line. Grep only the lines `chain_end`,
  chain_exit, the TERM trap and chain_run's first `log` write. Or have chain_end also write its line to a small
  `$JOB/run.end` that chain_run truncates at start; `wait` reads that file. Either way, `receipt`, `ci-wait` and
  kept children cannot displace it. At minimum, put the last runner line in the stuck message (LOW-10), so the
  reader can see `job done` there.

### MEDIUM-3. A read failure that does not clear mid-watch blocks forever with no output (P6R1-5 regression)
- Location: lib/units.sh:123 (`until wait_snap; do sleep "$p"; done`); lib/units.sh:131,133-135 (`2>/dev/null`,
  `return 1`); README.md exit-1 row; docs/spec.md:55 ("retried at the next poll"); SKILL.md step 8; findings.md:64.
- Failure path / evidence: the job dir is removed or renamed mid-watch. Examples: the owner stops an abandoned job
  and runs `git worktree remove` within two polls (the default job dir sits inside the workdir), or deletes a
  paused-limit job while its timer waits. Or checkpoint.md is deleted, or the user bus goes away for good. Then
  `wait_snap` fails on every poll. The loop retries forever: no line on stdout, nothing on stderr (WAIT_ERR is
  never printed mid-watch), no exit. The calling session, told to wake only when wait returns, never wakes.
  Before the fix this exited 1. The only remaining bound is the caller's background-command timeout, which
  spec.md:55 claims exists and P6R1-19 found does not. The fixer recorded this in findings.md:64, but README,
  spec and SKILL say only "retried at the next poll".
- Suggested fix: keep the retry for transient failures, but bound it. Exit 1 with `WAIT_ERR` once `$JOB` is no
  longer a directory (`[ -d "$JOB" ] || die "job dir $JOB is gone"`), and after N consecutive failed polls
  (e.g. 12, so about a minute at the default). Print WAIT_ERR to stderr on the first failure. Document the bound.

### MEDIUM-4. The two-poll stuck debounce counts polls, so at a low documented `BLAST_OFF_WAIT_POLL` the resume handoff reads `stuck`
- Location: lib/units.sh:109-118,121; lib/units.sh:62-66 (resume's own wait loop, `sleep 1`); lib/usage.sh:70-71
  (the resume service); fix-1 notes ("deactivating ... can exceed two polls ... not covered").
- Failure path / evidence:
  1. The resume timer fires. RemainAfterElapse=no makes it `inactive` at once, and resume.service starts.
  2. resume.service starts bash and sources every lib, reads status, runs unit_check, polls `systemctl show`
     with `sleep 1`, logs, then runs systemd-run. That gap is typically 0.3 to 2 s, and up to 90 s if the old
     runner is still stopping.
  3. Throughout the gap the snapshot shows unit `inactive` and timer `inactive`, so `down` reaches 2 after two
     polls. At `BLAST_OFF_WAIT_POLL=0.1`, which the docs and the test (tests/13-wait.sh:28) use, that is about
     0.2 s.
  4. Result: `wait: stuck ...` exit 12, which the docs define as "never changes on its own". The job is running
     a moment later.
- Suggested fix: read `$UNIT.resume.service` ActiveState in `wait_snap` and treat it `activating`/`active` as
  scheduled, alongside the `*' active'` arm. This is state, not clock, so it keeps the design rule and covers the
  `deactivating` case too. Or set the threshold to `max(2, ceil(10 s / poll))` polls.

### LOW-5. A TERM that lands during `chain_end`'s log leaves `runner stopped by signal` after `job done`
- Location: lib/chain.sh:6 (`CHAIN_END=1; log "$2"; exit "$1"`), :159 (TERM trap), :16 (signals ignored only inside
  chain_exit); systemd/blast-off@.service `KillMode=control-group`.
- Failure path / evidence: `blast-off stop` or a shutdown sends TERM while `log "job done"` runs. Bash defers the
  trap until the pipeline ends, then the TERM trap logs `runner stopped by signal; stopping child scopes` and
  exits 143. chain_exit returns quietly because CHAIN_END is set. run.log now ends with the signal line, status
  `done`, unit down, so `wait` reads stuck. With control-group kill, tee itself can also be TERMed before writing,
  so the `job done` line is lost.
- Suggested fix: in chain_end, `trap '' HUP INT TERM` before `log`. It is the runner's last word either way.

### LOW-6. A failed `tee` in `chain_end` drops the end line with no trace in run.log
- Location: bin/blast-off:52 (`printf | tee -a "$LOG"`, pipefail); lib/chain.sh:6,20.
- Failure path / evidence: `log "job done"` fails. Causes include ENOSPC, the job dir unwritable, or EPIPE on the
  journal stream: GNU tee writes stdout before the file, and SIGPIPE kills it first. set -e then exits with tee's
  status. CHAIN_END is already 1, so chain_exit skips its `runner exit ... without a state` line. Status `done`,
  no `job done` line, exit 1 in the journal: `wait` says stuck, and its docs call that a refused done.
- Suggested fix: write the file first and stdout second in `log` (`printf ... >> "$LOG"; printf ...`). Or set
  CHAIN_END only after `log` succeeds, so chain_exit reports the failure.

### LOW-7. README, spec, usage and SKILL describe 12 in ways the code no longer matches
- Location: README.md wait table (12 rows); bin/blast-off:12-14; docs/spec.md:55; lib/units.sh:56 (resume refuses
  `done`); lib/chain.sh:186-189,234 (a blocked can be refused too).
- Failure path / evidence:
  - (a) "the runner logged no end" is false when it logged `job done` and another line followed (MEDIUM-2), and
    when it logged a refusal, which is that run's end.
  - (b) README's 12 advice "`resume` or `start`" now covers "a refused `done`", where `resume` dies with
    `status is 'done'; resume acts only on paused-cap or paused-limit`.
  - (c) A refused `blocked` is not listed anywhere, though `receipt_check` (exit 9) and `chain_dirty` (exit 7)
    run before the blocked check. These are the same cases as a refused done.
- Suggested fix: word 12 as "nothing runs or is scheduled and run.log's last runner line is not the job's end".
  List refused done/blocked with `logs` then `start` (not `resume`).

### LOW-8. spec.md's 13-wait row still says 12 "at once on an already stuck job"
- Location: docs/spec.md:234; lib/units.sh:111-121.
- Failure path / evidence: with the two-poll rule an already stuck job is reported after one sleep (default 5 s),
  as fix-1 notes ("Stuck now takes one extra poll"). The spec row says "at once".
- Suggested fix: "after a second poll".

### LOW-9. SKILL step 8 says never rerun an exit 1 unchanged, but a transient read at start also exits 1
- Location: skills/blast-off/SKILL.md step 8; lib/units.sh:106,131.
- Failure path / evidence: a child rewriting checkpoint.md (truncate then write), or a short bus hiccup, at the
  instant `wait` starts gives `missing <job>/checkpoint.md` or `... failed (no user bus?)`, exit 1. Mid-watch,
  the same transient is retried. SKILL tells the session "fix that, do not run it again unchanged", which is
  wrong here: an unchanged rerun is the fix. The message also says "missing" for an empty file.
- Suggested fix: retry the start read a few times too, and keep exit 1 for failures that persist. Say "empty or
  missing" in the message.

### LOW-10. The stuck line for a `done`/`blocked` status gives no reason, and run.log read errors are swallowed
- Location: lib/units.sh:115-116,151 (`grep ... 2>/dev/null | tail -n 1 || return 1`).
- Failure path / evidence: `wait: stuck · status: done ...; see blast-off status` looks the same for a refused
  done, a done followed by another line (MEDIUM-2), a run.log that was deleted or rotated, or one that is
  unreadable (grep exits 2, which is hidden). `blast-off status` shows `done`, so the reader has no next step.
- Suggested fix: for done/blocked, add the last runner line, cleaned and cut to 80 characters, or `run.log
  unreadable`, to the stuck line.

### LOW-11. P6R1-17 made worse: a refused done/blocked plus a leftover waiting resume timer blocks until the timer fires
- Location: lib/units.sh:108-121; lib/units.sh:35-46 (`start` never stops the timer; only resume does, :67);
  lib/units.sh:56.
- Failure path / evidence:
  1. A paused-limit job's timer is armed for a seven_day reset, days ahead.
  2. The owner sets status `running` and runs `blast-off start` early, so the timer stays waiting.
  3. The job ends with a refused done. Before this fix, `done` returned `final` at once. Now the unlogged `done`
     suppresses every change, and `*' active'` holds `down` at 0.
  4. `wait` blocks until the timer fires. Its `resume` then dies on `status is 'done'` without a run.log line,
     and only then does `wait` print stuck.
- Suggested fix: covered by P6R1-17's fix. Have `unit_start` stop a waiting `$UNIT.resume.timer` too.

### LOW-12. The P6R1-7 cleaning leaves lookalike separators and Unicode format characters
- Location: lib/units.sh:142-143.
- Failure path / evidence: only `[[:cntrl:]]` and U+00B7 are removed. A phase line such as `phase: x ⋅ child 9 ⋅
  unit failed ⋅ timer inactive` (U+22C5, or U+2027, U+30FB, U+2022) still forges fields for a human or model
  reader within 80 characters. The same goes for bidi overrides (U+202E) and zero-width characters. Under a C
  locale, `${ph:0:80}` can split a multibyte character (fixer-acknowledged). None of this changes an exit code.
- Suggested fix: keep only printable ASCII in the phase (`LC_ALL=C` and `${ph//[^[:print:]]/?}`), which fixes
  all three.

### LOW-13. 13-wait does not cover the new failure modes
- Location: tests/13-wait.sh:88-102,179-187.
- Failure path / evidence: there is no case for any of these:
  - (i) child text holding `<ts> job done` as the last timestamped line while the unit is active (HIGH-1)
  - (ii) a timestamped line after `job done`, such as a receipt (MEDIUM-2)
  - (iii) a read failure that never clears (MEDIUM-3)
  - (iv) a handoff gap longer than two polls (MEDIUM-4)

  The `fin` block tests only the benign direction (an untimestamped `job done` after a refusal, :99).
- Suggested fix: add one case each, alongside the fixes.

### LOW-14. A change past character 80, or after the status word, is silently not a change
- Location: lib/units.sh:137,143.
- Failure path / evidence: SNAP compares only the cut fields, so a phase line whose first 73 characters of
  content stay the same and whose tail changes reads as no change. So does `status: running (note ...)` with
  new free text. Fixer-acknowledged. It matters only for long phase lines that put progress at the end.
- Suggested fix: compare a hash of the full phase line (`cksum`) in SNAP, and print only the cut text.

### LOW-15. The at-start error messages guess the cause and drop the real error
- Location: lib/units.sh:131 (`cat ... 2>/dev/null` gives "missing" for EACCES or an empty file); lib/units.sh:133-135
  (systemctl stderr to /dev/null; WAIT_ERR says "(no user bus?)").
- Failure path / evidence: a permission error, an empty file or an unrelated systemctl failure (such as an
  invalid unit name from an odd workdir) is reported as "missing" or "no user bus?". The real message is gone.
- Suggested fix: capture stderr into WAIT_ERR (`2>&1` into a variable) instead of discarding it.

### LOW-16. `BLAST_OFF_WAIT_POLL=.5` is refused though it is within 0.1 to 3600
- Location: lib/units.sh:104-105.
- Failure path / evidence: the regex needs an integer part, so `.5`, a value `sleep` accepts, exits 1 with "not a
  number of seconds from 0.1 to 3600".
- Suggested fix: `^([0-9]{0,4})(\.([0-9]{1,3}))?$` with a non-empty check, or reword the message to "digits[.ddd]".

## Open questions for the owner

1. HIGH-1: is indenting child text in run.log (`  | ` prefix) and flattening newlines in `log()` acceptable,
   given it changes run.log's look for human readers? Or should the end be recorded in a separate
   `$JOB/run.end` file?
2. MEDIUM-2: should a `receipt`/`ci-wait` line written after `job done` be able to turn a final job into
   `stuck`? If not, should the anchor be "last runner end-or-start line" or a dedicated end file?
3. MEDIUM-3: bound the mid-watch retry (exit 1 after N failed polls, or at once when the job dir is gone), or
   keep retrying forever by design? If forever, the docs should say so, since the caller has no timeout
   (P6R1-19).
4. MEDIUM-4: read `$UNIT.resume.service` as "scheduled" (state only), or use a time floor for the debounce, or
   raise the poll minimum?
5. LOW-5/LOW-6: should `chain_end` ignore signals and write the file before stdout, so a logged end is never
   followed or lost?
