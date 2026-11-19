# silent-failure-hunter: round-2 fix review (runner-end, phase 6, issue 14)

Returned as text by a `general-purpose` subagent reading `~/.claude/agents-parked/silent-failure-hunter.md` read-only,
static only. Saved verbatim by the review unit.

Static review only. I made no edits and ran no commands beyond reading files.

**Checked, no finding**
- **set -e:** `chain_accept` is `echo > tmp && mv`. If either half fails, the `&&` list is exempt, but the function returns non-zero. Its call at `lib/chain.sh:199`/`:200` is a plain simple command, so set -e exits there.
  - `CHAIN_END` is not set yet, so the EXIT trap logs `runner exit 1 without a state`, no `runner-end` exists, and `wait` reads stuck. That is loud and correct.
  - `chain_run` is only ever called plainly (`bin/blast-off:71`). The unit runs `blast-off run` as a new process under `set -euo pipefail` (`bin/blast-off:45`). Nothing calls it with set -e off.
  - A failed `mv` leaves `runner-end.tmp` behind. That is harmless: the dirty check skips the job dir, and wait never reads the tmp file.
- **Accept placement:** `chain_accept 'done'` comes after `ci_plan`, `receipt_all_done` and `ci_check`, the last gate. Every refusal (exit 7 from chain_dirty, 9 from receipt_check/receipt_all_done, 10 from ci_plan/ci_check, 1 from die or abort) exits before it. `blocked` is accepted only after `chain_dirty` and `receipt_check`. No path writes `runner-end` on a refused end.
- **Clear-on-start vs the lock:** `rm -f` at `lib/chain.sh:166` comes after `chain_lock` (161), which dies before the EXIT trap is set. A second runner refused by the lock does not touch `runner-end`.
  - If `rm` fails, set -e aborts the run loudly (see LOW-4 for when that can happen).
  - From the rm until an accept, no `runner-end` exists, so a done or blocked under evaluation is held while the unit is up and reads stuck 10 s after it goes down.
- **Mutants caught:**
  - accept moved after `chain_end` (never runs): test 10, lines 22 and 45.
  - accept moved anywhere before `ci_check`: test 10's refused fresh job.
  - rm removed: test 10's re-open case.
  - final not checking the word (`-e`/`-s` only): 13-wait d3 (`runner-end` blocked, status done, expect 12).
  - hold on unaccepted done/blocked removed: 13-wait `blocks d` after `ck status done`.
  - stuck threshold set to 0: the `hand` and `slow` cases.

---

**LOW-1. `runner-end` sits in the child-writable job dir; one a child writes ends the watch and is never cleared**
- **Where:** `lib/units.sh:112`, `lib/chain.sh:10`, `:166`
- **Scenario:**
  1. A child writes `echo "done x" > $JOB/runner-end` and sets `status: done`.
  2. `wait` prints `wait: final` and exits 0 at once.
  3. The runner then refuses the done (exit 9 or 10). Nothing deletes the forged file until the next run passes the lock, so a later `wait` also reads final, never stuck.
- This is the same class as P6R2-1, the reason `run.log` was dropped. The difference is that it needs a deliberate write to that exact name, not text that reaches `run.log` by accident.
- It cannot be prevented at the same uid.
- **Fix options:**
  - Cheap hardening: also `rm -f "$JOB/runner-end"` at the top of each loop pass, and in `chain_exit` when the exit was not an accept, so a refused run always ends with no file.
  - Or have `wait` require the file to be newer than the unit's `ExecMainStartTimestamp` (see LOW-2).
  - Or document the limit.

