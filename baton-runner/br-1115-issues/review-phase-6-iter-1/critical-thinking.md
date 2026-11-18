# critical-thinking: phase 6 (issue 14), round 1

### Summary

Reviewed `git diff 62eeb5c...b010b90 -- . ':!baton-runner'` (lib/units.sh `unit_wait`/`wait_snap`, bin/blast-off
dispatch and usage, tests/13-wait.sh, tests/70-docs.sh, docs/spec.md, README.md, skills/blast-off/SKILL.md) against
issue 14, its devil's-advocate note, and the work unit's notes (baton-phase-6-work.md, phase-6/findings.md). Read
surrounding code: lib/chain.sh (chain_run, chain_count, chain_count_set, chain_exit), lib/usage.sh (usage_pause,
usage_arm, usage_until), lib/units.sh (unit_resume, unit_status), lib/child.sh (child_wait), lib/checkpoint.sh
(cp_status, cp_set_status), systemd/blast-off@.service, templates/checkpoint.md, tests/lib.sh. Static only; nothing run.

Verdict: the shape is right (poll, compare state, no clock, final/stuck checked before changed, exit codes outside the
runner's 0-10, an "already final/stuck" return at start). Two design holes need answers before this is the
recommended way to watch a job. (1) `final` (exit 0) is the child's claim, not the runner's verdict: the runner
can still refuse done (exit 7, 9, 10) and leave `status: done`, so wait says "done, stop watching" on a job that
needs action, and repeats it at once forever. (2) The "a resume timer is active, so something is scheduled" rule
trusts systemd's `ActiveState`, which stays `active` on an elapsed one-shot timer whose resume failed. wait then blocks
forever on a job that will never move, which is the hazard the devil's-advocate note names. The other findings are
transient-error handling (a torn read or a bus error ends a watch with exit 1, "fix the path"), read-order races, and
test gaps: activating, deactivating and elapsed states, and the real running→paused order, are never exercised.

Checked and found sound: `chain_count_set` writes by rename, so `child-count` cannot be read torn and `?` cannot
flap from the runner's writes. `cp_set_status`/`cp_mark_usage` use `sed -i`, also a rename. The unit-then-timer read
order is the safe one for usage_pause (status, arm timer, then exit). Type=exec with no Restart= means `activating` is
brief and `reloading` never occurs. A missing unit or timer reads `inactive` (exit 0). The test's fake `systemctl`
never touches real units, and `stop_bg`'s `pkill -P` on each subshell reaches `timeout`, which signals its group.

### Findings

#### CRITICAL

None.

#### HIGH

**H1. `final` (exit 0) fires on the child's `status: done`, before the runner accepts it; refused dones read as done forever**
- Location: lib/units.sh:105; README.md:106; skills/blast-off/SKILL.md:70-71; tests/13-wait.sh:63-65
- Failure path / evidence: `case "$WAIT_STATUS" in done|blocked) echo "wait: final · $SNAP"; exit 0 ;; esac` is
  checked first, "whatever the unit" (findings.md Decisions). But `status: done` is written by the child mid-session.
  After that the runner still runs `chain_dirty "after child $n"` (lib/chain.sh:234, exit 7), `receipt_check` /
  `receipt_all_done` (exit 9) and `ci_check` (exit 10, "done refused, status unchanged", lib/ci.sh:110-134), and
  `ci_check` can spend minutes on `gh`. Each refusal leaves `status: done` with the unit inactive. wait has already
  returned 0, and every later `wait` returns `final` at once, so the watcher never learns the job was refused. The
  README tells it to "stop watching; read `checkpoint.md`", which still says done; the refusal reason is only in
  run.log. The test asserts this behaviour: line 64-65 flips status to done while the fake unit is `active` and expects
  exit 0. The same holds, less harmfully, for `blocked` written while the child and runner are still up.
- Why it matters: issue 14's hit was a watcher that "kept firing after `job done`"; this is the opposite error, a
  watcher that stops before the job is done and reports success. A session that then starts the next job in that
  workdir also meets the live runner's lock.
- Fix: make `final` require the runner unit to be down (`inactive`/`failed`, not `active`/`activating`/
  `deactivating`); until then a done/blocked status is only a `changed` (or keep blocking). For `done`, also require
  the runner's own verdict: the last runner line in `run.log` is `job done` (chain_end 0 logs it; `--collect` drops
  `ExecMainStatus`). A done that the runner refused gets its own code, or `stuck` with the run.log line, never 0.
  Add a test: status done, unit active → no return; unit inactive with run.log ending in a refusal → not 0.

