---
source: runner
scope: br-1115-issues
parent_session: ""
---
# Pass-Baton: phase 4 fix round 1 (issue 22): P4R1-1, -6, -8, -9, -10, -11 fixed

**Date:** 2026-11-17
**Scope:** br-1115-issues
**Branch:** feat/br-1115-issues/phase-4
**Worktree:** /home/alex/blast-off/.claude/worktrees/pending-items-53932d
**HEAD:** e766e00 chore(phase-4): review round 1 CLEAN; owner ruling P4-22a; fix round started (changes uncommitted; the manager owns git)

## Where things stand

The six findings the manager named are fixed, test-first, under owner ruling P4-22a: a paused-cap resume gives the soft cap a fresh allotment (`base`), and the hard cap (no Phase plan rows) never resets for a job. P4R1-1 and P4R1-6 changed `lib/chain.sh` and went RED before the fix, then GREEN. P4R1-8, -9 and -11 are test-only. By reading, the code at HEAD already behaves as those tests ask. I did not run them at HEAD. Their evidence is a mutant they kill, not a staged RED. Each mutant was a temporary edit of `lib/chain.sh`, one scenario alone, restored from a saved copy and confirmed with `cmp`. P4R1-10 is a deleted duplicate line. No other finding was touched.

Scenarios run, each alone, one at a time (never the full gate): 10-chain-done, 21-soft-cap, 11-unit-smoke, 70-docs, plus the mutant runs of 10 and 21 below. Last results: 10 `GATE-ONLY: PASS passed=1 failed=0 shellcheck=ok only=10-chain-done`, 21 `GATE-ONLY: PASS passed=1 failed=0 shellcheck=ok only=21-soft-cap`, 11 `GATE-ONLY: PASS passed=1 failed=0 shellcheck=ok only=11-unit-smoke`, 70 `GATE-ONLY: PASS passed=1 failed=0 shellcheck=ok only=70-docs`. `shellcheck -S warning lib/chain.sh tests/10-chain-done.sh tests/21-soft-cap.sh tests/11-unit-smoke.sh` printed nothing, then `SHELLCHECK-CLEAN`.

`~/.config/systemd/user/blast-off@.service` read `ExecStart=/home/alex/blast-off/.worktrees/blast-off-build/bin/blast-off run %f` before the first run and after every run (14 runs: three RED and one GREEN of 10, one GREEN of 21, seven mutants, 11, 70-docs), unchanged.

Blast radius: I grepped `tests/`, `lib/` and `bin/` for `paused-cap`, `child-count`, `BASE` and the old die text (`whole numbers, base <= launched`). Nothing quotes the old text. `lib/units.sh:56` (`unit_resume`) only checks the status and then starts the unit, so the change is in `chain_run` alone. The `cap` job in `tests/31-resume-after-reset.sh:58-61` is a fresh job (no `child-count`, `base` 0) under the hard cap of 12. Its outcome is the same before and after this fix: status goes to `running` and child 1 launches. I read 31 and did not run it, to keep systemd untouched. `tests/51-templates.sh` quotes only the brief's status wording.

Files changed (tracked, 5):
- `lib/chain.sh`:
  - The paused-cap branch moves `base` (and saves it) only when the soft cap applies: `[ -z "$CAP_SOFT" ] || { BASE="$LAUNCHED"; chain_count_set; }`. `cp_set_status running` and the log line are unchanged.
  - The cap test is `$((n - (CAP_SOFT ? BASE : 0))) -gt "$MAXC"`: the soft cap subtracts `base`, the hard cap compares the total. `BASE` is not zeroed under the hard cap, so the save before launch keeps the soft allotment if the Phase plan comes back.
  - `chain_count`'s regex bounds each number to at most 9 digits (`[1-9][0-9]{0,8}`). The die message says "whole numbers of at most 9 digits", and the `chain_count` comment is updated.
- `tests/10-chain-done.sh`:
  - After the cap-2 re-run, `status: paused-cap` is written into the hard-capped job and it is re-run at cap 2. It must exit 4 with no child 3, and `child-count` must still read `2 0`.
  - The garbled loop gains `9223372036854775807 0`, and its children are `noop` (was `step`), so a wrapped count ends on two stalls (exit 5) and not on the harness timeout. No other value in the loop launches a child, so the change of mode does not weaken them.
  - New zero-byte `child-count` case (`: >`): exit 1 before any child, and the file stays empty.
  - New `basehard` job: `child-count` `5 5`, no Phase plan, cap 1. It must exit 4 with no child, and the file must stay `5 5`.
