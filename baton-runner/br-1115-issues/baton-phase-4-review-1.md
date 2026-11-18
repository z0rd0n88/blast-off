---
source: runner
scope: br-1115-issues
parent_session: ""
---
# Pass-Baton: phase 4 review round 1 (issue 22), VERDICT CLEAN, 0 CRITICAL, 0 HIGH, 11 MEDIUM, 19 LOW

**Date:** 2026-11-17
**Scope:** br-1115-issues
**Branch:** feat/br-1115-issues/phase-4
**Worktree:** /home/alex/blast-off/.claude/worktrees/pending-items-53932d
**HEAD:** f388962 feat(chain): persist the child count per job so the cap survives relaunches (#22)

## Where things stand

VERDICT: CLEAN by the contract's rule: gate exit 0, zero CRITICAL or HIGH in the synthesized report, and every acceptance criterion has a passing test (cited below). CLEAN does not mean nothing to fix. 11 MEDIUM and 19 LOW are open, and they are the manager's to triage. Read P4R1-1 first. I reproduced it: the paused-cap branch resets `base` under the hard cap too, so a hard-capped job with `status: paused-cap` in its checkpoint (a child can write that line), or with a `base` left by an earlier soft pause, launches past `JOB_MAX_CHILDREN` counted over the job. That is criterion 1's invariant failing on a reachable path that no test covers. Reviewers filed it MEDIUM (five of six), and I kept their severity. The work baton's "the hard cap has no reset path", spec row 4 and README row 4 are false as written.

- Gate: `scripts/gate.sh` ran once, alone, before any reviewer: exit 0, `GATE: PASS passed=18 failed=0 shellcheck=ok`. The log holds 18 `PASS NN-` lines for 18 scenario files. No `BLAST_OFF_*` variable was set in the environment, and the tree outside `baton-runner/` was clean at f388962. Log: `baton-runner/br-1115-issues/gate-phase-4-iter-1/tests-run.log`.
- ExecStart check: it read `ExecStart=/home/alex/blast-off/.worktrees/blast-off-build/bin/blast-off run %f` at four points: before the gate, after the gate, after the reviewers, and after my probe and mutant runs. It never changed.
- Multi-agent review: ran. Report: `baton-runner/br-1115-issues/review-phase-4-iter-1.md`. All 6 of 6 reviewers returned. It was reviewed at f388962ab3ecb154ac69fd898d7f24c6f6c08f6f, and a Report Audit is appended: 5 attribution overreaches plus 1 labelling note, none touching a severity or a count. Reviewer outputs: `baton-runner/br-1115-issues/review-phase-4-iter-1/<reviewer>.md`. Deviations, all listed in the report's `## Notes`:
  - The review ran inline from this unit.
  - The six reviewers are parked agents, so each ran as a `general-purpose` agent reading its parked definition read-only.
  - `--high-cap off`.
  - Reviewers were held to static work only, with no scenario runs. I ran their claims myself afterwards, one scenario at a time on a `git archive` copy.
  - A synthesizer agent wrote the report, and an audit agent appended the audit.
- Reviewer side effects: none found. The report's Notes say no reviewer reports deleting, moving or writing any file other than its own output. I checked after the reviewers returned and again after the synthesizer and auditor: `git status` outside `baton-runner/` was empty, HEAD was still f388962, and the review dir held exactly the six files.
- New dependencies: none.
- Tracked files: this unit changed none. `STATE.md` and `log.md` were already modified when this unit started, and I did not touch them.

## Intent check (issue 22)

| Criterion | Evidence | Test real? |
|---|---|---|
| 1. Cap reached across two runner runs stops the job (exit 4) | `tests/10-chain-done.sh:81-83`: a re-run at cap 1 exits 4 with no launch. `:84-89`: a re-run at cap 2 launches child 2, then exits 4 at `child cap 2 reached`. `:127-130`: after SIGHUP during child 1, a re-run at cap 1 exits 4 with no launch. Soft analogue: `tests/21-soft-cap.sh:37-44` | Yes when `base` is 0 (the work baton's RED). It fails when `base` is nonzero (P4R1-1, reproduced below), and no test sets that up |
| 2. Child numbers in run.log continue after a relaunch | `tests/10-chain-done.sh:86-87` (one `child 1 launched`, then `child 2 launched`); `tests/21-soft-cap.sh:35` (paused-cap re-run's child is `child 3`) | Yes (the work baton's 21 RED) |
| 3. A fresh job starts at 1 | `tests/10-chain-done.sh:16` (`child 1 launched`), with no `child-count` file. No new assertion | Yes. M1 below (a missing file starts at `LAUNCHED=1`) turns test 10 red at `:16` ("launch lines missing") |

Probes ran as a scratch scenario (`tests/99-probe.sh`) on a `git archive f388962` copy, through `BLAST_OFF_TEST_ONLY=99-probe tests/run`, in two versions. The first version stopped at D: a `pipefail` in my own `show` helper hit a missing `run.log`, and that version ran twice. Probes A to C come from it, with the same results both times. D to F come from an edited version that kept D to F only and ran once, ending `GATE-ONLY: PASS`.

- A (P4R1-1): no Phase plan, `status: paused-cap` written into the checkpoint, `child-count` `5 0`, `JOB_MAX_CHILDREN=1`. Result: `status paused-cap -> running`, `child 6 launched`, then `child cap 1 reached (6 children launched for this job, ...)`, exit 4, file `6 5`. One child ran past a hard cap of 1 counted over the job.
- B (P4R1-1): no Phase plan, `status: running`, `child-count` `5 5` (a `base` left by an earlier soft pause). Result: `child 6 launched`, exit 4, file `6 5`.
- C (P4R1-6): `9223372036854775807 0`, `JOB_MAX_CHILDREN=1`, noop children. Result: `child -9223372036854775808 launched`, `child -9223372036854775807 launched`, exit 5 (two stalls), file `-9223372036854775807 0`. The cap never fired. By reading, the next run rejects that file as garbled.
- D (P4R1-2): `child-count` `x`. Result: exit 1, and the message (`... holds 'x', not '<launched> <base>' ...; fix it, or delete it ...`) goes to stderr only. `run.log` was never created.
- E (P4R1-5): `child-count` a dangling symlink, cap 1. Result: read as a fresh job, `child 1 launched`, exit 4. The symlink was replaced by a regular file holding `1 0`.
- F (control for P4R1-9): soft cap 2 (2 rows x factor 1), `child-count` `2 2`. Result: parsed, children 3 and 4 launched, exit 6, file `4 2`. So `-le` at HEAD is right, and equality is a real state.

Mutants: each ran alone on its own archive copy, one scenario each, with sequential runs.

- Red as intended: M1, `[ -e "$f" ] || return 0` to `[ -e "$f" ] || { LAUNCHED=1; return 0; }`. Test 10 fails with `FAIL: launch lines missing`.
- Survive, as tdd-guide predicted:
  - M2 (P4R1-7): the save before `child_launch` removed and put in `chain_exit` (`[ -z "${LAUNCHED:-}" ] || chain_count_set || true`). Test 10: `GATE-ONLY: PASS`.
  - M3 (P4R1-8): the paused-cap branch's `chain_count_set` removed, so `BASE` lives only in memory. Test 21: `GATE-ONLY: PASS`.
  - M4 (P4R1-9): `-le` to `-lt` in `chain_count`. Test 10: `GATE-ONLY: PASS`. Probe F shows the real cost: a `k k` file, which every paused-cap resume writes, would then exit 1.
  - M5 (P4R1-11): `[ -e "$f" ]` to `[ -s "$f" ]`. Test 10: `GATE-ONLY: PASS`.
- Not run: a mutant of test 31 (`resume`). It installs real units, so I left it out to keep systemd untouched. P4R1-28 is by reading only.

## Findings

Severity is the report's: the highest any reviewer filed. "Confirmed" means I ran it. The Failure path and Suggested fix cells are cut down from the report's rows. Where a fix is my own and not the report's, the cell says "Mine". For P4R1-1 to -8 and -10, -11, the fixes are the report's or follow it.

| ID | Sev | Where | Failure path | Suggested fix |
|---|---|---|---|---|
| P4R1-1 | MEDIUM | `lib/chain.sh:163,184-186`; claims at `baton-phase-4-work.md:50,134`, `docs/spec.md` row 4, `README.md:136` | The paused-cap branch sets `BASE=$LAUNCHED` in any cap mode, and the hard cap tests `n - BASE`. Two routes reach it: a `status: paused-cap` from a child or left over, or a soft job that loses its readable Phase plan rows. Either way the job gets a fresh hard cap. Confirmed (probes A, B) | Move `base` only when `CAP_SOFT` is set, and make the hard cap compare `n` alone. Add one test with `5 5` and no plan |
| P4R1-2 | MEDIUM | `lib/chain.sh:119-121`, called at `:135` before `chain_lock` `:144` and the trap `:145` | A garbled `child-count` exits 1 with stderr only, so under `start` or the resume timer the reason is only in the journal. Confirmed (probe D: no `run.log`) | `log` the refusal before `die`, or read the count after the trap |
| P4R1-3 | MEDIUM | `lib/preflight.sh`; `lib/units.sh` (`status`) | Neither reads or shows `child-count`. A garbled file, or a job already at its cap, passes `preflight`, then `start` exits at once | Have preflight validate the file and print `launched`/`base` next to the cap |
| P4R1-4 | MEDIUM | `README.md:136`; `lib/chain.sh:183-186` | The README exit-4 remedy ("add a Phase plan table and start again") now pauses at once when the children already launched reach rows x factor. It takes a second start (P4-22b) | Owner decision. Reword the row, or start `base` at `launched` when the cap turns soft |
| P4R1-5 | MEDIUM | `lib/chain.sh:118,152` | A missing or dangling `child-count` is a fresh job even when `run.log` shows launches, and the start line does not log the count a run began from. Confirmed (probe E) | Log `launched`/`base` at start. Treat a non-regular file as garbled |
| P4R1-6 | MEDIUM | `lib/chain.sh:120,183-184` | `9223372036854775807 0` parses, `n` wraps negative, and the cap never fires for that run. Confirmed (probe C) | Bound the digits in the regex (say `{1,9}`) |
| P4R1-7 | MEDIUM | `lib/chain.sh:194-196`; `tests/10-chain-done.sh:118,127-130` | Save-before-launch is tested only on deaths that run the EXIT trap, so a save moved into `chain_exit` passes. The reboot claim has no test behind it. Confirmed (M2 survives) | Assert the file reads `1 0` while child 1 hangs in the hup block |
| P4R1-8 | MEDIUM | `lib/chain.sh:122,163-164`; `tests/21-soft-cap.sh:27-44` | The paused-cap save is masked by the save at `:194`, so dropping it passes. Confirmed (M3 survives) | Run a `JOB_MAX_CHILDREN=0` re-run in test 21 (pauses before a launch), then read the file |
| P4R1-9 | MEDIUM | `lib/chain.sh:120`; `tests/10-chain-done.sh:91-96` | No test reads a `k k` file, so `-le` to `-lt` survives. Under that mutant every paused-cap resume strands the job (exit 1). Confirmed (M4 survives; probe F) | As filed: a `JOB_MAX_CHILDREN=0` run in test 21. Mine: or a `2 2` case that must launch |
| P4R1-10 | MEDIUM | `tests/11-unit-smoke.sh:58-59` | `rm -f "$JOB/child-count"` appears twice with different comments. The baton's reason is also wrong: without it, `pid` is empty and the test goes vacuous, not red | Delete one line. Add `[ -n "$pid" ]` |
| P4R1-11 | MEDIUM | `lib/chain.sh:118`; `tests/10-chain-done.sh:92` | The `''` case writes a newline (1 byte), so `-e` to `-s` survives and a truly empty file would read as fresh. Confirmed (M5 survives) | Add an empty-file case (`: > child-count`) |
| P4R1-12 | LOW | `templates/brief.md:4-5,107,191`; `lib/chain.sh:116,119,125` | The cap used to live in runner memory. Now a child can delete the file or write a smaller valid value (`0 0`). Within a run this heals at `:194`, but the next relaunch resets the cap. With P4R1-1, a child has two ways to reset its own cap | As filed: the brief tells children that `child-count` is the runner's |
| P4R1-13 | LOW | `lib/chain.sh:118` | A job in flight when this lands has no file, so it restarts at child 1 with a full cap, once. That is the issue's own 27-to-30 overrun | Seed from `run.log` (P4R1-5), or one spec sentence |
| P4R1-14 | LOW | `lib/chain.sh:125` | `echo >` follows a planted `child-count.tmp` link and truncates its target (security-reviewer gives `~/.ssh/authorized_keys` as an example). `mv -f` then renames the link to `child-count`. A tmp directory makes every start abort with `runner exit 1 without a state`. A `child-count` directory swallows the temp file | As filed in the report's row |
| P4R1-15 | LOW | `lib/chain.sh:118-121` | `[ -e ]` accepts any file type. A FIFO blocks `cat` forever before the lock (the unit stays active, and `status` shows running). A link to `/dev/zero` reads without bound | `[ -f "$f" ] && [ ! -L "$f" ]`, then `head -c` |
| P4R1-16 | LOW | `lib/chain.sh:121`; `bin/blast-off:48` | `die` prints `$c` unescaped, so ESC sequences reach a terminal. security-reviewer: a `child-count` linked to the owner's secrets file prints `GH_TOKEN` into the user journal (not into `run.log`) | `printf %q`, or name only the shape |
| P4R1-17 | LOW | `lib/chain.sh:30,135,144-145`; `bin/blast-off:55-58` | The read-before-lock window is a few statements, which reviewers judge practically unreachable with a live runner. Under the documented stale-lock race, both runners read the same `LAUNCHED` and give duplicate numbers | Read after `chain_lock` |
| P4R1-18 | LOW | `lib/chain.sh:121,124-125`; comment `:194` | There is no `sync` before the rename. A power cut can leave an empty file (fails closed) or the old count (the reboot child goes uncounted). The die message's "delete it" resets the cap | As filed in the report's row |
| P4R1-19 | LOW | `lib/chain.sh:194-195`; `lib/child.sh:41-50` | If `mktemp -d`, `sed` or `tmux new-window` fails after the save, the runner aborts with the count already raised. A broken tmux and some retries can exhaust a hard cap of 12 with no child run. Numbering gaps appear, and "N children launched" overstates. Reviewers call this order intended | Spec clause ("launched" means attempted) |
| P4R1-20 | LOW | `tests/11-unit-smoke.sh:28,38,58-59,62,66` | Test 11 is the only start-to-start sequence, and the `rm` makes every restart a fresh job. So no test shows the count surviving a unit relaunch. No production code depends on `child-1` | Take the number from the file instead of resetting it |
| P4R1-21 | LOW | `lib/chain.sh:172-173`; `tests/22-dirty-tree.sh:28`; `docs/spec.md:94,96`; `bin/blast-off:35`; test 40 comments `:81,90,109` | `run.log` says "dirty tree before child 1" though it already has `child 1 launched`, and a test pins that text. Test 40's comments and `lib/child.sh:9-10` still say child 1 | Name `$((LAUNCHED+1))`, or accept |
| P4R1-22 | LOW | `lib/chain.sh:185`; `docs/spec.md:91`; `tests/10-chain-done.sh:75,89` | The message reads "(1 children launched ...)" and does not name deleting the file. Tests grep only `child cap N reached`, so reverting `:185` survives | Assert the message's tail |
| P4R1-23 | LOW | `lib/checkpoint.sh:5,118` | Not new in this commit. The first `status:` line anywhere in the file counts, which widens P4R1-1's route (a) | Fix together with PT-1's runner-owned pause marker |
| P4R1-24 | LOW | `tests/10-chain-done.sh:79-96,127-130`; `tests/21-soft-cap.sh:34-44` | Every check reads `run.log`, so a wrong saved `base` shows only in a later run. No case covers the hard cap plus `paused-cap`, overflow, a symlink, a directory, or a missing file with `run.log` history. Criterion 3 has no new assertion, though it is held (M1) | Read the file's content in the tests |
| P4R1-25 | LOW | `lib/chain.sh:120,183-184`; `tests/10-chain-done.sh:91-96` | Dropping `$` lets `1 0 x` match. Writing group 2 as `([0-9]+)` survives, and then `1 08` aborts at `:184` ("value too great for base") with the path message lost | Add `1 0 x` and `1 08` cases |
| P4R1-26 | LOW | `bin/blast-off:18,33-35,71` | `--help` does not say the cap counts across runs | Append "per job (its child-count), across runs" to `:18` |
| P4R1-27 | LOW | `docs/spec.md:61,225`, §2, row 6, §6 row 10 | The spec says "two whole numbers", but leading zeros are refused. §2 says the file is written "before each child launches", but the paused-cap resume also writes it. Other nits as filed | As filed |
| P4R1-28 | LOW | `tests/31-resume-after-reset.sh:58-61` | The `cap` resume there passes regardless of the `base` logic (a fresh job) | Optional |
| P4R1-29 | LOW | `tests/21-soft-cap.sh:37-44` | The `relaunch` case does not assert `status: paused-cap` after its exit 6 | One grep |
| P4R1-30 | LOW | `lib/chain.sh` | `LAUNCHED` and `BASE` are unprefixed globals. An exported `BASE` is overwritten and reaches children | Rename, optional |

The report also lists 6 PENDING open questions (its `## Open Questions for the Author`). Its Report Audit has 5 items, all attribution overreaches, none touching a severity or a count:

- The P4R1-7 disagreement credits critical-thinking and code-reviewer with a claim they did not make.
- The P4R1-1 fix is credited to all six reviewers.
- The P4R1-6 fix is credited to "all".
- The P4R1-17 ponytail note is credited to "All".
- Loose credits in the Coverage and Disagreements sections.

## Next steps

1. Manager: triage P4R1-1 to P4R1-30. P4R1-1 is a one-guard fix (`[ -z "$CAP_SOFT" ] || BASE=$LAUNCHED`, and the hard cap compares `n`), plus one test (`5 5`, no plan, cap 1, must exit 4 with no launch). It makes the docs this commit wrote true.
2. If a fix round runs, the test-binding items are each a line or two in tests 10, 11 and 21: P4R1-7, -8, -9, -10, -11. The parser items are each a line in `chain_count`: P4R1-6, -15, -16.
3. Owner: P4-22a and P4-22b (below), and whether the cap must hold against a child that deletes `child-count` or writes `status: paused-cap`.

## Open questions / risks

- P4-22a (work baton): is the soft cap a lifetime cap, or a fresh allotment per paused-cap resume? PENDING.
- Why should `base`, which exists only for the soft cap's allotment, apply to the hard cap at all? PENDING (P4R1-1).
- P4-22b (work baton): should README row 4 say that adding a Phase plan after exit 4 may need a second start, and should hard-capped children count against the first soft allotment? PENDING.
- Reusing a job dir: is `rm child-count` the intended reset, and should the README say so? PENDING.
- Is the cap meant to hold against a child that deletes `child-count` or writes `status: paused-cap`, or only against runner relaunches? PENDING.
- Is "launched" meant to be "attempted" (a launch that fails after the save counts)? PENDING.
- CLEAN rests on the contract's rule. P4R1-1 is a reproduced path on which criterion 1's "stops the job" does not hold, and no test covers it.
- Scratch left behind: `/tmp/claude-1000/-home-alex-blast-off--claude-worktrees-pending-items-53932d/60b15296-819e-491a-8ffe-34b3bd988f86/scratchpad/p4r1.1QfhXF` holds the archive copy, the probe scenario, `mutants.sh`, the per-mutant copies and logs, `probe.out` and `probe-ABC.out`.

## References

- Issues: z0rd0n88/blast-off issue 22 (blocks 17 and 20)
- Docs: `baton-runner/br-1115-issues/review-phase-4-iter-1.md`, `baton-runner/br-1115-issues/review-phase-4-iter-1/<reviewer>.md`, `baton-runner/br-1115-issues/gate-phase-4-iter-1/tests-run.log`, `baton-runner/br-1115-issues/baton-phase-4-work.md`, `baton-runner/br-1115-issues/phase-4/findings.md`
- Code: `lib/chain.sh:113-125` (`chain_count`, `chain_count_set`), `:135`, `:163`, `:183-186`, `:194`; `tests/10-chain-done.sh:16,79-96,127-130`; `tests/21-soft-cap.sh:34-44`; `tests/11-unit-smoke.sh:58-59`
