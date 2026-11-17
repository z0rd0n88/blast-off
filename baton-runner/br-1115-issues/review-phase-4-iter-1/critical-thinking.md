### Summary

I read the 7-file diff of f388962 against 7867255. I also read all of `lib/chain.sh`, `lib/child.sh:1-60`, `lib/units.sh:25-83`, `systemd/blast-off@.service`, and the `jev_pick` body. I read the `JOB_CHILD` lines in `tests/fakes/claude`, the work baton, `phase-4/findings.md`, issue 22 and the phase 4 gate log (`GATE: PASS passed=18`). I grepped every production consumer of the child number and the scope name. Static work only. I ran no scenario, no `tests/run`, no `scripts/gate.sh` and no `bin/blast-off`. I ran three inline bash probes that touch no repo file:
- set -e on a failing `a && b` inside a function: the caller exits 1.
- `[ 0 -le 99999999999999999999 ]`: "integer expression expected", rc 2.
- `9223372036854775807 + 1` wraps to a negative number.

The main path works. A job that starts in hard-cap mode keeps `base` at 0, so its cap is per job, numbering continues, and a fresh job starts at 1. Each of the three criteria has an assertion that a mutant would turn red (see Validated).

The weak point is one unexamined assumption. The baton (line 50) says "the hard cap has no reset path", findings.md line 12 says "the hard cap counts every child of the job", and spec row 4 says "the cap counts every child of the job across runs". None of these holds once `base` is nonzero. `base` does not depend on the cap mode. The paused-cap branch moves it in any mode, and the hard cap subtracts it. So a job that was ever soft-paused, or that starts with `status: paused-cap`, gets a hard cap counted from `base`, not from 0. The exit-4 message then reports more children than the cap. That is item 1, MEDIUM. Everything else is LOW: edge cases of the counter file, test gaps, a duplicated test line, and doc and label wording.

Counts: CRITICAL 0, HIGH 0, MEDIUM 1, LOW 13.

### Findings

**1. MEDIUM: the hard cap subtracts `base`, so the cap can be reset and the claim "the hard cap counts every child of the job" is false**

- **Location:**
  - `lib/chain.sh:163`: the paused-cap branch sets `BASE="$LAUNCHED"` whatever `CAP_SOFT` is. `chain_cap` has already run at :151, so the mode is known here.
  - `lib/chain.sh:184`: `[ $((n - BASE)) -gt "$MAXC" ]` is used for both caps.
  - `lib/chain.sh:185`: the exit-4 message.
  - `docs/spec.md` row 4 ("the cap counts every child of the job across runs") and the §2 `JOB_MAX_CHILDREN` text ("either cap counts the job's children, not one run's").
  - `README.md` exit-4 row ("counted over every run of the job").
  - Baton line 50 and `phase-4/findings.md:12,16`.
- **Description:** There are three ways a hard-mode run gets `base > 0`:
  - (a) A job paused on its soft cap and was resumed (base = 9 with 3 rows x 3). Then its Phase plan stopped being read: a child rewrote or broke the table (`cp_unread`), or the owner removed it. On the next start, `chain_cap` picks the hard cap of 12 and the loop counts it from 9. Children 10 to 21 launch, and the message reads `child cap 12 reached (21 children launched for this job, ...)`.
  - (b) `checkpoint.md` holds `status: paused-cap` when a hard-mode run starts, and :163 hands out a fresh 12. That status is plain text in a file children edit. The loop ignores a child-written `paused-cap` mid-run (:179-182 act only on done and blocked), but it is still there at the next relaunch, such as a reboot. So a child, or a leftover status, resets the hard cap without the owner doing anything.
  - (c) A hand-written but valid file, for example `5 5`.

  The message's way on, "a larger JOB_MAX_CHILDREN goes on", is wrong for any of these. With base 9, an owner who reads "21 launched" and sets `JOB_MAX_CHILDREN=30` gets 18 more children, not 9. No test has `base > 0` in hard mode, so a mutant that uses `n` in place of `n - BASE` for the hard cap only survives every scenario. Issue 22's point is that the cap must survive relaunches. Route (b) is exactly a relaunch that gets past it.
