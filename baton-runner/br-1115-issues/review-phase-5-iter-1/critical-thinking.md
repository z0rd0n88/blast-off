### Summary

Reviewer: critical-thinking. Static review of dcee737 against c4e2a41 (lib/chain.sh, lib/preflight.sh, lib/units.sh, tests 10, 11, 21, 60, docs/spec.md, README.md). I read the work baton, phase-5/findings.md, issue 39, all of lib/chain.sh, lib/preflight.sh:1-80, lib/units.sh, bin/blast-off, and the changed regions of tests 10, 11, 21 and 60. I grepped every test and every lib file for run.log consumers that match `child N`, `launched`, `head -n 1`, `tail -n 1` and `grep -c`. I ran no tests, only three bash one-liners that print to stdout: the arithmetic of `(CAP_SOFT ? b : 0)` with CAP_SOFT empty and set, and the `{1,9}` regex at 9 and 10 digits.

Every item in issue 39 is done in code or docs, and the three rulings are worded as ordered. preflight's `N left under cap M` matches chain_run's cap test in every case the brief lists (worked through below). No run.log consumer is broken by the new `child-count: ...; next child N` line. The one positional grep that could catch it (test 50:37) only runs fresh jobs. No CRITICAL or HIGH.

The weak points are about what is pinned and what is still open. The question I keep asking is: why was preflight's `left` given a hard-cap branch that no test exercises? And why does P4R1-3 count as closed when a capped job still passes preflight and `start`? The same goes for P4R1-2: the run.log refusal was added for child-count only, while every other pre-lock refusal under `start` still reaches only the journal. P4R2-9 just made that set bigger.

Counts: CRITICAL 0, HIGH 0, MEDIUM 3, LOW 17.

preflight vs chain_run, worked out (left = launches before the cap stops the run; chain_run launches while `LAUNCHED+1 - (CAP_SOFT ? BASE : 0) <= MAXC`):
- Soft, status running, `L B`: run allows `MAXC - L + B`; preflight `MAXC - L + B`. Match.
- Soft, status paused-cap: run sets BASE=L (chain.sh:171), so it allows `MAXC`. preflight sets b=L and gets `MAXC`. Match. Pinned by 60:119.
- Hard, `5 5`, cap 12: run allows `12 - 5 = 7`. preflight: `(CAP_SOFT ? b : 0)` = 0 (one-liner: CAP_SOFT empty gives 7, CAP_SOFT=1 gives 12), so 7. Match, **but not pinned** (M1).
- Hard, status paused-cap: run does not move BASE (CAP_SOFT empty), it flips status to running and exits 4. preflight leaves b alone, and the ternary zeroes it anyway. Match, not pinned.
- done / blocked / paused-limit before its reset: run exits 0/3/9/10/8 before the cap test. preflight still prints `N left`. That is the cap allotment, not a forecast of launches. Not wrong, but not what "what the next run may launch" (spec:56) promises (L-item below).
- JOB_MAX_CHILDREN=0: soft gives MAXC 0, `left = B - L <= 0`, clamped to 0. The run gives `L+1-B > 0`, so exit 6 at once. Hard gives 0 left and exit 4. Match.

### Findings

#### CRITICAL

None.

#### HIGH

None.

#### MEDIUM

**M1. preflight's `left` is pinned only for the soft cap with base 0, so its base and hard-cap arithmetic can break unseen**
- Location: `lib/preflight.sh:31-33`; tests `tests/60-preflight.sh:57`, `:115`, `:119`.
- Failure path: the three preflight assertions all run under a soft cap (3 Phase plan rows) with `base` 0 or paused-cap. Two mutants survive. (a) `left=$((MAXC - LAUNCHED + b))`, dropping `CAP_SOFT ?`. A hard-cap job with child-count `5 5` at cap 12 would then print `12 left`, while `run` exits 4 after 7 children. With `5 5` at cap 5 it would print `5 left` while `run` exits 4 at once. (b) `left=$((MAXC - LAUNCHED))`, dropping base entirely. A soft running job at `4 2`, cap 2, would print `0 left`, while `run` launches 2. Either mutant gives back exactly what P4R1-3 complained about: a capped job looks fine in preflight and exits at once.
- Evidence: the one-liner shows the ternary is the only thing separating 7 from 12. No test writes a non-zero base for preflight, and none runs preflight on a hard-cap job (no Phase plan).
- Suggested fix: two more preflight cases in test 60. A job with no Phase plan and `5 5` must show `7 left under cap 12`, or under JOB_MAX_CHILDREN. A soft running job with `4 2` must show `left = MAXC - 2`.

