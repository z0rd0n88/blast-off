# code-reviewer: phase 6, round-2 fix (`runner-end`, the 10 s and 60 s limits)

Returned as text by a `general-purpose` subagent reading `~/.claude/agents-parked/code-reviewer.md` read-only, static
only. Saved verbatim by the review unit.

**Verdict: APPROVE with notes.** No CRITICAL or HIGH. 1 MEDIUM and 8 LOW.

**Process note.** I broke the no-writes rule by accident. Three scratch copies of repo text went into my session scratchpad: `/tmp/claude-1000/-home-alex-blast-off--claude-worktrees-pending-items-53932d/60b15296-819e-491a-8ffe-34b3bd988f86/scratchpad/chain_tail.txt`, `.../scratchpad/t13a.txt` and `.../scratchpad/t13b.txt`. Nothing in the repo was touched. I ran no tests, no scripts and no git. They can be deleted.

### Answers to the focus questions

- **Written on every accepted end, never on a refused one: yes.**
  - Every `chain_end 0` and `chain_end 3` in `lib/` is at `lib/chain.sh:199-200`, and each is preceded by `chain_accept`.
  - Every refusal runs before `chain_accept`:
    - exit 7: `chain_dirty` runs before child 1 and after each child, so before the next status read.
    - exit 9: `receipt_check` at the top of the loop, and `receipt_all_done`.
    - exit 10: `ci_plan` and `ci_check`.
  - A failed write aborts under `set -e` (`bin/blast-off:45`; `chain_run` is never called in an `||` or `if` context). The trap then logs `runner exit 1 without a state`, the status stays done, and `wait` reads stuck. That is correct.
  - The usage pause skips done and blocked. Cap exits and stalls cannot be reached with status done or blocked.
- **Clear-on-start placement: right relative to the lock.** A second runner refused by `chain_lock` dies before line 166. But there is a window between the unit starting and the `rm`, and runs that die before the lock leave the old file. See MEDIUM-1. Untested: LOW-2.
- **Block forever or wake falsely:** no unbounded block that is new in this fix (P6R2-13 is still open). The new risks come from the wall clock (LOW-4) and a stale or child-written file (MEDIUM-1, LOW-3).
  - `now` is always set in the same pass that sets `down`, so `set -u` cannot fire.
  - Odd content in `runner-end` (several lines, no space, a directory, unreadable) never reads as final. It ends as `stuck` after 10 s with no reason given, which is the same class as the still-open P6R2-12.
- **Regressions in other scenarios:** none found.
  - `chain_dirty` skips the job dir's paths by the `JOBREL` prefix, so `runner-end` and its `.tmp` are skipped.
  - The EXIT trap is unchanged.
  - The `rm -f` comes after the traps, so if it fails, the trap logs `without a state`.
- **0/11/12/1 contract:** the code matches `bin/blast-off`, the README, spec §2 and §3, and SKILL step 8. Small inaccuracies are in LOW-7, LOW-8 and LOW-9.
- **Mutants:** these are killed:
  - final with no `runner-end` check
  - any `runner-end` counts, word not compared
  - `run.log` still read
  - `runner-end` checked only at start
  - no `rm`
  - accept written before `ci_check`
  - the two-poll rule
  - `deactivating` dropped
  - the failed-read spell not reset
  - the stuck threshold set to 0

  These survive: the `rm` moved above `chain_lock` (LOW-2), changed threshold values (LOW-5), and an at-once stuck only on the first snapshot (LOW-9).

### MEDIUM

**MEDIUM-1: A stale `runner-end` reads as `final` while a re-run starts, and forever if that re-run dies before the lock**

