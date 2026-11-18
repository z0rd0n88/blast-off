### Summary

I reviewed commit f388962 (`git diff 7867255...f388962 -- . ':!baton-runner'`, 7 files) against issue 22, statically only. I read the whole diff and `lib/chain.sh` in full. I also read `lib/child.sh` (launch/stop), `lib/jev.sh` (`jev_pick`), `lib/preflight.sh`, `lib/units.sh` (start/resume/status/stop), `lib/usage.sh` (`usage_arm`), `lib/checkpoint.sh` (`cp_scan` row reading), `bin/blast-off` (header, `die`, `job_init`, dispatch), the run/launch greps of tests 12, 22, 23, 30, 31, 40 and 41, the fake `claude`, the work baton, and `phase-4/findings.md`. Shellcheck was clean. I ran one bash probe (integer overflow). I ran no tests.

The change is small, matches the file's style, and meets all three acceptance criteria. Each criterion has an assertion that a likely mutant turns red. The save-before-launch and garbled-file decisions are sound and fail closed. The main defect is in the `base` design: a `base` that a soft-cap resume moved is also subtracted under the hard cap. So the baton's "the hard cap has no reset path" is false, and so are the README/spec exit-4 rows ("counted over every run"). Two more medium items: `preflight` is blind to the count, and the README exit-4 remedy now usually needs two starts. Counts: 0 CRITICAL, 0 HIGH, 3 MEDIUM, 11 LOW.

### Findings

#### CRITICAL

None.

#### HIGH

None.

#### MEDIUM

- **Title:** A `base` left by a paused-cap resume also offsets the hard cap. The job can exceed `JOB_MAX_CHILDREN` counted over its runs, and the exit-4 message reports more children launched than the cap
- **Location:** `lib/chain.sh:163` (`paused-cap) BASE="$LAUNCHED"; chain_count_set`), `lib/chain.sh:184-185` (`if [ $((n - BASE)) -gt "$MAXC" ]; then [ -n "$CAP_SOFT" ] || chain_end 4 "child cap $MAXC reached ($LAUNCHED children launched for this job, ...`). Claims: `baton-phase-4-work.md:50` ("The hard cap has no reset path"), `README.md:136` ("hard child cap, counted over every run of the job in its `child-count`"), `docs/spec.md:91` ("the cap counts every child of the job across runs, so a re-run at the same cap exits 4 before any child").
- **Description:** `base` only moves on a paused-cap re-run, and that needs a soft cap. But the subtraction at line 184 runs under both caps. `chain_cap` (`lib/chain.sh:99-109`) works the cap out fresh each run from `cp_phases`, so one job can be soft in one run and hard in the next. The Phase plan rows read can drop to 0 when a child rewrites `checkpoint.md` with Status no longer the last column, a missing separator row, a second Phase plan heading, or a renamed heading (`lib/checkpoint.sh:74,81-89`; each sets `st = 3` and emits no row).
  Scenario: 3 rows, factor 3, soft cap 9. Run 1 launches children 1-9 and stops at paused-cap (exit 6). Run 2 sets `base` 9, launches child 10, and that child breaks the table header. Run 2 then ends some other way (a stall, a dirty tree, a reboot). Run 3 reads no row, so the cap is hard (default 12). Its check is `n - 9 > 12`, so it launches children 11-21 and stops with "child cap 12 reached (21 children launched for this job ...)". The message contradicts itself. The README tells the owner that a larger `JOB_MAX_CHILDREN` goes on: set to 22 meaning "one more child", it gives 10 more.
  The same holds for a paused-cap job whose rows were lost before the resume: line 163 moves `base` without checking `CAP_SOFT`. No guard catches this: the regex in `chain_count` only checks `base <= launched`, and no test runs a hard-cap job with a nonzero `base`. `docs/spec.md:61` ("the cap is reached when that next child less `base` would pass it") does describe the code. It is spec rows 4 and README row 4 that the code does not meet.
  UNREPRODUCED. Dispatcher, on a `git archive` copy, as a test-10-style block: `new_job x step; echo '5 5' > "$JOB/child-count"; rc=0; JOB_MAX_CHILDREN=1 "$bo" run "$JOB" || rc=$?`. Expected from the code: `child 6 launched`, then exit 4 with `child cap 1 reached (6 children launched for this job, ...)`. Per README row 4: exit 4 with no child.