**M2. P4R1-3 is half closed: a capped job still passes preflight and `start`, and `start` still accepts a garbled count**
- Location: `lib/preflight.sh:30-36` (no refusal at `0 left`); `lib/units.sh:28-32` (`unit_check` calls neither `chain_count` nor `chain_nums`); issue 39 P4R1-3 text: "a garbled or capped job passes preflight and exits at once".
- Failure path: a hard-cap job at `12 0`, default cap 12. `blast-off preflight` prints `...; 0 left under cap 12` and then `preflight: ok`, exit 0. `blast-off start` prints `systemd-run ...` and `status: blast-off status ...` (success). The unit exits 4 a moment later. With a garbled child-count, preflight now refuses, but `start` still succeeds and the unit dies with exit 1. The run.log line (P4R1-2) is now the only trace.
- Evidence: the work unit lists "preflight shows left but does not refuse at the cap" as a decision and an owner question. The issue's checkbox wording covers "capped", not only "garbled".
- Why it matters: does "display only, minimal" really close a finding whose stated harm is "passes preflight and exits at once"? `0 left` is easy to miss among about 15 preflight lines, and `preflight: ok` is the line people act on.
- Suggested fix: owner call (see Open questions). Either preflight refuses, or prints a warning line, at `0 left` when the status is not done or blocked. `unit_check` could also call `chain_count` so that `start` refuses a garbled file before systemd-run. If the owner keeps display only, mark P4R1-3 "partially closed" in the checklist rather than done.

**M3. P4R1-2 is fixed for child-count only: other refusals made before the lock still reach only the journal under start or the timer, and P4R2-9 adds to them**
- Location: `lib/chain.sh:134-140` (`die` for CLAUDE_FLAGS, a missing dependency, a missing brief or checkpoint, and `chain_nums`); `lib/chain.sh:37` (lock held); `lib/units.sh:28-32` (`unit_check` does not run `chain_nums`); README exit-1 row ("read the message or the last `run.log` line").
- Failure path: `JOB_MAX_CHILDREN=1234567890 blast-off start <job>` worked before this commit. It is now refused, but only inside the unit. `start` reports success, because `unit_check` does not validate the `JOB_*` counts. The runner dies in `chain_nums` with `die`, so stderr goes to the journal and nothing goes to run.log. The last run.log line is the previous run's, e.g. `soft cap 2 reached; status paused-cap; run again to continue`. Following the README, the owner reads that line and is misled. The resume timer path is the same: a `JOB_*` env passed through `--setenv` that is now out of range fails silently at the reset.
- Evidence: `chain_nums` (chain.sh:88-93) uses `die`, which goes only to stderr (bin/blast-off:48). P4R2-9 narrowed the accepted set, and test 21:86 checks only `bad.out` (stdout+stderr of a foreground run), never run.log or `start`.
- Why it matters: why log child-count's refusal to run.log, but not the refusal that this same phase made stricter?
- Suggested fix: call `chain_nums` in `unit_check` (start and resume then refuse before systemd-run), or send chain_run's pre-lock `die`s through the same `log ... >&2; exit 1` path. A test: `start` with a 10-digit `JOB_MAX_CHILDREN` exits 1 and starts no unit.

#### LOW

**L1. The stderr half of the run.log+stderr refusal is not pinned**
- Location: `lib/chain.sh:142`; `tests/10-chain-done.sh:104`, `:107`, `:112`.
- Failure path: a mutant `log "$COUNT_ERR"` (no `>&2`) prints the line on stdout. `badcount.out` captures `2>&1`, so 10:104 still finds the path, and 10:107 finds it in run.log. Spec:61 says "in `run.log` and on stderr".
- Suggested fix: capture stderr apart (`2> badcount.err`) for one case and grep that.

