### Summary

I reviewed commit dcee737 (`git diff c4e2a41...dcee737 -- . ':!baton-runner'`, 9 files) against issue 39, statically. I read `lib/chain.sh` whole, `bin/blast-off` whole, `lib/units.sh` whole, `lib/preflight.sh:1-60`, the test and doc diffs, `tests/50-checkpoint-size.sh:20-45`, `tests/23-runner-lock.sh:1-40`, `tests/30-paused-limit.sh:131-132`, `lib/child.sh:123`, the work note and `phase-5/findings.md`, and the phase 4 review rows for P4R1-2/3/4/5/7 and P4R2-2. I ran two bash one-liners that write nothing (octal arithmetic on `08` and `[ -gt 010 ]`). No scenario, `tests/run`, `scripts/gate.sh` or `bin/blast-off` was run.

What holds:
- Every issue 39 item is done in code or docs, and every behavioural one has an assertion that kills its obvious mutant (table below). P4R2-1 (`base` read back) and P4R2-2 (in-memory `BASE` at resume) are now pinned.
- `chain_count` returning instead of dying is sound: every caller tests it (`chain.sh:142` `||`, `preflight.sh:30` and `units.sh:74` `if`), so `set -e` never fires inside it and no caller misreads a refusal as a fresh job. The `local b` in `preflight.sh:31` re-declares the function's own `b` (`:9`) after the `for b` loop is done; no shadowing bug.
- preflight's `left = MAXC - LAUNCHED + (CAP_SOFT ? b : 0)` equals chain_run's launch count `MAXC + (CAP_SOFT ? BASE : 0) - LAUNCHED` for: a soft `paused-cap` (b = LAUNCHED, as `chain.sh:171`); a hard job at `5 5` (base ignored); a hard `paused-cap` (BASE not moved, ignored); `JOB_MAX_CHILDREN=0` soft and hard (0 left; the run pauses or exits 4 before any child). It diverges only on leading-zero values (LOW-4) and does not reflect done / blocked / paused-limit (LOW-11).
- Blast radius in tests: the new line `child-count: ...; next child N` / `first child 1` matches no existing assertion. Every `child N` grep in tests 10, 20, 21, 22, 23, 30, 31, 32, 40, 41, 61 is followed by `launched`, `timed`, `usage`, `hit`, etc., or is anchored at `^`; `grep -c 'child [0-9]* launched'` needs a space after `child`; `logt` in test 30 matches ` child 2 launched`; `child_screen`'s `sed` (`lib/child.sh:123`) is anchored at `^child`. Only test 50's `grep -n 'child 2' | head -n 1` is loose (LOW-13, latent).

No CRITICAL or HIGH finding. The silent paths left:
- `start` and `resume` still accept a job that refuses at once: a garbled count, or a bad `JOB_*` number, which still reaches only the journal (MEDIUM-1, MEDIUM-4).
- preflight says `ok` with `0 left` under the hard cap (MEDIUM-2).
- preflight's hard-cap branch has no test (MEDIUM-3).
- The rest is LOW: logging gaps around the soft-cap allotment, raw file content in log lines, the pre-lock refusal, test pins, doc drift.

### Findings

#### CRITICAL

None.

#### HIGH

None.

#### MEDIUM

**MEDIUM-1. `start` and `resume` still launch a unit for a job whose `child-count` the runner will refuse; `start` exits 0.**
- **Location:** `lib/units.sh:28-32` (`unit_check`), `:35-46` (`unit_start`), `:54-68` (`unit_resume`); refusal at `lib/chain.sh:142`.
- **Failure path:** `printf 'x\n' > <job>/child-count; blast-off start <job>`. `unit_check` checks env, brief and checkpoint only. `systemd-run` succeeds and `start` prints `status: blast-off status ...` and exits 0. The runner refuses at once with exit 1. With `resume` (owner or timer), `unit_resume` logs `resume: starting ...`, and the start succeeds, so it stops `<unit>.resume.timer` (`:67`). The job is then paused with no runner and no timer. The only signal is the run.log line this change added.
- **Evidence:** `unit_check`'s own comment: "What `start` needs from the caller's environment and the job dir; checked before anything changes." A readable `child-count` is a job-dir need now. P4R1-3's text was "passes preflight and exits at once". preflight now catches it; `start` still does not.
- **Fix:** in `unit_check`, `chain_count || die "$COUNT_ERR"` (and `chain_nums`, see MEDIUM-4). A garbled count then refuses at `start` and `resume` with exit 1 before any unit exists, and the resume timer stays armed.

