---
source: runner
scope: br-1115-issues
parent_session: ""
---
# Pass-Baton: phase 4 work unit, issue 22 (child count persisted per job) implemented

**Date:** 2026-11-17
**Scope:** br-1115-issues
**Branch:** feat/br-1115-issues/phase-4
**Worktree:** /home/alex/blast-off/.claude/worktrees/pending-items-53932d
**HEAD:** 7867255 Merge pull request #37 (changes uncommitted; the manager owns git)

## Where things stand

All three acceptance criteria of issue 22 are implemented and tested. The child count now lives in the job dir's `child-count` file. The cap counts the job's children across runs, and run.log numbering continues after a relaunch. A fresh job (no file) starts at child 1. Every scenario I touched passes when run alone, one at a time: 10, 11, 21, 23, 40 and 70-docs. `shellcheck -S warning` is clean on the 5 changed scripts. I did not run the full gate, as the brief requires. No new dependency, and nothing committed.

Files changed (tracked, 7):
- `lib/chain.sh`:
  - New `chain_count` reads `$JOB/child-count` (`<launched> <base>`) into LAUNCHED and BASE. It is called right after `chain_nums`, before the lock and the EXIT trap. A missing file means `0 0`.
  - Anything other than two whole numbers with no leading zero and base <= launched is a `die` (exit 1) that names the file and its content.
  - New `chain_count_set` writes `child-count.tmp` and then `mv`s it over `child-count`.
  - The loop's `n=$((n+1))` became `n=$((LAUNCHED+1))`. The cap test is `n - BASE > MAXC`.
  - `LAUNCHED=$n; chain_count_set` runs just before `child_launch`.
  - The `paused-cap -> running` branch sets `BASE=$LAUNCHED` and saves it before it sets the status.
  - The exit-4 message now reads `child cap N reached (L children launched for this job, <job>/child-count); a larger JOB_MAX_CHILDREN goes on`.
  - `local n=0` became `local n`.
- `tests/10-chain-done.sh`:
  - After the hard-cap block: a re-run at cap 1 exits 4 with no new launch. A re-run at cap 2 launches `child 2`, has exactly one `child 1 launched`, has no child 3, and exits 4 with `child cap 2 reached`.
  - Six garbled `child-count` values (`''`, `x`, `1`, `08 0`, `1 2`, `-1 0`) each exit 1 before any child, with the file path in the output and the file left unchanged.
  - After the SIGHUP block: the hup job (runner killed during child 1) re-run at cap 1 exits 4 with no new launch. This proves the count is saved before the launch, which is the reboot case.
- `tests/21-soft-cap.sh`:
  - The paused-cap re-run's child is `child 3`, with exactly one `child 1 launched`.
  - New `relaunch` job (plan 2, factor 1, `noop`): the first run ends on two stalls (exit 5), and the re-run pauses before any child (exit 6, still 2 launches). So the soft cap also survives a relaunch that is not a paused-cap resume, which is the issue's 27->30 case.
- `tests/11-unit-smoke.sh`: `start_hang` also runs `rm -f "$JOB/child-count"`. Its `child=1 pid=` sed and its `$TEST_ID-job-child-1.scope` name assume each restart's child is child 1. Without this, numbering would continue to 2, 3 and 4. It is the same kind of fixture reset as the status, fake-mode and fake-marker resets beside it.
- `tests/40-receipt-required.sh`: two comments only (lines 85 and 104) that said "child 1 of the re-run".
- `docs/spec.md`:
  - The `JOB_MAX_CHILDREN` env text describes `child-count`, when it is written, how the cap reads it, and the missing and garbled cases.
  - Exit 1 lists a bad `child-count`.
  - Exit 4 says the cap counts every child across runs and names the way on.
  - Exit 6: "fresh child count" became a fresh allotment, with `base` moving to `launched` and numbering going on.
  - Test rows `10-chain-done` and `21-soft-cap` name the new cases.
- `README.md`: the exit 4 row says the cap is counted over every run in `child-count`. The exit 6 row says "a fresh allotment of the cap; child numbers go on" in place of "fresh child count".

Untracked, planning only: `baton-runner/br-1115-issues/phase-4/{task_plan,findings,progress}.md` and this file. I did not touch `STATE.md` or `log.md`.

## Decisions (counter file), also in `phase-4/findings.md`