**LOW-2. A stale `runner-end` reads as final for a re-run that has not reached its rm, or died before the lock**
- **Where:** `lib/chain.sh:144-166`; `lib/units.sh:112`; `lib/units.sh:28-46` (`start` does not check status or `JOB_*` counts)
- **Scenario A:** A job is done and accepted (`runner-end` says done). The owner runs `blast-off start` again, for example to re-check CI after a force-push. `start` returns once the unit is up, but the runner has not yet passed its DEPS, chain_nums and chain_count checks, the lock and the rm. A `wait` launched in that window reads the old `done` and exits 0. The new run may then refuse it (exit 9 or 10).
- **Scenario B:** The same re-run with `JOB_MAX_CHILDREN=abc`, which `unit_check` does not validate, or a garbled `child-count`. The runner exits 1 before the lock and the rm, and `wait` reports final 0 for a run that never evaluated anything.
- The fixer judged B acceptable ("the job is unchanged, so that end still holds"). It still contradicts the spec's "deleted at the start of every run" (LOW-3).
- **Fix:**
  - Have `wait_snap` also read the unit's `ExecMainStartTimestamp`, and trust `runner-end` only when its mtime is later than that start, or when the unit has never started.
  - Or accept the window and document it.
  - Deleting the file in `start` is worse: it races a just-ended runner that is still deactivating.

**LOW-3. The spec and README overstate when `runner-end` is absent**
- **Where:** `docs/spec.md:45-49`; `README.md:109`, `:112`
- **Text:** "deleted at the start of every run (after the runner takes the job's lock), so a refused `done` or `blocked` (exit 7, 9 or 10) or a re-opened job has none".
- **What is wrong:**
  - Runs that exit 1 before the lock (CLAUDE_FLAGS, DEPS, brief, chain_nums, chain_count) do not delete it.
  - A re-opened job keeps the file until the next run passes the lock.
  - Refusals of a done or blocked also include exit 1 (die, or a set -e abort after the lock, such as `git rev-parse` at `lib/chain.sh:175`) and signals, not only 7, 9 or 10.
- **Fix:** Say "deleted by every run that takes the lock". List the refusals as "any exit but 0 and 3", or "7, 9, 10, or an abort".

**LOW-4. A `runner-end` that is not a regular file breaks things silently or for good**
- **Where:** `lib/chain.sh:10`, `:166`; `lib/units.sh:112`
- **Directory created mid-run** (by a child, or anything else):
  - `mv -f runner-end.tmp runner-end` moves the tmp *into* the directory and returns 0.
  - The runner logs `job done` and exits 0, but `cut` fails (2>/dev/null) and `wait` never sees final.
  - After 10 s it prints `stuck ...; see blast-off status` for an accepted done, and `status` does not show `runner-end` at all.
- **Directory present at a run's start:** `rm -f` fails. Every later run aborts with exit 1. `run.log` says only `runner exit 1 without a state`, and the reason sits in the journal.
- **FIFO:** `cut` in `wait` blocks forever with no output. This is outside the 60 s failed-read limit, because the read is not in `wait_snap`.
- **Fix:**
  - Use `mv -fT`.
  - In `wait`, read only a regular file: `[ -f "$JOB/runner-end" ] && [ ! -p "$JOB/runner-end" ]`, then `read -r w _ <`.
  - Optionally name the offending path in the abort.

**LOW-5. A backward wall-clock step delays both of wait's limits by the size of the step**
- **Where:** `lib/units.sh:117`, `:120`, `:131-132`
- **Scenario:**
  1. `down` (or `bad`) is set from `date +%s`.
  2. The clock steps back by X seconds (an NTP step, or a WSL2 host resync).
  3. `now - down` is negative, so stuck needs X + 10 s and the failed-read limit X + 60 s. Until then `wait` blocks with no output while nothing runs.
- **Fix:** Clamp it: `[ "$now" -ge "$down" ] || down=$now`, and the same for `bad`. This keeps `date`, so 13-wait's fake clock still works.