- **Question for the author:** Why should `base`, which exists only to give the soft cap its fresh allotment (baton line 50), apply to the hard cap at all?
- **Suggested fix:** Pick one and make code, spec §2 / row 4, README row 4 and findings.md agree:
  - In hard mode, compare `n` (not `n - BASE`), and move `base` at :163 only when `CAP_SOFT` is set.
  - Or keep the current behaviour and say in spec row 4 and the message that the hard cap counts from the last paused-cap resume, with the message printing `n - BASE`, not `LAUNCHED`.

  Add one scenario row either way.
- **UNREPRODUCED.** On a `git archive` copy, append to `tests/10-chain-done.sh` after the badcount loop: `new_job basehard step; printf '5 5\n' > "$JOB/child-count"; rc=0; JOB_MAX_CHILDREN=1 "$bo" run "$JOB" > bh.out 2>&1 || rc=$?; echo "rc=$rc" >&2; grep -E 'launched|cap' "$JOB/run.log" >&2`, then run `BLAST_OFF_TEST_ONLY=10-chain-done tests/run`. Expected by reading: `child 6 launched`, rc=4, and `child cap 1 reached (6 children launched for this job, ...)`. Route (b) is the same with `sed -i 's/^status: .*/status: paused-cap/' "$JOB/checkpoint.md"` and `printf '3 0\n'` in place of `5 5`. Expected: `status paused-cap -> running`, then `child 4 launched` past hard cap 1.

**2. LOW: a dangling symlink at `child-count` is read as a fresh job (0 0), against "never read as 0"**

- **Location:** `lib/chain.sh:118` (`[ -e "$f" ] || return 0`). The spec §2 text says "is never read as 0". The baton's risk list (line 137) admits the case, but the spec and the code comment (:114-115) do not.
- **Description:** `-e` follows the link. A link whose target has gone, for example a job dir copied with `cp -a` from elsewhere, reads as `0 0`. The cap and the numbering silently restart, and :194 then replaces the link with a regular file.
- **Suggested fix:** `[ -e "$f" ] || [ -L "$f" ] || return 0`, so `cat` fails and `die` names the file. Or say the exception in the spec.

**3. LOW: a value near INT64_MAX passes the parser and turns off the cap**

- **Location:** `lib/chain.sh:120` and :183-184.
- **Description:** The regex has no length limit. `9223372036854775807 0` passes the parser and the `-le` check. Then `n=$((LAUNCHED+1))` wraps to -9223372036854775808 (probe above), `n - BASE` is never greater than MAXC, and the cap never fires. One digit more is caught: `[` fails with "integer expression expected", rc 2, so `die`. Only a hand edit gets here, but "a garbled count must not reset the cap" (:114-115) is the stated design goal.
- **Suggested fix:** Bound the digits (`[1-9][0-9]{0,8}`).

**4. LOW: `child-count.tmp` as a symlink or a directory**

- **Location:** `lib/chain.sh:125`.
- **Description:**
  - Symlink: `echo >` writes through it to the link's target, overwriting any file the owner can write. `mv -f` then renames the link itself to `child-count`, so the job's count is now a symlink to that file.
  - Directory: `echo >` fails, and set -e aborts the runner as `runner exit 1 without a state`. That happens at the paused-cap branch or before the first launch, on every start, until someone removes it, and the only clue is bash's error on stderr / in the journal. It is safe, since the cap is not bypassed, but opaque.

  A leftover regular `child-count.tmp` is harmless, as the baton says: it is overwritten. There is no privilege boundary, because children run as the owner.
- **Suggested fix:** `rm -f` the tmp path first, or accept this and note it. No action is needed for the cap.

**5. LOW: a launch that fails after the save uses up a cap slot with no child and no `child N launched` line**

- **Location:** `lib/chain.sh:194-195` and `lib/child.sh:44-50`.
- **Description:** The count is saved before `mktemp -d`, `sed` and `tmux new-window`. If any of these fails, set -e aborts after the count went up, and the `log "child $n launched"` line (`child.sh:50`) is never written. Each such failed start uses up one slot. A broken tmux and a few retries can exhaust a hard cap of 12 with no child having run. run.log then shows gaps in the numbering, and the exit-4 message says "N children launched". The baton chose to over-count rather than under-count, which is fine. It just is not stated that "launched" includes launch attempts that failed.
- **Question:** Is "launched" meant to be "attempted"? If so, should the spec say so?

