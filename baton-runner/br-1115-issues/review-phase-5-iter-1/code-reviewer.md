# code-reviewer: phase 5 (issue 39), round 1

### Summary

Commit dcee737 against base c4e2a41 (`git diff c4e2a41...dcee737 -- . ':!baton-runner'`), 9 files. Static review only; no tests were run.

Every issue 39 item is implemented. Each code item has a test that fails without it, except the hard-cap and base>0 branches of preflight's `left` arithmetic. The three owner rulings are reflected in code and docs without contradiction. Preflight's `left` matches chain_run's cap test for every case in brief item 3, as long as `JOB_MAX_CHILDREN` has no leading zero: soft paused-cap, hard cap with `5 5`, hard cap at `paused-cap`, and `JOB_MAX_CHILDREN=0`. Blast radius: no current scenario matches the new `child-count: ...; next child N` run.log line by accident. One scenario (test 50) would match it on a non-fresh job.

Two MEDIUM findings. First, a `JOB_MAX_CHILDREN` with a leading zero is now evaluated as octal in preflight's new arithmetic: `08`/`09` abort preflight with a bash error and no verdict line, and `010` shows the wrong number left. Second, P4R1-3 is only half addressed: a capped job still gets `preflight: ok`. The rest are LOW.

Verdict: APPROVE with notes. No CRITICAL or HIGH.

### Findings

#### CRITICAL

None.

#### HIGH

None.

#### MEDIUM

**M1. Preflight's new `left` arithmetic reads a leading-zero `JOB_MAX_CHILDREN` as octal: `08`/`09` crash preflight, `010` shows the wrong count**
- Location: `lib/preflight.sh:32` (`local left=$((MAXC - LAUNCHED + (CAP_SOFT ? b : 0)))`), with `lib/chain.sh:91` (`^[0-9]{1,9}$` still accepts leading zeros) and `lib/chain.sh:105,109` (`MAXC="$JOB_MAX_CHILDREN"` verbatim).
- Failure path: with `JOB_MAX_CHILDREN=08`, chain_nums passes and chain_cap sets `MAXC=08`. chain_run never puts MAXC in `$(( ))`: it compares with `[ ... -gt "$MAXC" ]` (`lib/chain.sh:194`), which reads `08` as decimal 8, so `run` works. Preflight's new line is `$((08 - ...))`, which errors with "08: value too great for base". Under `set -e`, preflight then exits 1 right after the `cap:` line. Nothing after it is printed: no timeout, account, usage, estimate, PRs or behind count, and no `preflight: ok` or `preflight: refused:` line. With `JOB_MAX_CHILDREN=010`, preflight prints `8 left under cap 010`, but run's `-gt 010` lets 10 children through.
- Evidence (bash one-liner): `MAXC=010 ... $((MAXC - 0 + 0))` gives `left=8`, while `[ 11 -gt "$MAXC" ]` is true only past 10. `set -e; MAXC=08; local left=$((MAXC-0))` prints `08: value too great for base (error token is "08")` and exits 1.
- Why nothing catches it: the work unit kept leading zeros on purpose ("leading zeros keep their old behaviour"). That held while MAXC was only ever compared with `test`. This diff adds the first arithmetic use of MAXC, so a preflight that worked before now breaks. `JOB_CAP_FACTOR=08` already broke chain_cap's `$((phases * 08))` before this change; that part is pre-existing.
- Fix: one of these two.
  - Make chain_nums reject leading zeros: `^(0|[1-9][0-9]{0,8})$`, the same shape chain_count already uses. This also closes the pre-existing `JOB_CAP_FACTOR=08` abort.
  - Use `$((10#$MAXC - LAUNCHED + ...))` in preflight.

  The first is the root-cause fix. Add `JOB_MAX_CHILDREN=08` to test 21's bad-number loop.