**MEDIUM-2. preflight prints `0 left under cap M` and still says `preflight: ok` under the hard cap, where `start` then exits 4 with no child.**
- **Location:** `lib/preflight.sh:30-36, 46`; decision `phase-5/findings.md:13` ("No refusal at the cap (display only, minimal)").
- **Failure path:** a no-Phase-plan job at `12 0` with default cap 12 prints `child-count: 12 launched, base 0; next child 13; 0 left under cap 12`, then `preflight: ok`, exit 0. `start` launches a unit that exits 4 before any child. Under the soft cap the same `0 left` is harmless: the run pauses (exit 6), and `resume` gives a fresh allotment. Under the hard cap no re-run helps without an env or checkpoint change.
- **Evidence:** issue 39, P4R1-3: "a garbled or capped job passes preflight and exits at once". The garbled half is fixed; the capped half is display only, by decision. The README exit-1 row says "`preflight` refused" is how a refusal reads. A script or agent that gates on preflight's exit code gets 0 here.
- **Fix:** add a refusal when `left == 0 && -z CAP_SOFT` and the status is not done or blocked: `probs+=("hard cap $MAXC reached ($LAUNCHED launched); add a Phase plan table or a larger JOB_MAX_CHILDREN")`. Or the owner confirms display only (open question 1).

**MEDIUM-3. preflight's hard-cap branch of `left` has no test; two mutants survive.**
- **Location:** `lib/preflight.sh:31-32`; `tests/60-preflight.sh:111-125` (p7, p8, p9 all run on the soft cap 9 from 3 Phase plan rows).
- **Failure path:** mutant A `local left=$((MAXC - LAUNCHED + b))` (drops `CAP_SOFT ?`). Mutant B removes `[ -z "$CAP_SOFT" ] ||` from `:31`. Every test-60 job is soft, so both pass. Under A, a hard job at `5 5`, cap 12, prints `12 left`; the run launches 7. Under B, a hard `paused-cap` at `9 0`, cap 9, prints `9 left`; the run exits 4 at once. That case is exactly the hard-cap `paused-cap` P4R1-1 and P4R2-4 dealt with.
- **Evidence:** test 60's tail only covers `none`, `9 0`, `9 0 paused-cap` and `x`, all under `cap: 9 (soft: ...)`.
- **Fix:** one hard-cap preflight in test 60: a checkpoint with no Phase plan row, `JOB_MAX_CHILDREN=6`, `child-count` `5 5`, status `paused-cap`. Expect `child-count: 5 launched, base 5; next child 6; 1 left under cap 6`. This kills A (it prints 6) and B (it prints 6).

**MEDIUM-4. The sibling pre-lock refusal, `chain_nums`, still goes to stderr only under `start` and the resume timer; P4R2-9's new bound adds a way to reach it.**
- **Location:** `lib/chain.sh:88-93` (`die`), called at `:140`, before the run.log refusal at `:142` and before the lock and trap at `:151-152`; `lib/units.sh:28-32` (no `chain_nums`).
- **Failure path:** `JOB_MAX_CHILDREN=99999999999999999999 blast-off start <job>`. Before this commit the value was accepted (and turned the cap off); now `chain_nums` dies. `unit_check` does not run `chain_nums`, so `start` exits 0, the unit dies at once, and run.log gets nothing. This is P4R1-2's failure mode exactly, fixed for `child-count` but not for its neighbour two lines up. The other pre-lock dies (`chain.sh:134-137`: deps on the unit's PATH) are the same but rarer.
- **Evidence:** `bin/blast-off:48` `die` writes stderr only; the comment at `chain.sh:141` names the reason ("under start or the resume timer only the journal reads stderr").
- **Fix:** call `chain_nums` in `unit_check`, so `start` and `resume` refuse it in the caller's terminal. Or give `chain_nums` the same `log ... >&2; exit 1` treatment, or both.

