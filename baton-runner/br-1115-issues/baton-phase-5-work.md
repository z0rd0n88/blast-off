---
source: runner
scope: br-1115-issues
parent_session: ""
---
# Pass-Baton: phase 5 work unit, issue 39 (child-count follow-ups) implemented

**Date:** 2026-11-17
**Scope:** br-1115-issues
**Branch:** feat/br-1115-issues/phase-5
**Worktree:** /home/alex/blast-off/.claude/worktrees/pending-items-53932d
**HEAD:** c4e2a41 Merge pull request #38 (changes uncommitted; the manager owns git)

## Where things stand

Every issue 39 item named in the brief is done test-first: P4R2-1, P4R2-2, P4R1-2, P4R1-3, P4R1-4/P4-22b, P4R1-5, P4R1-7, the two LOWs P4R2-9 and P4R2-10, and the owner-ruling docs for P4R2-4 and P4R2-11. P4R1-7 was feasible in the harness: test 10 SIGKILLs a foreground runner during child 1. Scenarios run alone, one at a time, all PASS: 10, 11, 21, 60, 70-docs, plus the neighbours 22, 23, 30, 31 and 50. I did not run the full gate. `shellcheck -S warning` is clean on the 7 changed scripts. Nothing committed; STATE.md and log.md untouched.

Files changed (tracked, 9; `git diff --stat`: 106 insertions, 32 deletions):
- `lib/chain.sh`:
  - `chain_nums`: `^[0-9]+$` became `^[0-9]{1,9}$`, and the message says "not a whole number of at most 9 digits" (P4R2-9).
  - `chain_count` no longer dies. It returns 1 with `COUNT_ERR` set, and on success sets `COUNT_SAY`: `child-count: none, a fresh job; first child 1`, or `child-count: L launched, base B; next child L+1`. `[ -e ] || [ -L ]` makes a dangling symlink garbled ("cannot read <f>: <cat's error>"), not fresh (P4R1-5). The garbled message is unchanged.
  - `chain_run`: `chain_count || { log "$COUNT_ERR" >&2; exit 1; }`, so the refusal reaches run.log and stderr. It still comes before the lock and the trap, before any child, and never rewrites the file (P4R1-2). `log "$COUNT_SAY"` comes right after the `child cap` line (P4R1-5).
  - Comments: `chain_cap` says a paused-cap status already reads running at exit 4 (P4R2-4). The cap-test comment says the hard cap never resets "unless the owner deletes child-count" (P4R2-11).
- `lib/preflight.sh`: after `cap:`, a new line `<COUNT_SAY>; N left under cap M`. Under the soft cap a `paused-cap` status counts `base` as `launched`, the fresh allotment `run` gives. A garbled file prints `child-count: <COUNT_ERR>` and is a refusal reason. Header comment updated (P4R1-3).
- `lib/units.sh` `unit_status`: prints `COUNT_SAY`, or `child-count: <COUNT_ERR>` without failing, with no "left" (P4R1-3).
- `tests/10-chain-done.sh`:
  - The cap job: run.log logs `child-count: none, a fresh job; first child 1`, and the re-run logs `child-count: 1 launched, base 0; next child 2` (P4R1-5).
  - The paused-cap exit-4 case also asserts `status: running` (P4R2-4).
  - The garbled loop also requires the child-count path in run.log (P4R1-2).
  - New `badcount-link` case: `ln -s nowhere child-count` gives exit 1, no child, the link kept, and the reason in run.log (P4R1-5).
  - New `kill` job (hang): while child 1 runs, `child-count` = `1 0`. Then `kill -KILL` of the runner (rc 137, no EXIT trap), and a re-run at `JOB_MAX_CHILDREN=1` exits 4 with exactly one `child N launched` (P4R1-7).
- `tests/21-soft-cap.sh`:
  - Header reworded (P4R2-4).
  - After the cap-0 run, `2 0` is put back, so the re-run must move the in-memory BASE (P4R2-2).
  - New `base` job: plan 2, status running, `child-count` `2 2`, factor 1. It must launch children 3 and 4, then exit 6 at `4 2` with no child 5 (P4R2-1).
  - The bad-number loop adds `JOB_MAX_CHILDREN=99999999999999999999` and `JOB_CAP_FACTOR=1000000000` (P4R2-9).
