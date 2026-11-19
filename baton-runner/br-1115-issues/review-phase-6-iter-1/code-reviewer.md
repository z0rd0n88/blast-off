# code-reviewer: phase 6 (issue 14), round 1

### Summary

Reviewed `git diff 62eeb5c...b010b90 -- . ':!baton-runner'`: `lib/units.sh` (`unit_wait`, `wait_snap`),
`bin/blast-off` (dispatch, usage header, env list), `tests/13-wait.sh`, `tests/70-docs.sh`, `docs/spec.md`,
`README.md`, `skills/blast-off/SKILL.md`. I read them against issue 14 (`gh issue view 14`), the phase-6 work
note and findings, and the code around them: `lib/chain.sh` (`chain_run`, `chain_count`, `chain_count_set`,
`chain_end`), `lib/checkpoint.sh` (`cp_status`, `cp_set_status`), `lib/usage.sh` (`usage_pause`, `usage_arm`,
`usage_until`), `lib/receipt.sh` (`receipt_all_done`), `lib/ci.sh` (`ci_check`), `systemd/blast-off@.service`,
`templates/checkpoint.md`, `tests/lib.sh`. Static review only: nothing was run.

The code is small and careful. `set -e` holds, `local` never masks a substitution, quoting is right, and a
missing line degrades to `?` or an empty field, never to a hang. The fake `systemctl` is local to the scenario,
and `cleanup`'s `systemctl --user stop` goes to it, so the test never touches real systemd. Every issue-14
criterion and the devil's-advocate case has a test. Mutants M1 to M7 were killed.

One real defect: `wait` returns 0 `final` the moment a child writes `status: done`. The runner then still checks
receipts and CI, and can refuse done (exit 9 or 10) while leaving the status `done`. The watcher has already
stopped and reports a done job that the runner refused. The test at `tests/13-wait.sh:62-65` locks this in.

Verdict: WARNING. One HIGH, two MEDIUM, several LOW.

### Findings

#### CRITICAL

None.

#### HIGH

**H1. `final` (exit 0) fires on the child's `status: done`, before the runner accepts it; a refused done reads as done**
- Location: `lib/units.sh:105`; runner side `lib/chain.sh:194`, `lib/receipt.sh:70`, `lib/ci.sh:79`;
  docs `README.md:106`, `skills/blast-off/SKILL.md:72`, `docs/spec.md:55`; test `tests/13-wait.sh:62-65`.