- **Where:** `$JOB/child-count`, one line `<launched> <base>`. `launched` is every child this job has launched, so it is also the last child's number. `base` is `launched` at the last `paused-cap -> running`. The dirty-tree check already skips job dir files by prefix.
- **Why two numbers:** spec row 6 and test 21 promise that a paused-cap re-run continues with a fresh allotment. A single persisted count would pause that job again at once, forever. With `base`, the soft cap resets only on the deliberate paused-cap resume. A crash or reboot relaunch of a `running` job does not reset it, and numbering always continues. The hard cap has no reset path.
- **When it increments:** after the cap check passes and just before `child_launch` (after the backoff sleep, size warning and `jev_pick`). It is written by temp file and rename. A child cut off by a reboot is counted, and a cap exit writes nothing. The cap check and the run.log number use the same `n`, so `child n launched` is always `launched`.
- **Missing file:** a fresh job, `0 0`, first child 1.
- **Garbled file** (empty, unreadable, not two numbers, a leading zero, negative, or base > launched): exit 1 before any child, and the message names the file and what it holds. The file is never read as 0 and never rewritten. The way on is to fix the numbers by hand, or delete the file to restart the count, which is a deliberate owner act.
- **Read point:** before the lock and the trap, so a bad file is a clean `die` and is not logged as a runner abort. A second runner beside a live one only reads, and the rename means it never sees a half-written file. Test 23 passes.

## Evidence

RED, the tracer (`BLAST_OFF_TEST_ONLY=10-chain-done tests/run`, new assertions with the old `lib/chain.sh`):

```
FAIL 10-chain-done
  | FAIL: re-run at a reached cap launched a child: 2026-11-17T17:30:07Z child cap 1 (hard: no Phase plan row the runner reads in checkpoint.md; done is refused (exit 10) until it has one)
PASS shellcheck (33 files)
GATE-ONLY: FAIL passed=0 failed=1 shellcheck=ok only=10-chain-done
```

GREEN (same command, after the change):

```
PASS 10-chain-done
PASS shellcheck (33 files)
GATE-ONLY: PASS passed=1 failed=0 shellcheck=ok only=10-chain-done
```

The RED run stopped at the first new assertion, so I checked the two later new blocks by mutation. Each mutation was a temporary edit of `lib/chain.sh`, restored afterwards and confirmed with `cmp`:
- Count saved after `child_wait` instead of before `child_launch`:
  `| FAIL: a child launched past cap 1 after a relaunch: 2026-11-17T17:32:05Z child cap 12 (hard: ...`
- Garbled file read as `0 0`:
  `| FAIL: child-count '': exit 4, want 1 before any child: 2026-11-17T17:33:00Z child cap 1 (hard: ...`

21-soft-cap RED (new assertions, old `lib/chain.sh`):

```
FAIL 21-soft-cap
  | FAIL: child numbering did not go on after paused-cap: 2026-11-17T17:33:40Z child cap 2 (soft: 2 Phase plan rows x JOB_CAP_FACTOR 1)
GATE-ONLY: FAIL passed=0 failed=1 shellcheck=ok only=21-soft-cap
```

21-soft-cap with the paused-cap `BASE` reset removed (a mutation), which shows why there are two numbers:

```
FAIL 21-soft-cap
  | FAIL: re-run after paused-cap exit 6: 2026-11-17T17:33:49Z child cap 2 (soft: 2 Phase plan rows x JOB_CAP_FACTOR 1)
```

21-soft-cap GREEN: `GATE-ONLY: PASS passed=1 failed=0 shellcheck=ok only=21-soft-cap`

Other scenarios, each run alone in this order after the change:
- `11-unit-smoke`: `GATE-ONLY: PASS passed=1 failed=0 shellcheck=ok only=11-unit-smoke`
- `23-runner-lock`: `GATE-ONLY: PASS passed=1 failed=0 shellcheck=ok only=23-runner-lock`
- `40-receipt-required`: `GATE-ONLY: PASS passed=1 failed=0 shellcheck=ok only=40-receipt-required`
- `70-docs`: `GATE-ONLY: PASS passed=1 failed=0 shellcheck=ok only=70-docs`

`shellcheck -S warning lib/chain.sh tests/10-chain-done.sh tests/21-soft-cap.sh tests/11-unit-smoke.sh tests/40-receipt-required.sh` printed nothing, then `SHELLCHECK-CLEAN`.

`~/.config/systemd/user/blast-off@.service` was checked before the first run and after the 10, 11 and 23/40 runs. Every time it read `ExecStart=/home/alex/blast-off/.worktrees/blast-off-build/bin/blast-off run %f`, unchanged.