- **Where:** `lib/chain.sh:166` (the `rm` comes after `chain_lock`, the last step of startup); `lib/units.sh:112`; the claim at `docs/spec.md:46` ("deleted at the start of every run … so a refused done … or a re-opened job has none").
- **Scenario A, the race:**
  1. A job ended accepted `done`, so `runner-end` holds `done <utc>`.
  2. With the status still `done`, a session runs `blast-off start J && blast-off wait J`, for example to re-check after new commits.
  3. `systemd-run` returns once the runner process exists.
  4. Before line 166, the runner still has to source every `lib/*.sh`, run 8 `command -v` checks, `chain_nums`, `chain_count` and `chain_lock` (which reads `/proc`).
  5. `wait`'s first snapshot (`cat`, `chain_count`, two `systemctl show`) can run before the `rm`. It sees status `done` and `runner-end` `done`, prints `final` and exits 0.
  6. The new runner then refuses: exit 10 for CI red at the new head, or exit 9 for a code change after the receipt. The watcher has already stopped on a done that the latest run refused.
- **Scenario B, death before the lock:** the same job is re-run, but `chain_count` is garbled, a dependency is missing from the unit's `PATH`, or `JOB_*` is invalid (`chain_run` exits at lines 145-152). The runner exits 1, the old `runner-end` stays, and every later `wait` reports `final` though no run accepted anything since.
- **Why existing guards miss it:** the fixer chose this ("a run that dies before the lock leaves the earlier end. The job is unchanged, so that end still holds"). But a done re-run exists to re-check things that can change: HEAD and CI. No test reads `runner-end` during a re-run's startup.
- **Fix, option (a), one line plus a guard:** in `unit_start`, just before `systemd-run`, run `rm -f "$JOB/runner-end"`, but only when the unit's `ActiveState` is `inactive` or `failed`. If the unit is active, `systemd-run` refuses the name anyway, and a live runner in its EXIT trap keeps its end. This closes both A and B for `start` and `resume`. The `rm` in `chain_run` stays for foreground `run`.
- **Fix, option (b), exact:** write `$INVOCATION_ID` into `runner-end`. At done or blocked, `wait` counts it final only when the unit is not active, or when the unit's `InvocationID` equals the file's.

### LOW

**LOW-2: Clearing after the lock has no test**

- **Where:** `lib/chain.sh:166`; `tests/23-runner-lock.sh:15-18`.
- **Scenario:** a mutant that moves `rm -f "$JOB/runner-end"` above `chain_lock` passes every test. The fixer's notes say so too.
- **Real failure it allows:** a runner that accepted done is in its EXIT trap (stopping child scopes can take up to 60 s). A second `run` is refused by the lock but has already deleted the end. `wait` then reads stuck instead of final.
- **Fix:** in test 23's second-runner case, write a `runner-end` before the second `run` and assert it is still there after the exit-1 refusal.

**LOW-3: A child can write `runner-end` itself**

- **Where:** `lib/chain.sh:166` (cleared once per run, not once per child); `lib/units.sh:112`.
- **Scenario:** a child writes `done …` to `$JOB/runner-end` and sets status done. A child working on blast-off itself knows the file from `docs/spec.md`. The runner refuses with exit 9 or 10, but `wait` reports `final`.
- **Why it matters:** the ruling moved off `run.log` because it holds child text, but the job dir is child-writable too. This needs a deliberate write, and everything runs as the same user, so it is LOW.
- **Fix:** move the `rm` to the top of each loop pass, before `receipt_check`. It is still after the lock, and it also covers the clear at start.

**LOW-4: The 10 s and 60 s limits use the wall clock (`date +%s`)**

- **Where:** `lib/units.sh:117`, `:120`, `:131-132`.
- **Scenario, clock steps back:** an NTP or WSL2 resync after a resume steps the clock back N seconds. `now - down` goes negative, so `stuck` comes N seconds late, and so does `no read for 60 s` (a deleted job dir keeps `wait` blocked that long).
- **Scenario, clock steps forward:** stuck fires on the second down poll. That brings back the P6R1-3 handoff hazard: the resume timer is gone, the runner is not up yet, and `wait` says `stuck`.
- **Fix:** use a monotonic source, for example `read -r up _ < /proc/uptime` (boot time, counts suspend, never steps). Tests could fake it through a path variable. Or keep `date` and add a `ponytail:` comment naming the ceiling.

**LOW-5: The threshold values are not pinned by 13-wait**