- **Suggested fix:** Subtract `base` only under the soft cap: `local used=$n; [ -z "$CAP_SOFT" ] || used=$((n - BASE))`, then compare `used` against `MAXC`. Add the repro above as a test-10 assertion. If the owner instead wants `base` to apply under both caps, reword README row 4 and spec row 4 ("counted since the last paused-cap resume"), correct the baton claim, and make the exit-4 message print `n - base` rather than `launched`.

---

- **Title:** `preflight` (and so the decision to `start`) cannot see `child-count`. A garbled file passes preflight, then the unit dies with the reason only in the journal. A job already at its cap passes preflight and `start`, then exits 4 or 6 with no child
- **Location:** `lib/preflight.sh:13,25-26` (`chain_nums` ... `chain_cap; echo "cap: $MAXC ($CAP_WHY)"`), against `lib/chain.sh:134-135` (`chain_nums` then `chain_count`). `lib/units.sh:28-32` (`unit_check`).
- **Description:** Preflight's header (`lib/preflight.sh:2-4`) promises one line per thing a launch would meet, and it already mirrors `chain_nums`. The new pre-lock `die` sits right next to `chain_nums` in `chain_run`, but preflight neither calls nor shows it.
  - Garbled file (`x`, `08 0`, `1 2`): `preflight: ok`, then `start` returns 0 (`systemd-run` succeeds). The unit's `run` dies at `chain_count` before the EXIT trap, so `run.log` gets no line (`die` is `echo >&2; exit 1`, `bin/blast-off:48`). `blast-off status` shows the checkpoint header and `ActiveState` failed or inactive, with no reason. `blast-off logs` shows the old tail. This matches the other pre-lock `die`s (`CLAUDE_FLAGS`, missing brief), but those are also checked by `unit_check` or preflight before a start. This one is not.
  - Job at its cap (12 launched under the default hard cap): preflight prints `cap: 12 (hard: ...)` with no count, and the start exits 4 at once. The common form of this is P4-22b (next finding).
- **Suggested fix:** In `preflight_run`, call `chain_count` after `chain_nums` (it writes nothing and dies the same way). Print `cap: $MAXC ($CAP_WHY); $LAUNCHED launched, base $BASE, next child $((LAUNCHED+1))`, and add a problem when the next child would already pass the cap. Optionally run the same validation in `unit_check`, so `start` refuses in the foreground instead of the unit dying.

---

- **Title:** README exit-4 remedy ("add a Phase plan table ... and start again") now usually gives an immediate exit 6 with no child. The doc is not updated (owner question P4-22b)
- **Location:** `README.md:136` (exit 4 row, remedy column, unchanged in substance); code `lib/chain.sh:183-186`; `baton-phase-4-work.md:133`.
- **Description:** A hard-cap job stops at `launched` = 12 (default). The owner follows the row and adds a table of R rows. The next run is soft with `MAXC = 3R` and `base` 0, so `13 - 0 > 3R` holds for any R <= 4. That sets `paused-cap` and exits 6 before any child, and a second `run` or `resume` is needed (line 163 then moves `base`). Before this change, `n` started at 0 on every run, so the remedy worked in one start. The diff introduced this inaccuracy. The baton flagged it as an owner question but left the row as it was.
- **Suggested fix:** Add to the remedy: "if the children already launched reach the new soft cap, that start pauses at once (exit 6); `blast-off resume <job-dir>` goes on". Or, in code, have the hard-to-soft switch count from `base` = `launched` when the previous run was hard-capped. That needs a third state and is likely not worth it.

