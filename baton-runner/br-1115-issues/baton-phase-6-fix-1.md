---
source: runner
scope: br-1115-issues
parent_session: ""
---
# Pass-Baton: phase 6 fix round 1 (issue 14): P6R1-1 (owner ruling), -2, -3, -4, -5, -6, -7, -8, -10, -11 fixed

**Date:** 2026-11-18
**Scope:** br-1115-issues
**Branch:** feat/br-1115-issues/phase-6
**Worktree:** /home/alex/blast-off/.claude/worktrees/pending-items-53932d
**HEAD:** 174f873 chore(phase-6): review round 1 ISSUES (1 HIGH); owner ruling P6R1-1; fix round started (changes uncommitted; the manager owns git)

## Where things stand

The HIGH is fixed under owner ruling P6R1-1, and the nine items the manager named are fixed, test-first, under the
manager's defaults. P6R1-9, -12, -13, -14 and the LOWs are not touched (notes below).

Scenarios run, each alone, one at a time (never the full gate): 13-wait (1 baseline after the test-helper change,
6 RED, 6 GREEN, 12 mutant runs, 1 final) and 70-docs (1 final). Final results, on the final code:
- 13-wait: `GATE-ONLY: PASS passed=1 failed=0 shellcheck=ok only=13-wait`
- 70-docs: `GATE-ONLY: PASS passed=1 failed=0 shellcheck=ok only=70-docs`

`shellcheck -S warning` is clean on `lib/units.sh`, `bin/blast-off` and `tests/13-wait.sh`, and tests/run's own
shellcheck pass (34 files) is ok on every run.

`~/.config/systemd/user/blast-off@.service` read `ExecStart=/home/alex/blast-off/.worktrees/blast-off-build/bin/blast-off run %f`
four times: before the first run, after the first 13-wait run, after the 12 mutant runs, and after the final runs. It
never changed. 13-wait uses its own fake `systemctl` only. No real unit, timer, systemd-run or install was used, and
tests 11 and 31 were not run.

After every mutant, `lib/units.sh` was restored from the GREEN copy and `cmp` confirmed it was identical (12 of 12).
The edits made after the mutants are comments only in `lib/units.sh` and the test header, plus usage text in
`bin/blast-off`, and the final 13-wait and 70-docs runs cover them. No `blast-off wait` process was left running.

Files changed (tracked, 7):
- `lib/units.sh` (`unit_wait`, `wait_snap`, new `wait_logged`):
  - P6R1-1: `final` only when run.log's last runner line (one starting `YYYY-MM-DDTHH:MM:SSZ `, as `log` writes it)
    is `job done` for status `done` or `job blocked; see ` for status `blocked`. That is the exact `chain_end 0`/`3`
    text, lib/chain.sh:194-195. An unlogged `done`/`blocked` is no change. It keeps waiting while the unit is up and
    reads `stuck` once unit and timer are down.
  - P6R1-3: `stuck` only after two polls in a row with unit and timer down (counter `down`). The first such poll
    reports nothing, not even `changed`.
  - P6R1-2: the paused-cap stuck line ends `; paused-cap: run blast-off resume <job>`, others `; see blast-off status <job>`.
  - P6R1-5: `wait_snap` returns 1 with `WAIT_ERR` instead of `die`. At start that means exit 1 with the reason:
    `missing <job>/checkpoint.md`, or `systemctl --user show <unit>.service or .resume.timer failed (no user bus?)`.
    Mid-watch the read is retried each poll, with systemctl's stderr dropped.
  - P6R1-6: `BLAST_OFF_WAIT_POLL` must match `^[0-9]{1,4}(\.[0-9]{1,3})?$` and be 100 to 3600000 ms. Otherwise the
    exit is 1 with `BLAST_OFF_WAIT_POLL='<v>' is not a number of seconds from 0.1 to 3600`, before any read. The check
    is pure bash, with no new dependency.
  - P6R1-7: the status field is `status: <word>`, plus `until <[0-9TZ:.+-]{1,40}>` when present. The phase line loses
    control characters and has `·` replaced by `-`. Each field is cut to 80 characters. SNAP compares these cleaned
    fields.