**M2. P4R1-3 is half addressed: a capped job still passes preflight (`preflight: ok`) and then exits at once**
- Location: `lib/preflight.sh:30-36`; `docs/spec.md` preflight row; decision "preflight shows `left` but does not refuse at the cap".
- Failure path: issue 39's P4R1-3 checkbox says "a garbled **or capped** job passes preflight and exits at once". The garbled case now refuses. Take a hard-cap job at `12 0` with the default cap 12. Preflight prints `0 left under cap 12` and then `preflight: ok`, exit 0. The follow-on `start` runs a unit that exits 4 before any child. The SKILL.md hand-over step 6 tells the operator to fix whatever a `preflight: refused` line names, so a `0 left` with `preflight: ok` goes through unnoticed.
- Evidence: test 60 pins this on purpose: `9 0` gives `0 left` and asserts `rc -eq 0` (`tests/60-preflight.sh:112-115`).
- Why it may still be fine: under the soft cap, `0 left` at `running` means the run pauses at once (exit 6), and the following `resume` gets a fresh allotment, so refusing there would be wrong. Under the hard cap, `0 left` always means exit 4 with no child, and the only way on is a larger `JOB_MAX_CHILDREN`.
- Fix (owner call): refuse when `CAP_SOFT` is empty and `left` is 0, e.g. `probs+=("hard child cap $MAXC reached (child-count); a larger JOB_MAX_CHILDREN goes on")`. Otherwise record in issue 39 that display-only is the accepted resolution of P4R1-3's "capped" half.

#### LOW

**L1. The hard-cap and base>0 branches of preflight's `left` are untested; p8's exit code is unchecked**
- Location: `tests/60-preflight.sh:112-125`, `lib/preflight.sh:31-32`.
- Failure path: every test 60 case is a soft-cap job with base 0. Two mutants survive:
  - `left=$((MAXC - LAUNCHED + b))`, which adds base under the hard cap too.
  - Dropping `[ -z "$CAP_SOFT" ] ||`, which gives a hard-cap `paused-cap` job a fresh allotment in preflight that run never gives.

  Neither is caught. These are exactly the cases brief item 3 names: hard cap with `5 5`, and hard cap at `paused-cap`. The p8 run (`tests/60-preflight.sh:118`) sets `rc` but never asserts it.
- Fix: add a hard-cap case. A job with no Phase plan row and `JOB_MAX_CHILDREN=6`, at `5 5`, should show `1 left under cap 6`. At `paused-cap` it should still show `1 left`. Also add `[ "$rc" -eq 0 ]` after p8.

**L2. The garbled-count refusal is written before the lock, so it can land in a live runner's run.log, and the lock error is never shown**
- Location: `lib/chain.sh:142` (before `chain_lock` at 151).
- Failure path: a unit's runner is live, and the owner hand-edits `child-count` into a bad shape, then runs `blast-off run <job>` by hand. The second runner never reaches `chain_lock`, so it does not print `runner N already drives ...`. Instead it appends `<ts> <job>/child-count holds '...'` to the live runner's run.log and exits 1. A reader of run.log sees a refusal in the middle of a running chain. The live runner then overwrites the bad file with its in-memory count at its next `chain_count_set` (`lib/chain.sh:204`), so the garble is fixed silently while the log says the job was refused. The spec's `run` row (`docs/spec.md:49`) says the lock comes first ("Before child 1 it takes the job's runner lock ..."), which no longer describes the order for this refusal. No other path is affected: a missing job dir dies in job_init, and LOG is always set by job_init before chain_run. Exit 1 with no `runner exit` line is correct, because the trap is not set yet.
- Fix: either move `chain_count || ...` after `chain_lock`, adding nothing to the EXIT trap (a refusal there exits 1 through chain_exit with a `runner exit 1 without a state` line, so `CHAIN_END=1` is needed first), or note the pre-lock ordering in the spec `run` row.

**L3. run.log shows the old `base` on a soft paused-cap resume; the moved base is never logged**
- Location: `lib/chain.sh:160` (`log "$COUNT_SAY"`), then `lib/chain.sh:171` (`BASE="$LAUNCHED"; chain_count_set`).
- Failure path: on a soft `paused-cap` re-run from `5 2`, run.log says `child-count: 5 launched, base 2; next child 6`. Then comes `status paused-cap -> running; the chain continues`. The base the run actually uses is 5, and that is never written to run.log. Anyone working out the remaining allotment from run.log gets MAXC-3 instead of MAXC. Preflight already shows the fresh allotment for the same state, so the two disagree.
- Fix: add the new base to the paused-cap log line, e.g. `status paused-cap -> running; base $BASE, a fresh allotment of $MAXC`.

**L4. Test 50 finds child 2's launch with an unanchored `grep -n 'child 2' | head -n 1`, which the new count line would match on a non-fresh job**
- Location: `tests/50-checkpoint-size.sh:37`.
- Failure path: `c2` is the first run.log line containing `child 2`. Today the job is fresh, so the count line reads `first child 1` and does not match. If this scenario ever starts from a count of `1 0` (`next child 2`), the count line comes first, before the size warning. `w -lt c2` would then fail, or pass vacuously in a variant. No other scenario greps run.log loosely for `child N`. All others use `child N launched`, `child [0-9]* launched`, anchored `^child N session=`, or full phrases. `lib/child.sh:123` uses an anchored `^child $1 session=` and is unaffected.
- Fix: `grep -n 'child 2 launched'`.