**6. LOW: a garbled count under a unit (start, resume, or the resume timer) leaves nothing in run.log**

- **Location:** `lib/chain.sh:135` (before `chain_lock` and the EXIT trap), and `bin/blast-off:48` (`die` writes to stderr only).
- **Description:** The baton calls this "a clean die". For a foreground `run`, it is. Under a unit, the message goes only to the journal. The status stays `paused-limit` or `paused-cap`, because the runner clears it only after the lock, and a timer that fired is now spent. `blast-off status` shows a paused job with no resume timer and no reason. This matches the other pre-lock dies (CLAUDE_FLAGS, DEPS), so it is consistent, but the new failure mode is one an owner will hit only under a unit.
- **Suggested fix:** None needed. Optionally `log` before `die` here, since `$LOG` is known after `job_init`.

**7. LOW: the read-before-lock window, and the documented stale-lock race, now also corrupt the count**

- **Location:** `lib/chain.sh:135` versus :144, and the `ponytail:` note at :30.
- **Description:**
  - Read-before-lock: the window is :135 to :144 (`chain_nums` and the `PROMPT` assignment). A second runner reads first and then dies at the lock while the first is alive. A stale count would need the first runner to launch, finish and release the lock inside that window, which is not practical. I confirm the baton's claim here.
  - Stale-lock race: the race the code already accepts (two runners both take a stale lock) now also makes both runners read the same `LAUNCHED`. Both launch `child LAUNCHED+1`, and both write `LAUNCHED+1`. The result is duplicate numbers and an undercount of one per pair. Two runners already break the tmux server and the scope names, so this adds little.
- **Suggested fix:** Moving `chain_count` after `chain_lock` costs nothing but the "not logged as an abort" nicety. Otherwise leave it, and add "and the child count" to the `ponytail:` note.

**8. LOW: test 11 has the same line twice**

- **Location:** `tests/11-unit-smoke.sh:58-59`: two `rm -f "$JOB/child-count"` lines with two different comments.
- **Description:** It looks like an edit applied twice. It is harmless but noisy.
- **Suggested fix:** Delete one.

**9. LOW: test 11's reset means the unit path (`start`) never exercises the persisted count**

- **Location:** `tests/11-unit-smoke.sh:58-59`, and :28, :38, :62, :66 (the `child=1`, `-child-1.scope` hard-coding).
- **Description:** No production consumer depends on `child-1`. `child_stop_all` (`child.sh:30`) and `unit_stop` (`units.sh:83`) use the `-child-*.scope` glob, and `JOB_CHILD` is read only by the fake. So the `rm` hides no real consumer. But test 11 is the only scenario that restarts one job through `blast-off start`, and the `rm` makes every restart a fresh job. So no test shows that the count survives a unit-started relaunch, which is the issue's reboot story. I expect it does, by reading: the same `run %f`, and the same `$JOB` from `job_init`.
- **Suggested fix:** Make the test parse the latest `child=N` and scope name instead of deleting the count. Or add one unit-path assertion that the second start's child is child 2.

**10. LOW: no test covers the save at the paused-cap branch**

- **Location:** `lib/chain.sh:163` (`chain_count_set`).
- **Description:** If you remove that call and keep `BASE="$LAUNCHED"` in memory, test 21 still passes, because :194 writes `3 2` at the next launch. The save matters only when the re-run exits before any child (dirty tree exit 7, receipt exit 9). In that case the status is already `running`, and without the save the next start re-pauses at exit 6. That costs one extra start. The code is right; the test just does not check it.
- **Suggested fix:** Optional. In test 21, after a paused-cap re-run that exits 7, assert that `child-count` reads `2 2`.

**11. LOW: the exit-4 way on (README row 4, P4-22b) now takes two starts, and hard-capped children count against the first soft allotment**

- **Location:** `README.md` exit-4 row ("add a Phase plan table with a row per phase and start again"), and `lib/chain.sh:184,186`.
- **Description:** I confirm P4-22b by reading. After exit 4 at 12 launched, adding a 4-row table gives a soft cap of 12 with `base` 0, so the next start exits 6 with no child, and only a second start moves `base`. With a 5-row table, the soft cap is 15, so the next start gives only 3 children. Children counted under the hard cap count against the first soft allotment. The exit-6 message does say "run again", so the owner is not stuck, but README row 4 describes a one-step way on.
- **Question:** Is it intended that the first soft allotment after a hard-cap exit is reduced by the hard-capped children?

