---
source: runner
scope: br-1115-issues
parent_session: ""
---
# Pass-Baton: phase 5 fix round 1 (issue 39): P5R1-4, -5, -1, -9 fixed

**Date:** 2026-11-17
**Scope:** br-1115-issues
**Branch:** feat/br-1115-issues/phase-5
**Worktree:** /home/alex/blast-off/.claude/worktrees/pending-items-53932d
**HEAD:** 35c07d3 chore(phase-5): review round 1 CLEAN; fix round started (changes uncommitted; the manager owns git)

## Where things stand

The four findings the manager named are fixed, test-first, under owner questions Q3 (no leading zero in any JOB_* number) and Q5 (a refusal never shows the child-count file's content).

Scenarios run, each alone, one at a time (never the full gate): 21-soft-cap, 60-preflight, 10-chain-done, 50-checkpoint-size, 70-docs, plus seven mutant runs. Last results, all on the final code:
- 21: `GATE-ONLY: PASS passed=1 failed=0 shellcheck=ok only=21-soft-cap`
- 60: `GATE-ONLY: PASS passed=1 failed=0 shellcheck=ok only=60-preflight`
- 10: `GATE-ONLY: PASS passed=1 failed=0 shellcheck=ok only=10-chain-done`
- 50: `GATE-ONLY: PASS passed=1 failed=0 shellcheck=ok only=50-checkpoint-size`
- 70: `GATE-ONLY: PASS passed=1 failed=0 shellcheck=ok only=70-docs`

`shellcheck -S warning` is clean on all six changed scripts.

`~/.config/systemd/user/blast-off@.service` read `ExecStart=/home/alex/blast-off/.worktrees/blast-off-build/bin/blast-off run %f` five times: before the first run, after the RED and GREEN runs of 10, after the last mutant run, and at the end. It never changed. Tests 11 and 31 were not run.

After every mutant, the file was restored from a copy of the GREEN version, and `cmp` confirmed it was identical. At the end, `cmp` confirmed both `lib/chain.sh` and `lib/preflight.sh` match that GREEN copy.

Blast radius: nothing passes a leading-zero JOB_* value. A grep of `bin lib tests templates docs README.md` for `JOB_[A-Z_]+[:=-]+0[0-9]+` found nothing. `chain_nums` is called only by `chain_run` and `preflight_run`. `chain_count` is called by `chain_run`, `unit_status` (`lib/units.sh:74`) and `preflight_run`. The old `holds '...'` text was asserted only in test 60 (p9), which is updated. Test 10's loop greps only the file path.

Files changed (tracked, 7):
- `lib/chain.sh`:
  - `chain_nums` regex is now `^(0|[1-9][0-9]{0,8})$`. On failure it sets `NUMS_ERR` and returns 1 instead of calling `die`. `chain_run` does `chain_nums || die "$NUMS_ERR"`, so stderr shows the same message as before, plus "with no leading zero".
  - `chain_count`: the shape refusal now reads `<file> is not '<launched> <base>' (<N> bytes; want two whole numbers of at most 9 digits, no leading zero, base <= launched; content not shown); fix it, or delete it ...`. The byte count comes from `stat -Lc %s`. The cannot-read branch now reads `cat ... 2>/dev/null` and says `cannot read <file> (a dangling link, a directory, or no read permission)`. It used to append `cat`'s combined stdout and stderr, which could carry partial content.
- `lib/preflight.sh`: `chain_nums || { echo "preflight: refused: $NUMS_ERR"; exit 1; }` runs before any other line, because no cap or "left" value can be derived from a bad count. The header comment is updated.
- `tests/21-soft-cap.sh`: the bad-number loop adds `JOB_MAX_CHILDREN=08`, `JOB_MAX_CHILDREN=010` and `JOB_CAP_FACTOR=03`. Each must exit 1 before any child with "is not a whole number".
- `tests/60-preflight.sh`:
  - New cases: soft running `4 2` (7 left under cap 9), and hard `5 5` at `running` and at `paused-cap` (7 left under cap 12, on a new `pfhard` job).
  - p9 asserts the new refusal text with `(2 bytes; `.
  - A two-line child-count (`1 0` then `2099-01-01T00:00:00Z job done`) is refused, and `job done` must not appear in the output.
  - `JOB_MAX_CHILDREN` `08` and `010` exit 1 with `preflight: refused: JOB_MAX_CHILDREN='<v>' is not a whole number`.
- `tests/10-chain-done.sh`: a new `badcount-forged` job uses the same two-line child-count. `run` must exit 1 before any child, and the refusal must be in run.log and in `blast-off status`. `job done` must appear in none of run.log, run stderr/stdout or status output.
- `tests/50-checkpoint-size.sh:37`: `grep -n 'child 2'` becomes `grep -n 'child 2 launched'`.
- `docs/spec.md`:
  - `JOB_MAX_CHILDREN` paragraph: a refusal names the file, its size and the expected shape, never its content (Q5).
  - Exit 1 row: a JOB_* count with a leading zero is refused (Q3).
  - Preflight row: a garbled child-count is refused by name only, and a bad JOB_* count is refused before any other line.
  - Test rows 10, 21, 50 and 60 are updated.
- `README.md`: unchanged. Line 60's list of preflight refusals was already partial (it never named a garbled child-count), and nothing in it became wrong.

## Evidence, per finding

### P5R1-4: leading-zero JOB_* numbers read as octal

RED (test 21, HEAD code):
```
FAIL 21-soft-cap
  | FAIL: JOB_MAX_CHILDREN=08 exit 0, want 1 before any child: 2026-11-18T04:01:33Z child cap 08 (hard: no Phase plan row the runner reads in checkpoint.md; done is refused (exit 10) until it has one)
GATE-ONLY: FAIL passed=0 failed=1 shellcheck=ok only=21-soft-cap
```
GREEN: `PASS 21-soft-cap` / `GATE-ONLY: PASS passed=1 failed=0 shellcheck=ok only=21-soft-cap`; `PASS 60-preflight`.

Mutant M1 (`chain_nums` regex back to `^[0-9]{1,9}$`), test 21:
```
FAIL 21-soft-cap
  | FAIL: JOB_MAX_CHILDREN=08 exit 0, want 1 before any child: 2026-11-18T04:04:39Z child cap 08 (hard: no Phase plan row the runner reads in checkpoint.md; done is refused (exit 10) until it has one)
restored: cmp lib/chain.sh identical
```
Mutant M1, test 60:
```
FAIL 60-preflight
  | FAIL: no line /^preflight: refused: JOB_MAX_CHILDREN='08' is not a whole number / in p13.out: job: /tmp/tmp.NJoBePQRws/cwd/test-615420-pf/job · workdir: /tmp/tmp.NJoBePQRws/cwd/test-615420-pf · unit: blast-off-test-615420-pf.service
restored: cmp lib/chain.sh identical
```
Mutant M1b (preflight `chain_nums || die "$NUMS_ERR"`, so no refused line), test 60:
```
FAIL 60-preflight
  | FAIL: no line /^preflight: refused: JOB_MAX_CHILDREN='08' is not a whole number / in p13.out: blast-off: JOB_MAX_CHILDREN='08' is not a whole number of at most 9 digits with no leading zero
restored: cmp lib/preflight.sh identical
```

### P5R1-5: the refusal copied child-count's content

RED (test 10, HEAD code):
```
FAIL 10-chain-done
  | FAIL: forged child-count: exit 1, want 1 before any child, refusal in run.log and status: 2026-11-18T04:02:05Z /tmp/tmp.40Wt15kIVk/cwd/test-593807-badcount-forged/job/child-count holds '1 0
GATE-ONLY: FAIL passed=0 failed=1 shellcheck=ok only=10-chain-done
```
RED (test 60, HEAD code; it fails first at p9, the text change):
```
FAIL 60-preflight
  | FAIL: no line /^child-count: /tmp/tmp.9ZFIjuQd4c/cwd/test-592669-pf/job/child-count is not '<launched> <base>' \(2 bytes; / in p9.out: job: /tmp/tmp.9ZFIjuQd4c/cwd/test-592669-pf/job · workdir: /
GATE-ONLY: FAIL passed=0 failed=1 shellcheck=ok only=60-preflight
```
GREEN: `PASS 10-chain-done`, `PASS 60-preflight`.

Mutant M2 (`content not shown)` -> `holds '$c')`, so the content is back in COUNT_ERR), test 10:
```
FAIL 10-chain-done
  | FAIL: child-count's content echoed: 2026-11-18T04:05:17Z /tmp/tmp.et3ZWguVQF/cwd/test-617889-badcount-forged/job/child-count is not '<launched> <base>' (34 bytes; want two whole numbers of at most 9 digits, no leading zero, base <= launched; holds '1 0
restored: cmp lib/chain.sh identical
```
Mutant M2, test 60:
```
FAIL 60-preflight
  | FAIL: preflight echoed child-count's content: job: /tmp/tmp.Bon3reUFR2/cwd/test-621292-pf/job · workdir: /tmp/tmp.Bon3reUFR2/cwd/test-621292-pf · unit: blast-off-test-621292-pf.service
restored: cmp lib/chain.sh identical
```

### P5R1-1: preflight's "left" was untested under the hard cap and with base > 0

The new assertions pass on HEAD code, because they guard existing behaviour. They are proven by the two named mutants.

Mutant M3 (`local b="$BASE";` -> `local b=0;`), test 60:
```
FAIL 60-preflight
  | FAIL: no line /^child-count: 4 launched, base 2; next child 5; 7 left under cap 9$/ in p11.out: job: /tmp/tmp.gRWfaMD0bM/cwd/test-622533-pf/job · workdir: /tmp/tmp.gRWfaMD0bM/cwd/test-622533-pf · unit: blast-off-test-622533-pf.service
restored: cmp lib/preflight.sh identical
```
Mutant M4 (`(CAP_SOFT ? b : 0)` -> `b`), test 60:
```
FAIL 60-preflight
  | FAIL: no line /^child-count: 5 launched, base 5; next child 6; 7 left under cap 12$/ in p12.out: job: /tmp/tmp.PV8V7tUVMh/cwd/test-623435-pfhard/job · workdir: /tmp/tmp.PV8V7tUVMh/cwd/test-623435-pfhard · unit: blast-off-test-623435-pfhard.service
restored: cmp lib/preflight.sh identical
```
GREEN: `PASS 60-preflight`.

### P5R1-9: test 50's `child 2` grep could match the child-count line

There is no code mutant, because this is a latent false failure in the test. A two-line run.log shows the difference: line 1 is `child-count: 1 launched, base 0; next child 2` and line 2 is `child 2 launched  window=x`. The old pattern picks line 1 and the new one picks line 2:
```
old: 1  new: 2
```
GREEN: `PASS 50-checkpoint-size` / `GATE-ONLY: PASS passed=1 failed=0 shellcheck=ok only=50-checkpoint-size`.

## Next steps

1. Manager: review the diff (`git diff` in the worktree), then commit with the regenerated ARCH.md if the hook stages it.
2. Review round 2 on the fix.

## Open questions / risks (not fixed; outside this round's list)

- A bad JOB_* count in `run` still goes to stderr only, through `die`, and not to run.log. Under `start` or the resume timer, only the journal shows it. P4R1-2 had routed the child-count refusal to run.log for this same reason.
- `chain_count` still reads child-count through any symlink with no size limit. A link to `/dev/zero`, `/dev/urandom` or a FIFO hangs the runner, `status` and `preflight`, or fills memory. Q5 removed the leak, but the unbounded read remains.
- The cannot-read refusal now lists the possible causes instead of quoting cat's own error, so the exact errno is lost. This trades precision for never mixing in partial content.
- `NUMS_ERR` still prints the JOB_* value as given, with no length limit or escaping. The value is the owner's own environment, not a file, so Q5 does not cover it.
- `stat -Lc %s` reports 0 for `/proc` and other special files, so the byte count can read `0 bytes` for a link that has content.
- In test 60 the `pfhard` preflight runs do not assert an exit code. They check only the child-count line.
- The forged and leading-zero preflight cases never got their own RED run on HEAD code, because test 60 fails first at p9. Mutants M1, M1b and M2 kill them instead.
- Tooling: the context-mode hook indexes any tool output over about 4 KB, so this session read files in small slices.

## References

- Review: `baton-runner/br-1115-issues/baton-phase-5-review-1.md`, `review-phase-5-iter-1.md`
- Code: `lib/chain.sh` (`chain_nums`, `chain_count`, `chain_run`), `lib/preflight.sh` (`preflight_run`)
- Tests: `tests/10-chain-done.sh`, `tests/21-soft-cap.sh`, `tests/50-checkpoint-size.sh`, `tests/60-preflight.sh`