#### LOW

**LOW-1. The soft cap's fresh allotment is not logged; the `child-count:` line written just before it shows the old `base`.**
- **Location:** `lib/chain.sh:160` (`log "$COUNT_SAY"`), `:171` (`BASE="$LAUNCHED"; chain_count_set`, then `log "status paused-cap -> running; ..."`).
- **Failure path:** a soft `paused-cap` job at `4 2`. run.log reads `child-count: 4 launched, base 2; next child 5`, then `status paused-cap -> running; the chain continues`. Base is now 4, but no line says so. A reader working out how many children are left gets MAXC-2 instead of MAXC.
- **Fix:** `log "status paused-cap -> running; base $BASE, a fresh allotment of $MAXC; the chain continues"` under the soft branch.

**LOW-2. `COUNT_ERR` holds the file's raw content, unbounded, in run.log, preflight's refusal line and `status`.**
- **Location:** `lib/chain.sh:123-125` (`c="$(cat "$f" 2>&1)"`, `'$c'` in the message); written at `:142`, `preflight.sh:35`, `units.sh:74`.
- **Failure path:** a `child-count` holding several lines gives a multi-line run.log entry; only its first line has a timestamp. It also breaks preflight's one-`name: value`-line contract and makes `preflight: refused:` span lines. A large file (or a symlink to a large file, which `chain_count` follows) is copied whole into run.log, the journal and the terminal. So are terminal escape sequences. This was in the old `die` message too, but that only reached stderr; it now also reaches run.log, preflight and status.
- **Fix:** `c="$(head -c 64 "$f" 2>&1)"` and print `${c//[^[:print:]]/?}`, or `printf %q`.

**LOW-3. A FIFO or character-device `child-count` hangs `chain_count`, and now `status` and `preflight` with it.**
- **Location:** `lib/chain.sh:122-123`.
- **Failure path:** `[ -e ]` is true for a FIFO and for a symlink to `/dev/zero`. `cat` then blocks forever on a writer-less FIFO, or reads `/dev/zero` until memory runs out. Before, only `run` read the file; `status` and `preflight` now hang on it too. Pre-existing for `run`, and rare.
- **Fix:** `[ -f "$f" ] || { COUNT_ERR="$f is not a regular file"; return 1; }` after the existence test. A symlink to a regular file still passes. Pair it with the `head -c` from LOW-2.

**LOW-4. preflight crashes or prints a wrong count on a leading-zero `JOB_MAX_CHILDREN` that `run` accepts and reads as decimal.**
- **Location:** `lib/preflight.sh:32` (`$((MAXC - LAUNCHED + ...))`); `chain_nums` at `chain.sh:91` still accepts leading zeros (decision: "leading zeros keep their old behaviour"); `chain.sh:194` compares with `[ ... -gt "$MAXC" ]`, which reads decimal.
- **Failure path:** probe: `MAXC=08; $((MAXC - 0))` gives `08: value too great for base`, so preflight aborts mid-output with exit 1 and no `preflight: refused` line, while `run` uses cap 8. With `JOB_MAX_CHILDREN=010`, preflight computes octal 8 (`8 left under cap 010`) while `run`'s `[ 11 -gt 010 ]` caps at 10. preflight's `left` is a new arithmetic use of `MAXC`, so this behaviour is new; it is not the "old behaviour" the decision kept.
- **Fix:** `^(0|[1-9][0-9]{0,8})$` in `chain_nums`, or `$((10#$MAXC - ...))` in preflight.