**L2. status's garbled-file branch is untested**
- Location: `lib/units.sh:74`; spec:51 ("or why the file is garbled").
- Failure path: a mutant that drops the `else` branch, or makes status exit non-zero on a garbled file (e.g. `chain_count; echo "$COUNT_SAY"` under set -e), passes every test. Test 11:42 covers only the good case.
- Suggested fix: one `status` call on a job whose child-count is `x`, asserting exit 0 and a `child-count: <f> holds 'x'` line.

**L3. chain_nums' 9-digit bound is pinned from above only**
- Location: `lib/chain.sh:91`; `tests/21-soft-cap.sh:86`.
- Failure path: no test passes any accepted `JOB_*` value of 5 or more digits (grep of tests/). So `^[0-9]{1,4}$` survives every test, and it would refuse e.g. `JOB_CHILD_TIMEOUT=86400` (a 1-day child) or `JOB_API_BACKOFF=36000`.
- Suggested fix: one run with a 9-digit value that is accepted (e.g. `JOB_CHILD_TIMEOUT=999999999` on a `done` job).

**L4. A FIFO or other special file at child-count now hangs `status` and `preflight` as well as `run`**
- Location: `lib/chain.sh:122-123`, newly reached from `lib/units.sh:74` and `lib/preflight.sh:30`.
- Failure path: `mkfifo <job>/child-count`. `[ -e ]` is true, `cat` blocks for a writer that never comes, and `blast-off status` hangs with no timeout. A symlink to `/dev/zero` reads without end into `$(...)`. `run` was already exposed. `status` is the read-only command an owner reaches for when something looks wrong.
- Suggested fix: `[ -f "$f" ] || [ ! -e "$f" ]`, or refuse a non-regular file as garbled (`[ -L ] || [ -e ]` then `[ -f ]`, else COUNT_ERR "not a regular file").

**L5. COUNT_ERR embeds the file's whole content, which can span many lines, in run.log and in preflight's one-line refusal**
- Location: `lib/chain.sh:125`; `lib/preflight.sh:35`, `:47`.
- Failure path: a child-count holding `1 0\n2 0` (two writers) or a pasted log gives a run.log entry over several lines, with no timestamp on the lines after the first. preflight's `preflight: refused: ...` line gets newlines inside it, which breaks the "one `name: value` line each" contract (spec:56) and any `^preflight: refused:` reader.
- Suggested fix: cut `c` to its first line and a bounded length in COUNT_ERR (e.g. `${c%%$'\n'*}` plus a length cap and `...`).

**L6. The logged starting count comes before the paused-cap branch moves BASE, so a soft resume's run.log shows the old base**
- Location: `lib/chain.sh:160` vs `:171`.
- Failure path: a soft job paused at `2 0`. The re-run logs `child-count: 2 launched, base 0; next child 3`, then `status paused-cap -> running`. The base it actually runs with (2) and the fresh allotment it got are never logged. Someone reconstructing from run.log works out `MAXC - 2` left instead of `MAXC`. P4R1-5's aim was "the count a run starts from is logged".
- Suggested fix: log the count after the status `case` too (or add `; base -> $BASE` to the paused-cap log line).

**L7. Test 50's positional `grep -n 'child 2' | head -n 1` would now match the count line on any job that is not fresh**
- Location: `tests/50-checkpoint-size.sh:37`.
- Failure path: if `grow` ever starts from a child-count of `1 0` (e.g. a future helper that reuses a job dir), the first `child 2` match becomes `child-count: 1 launched, base 0; next child 2`, logged before the size warning. `w < c2` then fails falsely. Safe today because `new_job` makes a fresh dir and the line reads `first child 1`. The work unit flagged this. I found no other loose `child N` match: every other test greps `child N launched`, `child N usage`, `child N timed out` or similar, and `grep -c 'child [0-9]* launched'` does not match `child-count: N launched` because of the `-`. lib/child.sh:123 is anchored `^child $1 session=`.
- Suggested fix: grep `'child 2 launched'` there.

**L8. The `[ -z "$CAP_SOFT" ] ||` guard in preflight is dead: the ternary zeroes b under the hard cap anyway**
- Location: `lib/preflight.sh:31-32`.
- Failure path: none at runtime. Removing the guard gives the same output in every case (an equivalent mutant), so a reader may think the guard carries the hard-cap rule when the ternary does. Two places now encode one rule.
- Suggested fix: keep one of them; the ternary mirrors chain.sh:194.

