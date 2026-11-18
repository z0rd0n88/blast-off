### Summary

I reviewed commit dcee737 (9 files against main c4e2a41, `baton-runner/` excluded) as the tests reviewer. The questions: are the new assertions real, what does each bind, and which mutants survive. I did static work only. I ran no scenario, no `tests/run`, no `scripts/gate.sh` and no `bin/blast-off`. My only probes were `bash -c` one-liners that print to stdout (arithmetic and regex checks).

Every issue 39 item has a real assertion behind it, except the "capped job passes preflight" half of P4R1-3, which the work unit left as an owner call. Two of phase 4's surviving mutants are now dead:
- `-le` to `-lt` on `base <= launched` dies at `tests/21-soft-cap.sh:49-52`, because the `2 2` job reads `k k`.
- `[ -e ]` to `[ -s ]` dies at `tests/10-chain-done.sh:115-117`.

The new preflight `left` arithmetic matches `chain_run`'s cap test in every case the brief lists (worked through below). The tests pin only three of its inputs, though. I found no CRITICAL and no HIGH. Two MEDIUM items:
1. A job at its cap still gets `preflight: ok`. That is half of P4R1-3, and test 60 now pins the pass.
2. Preflight's `left` is unpinned for `base` > 0 and for the hard cap. Two one-token mutants survive.

The rest is LOW: one new preflight crash on a leading-zero `JOB_MAX_CHILDREN`, more surviving mutants (each with its exact edit), refusal-before-lock effects, and doc wording.

Blast radius of the new run.log line: no scenario matches `child-count: ...; next child N` or `first child 1` by accident today. Every count grep is `child [0-9]* launched` or `child N launched`. `child.sh:123`'s `sed -n "/^child $1 session=/` is anchored, and run.log lines start with a timestamp. Test 30's `logt` uses `child 2 launched`. Only `tests/50-checkpoint-size.sh:37` (`grep -n 'child 2' | head -n 1`) could hit the new line, and only on a non-fresh job. It would fail loudly, not pass vacuously (LOW below). No status check is positional, so the new status line between `ActiveState` and `resume timer` breaks nothing (tests 11 and 30).