**LOW-5. The garbled-count refusal is written before the lock: it goes into a live runner's run.log and hides the lock message.**
- **Location:** `lib/chain.sh:142` (before `chain_lock` `:151`).
- **Failure path:** while runner A is live, the owner (or a child) garbles `child-count`, and someone runs `blast-off run <job>` again. Runner B writes `<ts> <job>/child-count holds 'x', ...; fix it, or delete it ...` into A's run.log and exits 1. B does not say A is running (`runner N already drives ...`). A then overwrites the file at its next launch (`chain_count_set`), so the logged refusal names a state that no longer exists. Test 23's header ("exits 1 before it touches anything", D1-6) no longer holds for this case. The line also carries no marker that a run refused: no `refused` prefix and no `runner exit 1` line (the trap is not set yet). The other answers to the brief's questions: `LOG` is always set here (`job_init` `bin/blast-off:61`), and a missing job dir dies in `job_init` first.
- **Fix:** move `chain_count` after `chain_lock` and the trap, and refuse with `chain_end 1 "refused: $COUNT_ERR"`. That sets `CHAIN_END`, so no `runner exit` noise; it gives the lock precedence; and it closes LOW-14. Or at least prefix the line with `refused, nothing started:`.

**LOW-6. A missing `child-count` with launches already in run.log is still read as a fresh job, logged as a plain info line.**
- **Location:** `lib/chain.sh:121-122`, `:160`.
- **Failure path:** something other than the owner removes the file: a child's `git clean -fdx`, or a job dir copied without it. The next run logs `child-count: none, a fresh job; first child 1` with no warning, then gives a full cap and numbers from 1 again. P4R2-11 makes deletion the owner's reset, so the behaviour stands. But the log line does not tell a deliberate reset from an accidental one, though run.log already holds `child N launched` lines that would.
- **Fix:** when the file is missing and `grep -q 'child [0-9]* launched' "$LOG"`, say `child-count: none, a fresh job (run.log shows earlier launches: deleted? that resets the cap, P4R2-11); first child 1`. This is display only; it does not recover the count, which the decision rules out.

**LOW-7. The stderr half of the run-time refusal is not pinned.**
- **Location:** `lib/chain.sh:142` `>&2`; `tests/10-chain-done.sh:103-107` (`> badcount.out 2>&1`).
- **Failure path:** mutant `log "$COUNT_ERR"; exit 1` (no `>&2`). The message still reaches `badcount.out` through stdout, and run.log, so test 10 passes. Harmless under systemd (stdout and stderr both go to the journal). It matters to a foreground caller that reads stderr only.
- **Fix:** capture `2> badcount.err` separately and grep that.

**LOW-8. `status` on a garbled `child-count` has no test.**
- **Location:** `lib/units.sh:74` else branch; `tests/11-unit-smoke.sh:42` covers only the good file.
- **Failure path:** a mutant that replaces the `if` with plain `chain_count; echo "$COUNT_SAY"` makes `status` exit 1 under `set -e` at a garbled file, before it prints the resume-timer lines. No test sees it.
- **Fix:** one `blast-off status` on a job with `x` in `child-count`: exit 0 and `^child-count: .*holds 'x'`. No unit is needed; `status` only reads.

**LOW-9. Test 60 p8 does not check its exit code, and the `left > 0 ? left : 0` clamp is not pinned.**
- **Location:** `tests/60-preflight.sh:118-119`; `lib/preflight.sh:33`.
- **Failure path:** p8 sets `rc` and never asserts it, so a preflight that refuses on a `paused-cap` job still passes. No test has `LAUNCHED - base > MAXC` (for example `10 0` at cap 9), so a mutant without the clamp, printing `-1 left`, survives.
- **Fix:** `[ "$rc" -eq 0 ]` after p8; one `10 0` case expecting `0 left`.