- `tests/13-wait.sh`:
  - The fake systemctl now logs each `show` to `sd/calls`. With `sd/fail` present it fails as with no bus. `sd/next`
    runs once, right after a resume timer reads inactive.
  - `blocks` waits for three more snapshots instead of `sleep 1` (P6R1-11).
  - The fin block is rewritten for P6R1-1.
  - New blocks: P6R1-7 escape and forged fields, status-only change (P6R1-4), `activating` (P6R1-8), timer handoff
    (P6R1-3), paused-cap advice (P6R1-2), systemctl failing at start (P6R1-5), bad poll values (P6R1-6), and failed
    reads mid-watch (P6R1-5).
- `README.md`: the wait table now has separate `final`, paused-cap `stuck`, other `stuck` and exit-1 rows. A sentence
  covers the field cleaning.
- `docs/spec.md`: the `wait` row, the wait exit-code paragraph and the 13-wait test row.
- `bin/blast-off`: the usage lines for wait's exit codes, and `BLAST_OFF_WAIT_POLL`'s range.
- `skills/blast-off/SKILL.md` step 8 (P6R1-10): run wait after `start` or `resume` returns, since before that it
  reads as stuck. It also gives the meaning of 0, 12 and paused-cap's advice, and of 1 (the reason is on stderr; fix
  it, do not rerun unchanged).
- `baton-runner/br-1115-issues/phase-6/findings.md`: corrects the wrong claim that exits 9/10 leave the status
  `running` (they leave it `done`), and adds the decisions of this round.

## Evidence, per finding