- Failure path / evidence: `unit_wait` checks the status word first and alone:
  `case "$WAIT_STATUS" in done|blocked) echo "wait: final · $SNAP"; exit 0 ;; esac`.
  But `done` is only the child's claim. On its next pass the runner does
  `done) ci_plan; receipt_all_done; ci_check; chain_end 0 "job done" ;;` (chain.sh:194).
  `receipt_all_done` can `chain_end 9 "status done but phase row $k is not done ..."`, and `ci_check` can
  `chain_end 10`, with `end='then run again; done refused, status unchanged'` (ci.sh:79). No refusal path calls
  `cp_set_status`: `grep cp_set_status lib/` finds only chain.sh:178/183/202 and usage.sh:47.
  Concrete run: child N writes `status: done` but leaves a phase row open, or its PR's CI is red. `wait` (unit
  still `active`) prints `wait: final · status: done ...` and exits 0. The skill (step 8: "0 means `done` or
  `blocked`") and README ("stop watching; read `checkpoint.md`") send the session to `checkpoint.md`, which says
  `done`. The runner then exits 10 (`ci_check` can watch a run for up to `BLAST_OFF_CI_WATCH`=3600 s first), and
  no one is watching. Running `wait` again also gives 0 at once ("already done at start"), so the refusal stays
  hidden. Only `run.log` has the truth. Nothing in the unit state catches it either: the template has no
  `SuccessExitStatus=`, so exits 0, 9 and 10 all end in a collected (`--collect`) unit that reads `inactive`.
  The test makes this behaviour required: `job fin` has the unit `active`, then `ck status "done"` and
  `ends d 0 'wait: final · status: done'`.
- Fix: count `done` as final only after the runner has finished with it. While the status is `done` and the unit
  is `active`/`activating`/`deactivating`, keep polling, treating the status change as an 11 at most, never 0.
  Once the unit is down, read `run.log`'s last line: `job done` gives `final` 0; anything else (a refusal) gives
  `stuck` 12, with the `run.log` line or `see blast-off logs`. `blocked` can stay as it is, because
  `chain_end 3` follows at once. Change test `fin` to require that `done` with the unit active does not exit 0.
  Add a case where `run.log` ends in a refusal and the unit is inactive: it should give 12. Update README's 0 row
  and SKILL step 8 to match.

#### MEDIUM

**M1. SKILL step 8 sends the session to watch a job that may not be started yet; a fresh job reads `stuck` (12, "the owner must act")**
- Location: `skills/blast-off/SKILL.md:70-72` (with steps 7 and "The start line and permissions");
  `lib/units.sh:106-108`.
- Failure path / evidence: step 7 hands `blast-off start` to the owner to run in their terminal. Step 8 then
  says "End your turn. The chain runs without you. Asked to watch it, run `blast-off wait <job-dir>` ...". By
  default the session never runs `start` itself (see "The start line and permissions"). A session asked to
  watch before the owner's start has run sees `status: running`, unit `inactive`, timer `inactive`, so
  `inactive*` matches and it exits 12. It then tells the owner "nothing is running and the owner must act". The
  work note lists this as a known risk ("A fresh job read before `start` ... is `stuck`"), and README says "run
  it after `start`" (README.md:111). SKILL.md, the text the session actually follows, does not say it. "The
  chain runs without you" is also only true once the owner has run step 7's first block.
- Fix: in step 8, say to run it once `blast-off start` has returned (the owner's or yours), and that a 12 right
  after the hand-over usually means the job was never started. Optionally add `(README, Watch)` wording that
  matches README.md:111.

**M2. A transiently empty `checkpoint.md` mid-run kills `wait` with exit 1 "missing checkpoint.md"**
- Location: `lib/units.sh:119`.
- Failure path / evidence: `cp="$(cat "$JOB/checkpoint.md" 2>/dev/null)" && [ -n "$cp" ] || die "missing $JOB/checkpoint.md"`
  runs at every poll, not only at start. The runner's own writes are atomic (`sed -i` renames, and
  `chain_count_set` uses tmp+mv). Children rewrite `checkpoint.md` with their own tools, though, and a
  truncate-then-write leaves a short window where `cat` reads empty. A poll that lands there exits 1 with a
  reason that says the path is wrong (README's 1 row: "fix the path"), on a healthy job. A partial read (status
  line present, `phase:` not yet written) instead gives a spurious 11, which is harmless. The window is small
  but recurs on every child's checkpoint edit, for the whole life of a long job.
- Fix: `die` only on the first snapshot. On later polls, an empty or unreadable read means "no snapshot this
  poll": `sleep` and read again, or retry once after a short sleep before dying.

#### LOW

**L1. Status is read before the unit state; a runner that finishes between the two reads gives `stuck` instead of `final`**
- Location: `lib/units.sh:119-124` (checkpoint read at 119, `systemctl show` at 121-122).
- Failure path / evidence: the snapshot reads `checkpoint.md` (`running`), then `child-count`, then the unit.
  If `status: done` lands and the runner exits in between, the snapshot is `running` + `inactive`, which prints
  `stuck` 12 for a finished job. The window is milliseconds against a done path that takes seconds
  (`receipt_all_done`, `ci_check`, `gh`), so it is very unlikely. The opposite order cannot err this way.
- Fix: read both `systemctl show` values first, then `checkpoint.md` and `child-count`. A status read after an
  inactive unit is then at least as new as the unit's end.

**L2. A `systemctl --user` failure (no user bus) exits 1, which the docs explain as a path problem**
- Location: `lib/units.sh:121-122`; `README.md:108`; `docs/spec.md:55`, 108-110.
- Failure path / evidence: `WAIT_UNIT="$(systemctl --user show ...)"` is a plain assignment under `set -e`. If
  the user manager is unreachable ("Failed to connect to bus", e.g. a shell without
  `XDG_RUNTIME_DIR`/`DBUS_SESSION_BUS_ADDRESS`), the script exits 1 with no `wait:` line. README's exit-1 row
  says "no job dir or no `checkpoint.md` | fix the path". `unit_status` has the same pattern, so this matches
  existing behaviour; only the doc row is wrong.
- Fix: document exit 1 as "no job dir, no `checkpoint.md`, or an error (stderr says which)", or `die` with a
  named reason when `systemctl show` fails.

**L3. `BLAST_OFF_WAIT_POLL` is unvalidated: a non-number exits 1 after the first snapshot; `0` busy-loops two `systemctl` calls**
- Location: `lib/units.sh:111` (`sleep "${BLAST_OFF_WAIT_POLL:-5}"`).
- Failure path / evidence: `BLAST_OFF_WAIT_POLL=5s` works, but `=abc` makes `sleep: invalid time interval`, and
  `set -e` exits 1 (doc'd as "fix the path"). `=0` spins with two `systemctl` and three `sed` per iteration and
  no pause. This is in the work note's risk list. Every `JOB_*` number is validated (`chain_nums`); this one
  is not.
- Fix: `[[ ${BLAST_OFF_WAIT_POLL:-5} =~ ^[0-9]+(\.[0-9]+)?$ ]] || die "BLAST_OFF_WAIT_POLL ..."` at the top of
  `unit_wait`. Clamping 0 is optional.

**L4. Timer ActiveState `active` includes `elapsed`; if a fired resume timer stays loaded after a failed `resume`, `wait` blocks forever**
- Location: `lib/units.sh:107` (`*' active') ;;`), `lib/usage.sh:70-71`.
- Failure path / evidence: systemd maps a timer's `waiting`, `running` and `elapsed` substates all to
  ActiveState `active`. If `<unit>.resume.timer` remains `active (elapsed)` after its `resume` service fails
  (e.g. `unit_check` dies on `CLAUDE_FLAGS`, or `systemd-run` refuses), the snapshot `status: paused-limit`,
  `unit inactive`, `timer active` never changes and is never `stuck`: the "never changes on its own" case from
  the devil's-advocate note. I believe `systemd-run` sets `RemainAfterElapse=no` on transient timers unless
  `--remain-after-exit` is given, which would make the timer go `inactive` once its service ends, but I have not
  checked this on this box. The work note also lists it as unverified.
- Fix: decide on the substate, not the ActiveState. Read `-p SubState` for the timer and count it as scheduled
  only when it is `waiting` or `running`. This holds whatever the systemd default turns out to be.

**L5. The machine-sleep test proves only that `date` is not called**
- Location: `tests/13-wait.sh:110-129`.
- Failure path / evidence: the fake `date` jumps 10 h per poll, but `unit_wait` never calls `date`, so the test
  passes whatever the code does with time, as long as it does not use `date`. A regression using
  `$EPOCHSECONDS`/`$SECONDS`/`printf '%(%s)T'` would survive (the work note says so). The behaviour itself is
  correct by construction: `unit_wait` keeps no time at all.
- Fix: add a cheap static guard to the scenario, e.g. `! sed -n '/^unit_wait()/,/^}/p;/^wait_snap()/,/^}/p' lib/units.sh | grep -qE 'date|EPOCH|SECONDS|%\(.*\)T'`,
  or accept the gap and say so in the spec's 13-wait row.

**L6. Test gaps: `deactivating`, `activating`, and the runner's real pause order are not exercised**
- Location: `tests/13-wait.sh:71-92`; `lib/units.sh:106-108`.
- Failure path / evidence: (a) a mutant that drops `deactivating*` from the stuck pattern survives: no case sets
  the unit to `deactivating`. (b) A mutant that adds `activating*` to it (a false `stuck` during `start` or
  `resume`) survives too. (c) The runner writes `paused-cap`/`paused-limit` while the unit is still `active`
  (chain.sh:202, usage.sh:47), then exits. The test only covers "unit inactive first, then status" (line 84,
  commented as such), so the "returns on paused" criterion has no test in the real order: 11 on the status
  change with the unit active, then 12 (cap) or blocking (limit with timer) on the next `wait`.
- Fix: add `deactivating` (gives 12) and `activating` (blocks, then 11 on `active`) cases, plus one run of
  `running`+active, then `paused-cap`+active (11), then inactive (12).

**L7. `blocks` proves blocking by a 1 s sleep, which a slow start can make vacuous**
- Location: `tests/13-wait.sh:37`.
- Failure path / evidence: `blocks() { sleep 1; [ ! -e "$1.rc" ] || fail ...; }`. If `blast-off` takes over 1 s
  to source `lib/*.sh` and take its first snapshot (a loaded box running the full gate), the check passes before
  `wait` has read anything. A wrongly-returns-at-once bug could then pass whenever the mutation lands before the
  first snapshot. Most cases still fail such a bug through the later text check, so this is low.
- Fix: in `blocks`, first wait for evidence that a poll happened. A fake `sleep` that counts calls, like the
  clock case's, does this: wait until `polls >= 2`, then check that no `.rc` exists.

**L8. spec §3 says all of wait's codes are "outside this table's range", but 0 and 1 are inside it**
- Location: `docs/spec.md:108-110`.
- Failure path / evidence: "0 at `done` or `blocked`, 11 ..., 12 ..., 1 with no job dir or `checkpoint.md`.
  They are outside this table's range, so a watcher never reads one as the runner's." Only 11 and 12 are outside
  0-10. Wait's 0 also covers the runner's 3 (`blocked`), and its 1 is the runner's 1.
- Fix: "11 and 12 are outside this table's range; 0 and 1 mean what they mean there, except that wait's 0 also
  covers `blocked` (the runner's 3)."

**L9. The spec says the caller's background command has a timeout; a Claude Code background command has none**
- Location: `docs/spec.md:55` ("No timeout of its own: the caller's background command has one"); findings
  "the caller's background command has its own timeout".
- Failure path / evidence: the Bash tool's `timeout` caps foreground commands. `run_in_background` commands run
  until they exit. A `wait` on a `paused-limit` job with an armed timer blocks for hours, which is intended, but
  nothing bounds it if L4's case happens. The justification for skipping `BLAST_OFF_WAIT_MAX` rests on this
  claim.
- Fix: drop or correct the sentence. The no-timeout decision still stands on "state, never the clock".

**L10. The usage header leaves out wait's exit 1 and the `paused-limit`-without-timer stuck case**
- Location: `bin/blast-off:9-11`.
- Failure path / evidence: "12 nothing runs or is scheduled while the status is not final (stopped, crashed,
  paused-cap)". README and spec also list "a reboot" and "`paused-limit` with no timer". This is a minor drift
  between the three docs. Exit 1 is covered by the general `# Exit:` 1, so leaving it out there is fine.
- Fix: add "paused-limit with no timer" to the parenthesis, or end it with "...".

### Open questions for the owner

- **Q1 (paused-cap gives 12, not 0):** I agree with the default. 12 means "needs the owner" for every case where
  nothing will move on its own, and 0 should stay "the runner finished". If H1 is fixed as proposed, 0 becomes
  "the runner accepted done, or blocked", which is a cleaner meaning. Note that the issue lists "paused" beside
  done and blocked as return events. 11 then 12 satisfies "returns", so no change is needed.
- **Q2 (a foreground `run` reads as `stuck`):** I agree with the default, for scope. One cheap improvement: when
  stuck, check the runner lock (`$XDG_RUNTIME_DIR/<unit>.lock`, see `tests/lib.sh:55`). If a live process holds
  it, print `changed`/block instead of `stuck`. That covers foreground runs and the own-workdir case in one
  check. Defer it unless foreground watching is wanted.
- **Exit-code scheme:** 11 and 12 are well chosen: outside the runner's 0-10 and clear of 124/126/127/143. The
  only overlap is 1 (see L2 and L3: any internal error lands there with a path-fix hint).
- **`activating` during `start`/`resume`:** handled correctly. `Type=exec` keeps `activating` short, it is not
  in the stuck pattern, and it falls through to the change check (at worst an extra 11 when it becomes
  `active`). During a timer-run `resume`, the timer reads `active` (running) for the whole 90 s
  wait-for-old-unit loop, so `deactivating` is not `stuck` there either. Untested (L6).
- **Is the resume timer `RemainAfterElapse=no` under `systemd-run`?** Decides whether L4 can happen. A one-time
  check on real systemd (arm a 5 s transient timer whose service exits 1, then `show -p ActiveState,SubState`)
  would settle it.