**L9. Spec test-21 row: "a `JOB_CAP_FACTOR` of 10 (past 9 digits" reads as the value 10**
- Location: `docs/spec.md:229`.
- Failure path: a reader takes `JOB_CAP_FACTOR=10` to be refused. The test uses `1000000000` (10 digits).
- Suggested fix: "a `JOB_CAP_FACTOR` of 10 digits".

**L10. Spec status row: "no children left, since the cap is set by the unit's environment" reads as "the job has no children left"**
- Location: `docs/spec.md:51`.
- Failure path: the intended meaning is "no `left under cap` figure". As written it says the opposite of what an owner wants to learn.
- Suggested fix: "no `left under cap` count, since ...".

**L11. "deleting `child-count` is the one reset of the count" (README) is not true: editing it to a smaller valid pair resets it too**
- Location: `README.md:136`; `docs/spec.md:61` ("the one deliberate reset"); `lib/chain.sh:125` (the error tells the owner to "fix it").
- Failure path: `echo '0 0' > child-count` passes validation and resets both caps. The ruling P4R2-11 says "deliberate". The README drops that word, so it claims the file cannot be reset any other way.
- Suggested fix: README: "deleting (or rewriting) `child-count` resets the count; nothing else does".

**L12. The exit-4 message and the README remedy disagree on the way out**
- Location: `lib/chain.sh:195` ("a larger JOB_MAX_CHILDREN goes on"); `README.md:136` (add a Phase plan, start, maybe resume; "raising JOB_MAX_CHILDREN alone gives more children, not a way to done"); `docs/spec.md:91`.
- Failure path: the owner under `start` reads the run.log line, raises the cap, and spends more children on a job that can never end `done` (exit 10). Pre-existing, but P4-22b reworked the remedy and left the message as it was.
- Suggested fix: append "; a Phase plan table in checkpoint.md is the way to done (README exit 4)".

**L13. The README exit-4 remedy does not warn that Phase plan rows added for phases already finished need receipts and PR cells**
- Location: `README.md:136`.
- Failure path: the owner adds a Phase plan with the phases the hard-capped children already did marked `done`. `receipt_check` exits 9 (no `gate-logs/phase-<row>.json` PASS) and the CI check exits 10 (no PR / `no PR`) before any child. So there is a third start the remedy does not predict. Pre-existing.
- Suggested fix: say a row marked done needs its commit, PASS receipt and `PR #N`/`no PR` (or point at templates/checkpoint.md).

**L14. The count is read before the lock (pre-existing), so a runner that wins a just-released lock can start from a stale count**
- Location: `lib/chain.sh:142` vs `:151`.
- Failure path: runner A is live. Runner B reads `3 0`, then A saves `4 0` and exits, then B takes the now-stale lock and launches "child 4" again with a cap one short. The window is tiny, and `unit_resume` waits for the old unit. It is worth naming now that the refusal deliberately sits before the lock: why must the read also sit there?
- Suggested fix: re-read after `chain_lock` (the refusal can stay before it), or note it as a `ponytail:` ceiling.

**L15. The refusal on stderr has no `blast-off:` prefix, unlike every other exit-1 message**
- Location: `lib/chain.sh:142` (`log` prints `<ts> <msg>`), vs `die` (bin/blast-off:48).
- Failure path: journal readers or scripts that look for `blast-off:` miss this one refusal. Cosmetic, and acknowledged in the baton.
- Suggested fix: none needed if accepted; else `log ...; echo "blast-off: $COUNT_ERR" >&2`.

**L16. Test 60's paused-cap case does not assert its exit code**
- Location: `tests/60-preflight.sh:118-119` (`rc` set, never checked).
- Failure path: a mutant that makes preflight refuse a paused-cap job (exit 1) but still print the line passes.
- Suggested fix: `[ "$rc" -eq 0 ] || fail ...` as at :114.

**L17. Carried over, still open: P4R2-3 (test 21's resume-log grep is also satisfied by the cap-0 run's line), and chain_nums still accepts leading zeros (`JOB_CAP_FACTOR=08` breaks the arithmetic as octal), while child-count refuses `08 0`**
- Location: `tests/21-soft-cap.sh:39`; `lib/chain.sh:91` vs `:124`.
- Failure path: as named in the work baton. Both are pre-existing and out of this issue's scope. They are listed so the triage sees them.
- Suggested fix: separate issue.