**LOW-6. Test gap: the rm's placement is not pinned in either direction**
- **Where:** `tests/10-chain-done.sh:46-56`; `tests/23-runner-lock.sh:9-21`
- **Mutant (a) survives:** rm moved before `chain_lock`, or even to the first line of `chain_run`. No test leaves a `runner-end` in place while a second runner is refused by the lock. The fixer notes this too.
  - The real window: an accepted runner's `chain_exit` holds the lock during `child_stop_all`, which can last up to TimeoutStopSec, while `runner-end` already exists. A runner refused by the lock (resume timer, or the owner's `run`) would delete it, and `wait` would print stuck for an accepted end.
  - **Fix:** In test 23, write `echo "done x" > "$JOB/runner-end"` before the second `run`, and assert it is unchanged after the exit 1.
- **Mutant (b) survives:** rm moved later, after `chain_dirty "before child 1"`, after the loop's `receipt_check`, or into the `done)` branch before `ci_plan`.
  - Test 10's only "clears on re-run" case is refused at `ci_check`, the last gate, so any rm before it passes.
  - The broken behaviour: an accepted `blocked`, re-run and refused before child 1 by a dirty tree (7), a receipt (9) or exit 8, keeps its stale `blocked`, and `wait` reads final.
  - **Fix:** Add a re-run refused early (a dirty tree before child 1, or `paused-limit` before its reset, exit 8) and assert there is no `runner-end`.

**LOW-7. Test gap: wait's word match against odd content**
- **Where:** `tests/13-wait.sh:100-124`
- **Gap:**
  - Every `runner-end` in 13-wait comes from `rend` (`<word> <utc>`).
  - Nothing covers a prefix like `donex`, a bare `done`, two lines, a directory or an unreadable file. So a prefix-match mutant (`[[ $(<f) == "$WAIT_STATUS"* ]]`) survives.
  - The format contract between `chain_accept` and `wait`'s `cut -f1` is pinned only by test 10's regex.
- **Fix:** One case, `echo donex > runner-end` with status done and the unit down, expecting 12.

**LOW-8. A set -e failure mid-watch exits 1 with no line**
- **Where:** `lib/units.sh:117`, `:131`
- **Scenario:** `now="$(date +%s)"` failing mid-watch exits with date's status, usually 1, and prints nothing on stdout. Exit 1 is documented as "cannot start watching". This is contrived.
- **Fix:** None needed unless the owner wants a guaranteed line, for example `|| { echo "wait: stuck · clock read failed ..."; exit 12; }`.

**LOW-9. The docs state the limits in seconds, but a large poll value stretches them**
- **Where:** `README.md:112-113`; `docs/spec.md:59`, `:112-115`; `bin/blast-off:44-47`
- **Scenario:** At `BLAST_OFF_WAIT_POLL=3600`, "no read for 60 s" first fires after 3600 s, and stuck after 3600 s too. README's "for 10 s (at least two polls)" is right as a minimum. The 60 s line has no such qualifier.
- **Fix:** "60 s (at least one poll)" or "the longer of 60 s and one poll".

**Carry-over note (not re-filed):** P6R2-12 now applies to `runner-end` as it did to `run.log`. An unreadable `runner-end` (the `2>/dev/null` at `lib/units.sh:112`), a refused end and a missing file all print the same `stuck ...; see blast-off status` line, and `blast-off status` does not show `runner-end`. It is no worse than before.

---

**Questions for the owner**
1. LOW-1: is a child writing `runner-end` itself inside the P6R2-1 threat model, or out of scope since only a deliberate write can do it? If in scope, add a loop-top or `chain_exit` rm, or an mtime check against the unit start?
2. LOW-2: should a re-run of an already done or blocked job, including one that dies before the lock, keep reporting the earlier accepted end as final? If not, use an mtime check against `ExecMainStartTimestamp`, which costs one more `systemctl show` property per poll.
3. LOW-4: should `wait` treat a non-regular `runner-end` as "no end", silently as now, or name it in the stuck line?
4. LOW-5: clamp backward clock steps, or accept the delay?
