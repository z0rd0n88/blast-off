### Summary

I reviewed commit f388962 (7 files against main 7867255, `baton-runner/` excluded) as the tests reviewer. The questions: are the new assertions real, what does each bind, and what is left unbound. I did static work only. I ran no scenario, no `tests/run`, no `scripts/gate.sh` and no `bin/blast-off`. My only probes were bash idioms that print to stdout. Criteria 1 and 2 of issue 22 have real assertions, backed by the work unit's RED runs. Criterion 3 rests on existing assertions, and those kill every "fresh job starts at 2" mutant at `tests/10-chain-done.sh:16`. I found no CRITICAL and no HIGH. Five MEDIUM items are binding gaps:
1. Save-before-launch is only exercised where the EXIT trap runs, so a "save on exit" mutant survives.
2. The paused-cap save of `base` is masked by the save before each launch.
3. The `base <= launched` boundary has no case that reads `k k`, so `-le` to `-lt` survives.
4. Test 11's `start_hang` has a duplicated reset line, and the baton's reason for that reset is wrong: without it the test stays green and goes vacuous, because no guard checks `pid`.
5. `[ -e ]` to `[ -s ]` survives, because the `''` case writes a newline.

Ten LOW items follow. Each surviving mutant is in the table with its exact edit.

### Findings

#### CRITICAL

None.

#### HIGH

None.

#### MEDIUM

- **Save-before-launch is tested only on deaths where the EXIT trap runs, so the reboot claim is not bound**
  - **Location:** `lib/chain.sh:194`; `tests/10-chain-done.sh:127-130`; `tests/11-unit-smoke.sh:83-85` (the one trapless death); `docs/spec.md:61` ("written by rename before each child launches, so a child a reboot cut off counts").
  - **Description:** Every relaunch test ends the first run through `chain_end` (exit 4, 5 or 6) or SIGHUP, and both go through `chain_exit`. The hup2 block kills the work unit's mutant (save after `child_wait`), but not one that moves the save into the EXIT trap. The edit: line 194 becomes `LAUNCHED="$n"`, and `chain_exit` gains `[ -z "${LAUNCHED:-}" ] || chain_count_set || true` after line 16. Under that mutant every scenario still sees the right file: a cap exit, a stall exit, SIGHUP and a garbled `die` (which happens before the trap is set) all behave the same. Test 11's `kill` case is the suite's only SIGKILL, and it never reads the count, because `start_hang` deletes the file first and nothing reads it afterwards. A power loss, an OOM kill or a stop that escalates to SIGKILL is exactly the case where "saved before the launch" differs from "saved on exit". Issue 22's hit (27 overrun to 30 after a reboot) is that class. A save placed after `child_launch` but before `child_wait` also survives; that one is near-equivalent.
  - **Suggested fix:** One assertion, and no extra run. In test 10's hup block, after line 118 (the child is hanging, the runner is alive), add `[ "$(cat "$JOB/child-count")" = "1 0" ] || fail "child 1 running, count not saved before its launch: $(cat "$JOB/child-count" 2>&1)"`. It kills the trap mutant and the save-after-wait mutant. It also removes the 30 s timeout the latter costs at line 128. The same line after `tests/11-unit-smoke.sh:85` binds the real SIGKILL path too.

- **The paused-cap branch's save (`chain_count_set` at `lib/chain.sh:163`) is unbound, because line 194 masks it**
  - **Location:** `lib/chain.sh:163`; `tests/21-soft-cap.sh:29-35`; `docs/spec.md:93` ("`child-count`'s `base` moves to `launched`").
  - **Description:** Under the mutant `BASE="$LAUNCHED"` (in memory only), the re-run at 21:29 launches child 3, and line 194 writes `3 2` anyway, so every assertion holds. The difference appears only when a resumed run exits before its first launch: dirty tree (exit 7), unreceipted row (exit 9), or `stop` or a reboot during startup. In that case the status is already `running` but the file still says `2 0`. The next run then pauses again at once, logging "soft cap 2 reached", which costs one wasted run and gives a false message. The order on line 163-164 (save, then status) is also unbound; it matters only for a crash between the two.
  - **Suggested fix:** In test 21, between line 26 and line 27, add `rc=0; JOB_MAX_CHILDREN=0 "$bo" run "$JOB" > zero.out 2>&1 || rc=$?` (soft, because the plan has rows, so `MAXC=0`). Then check `[ "$rc" -eq 6 ] && [ "$(cat "$JOB/child-count")" = "2 2" ] && [ "$(grep -c 'child [0-9]* launched' "$log")" -eq 2 ]`. I traced it statically: the paused-cap branch saves `2 2` and sets `running`; then `n - BASE = 1 > 0` sets `paused-cap` again with exit 6 and no launch. The existing re-run at line 29 then reads `2 2` (see the next item). UNREPRODUCED.