### Issue 39 checklist

| Item | Done? | Pinning test (file:line) | Notes |
|---|---|---|---|
| P4R2-1 base read back | Yes | tests/21-soft-cap.sh:49-52 (`base` job, `2 2` at cap 2: children 3 and 4, then `4 2`) | Kills `BASE=0` on read (exit 6 with no child). Also kills a save that drops base (`4 0` != `4 2`). |
| P4R2-2 in-memory BASE on paused-cap | Yes | tests/21-soft-cap.sh:33 (re-seed `2 0`) + :38 (rc 0) | Kills "file only" (MB: BASE stays 0, exit 6). The cap-0 run at :30 kills "memory only, no save". |
| P4R1-2 refusal in run.log | Yes for child-count | tests/10-chain-done.sh:107, :112 | The stderr half is not pinned (L1). Other pre-lock refusals are still journal-only (M3). |
| P4R1-3 preflight/status show child-count | Partly | tests/60-preflight.sh:57, :115, :119, :122-125; tests/11-unit-smoke.sh:42 | A garbled file refuses in preflight. A capped job still passes preflight and `start` (M2). Hard-cap and base>0 `left` not pinned (M1). status garbled branch not pinned (L2). |
| P4R1-4 / P4-22b README exit-4 remedy | Yes (doc) | none (70-docs checks rows exist, not wording) | The wording is accurate: a start from `running` with L >= the soft cap pauses at once, then resume moves base. Message mismatch (L12); done rows need receipts (L13). |
| P4R1-5 missing/dangling file; starting count logged | Yes | tests/10-chain-done.sh:76, :85 (count lines); :110-113 (dangling link exit 1, link kept) | Kills a dropped `log "$COUNT_SAY"` and a dropped `[ -L ]`. The logged base predates the paused-cap move (L6). |
| P4R1-7 save before launch without EXIT trap | Yes | tests/10-chain-done.sh:158-166 (`1 0` while child 1 runs; SIGKILL; re-run at cap 1 exits 4 with one launch) | Kills MT (save in chain_exit) and MT2. A save between child_launch and child_wait is near-equivalent (baton). |
| P4R2-9 chain_nums digits | Yes | tests/21-soft-cap.sh:86 (20-digit cap, 10-digit factor) | The upper bound is pinned; the lower is not (`{1,4}` survives, L3). Leading zeros still pass (L17). |
| P4R2-10 start_hang pid guard | Yes | tests/11-unit-smoke.sh:63 | Kills MG (pid empty). |
| Ruling P4-22a | Kept | tests/21-soft-cap.sh:30, :38; tests/10-chain-done.sh:96 | Soft fresh allotment via base; hard never resets. |
| Ruling P4R2-4 wording | Yes | tests/10-chain-done.sh:97 (`status: running` after exit 4 from paused-cap) | spec:91 status column, chain.sh:98-99 comment, test 21 header :4-5 all reworded. The assertion documents existing behaviour and would kill a mutant that keeps paused-cap. |
| Ruling P4R2-11 wording | Yes | none (doc) | spec:61 "never resets unless you delete `child-count` (the one deliberate reset...)"; README:136 says so. README drops "deliberate", so its claim is too strong (L11). chain.sh:192-193 comment too. |

### Open questions for the owner

1. P4R1-3 says a capped job "passes preflight and exits at once". Now preflight prints `0 left` and still says `preflight: ok`. Is a display line enough, or should preflight refuse or warn when nothing is left and the status is not done or blocked?
2. Should `start` (and `resume`) refuse a garbled child-count and out-of-range `JOB_*` counts before systemd-run, the way they already refuse an empty CLAUDE_FLAGS or GH_TOKEN, rather than start a unit that dies at once?
3. status shows no `left` because the unit's env may differ from the caller's. preflight has the same caveat and shows it anyway. Is the asymmetry deliberate? Would `left (under this shell's env)` on status be more useful than nothing?
4. Is rewriting child-count by hand (e.g. `0 0`) an allowed reset, or only deleting it? The error message invites "fix it", and the README now says deleting is "the one reset".