- `tests/60-preflight.sh`:
  - p1 asserts `child-count: none, a fresh job; first child 1; 9 left under cap 9`.
  - New tail: `9 0` gives `0 left`. `9 0` at `paused-cap` gives `9 left`. `x` gives exit 1, a `child-count: <f> holds 'x', ...` line, `preflight: refused: <f> holds 'x', ...`, and the file is left as `x`.
- `tests/11-unit-smoke.sh`: `status` shows `child-count: 1 launched, base 0; next child 2` while child 1 runs (P4R1-3). `start_hang` gets `[ -n "$pid" ] || fail ...` (P4R2-10).
- `docs/spec.md`:
  - The `status` and `preflight` rows describe the new lines and the refusal.
  - The JOB_MAX_CHILDREN text says the hard cap "never resets unless you delete `child-count` (the one deliberate reset, owner ruling P4R2-11)". It also says each run logs its starting count, and that a dangling symlink is garbled, refused with its reason in run.log and on stderr.
  - Exit 1 now covers "at most 9 digits" and "also logged in `run.log`".
  - The exit-4 status column now reads "unchanged, but a `paused-cap` already reads `running`: the run sets it before the cap stops it (owner ruling P4R2-4)".
  - Test rows 10, 11, 21 and 60 updated.
- `README.md`:
  - The preflight and status comment lines add "child count".
  - The exit-4 remedy says the start can pause at `paused-cap` before any child, because the children already launched count against the first soft allotment, so `blast-off resume <job-dir>` follows (P4R1-4/P4-22b). It also says deleting `child-count` is the one reset of the count (P4R2-11).

Untracked: `baton-runner/br-1115-issues/phase-5/{task_plan,findings,progress}.md` and this file.

## Decisions (also in `phase-5/findings.md`)