**12. LOW: the label `chain_dirty "before child 1"` is wrong on a re-run, now that run.log numbers children per job**

- **Location:** `lib/chain.sh:172`. Literal matches in `tests/22-dirty-tree.sh:28` and the spec rows.
- **Description:** In test 22's re-run (:25-28), the next child would be child 2, but run.log says `dirty tree before child 1`, in a log that already has a `child 1 launched` line from the first run. Before issue 22, "child 1" meant "this run's first", which was true because numbering restarted. Now run.log numbering is per job, so the label points at the wrong child.
- **Suggested fix:** Use `before child $((LAUNCHED+1))`, and update test 22:28 and the spec rows. Or use "before this run's first child".

**13. LOW: `preflight` and `status` cannot show that a job is already at its cap**

- **Location:** `lib/preflight.sh:25-26` (`cap: $MAXC ($CAP_WHY)`) and `lib/units.sh:70+`.
- **Description:** `preflight` prints `cap: 12` for a job whose next start exits 4 before any child. `status` shows nothing about the count. Before this change, a fresh run always had its full cap, so the cap line was the whole truth. Now it is not. The baton lists this as outside the criteria.
- **Suggested fix:** Add `launched L, base B` to preflight's cap line, which costs one `chain_count` call. Note that this means preflight reads the file, which `findings.md:6` chose against.

**14. LOW: children can reset the count, and the brief does not tell them the file is the runner's**

- **Location:** `templates/brief.md:4-5`, which lists the job dir's own files (`phases/`, `gate-logs/`, `decisions.tsv`) but not `child-count`. Also item 1(b).
- **Description:** A child that tidies the job dir and deletes an unknown `child-count`, or writes `status: paused-cap`, resets the cap at the next relaunch. Mid-run the count lives in memory, so the current run is safe. This is a trust question, not a bug.
- **Question:** Is the cap meant to hold against a misbehaving child, or only against runner relaunches? If the former, say in the brief that `child-count` belongs to the runner.

**Docs nits (LOW, folded here):**

- Spec §2 says `child-count` is "written by rename before each child launches", but it is also written at the paused-cap resume (:163).
- Spec row 6 says "a re-run of `run`", but `resume` reaches the same branch through `unit_start`.
- The spec §6 row for `10-chain-done` still says "a stale scope of the same job is stopped before child 1". That is true only for a fresh job, which that test uses (:107), so it is fine as written.

### Owner-level open questions

1. **P4-22a (soft cap semantics).** I agree with the baton's choice to keep the fresh allotment on a paused-cap resume, and I confirmed that nothing automates it. The unit template has no `Restart=` ("No Restart:" at the head of `systemd/blast-off@.service`). The resume timer is armed only by `usage_pause` (paused-limit). `unit_resume` on paused-cap is an owner act. So a timer cannot loop through soft allotments without bound. The question for the owner stays: lifetime cap or per-resume allotment?
2. **Should `base` touch the hard cap at all?** (item 1.) If the hard cap is meant to count every child of the job, the code must ignore `base` in hard mode, and :163 must not move `base` when `CAP_SOFT` is empty.
3. **P4-22b.** Should README row 4 say that adding a Phase plan after exit 4 may need a second start, and that earlier children count against the first soft allotment? (item 11.)
4. **Reusing a job dir.** "A fresh job starts at 1" means "no `child-count` file". A job dir reused for a new brief keeps counting. Is `rm child-count` the intended reset, and should the README say so?
5. **Children and the count.** Is the cap meant to hold against a child that deletes `child-count` or writes `status: paused-cap`? (item 14.)

### Validated

**Confirmed correct:**
- **Criterion 1** (cap across two runs, exit 4):
  - `tests/10-chain-done.sh:81-83`: a re-run at a reached cap 1 exits 4 with one launch line in total.
  - `:84-89`: run 2 at cap 2 launches child 2 and exits 4, `child cap 2 reached`, no child 3.
  - `:127-130`: a runner cut off by SIGHUP, re-run at cap 1, exits 4.
  - Mutants killed: the old `local n=0` (the baton's RED at :83), and save-after-wait (the baton's mutation, :130).