Preflight `left` = `MAXC - LAUNCHED + (CAP_SOFT ? b : 0)`, where b is `LAUNCHED` for a soft `paused-cap`, else `BASE`. `chain_run` launches children `L+1 .. MAXC+B'`, where B' is `BASE` moved to `L` for a soft `paused-cap` and is 0 under the hard cap. That is `MAXC + B' - L`, the same number. Case by case:
- Soft `paused-cap`: MAXC.
- Hard cap at `5 5`, cap M: M-5, as `tests/10-chain-done.sh:119-121` expects at M=1 (clamped to 0).
- Hard cap at `paused-cap`: `BASE` is ignored, so no fresh allotment. This matches P4R2-4 and P4-22a.
- `JOB_MAX_CHILDREN=0`: soft gives 0, and so does soft `paused-cap` (`0 - L + L`). Hard gives 0. The run pauses or exits 4 at once.
- done, blocked, or paused-limit before its reset: the run launches nothing, but preflight still prints the cap-based number (LOW below).

### Findings

#### CRITICAL

None.

#### HIGH

None.

#### MEDIUM

- **A job at its cap still passes preflight (half of P4R1-3 not done), and test 60 now pins the pass**
  - **Location:** `lib/preflight.sh:30-33`; `tests/60-preflight.sh:112-115`; issue 39 checkbox P4R1-3; decision at `phase-5/findings.md:13`
  - **Failure path:** a hard-cap job (no Phase plan) at `12 0` with the default cap gets `child-count: 12 launched, base 0; next child 13; 0 left under cap 12` and `preflight: ok` (exit 0). `start` then exits 4 before any child. That is the exact case the P4R1-3 row describes ("a job already at its cap, passes preflight and then exits at once"). A soft job at `n - BASE == MAXC` likewise passes, then exits 6.
  - **Evidence:** test 60 p7 asserts `rc -eq 0` for `9 0` at cap 9 (`tests/60-preflight.sh:114`). The decision to show `0 left` without refusing is the work unit's own (an "owner call", `baton-phase-5-work.md:58,99`). The issue checkbox wording covers both halves.
  - **Suggested fix:** owner ruling. Either refuse on `0 left` under the hard cap only, since that one never recovers without a larger `JOB_MAX_CHILDREN` or a deleted `child-count`; the soft one recovers through `resume`. Or record that P4R1-3 is closed as display-only and tick the box with that note.

- **Preflight's `left` is unpinned for `base` > 0 and for the hard cap: two one-token mutants survive**
  - **Location:** `lib/preflight.sh:31-32`; `tests/60-preflight.sh:57,112-119`
  - **Failure path:** test 60's job is soft (cap 9) and every case has `base` 0: `none`, `9 0`, and `9 0` at `paused-cap`. Neither of these is ever exercised:
    1. A soft job running from `L B` with B > 0, which P4R2-1 says follows any resumed run that ended on exit 5, 7 or 8, a `stop`, or a reboot.
    2. A hard-cap preflight.
  - **Evidence, surviving mutants:**
    - **SP1** `lib/preflight.sh:31`: `local b="$BASE"` becomes `local b=0`. p1 and p7 have B=0, and p8 takes the paused-cap branch (`b="$LAUNCHED"`). A soft running `9 9` at cap 9 would print `0 left`, not `9 left`. That is the preflight twin of P4R2-1.
    - **SP2** `lib/preflight.sh:32`: `(CAP_SOFT ? b : 0)` becomes `b`. With no hard-cap preflight case, a hard job at `5 5` with `JOB_MAX_CHILDREN=6` would print `6 left`, not `1 left`. Under the hard cap, `run` exits 4 after one child. The display is exactly the "hard cap never resets" property P4-22a protects.
    - Equivalent, not a gap: dropping `[ -z "$CAP_SOFT" ] ||` on line 31 alone has no effect, because line 32 multiplies `b` by `CAP_SOFT`. It becomes live together with SP2.
  - **Suggested fix:** two more cases in the test 60 tail:
    1. `printf '9 3\n'` with status `running`: expect `next child 10; 3 left under cap 9`. This kills SP1.
    2. A copy of the job with the Phase plan stripped, `printf '5 5\n'` and `JOB_MAX_CHILDREN=6`: expect `1 left under cap 6`. Add `status: paused-cap` and expect `1 left` still. This kills SP2, and the dropped `[ -z "$CAP_SOFT" ] ||` with it.

#### LOW

- **New: preflight aborts on a leading-zero `JOB_MAX_CHILDREN` that `run` accepts**
  - **Location:** `lib/preflight.sh:32` (new arithmetic); `lib/chain.sh:91` (`^[0-9]{1,9}$` accepts `08`); `lib/chain.sh:105,109` (MAXC copied as text)
  - **Failure path:** with `JOB_MAX_CHILDREN=08`, `chain_nums` passes and `chain_cap` sets `MAXC=08`. `run` works, because its test is `[ ... -gt "08" ]`, which reads decimal 8. Preflight now evaluates `$((MAXC - ...))` and bash aborts: `08: value too great for base`, exit 1. Preflight prints no `preflight: refused` line and none of the lines after `cap:`, which breaks "every line still printed". With `010`, preflight counts 8 (octal) while `run` uses 10, so `left` is off by 2. Before this commit, preflight never did arithmetic on `MAXC` and printed `cap: 08`.
  - **Evidence:** `bash -c 'f(){ if true; then local left=$((08 - 0)); echo in; fi; }; f; echo after'` prints the base error, no `in`, no `after`, rc 1. `[[ 08 =~ ^[0-9]{1,9}$ ]]` is true.
  - **Suggested fix:** `chain_nums` regex `^(0|[1-9][0-9]{0,8})$`, the same shape as `chain_count`'s. That also closes the noted `JOB_CAP_FACTOR=08` octal case (`baton-phase-5-work.md:60`). Add `JOB_MAX_CHILDREN=08` to test 21's bad loop.

- **`status`'s garbled branch is untested (surviving mutant)**
  - **Location:** `lib/units.sh:74`; `tests/11-unit-smoke.sh:42`
  - **Failure path:** **SU1**: `if chain_count; then echo "$COUNT_SAY"; else echo "child-count: $COUNT_ERR"; fi` becomes `chain_count; echo "$COUNT_SAY"`. Under `set -e`, `status` then exits 1 on a garbled file, before the `resume timer` and `no resume timer` lines. The spec row promises "or why the file is garbled". No test runs `status` on a garbled file, or on a fresh job (`none`).
  - **Suggested fix:** in test 30 or 11, `printf 'x\n' > child-count`, then expect `status` to exit 0 with `^child-count: .*holds 'x'` and the `resume timer:` line still printed.

- **Preflight's clamp at 0 is untested (surviving mutant)**
  - **Location:** `lib/preflight.sh:33`; `tests/60-preflight.sh:112-115`
  - **Failure path:** **SP3**: `$((left > 0 ? left : 0))` becomes `$left`. p7 lands on exactly 0. A count above the cap, which a lowered `JOB_MAX_CHILDREN` or a hard job at `5 5` with cap 1 produces, would print `-1 left` or `-4 left`.
  - **Suggested fix:** `printf '10 0\n'` at cap 9: expect `0 left under cap 9`.

- **The refusal's stderr half is unpinned (surviving mutant)**
  - **Location:** `lib/chain.sh:142`; `tests/10-chain-done.sh:103-107,111-112`
  - **Failure path:** **SC1**: `log "$COUNT_ERR" >&2` becomes `log "$COUNT_ERR"`. Every run in the garbled loop captures `> badcount.out 2>&1`, so stdout and stderr are indistinguishable. The spec says "in `run.log` and on stderr". Under the unit both streams reach the journal, so the practical impact is small.
  - **Suggested fix:** one case with `2> err.out > /dev/null`, then grep the path in `err.out`.

- **The dangling-link reason (cat's error) is unpinned (surviving mutant)**
  - **Location:** `lib/chain.sh:123`; `tests/10-chain-done.sh:112`
  - **Failure path:** **SC2**: `c="$(cat "$f" 2>&1)"` becomes `c="$(cat "$f")"`. `COUNT_ERR` then reads `cannot read <f>: ` with no reason, and cat's message goes to bare stderr only. The test greps only the path, so the mutant survives.
  - **Suggested fix:** grep `cannot read $JOB/child-count: .*No such file` in run.log.

- **`chain_nums`' 9-digit accept boundary is untested (surviving mutant)**
  - **Location:** `lib/chain.sh:91`; `tests/21-soft-cap.sh:86`
  - **Failure path:** **SN1**: `{1,9}` becomes `{1,8}`. Only the reject side (20 digits, 10 digits) is tested, so a 9-digit value the spec allows would be refused, and no test notices. `{1,10}` and wider are killed by `JOB_CAP_FACTOR=1000000000`.
  - **Suggested fix:** a positive case, e.g. `JOB_CHILD_TIMEOUT=999999999` on a `done` job: expect it to reach a child.

- **The save moved to between `child_launch` and `child_wait` still survives (acknowledged)**
  - **Location:** `lib/chain.sh:204-205`; `tests/10-chain-done.sh:158-166`
  - **Failure path:** **ST1**: `LAUNCHED="$n"; chain_count_set` followed by `child_launch "$n"` becomes `LAUNCHED="$n"`, then `child_launch "$n"; chain_count_set`. The kill test waits for `^grandchild=` before it reads `1 0`, so the save has always happened by then. A reboot inside `child_launch` (tmux, systemd-run, the trust scrape over `BLAST_OFF_TRUST_SECONDS`, up to 60 s) loses the count. That window is wider than the work note's "cannot be hit" suggests.
  - **Suggested fix:** a fake child mode that writes `child-count`'s content into fake-marker at its first line, before anything else. Then assert `1 0` from inside the child.

- **The kill test's comment claims a cleanup it does not assert**
  - **Location:** `tests/10-chain-done.sh:156-166`
  - **Failure path:** the comment says the re-run "clears what the dead runner left", but no check follows. The SIGHUP case above it checks `! kill -0 $hung`, `! kill -0 $gc`, `tmux has-session` and `gone_dirs`. After SIGKILL the hang child, its grandchild, the tmux server and the child dir outlive the runner until the re-run's `child_server`/`chain_exit`. A regression there would leave a hanging fake child behind the scenario.
  - **Suggested fix:** capture `hung` and `gc` as the hup case does, then after the re-run add `wait_until 5 eval "! kill -0 $hung && ! kill -0 $gc"`, `! tmux -L "$TEST_ID-kill" has-session` and `gone_dirs kill`.

- **The refusal is logged before the lock and before the EXIT trap**
  - **Location:** `lib/chain.sh:142` vs `:151-152`
  - **Failure path:**
    1. A second runner beside a live one (the resume timer firing during an owner's foreground run, or a stray `start`) that meets a garbled file appends a refusal to the live job's run.log, then exits 1. The owner reads "the last run.log line" (README exit-1 row) and sees a refusal while the job is in fact running. The live runner's next `chain_count_set` rewrites the file.
    2. Without the trap there is no `runner exit 1 ...` line. That is consistent with the other pre-lock refusals, which go to stderr only.
    3. On stderr the line carries a timestamp and no `blast-off:` prefix, unlike `die`.
    4. Pre-existing: the count is read before the lock, so a runner that took over just after another runner's last save would start from a stale `LAUNCHED`. The window is tiny.
  - `LOG` is always set, since `job_init` runs first. A missing job dir dies in `job_init`. An unwritable run.log makes `tee` fail, so `log` returns 1 under `set -e` inside the `||` group, and the run still exits 1.
  - **Suggested fix:** none required. Optionally move `chain_count` after `chain_lock` and the trap, using `chain_end 1 "$COUNT_ERR"`. The refusal is then lock-serialised and read under the lock.

- **The run.log count line shows the pre-resume `base` on a soft paused-cap resume**
  - **Location:** `lib/chain.sh:160` vs `:171`
  - **Failure path:** a resume from `2 0` logs `child-count: 2 launched, base 0; next child 3`, then `status paused-cap -> running`. The run actually uses base 2, and no line records the moved base. The P4R1-5 aim, making the count a run starts from visible, is half met for this case. Test 21 does not look at the line.
  - **Suggested fix:** append `; base -> $LAUNCHED (fresh allotment)` to the `status paused-cap -> running` log line under the soft cap.

- **Preflight's `left`, and the spec's "what the next run may launch", are wrong for done, blocked and paused-limit jobs**
  - **Location:** `lib/preflight.sh:33`; `docs/spec.md` preflight row
  - **Failure path:** a `done` job at `3 0` under cap 9 prints `6 left`, but `run` exits 0 before the cap test. The same goes for `blocked` (exit 3) and for `paused-limit` before its reset (exit 8). This is display only.
  - **Suggested fix:** reword the spec to "under the cap". Or print `0 left (status done)` when the status is not `running` or `paused-cap`.

- **Spec wording for test 21's bad factor reads as the value 10**
  - **Location:** `docs/spec.md:229` (`a JOB_CAP_FACTOR of 10 (past 9 digits, P4R2-9)`)
  - **Failure path:** the test uses `JOB_CAP_FACTOR=1000000000`, which is 10 digits. The value 10 is valid.
  - **Suggested fix:** "a `JOB_CAP_FACTOR` of 10 digits".

- **`bin/blast-off` help header does not name the child count**
  - **Location:** `bin/blast-off:9,12`
  - **Failure path:** README lines 56 and 86 now list "child count" for `preflight` and `status`. The `--help` text, which test 70 reads for exit codes, lists neither. This is doc drift, possibly folded into the out-of-scope P4R1-26.
  - **Suggested fix:** add "child count" to both usage lines.

- **Test 50's positional `child 2` grep is fragile against the new line**
  - **Location:** `tests/50-checkpoint-size.sh:37`
  - **Failure path:** `grep -n 'child 2' run.log | head -n 1` takes the first line containing `child 2`. On a job whose run.log has `child-count: 1 launched, base 0; next child 2`, that line would be picked. It is logged before the warning, so the test would fail. Today test 50 runs only fresh jobs, whose line is `first child 1`.
  - **Suggested fix:** `grep -n 'child 2 launched'`.

- **Test 60's p8 does not check the exit code**
  - **Location:** `tests/60-preflight.sh:118`
  - **Failure path:** `rc` is captured but not asserted, so a refusal at a soft `paused-cap`, which `run` would not refuse, would pass the scenario.
  - **Suggested fix:** `[ "$rc" -eq 0 ] || fail ...`, as p7 does.

- **A FIFO `child-count` now hangs `status` and `preflight`**
  - **Location:** `lib/chain.sh:122-123`, called from `lib/units.sh:74` and `lib/preflight.sh:30`
  - **Failure path:** `[ -e fifo ]` is true and `cat` blocks with no writer. `run` already had this hang before this commit; `status` and `preflight` are new exposures, and they are the owner's diagnostics.
  - **Suggested fix:** `[ -f "$f" ] || [ ! -e "$f" ]` as a guard. Treat a non-regular file as garbled (`not a regular file`).

### Issue 39 checklist

| Item | Done? | Pinning test (file:line) | Notes |
|---|---|---|---|
| P4R2-1 base read back | Yes | `tests/21-soft-cap.sh:45-52` (`2 2` running, cap 2: children 3 and 4, `4 2`) | Kills MA (`BASE=0`) and `-le`→`-lt`. `BASE=$LAUNCHED` on read is killed by `21:56-61` (relaunch from `2 0`). Preflight's twin is unpinned (SP1, MEDIUM). |
| P4R2-2 in-memory BASE at resume | Yes | `tests/21-soft-cap.sh:33,37-43` (re-seed `2 0`) | Kills MB. The file-only save is still killed by `21:29-31`. P4R2-3 (the resume grep satisfied by the cap-0 run) is still open, out of scope. |
| P4R1-2 refusal in run.log | Yes | `tests/10-chain-done.sh:107,112` | Binds the path in run.log. Stderr unpinned (SC1); cat's reason unpinned (SC2). Logged before the lock (LOW). |
| P4R1-3 preflight/status show child-count | Partly | `tests/60-preflight.sh:57,115,119,123-125`; `tests/11-unit-smoke.sh:42` | Garbled refuses. A capped job still passes (MEDIUM). `left` unpinned for B>0 and hard (SP1, SP2), clamp unpinned (SP3), status garbled branch unpinned (SU1). |
| P4R1-4 / P4-22b README exit-4 remedy | Yes (docs) | none (doc-only, as asked) | `README.md:136` says the start can pause at `paused-cap` and `resume` follows. Accurate to `chain.sh:171,194`. |
| P4R1-5 missing/dangling child-count; count logged | Yes | `tests/10-chain-done.sh:76,85,110-113` | Missing stays fresh, per P4R2-11; dangling is garbled. The resume line shows the old base (LOW). |
| P4R1-7 save before launch on no-trap deaths | Yes | `tests/10-chain-done.sh:158-166` | Kills MT and MT2. ST1 (save between launch and wait) survives (LOW). The cleanup claim is unasserted (LOW). |
| P4R2-9 chain_nums digit bound | Yes | `tests/21-soft-cap.sh:86` | The reject side is pinned. `{1,8}` survives (SN1). Leading zeros now crash preflight (LOW, new). |
| P4R2-10 start_hang pid guard | Yes | `tests/11-unit-smoke.sh:63` | Kills MG. |
| Ruling P4R2-4 docs | Yes | `tests/10-chain-done.sh:97` (`status: running` after exit 4 from paused-cap) | Spec exit-4 column, `chain.sh:98-99` and test 21 header reworded. The assertion documents existing behaviour, so it passes on old code by design. |
| Ruling P4R2-11 docs | Yes | none (docs) | Spec JOB_MAX_CHILDREN text, README exit-4 row, `chain.sh:116,193`. |
| Ruling P4-22a (context) | Unchanged | `tests/10-chain-done.sh:93-96`, `:119-121` | Preflight mirrors it (soft paused-cap gets a fresh allotment, hard does not), but hard is unpinned (SP2). |

### Open questions for the owner

- P4R1-3: should preflight refuse a hard-cap job with `0 left`, which always exits 4 at start? And a soft one, which exits 6 and then resumes? Or is display-only the intended close?
- Should `chain_nums` reject leading zeros (`^(0|[1-9][0-9]{0,8})$`), as `chain_count` already does? This closes both the new preflight crash and the old octal `JOB_CAP_FACTOR` note.