- **The `base <= launched` boundary is never read at equality: `-le` to `-lt` survives**
  - **Location:** `lib/chain.sh:120`; `tests/10-chain-done.sh:91-96`.
  - **Description:** The runner only ever reads back a file it wrote: `n B` with `n > B` (line 194), or `L L` (line 163) that line 194 overwrites before the run ends. No scenario starts a run on a `k k` file, and no test reads a hand-written *valid* file, though the `die` message tells the owner to "fix it" by hand. Under `-lt`, a paused-cap resume that exits before its first child (same paths as above) leaves `L L`. Every later run then exits 1 "garbled" until the owner edits the file. That strands the job; under `-le` it is fine.
  - **Suggested fix:** The `JOB_MAX_CHILDREN=0` run above makes 21:29 read `2 2` and kills `-lt` too. Or add a positive case beside the garbled loop: `new_job okcount step; printf '1 1\n' > "$JOB/child-count"`, then `JOB_MAX_CHILDREN=1` run, expecting `child 2 launched`, no `child 1 launched`, exit 4.

- **`tests/11-unit-smoke.sh` `start_hang`: the reset line is duplicated, and the baton's reason for it is wrong (without it the test goes vacuous, not red)**
  - **Location:** `tests/11-unit-smoke.sh:58-59` (two identical `rm -f "$JOB/child-count"` lines with different comments; the baton describes one); `:62` (`pid` sed for `child=1`); `:66` (`scope=...-child-1.scope`); `:72-73,80`; baton claim "it would break without the reset".
  - **Description:** The job's first run (line 20) leaves `1 0`. With no reset, the first `start_hang` child is child 2. Then `pid` is empty, and `gone ""` is true; probe: `gone() { ! kill -0 "$1" 2>/dev/null; }; gone ""` prints true. `not_active "$TEST_ID-job-child-1.scope"` is also true, because that scope does not exist. So `fail "child $pid alive after stop"` (line 73) and both scope checks (lines 72, 80) pass vacuously. Only the grandchild checks stay real. The test would stay green and stop testing the child and its scope. The duplicated line is dead. The real hazard is the missing guard: any future numbering change hollows this test out silently. Test 10 line 56 (`[ -n "$hung" ] || fail`) has that guard.
  - **Suggested fix:** Delete one `rm` line. Add `[ -n "$pid" ] || fail "no child=1 line ($1): $(cat "$JOB/fake-marker")"` to `start_hang` after line 62. Correct the baton's sentence.

- **`[ -e "$f" ]` to `[ -s "$f" ]` survives: the `''` case is a one-byte file**
  - **Location:** `lib/chain.sh:118`; `tests/10-chain-done.sh:92` (`printf '%s\n' "$bad"` writes `\n` for `''`).
  - **Description:** The file is 1 byte, so `-s` is true, `cat` strips the newline, `c=''`, and the regex dies as before. A truly empty file (0 bytes), which is what a crash between create and write would leave if the rename were ever dropped, is never tested. Under `-s` it reads as a fresh job, which is the "garbled count resets the cap to 0" case that the code comment forbids. The `cat` failure `die` at line 119 is also untested; it is near-equivalent, because an empty `c` dies at the regex anyway.
  - **Suggested fix:** Write the `''` case as `: > "$JOB/child-count"` (true 0 bytes), or add it as a seventh value with a special case in the loop.

#### LOW