#### LOW

- **Title:** The count is read before the lock. A runner that gets the lock may hold a stale `LAUNCHED`. Two runners on one job dir with different workdir basenames share `child-count` with no lock at all
- **Location:** `lib/chain.sh:135` (`chain_count`) vs `:144` (`chain_lock`); lock key `bin/blast-off:55-58` (`UNIT="blast-off-$NAME"`, `NAME` = workdir basename); `lib/chain.sh:30` (existing ponytail note on stale-lock takeover).
- **Description:** (a) If runner A writes the count and exits between B's `chain_count` and B's `chain_lock`, B proceeds with the old `LAUNCHED`. B then reuses a child number and undercounts by one. The window is only the `PROMPT` assignment, and A must launch and finish a child (at least a 1 s poll) inside it, so it is practically unreachable. (b) The lock is per workdir basename, not per job dir. `blast-off run J /a/x` and `blast-off run J /b/y` take different locks and both drive `J`: both read the same `LAUNCHED`, launch the same child number, and the last writer wins, so the cap undercounts. This is pre-existing for `checkpoint.md`, but the count now inherits it. (c) The racing stale-lock takeover (the ponytail note at line 30) lets two runners share one count the same way.
- **Suggested fix:** Keep the pre-lock call for the clean `die`, and call `chain_count` again right after `chain_lock` (one line) so the value used is read under the lock. (b) and (c) are out of scope; name the shared count in the existing ponytail note.

---

- **Title:** A dangling `child-count` symlink reads as a fresh job (`0 0`) and is silently replaced. This contradicts "never read as 0". A `child-count.tmp` symlink is written through
- **Location:** `lib/chain.sh:119` (`[ -e "$f" ] || return 0`), `:125` (`echo ... > "$JOB/child-count.tmp" && mv -f ...`).
- **Description:** `[ -e ]` follows symlinks and is false for a dangling one, so the cap resets to 0 and the first `chain_count_set`'s `mv -f` replaces the link. A `child-count.tmp` that is a symlink makes the `>` write `"L B"` into the link's target (for example `checkpoint.md`), and the `mv` then renames the link to `child-count`. The next run reads the target's content and dies as garbled. Both need someone to plant a link in the job dir (a child session or the owner), so this is unlikely.
- **Suggested fix:** `[ -e "$f" ] || [ -L "$f" ] || return 0` (a dangling link then reaches `cat`, fails, and hits the existing `die "cannot read"`). Before the write, `rm -f "$JOB/child-count.tmp"`.

---

- **Title:** An in-range but huge count passes validation and wraps `n` negative, so the cap never fires for that run
- **Location:** `lib/chain.sh:121` (regex `^(0|[1-9][0-9]*)\ (0|[1-9][0-9]*)$`), `:183-184`.
- **Description:** Probe (bash, stdout only): `c="9223372036854775807 0"` is accepted and `n=$((L+1))` gives `-9223372036854775808`. `[ $((n-0)) -gt 12 ]` is false, so children launch with negative numbers and no cap. The value written back is then rejected on the next run. `99999999999999999999 0` is rejected (`[: integer expression expected`, which falls through to `die`). This needs a hand-edit to an absurd value.
- **Suggested fix:** Bound the digits: `(0|[1-9][0-9]{0,8})` for both fields.

---

- **Title:** Save-before-launch counts launches that never started a child
- **Location:** `lib/chain.sh:194-195` (`LAUNCHED="$n"; chain_count_set` then `child_launch "$n"`); `lib/child.sh:41-50` (`mktemp -d`, `sed` of the settings template, `tmux new-window`).
- **Description:** If `child_launch` fails under `set -e` (full `XDG_RUNTIME_DIR`, missing template, a tmux error), the runner aborts after the count was written. Each relaunch in that state uses up one count with no child, and the exit-4 message's "N children launched" overstates. This is the intended trade-off (a child cut off by a reboot must count) and it bounds a crash loop. It is not documented.
- **Suggested fix:** Say "launches" rather than "children launched" in the exit-4 message and the spec, or accept as is.