Also run alone: `41-ci-wait`: `GATE-ONLY: PASS passed=1 failed=0 shellcheck=ok only=41-ci-wait`. ExecStart was unchanged afterwards.

Blast radius: I read every scenario that re-runs one job dir (11, 12, 22, 23, 30, 31, 40, 41) for hard-coded child numbers, multi-line fake-mode, `fake-usage-N` and small caps after a re-run.
- 12, 22 and 30: the re-runs launch no child, or refuse before child 1.
- 23's `stale` job, 31's `fire` job and 40's `chain` job do launch a later-numbered child on re-run (child 2 or later). This is harmless: their fake-mode is a single line, or it is rewritten to one before the re-run, they assert no child number, and their cap (12, or rows x 3) is far off. 23, 40 and 41 were run and pass. 31 was read only, because it uses `resume`/`start`.
- 41: the `fin` and `wf` jobs are `status: done` after their first child, so every re-run takes the done branch with no launch.
- 20, 32, 50 and 61: one run per job.
- Only 11 needed a change.

Criterion 3 ("a fresh job starts at 1") rests on the existing assertions `child 1 launched` (test 10 line 16) and `^child=1 ` (test 10 hard-cap block), which pass with no `child-count` file. I added no new assertion for it.

Files outside the brief's named set (the brief named `lib/chain.sh`, the chain test under tests/ and `docs/spec.md`), each kept for a reason. The manager may accept or revert each:
- `tests/21-soft-cap.sh`: the soft cap is the issue's real 27->30 case, and the paused-cap `base` decision needs its guard.
- `tests/11-unit-smoke.sh`: it would break without the reset (it assumes child 1 on every restart).
- `tests/40-receipt-required.sh`: two comments my change made false. No behaviour change.
- `README.md`: the exit 6 row said "fresh child count", which my change makes half-true, and the exit 4 row now says the cap spans runs.

## Next steps

1. Review unit: `git diff` in the worktree (7 tracked files above), against issue 22 (`gh issue view 22`). Then the full gate, alone.
2. Manager: commit the 7 tracked files, plus the planning files and this note per the run's convention.

## Open questions / risks

- **Owner question P4-22a, soft cap semantics:** I kept spec row 6's fresh allotment on a paused-cap re-run (through `base`). The issue's text ("JOB_MAX_CHILDREN is a per-run limit, not a per-job one") could also be read as wanting the soft cap never to reset. That would make paused-cap a dead end and break test 21's re-run. If the owner wants a lifetime cap, the change is to drop `base`.
- **Owner question P4-22b, the exit-4 remedy now takes two starts.** README row 4 says "add a Phase plan table with a row per phase and start again". With the count kept, the cap turns soft (rows x factor, `base` 0). If the children already launched reach that cap, the next start pauses at once: `paused-cap`, exit 6, no child (from the code: `n - BASE > MAXC` with `CAP_SOFT` set). A second `run` or `resume` then moves `base` and goes on. I did not reword the README row; the owner can say whether it should mention the second start.
- **The hard cap is now final for a job.** Exit 4 on a re-run at the same cap is immediate. The way on is a larger `JOB_MAX_CHILDREN`, adding a Phase plan table (the cap turns soft), or deleting `child-count`, which also resets numbering. The exit-4 message names the first; the spec and README rows name the first two.
- The log label `chain_dirty "before child 1"` (`lib/chain.sh`, before the loop) still says "child 1" on a re-run whose next child is, say, child 4. Tests 22 and 40 and spec rows 7 and 9 use that literal. I left it because it means "before this run's first child". The reviewer can decide whether it should name `$((LAUNCHED+1))`.
- `preflight` and `status` do not show the count (`chain_cap` is unchanged, so preflight's `cap:` line is still the cap, not what remains). This is outside the criteria.
- `[ -e "$f" ]`: a dangling symlink named `child-count` reads as a fresh job. A leftover `child-count.tmp` after a crash between write and rename is harmless: it is overwritten next time, and the dirty check skips job dir files.
- I did not prove test 11's `start_hang` fix RED, to avoid a second systemd-touching run. The argument is static: its `child=1 pid=` sed would return empty on the second start.

## References

- Issues: z0rd0n88/blast-off issue 22 (blocks 17 and 20)
- Docs: `baton-runner/br-1115-issues/phase-4/{task_plan,findings,progress}.md`, `docs/spec.md` §2 env, §3 rows 1/4/6, §6 rows 10/21
- Code: `lib/chain.sh` `chain_count`, `chain_count_set`, `chain_run` (paused-cap branch, cap check, save before `child_launch`)