- `tests/21-soft-cap.sh`: between the soft run and the re-run, a `JOB_MAX_CHILDREN=0` run of the paused-cap job. It must exit 6 with `child-count` `2 2` and still 2 launches. The existing re-run then starts from `2 2` (base == launched) and must reach `done` as before.
- `tests/11-unit-smoke.sh`: the second, duplicate `rm -f "$JOB/child-count"` line in `start_hang` is deleted. The first line and its comment stay.
- `docs/spec.md`:
  - The `JOB_MAX_CHILDREN` env text was wrong for the hard cap. It now says the hard cap is reached when the next child would pass it (it never resets for a job), and the soft cap when the next child less `base` would. It says `base` is the soft cap's alone and moves only on a paused-cap resume under the soft cap (P4-22a), and that each number has at most 9 digits.
  - The `10-chain-done` test row names the paused-cap and `5 5` hard-cap cases, the zero-byte file and the overflow value.
  - The `21-soft-cap` test row names the cap-0 paused-cap run and its `2 2`.
  - README is unchanged. Its exit 4 row ("counted over every run of the job in its `child-count`") was false before this fix and is true after it. Its exit 6 row is about the soft cap only.

Untracked: this file. Scratch: `/tmp/claude-1000/-home-alex-blast-off--claude-worktrees-pending-items-53932d/60b15296-819e-491a-8ffe-34b3bd988f86/scratchpad/p4fix1` holds `t.sh` (one scenario plus the ExecStart check), `mut.sh` (one mutant: edit, `cmp` differs, run, restore, `cmp` equal), `chain.sh.head`, `chain.sh.fix1-nobound`, `chain.sh.fixed`, and every run's log. I did not touch `STATE.md` or `log.md`.

## Correction to the work baton

`baton-phase-4-work.md` line 35 (and line 121, "it would break without the reset") gave the wrong reason for test 11's `rm -f "$JOB/child-count"`. Without it the test does not go red. Its `child=1 pid=` sed returns an empty `pid`, `gone ""` is true, and the `child-1` scope never exists, so the test passes vacuously (tdd-guide, P4R1-10). The reset is still needed, for that reason. I fixed only the duplicate line, as asked. I did not add the `[ -n "$pid" ]` guard that would make that failure red (see Notes).

## Evidence, per finding

### P4R1-1: the hard cap could be reset through `base`

RED 1 (`5 5` case only, `lib/chain.sh` at HEAD; `BLAST_OFF_TEST_ONLY=10-chain-done tests/run`):

```
FAIL 10-chain-done
  | FAIL: hard cap 1 with child-count '5 5': exit 4, want 4 and no child: 2026-11-17T18:29:47Z child cap 1 (hard: no Phase plan row the runner reads in checkpoint.md; done is refused (exit 10) until it has one)
PASS shellcheck (33 files)
GATE-ONLY: FAIL passed=0 failed=1 shellcheck=ok only=10-chain-done
```
from the same log: `child 6 launched` and then `child cap 1 reached (6 children launched for this job, .../test-96103-basehard/job/child-count)`.

RED 2 (paused-cap variant added, HEAD code):

```
FAIL 10-chain-done
  | FAIL: hard cap reset by paused-cap: exit 4, child-count '4 2': 2026-11-17T18:30:16Z child cap 2 (hard: no Phase plan row the runner reads in checkpoint.md; done is refused (exit 10) until it has one)
PASS shellcheck (33 files)
GATE-ONLY: FAIL passed=0 failed=1 shellcheck=ok only=10-chain-done
```
from the same log: `child 3 launched` and `child 4 launched`, then `child cap 2 reached (4 children launched for this job, ...)`.

GREEN: after the fix, the next run (RED 3 below) passed both P4R1-1 cases and failed only at the later overflow case. The final run passed: `GATE-ONLY: PASS passed=1 failed=0 shellcheck=ok only=10-chain-done`.

Mutant kills. Each half of the fix was reverted on its own. The mutant blocks below are excerpts from `mut.sh`. Every one of them also printed `rc=1`, then `PASS shellcheck (33 files)`, then `15:ExecStart=/home/alex/blast-off/.worktrees/blast-off-build/bin/blast-off run %f`:
- M1a (guard removed: `base` moves in any cap mode, the hard cap still compares `n`):
  ```
  M1a-guard-removed mutant: <     paused-cap) [ -z "$CAP_SOFT" ] || { BASE="$LAUNCHED"; chain_count_set; }  # the soft cap's fresh allotment (P4-22a); numbering goes on >     paused-cap) { BASE="$LAUNCHED"; chain_count_set; }  # the soft cap's fresh allotment (P4-22a); numbering goes on
  FAIL 10-chain-done
    | FAIL: hard cap reset by paused-cap: exit 4, child-count '2 2': 2026-11-17T18:32:46Z child cap 2 (hard: no Phase plan row the runner reads in checkpoint.md; done is refused (exit 10) until it has one)
  GATE-ONLY: FAIL passed=0 failed=1 shellcheck=ok only=10-chain-done
  M1a-guard-removed: restored, cmp equal
  ```