---

- **Title:** The "before child 1" label and comments are wrong on every re-run of a job that has launched children
- **Location:** `lib/chain.sh:172` (`chain_dirty "before child 1"`), `:173` (comment); `bin/blast-off:35`; `docs/spec.md:94,96` (exit 7 and 9 rows). The literal is asserted by `tests/22-dirty-tree.sh:28` (`'dirty tree before child 1: ...'` on a re-run).
- **Description:** After this change, the next child of a re-run is `LAUNCHED+1`, not 1. `run.log` then says "dirty tree before child 1" on a job whose next child is, say, 7.
- **Suggested fix:** `chain_dirty "before child $((LAUNCHED+1))"` and update the test 22 grep (the re-run there launches child 2). Or keep the label and read "child 1" as "this run's first child" in the spec. Either way, the comment at `:173` should say "before this run's first child".

---

- **Title:** The `bin/blast-off` help header was not updated
- **Location:** `bin/blast-off:18` (`JOB_MAX_CHILDREN ... the hard cap (default 12)`), `:33-34` (`4 hard child cap reached`, `6 soft cap reached, status paused-cap (run again)`), `:35`.
- **Description:** README and spec now say the cap counts the job's children across runs and name `child-count`. The `--help` text (printed from these lines, `bin/blast-off:71`) does not, and it is the only place that lists exit 1 causes without a garbled `child-count`.
- **Suggested fix:** Append "per job (its child-count), across runs" to line 18. Exit 1's line already says "usage, dependency or runner error", so nothing is needed there.

---

- **Title:** Duplicated line in test 11
- **Location:** `tests/11-unit-smoke.sh:58-59`
- **Description:** `rm -f "$JOB/child-count"` appears twice in a row, with two different comments: "the job's child count goes on across runs (issue 22); each hang child is child 1 again" and "each start_hang child is child 1 again (issue 22 numbering goes on per job)". It looks like an editing slip. It does no harm.
- **Suggested fix:** Delete one line.

---

- **Title:** No test covers count persistence through `blast-off start` (the unit path). Test 11's reset removes the only `start`→`start` sequence
- **Location:** `tests/11-unit-smoke.sh:58-59`; scenarios that re-run use `run` (10, 21) or launch nothing (12, 31).
- **Description:** The reset hides no real consumer. A grep of `lib/`, `bin/` and `templates/` for `child-1`, `child=1` and `child 1` finds only the `before child 1` label. `stop` and `child_stop_all` use the wildcard `$UNIT-child-*.scope` (`lib/units.sh:83`, `lib/child.sh:30`). The reset only exists because test 11 hard-codes `child=1 pid=` and the `-child-1.scope` name. But it means the systemd path (stop, then start) never checks that numbering goes on. The code is the same `run` under the unit, so the risk is small.
- **Suggested fix:** In test 11, derive the child number from `child-count` (`read -r l _ < "$JOB/child-count"`) instead of deleting the file, and assert it increases across `start_hang` calls.

---

- **Title:** The `chain_count_set` in the paused-cap branch is unpinned
- **Location:** `lib/chain.sh:163`
- **Description:** Mutant: drop `chain_count_set` from line 163. The in-memory `BASE` is right for that run and is saved at the first launch (`:194`), so test 21 passes. The difference only shows when the resumed run ends before any child (exit 0, 3, 7, 9 or 10 in the pre-loop or first pass): the next relaunch reads `base` 0 and pauses again at once (exit 6). No scenario covers it.
- **Suggested fix:** In test 21, after a paused-cap job, make the re-run stop before a child (for example, a dirty tree, or `status: blocked` written before the re-run), then assert that `child-count` holds `L L`.

---

