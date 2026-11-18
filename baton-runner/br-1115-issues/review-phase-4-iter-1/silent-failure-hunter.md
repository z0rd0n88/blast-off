### Summary

I reviewed commit f388962 (7 files of `git diff 7867255...f388962 -- . ':!baton-runner'`) against issue 22, statically. I read `lib/chain.sh`, `bin/blast-off`, `lib/units.sh`, `lib/preflight.sh:20-30`, `lib/child.sh:40-51,123`, `lib/checkpoint.sh:118`, `tests/fakes/claude:44-70`, the test diffs, the re-run sites in tests 20, 22, 23, 30, 31, 32, 40, 41 and 61, the work note and `phase-4/findings.md`. I ran bash 5 probes that write nothing: the parse chain at the int64 edge, and a `set -e` abort of the save function inside a `case` arm. No scenario, `tests/run`, `scripts/gate.sh` or `bin/blast-off` was run.

The core is sound:
- A failed save aborts under `set -e` at both call sites. The EXIT trap logs it, and no child launches with its count unsaved.
- `chain_run` never runs with `set -e` suppressed.
- No input reaches the assignment at `:122` unmatched.
- All three acceptance criteria hold, and the new assertions kill their obvious mutants.

No CRITICAL or HIGH finding. The silent paths are elsewhere:
- A garbled `child-count` fails before the EXIT trap, so under `start` or the resume timer nothing reaches `run.log`.
- `preflight` and `status` never read the count.
- `paused-cap` moves BASE with no soft-cap guard, so the hard cap does have a reset path, despite what the docs and the work note say.
- No test reads a nonzero BASE back from the file.

The rest is LOW: a duplicated test line, a stale "before child 1" label, edge cases and durability.

### Findings

#### CRITICAL

None.

#### HIGH

None.

#### MEDIUM

- **Title:** A garbled `child-count` stops the runner with nothing in `run.log`. Under `start` or the resume timer the job just stops.
- **Location:** `lib/chain.sh:119-121` (die), called at `:135`, before `chain_lock` `:144` and `trap 'chain_exit $?' EXIT` `:145`; `bin/blast-off:48` (`die` writes stderr only); `lib/units.sh:65-67` (resume logs its start, then stops the timer)
- **Description:** `chain_count` dies before the EXIT trap exists, so `chain_exit` never writes `runner exit 1 without a state` and `die` writes nothing to `$LOG`. The work note calls this deliberate ("a clean `die`, nothing logged as a runner abort"), but the cost is unattended operation:
  - With `blast-off start`, `systemd-run --collect` succeeds and the unit fails at once. The `--collect` unit is unloaded, so `status` shows `ActiveState=inactive`.
  - `run.log` ends at the previous run's last line.
  - Through the resume timer it is worse. `unit_resume` logs `resume: starting ... (status paused-limit)`, `systemd-run` succeeds, and the timer is stopped (`units.sh:67`). The runner then dies at `:121`. Status stays `paused-limit until <past time>`, `run.log` ends with "resume: starting", and nothing will run again.
  - The reason exists only in the journal (`blast-off logs` shows its last 40 lines).
  - `preflight` does not read the file (next finding), so nothing before `start` catches it either.
  - Test 10's bad-count loop (`tests/10-chain-done.sh:91-96`) checks only the runner's own stdout/stderr (`badcount.out`), so this is untested.
  - The older pre-trap `die`s (missing brief, `CLAUDE_FLAGS`) are caught by `unit_check` before `start`. This one is new, and data corruption can reach it with nobody watching.
- **Suggested fix:** Log the reason to `run.log` before exiting. Either replace the `die` with `log "<same message>"; exit 1`, or call `chain_count` right after the trap at `:145`, where an exit 1 is logged by `chain_exit`. Calling it after the lock also closes the LOW lock race below. Add `grep -q child-count "$JOB/run.log"` to the bad-count loop.

