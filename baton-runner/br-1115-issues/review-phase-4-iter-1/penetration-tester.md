### Summary

Reviewed commit f388962 against base 7867255 (`git diff 7867255...f388962 -- . ':!baton-runner'`, 7 files) and issue 22. The work was static only: reading `lib/chain.sh`, `lib/child.sh`, `lib/units.sh`, `lib/preflight.sh`, `lib/checkpoint.sh`, `bin/blast-off`, the three test diffs, `docs/spec.md` and `README.md`, the work baton and `phase-4/findings.md`, plus read-only `gh issue view 22`. One in-memory bash probe tested the parse and the arithmetic. I ran no scenario and created no file other than this one.

**Threat model.** A child is a Claude session with the owner's uid and a shell. It can already delete `child-count`, rewrite `checkpoint.md`, or run `systemctl --user start` / `blast-off run` itself. So the cap is a **cost and runaway guardrail, not a trust boundary** against a hostile child. Severities below rank what an honest-but-confused child, or the owner, can trigger by accident. Deliberate tamper vectors are LOW because a child has easier ways to do the same thing.

The three acceptance criteria hold on the paths the tests exercise. The main gap is the `paused-cap -> running` branch (`lib/chain.sh:163`). It moves `base` regardless of who wrote `paused-cap` and regardless of whether the cap is soft. That makes the work baton's "the hard cap has no reset path" and `findings.md`'s "the hard cap counts every child of the job" false whenever `base` is nonzero. Other findings: an INT64_MAX value that the parse accepts disables the cap for one run; the file is read before the lock; and several filesystem-shape cases (symlink, directory, FIFO) are not covered.

Counts: CRITICAL 0, HIGH 0, MEDIUM 2, LOW 9.

### Findings

#### CRITICAL

None.

#### HIGH

None.

#### MEDIUM

- **Title:** PT-1. The `paused-cap -> running` branch resets `base` for a hard-cap job, so the hard cap has a reset path, and anything that writes `status: paused-cap` triggers it
- **Location:** `lib/chain.sh:162-164` (`paused-cap) BASE="$LAUNCHED"; chain_count_set`, not gated on `CAP_SOFT`, which `chain_cap` already set at `:151`); `lib/chain.sh:185` (exit 4 keeps the status); `lib/checkpoint.sh:5` (`cp_status` reads the first `status:` line, whoever wrote it); `lib/units.sh:56` (`resume` accepts any `paused-cap`); claims at `baton-phase-4-work.md` ("The hard cap has no reset path", "The hard cap is now final for a job") and `phase-4/findings.md` ("the hard cap counts every child of the job")
- **Description:** The runner only writes `paused-cap` on the soft-cap exit (`:186`). But at start, the branch at `:163` honours any `paused-cap`, whoever wrote it and whatever the cap kind. Hand-traced:
  1. A job with no Phase plan row the runner reads (hard cap, `MAXC=12`, `CAP_SOFT` empty).
  2. A child writes `status: paused-cap` into `checkpoint.md`. Mid-run nothing happens, because the loop only acts on `done`/`blocked` (`:179-182`).
  3. The run ends on exit 4 (`:185`), exit 5, exit 7, an abort, or a reboot. Exit 4 keeps the status by spec.
  4. The owner sees `paused-cap` in `blast-off status`, and README row 6 tells them `blast-off resume`. Or they just `run` again.
  5. `:163` sets `BASE=LAUNCHED`, and `:184`'s `n - BASE > MAXC` grants 12 more. Repeat for unbounded children.

  The same code also breaks the "hard cap counts every child" claim with no forged status at all. A job paused at its soft cap (say 9 children), then resumed (`BASE=9`), then loses its readable Phase plan rows (a child drops the table, or a line `cp_unread` refuses, `:178`). On the next relaunch `chain_cap` picks the hard cap, and it allows `9 + 12` in total, not 12. The spec text at `docs/spec.md:61` does say "the next child less `base`" for either cap, so the code matches the spec's formula. It contradicts the work unit's stated decision and acceptance criterion 1 ("cap reached across two runner runs stops the job (exit 4)"). No test covers a hard-cap job meeting `paused-cap`. Test 10 only ever has `BASE=0`.