- **Title:** Exit-4 message wording, and its spec claim is only partly asserted
- **Location:** `lib/chain.sh:185`; `docs/spec.md:91` ("the message names `child-count` and a larger `JOB_MAX_CHILDREN` as the way on"); `tests/10-chain-done.sh:75,89` grep only `child cap N reached`.
- **Description:** At the first cap it reads "(1 children launched ...)". A mutant that drops the `child-count` path or the remedy text from the message passes every test. The message also does not mention the other way on that the die text at `:122` names, deleting the file.
- **Suggested fix:** "(launched: $LAUNCHED; $JOB/child-count)". Extend the line 89 grep to `'child cap 2 reached (.*child-count); a larger JOB_MAX_CHILDREN goes on'`.

---

- **Title:** Nothing tells a child or the owner that `child-count` belongs to the runner; deleting it silently resets the cap
- **Location:** `templates/brief.md:4-5` (names `phases/`, `gate-logs/`, `decisions.tsv` as job-dir files); `lib/chain.sh:119` (missing file = fresh job).
- **Description:** A child that tidies the job dir, or an owner who clears runner files, removes the count. The next run starts at child 1 with a full cap, which is the issue's original overrun. `chain_dirty` skips job-dir paths, so nothing notices. A child cannot change the count within a run (it is read once at start).
- **Suggested fix:** Add one clause to the brief template's job-dir sentence: "`run.log` and `child-count` are the runner's; never edit them". Optionally, at the top of `chain_count`, log a "fresh count" line when `run.log` already has a `child N launched` line but the file is missing.

---

- **Title:** Minor spec wording: "two whole numbers" vs the leading-zero rejection
- **Location:** `docs/spec.md:61` ("a file that is not two whole numbers with `base` <= `launched` exits 1"), `:225` (lists `08 0`).
- **Description:** `08 0` is two whole numbers but is refused, which is right because bash would read `08` as octal. The rule is in the test row but not in the env text.
- **Suggested fix:** "two whole numbers without leading zeros".

### Validated

**Confirmed correct**