- **Title:** BASE moves on any `paused-cap` and is subtracted from the hard cap too, so the hard cap has a reset path the docs deny
- **Location:** `lib/chain.sh:163` (no `CAP_SOFT` guard), `:184-185`; `README.md` exit-4 row ("counted over every run of the job"); `docs/spec.md:91` ("the cap counts every child of the job across runs"); `baton-phase-4-work.md:50` ("The hard cap has no reset path"); `phase-4/findings.md:16`
- **Description:** The check is `n - BASE > MAXC` whichever cap is active, and the `paused-cap` arm sets `BASE=LAUNCHED` whichever cap is active. Two traces:
  - **Hand-set or child-set `paused-cap` on a hard-cap job.** Say LAUNCHED=12, BASE=0, no Phase plan rows, cap 12. The runner exits 4. Anyone who writes `status: paused-cap` into `checkpoint.md` and runs `run` or `blast-off resume` (`units.sh:56` accepts paused-cap) gets BASE=12 and 12 more children.
    - Children write the status line themselves (done or blocked), so a child can reset its own cap on the next relaunch.
    - The fix for issue 22 was meant to stop the cap being a per-run allotment, and this path quietly gives that back.
  - **A job that loses its rows after a paused-cap resume.** The soft cap paused at LAUNCHED=9, and the re-run set BASE=9. A later relaunch reads no Phase plan row (a child dropped the table, or `cp_unread` cuts it), so the cap turns hard: MAXC=12, counted from BASE=9. Children 10 to 21 launch.
    - The exit is `child cap 12 reached (21 children launched for this job, ...)`, which reads as a contradiction. The message leaves BASE out, so the reader cannot see that the cap was counted from 9.
- **Suggested fix:** Pick one rule and say it once.
  - **The docs' rule (the hard cap counts every child):** move BASE only when `CAP_SOFT` is set (`paused-cap) [ -z "$CAP_SOFT" ] || BASE="$LAUNCHED"; ...`). Note that `chain_cap` runs at `:151`, before the case. Also compare the hard cap against `n`, not `n - BASE`.
  - **The code's rule:** reword README row 4, spec `:91` and the work note to say "since the last paused-cap re-run", and put `base B` in the exit-4 message.

- **Title:** `preflight` and `status` ignore `child-count`, so a job whose cap is used up shows a full cap and passes preflight
- **Location:** `lib/preflight.sh:25-26` (`chain_cap`; `echo "cap: $MAXC ($CAP_WHY)"`); `lib/units.sh:70-78` (`unit_status`); decision recorded at `phase-4/findings.md:6`
- **Description:** Two problems:
  - **A full cap that is already spent.** Say `child-count` is `12 0` and the job has no rows. Preflight prints `cap: 12 (hard: ...)` and does not refuse. `start` then exits 4 before any child.
    - A soft-cap job at `n - BASE == MAXC` (for example after a stall exit) does the same: preflight looks clean, and the run exits 6 at once and flips the status to `paused-cap`.
    - Preflight exists to tell the owner what a start will do. The decision not to read the counter was about not erroring on a bad file, but showing it does not need that.
  - **A garbled `child-count` passes preflight.** The runner then dies on it, which the MEDIUM above makes invisible in `run.log`.

  `status` prints no count at all.
- **Suggested fix:** In preflight, after `chain_cap`, read the file with the same regex without dying. Then either print `children: L launched, base B; next is L+1; R left under the cap`, or print `child-count: unreadable (...)` and add it to `probs`. Optionally print the same line in `unit_status`.