- **Regex anchors and second-field branches are partly unbound.** Measured with a probe: dropping `$` lets `1 0 x` match (`BASH_REMATCH` = `1 0`), and no test value has trailing text, an extra field or a tab. The second group is never given a leading zero: `([0-9]+)` for group 2 survives. Under it, `1 08` aborts at `lib/chain.sh:184` with "value too great for base" (probe: rc 1), so the exit is still 1, but the path-naming message is lost. Group 1's leading zero (`08 0`) is caught, but only by the `grep -q "$JOB/child-count"` conjunct at 10:94: the mutant still exits 1 with no marker (arithmetic abort at line 183). `9223372036854775807 0` passes validation, and `n` wraps to `-9223372036854775808` (probe), so the cap never fires. A value one digit longer is rejected (`[: integer expression expected`). Suggested values: `'1 01'`, `'1 0 0'`, `'1 0 '`. A digit-count limit on the regex (e.g. `[1-9][0-9]{0,8}`) closes the wrap.
- **A dangling symlink named `child-count` reads as a fresh job** (`lib/chain.sh:118`; probe: `[ -e /nonexistent ]` false). This is a code gap the work baton already names, not a mutant: a `ln -s nowhere` case in the garbled loop would fail at HEAD (child 1 runs, exit 4). Fix: `[ -e "$f" ] || [ -L "$f" ] || return 0`.
- **Read-before-lock is unbound, and it opens a narrow stale-read window.** `chain_count` (line 135) runs before `chain_lock` (line 144). Moving it after the lock, or after the trap, passes every test: the garbled case still exits 1 with no marker, and test 23's second runner dies at the lock either way. The window: runner B reads `5 0`, live runner A writes `6 0` and exits (releasing the lock), then B takes the lock and runs with `LAUNCHED=5`. That gives a duplicate child number and the cap undercounts by one. The gap is a single assignment, and systemd refuses a second instance of the same unit, so a foreground `run` beside the unit is the only path. Reading right after `chain_lock` and before the trap keeps the clean `die` (a stale lock left by the `die` is taken over next time) and closes the window.
- **The hard cap subtracts `base` too, but spec row 4 says it "counts every child of the job across runs".** `base > 0` under the hard cap only when a soft-capped job loses its readable Phase plan rows (`cp_unread`) after a paused-cap resume. No test has that state, so "hard cap ignores BASE" and "hard cap uses BASE" are indistinguishable. `docs/spec.md:61` defines the cap with `base` for "either cap", so the two spec sentences disagree slightly. Pick one and say it.
- **The new exit-4 message tail is unasserted.** `docs/spec.md:91` says the message "names `child-count` and a larger `JOB_MAX_CHILDREN` as the way on". Tests 10:75 and 10:89 match only the prefix `child cap N reached`, so reverting line 185 to the old text survives.
- **Test 31's `cap` resume (lines 58-61) passes regardless of the `base` logic.** The job is fresh (no file, `LAUNCHED=0`), so the `blast-off resume` path (`lib/units.sh:54-68`, which leaves the status to the runner) never meets a reached cap. It is the same `chain_run` code test 21 binds through `run`, so this is a note, not a gap. I traced `unit_resume` and confirmed it does not set `running` itself, so the paused-cap branch does fire on resume.
- **P4-22b is untested and undocumented.** README row 4's remedy after exit 4 ("add a Phase plan table ... and start again") now pauses at once (exit 6, no child) when the children already launched reach rows x factor, and only a second start continues. No test covers it, and the README row does not say so.
- **Test 21's `relaunch` case (lines 37-44) proves what its comment says, with one omission.** Under the old per-run counter the re-run launches child 1 (count 3), and under "reset `base` on every start" it launches child 3; both are killed. It does not assert `status: paused-cap` after the exit 6, though spec row 21 implies it. One `grep -q '^status: paused-cap$'` closes that.
- **Stale wording left by the change (not in the diff).** `lib/chain.sh:172` logs `before child 1` on every re-run (the work baton flagged this; tests 22:28 and 40 pin the literal). `lib/child.sh:9-10` says earlier scopes "hold the names child_launch reuses", which is now true only after the count is reset. The glob stop at `lib/child.sh:30` still covers every stale number, so behaviour is fine. Test 10's stray-scope case (104-113) uses a fresh job, so its premise (child 1 reuses the name) still holds.
- **Upgrade path.** A job that is mid-flight from before this change has no `child-count` file, so its first run under the new code counts from 0 and restarts run.log numbering at 1. It happens once and is not covered. One sentence in the spec's env text would document it.
- **`LAUNCHED` and `BASE` are unprefixed globals.** If the owner's environment exports `BASE`, the runner overwrites it and children inherit the number. This is cosmetic; `JOB_`-style or `CHAIN_` names would avoid it.