**H2. An elapsed resume timer reads `active` forever, so a paused-limit job whose resume failed blocks wait indefinitely**
- Location: lib/units.sh:106-107 (`*' active') ;;`), lib/units.sh:122; lib/units.sh:54-67 (unit_resume); lib/usage.sh:70
- Failure path / evidence: the stuck rule treats `WAIT_TIMER = active` as "scheduled". The resume timer is a one-shot
  `--on-calendar` transient. systemd maps the timer's `elapsed` substate to `ActiveState=active` (as it does `waiting`
  and `running`), and `RemainAfterElapse=` defaults to yes, so after it fires the timer stays loaded and `active`
  until someone stops it (`--collect` only collects inactive or failed units). Only a *successful* `unit_resume`
  stops it (`systemctl --user stop "$UNIT.resume.timer"`, line 67). Every failure path leaves it elapsed and
  `active`: `unit_check` dies, `unit_start` fails (line 66 logs "status kept ... journalctl --user -u
  $UNIT.resume.service when the timer ran it"), or resume dies because the owner already started the job by hand
  ("status is 'running'; resume acts only on ..."). The runner unit then stays `inactive` and the status stays
  `paused-limit until …` (or, in the second path, a later crash leaves `running`), so the snapshot never changes. wait
  hits `*' active'`, skips stuck, sees no change, and sleeps forever. The watching session never wakes. This is
  exactly "a state that never changes on its own", the devil's-advocate case, entered through the timer.
- Fix: read `SubState` with `ActiveState` (`systemctl show -p ActiveState,SubState`) and count the timer as
  "scheduled" only when its SubState is `waiting` or `running`; `elapsed` (or a `paused-limit until` time well in the
  past with the runner down) is stuck. Teach the fake systemctl a SubState and add a scenario: unit inactive, timer
  `active`/`elapsed`, status paused-limit → 12. Ask the owner to confirm the elapsed reading on a real box with one
  forced resume failure (`systemctl --user show <unit>.resume.timer -p ActiveState,SubState`).

#### MEDIUM

**M1. Any transient read error mid-watch ends wait with exit 1, the code the README maps to "fix the path"**
- Location: lib/units.sh:119, 121-122; README.md:109; bin/blast-off:43 (`set -euo pipefail`)
- Failure path / evidence: (a) `cp="$(cat "$JOB/checkpoint.md" 2>/dev/null)" && [ -n "$cp" ] || die "missing
  $JOB/checkpoint.md"` runs on every poll, not just the first. The runner's own writes are renames (`sed -i`), but
  children edit checkpoint.md with whatever tool they use. A truncate-then-write (shell `>`, or an editor or tool that
  rewrites in place) read at the wrong moment gives an empty file → `die` → exit 1 on a healthy running job. A
  partial read (status line present, phase line not yet) gives a spurious 11, which is harmless. (b)
  `WAIT_UNIT="$(systemctl --user show ...)"`: when systemctl fails (user bus restart, `XDG_RUNTIME_DIR`/
  `DBUS_SESSION_BUS_ADDRESS` missing in the caller's shell), the assignment takes its non-zero status and `set -e`
  aborts wait with exit 1, no `wait:` line on stdout, only systemctl's stderr. (c) A non-numeric
  `BLAST_OFF_WAIT_POLL` makes `sleep` fail the same way. In all three the watcher is told "no job dir or no
  `checkpoint.md` … fix the path" and stops watching a job that is running fine.
- Fix: `die` only on the first snapshot (job dir/checkpoint truly absent). Inside the loop, an empty or unreadable
  checkpoint or a failed systemctl is "no snapshot this poll": keep the old one and sleep again, or give it a code of
  its own after N failures in a row. Guard the systemctl calls (`|| WAIT_UNIT=unknown`) so `set -e` cannot end the
  watch silently. Validate `BLAST_OFF_WAIT_POLL` as a positive number once at entry.

**M2. `paused-cap` shares exit 12 ("stuck") with crash, stop and reboot; the issue lists "paused" beside done/blocked**
- Location: lib/units.sh:106-108; README.md:108; SKILL.md:70-71; findings.md Q1
- Failure path / evidence: issue 14 says wait "returns on … done/blocked/paused" and "exit 0 on a terminal status".
  The implementation returns on paused (good) but puts `paused-cap` under `stuck`, the same code as a crashed or
  rebooted runner. Those need different actions: `resume` for paused-cap (a designed pause, runner exit 6 "run again
  to continue") versus `logs`, then `start`, for a crash. A watcher can only tell them apart by parsing the status
  word out of the line, while the SKILL tells it "12 means nothing is running and the owner must act". "Stuck" also
  reads as a failure for a pause the owner configured. The alternative reading (paused-* is terminal → 0) is wrong
  for an armed paused-limit, so Q1's refusal to use 0 is sound. Still, one code for two meanings that need different
  actions is a choice the owner should make on purpose.
- Fix: decide Q1 explicitly. The cheapest version that keeps the codes honest: a separate code (e.g. 13 `paused`) for
  paused-cap and an unarmed paused-limit, with the action `blast-off resume`; 12 stays crash/stop/reboot. If 12 is
  kept, the SKILL step 8 text should say to read the status word before choosing between `resume` and `start`.

**M3. Tests never exercise the states the stuck rule depends on, nor the real order of a pause**
- Location: tests/13-wait.sh:12-16 (fake systemctl), 82-92
- Failure path / evidence: the fake prints only what a file holds and never returns `activating`, `deactivating`,
  `elapsed` (SubState), an empty string or a non-zero exit, so H2 and M1(b) are invisible to the suite. The paused-cap
  check flips the unit to inactive *before* the status ("unit first: running or paused-cap, both are stuck", line 84),
  so it proves the unit-inactive path, not "returns on paused". The runner's real order is the reverse: `cp_set_status
  paused-cap` then `chain_end 6` (lib/chain.sh:202), and `usage_pause` writes `paused-limit` while the unit is still
  `active` (lib/usage.sh:47-49). No scenario asserts that a status flip from running to paused-limit or paused-cap with
  the unit still `active` returns 11. `blocked` is only tested "already at start", never as a transition. The
  `deactivating`-is-stuck branch (`deactivating*`) has no test at all.
- Fix: add scenarios: running→paused-limit with unit active and timer inactive → 11; running→paused-cap with unit
  active → 11, then unit inactive → 12; unit `deactivating`, timer inactive → 12; unit `activating` → no stuck; timer
  `elapsed` → 12 (after H2); fake systemctl exiting 1 → no exit 1 (after M1).

#### LOW

**L1. The machine-sleep test proves only that wait does not call `date` from PATH**
- Location: tests/13-wait.sh:110-129
- Failure path / evidence: wait calls no `date` anywhere on its path (job_init, chain_count, wait_snap: no `log`),
  so the fake `date` (lines 118-122) is never invoked. The scenario reduces to "wait keeps blocking over 5 polls with
  no change", which `blocks` already proves. A mutant that times out with bash's own clock (`$SECONDS`,
  `$EPOCHSECONDS`, `printf '%(%s)T'`) passes it. The property holds by construction (no clock read), so this is a
  proof-strength note, not a bug. Separately, the runner's `child_wait` measures with `$SECONDS` (wall clock,
  lib/child.sh:69-72), so a suspend longer than `JOB_CHILD_TIMEOUT` kills the child on wake and launches the next one.
  wait will then report a real `changed`, caused by the sleep. That meets the letter of "a machine sleep does not
  count as a change" (wait doesn't count it, the runner makes one), but not necessarily its intent.
- Fix: say in the test comment that the property is structural (no clock reads), or add a grep assertion that
  `unit_wait`/`wait_snap` contain no `date`, `SECONDS` or `EPOCHSECONDS`. Raise the `child_wait` wall-clock behaviour
  with the owner as its own question (see open questions).

**L2. Race: the unit is read before the timer, so a timer-driven resume can read as stuck for one poll**
- Location: lib/units.sh:121-122 vs lib/units.sh:66-67
- Failure path / evidence: `unit_resume` runs `unit_start` (unit goes active) and then stops the timer. If wait reads
  the unit just before the start and the timer just after the stop, the snapshot is `unit inactive · timer inactive`
  with `status: paused-limit …` → 12 "stuck" on a job that just resumed. The window is narrow: both resume steps have
  to fall between wait's two systemctl forks. The current order is the right one for the opposite race
  (usage_pause arms, then exits), so no fixed order closes both.
- Fix: debounce `stuck`. When a snapshot looks stuck mid-watch, take one more snapshot after a poll and return 12
  only if it is stuck again. That also absorbs M1-style one-off reads.

**L3. Status is read before the unit, so a stuck line can show a stale status**
- Location: lib/units.sh:119-124
- Failure path / evidence: checkpoint.md is read first, the unit last. When the runner sets `paused-cap` and exits 6
  between those reads, the line says `wait: stuck · status: running · … · unit inactive`. The exit code is the same
  (12), but the line, which the watcher acts on, names the wrong cause (crash instead of pause). A re-read gives the
  right line.
- Fix: read the unit and timer first and checkpoint.md last, or re-read the status when the snapshot is stuck (the
  L2 debounce does both).

**L4. Every systemd transition is a "change", so one resume wakes the watching session up to three times**
- Location: lib/units.sh:125 (`unit $WAIT_UNIT · timer $WAIT_TIMER` in SNAP); README.md:107
- Failure path / evidence: issue 14 lists status, phase, child number "or the unit goes inactive". SNAP includes the
  raw unit and timer states, so a timer-driven resume yields: unit inactive→activating/active (11), timer
  active→inactive when resume stops it (11), status `paused-limit …`→`running` when chain_run takes the lock (11),
  within seconds. Each return is a Claude turn, the cost the issue exists to cut. Rare (only around pauses), hence
  LOW.
- Fix: compare only status, phase, child and a coarse "runner up / down / scheduled" bit, and keep the raw states in
  the printed line.

**L5. Events between two waits are lost; the new wait's baseline is whatever it reads first**
- Location: lib/units.sh:103 (`wait_snap; was="$SNAP"`)
- Failure path / evidence: after wait returns 11, the session takes a turn before it starts the next wait. A child
  launch or phase change in that gap becomes the new baseline and is never reported. Final and stuck are still
  caught at start, so nothing is lost for good. A watcher that logs progress ("child 6 launched") skips steps.
- Fix: optional `wait <job-dir> [<previous line>]` that compares against the last printed snapshot, or just say in
  the README that intermediate changes can be coalesced.

**L6. `BLAST_OFF_WAIT_POLL=0` (or tiny) turns wait into a busy loop of two systemctl calls and five forks per spin**
- Location: lib/units.sh:111
- Failure path / evidence: `sleep "${BLAST_OFF_WAIT_POLL:-5}"` accepts 0; the loop then forks `cat`, `sed` x3 and
  `systemctl` x2 continuously for hours. The test uses 0.1, which is fine.
- Fix: clamp to a floor (e.g. 1 s outside tests), or validate once (shares M1's fix).

**L7. The common outcome (11, changed) is a non-zero exit; a harness may show each return as a failed command**
- Location: lib/units.sh:110; SKILL.md:70-71
- Failure path / evidence: the issue fixes only "exit 0 on a terminal status". With 11 for the routine "something
  moved", most wait returns surface as a failed background command. A session that skims the exit code rather than
  the line may start debugging a healthy job. The SKILL text explains 11, which mitigates this.
- Fix: none required. Owner's call whether `changed` should be 0 too, with final told apart by the line, at the cost
  of the issue's "exit 0 on a terminal status" being the only meaning of 0.

**L8. Foreground `blast-off run`, or a job run with its own workdir, reads as `stuck` at once (Q2)**
- Location: lib/units.sh:106-108; bin/blast-off:70 (`job_init "${2:-}"`, default workdir); README.md:111
- Failure path / evidence: wait derives `UNIT` from the job dir's parent. A foreground `run` has no unit → 12
  immediately. `run <job> <workdir>` has a different unit and lock name, so wait stays at 12 for the whole job. The
  README documents the first case; the second is not mentioned. The SKILL calls wait *the* way to watch a job without
  that caveat.
- Fix: accept Q2's default but add one line to SKILL step 8: "jobs started with `start` only". A runner-alive check
  via the lock file (`$XDG_RUNTIME_DIR/$UNIT.lock` + `pid_start`, already in lib/chain.sh) would cover the
  default-workdir foreground case in a few lines if the owner wants it.

### Open questions for the owner

1. When the child writes `status: done`, should wait return 0 at once, or only after the runner exits and its
   run.log says `job done` (H1)? Today a done the runner refuses (exit 7/9/10) is reported as done, and every later
   wait says so at once.
2. Should an elapsed resume timer (fired, resume failed) count as stuck (H2)? Please confirm on a real box that its
   `ActiveState` stays `active` after a failed `blast-off resume`.
3. Q1: should `paused-cap` keep exit 12, or get its own code, so "resume" and "investigate a crash" are separable
   without parsing the line (M2)?
4. Q2: is "jobs started with `start` only" acceptable as a documented limit, including jobs run with their own
   workdir (L8)?
5. Outside this diff: the runner's `child_wait` times children by `$SECONDS` (wall clock), so a suspend longer than
   `JOB_CHILD_TIMEOUT` kills the child on wake. Is that intended, given issue 14's "machine sleep is not a stall" (L1)?