**L5. A FIFO (or a slow/blocking file) at `child-count` now hangs `status` and `preflight`**
- Location: `lib/chain.sh:123` (`cat "$f"`), now called from `lib/units.sh:74` and `lib/preflight.sh:30`.
- Failure path: `mkfifo <job>/child-count` makes `[ -e ]` true, and `cat` then blocks with no writer. `run` hung the same way before this diff. `status`, a read-only diagnostic, now hangs too, and so does `preflight`.
- Fix (optional): `[ -f "$f" ] || [ ! -e "$f" ] ...`, treating a non-regular file as garbled, or `timeout 5 cat`. A low-value hardening; this could be an accepted ceiling.

**L6. The whole garbled file's content now goes into run.log and the preflight `refused:` line**
- Location: `lib/chain.sh:125` (`holds '$c'`), and the new sinks at `lib/chain.sh:142` and `lib/preflight.sh:35`.
- Failure path: a multi-line or large `child-count`, such as a misdirected redirect, is copied whole into run.log as a multi-line entry and into preflight's single `preflight: refused: ...` line. Before this diff it went only to stderr.
- Fix (optional): quote at most the first line or the first 80 bytes, e.g. `${c:0:80}` with newlines flattened. receipt_refuse already flattens newlines (`lib/receipt.sh:11`).

**L7. The spec's test-21 row says "a `JOB_CAP_FACTOR` of 10", which reads as the value 10**
- Location: `docs/spec.md:229`: "a `JOB_MAX_CHILDREN` of 20 digits or a `JOB_CAP_FACTOR` of 10 (past 9 digits, P4R2-9)".
- Failure path: the test uses `JOB_CAP_FACTOR=1000000000`, which is 10 digits. The value 10 is valid. A reader, or a later doc check, takes the row literally.
- Fix: "a `JOB_CAP_FACTOR` of 10 digits".

**L8. The spec `run` row was not updated for the new behaviour**
- Location: `docs/spec.md:49` (`run` row).
- Failure path: the row lists what `run` does before child 1: the lock, the cap log, paused-cap to running, and the dirty check. It does not mention the new `child-count: ...` log line, or that a garbled count refuses before the lock (see L2). The JOB_MAX_CHILDREN paragraph has both, so the information exists, but in a different place.
- Fix: add "logs the count it starts from (`child-count: ...`); a garbled `child-count` exits 1 before the lock, its reason in run.log".

**L9. The SIGKILL test's comment says the re-run "clears what the dead runner left", but nothing asserts it**
- Location: `tests/10-chain-done.sh:156-166`.
- Failure path: after `kill -KILL`, the hang child, its HUP-ignoring grandchild, the tmux server `$TEST_ID-kill` and the child dir all outlive the runner. The re-run at cap 1 exits 4, and its `child_server` and EXIT trap should stop them. A regression there would leak a `sleep` process past the scenario, and no assert would notice. The SIGHUP case checks all of this (`gone_dirs`, `kill -0`, `tmux has-session`).
- Fix: capture `hung` and `gc` before the kill, as the hup case does. After `kill2`, assert `! kill -0` on both, `! tmux -L "$TEST_ID-kill" has-session`, and `gone_dirs kill`.

**L10. status's garbled-count branch is untested**
- Location: `lib/units.sh:74` (else branch); `tests/11-unit-smoke.sh:42` covers only the good line.
- Failure path: if the branch regressed to `chain_count; echo "$COUNT_SAY"`, status would print the fresh-job line for a garbled file. That is the exact P4R1-5 silent-fresh failure, now in status. Status could also exit non-zero, and nothing would catch either.
- Fix: one cheap check needing no unit. Write `x` into a job's `child-count`, then run `"$bo" status "$JOB"`. Expect exit 0 and `^child-count: .*holds 'x'`. This fits in test 10 or 60.

**L11. Test 60's header does not mention the new refusal or line**
- Location: `tests/60-preflight.sh:2-8`.
- Failure path: the header lists the refusal reasons as "the estimate over ... or a launch would refuse (CLAUDE_FLAGS empty)" and the lines as "cap, timeout, ...". It omits the `child-count` line and the garbled-count refusal. The spec row was updated; the header was not.
- Fix: add "child count (left under the cap), a garbled child-count refuses".