- **chain_count returns rather than dies,** so preflight and status can show a garbled file. `run` refuses it with `log "$COUNT_ERR" >&2; exit 1`, which writes one timestamped line to run.log and stderr. The line has no `blast-off:` prefix.
- **A missing file stays a fresh job** (P4R2-11 makes deleting it the owner's reset). I added no recovery from run.log. Each run now logs the count it starts from, so a silent reset is visible.
- **A dangling symlink is garbled** (exit 1). A symlink to a real file is still read, and the first save replaces the link, as before.
- **preflight shows `left` but does not refuse at the cap,** to keep the change minimal. `0 left` says start would exit 4 or 6 at once. A refusal there is an owner call.
- **status shows no `left`.** status runs in the caller's environment, not the unit's, so a cap it computed could differ from the runner's.
- **chain_nums bounds digits only.** Leading zeros keep their old behaviour, so `JOB_CAP_FACTOR=08` still breaks the arithmetic as octal. That predates this phase and is noted only.
- **P4R2-2: I re-seeded `2 0`** rather than adding a new job. It is the reviewers' second option, and the smaller one.
- **P4R2-4:** I added one assertion at the old `10:93` (`status: running`) to pin the ruling. It passes on old code too, since it documents existing behaviour.

## Evidence

Old code means a `git archive c4e2a41` copy with the new tests copied in. Mutants are copies of the new code with one edit each. All were scratchpad copies, run one at a time, and ExecStart was checked after each run.

RED, old code:
- `10-chain-done`: `FAIL: the count a fresh run starts from not logged (P4R1-5): 2026-11-18T03:29:47Z child cap 1 (hard: no Phase plan row the runner reads in checkpoint.md; done is refused (exit 10) until it has one)`
- `21-soft-cap`: `FAIL: JOB_MAX_CHILDREN=99999999999999999999 exit 0, want 1 before any child: ... chain.sh: line 186: [: 99999999999999999999: integer expression expected ... child 1 launched` (P4R2-9). The run got past the new `2 0` re-seed and the `base` job: old code is correct there.
- `60-preflight`: `FAIL: no line /^child-count: none, a fresh job; first child 1; 9 left under cap 9$/ in p1.out` (P4R1-3)
- `11-unit-smoke`: `FAIL: status lacks the child count (P4R1-3): # Checkpoint: test ... ActiveState=active / resume timer: inactive`
- Probe `90-red-runlog` (P4R1-2): `FAIL: child-count 'x': the refusal is not in run.log: cat: .../run.log: No such file or directory` / `GATE-ONLY: FAIL passed=0 failed=1 shellcheck=ok only=90-red-runlog`
- Probe `91-red-link` (P4R1-5): `FAIL: dangling child-count link: exit 4, want 1 before any child, link kept: ... child 1 launched ... child cap 1 reached (1 children launched for this job, .../child-count)` / `GATE-ONLY: FAIL ... only=91-red-link`
- Probe `92-red-pfbad` (P4R1-3 garbled): `FAIL: garbled child-count: exit 0, want 1 and refused: ... preflight: ok` / `GATE-ONLY: FAIL ... only=92-red-pfbad`

Mutants, new code (each kills the named mutant):
- MA, `chain.sh:127` `BASE="${BASH_REMATCH[2]}"` -> `BASE=0` (P4R2-1): `FAIL: soft run from '2 2' at cap 2: exit 6, child-count '2 2', want 6, children 3 and 4, '4 2': ... child-count: 2 launched, base 0; next child 3 ... soft cap 2 reached`
- MB, the paused-cap branch `{ BASE="$LAUNCHED"; chain_count_set; }` -> `{ echo "$LAUNCHED $LAUNCHED" > "$JOB/child-count"; }` (P4R2-2): `FAIL: re-run after paused-cap exit 6: ... status paused-cap -> running; the chain continues ... soft cap 2 reached; status paused-cap; run again to continue`
- MT, save moved from before `child_launch` into `chain_exit` (P4R1-7): `FAIL: child-count while child 1 runs: 'cat: .../test-445763-kill/job/child-count: No such file or directory', want '1 0'`
- MT2, MT with the `1 0` check removed from the test, so only the SIGKILL re-run judges: `FAIL: re-run after a SIGKILLed runner, cap 1: exit 4, want 4 and no launch: ... child-count: none, a fresh job; first child 1` (two launches)
- MG, `start_hang` without `rm -f child-count`, so the hang child is child 2 and `pid` is empty (P4R2-10): `FAIL: hanging child 1 left no pid (stop): child=2 pid=457502 mode=hang gh_token=set prev_alive=no`

GREEN (worktree, `BLAST_OFF_TEST_ONLY=<name> tests/run`, one at a time):
- `GATE-ONLY: PASS passed=1 failed=0 shellcheck=ok only=10-chain-done` (47 s)
- `GATE-ONLY: PASS passed=1 failed=0 shellcheck=ok only=21-soft-cap` (15 s)
- `GATE-ONLY: PASS passed=1 failed=0 shellcheck=ok only=60-preflight` (5 s)
- `GATE-ONLY: PASS passed=1 failed=0 shellcheck=ok only=11-unit-smoke` (14 s)
- `GATE-ONLY: PASS passed=1 failed=0 shellcheck=ok only=70-docs`
- Neighbours: 22-dirty-tree, 23-runner-lock, 30-paused-limit, 50-checkpoint-size and 31-resume-after-reset each `GATE-ONLY: PASS`.

ExecStart check: before the first run and after every run (old-code 11, mutant 11, green 11, 31, and the rest), always `ExecStart=/home/alex/blast-off/.worktrees/blast-off-build/bin/blast-off run %f`.

## Open questions / risks

- P4R1-7: a save moved to between `child_launch` and `child_wait` still survives. The kill comes after the child is up, so the gap cannot be hit. It is near-equivalent and I did not run it.
- P4R2-3 is still open: test 21's resume-log grep is also satisfied by the cap-0 run's own line. The re-seed does not change that, and I left it alone as out of scope.
- The new `child-count: ...; next child N` run.log line contains `child N`. Test 50's `grep -n 'child 2' | head -n 1` would match it on a re-run job, but test 50 runs only fresh jobs, so `first child 1` and no match (it passes). Watch for other `grep 'child N'` positional checks.
- preflight at the cap shows `0 left` but passes. Should it refuse? That is an owner question.
- `log "$COUNT_ERR"` runs before the lock, so a second runner beside a live one, given a garbled file, also appends to run.log. This is harmless.
- Not done, as out of scope: P4R1-20 (test 11 still deletes `child-count`), P4R2-5, -6, -7, -8 and -12, P4R1-21 to -30, and the `bin/blast-off` help header (P4R1-26).

## Next step for the review unit

Run the full gate alone (`scripts/gate.sh`), then review `git diff c4e2a41` on the 9 tracked files. Check that preflight's `left` matches `chain_run`'s cap test, including soft `paused-cap` and the hard cap with `base` > 0. Check the wording of the new docs against the owner rulings P4R2-4 and P4R2-11.