- **Title:** No test round-trips a nonzero BASE through the file, so three mutants of the BASE logic survive
- **Location:** `lib/chain.sh:120` (`-le`), `:122` (BASE assignment), `:163` (`chain_count_set` in the paused-cap arm); tests `tests/21-soft-cap.sh:27-44`, `tests/10-chain-done.sh:79-96`
- **Description:** In every new assertion the file is read back with BASE 0. Test 21's paused-cap re-run reads `2 0` at start, and the BASE it uses is the in-memory one set at `:163`. The `relaunch` job is `2 0` and then exit 6. Traced statically:
  - **(a) `:122` forced to `BASE=0`.** Test 21 still passes, because the re-run sets BASE in memory and finishes `done` in the same run. Real effect: any relaunch after a paused-cap resume (a crash, exit 5 or exit 7) loses the fresh allotment and re-pauses at once.
  - **(b) Delete `chain_count_set` at `:163`.** It still passes, because `:194` writes `"$LAUNCHED $BASE"` from memory at the next launch. Real effect: an exit before the next launch (exit 7 at `chain_dirty "before child 1"` `:172`, or an abort) loses the moved BASE, so the next run re-pauses with exit 6.
  - **(c) `-le` changed to `-lt` at `:120`.** It still passes, because no test reads an `N N` file. The bad-count set (`'' x 1 '08 0' '1 2' '-1 0'`) has no equal pair. Real effect: a run that exits between the paused-cap save and its first launch leaves `N N`, and every later run dies on it as garbled.
- **Suggested fix:** Add one case to test 21: after the paused-cap re-run, also check `[ "$(cat "$JOB/child-count")" = "3 2" ]` (one child, child 3, sets the job `done`). Add a second case: a paused-cap job with an unnamed dirty path, which exits 7 after `:163`, then a clean re-run that must launch a child rather than exit 6. That kills (a), (b) and (c). UNREPRODUCED. For each mutant, apply it to a `git archive f388962` copy, then run `BLAST_OFF_TEST_ONLY=21-soft-cap tests/run` from that copy. Expect it to pass, which shows the mutant survives. The mutant edits are:
  - (a) `sed -i 's/BASE="${BASH_REMATCH\[2\]}"/BASE=0/' lib/chain.sh`
  - (b) `sed -i '163s/BASE="$LAUNCHED"; chain_count_set/BASE="$LAUNCHED"/' lib/chain.sh`
  - (c) `sed -i '120s/-le/-lt/' lib/chain.sh`

- **Title:** The README's exit-4 remedy now takes two starts, and the first launches nothing and flips the status to `paused-cap`. This is the work unit's own owner question P4-22b.
- **Location:** `README.md` exit-4 row ("add a Phase plan table with a row per phase and start again"); `lib/chain.sh:184-186`; `baton-phase-4-work.md:133`
- **Description:** Say the hard cap is reached at LAUNCHED=12, BASE=0. The owner adds 3 rows (soft cap 9 with the default factor 3) and starts again: 13 - 0 > 9, so the runner writes `status: paused-cap` and exits 6 "soft cap 9 reached" without launching a child. Following the documented remedy gives an exit the doc does not mention. A second `run` or `resume` moves BASE and goes on. The work unit flagged this but left the README unchanged.
- **Suggested fix:** Add "(a second start may be needed: the first pauses at `paused-cap` when the children already launched exceed the new soft cap)" to the row. Or, on the soft-cap path, move BASE when the file's BASE is 0 and the previous cap was hard. The README sentence is the smaller change.

#### LOW

- **Title:** The `rm -f "$JOB/child-count"` line in `start_hang` appears twice
- **Location:** `tests/11-unit-smoke.sh:58-59`
- **Description:** The same line appears twice, with two different comments. It looks like an edit left in twice. It is harmless, since `-f` makes the second a no-op. It hides no consumer in the program: the only readers keyed on child 1 are this test's own `sed -n 's/^child=1 pid=...'` (`:62`) and the scope name `$TEST_ID-job-child-1.scope` (`:66`). `lib/` names scopes `"$UNIT-child-$n.scope"` (`child.sh:47`), and `unit_stop` stops a glob (`units.sh:83`). Test 11's first, fresh run (`:27-38`) still writes the count from inside a real unit, so that path stays covered.
- **Suggested fix:** Delete line 59. A related duplicate is already in the base and is not part of this diff: `tests/21-soft-cap.sh:27-28` writes `printf 'done\n' > "$JOB/fake-mode"` twice.