**LOW-10. P4R1-7: the save moved to between `child_launch` and `child_wait` still survives; the SIGKILL test leaves the orphan's cleanup unasserted.**
- **Location:** `lib/chain.sh:204-205`; `tests/10-chain-done.sh:158-166`.
- **Failure path:** the new test checks `1 0` only after the child has written `grandchild=`. So the phase 4 mutant "save in the EXIT trap" is now killed, but "`child_launch "$n"; chain_count_set`" is not: the file is written long before the fake child writes its marker. That mutant is near-equivalent (it opens a window of milliseconds), so this is LOW. The comment at `:156-157` also says the re-run "clears what the dead runner left", but no assertion checks the SIGKILLed runner's hang child, grandchild or tmux server is gone after `kill2`. The SIGHUP case checks it at `:149-150`.
- **Fix:** add `wait_until 5 eval "! kill -0 $hung ..."` and `! tmux -L ... has-session` after the `kill2` run, as the hup case does. Note the near-equivalent mutant as accepted.

**LOW-11. preflight shows `N left` for jobs whose run launches no child: status `done`, `blocked`, or `paused-limit` before its reset.**
- **Location:** `lib/preflight.sh:30-33`; compare `lib/chain.sh:175-176` (exit 8) and `:188-189` (exit 0 / 3 before the cap test).
- **Failure path:** a `blocked` job at `2 0`, cap 9, reads `7 left under cap 9`, then `preflight: ok`; `start` exits 3 at once. Display only.
- **Fix:** append the reason when `cp_status` is done, blocked, or paused-limit with `usage_until` in the future (`; none launch: status blocked`). Or leave it and say "left under the cap" means cap only.

**LOW-12. Doc drift: the `bin/blast-off` usage header and the spec's `run` row do not mention the new lines; one spec phrase is ambiguous.**
- **Location:** `bin/blast-off:9` (`status|stop|logs ... checkpoint header + unit state`) and `:12` (preflight prints "flags and level, cap, account, ..."), both without the child count; `docs/spec.md` `run` row (it lists lock, cap line, `paused-cap` -> `running`, dirty check, but not the `child-count:` line or the pre-lock refusal); `docs/spec.md` `21-soft-cap` row, "a `JOB_CAP_FACTOR` of 10 (past 9 digits)", which reads as the value 10 when the test uses `1000000000`.
- **Fix:** add "child count" to `bin/blast-off:9,12`; add the count line and refusal to the spec's `run` row; write "a `JOB_CAP_FACTOR` of 10 digits".

**LOW-13. Latent: test 50's loose `grep -n 'child 2' | head -n 1` would match the new count line on a non-fresh job.**
- **Location:** `tests/50-checkpoint-size.sh:37-38`.
- **Failure path:** the `grow` job is fresh, so its count line reads `first child 1` and does not match. If that job ever started from `1 x` (`next child 2`), or a later edit puts `child 2` in an earlier line, `c2` would be the count line, which comes before the warning, and the test would fail for the wrong reason. No current failure. It is the only positional `child N` read in the suite (blast-radius sweep in Summary).
- **Fix:** `grep -n 'child 2 launched'`.

**LOW-14. `chain_count` reads the file before the lock (pre-existing): a runner that takes over a just-released lock can start from a stale count.**
- **Location:** `lib/chain.sh:142` vs `:151`.
- **Failure path:** runner B reads `3 0`. Live runner A then saves `4 0`, launches child 4, and exits on TERM, releasing the lock in its trap. B then takes the lock and launches a second "child 4"; the cap counts one child fewer. The window is the few statements between `:142` and `:151`, so this is very unlikely. Pre-existing; this commit made it no wider.
- **Fix:** the same move as LOW-5: read the count after `chain_lock`.

### Issue 39 checklist

