# silent-failure-hunter: phase 6 (issue 14), round 1

### Summary

Static review of `git diff 62eeb5c...b010b90` (lib/units.sh `unit_wait`/`wait_snap`, bin/blast-off dispatch,
tests/13-wait.sh, docs). Nothing was run. The poll loop is small and mostly right: no `grep` under `set -e`, no
`local v=$(...)` masking, `child-count` is written by rename (`chain_count_set`, lib/chain.sh:137) so `?` cannot flap
from the runner's own writes, and the issue-14 criteria (child launch, phase change, done, unit inactive, missing dir,
clock jump) each have a test a mutant kills.

Two paths give the watcher a wrong answer that never corrects itself:

- **H1:** `final` fires on `status: done` while the runner is still checking that done (receipts, CI). A refused done
  (exit 9 or 10) leaves `status: done` in the file, so every later `wait` says `final` too.
- **H2:** a resume timer that has fired stays `ActiveState=active` (substate `elapsed`). When its `resume` fails, or a
  stale one is left behind, the stuck rule never fires and `wait` blocks forever. That is the hang issue 14 set out to remove.

The MEDIUM findings are exit-1 aborts that the docs say mean "fix the path": a `systemctl` failure under `set -e`, a
bad `BLAST_OFF_WAIT_POLL`, or a checkpoint that is briefly empty. Also: a race between the two `systemctl` reads that
can produce a false `stuck`, and a fake `systemctl` too thin to catch H2 or M1.

Counts: CRITICAL 0 · HIGH 2 · MEDIUM 5 · LOW 9.

### Findings

#### CRITICAL

None.

#### HIGH

**H1. `final` (exit 0) on `status: done` before the runner accepts done; a refused done reads as `final` forever**
- Location: lib/units.sh:105 (`case "$WAIT_STATUS" in done|blocked) ... exit 0`); tests/13-wait.sh:64 (`ck status "done"` with the unit `active` expects 0).
- Failure path / evidence: a child writes `status: done`, and the runner then goes to lib/chain.sh:194 (`ci_plan;
  receipt_all_done; ci_check; chain_end 0`). Those can end in `chain_end 9` (lib/receipt.sh:53-70: no sha, no PASS
  receipt, code changed after the sha, an open row) or `chain_end 10` (lib/ci.sh:62-134: CI red, unread or absent, a
  Status cell it cannot read). Neither path rewrites the status: `cp_set_status` is never called, so checkpoint.md
  keeps `status: done`. Meanwhile `wait` has already printed `wait: final · status: done ...` and exited 0 while the
  unit was still `active`. README:106 says "stop watching; read checkpoint.md", and checkpoint.md says done. The
  refusal is only in run.log and the journal. Running `wait` again gives `final` again, forever, so the session tells
  the owner the job is done when CI is red or a receipt is missing. The phase notes rest on a false premise:
  phase-6/findings.md:29 lists "a runner exit 1/4/5/7/9/10 (status stays running)", but for 9 and 10 the status stays
  `done`. The test at 13-wait.sh:63-65 locks the premature `final` in.