**L12. Preflight's `left` overstates for jobs whose next run launches nothing**
- Location: `lib/preflight.sh:32-33`; spec preflight row ("what the next run may launch").
- Failure path: for a `done` or `blocked` job, preflight prints for example `9 left under cap 9`, but run exits 0 or 3 before any child. A `paused-limit` job before its reset gets exit 8 with no child, and preflight prints the same. The spec says "may", so this is not wrong, only unqualified.
- Fix (optional): leave it, or say "(status <s>: none will launch)" for done, blocked and paused-limit.

**L13. A `child-count` that is a symlink to a real file is silently replaced by a regular file (pre-existing)**
- Location: `lib/chain.sh:131` (`mv -f child-count.tmp child-count`).
- Failure path: the docs now single out symlinks ("a dangling symlink is garbled"). A live symlink is read through, then the first launch renames a regular file over the link, and the link target stops being updated. This is pre-existing, and the work unit kept it on purpose ("read as before").
- Fix (optional): one line in the spec ("a symlink to a file is read, then replaced by a plain file at the next launch"), or treat any symlink as garbled.

**L14. The P4R1-2 reasoning applies to the other pre-lock refusals, which still go to stderr only (pre-existing)**
- Location: `lib/chain.sh:134-140` (CLAUDE_FLAGS, deps, brief, checkpoint, chain_nums via `die`).
- Failure path: `start` passes `JOB_*` through `--setenv`, and `unit_check` does not run chain_nums. So a 20-digit `JOB_MAX_CHILDREN` given to `start`, or a dependency missing from the unit's PATH, still kills the runner with the reason only in the journal. That is the same blind spot P4R1-2 fixed for the count. The two styles also differ on stderr: the count refusal is a timestamped line with no `blast-off:` prefix, while `die` prints `blast-off: ...`.
- Fix (optional, out of issue 39's scope): have `die` also append to `$LOG` when it is set and the job dir exists, or file a follow-up.

### Issue 39 checklist

| Item | Done? | Pinning test (file:line) | Notes |
|---|---|---|---|
| P4R2-1: base read back from the file | Yes | `tests/21-soft-cap.sh:47-52` | Mutant `BASE=0` on read: from `2 2` at cap 2 the first child would be 3 with 3-0>2, so exit 6 with no child 3. Killed. A mutant that also zeroes LAUNCHED launches child 1 and is killed too. |
| P4R2-2: cap-0 run masks a mutant that writes the file but not the in-memory BASE | Yes | `tests/21-soft-cap.sh:33` (re-seed `2 0`), checked by `:37-43` | The mutant (file written, in-memory BASE unmoved) reads 0 from `2 0`, so 3>2 gives exit 6 where the test wants 0. Killed. The cap-0 run (`:29-31`) still kills the opposite mutant (memory only, no file write). |
| P4R1-2: garbled refusal reaches run.log | Yes | `tests/10-chain-done.sh:107` (each garbled value), `:112` (dangling link) | Each case is a new job, so run.log holds only the refusal, and with the log removed the grep fails. Killed. Ordering caveat in L2; other pre-lock refusals in L14. |
| P4R1-3: preflight and status show child-count | Partly | preflight `tests/60-preflight.sh:57,115,119,123-125`; status `tests/11-unit-smoke.sh:42` | Garbled is refused in preflight. A capped job still gets `preflight: ok` (M2). The hard-cap `left` branch is untested (L1), and so is status's garbled branch (L10). Leading-zero cap crash in M1. |
| P4R1-4 / P4-22b: README exit-4 remedy can need a second start | Yes | docs only (`README.md:136`) | Correct. With a soft cap ≤ L the start pauses (exit 6), then `resume` sets BASE=L and continues. The status after exit 4 is `running` (or was `paused-cap`, then `running`), so `start` is allowed. |
| P4R1-5: missing or dangling file silently fresh; start count not logged | Yes | `tests/10-chain-done.sh:76` (fresh line), `:85` (re-run line), `:110-113` (dangling link) | Mutant without `[ -L ]`: the run launches a child and the `mv` replaces the link. Killed. Mutant dropping `log "$COUNT_SAY"`: killed. The logged base is stale on a soft paused-cap resume (L3). |
| P4R1-7: save-before-launch only tested on deaths that run the EXIT trap | Yes | `tests/10-chain-done.sh:158-166` (SIGKILL, `child-count` = `1 0` while child 1 runs) | Kills both "save after child_wait" and "save in the EXIT trap". A mutant that saves just after `child_launch` survives, but that window is negligible. Cleanup after the kill is not asserted (L9). |
| P4R2-9: chain_nums accepts any length | Yes | `tests/21-soft-cap.sh:86` (the bad loop adds the 20-digit cap and the 10-digit factor) | The old `^[0-9]+$` lets both through and a child runs. Killed. `{1,10}` lets `1000000000` through. Killed. Leading zeros remain (M1). |
| P4R2-10: `start_hang` has no `[ -n "$pid" ]` guard | Yes | `tests/11-unit-smoke.sh:63` | Test-only guard; no mutant applies. |
| Ruling P4-22a (soft fresh allotment via base, hard never resets) | Consistent | `tests/21-soft-cap.sh:29-43`, `tests/10-chain-done.sh:93-97,119-121` | Preflight's `left` follows it (soft paused-cap: b=L; hard: base ignored). |
| Ruling P4R2-4: docs say a paused-cap reads running at exit 4 | Yes | `tests/10-chain-done.sh:97` | Reworded: spec exit-4 status column, `lib/chain.sh:98-99` comment, `tests/21-soft-cap.sh:4-5` header, spec row 21. |
| Ruling P4R2-11: deleting child-count is the one reset, documented | Yes | indirect: `tests/11-unit-smoke.sh:59` (rm then fresh), `tests/10-chain-done.sh:76` | Reworded: `docs/spec.md:61`, README exit-4 row, `lib/chain.sh:116,193`, the refusal message ("delete it to count ... from 0 again"). |

Work-unit decisions:

| Decision | Assessment |
|---|---|
| chain_count returns 1 with COUNT_ERR instead of dying | Sound. All three callers handle it: chain_run with `\|\| { log; exit 1; }`, preflight and status with `if`. `set -e` does not trigger inside `if`/`\|\|`. The globals LAUNCHED, BASE, COUNT_SAY and COUNT_ERR are harmless in the status and preflight processes. The second `local b` in preflight re-declares the existing local loop variable `b` from `:9` in the same scope, after the loop has finished; no shadowing problem. |
| Missing file stays fresh | Sound and consistent with P4R2-11. It is now logged (`none, a fresh job`). |
| Dangling symlink is garbled | Sound. `[ -e ] \|\| [ -L ]` with `cat` failing gives `cannot read <f>: <cat error>`. A directory or an unreadable file is refused the same way (cat fails). A FIFO hangs (L5). A symlink to a real file is read through and later replaced (L13). |
| Preflight shows `left` but does not refuse at the cap | Arithmetic matches chain_run for every case in brief item 3. Not refusing at a hard-cap 0 leaves half of P4R1-3 open (M2). |
| Status shows no `left` | Sound: status runs in the caller's env, not the unit's. |
| chain_nums bounds digits only | It bounds overflow, but leading zeros now break preflight (M1). |
| `2 0` re-seed for P4R2-2 | Sound and minimal; kills the named mutant. |

Preflight vs chain_run cap test (brief item 3). Run launches `MAXC + (soft ? base_eff : 0) - L` children, where base_eff = L for a soft paused-cap and BASE otherwise. Preflight's formula is the same:

| Case | Run | Preflight | Match |
|---|---|---|---|
| Soft, `paused-cap`, `9 0`, cap 9 | BASE←9, launches 9 | b=9, 9 left | yes |
| Hard, `5 5`, cap 6 | base ignored, launches 1 | CAP_SOFT empty, 6-5 = 1 | yes (untested, L1) |
| Hard, `paused-cap`, `2 0`, cap 2 | flips to running, exit 4, 0 launched | b unused, 0 | yes |
| done / blocked / paused-limit before reset | exit 0 / 3 / 8, none launched | N left | display only (L12) |
| `JOB_MAX_CHILDREN=0`, soft or hard | exit 6 / 4 at once | 0 (clamped) | yes |
| `JOB_MAX_CHILDREN=010` or `08` | `-gt` reads it as decimal 10 / 8 | octal 8 / bash error | **no** (M1) |

### Open questions for the owner

1. M2: should preflight refuse a hard-cap job with 0 children left (exit 4 is certain), or is display-only the accepted close of P4R1-3's "capped" half?
2. M1: reject leading zeros in every `JOB_*` count (`^(0|[1-9][0-9]{0,8})$`), which changes accepted input, or keep them and force base 10 at each arithmetic use?
3. L2: should the garbled-count refusal move after the lock, so a live runner's run.log never gets a second runner's refusal?