- **Title:** The literal "before child 1" is now wrong on any relaunch, and a test pins the wrong text
- **Location:** `lib/chain.sh:172` (`chain_dirty "before child 1"`), comment `:173`; `tests/22-dirty-tree.sh:28` (greps `dirty tree before child 1` on a re-run whose next child is 2); stale comments `tests/40-receipt-required.sh:81,90,109` ("refuses before child 1", "refused before child 1", "exit 9 before child 1")
- **Description:** After a relaunch, the next child is `LAUNCHED+1`, but `run.log` says "dirty tree before child 1". The work note says it updated test 40's comments, yet lines 81, 90 and 109 still say child 1. Test 22 passes because the label is a fixed literal, not because it is correct.
- **Suggested fix:** Use `chain_dirty "before child $((LAUNCHED+1))"`, and update `tests/22:28` to `before child 2` along with the three comments.

- **Title:** At the int64 edge the next child number wraps negative and launches
- **Location:** `lib/chain.sh:120,183-184`
- **Description:** Probed with bash 5:
  - A value above int64 (`99999999999999999999 0`, `5 99999999999999999999`, `9223372036854775808 0`) makes `[ -le ]` print `[: ...: integer expression expected` and return 2. `|| die` catches it, so it fails closed with one extra stderr line.
  - `9223372036854775807 9223372036854775807` passes. Then `n=$((L+1))` = `-9223372036854775808`, and `n - BASE` wraps to `1`, which is not above MAXC. The runner launches child `-9223372036854775808`.

  Only a hand-edited file can reach this.
- **Suggested fix:** Cap the digit count in the regex, for example `[1-9][0-9]{0,8}`, which also removes the stderr noise.