- **Where:** `tests/13-wait.sh:57-67`, `:172-179`, `:210-239`.
- **Scenario:** each clock read adds 5 s, and `ends` allows 10 s of real time. These mutants survive:
  - 10 s changed to anywhere from 2 to 9 s: the slow case covers only about 0.6 s of real clock.
  - 10 s changed to anywhere from 11 to about 40 s: still only a few polls.
  - 60 s changed to anywhere from about 40 to about 150 s.
- **Fix:** with step 1, assert `wait` still blocks at a skew of 9 and returns 12 by 11. Do the same for 59 and 61.

**LOW-6: The retry test has only about 0.5 s of margin and may flake under CI load**

- **Where:** `tests/13-wait.sh:221-227`.
- **Scenario:** `skewed $((k+40))` returns 35 s into a 60 s spell. The checkpoint rewrite or `rm sd/fail` must land within about 5 more failed reads (about 0.5 to 0.75 s at `POLL=0.1`). If it does not, `wait` exits 12 and the test fails.
- **Fix:** use three spells of about 25 s. The total of 75 s still kills M2b, and each spell gets about 35 s of margin.

**LOW-7: `runner-end` can exist with no `job done` line**

- **Where:** `lib/chain.sh:199-200`, `:6`; `docs/spec.md:46-47`.
- **Scenario:** a TERM arrives between `chain_accept` and `chain_end` setting `CHAIN_END`. `run.log` ends `runner stopped by signal` and `runner exit 143 without a state`, and the unit exits 143. `wait` still says `final`, exit 0.
- **Why it matters:** the fixer accepted this, but spec §2 says the file is written "just before its `job done` … line", which implies the line always follows. This is not P6R2-6, which covers a different window.
- **Fix:** one spec sentence: "a TERM or a failed log between the two leaves the file and no line; `wait` reads final."

**LOW-8: A job ended by a runner older than this change reads `stuck`**

- **Where:** `lib/units.sh:112`; README Watch.
- **Scenario:** a runner started before this lands keeps running the old code bash already loaded, and jobs run for hours. When it ends done or blocked, it writes no `runner-end`. Jobs that ended before the change have none either. `wait` returns 12 with `see blast-off status`, which reads like a refusal.
- **Fix:** add a line to README and SKILL: "an end from a runner older than this has no `runner-end` and reads stuck; `logs` shows `job done`." Or the owner accepts it as a one-time migration.

**LOW-9: Small doc inaccuracies**

- **Status `until` length:** README:104 and `docs/spec.md:59` say "at most 40 more". The code keeps " until " plus up to 40 characters (`lib/units.sh:151-152`), so up to 47 more.
- **The `·` replacement:**
  - `docs/spec.md:59` says the phase line "loses … every `·`". The code replaces each one with `-` (`lib/units.sh:153`; test line 91 expects `- child 9`).
  - The 13-wait row at `docs/spec.md:239` still says "without control characters or ` · `".
- **"Not at once" is not asserted:** the same row claims stuck comes "after 10 s on wait's clock, not at once" on an already stuck job. g2 (test line 132) asserts only exit 12, so a mutant that goes stuck at once only when the first snapshot is down survives.
- **Fix:** correct the wording. Optionally, assert that g2 took at least 3 snapshots, using `polls`.

### Review summary

| Severity | Count | Status |
|---|---|---|
| CRITICAL | 0 | pass |
| HIGH | 0 | pass |
| MEDIUM | 1 | info |
| LOW | 8 | note |

### Open questions for the owner

1. **MEDIUM-1:** should a re-run of an accepted `done` or `blocked` hide the old end from the moment `start` launches it? Option (a) is an `rm` in `unit_start` when the unit is down; option (b) compares the `InvocationID`. Or is the fixer's call right that a run which dies before the lock keeps the earlier end ("the job is unchanged")?
2. **LOW-3:** clear `runner-end` once per loop pass, so a child-written file is gone before the runner reads the status? Or accept the same-user trust boundary?
3. **LOW-4:** switch the 10 s and 60 s timing to a monotonic clock (`/proc/uptime`)? Or keep `date +%s` for easy faking and record the limit with a `ponytail:` note?
4. **LOW-8:** document how an end from an older runner reads, or accept it as a one-time migration?