- Fix: treat `done` as final only once the runner has finished with it, meaning the unit is not active or activating.
  Then tell an accepted done from a refused one: run.log's last line is `job done` (lib/chain.sh:194 `chain_end 0
  "job done"`), and anything else is a refusal. Report a refusal as `stuck` (12) and print run.log's last line. While
  the unit is still active with `done`, keep polling. `blocked` can stay as it is (chain_end 3 does not check
  anything first). Add a test with status `done` and the unit active: `wait` blocks. Unit goes inactive with run.log
  ending `job done`: exit 0. Unit goes inactive with a refusal line: exit 12.

**H2. A fired resume timer stays `active` (`elapsed`), which masks `stuck` and makes `wait` block forever**
- Location: lib/units.sh:106-107 (`*' active') ;;`, checked before the stuck patterns) and :122 (only `ActiveState` is read).
- Failure path / evidence: systemd maps a timer's `elapsed` state to `ActiveState=active` (timer.c state table:
  WAITING, RUNNING and ELAPSED all map to UNIT_ACTIVE). `RemainAfterElapse=` defaults to yes, so the transient
  OnCalendar timer from `usage_arm` (lib/usage.sh:70) stays `active` after it fires until someone stops it. Only a
  successful `unit_resume` stops it (lib/units.sh:67, and that `stop` is `|| true`), or `unit_stop`, or a new
  `usage_arm`. Paths where the timer has fired and nothing will move:
  1. The timer fires and `blast-off resume` fails. It can exit 1: `systemd-run` refuses because the old unit is still
     loaded after the 90 s loop, or `unit_check` fails, or the status is not `paused-*`. Or it can exit 8 when `until`
     is still ahead. The timer is not stopped (the `exit 1` at units.sh:66 comes before :67). The state is now
     `paused-limit`, unit `inactive`, timer `active (elapsed)`. `"inactive active"` matches `*' active'`, the snapshot
     never changes, and `wait` blocks forever.
  2. The owner runs `blast-off start` on a `paused-limit` job after `until` but before the timer fires (it fires at
     reset plus `JOB_RESUME_MARGIN`, default 60 s). chain_run sets `running` (lib/chain.sh:183) and does not stop the
     timer. The timer then fires, and `resume` dies with "status is 'running'" (units.sh:56). From then on every crash
     or exit 1/4/5/7 with `status: running` reads as "unit inactive, timer active", which is not stuck, so `wait`
     blocks forever. `blast-off stop` clears this (units.sh:85), but a crash does not.
  3. The `systemctl --user stop "$UNIT.resume.timer" ... || true` at units.sh:67 fails silently. The result is the
     same as path 2.

  README and the spec say no `wait` timeout exists ("the caller's background command has one"). A Claude Code
  background command does not time out by default, so in practice it is never woken: the issue-14 failure in a new form.
- Fix: count a timer as "scheduled" only when its `SubState` is `waiting` or `running`, read with
  `systemctl --user show "$UNIT.resume.timer" -p ActiveState,SubState`. Better still, also require the status to be
  `paused-limit` before the timer counts at all. Add a test whose fake reports the timer as active/elapsed with the
  unit inactive and status `paused-limit`, expecting 12. Separately, unit_resume should stop the timer on its failure
  paths too, but `wait` must not depend on that.

#### MEDIUM

**M1. A `systemctl` failure aborts `wait` under `set -e` with exit 1 and no `wait:` line, and the docs map exit 1 to "fix the path"**
- Location: lib/units.sh:121-122 (`WAIT_UNIT="$(systemctl ...)"`, a bare assignment run with `set -euo pipefail` from bin/blast-off:43).
- Failure path / evidence: a bare assignment takes the status of its command substitution, so `set -e` fires. Checked:
  `bash -c 'set -euo pipefail; f(){ X="$(false)"; echo after; }; f; echo end'` gives rc 1 and prints nothing. When the
  user bus is unreachable (no `XDG_RUNTIME_DIR`/`DBUS_SESSION_BUS_ADDRESS` in the background command's env, the user
  manager restarting, a D-Bus call timing out after its 25 s default under load), `wait` exits 1. That can happen on
  the first poll or hours into a watch. Only systemctl's own stderr comes out ("Failed to connect to bus ..."). README:109
  says exit 1 means "no job dir or no checkpoint.md | fix the path", and SKILL.md step 8 (:70-72) does not mention
  exit 1 at all. The watch ends with a wrong diagnosis, and an agent that re-runs `wait` on any unknown code would loop
  hot. No `timeout` wraps these calls. The `timeout 10`/`timeout 30` wraps exist only in the test (13-wait.sh:35, 96-108).
- Fix: read both units in one call, e.g. `systemctl --user show A B -p ActiveState,SubState`, with an explicit `||`.
  On failure, print `wait: error · systemctl: <msg>` and exit a separate code such as 13, documented in README,
  spec §2 and SKILL.md. Retrying the next poll is another option.

**M2. The two `systemctl` reads are not one snapshot, so the resume handoff can produce a false `stuck`**
- Location: lib/units.sh:121-122 (the unit is read, then the timer), against lib/units.sh:66-67 (resume starts the unit, then stops the timer).
- Failure path / evidence: the timer fires and `resume` runs. `wait` reads the unit as `inactive` (before
  `systemd-run`). `resume` then starts the unit and stops the timer. `wait`'s second `systemctl` reads the timer as
  `inactive`. The snapshot is `paused-limit`, unit inactive, timer inactive, so `wait` prints `stuck` and exits 12 on
  a job that is now running. The window is two fork/exec+D-Bus round trips wide, so it is narrow but real over many
  hours of 5 s polls. Swapping the read order only moves the race to the pause transition (usage_pause arms the timer,
  then the runner exits). The checkpoint is read even earlier, so the status can be stale against both unit reads, as
  with `running` printed beside a `paused-cap` exit. That case gets the right code but a misleading line.
- Fix: debounce `stuck`. On a stuck snapshot, sleep one poll, take a fresh snapshot, and return 12 only if it is still
  stuck. `stuck` "never changes on its own" by definition, so confirming it costs one poll. Reading both units in one
  `systemctl show` call (M1) narrows the window as well.

**M3. A briefly empty or missing checkpoint.md mid-watch ends `wait` with exit 1 "missing checkpoint.md"**
- Location: lib/units.sh:119 (`cat ... && [ -n "$cp" ] || die "missing $JOB/checkpoint.md"`, run at every poll).
- Failure path / evidence: the runner's own writes are atomic (`sed -i` writes a new file and renames it, at
  lib/checkpoint.sh:118 and 139). The children's are not guaranteed to be: a child that rewrites the checkpoint with
  a shell redirect (`cat > checkpoint.md`), or an editor/tool that truncates and then writes, leaves the file empty
  for a moment. A poll that lands there dies with exit 1 and "missing", although the file exists. README:109 says
  "fix the path", so the watch ends on a healthy job. A truncated read that still has the `status:` line but lacks
  `phase:` only produces a spurious `changed` (11), which is harmless. The test covers a missing file only at start
  (13-wait.sh:104-108).
- Fix: die only on the first snapshot (before blocking). Mid-watch, treat an unreadable or empty checkpoint as
  "no change this poll" and die only if it persists for several polls (or not at all, letting `stuck` take over). Say
  "empty" when the file exists.

**M4. `BLAST_OFF_WAIT_POLL` is not validated: garbage aborts with exit 1, `0` busy-loops, `inf` never polls again**
- Location: lib/units.sh:111 (`sleep "${BLAST_OFF_WAIT_POLL:-5}"`).
- Failure path / evidence: `bash -c 'set -euo pipefail; sleep abc; echo after'` prints "invalid time interval" and gives
  rc 1. So `BLAST_OFF_WAIT_POLL=5s0` or `=abc` checks the first snapshot and then dies with exit 1, which README reads
  as a path error. `=0` re-runs `cat`, 3x `sed`, `chain_count` and 2x `systemctl` with no pause: a CPU and D-Bus storm
  against the user manager for the whole watch. `=inf` or a huge value means the first snapshot is the only one, so
  `wait` blocks forever. Every other numeric knob is refused up front (`chain_nums`, lib/chain.sh:146).
- Fix: validate once in `unit_wait` against something like `^([1-9][0-9]{0,4}|0?\.[0-9]*[1-9][0-9]*)$` with an upper
  bound, and `die` with the variable named, before the first snapshot.

**M5. The test's fake `systemctl` is too thin to catch H2, M1 or a dropped `--value`**
- Location: tests/13-wait.sh:12-16 (the fake ignores every argument but `$3`, always exits 0, and knows only an ActiveState word).
- Failure path / evidence: the fake prints the file's word whatever the `-p` and `--value` arguments are. If
  `--value` were dropped from units.sh:121-122, real systemd would print `ActiveState=inactive`, which matches none of
  the case patterns. `stuck` would then never fire in production while every 13-wait check still passed. The fake
  cannot model a timer's SubState (`elapsed`, H2) or a bus failure (M1), so neither can have a test. Every unit-state
  check in the scenario therefore asserts against the fake's contract, not systemd's.
- Fix: make the fake check its arguments. Fail loudly unless it gets `--user show <unit> -p <props> --value`, and print
  per-property lines the way systemd does when several `-p` are given. Add a "fail" mode (exit 1 plus a stderr line)
  and a SubState file, then add tests for H2 and M1.

#### LOW

**L1. The stuck rule is a deny-list: an unlisted or empty unit state never counts as stuck**
- Location: lib/units.sh:106-109.
- Failure path / evidence: only `inactive*|failed*|deactivating*` are stuck. Any other value falls through to "not
  stuck": `activating`, `reloading`, `refreshing` (systemd 253+), `maintenance` (systemd 250+), or an empty string
  from a `systemctl` that printed nothing with rc 0. If that value persists, `wait` blocks forever. `Type=exec` with
  no `Restart=` (systemd/blast-off@.service) makes `activating` brief today, so the risk is small.
- Fix: invert the rule. The job is running or scheduled only when the unit is `active|activating|reloading|refreshing`
  or the timer's SubState is `waiting|running` (H2). Everything else, including empty output, is stuck.

**L2. A garbled `child-count` hides every child launch as `child ?` and drops the reason**
- Location: lib/units.sh:120 (`if chain_count; then c="$LAUNCHED"; fi`; `COUNT_ERR` is thrown away).
- Failure path / evidence: the runner writes by rename (lib/chain.sh:137) and refuses a garbled file at start
  (chain.sh:148), so `?` mid-run needs an outside writer. If that happens, child launches stop showing up as changes
  and the line never says why. No false wake from flapping was found.
- Fix: print `child ?` plus a pointer to `blast-off status` when `COUNT_ERR` is set, or fold `COUNT_ERR` into the line
  once (it is already content-safe, P5R1-5).

**L3. A free-text edit to the `status:` or `phase:` line wakes the watcher**
- Location: lib/units.sh:125 (SNAP holds the whole `status:` and `phase:` lines).
- Failure path / evidence: a child that rewrites `phase: 2 of 5 — build (step 3/7)` every step, or adds notes after
  `status: running`, triggers an 11 each time. Each wake costs the watching session tokens, which is the cost issue 14
  complains about. It is bounded by child activity, not by the clock.
- Fix: decide (owner question Q-c). Either compare the status word plus the phase's `<n> of <N>` only, or keep the
  whole line as the spec now says.

**L4. Nothing tests that a status-only change returns 11; dropping the status line from SNAP survives the suite**
- Location: tests/13-wait.sh (every status change it makes goes to `done` or comes together with a unit change, or is
  made before `wait` starts).
- Failure path / evidence: `done` returns through `WAIT_STATUS`, not SNAP. In the `pl` case the status is set before
  `bw`. If `$s` were removed from SNAP at units.sh:125, `running -> paused-limit` with the unit still active would not
  wake, and no test would fail. README:107 promises "the phase or status moved".
- Fix: with the unit active, start `wait`, `ck status 'paused-limit until 2099-...'`, and expect 11.

**L5. `blocks()` assumes `wait` has taken its first snapshot within 1 s**
- Location: tests/13-wait.sh:37.
- Failure path / evidence: on a loaded box (the gate runs scenarios with other load), `blast-off` sourcing 10 libs
  and its first `systemctl` calls can take longer than 1 s. The state change then lands before the first snapshot.
  For `c`/`p` the test fails falsely ("did not return"). For `d`, `g` and `pc`, the "on the change" check quietly
  becomes the "already there at start" check and passes without testing the transition.
- Fix: before changing state, wait until `wait` has polled at least once. For example, have a fake `sleep` touch a
  marker (as the clock case does) and `wait_until` that marker.

**L6. The machine-sleep test only catches a clock read through `date`**
- Location: tests/13-wait.sh:110-129.
- Failure path / evidence: the fake `date` intercepts only `date`. A future stall detector using `$EPOCHSECONDS`,
  `$SECONDS`, `printf '%(%s)T'` or `/proc/uptime` would see real time (about 0.25 s across the polls) and the test
  would pass while `wait` is clock-dependent again. The code calls no clock today, so this is only a gap in the guard.
- Fix: also assert that `unit_wait`/`wait_snap` contain no `date|EPOCHSECONDS|SECONDS|%(` (a grep in 70-docs or in
  13-wait), or accept the gap.

**L7. SKILL.md step 8 names only 11, 0 and 12**
- Location: skills/blast-off/SKILL.md:70-72.
- Failure path / evidence: an agent following the skill has no instruction for exit 1 (path, or today any M1/M3/M4
  abort) or 124/137 (its own wrapper's kill). The likely behaviours are re-running `wait` in a loop or reporting
  "stuck".
- Fix: add "any other code: stop and show the owner the output", and the new error code if M1 adds one.

**L8. An empty checkpoint.md is reported as "missing"**
- Location: lib/units.sh:119.
- Failure path / evidence: `[ -n "$cp" ]` fails on a zero-byte file that exists, and the message says `missing`. No
  test covers an empty file, although README:109 and the phase notes say "no/empty".
- Fix: give the two cases separate messages, and add a test for the empty file.

**L9. Background waits can outlive a killed scenario**
- Location: tests/13-wait.sh:22-23, 35.
- Failure path / evidence: `stop_bg` runs from the EXIT trap. If `tests/run` kills the scenario with SIGKILL, the
  trap does not run and each live `bw` lingers until its `timeout 30`, writing `*.rc` into a temp dir that may already
  be deleted. `pkill -P` reaches only the `timeout` child. The `sleep 0.1` inside a killed `blast-off` is orphaned but
  ends on its own. All of this is bounded and leaves no lasting state. Information only.
- Fix: none needed. Optionally use `timeout -k 1 30` and a shorter bound.

### Open questions for the owner

- Q-a (H1): should `wait` report `final` only after the runner has accepted done, with a refused done (exit 9/10,
  status still `done`) reported as `stuck` plus run.log's last line? Or should the runner rewrite the status on a done
  refusal, for example to `running` or a new `refused` word, so every reader, `wait` included, sees it?
- Q-b (H2): should the resume timer count as "scheduled" only when its SubState is `waiting`/`running` and the status
  is `paused-limit`? Should `unit_resume` also stop the timer on its failure paths, and `start`/chain_run stop a
  pending one when they move `paused-limit` to `running`?
- Q-c (L3): should a wake on any edit to the `phase:` line's free text stay, or should `wait` compare only the status
  word and the `<n> of <N>`?
- Q-d (M1): should a `systemctl` error get its own exit code (e.g. 13) or be retried silently for a few polls?
- Q-e (Q2 ruling follow-up): a foreground `run` reads as `stuck`, and the advice printed is `start`. That start is
  refused by `chain_lock` (exit 1), so it is harmless. Should the stuck line add "or a foreground run holds the lock"
  when `$XDG_RUNTIME_DIR/$UNIT.lock` names a live pid? That is cheap, and it removes the misleading advice.