- **Suggested fix:** Gate the reset and use `base` only on the soft path. Change `:163` to `paused-cap) [ -z "$CAP_SOFT" ] || { BASE="$LAUNCHED"; chain_count_set; }`. At `:184`, compare `used` instead of `n - BASE`, where `used=$n; [ -z "$CAP_SOFT" ] || used=$((n - BASE))`. Then the hard cap counts `launched` and nothing else. To stop a child-forged `paused-cap` from also resetting a soft cap, let the runner record its own pause, for example by writing `<launched> <base> paused` at `:186`, and honour the reset only when that marker is present. Add one test-10 case: a hard-cap job at cap with `status: paused-cap` exits 4 on re-run with no child. UNREPRODUCED. The dispatching unit can confirm it with a one-off probe on a `git archive` copy: in test 10's hard-cap block, after the cap-1 exit 4, run `sed -i 's/^status:.*/status: paused-cap/' "$JOB/checkpoint.md"`, then `JOB_MAX_CHILDREN=1 "$bo" run "$JOB"`. Expected today: child 2 launches. Expected after the fix: exit 4 with no child. Run it as `BLAST_OFF_TEST_ONLY=10-chain-done tests/run` on the copy.

- **Title:** PT-2. `9223372036854775807 0` passes the parse, `n=$((LAUNCHED+1))` wraps negative, and the cap never trips for the rest of that run
- **Location:** `lib/chain.sh:120` (regex `^(0|[1-9][0-9]*)\ (0|[1-9][0-9]*)$`, no digit bound), `:183-184`
- **Description:** In-memory probe (bash, no files): `L=9223372036854775807 B=0` passes the regex and `[ 0 -le L ]`. Then `n=$((L+1))` = `-9223372036854775808`, `n-B` is negative, and `-gt 12` is false, so the child launches. Each later child increments from INT64_MIN, so `n - BASE` stays negative for about 9.2e18 launches: no cap for the rest of that run. Child numbers in `run.log`, `JOB_CHILD` and the scope name `$UNIT-child-<negative>.scope` (`lib/child.sh:47`) are negative. The next `chain_count_set` writes `-9223372036854775808 0`, which the next start rejects (exit 1), so the damage is limited to one run. `99999999999999999999 0` (20 digits) fails closed, but only because `[` errors with `integer expression expected` and the `&&` chain turns that into the `die`. That is fail-closed by accident, with a raw bash error on stderr. Only a deliberate write reaches this, so it is MEDIUM as a parser correctness bug, LOW as a threat.
- **Suggested fix:** Bound the digits: `^(0|[1-9][0-9]{0,8})\ (0|[1-9][0-9]{0,8})$`. Nine digits is far above any real count and far below overflow. Add `'9223372036854775807 0'` and `'99999999999999999999 0'` to test 10's garbled list.

#### LOW

- **Title:** PT-3. A missing `child-count` is read as a fresh job (fail-open), including after an upgrade of an in-flight job and for a dangling symlink
- **Location:** `lib/chain.sh:118` (`[ -e "$f" ] || return 0`)
- **Description:** Deleting the file resets both the cap and the numbering. A dangling `child-count` symlink does the same, because `-e` follows the link (the work baton notes this). Three accidental routes:
  - A job already running when this commit lands has no file, so its first relaunch restarts at child 1 with a full cap. Issue 22's own 27->30 incident happens once more.
  - A child "tidying" the job dir removes an unknown file.
  - The owner reuses a job dir.

  Git is a weak route. README:38 has the job dir excluded via `info/exclude`, so `git clean -fd` without `-x` and `git stash -u` leave it alone, and `git clean -fdx` removes `checkpoint.md` too (then `die "missing checkpoint"`). The effect only appears after a relaunch: during a run the in-memory `LAUNCHED` rewrites the file before every launch (`:194`). `run.log` still holds `child N launched` lines, so the history the runner would need is on disk.
- **Suggested fix:** When the file is missing (`[ -e "$f" ] || [ -L "$f" ]` false) but `run.log` has a `child [0-9]* launched` line, either die with "child-count missing but run.log shows N children; write '<N> 0' or delete run.log to start fresh", or recover `LAUNCHED` from the highest launched number in `run.log`. Treat a dangling symlink (`-L` true, `-e` false) as garbled.