#### Surviving mutants for the dispatching unit (all UNREPRODUCED, runs forbidden in this review)

| Exact edit | Assertion expected to catch it | Prediction |
|---|---|---|
| `lib/chain.sh:117` `LAUNCHED=0 BASE=0` -> `LAUNCHED=1 BASE=0` (a missing file starts at `1 0`, first child 2) | `tests/10-chain-done.sh:16` (`child 1 launched` absent); also 10:77 (cap 1: `2-0 > 1`, exit 4 before any child, no marker), 20:15 | killed |
| `lib/chain.sh:118` `[ -e "$f" ] \|\| return 0` -> `[ -e "$f" ] \|\| { LAUNCHED=1; return 0; }` | 10:16, 10:77 | killed |
| `lib/chain.sh:118` `-e` -> `-s` | none (the `''` case is `\n`, 1 byte) | survives |
| `lib/chain.sh:120` delete `&& [ "${BASH_REMATCH[2]}" -le "${BASH_REMATCH[1]}" ]` | 10:94, value `1 2` (child 2 launches, marker exists) | killed |
| `lib/chain.sh:120` `-le` -> `-lt` | none (no run reads `k k`) | survives |
| `lib/chain.sh:120` group 1 `(0\|[1-9][0-9]*)` -> `([0-9]+)` | 10:94, value `08 0`, only via the `grep -q "$JOB/child-count"` conjunct (arithmetic abort at line 183, rc 1, no marker) | killed |
| `lib/chain.sh:120` group 2 `(0\|[1-9][0-9]*)` -> `([0-9]+)` | none (no second-field leading zero in the list) | survives |
| `lib/chain.sh:120` drop the trailing `$` | none | survives |
| `lib/chain.sh:120` drop the leading `^` | 10:94, value `-1 0` (matches `1 0`) | killed |
| `lib/chain.sh:121` insert `echo "0 0" > "$f";` before `die` | 10:95 (file rewritten) | killed |
| `lib/chain.sh:121` `die ...` -> `{ LAUNCHED=0 BASE=0; return 0; }` (garbled read as 0) | 10:94 (exit 4, marker) | killed (work unit reproduced) |
| move `chain_count` from line 135 to just after `chain_lock` (line 144) | none | survives |
| move `chain_count` to just after `trap 'chain_exit $?' EXIT` (line 145) | none (still rc 1, message, no marker, file unchanged) | survives |
| `lib/chain.sh:125` `echo ... > "$JOB/child-count.tmp" && mv -f ...` -> `echo "$LAUNCHED $BASE" > "$JOB/child-count"` | none (crash atomicity) | survives |
| `lib/chain.sh:163` `BASE="$LAUNCHED"; chain_count_set` -> `BASE="$LAUNCHED"` | none (line 194 writes `3 2` anyway) | survives |
| `lib/chain.sh:163` delete `BASE="$LAUNCHED";` | 21:30 (re-run exit 6) | killed (work unit reproduced) |
| swap lines 163/164 so `cp_set_status running` runs before `chain_count_set` | none (crash window only) | survives |
| move `BASE="$LAUNCHED"; chain_count_set` out of the case to just before line 162 (reset on every start) | 10:83 (re-run at cap 1 launches child 2), 21:44 | killed |
| `lib/chain.sh:184` `$((n - BASE))` -> `$n` | 21:30 (re-run `3 > 2`, exit 6) | killed |
| `lib/chain.sh:184` `[ $((n - BASE)) -gt "$MAXC" ]` -> `{ [ -n "$CAP_SOFT" ] && [ $((n - BASE)) -gt "$MAXC" ]; } \|\| { [ -z "$CAP_SOFT" ] && [ "$n" -gt "$MAXC" ]; }` | none (no hard-cap job with `base > 0`) | survives |
| `lib/chain.sh:185` message back to `"child cap $MAXC reached"` | none (10:75, 10:89 match the prefix) | survives |
| `lib/chain.sh:194` `LAUNCHED="$n"; chain_count_set` -> `LAUNCHED="$n"`, and add `[ -z "${LAUNCHED:-}" ] \|\| chain_count_set \|\| true` to `chain_exit` after line 16 | none (every first run ends via a trap) | survives |
| `lib/chain.sh:194` moved to after `child_wait` (after line 196) | 10:130 (two launches, after the 30 s timeout) | killed (work unit reproduced) |
| `lib/chain.sh:194` moved to between `child_launch` (195) and `child_wait` (196) | none | survives (near-equivalent) |
| `lib/chain.sh:194` moved above the cap check (before line 184) | 10:87 (re-run at cap 2: `LAUNCHED=2`, `3 > 2`, no child 2) | killed |
| per-run numbering, cap still per job: line 133 add `r=0`, line 195 `child_launch "$((++r))"` | 10:86 (`child 1 launched` twice), 21:35 | killed |
| `tests/11-unit-smoke.sh` delete both `rm -f "$JOB/child-count"` lines (58-59) | none: `pid` empty, `gone ""` true, child-1 scope never exists | survives (test goes vacuous) |

