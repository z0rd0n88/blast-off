# Review: phase 6 (issue 14, `blast-off wait`), round 3 (final allowed round)

This round reviews the fix diff `git diff 06d9de1..b917cec -- . ':!baton-runner'` (round-2 fixes: `runner-end`, the
10 s and 60 s limits, docs), read against the phase diff `git diff 62eeb5c...b917cec -- . ':!baton-runner'`. Two
static reviewers wrote `review-phase-6-iter-3/{code-reviewer,silent-failure-hunter}.md`. The review unit then checked
the concrete claims: one probe of `mv -f` onto a directory named `runner-end`, and greps of the tests and docs.

## Executive summary

- Gate: `scripts/gate.sh` exited 0. Last line: `GATE: PASS passed=19 failed=0 shellcheck=ok`
  (`gate-phase-6-iter-3/tests-run.log`). It ran once, alone, before any reviewer. ExecStart read the build worktree's
  line before the gate, after it, and at the end.
- The owner rulings hold in the code, and both reviewers confirm it independently:
  - `runner-end` is written only at `lib/chain.sh:199-200`, after every gate. Every refusal (exit 7, 9 or 10, die, a
    set -e abort) exits before it.
  - A failed write aborts under set -e with no file. `chain_run` is only ever called plainly (`bin/blast-off:71`).
  - The clear at `:166` comes after `chain_lock`, so a second runner refused by the lock never deletes the file.
- What is still weak is the edges of the file's lifetime:
  - A re-run of an accepted done or blocked job keeps the old `runner-end` until it passes the lock, and keeps it for
    good if it dies before the lock. A `wait` in that window reads `final` (P6R3-1). The fixer chose this for the
    die-before-lock case. The race on `start` is new to this review.
  - The lock-side placement of the clear has no test (P6R3-5).
- No CRITICAL or HIGH. No regression found in other scenarios. The 0/11/12/1 contract in the code matches
  `bin/blast-off`, the README, the spec and SKILL step 8. Several doc details are off (P6R3-11, -12, -14).
- 0 CRITICAL, 0 HIGH, 1 MEDIUM, 13 LOW.

**VERDICT: CLEAN** (gate exit 0, no CRITICAL or HIGH, every issue-14 criterion has a passing test). This was the last
allowed round. The open items go to a follow-up issue (list at the end).

## Issue-14 criteria -> tests (all in `tests/13-wait.sh` unless noted, PASS in the gate)

| Criterion | Test (line) | Note |
|---|---|---|
| Returns on child launch | 72-74 (`ends c 11 'child 1'`) | |
| Returns on phase change | 80-82 (`ends p 11 ...`) | |
| Returns on done | 102-108: holds on an unaccepted done and on a forged run.log line, then 0 once runner-end says done. 111: already done. 113: word mismatch -> 12. 115: refused done -> 12. `tests/10-chain-done.sh`: runner-end written on accept, absent after a refusal | the ruling's done half |
| Returns on blocked | 118-122: holds on an unaccepted blocked, refused -> 12. 124: already blocked -> 0 | P6R2-5 closed |
| Returns on paused | paused-cap 140-143 (12). paused-limit with a timer 146-148 (11). No timer 150 (12). Status-only change 154-156 (11) | |
| Returns when the unit goes inactive | 128-136 (`inactive`, `failed`, `deactivating`). `activating` 160-162 is not stuck. Handoff 167-179 is not stuck | P6R2-8 closed |
| Missing job dir: non-zero with a reason | 186 and 190 at start. Mid-watch 233-239 (12 after 60 s, with the reason) | P6R2-2 closed |
| Machine sleep is not a change | 242-261 | clock-based kill only (P6R1-12, open) |
| Devil's advocate: unit gone, status running | 128-130 (stuck line names `blast-off status`) | fake systemctl only (P6R1-13, open) |

## Critical

None.

## High

None.

## Medium

**P6R3-1. A stale `runner-end` reads as `final` while a re-run starts up, and for good if that re-run dies before
the lock**
- Reported by: code-reviewer MEDIUM-1 (MEDIUM), silent-failure-hunter LOW-2 (LOW). Review unit: MEDIUM.
- Location: `lib/chain.sh:144-166` (DEPS, brief, checkpoint, `chain_nums`, `chain_count`, `chain_lock`, then the
  `rm`); `lib/units.sh:112`; `lib/units.sh:28-46` (`start` checks neither the status nor the counts).
- Failure path, the race:
  1. A job ended with an accepted done, so `runner-end` reads `done <utc>`.
  2. With the status still done, a session runs `blast-off start J` and then `blast-off wait J`, for example to
     re-check CI after a push.
  3. The runner unit is up, but it has not reached line 166 yet.
  4. `wait`'s first snapshot reads the status done and the old file, so it prints `final` and exits 0.
  5. The new run then refuses the done (exit 9 or 10).
- Failure path, death before the lock: the re-run exits 1 before the lock (a garbled `child-count`, a bad `JOB_*`, a
  missing dependency). The old end stays, and every later `wait` reads final.