- **Title:** PT-4. A FIFO, device, or huge file at `child-count` hangs or exhausts the runner before the lock; the content is echoed unbounded into the `die` message
- **Location:** `lib/chain.sh:118-121`
- **Description:** `[ -e ]` accepts any file type. `child-count -> /dev/zero` makes `$(cat)` grow until out of memory. A FIFO makes `cat` block forever, before `chain_lock` and the trap, so the unit sits active and `status` shows the job running. A large regular file is read whole into `c` and then printed whole in the `die` text. This needs a deliberate plant. UNREPRODUCED (creating a FIFO or symlink is outside this review's rules). Probe for the dispatching unit, on a `git archive` copy: `new_job x step; mkfifo "$JOB/child-count"; timeout 10 "$bo" run "$JOB"; echo rc=$?`. Expected today: rc=124 (hung).
- **Suggested fix:** `[ -f "$f" ] || die "$f is not a regular file"`, and read a bounded prefix: `c="$(head -c 64 "$f")"`.

- **Title:** PT-5. The `die` message prints raw file content: control bytes and escape sequences reach the terminal or journal
- **Location:** `lib/chain.sh:121`, `bin/blast-off:48`
- **Description:** `die "$f holds '$c', ..."` prints the content as-is to stderr. An ESC sequence in the file is interpreted by the owner's terminal under a foreground `run`. Under the unit it goes to the journal, where `journalctl` shows non-printable lines as a blob unless `--all`. It does not reach `run.log`, because `die` is not `log` and runs before the trap. Low impact, because a child can already write to `run.log` directly.
- **Suggested fix:** Print it escaped: `$(printf %q "$c")`, or with PT-4's bounded read, `${c//[^0-9 ]/?}`.

- **Title:** PT-6. A planted `child-count.tmp` symlink makes the runner write through it; a `child-count` directory silently stops persistence for the run
- **Location:** `lib/chain.sh:125` (`echo ... > "$JOB/child-count.tmp" && mv -f ... "$JOB/child-count"`)
- **Description:** From the semantics of `>` and `mv`, not run:
  - **`child-count.tmp` -> any file the uid can write.** `echo` follows the link and overwrites the target with `<launched> <base>`. `mv` then renames the link itself to `child-count`, so `child-count` is now a symlink to that file. Same-uid only, so no privilege gain, but the runner clobbers a file outside the job dir.
  - **`child-count.tmp` as a directory.** The redirect fails, the function returns 1, and `set -e` aborts the runner (exit 1, "runner exit 1 without a state"). This fails closed: `chain_run` is called bare at `bin/blast-off:65`, so errexit is live.
  - **`child-count` as a directory (or a symlink to one).** `mv -f tmp dir` moves the temp file into the directory and returns 0. Nothing is persisted for the rest of the run, but the in-memory cap still holds. The next start fails closed at `cat` (`die "cannot read"`).

  UNREPRODUCED. Probes for the dispatching unit, each on a `git archive` copy with a scratch target:
  - `ln -s "$scratch/victim" "$JOB/child-count.tmp"; JOB_MAX_CHILDREN=1 "$bo" run "$JOB"; cat "$scratch/victim"`. Expected: `1 0`.
  - `mkdir "$JOB/child-count"; ...`. Expected: `$JOB/child-count/child-count.tmp` exists after child 1.
- **Suggested fix:** `rm -f "$JOB/child-count.tmp"` before the write, or use `mktemp "$JOB/child-count.XXXXXX"`. Use `mv -fT` so a directory target fails instead of swallowing the file.

- **Title:** PT-7. `chain_count` reads the file before `chain_lock`; a runner that takes the lock a moment later can act on a stale count. Two runners on one job dir lose updates
- **Location:** `lib/chain.sh:135` (`chain_count`) vs `:144` (`chain_lock`); `:30` (the existing ponytail: non-atomic stale-lock takeover); `bin/blast-off:57-58` (`UNIT` comes from the workdir name, `child-count` from the job dir)
- **Description:** These are lost-update races on a file with no lock:
  - **Stale count.** If the live runner A writes `LAUNCHED=n` and then exits (for example `blast-off stop` lands right after `:194`) between B's `chain_count` and B's `chain_lock`, B gets the lock with the old count. B relaunches the same number `n` and writes `n` back, so one child goes uncounted. The window is microseconds.
  - **Stale lock.** The documented race where two runners both take over one stale lock now also means both read the same `LAUNCHED` and share one `child-count.tmp` name. Up to double the cap is reachable, or one `mv` fails and aborts.
  - **Two workdirs.** The same job dir run with two different workdirs (`run <job> <wd>`) gets two units and two locks, so two runners count into one file. That is pre-existing misuse, but the shared counter now loses updates.

  The work baton's reason for the read point is that a bad file should give a clean `die`, not a logged abort. That still holds if the read moves after the lock: `die` after `chain_lock` but before `trap ... EXIT` leaves the lock file behind, so the read would need to go after the trap, or the `die` would have to release the lock.
- **Suggested fix:** Call `chain_count` after `trap 'chain_exit $?' EXIT` (`:145`). A garbled file then shows as `runner exit 1 without a state` in `run.log`, which is arguably better for an unattended unit (see PT-9). Alternatively, call it right after `chain_lock` and `rm -f "$LOCK"` before that one `die`.

- **Title:** PT-8. The "rename, so a reboot mid-write leaves one or the other" claim needs an fsync to be true on every filesystem
- **Location:** `lib/chain.sh:124-125`
- **Description:** With no `sync`, a power loss after the rename can leave a zero-length `child-count` on filesystems without ext4's `auto_da_alloc` rename heuristic (xfs, btrfs in some modes). The result fails closed: an empty value is garbled, exit 1, and the owner fixes it by hand. So the effect is an owner action after a crash, not a cap bypass. The comment overstates the guarantee.
- **Suggested fix:** `sync "$JOB/child-count.tmp"` (coreutils `sync FILE` fsyncs that file) before the `mv`, or reword the comment to "a garbled file after a crash fails closed".

- **Title:** PT-9. `preflight` and `status` neither validate nor show `child-count`: preflight passes, then the unit dies at once
- **Location:** `lib/preflight.sh:12,25-26` (`chain_nums`, `chain_cap`, no `chain_count`); `lib/units.sh:70` (`unit_status`)
- **Description:** If the file is garbled, `preflight` prints `preflight: ok` and `start` launches a unit that exits 1 at once. The reason goes only to the journal: `die` writes to stderr, and nothing reaches `run.log` (see PT-7). A job already at its hard cap also gets `preflight: ok` and a `cap: 12` line, then exits 4 with no child. A job at its soft cap pauses with exit 6, then needs a second start (owner question P4-22b). The work baton lists this as out of scope. It is noted here because an unattended start fails with no trace in the job dir.
- **Suggested fix:** Run `chain_count` in preflight. It only reads, and its `die` is the correct refusal. Print `children: <launched> launched, <MAXC - (launched - base)> left`.

- **Title:** PT-10. `cp_set_status` and `cp_status` take the first `status:` line anywhere in `checkpoint.md`, so the forged status in PT-1 does not even need to replace the real one
- **Location:** `lib/checkpoint.sh:5,118`
- **Description:** Not new in this commit. It widens PT-1: a `status: paused-cap` line placed above the real one (for example in a note block a child adds near the top) is what `cp_status` reads. Mentioned for completeness. The fix belongs to PT-1's runner-owned pause marker, not to the parser.
- **Suggested fix:** None beyond PT-1.

- **Title:** PT-11. No test pins acceptance criterion 3 ("a fresh job starts at 1") against a regression to a leftover file, and none covers the hard-cap/`paused-cap` interaction
- **Location:** `tests/10-chain-done.sh` (new blocks), `tests/21-soft-cap.sh`
- **Description:** Criterion 3 rests on existing `child 1 launched` assertions (the work baton says so). No new test asserts that `child-count` is absent before the first run and reads `1 0` after it. No test reaches `paused-cap` with `CAP_SOFT` empty (PT-1), an INT64 boundary value (PT-2), or a missing file with `run.log` history (PT-3).
- **Suggested fix:** Add `[ "$(cat "$JOB/child-count")" = "1 0" ]` after test 10's first hard-cap run, plus the cases named in PT-1, PT-2 and PT-3.

### Validated

- **Criterion 1 (exit 4 across runs).** True when `base` is 0. The test-10 re-run at cap 1 exits 4 with no launch, and a re-run at cap 2 launches child 2 only. Fails when `base` is nonzero (PT-1).
- **Criterion 2 (numbering continues).** `n=$((LAUNCHED+1))` and `log "child $n launched"` use the same `n`. Scope names `$UNIT-child-$n.scope` (`lib/child.sh:47`) are now unique across runs, and `child_stop_all` stops them by glob (`lib/child.sh:30`), so continued numbers do not escape cleanup. `child_report`'s `sed "/^child $1 session=/..."` (`lib/child.sh:122`) no longer matches an earlier run's child 1 block, which is a small fix as a side effect.
- **Criterion 3 (fresh job starts at 1).** No file gives `0 0`, so the first child is 1 (PT-3 and PT-11 cover the edges).
- **Save before launch** (`:194`, before `child_launch` at `:195`): a child cut off by a reboot or SIGHUP counts (test 10's hup2 block). A cap exit writes nothing.
- **Garbled values fail closed with exit 1:** empty, `x`, a single number, a leading zero (which also avoids octal `$(( ))` errors), negative, `base > launched`, CRLF (`\r` makes the regex fail), multiple lines (bash `=~` uses POSIX ERE without `REG_NEWLINE`, so `$` is end of string; probe: `$'5 0\n3 0'` rejected), and leading, trailing or doubled whitespace. Trailing newlines are stripped by `$(...)` and accepted, which is correct. A 20-digit value is rejected, but only through a `[` error (PT-2).
- **`set -e` coverage:** `chain_run` is called bare (`bin/blast-off:65`), and both `chain_count_set` calls (`:163`, `:194`) are plain commands, so a failed write aborts before any launch. `c="$(cat "$f")" || die` is not masked, because `local c` is declared on a separate line (`:116`).
- **Idempotent `paused-cap` reset:** `BASE` is saved before `cp_set_status running`. A crash in between leaves `paused-cap`, and the re-run sets the same `BASE` again. An exit 7 at `chain_dirty "before child 1"` (`:172`) after the reset does not reset twice, because the status is already `running`.
- **No auto-relaunch:** the unit has no `Restart=` (`docs/spec.md:151`, README:144), and the resume timer is armed only by `usage_pause`. So every relaunch that crosses the cap is a start by the owner, the timer, or a child, never systemd.
- **Blast radius:**
  - `unit_stop` and `unit_resume` do not touch the file. `resume`'s `paused-cap` path goes through PT-1.
  - `lib/units.sh` `unit_start` only passes `run "$JOB"`.
  - `preflight` does not read the file (PT-9).
  - Test 11's `rm -f "$JOB/child-count"` is a fixture reset like its neighbours.
  - Test 40's edits are comments only.
  - Test 21's new `relaunch` job covers the issue's 27->30 case for the soft cap.
- **Dirty-tree check:** `child-count` and `child-count.tmp` are under the job dir, which `chain_dirty` skips by `JOBREL` prefix (`:66`) and which README:38 excludes from git.
- **Owner question P4-22a** (the soft cap resets on `paused-cap` resume): from a security view, the soft reset needs an owner start (`resume` or `run`), so it is an allotment by design, not a bypass, provided PT-1's gate and marker hold. With Phase plan rows, `JOB_MAX_CHILDREN` stays soft (`chain_cap:103`), so it is per-allotment, not per-job. The owner should decide whether that is what "per-job" in the issue meant.
- **Owner question P4-22b** (two starts after adding a Phase plan): confirmed from the code: `n - 0 > MAXC` with `CAP_SOFT` set gives exit 6 with no child, and a second start moves `base`.

### Confidence

- **High** on PT-1's code path. It is a direct read of `:151`, `:162-164`, `:184-185` and `cp_status`, and the only unrun step is the end-to-end probe given.
- **High** on PT-2. The bash arithmetic was probed in memory: `n=-9223372036854775808` and `n-B` negative for `9223372036854775807 0`.
- **High** on the parsing table in Validated (probed).
- **Medium** on PT-4 and PT-6. They follow from the semantics of `cat`, `>` and `mv`, but are unrun because creating FIFOs and symlinks is outside this review's rules.
- **Medium** on PT-7's window size and on PT-8's filesystem behaviour.
- The MEDIUM, not HIGH, rating rests on the threat model: children share the owner's uid and can already delete the file or start units, so the cap guards against runaway cost, not against an attacker.