### Validated

- Criterion 1 (cap across two runs, exit 4): `tests/10-chain-done.sh:81-83` (re-run at reached cap 1: exit 4, still one launch), `:84-89` (cap 2 over two runs: child 2 launched, no child 3, `child cap 2 reached`, exit 4), `:127-130` (relaunch after SIGHUP). The old per-run counter fails 10:83; the work unit's RED run shows that exact line.
- Criterion 2 (numbering continues): `10:86-87`, `21:35`. The per-run numbering mutant is killed at 10:86.
- Criterion 3 (fresh job starts at 1): `10:16` and `10:77`, plus every scenario that greps `child 1` or `^child=1 ` on a fresh job (20, 30, 50). Every "missing file reads as `1 0` / `LAUNCHED=1`" mutant dies at 10:16, before 10:77 runs.
- `[ ! -e "$JOB/fake-marker" ]` (10:94) proves "before any child": `new_job` (`tests/lib.sh:21-28`) does not create the marker, and the fake `claude` writes it first thing. `die` goes to stderr (`bin/blast-off:48`) and the test captures `2>&1`, so the path grep sees the message.
- The six garbled values cover: empty, non-digit, missing field, group-1 leading zero, `base > launched`, sign/start anchor. Gaps are listed above.
- Decision "garbled exits 1 and file left as-is": bound by 10:94-95.
- Decision "two numbers / paused-cap fresh allotment": bound by 21:30 and 21:35 (dropping the reset is killed). Only the *persisting* of the reset is unbound.
- Test 21 `relaunch`: proves that a non-paused-cap relaunch keeps the soft count (exit 6, two launches).
- `blast-off resume` does not touch the status (`lib/units.sh:48-53`), so the runner's paused-cap branch is what moves `base` on a timer or owner resume.
- Stale scopes are stopped by glob (`lib/child.sh:30`), so continued numbering leaves no scope of an earlier run alive.
- Blast radius: 12 and 41 launch nothing on re-run. 22's re-runs (`dirty`, `rename`, `bare`) refuse before a child or assert no child number. Every 30 case uses `fresh`, a new job, and its only same-job re-run (42) refuses with exit 8 before a child. 23's `stale` job and 40's `chain` job launch a later-numbered child with single-line fake modes and assert no number. 32, 50 and 61 use one run per job. I found none that now passes for a different reason, except test 11 if its reset is lost (above) and test 31's `cap` job (fresh, LOW).
- Spec §6 row 10 matches 10:79-96 and 10:127-130. Row 21 matches 21:34-44. Row 10's "(the count is saved before a launch)" is bound only on the trap path (MEDIUM above).
- The gate log at f388962 shows 18/18 PASS and shellcheck ok.

### Confidence

High on the killed/survives predictions for the `lib/chain.sh` mutants. I traced each through the scenario's runs and the fake's mode-by-`JOB_CHILD` rule. I checked the arithmetic abort, the regex anchors, int64 wrap, `gone ""` and `[ -e ]` on a missing path with stdout-only bash probes. The `JOB_MAX_CHILDREN=0` fixture is traced, not run. Medium on test 41 past line 284: I read only grep hits there and rely on its jobs being `status: done`, plus the gate pass. Nothing here was run end to end.