- **Criterion 1 (a cap reached across two runs stops the job, exit 4).** `tests/10-chain-done.sh:81-83`: a re-run at cap 1 exits 4 with exactly one `child N launched`. `:84-89`: a re-run at cap 2 launches child 2 and exits 4 at `child cap 2 reached`. `:128-130`: the runner cut off by SIGHUP during child 1, re-run at cap 1, exits 4 with no launch. That kills the save-after-wait mutant (baton RED evidence, consistent with the code). For soft-cap jobs, the issue's real incident (cap 27 overrun to 30 after a reboot relaunch of a `running` job) is covered by `tests/21-soft-cap.sh:37-44`: two stalls end run 1 at 2 of 2, and the relaunch exits 6 with no child. Exit 6 rather than 4 is right there, because spec row 6 keeps the soft cap resumable.
- **Criterion 2 (numbering continues).** `tests/10-chain-done.sh:86-87` (exactly one `child 1 launched`, and a `child 2 launched`) and `tests/21-soft-cap.sh:35` (`child 3 launched` after paused-cap, exactly one `child 1 launched`). A mutant that keeps the cap but numbers per run fails `:86`.
- **Criterion 3 (a fresh job starts at 1).** `tests/10-chain-done.sh:16` (`child 1 launched` in the fresh `ok` job), plus `:77` (`^child=1 ` marker) and `:110`. Mutants that read a missing file as anything but `0 0` (for example `1 0`), or `die` on a missing file, turn `:13`/`:16` red. The badcount loop (`:91-96`) kills a mutant that reads an empty file as fresh. Holding with no new assertion is adequate.
- **The two-number file round-trips.** Writing `"$BASE $LAUNCHED"` swapped would make the next read `0 1` (base > launched) and turn `:82` red. A single-number write is rejected by the regex, which also turns `:82` red.
- **`chain_count_set` failure fails closed.** The body `echo > tmp && mv` returns non-zero. The callers at `:163` and `:194` are plain commands. `chain_run` is called unconditioned at `bin/blast-off:65` under `set -euo pipefail` (`:39`), so errexit fires: the EXIT trap logs `runner exit 1 without a state`, and no child launches past an unwritten count. If `child-count.tmp` is a directory, `>` fails and the result is the same. A leftover regular `child-count.tmp` is overwritten. A `child-count` that is a directory or unreadable at start makes `cat` fail, which hits `die "cannot read"` at `:120`.
- **Garbled file.** It exits 1 before the lock, the trap and any child, and the file is left unchanged (`tests/10-chain-done.sh:91-96` covers `''`, `x`, `1`, `08 0`, `1 2`, `-1 0`). This is consistent with the other pre-lock `die`s, which write no `run.log` line (see the preflight finding for the cost).
- **Ordering in the paused-cap branch.** `base` is saved before `cp_set_status running`. If the status write aborts, the next run moves `base` to the same value again (idempotent).
- **Cap exits write nothing.** Exits 4 and 6 come before `:194`, so a re-run at a reached cap is stable.
- **No unbounded loop through soft-cap allotments (bearing on P4-22a).** `usage_arm` (`lib/usage.sh`) is the only timer, armed only from `usage_pause` (paused-limit). `unit_resume` resumes paused-cap only when someone runs it. `systemd/blast-off@.service` has no `Restart=` (`git grep '^Restart'` finds none). Each fresh allotment needs a human `run` or `resume`, the same as before the change. Paused-limit resumes do not move `base`.
- **Blast radius in lib.** Scope names `$UNIT-child-$n.scope` are now unique across runs; stopping uses the wildcard (`lib/child.sh:30`, `lib/units.sh:83`), so the stale-scope stop still covers earlier runs. `jev_pick "$n"` uses `n` only as text in `decisions.tsv`. `status`, `stop`, `logs` and `resume` read no child number.
- **Blast radius in tests.** Tests 22, 23, 30, 40 and 41 count `^child=` lines or grep `child 2 launched` only after a first run of a fresh job, so continued numbering does not make their negative checks vacuous. 12 and 31 launch nothing or a single child. The fake picks `fake-mode` by `JOB_CHILD` (`tests/fakes/claude:44`), and its last line repeats, so a later-numbered child in a single-line-mode job behaves the same. The baton's per-scenario reading agrees. The gate log at f388962 shows 18/18 passing.
- **The test 40 diff is comments only (`:85`, `:104`), and both now match the code.**
- **Style.** One-line helper with a comment above it, as `chain_end` does; `|| die` on reads, as `chain_dirty` does. `local n` uninitialised is safe under `set -u` (assigned at `:183` before any read). `shellcheck -S style lib/chain.sh` is clean; the tests show only SC1091/SC2015 info, the file's existing pattern.
- **Spec env text at `docs/spec.md:61`** describes the code exactly, including `base`. The spec test rows for 10 and 21 match the assertions.

**Examined, inconclusive**

- **P4-22a (lifetime cap vs fresh allotment).** The issue says "JOB_MAX_CHILDREN is a per-run limit, not a per-job one", and its incident is a relaunch of a running job, which the `base` design covers. Keeping spec row 6's fresh allotment is a defensible reading. It is the owner's call; it is not a defect.
- **The baton's RED/GREEN and mutation outputs:** consistent with the code, not re-run (forbidden).

**Not examined**

- The bodies of tests 20, 32, 50, 51, 60, 61 and 70 beyond greps; `tests/lib.sh` `new_job`/`plan` internals; the CI workflow.
- Runtime behaviour of any finding marked UNREPRODUCED.

### Confidence

High on the code reading: `chain_count`/`chain_count_set`, the cap arithmetic, the `set -e` behaviour and the criteria mapping were each traced line by line, and the overflow was probed. For the stale-`base` finding, the arithmetic is certain. How likely a real job's rows drop to 0 after a paused-cap resume is a judgement; the repro is cheap. Medium on the severities of the preflight and README items: both are user-facing gaps, not wrong results.