- Why MEDIUM: the ruling says the end is "cleared at the start of every run". For a re-run, final can stand for a done
  the latest run never checked. The fixer judged the die-before-lock half acceptable ("the job is unchanged, so that
  end still holds"). That holds for checkpoint.md, not for HEAD or CI, which a re-run exists to check again. The race
  needs a re-run of a finished job plus a poll inside the startup window, so it is not HIGH.
- Fix options:
  - (a) In `unit_start`, `rm -f "$JOB/runner-end"` before `systemd-run`, only when the unit's ActiveState is inactive
    or failed (code-reviewer).
  - (b) Write `$INVOCATION_ID` into the file, and count it final only when it matches the unit's `InvocationID`, or
    when the unit is not active (code-reviewer).
  - (c) Trust the file only when its mtime is after the unit's `ExecMainStartTimestamp` (silent-failure-hunter).
  - Or document the window. The spec text is P6R3-11 either way.

## Low

**P6R3-2. A child can write `runner-end` itself, and a refused run never clears it**
- Reported by: code-reviewer LOW-3, silent-failure-hunter LOW-1.
- Location: `lib/chain.sh:10`, `:166` (cleared once per run, not per child); `lib/units.sh:112`.
- A child writes `done x` to `$JOB/runner-end` and sets status done. `wait` exits 0, the runner refuses (9 or 10), and
  the file stays until the next run passes the lock. This is the same class as P6R2-1, but it needs a deliberate
  write to that exact name, as the same uid. Fix: `rm` at the top of each loop pass (still after the lock), and/or in
  `chain_exit` on any exit that is not an accept.

**P6R3-3. A `runner-end` that is not a regular file fails silently, for good, or blocks wait forever**
- Reported by: silent-failure-hunter LOW-4. Reproduced by the review unit: `mv -f runner-end.tmp runner-end` onto a
  directory returns 0 and moves the tmp into it; `cut` then fails (rc 1, hidden by `2>/dev/null`).
- Location: `lib/chain.sh:10`, `:166`; `lib/units.sh:112`.
- The three cases:
  - A directory created mid-run: an accepted done reads stuck with no reason.
  - A directory there at a run's start: `rm -f` fails, so every run aborts with exit 1, and run.log names no cause.
  - A FIFO: `cut` blocks forever, outside the 60 s read limit.
- Fix: `mv -fT`. In `wait`, read only a regular file, with `read -r w _ <`.

**P6R3-4. The 10 s and 60 s limits use the wall clock**
- Reported by: code-reviewer LOW-4, silent-failure-hunter LOW-5.
- Location: `lib/units.sh:117`, `:120`, `:131-132`.
- A backward step of N s (NTP, a WSL2 resync) delays stuck and the read limit by N s, with no output. A forward step
  can read stuck on the second down poll, during a resume handoff (the P6R1-3 hazard). Fix: clamp
  (`[ "$now" -ge "$down" ] || down=$now`, the same for `bad`), or use `/proc/uptime`, or add a `ponytail:` note naming
  the ceiling.

**P6R3-5. The clear's placement is not pinned in either direction**
- Reported by: code-reviewer LOW-2, silent-failure-hunter LOW-6; the fixer's notes say so too. The review unit
  checked: `tests/23-runner-lock.sh` never mentions `runner-end`.
- Location: `lib/chain.sh:166`; `tests/23-runner-lock.sh:9-21`; `tests/10-chain-done.sh:46-56`.
- Two mutants survive:
  - The `rm` moved above `chain_lock`. Real failure: a runner refused by the lock (while the accepted runner's EXIT
    trap still holds it) deletes the end, and `wait` reads stuck.
  - The `rm` moved later, anywhere before `ci_check`. Test 10's only re-run is refused at the last gate, so an
    accepted blocked re-run and refused early (7, 9, 8) would keep its stale end.
- Fix: in test 23, write `runner-end` before the second `run` and assert it is unchanged. Add a re-run refused before
  child 1, and assert there is no `runner-end`.

**P6R3-6. The threshold values are not pinned by 13-wait**
- Reported by: code-reviewer LOW-5.
- Location: `tests/13-wait.sh:57-67`, `:172-179`, `:210-239`.
- 10 s changed to about 2-9 s or 11-40 s, and 60 s changed to about 40-150 s, survive. Fix: at step 1, assert that
  wait still blocks at skew 9 and returns by 11, and the same at 59 and 61.

**P6R3-7. The retry test has about 0.5 s of margin**
- Reported by: code-reviewer LOW-6.
- Location: `tests/13-wait.sh:221-227`.
- The good read has to land within about 5 failed polls of the 35 s mark of a 60 s spell, so the test may flake under
  load. Fix: three spells of about 25 s.

**P6R3-8. No test covers odd `runner-end` content**
- Reported by: silent-failure-hunter LOW-7.
- Location: `tests/13-wait.sh:100-124`.
- Every case comes from `rend`, so a prefix-match mutant survives. Fix: one case, `donex` with status done and the
  unit down, expecting 12.

**P6R3-9. `runner-end` can exist with no `job done` line**
- Reported by: code-reviewer LOW-7.
- Location: `lib/chain.sh:199-200`, `:6`; `docs/spec.md:46-47`.
- A TERM between `chain_accept` and `chain_end` leaves the file, `runner exit 143 without a state` in run.log, and
  `wait` reads final. The fixer accepted this, but the spec reads as if the line always follows. Fix: one sentence in
  the spec.

**P6R3-10. A job ended by a runner older than this change reads stuck**
- Reported by: code-reviewer LOW-8.
- Location: `lib/units.sh:112`; README Watch.
- A runner already running keeps its loaded code and writes no `runner-end`. Jobs that ended before the change have
  none either. `wait` gives 12 with `see blast-off status`, which reads like a refusal. Fix: one line in the README
  and SKILL, or accept it as a one-time migration.

**P6R3-11. The spec and README overstate when `runner-end` is absent**
- Reported by: silent-failure-hunter LOW-3. Checked: `docs/spec.md:47` says "deleted at the start of every run".
- Location: `docs/spec.md:45-49`; `README.md:109`, `:112`.
- What the docs get wrong:
  - Runs that exit before the lock do not delete it.
  - A re-opened job keeps it until the next run passes the lock.
  - Refusals also include exit 1 and signals, not only 7, 9 or 10.
- Fix: "deleted by every run that takes the lock"; refusals are "any exit but 0 and 3".

**P6R3-12. Small doc inaccuracies**
- Reported by: code-reviewer LOW-9. Checked: `README.md:104` says "at most 40 more".
- Location: `README.md:104`; `docs/spec.md:59`, `:239`; `tests/13-wait.sh:132`.
- The four details:
  - The `until` part can be up to 47 characters (" until " plus 40), not 40.
  - The phase line's `·` becomes `-`, where the docs say it is lost.
  - The 13-wait row still says "without ... ` · `".
  - "Not at once" for an already-stuck job is not asserted (g2 checks only the exit code).

**P6R3-13. A failed `date` mid-watch exits 1 with no line**
- Reported by: silent-failure-hunter LOW-8.
- Location: `lib/units.sh:117`, `:131`.
- set -e on `now="$(date +%s)"` exits with no stdout line, while 1 is documented as "cannot start watching". This is
  contrived. Fix (optional): a stuck line on failure.

**P6R3-14. The docs give the limits in seconds, but a large poll stretches them**
- Reported by: silent-failure-hunter LOW-9.
- Location: `README.md:112-113`; `docs/spec.md:59`, `:112-115`; `bin/blast-off:44-47`.
- At `BLAST_OFF_WAIT_POLL=3600`, "no read for 60 s" fires after 3600 s. Fix: "60 s (at least one poll)".

## Carried over, not re-filed

- P6R2-12 (the stuck line gives no reason) now covers an unreadable `runner-end` as well. silent-failure-hunter
  judges it no worse than before.
- Still open from earlier rounds, untouched by this fix:
  - P6R2-6, -7, -12, -13, -14, -15 (partly covered now), -16, -17, -18
  - skill-sheriff P6R2-S1..S3
  - P6R1-9, -12, -13, -14, -18, -19
  - the earlier LOWs

## Process

- The code-reviewer subagent wrote three scratch copies of repo text into the session scratchpad root (`chain_tail.txt`,
  `t13a.txt`, `t13b.txt`), against its brief. No repo file was touched. They are outside the review unit's own
  subfolder, so the review unit left them in place.
- No tracked file changed, no git operation ran, and `STATE.md` and `log.md` are untouched. The advisor was
  rate-limited.

## Owner questions

1. P6R3-1: should a re-run of an accepted done or blocked hide the old end from the moment the unit starts? The
   options are (a) an `rm` in `unit_start` when the unit is down, (b) an InvocationID match, or (c) an mtime check. Or
   does the fixer's "job unchanged, the end still holds" stand, with the docs fixed?
2. P6R3-2: is a child writing `runner-end` itself inside the threat model? If so, clear it per loop pass and on a
   refused exit.
3. P6R3-3: should a non-regular `runner-end` count as "no end", and should the stuck line name it?
4. P6R3-4: clamp the clock, move to a monotonic clock, or record the ceiling with a `ponytail:` note?
5. P6R3-10: document how an end from an older runner reads, or accept it as a one-time migration?

## For the follow-up issue (last allowed round)

- From this round: P6R3-1 (MEDIUM), then P6R3-2, -3, -4, -5 (the test for the lock-side clear), -6, -7, -8, and the
  doc fixes P6R3-9, -10, -11, -12, -14. P6R3-13 is optional.
- Carried over: P6R2-6, -7, -12..-18, P6R2-S1..S3, P6R1-9, -12, -13, -14, -18, -19, and the earlier LOWs.