| Item | Done? | Pinning test (file:line) | Notes |
|---|---|---|---|
| P4R2-1 `base` read back | Yes | `tests/21-soft-cap.sh:47-52` (`base` job, `2 2` at cap 2 -> children 3, 4, exit 6, `4 2`) | Kills `BASE=0` on read (it would exit 6 with no child 3). |
| P4R2-2 in-memory `BASE` at resume | Yes | `tests/21-soft-cap.sh:33` (re-seed `2 0`) + `:37-43` (re-run to done) | Kills mutant MB (writes `L L` to the file only): the re-run would exit 6, not 0. The cap-0 assertion `:29-31` still pins the save (P4R1-8). |
| P4R1-2 refusal in run.log | Yes | `tests/10-chain-done.sh:107`, `:112` | Kills "stderr only". The stderr half is unpinned (LOW-7). Still before the lock (LOW-5). The sibling `chain_nums` refusal is still journal-only (MEDIUM-4). |
| P4R1-3 preflight/status show the count | Partly | preflight: `tests/60-preflight.sh:54`, `:111-125`; status: `tests/11-unit-smoke.sh:42` | The garbled half is refused by preflight. A capped hard job still gets `preflight: ok` (MEDIUM-2); `start` and `resume` do not check (MEDIUM-1). Hard-cap `left` unpinned (MEDIUM-3); status garbled branch unpinned (LOW-8). |
| P4R1-4 / P4-22b README exit-4 remedy | Yes (docs) | none; docs only (70-docs checks rows exist, not text) | The README row now says the start can pause at `paused-cap` and to `resume` then. That matches `chain.sh:171,194-196`. |
| P4R1-5 missing/dangling file; count logged | Yes | logged: `tests/10-chain-done.sh:76`, `:85`; dangling: `:109-113` | Reverting `\|\| [ -L "$f" ]` makes the link fresh, so a child runs and `fake-marker` exists: killed. A missing file is still silent in effect (LOW-6, under ruling P4R2-11). |
| P4R1-7 save-before-launch on a death with no trap | Yes | `tests/10-chain-done.sh:158-166` (SIGKILL; `1 0` while child 1 runs; re-run exit 4, one launch) | Kills "save in the EXIT trap" and "save after `child_wait`". Does not kill "save just after `child_launch`" (near-equivalent). Orphan cleanup not asserted (LOW-10). |
| P4R2-9 `chain_nums` digit bound | Yes | `tests/21-soft-cap.sh:86-90` (`99999999999999999999`, `1000000000`) | `{1,10}` is killed by the 10-digit factor. Leading zeros still accepted, and preflight now mis-reads them (LOW-4). |
| P4R2-10 `start_hang` pid guard | Yes | `tests/11-unit-smoke.sh:63` | Test-only change. |
| Ruling P4R2-4 docs (status may read `running` at exit 4) | Yes | `tests/10-chain-done.sh:97` pins the behaviour | Spec exit-4 column, `chain.sh:98-99` comment, test 21 header `:3-5`: all reworded. |
| Ruling P4R2-11 docs (deleting `child-count` is the one reset) | Yes | none (docs) | Spec Environment paragraph, README exit-4 row, `chain.sh:116`, `:192-193`. The runner's garbled-count message also says "delete it to count ... from 0 again". |
| Ruling P4-22a (soft fresh allotment through `base`; hard never resets) | Holds | `tests/10-chain-done.sh:94-97`, `tests/21-soft-cap.sh:29-43` | `chain.sh:171` moves BASE only when `CAP_SOFT`; `:194` ignores BASE for the hard cap. preflight mirrors both (`preflight.sh:31-32`). The new allotment is not logged (LOW-1). |

Work-unit decisions: `chain_count` returning is sound (all callers test it). A missing file staying fresh is consistent with P4R2-11 (LOW-6 asks for a warning only). A dangling symlink being garbled is sound and pinned. preflight `left` without refusal is a choice that leaves part of P4R1-3 open (MEDIUM-2). status without `left` is sound: the unit's env sets the cap. `chain_nums` bounding digits only is sound for the overflow, but see LOW-4. The `2 0` re-seed is sound and pinned.

### Open questions for the owner

1. Under the hard cap, should preflight refuse at `0 left` (MEDIUM-2)? The soft cap at `0 left` is a working pause/resume, but the hard cap needs an env or checkpoint change first.
2. Should `start` and `resume` refuse a garbled `child-count` and a bad `JOB_*` number up front (MEDIUM-1, MEDIUM-4)? That would keep a paused-limit job's resume timer armed, rather than stopping the timer after starting a runner that refuses at once.