- **Title:** A missing `child-count` silently reads as a fresh job, even when `run.log` shows launches, and nothing logs the count in use
- **Location:** `lib/chain.sh:118` (`[ -e "$f" ] || return 0`), `:152` (the start line logs the cap, not LAUNCHED or BASE), `:121` (the die message advises deleting the file)
- **Description:** Four inputs all read as `0 0` and log nothing, which resets the cap and the numbering:
  - a deleted file (a child, `git clean -fdx`, an owner following the die message's "delete it");
  - a dangling symlink (`-e` follows the link);
  - a job dir copied without the file;
  - an in-flight job from before this commit.

  `run.log` then holds two `child 1 launched` blocks. `child_screen` (`child.sh:123`) prints the range for every block matching `^child $1 session=`, so it mixes runs (it shows the last 40 lines).
- **Suggested fix:** Log `child count: L launched, base B (<file>|no child-count: a fresh job)` beside the cap line at `:152`. Optionally warn when there is no file but `run.log` already has a `child N launched` line.

- **Title:** A failure inside `child_launch` is counted as a launched child
- **Location:** `lib/chain.sh:194-195`; `lib/child.sh:44-49` (`mktemp`, `sed`, `tmux new-window` can each fail after the save)
- **Description:** The save comes before `child_launch` on purpose, so that a reboot still counts the child. But a runner abort in `mktemp`, `sed` or `tmux new-window` (no server, no session) also bumps LAUNCHED with no child and no scope. Each failing attempt uses up one slot of the hard cap, which can only be reset by hand. `run.log` shows only `runner exit 1 without a state`, and later numbering skips a number. The exit-4 count "L children launched" then overstates.
- **Suggested fix:** Accept and document it ("a launch that aborts counts"). Or save after `CHILD_WIN` is set and before `log "child $n launched"`. The reboot window then shrinks to the tmux call, and the hup test (`tests/10:127-130`) still holds.

- **Title:** No test separates "save before launch" from "save after launch, before wait"
- **Location:** `tests/10-chain-done.sh:127-130`; `lib/chain.sh:194`
- **Description:** The hup test kills the runner while child 1 hangs, which is after `child_launch` returned. A mutant that moves `LAUNCHED="$n"; chain_count_set` to just after `child_launch "$n"` still saves before the SIGHUP and survives. Only the move to after `child_wait` is caught. The window is small (the tmux call), so LOW. UNREPRODUCED. On a `git archive f388962` copy, move line 194 below line 195, then run `BLAST_OFF_TEST_ONLY=10-chain-done tests/run`. Expect it to pass.
- **Suggested fix:** None needed unless the timing matters. Otherwise, a fake `tmux` that fails on `new-window` combined with a re-run at cap 1 would pin it, which is also the previous finding's behaviour.

- **Title:** The count is read before the lock
- **Location:** `lib/chain.sh:135` versus `:144`
- **Description:** Runner B reads `k` at `:135`. Runner A still holds the lock, launches child `k+1`, writes `k+1`, and then dies uncleanly, leaving a stale lock (`chain_lock:36` takes it over). B carries on with LAUNCHED=`k`, so child `k+1` is numbered twice and the cap counts one fewer. The window is the few statements between `:135` and `:144`.
- **Suggested fix:** Read after `chain_lock` (and after the trap; see the first MEDIUM).

- **Title:** The rename is not fsynced, so a power cut can lose the count that "a child cut off by a reboot still counts" relies on
- **Location:** `lib/chain.sh:125`, comment at `:194`
- **Description:** `echo > tmp && mv -f` with no `sync`. On ext4 the default `auto_da_alloc` usually orders replace-by-rename. On other filesystems, or with `noauto_da_alloc`, a power cut can leave an empty file or the old count:
  - An empty file is caught by `:120`, which dies (fails closed, but see the first MEDIUM).
  - The old count is the silent case: the child that was running is not counted, which is exactly the reboot case the comment and spec `:61` promise.

  UNREPRODUCED. A test cannot show it.
- **Suggested fix:** Run `sync "$JOB/child-count.tmp"` (coreutils `sync` takes file arguments) before the `mv`, or `sync -f`. Otherwise, soften the comment.

- **Title:** The counter sits in a directory the child writes
- **Location:** `lib/chain.sh:116,125`; `templates/brief.md:107,191` (only "never commit the job dir")
- **Description:** Before this change the cap lived in runner memory, which a child cannot touch. Now a child can delete the file, or write a smaller but valid value such as `0 0`. Within a run this heals, because `:194` rewrites the file from memory at each launch. If the runner then relaunches for any reason, though, the cap is silently partly or fully reset. Combined with the hard-cap `paused-cap` path in the MEDIUMs, a child has two ways to reset its own cap.
- **Suggested fix:** Note it in the spec as a known limit. Or keep a copy outside the job dir (for example `$XDG_STATE_HOME/blast-off/<unit>.count`) and refuse to start when the two disagree.

### Validated

- **A failed save aborts, is logged, and launches nothing.**
  - `chain_count_set` is `echo > tmp && mv`. A failing first command makes the `&&` list, and so the function, return 1, and the plain call aborts under `set -e`.
  - Probe: `JOB=/proc/1` inside a `case` arm under `set -euo pipefail` printed `/proc/1/child-count.tmp: No such file or directory` and `trap rc=1`. The next statement (the status write) did not run.
  - Both call sites (`:163` and `:194`) come after the EXIT trap (`:145`), so `chain_exit` logs `runner exit 1 without a state`.
  - At `:194` the save comes before `child_launch`, so no child starts with its count unsaved. The in-memory LAUNCHED or BASE that ran ahead of the file dies with the process.
  - `child-count.tmp` as a directory makes the redirect fail, so it aborts.
  - `child-count` as a directory or unreadable fails `cat` at `:119`, so it dies. It is read before `mv -f` could move the temp file into it.
- **`set -e` is never suppressed around `chain_run`.** It is called only at `bin/blast-off:65` (`run) shift; job_init "$@"; chain_run ;;`). `resume` and `start` reach it through `systemd-run` (`units.sh:44`), a new process. Its `unit_start ||` context does not carry over.
- **The parse chain.** `[[ =~ ]] && [ -le ] || die`:
  - no match → `die`; `-le` false → `die`; `-le` error (a value above int64) returns 2 → `die`.
  - `[` does not touch `BASH_REMATCH`.
  - `die` is `exit 1` in the same shell (no `$( )`), so `:122` runs only with both groups matched and BASE <= LAUNCHED.
  - `c="$(cat ...)" || die` takes `cat`'s status.
- **The paused-cap ordering.**
  - If the base save fails, nothing has changed (status still `paused-cap`, file untouched).
  - If the base save succeeds and `cp_set_status running` (`checkpoint.sh:118`, `sed -i`) then fails, the re-run enters the `paused-cap` arm again and sets BASE to the same LAUNCHED, since no child launched in between. It is idempotent, so there is no lost or double allotment.
  - If an exit comes after both (exit 7 at `:172`), the job is `running` with BASE saved, and its allotment is kept. The test for this is missing (see the MEDIUM).
- **Acceptance criteria.**
  - (1) `tests/10:79-89`: a re-run at cap 1 gives exit 4 with one launch; a re-run at cap 2 launches child 2, then exit 4.
  - (2) `tests/10:85-88` and `tests/21:34-35`.
  - (3) No new assertion, but existing assertions cover it on fresh jobs: `tests/10:78` (`^child=1 `), `tests/22:20` (`after child 1`), `tests/11:28` (`child=1 pid=`). A mutant that starts LAUNCHED at 1 fails all three.
- **The new assertions are real.**
  - Not persisting the count fails `tests/10:82`, `:129-130` and `tests/21:44`.
  - Resetting the numbering at paused-cap fails `tests/21:35`.
  - Dropping BASE altogether (a lifetime soft cap) fails `tests/21:33` (`status: done`).
  - Accepting a leading zero, `base > launched`, an empty file or one field each fails a value in the bad-count loop. Each value fails exactly one rule. `grep -q "$JOB/child-count"` matches only this `die` message.
- **Blast radius of the shifted child numbers.**
  - `tests/fakes/claude:44` picks its mode by `JOB_CHILD`, and `:62` its usage file the same way.
  - No multi-line `fake-mode` job is re-run in a way that depends on the line. Test 22's `dirty` re-run exits 7 before any child. Test 10's `reset` and `stall`, test 32's `rows` and test 61's `pick` run once. Test 30's re-run (`over`) exits 8 before any child. Test 31's jobs are single-mode `done`. Tests 40 and 41 use single-mode jobs, and their totals stay under their caps (test 40 `chain`: 3 children, cap 6).
  - `LAUNCHED` and `BASE` collide with no other name in `lib/`, `bin/` or `tests/fakes/`. `JOB_BASE` is distinct.
- **`stop`, `resume` and paused-limit.**
  - `unit_stop` and `chain_exit` write no count, and the child it cuts off was counted before its launch.
  - A paused-limit resume continues the count, as issue 22 asks. A timer resume that lands exactly on the soft cap pauses with exit 6 and needs the owner, which is the intended behaviour.
  - Scope names are now unique per job, and `unit_stop` uses a glob.
- **The unit is not sandboxed.** `systemd/blast-off@.service` has no `ProtectSystem` or `ReadOnlyPaths`, and test 11's first run writes the count under a real unit.

### Confidence

High for the save, abort and parse results (probed or traced line by line), and for the four MEDIUMs about logging, preflight, the BASE reset path and the README remedy (each read directly from the code and docs, no run needed). Medium for the surviving-mutant claims until the dispatching unit runs the given `BLAST_OFF_TEST_ONLY` commands on a `git archive` copy. Low for the fsync item, which no test can show.