### P6R1-1 (HIGH, owner ruling): `final` on a child-written done
RED (13-wait, HEAD code):
```
FAIL 13-wait
  | FAIL: wait returned before any change (status done the runner has not logged: it may still refuse it (receipts, CI)): rc 0: wait: final · status: done · phase: 1 of 1 · child 0 · unit active · timer inactive
GATE-ONLY: FAIL passed=0 failed=1 shellcheck=ok only=13-wait
```
GREEN: `PASS 13-wait` / `GATE-ONLY: PASS passed=1 failed=0 shellcheck=ok only=13-wait`.
Mutant M1 (final on any done/blocked, the old rule):
```
  | FAIL: wait returned before any change (status done the runner has not logged: it may still refuse it (receipts, CI)): rc 0: wait: final · status: done · phase: 1 of 1 · child 0 · unit active · timer inactive
restored: cmp lib/units.sh identical
```
Mutant M1b (any `job done` line in run.log, not the last runner line):
```
  | FAIL: wait exit 0, want 12 (done refused by the runner): wait: final · status: done · phase: 1 of 1 · child 0 · unit inactive · timer inactive
restored: cmp lib/units.sh identical
```
Mutant M1c (run.log's last line, no timestamp anchor):
```
  | FAIL: wait exit 0, want 12 (done refused by the runner): wait: final · status: done · phase: 1 of 1 · child 0 · unit inactive · timer inactive
restored: cmp lib/units.sh identical
```

### P6R1-3: false `stuck` at the resume-timer handoff
RED:
```
  | FAIL: wait exit 12, want 11 (one poll with the timer gone and the unit not up yet): wait: stuck · status: paused-limit until 2099-01-01T00:00:00Z · phase: 1 of 1 · child 0 · unit inactive · timer inactive; see blast-off status /tmp/tmp.cVovj23NkK/cwd/test-1070298-hand/job
GATE-ONLY: FAIL passed=0 failed=1 shellcheck=ok only=13-wait
```
(The new P6R1-4 and P6R1-8 tests, which come before it in the file, passed in this run.) GREEN: `GATE-ONLY: PASS passed=1 failed=0 shellcheck=ok only=13-wait`.
Mutant M3 (stuck on the first down poll):
```
  | FAIL: wait exit 12, want 11 (one poll with the timer gone and the unit not up yet): wait: stuck · status: paused-limit until 2099-01-01T00:00:00Z · phase: 1 of 1 · child 0 · unit inactive · timer inactive; see blast-off status /tmp/tmp.0JjlSCPyma/cwd/test-1125091-hand/job
restored: cmp lib/units.sh identical
```

### P6R1-2: paused-cap's line says why
RED:
```
  | FAIL: paused-cap line does not say to resume: wait: stuck · status: paused-cap · phase: 1 of 1 · child 0 · unit inactive · timer inactive; see blast-off status /tmp/tmp.Lv1Zho6CFt/cwd/test-1077816-pause/job
GATE-ONLY: FAIL passed=0 failed=1 shellcheck=ok only=13-wait
```
GREEN: `GATE-ONLY: PASS passed=1 failed=0 shellcheck=ok only=13-wait`.
Mutant M2 (same advice for every stuck):
```
  | FAIL: paused-cap line does not say to resume: wait: stuck · status: paused-cap · phase: 1 of 1 · child 0 · unit inactive · timer inactive; see blast-off status /tmp/tmp.noX5IywT99/cwd/test-1128105-pause/job
restored: cmp lib/units.sh identical
```

### P6R1-4 and P6R1-8: test gaps (the code was already right; no RED by design)
Mutant A (the review's: status dropped from the compare, `[ "${SNAP#* · }" = "${was#* · }" ]`):
```
  | FAIL: wait did not return (status only): 
restored: cmp lib/units.sh identical
```
Mutant B (stuck unless the unit or timer is exactly `active`, so `activating` is stuck):
```
  | FAIL: wait returned before any change (unit activating): rc 12: wait: stuck · status: running · phase: 1 of 1 · child 0 · unit activating · timer inactive; see blast-off status /tmp/tmp.hm0hl9c8Tw/cwd/test-1136486-act/job
restored: cmp lib/units.sh identical
```

### P6R1-5: a failed read mid-watch exited 1
RED (the at-start case runs first in the file):
```
  | FAIL: wait with systemctl failing at start: exit 1: Failed to connect to bus: No such file or directory
GATE-ONLY: FAIL passed=0 failed=1 shellcheck=ok only=13-wait
```
GREEN: `GATE-ONLY: PASS passed=1 failed=0 shellcheck=ok only=13-wait`.
Mutant M5 (`wait_snap || die` mid-watch, the old behaviour):
```
  | FAIL: an empty checkpoint.md mid-watch ended wait: rc 1: blast-off: missing /tmp/tmp.f2Qh7BY4BS/cwd/test-1138836-retry/job/checkpoint.md
restored: cmp lib/units.sh identical
```
The systemctl-failing-mid-watch check comes after the empty-checkpoint check in the same block, so M5 stops at the
first. No separate mutant was run for the systemctl case alone.

### P6R1-6: `BLAST_OFF_WAIT_POLL` not validated
RED:
```
  | FAIL: BLAST_OFF_WAIT_POLL=0: exit 124, want 1 before watching: 
GATE-ONLY: FAIL passed=0 failed=1 shellcheck=ok only=13-wait
```
GREEN: `GATE-ONLY: PASS passed=1 failed=0 shellcheck=ok only=13-wait`. The values tested are 0, inf, abc, 0.05, 3601
and --help. Each must exit 1 with the exact message.
Mutant M6 (validation removed):
```
  | FAIL: BLAST_OFF_WAIT_POLL=0: exit 124, want 1 before watching: 
restored: cmp lib/units.sh identical
```

### P6R1-7: child-written text raw in the line
RED (`cat -v`; `M-BM-7` is `·`):
```
  | FAIL: wait line lacks 'wait: changed · status: running · phase: 1 of 1 [31mred]0;t - child 9 xx' (child-written text): wait: changed · status: running · phase: 9 of 9 · child 99 · unit active · phase: 1 of 1 ^[[31mred^[]0;t^G · child 9 xxxx...(200 x) · child 1 · unit active · timer inactive
GATE-ONLY: FAIL passed=0 failed=1 shellcheck=ok only=13-wait
```
GREEN: `GATE-ONLY: PASS passed=1 failed=0 shellcheck=ok only=13-wait`.
Mutant M7a (no control-character strip):
```
  | FAIL: wait line lacks 'wait: changed · status: running · phase: 1 of 1 [31mred]0;t - child 9 xx' (child-written text): wait: changed · status: running · phase: 1 of 1 ^[[31mred^[]0;t^G - child 9 xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx · child 1 · unit active · timer inactive
restored: cmp lib/units.sh identical
```
Mutant M7b (no 80-character cap):
```
  | FAIL: phase field is 236 characters, want at most 80: phase: 1 of 1 [31mred]0;t - child 9 xxxx...
restored: cmp lib/units.sh identical
```
Mutant M7c (raw status line):
```
  | FAIL: wait line lacks '...' (child-written text): wait: changed · status: running · phase: 9 of 9 · child 99 · unit active · phase: 1 of 1 [31mred]0;t - child 9 xxx... · child 1 ...
restored: cmp lib/units.sh identical
```

### P6R1-10 (SKILL.md step 8) and P6R1-11 (`blocks` helper)
These are docs and test-harness changes, so they have no behaviour mutant. 70-docs passes. The new `blocks` passed
the baseline run on HEAD code and every GREEN run. It is what kills mutants A and B, M1 and M3 above.

## Decisions (also in phase-6/findings.md)

- P6R1-1: the run.log status and the checkpoint status must pair: `done` needs `job done`, and `blocked` needs
  `job blocked; see`. run.log is read only while the status is `done`/`blocked`.
- The anchor rests on the runner's own order. A child's text in run.log (child_report, child_screen) is always
  followed by the runner's timestamped `child <n> usage` line before the status is read. So only a runner killed
  between the two can leave a forged timestamped line last.
- P6R1-3: two polls, fixed, with no env knob. A resume.service that waits out an old runner still `deactivating`
  (up to 60 s) can exceed two polls at 5 s. That case is not covered, because at a usage reset the old runner exited
  long before.
- P6R1-5: systemctl failing **at start** exits 1 with a reason. The manager said "only a missing job dir / checkpoint
  at START exits 1". I read a start-time bus failure as the same class, because retrying it forever would be a silent
  hang. The README exit-1 row and SKILL.md say so.
- P6R1-6: the bounds are 0.1 to 3600 s, at most 4 integer digits and 3 decimals.
- P6R1-7: `·` is replaced by `-` in the phase so it cannot forge fields within the 80 characters.
- `docs/spec.md` and `README.md` changed only where these fixes made them wrong.

## Not fixed (as briefed), and other observations

- Not touched: P6R1-9 (unit-name mismatch, README's `start` advice), P6R1-12 (sleep test kills only `date`),
  P6R1-13 (thin fake / no real-systemd wait check; my fake changes are only what these tests need), P6R1-14
  (70-docs only checks that wait is mentioned), and every LOW (P6R1-15 to -35).
- P6R1-16 and P6R1-28 still stand. The `pc` test flips the unit before the status, so its stuck line may say
  `see blast-off status` (running) or `paused-cap: run blast-off resume`. It asserts only `wait: stuck`. `pc2`
  pins the paused-cap advice.
- P6R1-18: the spec paragraph still says wait's codes are outside the runner's range. 0 and 1 are not. The 1 clause
  was reworded because my causes made it wrong; the range claim was left alone.
- P6R1-19: the spec still says the caller's background command has a timeout. Not touched.
- New limits from this round:
  - A job dir or checkpoint.md deleted mid-watch is retried forever and never reads stuck.
  - A phase change past character 80, or free text after the status word, is no change.
  - Under a C locale, `${ph:0:80}` cuts bytes and can split a multibyte character.
- Stuck now takes one extra poll (~5 s) to report.
- `SC2015` (`A && B || C`) on the paused-cap echo is info level, so it is not flagged at `-S warning`.
- The PostToolUse hook asked for `skill-sheriff-cc` on `skills/blast-off` before committing, because SKILL.md
  changed. I did not run it (no commit here; the manager owns git). The manager should run it, or record that it was
  skipped, before the commit.
- Tooling: the context-mode hook cuts tool output over ~5 KB, so files were read in parts. That had no effect on the
  work.
- STATE.md and log.md untouched. No git operations. Scratch is
  `/tmp/claude-1000/-home-alex-blast-off--claude-worktrees-pending-items-53932d/60b15296-819e-491a-8ffe-34b3bd988f86/scratchpad/fix1`
  (GREEN copies, mutant script and log), which is mine and can be deleted.

## Next step

Review round 2 on the uncommitted diff (7 files). Read P6R1-1's pairing and anchor, and the P6R1-5 at-start decision
first.