- M1b (the hard cap subtracts `base` again, guard kept):
  ```
  M1b-hard-subtracts-base mutant: <     if [ $((n - (CAP_SOFT ? BASE : 0))) -gt "$MAXC" ]; then >     if [ $((n - BASE)) -gt "$MAXC" ]; then
  FAIL 10-chain-done
    | FAIL: hard cap 1 with child-count '5 5': exit 4, want 4 and no child: 2026-11-17T18:33:07Z child cap 1 (hard: no Phase plan row the runner reads in checkpoint.md; done is refused (exit 10) until it has one)
  GATE-ONLY: FAIL passed=0 failed=1 shellcheck=ok only=10-chain-done
  M1b-hard-subtracts-base: restored, cmp equal
  ```

### P4R1-6: a huge count wrapped the counter negative

RED (P4R1-1 fixed, no digit bound yet):

```
FAIL 10-chain-done
  | FAIL: child-count '9223372036854775807 0': exit 5, want 1 before any child: 2026-11-17T18:30:56Z child cap 1 (hard: no Phase plan row the runner reads in checkpoint.md; done is refused (exit 10) until it has one)
PASS shellcheck (33 files)
GATE-ONLY: FAIL passed=0 failed=1 shellcheck=ok only=10-chain-done
```
from the same log: `child -9223372036854775808 launched` and `child -9223372036854775807 launched`.

GREEN: `GATE-ONLY: PASS passed=1 failed=0 shellcheck=ok only=10-chain-done`.

Mutant kill (the bound removed from the fixed code):
```
M6-unbounded-digits mutant: <   [[ $c =~ ^(0|[1-9][0-9]{0,8})\ (0|[1-9][0-9]{0,8})$ ]] && [ "${BASH_REMATCH[2]}" -le "${BASH_REMATCH[1]}" ] || >   [[ $c =~ ^(0|[1-9][0-9]*)\ (0|[1-9][0-9]*)$ ]] && [ "${BASH_REMATCH[2]}" -le "${BASH_REMATCH[1]}" ] ||
FAIL 10-chain-done
  | FAIL: child-count '9223372036854775807 0': exit 5, want 1 before any child: 2026-11-17T18:33:31Z child cap 1 (hard: no Phase plan row the runner reads in checkpoint.md; done is refused (exit 10) until it has one)
GATE-ONLY: FAIL passed=0 failed=1 shellcheck=ok only=10-chain-done
M6-unbounded-digits: restored, cmp equal
```

### P4R1-8: the paused-cap resume's `base` save was not pinned

Test-only. By reading, it passes at HEAD's behaviour, so the evidence is the mutant. GREEN: `GATE-ONLY: PASS passed=1 failed=0 shellcheck=ok only=21-soft-cap`.

Mutant kill (the save dropped from the paused-cap branch):
```
M8-pausedcap-no-save mutant: <     paused-cap) [ -z "$CAP_SOFT" ] || { BASE="$LAUNCHED"; chain_count_set; }  # the soft cap's fresh allotment (P4-22a); numbering goes on >     paused-cap) [ -z "$CAP_SOFT" ] || { BASE="$LAUNCHED"; }  # the soft cap's fresh allotment (P4-22a); numbering goes on
FAIL 21-soft-cap
  | FAIL: paused-cap resume at cap 0: exit 6, child-count '2 0', want 6 and '2 2': 2026-11-17T18:34:05Z child cap 0 (soft: JOB_MAX_CHILDREN)
GATE-ONLY: FAIL passed=0 failed=1 shellcheck=ok only=21-soft-cap
M8-pausedcap-no-save: restored, cmp equal
```

### P4R1-9: `base == launched` was never read

Test-only. Test 21's re-run now starts from `2 2`. GREEN as above (21 PASS).

Mutant kill (`-le` to `-lt`):
```
M9-le-to-lt mutant: <   [[ $c =~ ^(0|[1-9][0-9]{0,8})\ (0|[1-9][0-9]{0,8})$ ]] && [ "${BASH_REMATCH[2]}" -le "${BASH_REMATCH[1]}" ] || >   [[ $c =~ ^(0|[1-9][0-9]{0,8})\ (0|[1-9][0-9]{0,8})$ ]] && [ "${BASH_REMATCH[2]}" -lt "${BASH_REMATCH[1]}" ] ||
FAIL 21-soft-cap
  | FAIL: re-run after paused-cap exit 1: blast-off: /tmp/tmp.rLESymMzx4/cwd/test-136631-soft/job/child-count holds '2 2', not '<launched> <base>' (whole numbers of at most 9 digits, base <= launched); fix it, or delete it to count this job's children from 0 again
GATE-ONLY: FAIL passed=0 failed=1 shellcheck=ok only=21-soft-cap
M9-le-to-lt: restored, cmp equal
```