- **Criterion 2** (numbering continues): `tests/10-chain-done.sh:86-87` (exactly one `child 1 launched`, then `child 2 launched`) and `tests/21-soft-cap.sh:35` (`child 3 launched` after paused-cap). A run-local log counter kills :86.
- **Criterion 3** (fresh job at 1): `tests/10-chain-done.sh:16` (`child 1 launched` on the fresh `ok` job) and :77 (`^child=1`). Defaulting a missing file to `LAUNCHED=1`, or dying on it, turns :16 red. The criterion is held, just not by a new line.
- The soft cap survives a relaunch that is not a resume: `tests/21-soft-cap.sh:39-44` (exit 5, then exit 6 with 2 launches). This is the issue's 27-to-30 case.
- **Garbled values.** `''`, `x`, `1`, `08 0`, `1 2`, `-1 0` each die, at `tests/10-chain-done.sh:91-96`. An unreadable file or a directory dies through `cat ... || die` (:119). `08` is rejected by the regex before any arithmetic, so there is no octal trap. A 20-digit value dies through `[`'s rc 2 (probe). CRLF and a second line fail the anchored regex. The exceptions are items 2 and 3.
- **`chain_count_set` failure under set -e.** A failing `echo >` makes the `&&` list return 1, and the function call then trips errexit in `chain_run`. `chain_run` is called plainly at `bin/blast-off:65` (probe: rc 1, "survived" not printed). The launch is stopped and the cap is not bypassed. The EXIT trap is set by both call sites (:163, :194), so run.log gets `runner exit 1 without a state`.
- **Save-before-launch.** The order (cap check, backoff, `jev_pick`, save, launch) means that a cap exit writes nothing and a child cut off by a reboot counts. `jev_pick` uses `n` only as a label (`lib/jev.sh:48-68`).
- **Crash between the paused-cap save and `cp_set_status running`** (:163-164). The re-run sets `base` to the same value again, so this is idempotent.
- **Blast radius in production.** Only `child.sh:47-48` uses `n` (the scope name and `JOB_CHILD`). Stop paths use the `-child-*` glob (`child.sh:30`, `units.sh:83`). Nothing in `bin/` or `lib/` is keyed on `child-1`. Per-job unique scope names across relaunches, if anything, lower the risk of a name clash with a stale scope.
- **Blast radius in tests.** `fake-usage-N` is used only in test 32, which runs once per job. The full gate at f388962 passed 18 of 18, including 12, 22, 23, 30, 31 and 41, which re-run job dirs.
- **The dirty-tree check skips `child-count` and `.tmp`** through the `JOBREL` prefix (`lib/chain.sh:66`). The brief forbids committing the job dir (`templates/brief.md:107`).

**Examined, inconclusive:**
- A leftover resume timer firing on a job that a manual `run` has since driven to paused-cap would give an unattended fresh allotment. By reading, this needs a manual `run` at the same moment as the timer: `run` refuses until the reset passes, and a timer that fires while a runner holds the job hits `unit_resume`'s "status is 'running'" die. I did not check whether `usage_until` and the timer's calendar time differ by `JOB_RESUME_MARGIN`. If they do, the window is that margin.
- Test 11's `start_hang` fix was not proven RED (the baton says so too). By reading, the `child=1 pid=` sed at :62 would come back empty on the second start.

**Not examined:**
- `tests/23-runner-lock.sh`, `30`, `31` and `41` beyond the gate result and the baton's notes.
- `lib/usage.sh` beyond the grep for the timer.
- `lib/cp.sh` (`cp_status`, `cp_phases`, `cp_unread`) internals: I assumed `cp_phases` returns 0 when the table is unreadable, as the `chain_cap` comment says.
- `tests/70-docs.sh`'s literal checks against the new spec text.

### Confidence

Medium-high. Every claim cites a line I read or a probe I ran. Item 1 is a direct reading of :163 and :184 with no branch between them, and the reproduction command will confirm it in one scenario run. Items 2 to 7 are edge cases with exact mechanisms but no runs. Items 8 to 14 are test, doc and design notes. I give the least confidence to the resume-timer window (Examined, inconclusive), because I did not read `usage_until` and the timer's calendar setup in full.