### P4R1-10: test 11's duplicate line

The duplicate line was deleted. `11-unit-smoke` was run alone afterwards: `GATE-ONLY: PASS passed=1 failed=0 shellcheck=ok only=11-unit-smoke`. ExecStart was unchanged. This is not a behaviour change, so it has no RED and no mutant.

### P4R1-11: a zero-byte file was untested

Test-only. By reading, a zero-byte file already exits 1 at HEAD (`cat` gives `''`, and the regex refuses it). GREEN as above (10 PASS).

Mutant kill (`-e` to `-s`):
```
M11-e-to-s mutant: <   [ -e "$f" ] || return 0 >   [ -s "$f" ] || return 0
FAIL 10-chain-done
  | FAIL: zero-byte child-count: exit 4, want 1 before any child: 2026-11-17T18:33:54Z child cap 1 (hard: no Phase plan row the runner reads in checkpoint.md; done is refused (exit 10) until it has one)
GATE-ONLY: FAIL passed=0 failed=1 shellcheck=ok only=10-chain-done
M11-e-to-s: restored, cmp equal
```

After the last mutant, `cmp` of `lib/chain.sh` against the saved fixed copy printed `chain-is-fixed`.

## Next steps

1. Review unit: `git diff` over the 5 tracked files above, then the full gate, alone.
2. Manager: commit the 5 files and this baton.

## Open questions / risks (not fixed; outside this round's list)

- Under the hard cap, a `status: paused-cap` still turns into `running` (and logs `status paused-cap -> running; the chain continues`) before the runner exits 4. No child launches and `base` does not move, but the status line and the log line overstate what happened. A guard that leaves the status alone under the hard cap would be one more line, so I left the choice to the owner or a later round.
- `chain_nums` (`lib/chain.sh:90`) still accepts any length of digits for `JOB_MAX_CHILDREN`, `JOB_CAP_FACTOR` and the others. A huge `JOB_CAP_FACTOR` can overflow `phases * factor` to a negative cap. This is the reviewer's sibling of P4R1-6 and is not in this round's scope.
- With the 9-digit bound, a job that reaches 999999999 children saves `1000000000 ...`, and its next run refuses that as garbled. This is unreachable in practice.
- Test 11 still has no `[ -n "$pid" ]` guard, so without the `rm` it would go vacuous, not red (P4R1-10's second half, not asked for).
- P4R1-8 is half closed against the report's row. The brief named only the save. The read-side mutant in the same row (`BASE="${BASH_REMATCH[2]}"` to `BASE=0`, from silent-failure-hunter) still survives. I ran it once on 21: `Mx-base-zero-on-read mutant: <   LAUNCHED="${BASH_REMATCH[1]}" BASE="${BASH_REMATCH[2]}" >   LAUNCHED="${BASH_REMATCH[1]}" BASE=0`, then `GATE-ONLY: PASS passed=1 failed=0 shellcheck=ok only=21-soft-cap`, then `Mx-base-zero-on-read: restored, cmp equal`. In test 21, every run that reads a nonzero `base` is a paused-cap resume, which sets `base` again. A test that would kill it: a soft job with status `running` that starts from `2 2` at cap 2 must launch child 3. I did not add it.
- `tests/21-soft-cap.sh:27-28` writes `done` to `fake-mode` twice. That predates this round, and I left it.
- The review baton's other open items are untouched: P4R1-2 (a garbled count's refusal goes to stderr only, before run.log exists), P4R1-3 (preflight and status do not show `child-count`), P4R1-4 (README's exit-4 remedy may need a second start), P4R1-5 (a missing or dangling `child-count` reads as fresh, and the start does not log the count), P4R1-7 (the save before launch is pinned only by deaths that run the EXIT trap), and the LOW items P4R1-12 to P4R1-30.

## References

- Issues: z0rd0n88/blast-off issue 22
- Docs: `baton-runner/br-1115-issues/baton-phase-4-review-1.md`, `baton-runner/br-1115-issues/review-phase-4-iter-1.md`, `baton-runner/br-1115-issues/baton-phase-4-work.md`, `docs/spec.md` §2 `JOB_MAX_CHILDREN`, §6 rows `10-chain-done` and `21-soft-cap`
- Code: `lib/chain.sh` `chain_count` (regex bound), the `chain_run` paused-cap branch (soft-only `base`), the cap test (`n - (CAP_SOFT ? BASE : 0)`); `tests/10-chain-done.sh` (paused-cap hard variant, garbled loop, zero-byte case, `basehard`); `tests/21-soft-cap.sh` (cap-0 paused-cap run); `tests/11-unit-smoke.sh` `start_hang`
