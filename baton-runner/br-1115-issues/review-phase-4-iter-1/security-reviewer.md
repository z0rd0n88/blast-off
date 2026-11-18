### Summary

I reviewed commit f388962 against base 7867255 (`git diff 7867255...f388962 -- . ':!baton-runner'`, 7 files) and issue 22. The review was static only. I fully read `lib/chain.sh` and the relevant parts of `lib/units.sh`, `lib/usage.sh`, `lib/checkpoint.sh`, `bin/blast-off`, `systemd/blast-off@.service`, the README threat-model paragraph, the work baton and `phase-4/findings.md`. I also ran read-only `git`/`gh` and one self-contained bash probe of the new regex and arithmetic, which printed to stdout and wrote nothing. I ran no scenario, `tests/run`, gate or `blast-off`.

All three acceptance criteria are met and asserted. Each baton decision is implemented as described. The core mechanism is sound:
- the rename is atomic within one directory;
- a failed write aborts under `set -e` before the child launches;
- a garbled file exits 1 before the lock, and the file is left unchanged;
- a child's mid-run edit of `child-count` is overwritten by the runner's in-memory count before the next launch;
- the dirty-tree check skips the file.

No CRITICAL or HIGH finding. Two MEDIUM:
- **M1:** the `paused-cap -> running` base reset is not gated on the soft cap. A hard-capped job whose checkpoint reads `paused-cap` gets a fresh `JOB_MAX_CHILDREN` on re-run, which contradicts spec row 4 and the baton's "the hard cap has no reset path". A `base` left over from an earlier soft resume also loosens the hard cap.
- **M2:** a missing file is silently a fresh job. The file lives where a confused child's `git clean`/`git stash -u` removes it. The last child before a runner exit can therefore reset the per-job cap, and nothing records which count a run started from.

The rest is LOW:
- a 64-bit overflow, measured, disables the cap for one run;
- tmp-file symlink and directory handling;
- unbounded, unescaped file content in the `die` message;
- no `run.log` line on a garbled-file exit;
- no fsync;
- the read happens before the lock;
- in-flight jobs restart at 1 on upgrade;
- test gaps;
- a duplicated line in test 11;
- `preflight` and `status` do not show the count.

Threat model: the README (lines 123-125, owner ruling 3) puts a malicious child out of scope and a lazy or confused child in scope. Findings that need deliberate tampering are therefore rated LOW, with that stated in each.

### Findings

#### CRITICAL

None.

#### HIGH

None.

#### MEDIUM

**M1. The paused-cap base reset applies under the hard cap too: a re-run of a hard-capped job whose status reads `paused-cap` launches a fresh `JOB_MAX_CHILDREN`, and a leftover `base` makes the hard cap count only part of the job**

- **Location:** `lib/chain.sh:163` (`paused-cap) BASE="$LAUNCHED"; chain_count_set`, with no `CAP_SOFT` test, although `chain_cap` already ran at `:151`). The cap test at `lib/chain.sh:184` (`n - BASE > MAXC`, for both caps). The exit-4 message at `:185` prints `$LAUNCHED`, not the counted `n - BASE`. Claims at `baton-runner/br-1115-issues/baton-phase-4-work.md:50` ("The hard cap has no reset path") and `:134` ("The hard cap is now final for a job"), `phase-4/findings.md:16`, the `docs/spec.md` row 4 ("the cap counts every child of the job across runs, so a re-run at the same cap exits 4 before any child"), and README row 4 ("counted over every run of the job").
- **Description:** The `case "$(cp_status)"` at `:162` acts on any `paused-cap` status, whichever cap `chain_cap` chose. Two reachable states break the hard-cap claim.
  1. **Status `paused-cap` with no Phase plan row the runner reads (hard mode).** The runner itself writes `paused-cap` only in soft mode (`:186`), but `checkpoint.md` is child-written. The loop stops only on `done`/`blocked` (`:179-182`), so a child that writes `status: paused-cap` keeps the chain running. Exit 4 does not touch the status (test 10:76 asserts this), so the job ends at the hard cap still reading `paused-cap`. The owner's `blast-off run`, or `blast-off resume`, which accepts `paused-cap` (`lib/units.sh:56`), then sets `BASE=LAUNCHED` and launches `JOB_MAX_CHILDREN` more children. That is "a re-run at the same cap" that does not exit 4. The same path opens when a soft-paused job's table becomes unreadable before the re-run, because `cp_scan` stops reading rows at the first line it refuses (`lib/checkpoint.sh:19-22`, P3R5-13).
  2. **`BASE > 0` from an earlier soft resume, then the table becomes unreadable.** The job is now hard (`phases == 0`, `MAXC = JOB_MAX_CHILDREN`), but the test stays `n - BASE > MAXC`. The hard cap therefore counts only the children since the last soft resume. For example, soft cap 6, one resume (`BASE=6`), then the table goes unreadable: the hard cap of 12 stops at child 19, not 13. The exit-4 message then says `child cap 12 reached (18 children launched ...)`, which reads as a contradiction.

  Each extra allotment needs an owner-started re-run. The resume timer is armed only by `usage_pause`, which overwrites the status with `paused-limit` (`lib/usage.sh:47`), so there is no unattended loop. This is MEDIUM rather than HIGH for that reason. It stays MEDIUM because it breaks the documented exit-4 invariant that issue 22 exists to establish, and the fix is one guard. UNREPRODUCED: runs are forbidden in this review.
- **Probe for the dispatching unit:** on a `git archive` copy, add these lines to the end of the hard-cap block in `tests/10-chain-done.sh` (after the new `child cap 2 reached` assertion), then run `BLAST_OFF_TEST_ONLY=10-chain-done tests/run`:
  `sed -i 's/^status: .*/status: paused-cap/' "$JOB/checkpoint.md"; rc=0; JOB_MAX_CHILDREN=2 "$bo" run "$JOB" > cap4.out 2>&1 || rc=$?; [ "$rc" -eq 4 ] && ! grep -q 'child 3 launched' "$JOB/run.log" || fail "hard cap reset by paused-cap: exit $rc"`.
  Predicted at f388962: FAIL, with `child 3` and `child 4` launched.
- **Suggested fix:** In hard mode, ignore `base`. Either guard the reset (`paused-cap) [ -z "$CAP_SOFT" ] || { BASE="$LAUNCHED"; chain_count_set; }`), or compute the test as `$((n - ${CAP_SOFT:+$BASE}0))`, or set an explicit `[ -n "$CAP_SOFT" ] || BASE=0` after `chain_cap` for the test only, without writing it back. Either way the test should be `n > MAXC` when `CAP_SOFT` is empty. Leave the status handling as it is. Add the probe above as a permanent assertion, and either correct the spec's sentence "the cap is reached when that next child less `base` would pass it" to say soft cap only, or correct the baton claim.

**M2. A missing `child-count` is silently a fresh job, and the file sits where a confused child's git cleanup removes it: the last child before a runner exit can reset the per-job cap, with no record of the count a run started from**

- **Location:** `lib/chain.sh:118` (`[ -e "$f" ] || return 0`), `:152` (the start line logs the cap, not `LAUNCHED`/`BASE`), and `bin/blast-off:54` (default `WORKDIR` is `dirname "$JOB"`, so the job dir is inside the work repo). `lib/chain.sh:66` (`chain_dirty` skips `$JOBREL/*`, so the deletion is never reported).
- **Description:** The runner rewrites `child-count` from memory before every launch (`:194`), so a deletion during a run is healed if another child launches. But after the last child of a run, the runner exits without writing again: at the cap (`:184-186`, at the next loop top), on two stalls (5), on a dirty tree (7), on a usage pause (8), or on an abort. That last child's edits stand.
  - The README's in-scope threat is a lazy or confused child. Such a child might run `git clean -fd[x]` or `git stash -u` to "fix" a dirty tree, or check out or reset to a commit holding an older committed `child-count`. Any of these deletes or rolls back the untracked file in the job dir, which by default is inside the repo.
  - The next run reads "no file": it starts with `0 0`, a fresh hard cap, and numbering from 1. On the paused-limit path the resume timer starts that run unattended (`lib/usage.sh:48`, `lib/units.sh:54-67`).
  - `[ -e ]` is also false for a dangling symlink, which reads the same way.
  - Nothing in `run.log` says which count the run started from, so the reset is visible only as a second `child 1 launched`, and `git clean` also takes `run.log` away.

  This is the exact class issue 22 closes (a relaunch resetting the per-job cap), moved from "any relaunch" to "a relaunch after a confused last child". It is a residual path, not a regression: before this commit every relaunch reset the count. Criterion 3 requires "no file = fresh job", so the fix has to add a witness rather than change that rule.
- **Suggested fix:** (a) Add `LAUNCHED`/`BASE` to the start line at `:152`, for example `child cap $MAXC ($CAP_WHY); $LAUNCHED children launched for this job, base $BASE`. Any reset is then on the record. (b) When the file is missing but `run.log` holds a `child N launched` line, do not assume a fresh job. Either die with the same "fix it, or delete run.log's count too" message, or take `LAUNCHED` from the largest N in `run.log`: `grep -o 'child [0-9]* launched' "$LOG" | tail -n 1`. `run.log` is also child-writable, but a confused child is unlikely to clear both selectively. (c) Use `[ -e "$f" ] || [ -L "$f" ]` so a dangling symlink is a garbled file (exit 1), not a fresh one.

#### LOW

**L1. A count of 9223372036854775807 passes the check and the next child number wraps negative, so the cap is never reached in that run (measured). The pre-existing `JOB_MAX_CHILDREN` check has the same 64-bit gap**

- **Location:** `lib/chain.sh:120` (regex `^(0|[1-9][0-9]*)\ (0|[1-9][0-9]*)$`, no length bound), `:183-184`. Pre-existing sibling: `lib/chain.sh:90`, where `chain_nums` accepts `^[0-9]+$`.
- **Description:** A self-contained probe of the exact `:120` test plus `:183-184` arithmetic (bash 5.2.21) gave:
  - `9223372036854775807 0`: ACCEPT, `n=-9223372036854775808`, `n-BASE=-9223372036854775808`, `-gt 12` false, so the child launches;
  - `9223372036854775807 9223372036854775807`: ACCEPT, `n-BASE=1`, so it launches;
  - `9223372036854775808 0`, `99999999999999999999 0` and `18446744073709551617 1`: REJECT, because `[` prints "integer expression expected" and `die` runs. This part fails closed.

  In the accepted case the run launches children with negative numbers and no cap until `n - BASE` climbs back past `MAXC`, which in practice is never. `:194` then writes `-9223372036854775808 0`, which the next run rejects (exit 1). So the effect is one unbounded run. In the same way, a 20-digit `JOB_MAX_CHILDREN` makes `[ ... -gt "$MAXC" ]` error, and inside the `if` that reads as false, so there is no cap. That gap is pre-existing.

  Rated LOW: writing that value takes deliberate tampering (out of scope, owner ruling 3), and the same writer can more easily write `0 0` or delete the file (M2). It is still the one file value that turns a bounded cap into an unbounded run.
- **Suggested fix:** Bound the digits: `^(0|[1-9][0-9]{0,8})\ (0|[1-9][0-9]{0,8})$`. Use the same `{1,9}` bound in `chain_nums`. Add `'9223372036854775807 0'` to test 10's garbled list.

**L2. `chain_count_set` writes through whatever `child-count.tmp` is (a symlink is followed), and `mv -f` onto a directory named `child-count` moves the file inside it**

- **Location:** `lib/chain.sh:125`.
- **Description:**
  - **Planted symlink.** `echo ... > "$JOB/child-count.tmp"` opens with `O_TRUNC` and follows a symlink. If something has planted `child-count.tmp -> ~/.ssh/authorized_keys` (or any owner-writable file), the runner truncates that file and writes `L B\n` into it. `mv -f` then renames the symlink itself to `child-count`. The next `chain_count` reads the target through it (it now holds a valid `L B`), and the next save replaces the link.
  - **Directory.** If `child-count` is a directory, `mv -f tmp child-count` moves the file into `child-count/child-count.tmp` and succeeds. The count is then not saved, and the next run dies at `cat` ("cannot read"), which fails closed.

  Rated LOW: a child runs as the same user with bypass permissions and could write those files directly, so no privilege boundary is crossed (owner ruling 3). It is still a confused-deputy write outside the job dir, by the runner. Static only; demonstrating it would mean creating files, which this review may not do. UNREPRODUCED. Probe for the dispatching unit, on a `git archive` copy in a scratch dir: `d=$(mktemp -d); mkdir "$d/j"; ln -s "$d/victim" "$d/j/child-count.tmp"; echo keep > "$d/victim"; JOB="$d/j" LAUNCHED=3 BASE=0 bash -c 'source lib/chain.sh; chain_count_set'; cat "$d/victim"; ls -l "$d/j"`. Expected: `victim` holds `3 0`, and `child-count` is a symlink to it.
- **Suggested fix:** `t="$(mktemp "$JOB/child-count.XXXXXX")" && echo "$LAUNCHED $BASE" > "$t" && mv -fT "$t" "$JOB/child-count"`. `mktemp` creates with `O_EXCL` and does not follow links, and `-T` refuses to move into a directory. The dirty-check prefix skip still covers the random name.

**L3. `chain_count` reads any file type with no size bound, and `die` echoes the raw content unescaped**

- **Location:** `lib/chain.sh:118-121`.
- **Description:**
  - **Symlink to a secret.** `cat` follows symlinks. A `child-count` that links to a secrets file fails the regex, and `die` prints `holds '<whole file>'` to stderr, which under the unit is the user journal. `~/.secrets` holds `GH_TOKEN`, so this persists a token in the journal.
  - **FIFO.** A FIFO named `child-count` blocks `cat` forever, before the lock and with no trap, so the unit stays active with nothing in `run.log`.
  - **Device.** A symlink to `/dev/urandom` grows memory without bound.
  - **Control text.** Escape sequences and CRs pass straight to a terminal when the job is run by hand.

  `die` writes only to stderr (`bin/blast-off:48`), so `run.log` cannot be injected. Rated LOW: all of these need deliberate tampering (out of scope), and only the secret-into-journal case adds exposure beyond what the same user already has.
- **Suggested fix:** Read only a regular file, bounded: `[ -f "$f" ] && [ ! -L "$f" ] || die "$f is not a regular file"`, then `c="$(head -c 64 "$f")"`. In the message, quote with `printf %q` (or just say "is not `<launched> <base>`"), not the raw content.

**L4. A garbled-file exit leaves nothing in `run.log`, so on the resume-timer path the job silently stays `paused-limit until <past time>` with no runner**

- **Location:** `lib/chain.sh:119-121` (`die` before the lock and before `log` is ever called). Spec exit 1 row.
- **Description:** This is the right choice for a hand-run `blast-off run`, where the message is on the terminal. But the unattended relaunch is the `<unit>.resume.timer` → `blast-off resume` → `systemd-run` → `blast-off run`. That runner exits 1 at `chain_count`, the status line keeps its `paused-limit until <time>` (now in the past), and `blast-off status` shows that with `ActiveState=inactive`. `run.log`'s last line is still the pause, so the owner has to know to read `journalctl --user -u <unit>`. The same applies to L5's empty-file case.
- **Suggested fix:** Call `log` with the same text before `die` (`log` only appends to `$LOG`, which is safe before the lock), or have `die` in `chain_count` go through `log`.

**L5. "A reboot mid-write leaves one or the other" has no fsync behind it; an empty file after power loss exits 1 on exactly the reboot relaunch issue 22 is about, and the message's remedy resets the cap**

- **Location:** `lib/chain.sh:124-125` (comment and code); the `die` text at `:121` ("or delete it to count this job's children from 0 again").
- **Description:** `echo > tmp && mv` is atomic against concurrent readers, but not durable against power loss. Without an fsync of the file before the rename, a crash can leave `child-count` as a zero-length file on filesystems without ext4's `auto_da_alloc` rename heuristic. The next run then exits 1, which fails closed. That is acceptable, but the owner's quickest way on is the remedy the message offers, "delete it", which grants a fresh cap: the issue's 27→30 case again, by instruction. Rated LOW: the failure is closed and recovery is a manual act.
- **Suggested fix:** Add `sync "$JOB/child-count.tmp"` (coreutils `sync FILE` fsyncs it) before the `mv`, or accept the risk and reword the comment. Have the message suggest the safe value first: "write `<N> <N>` where N is run.log's last `child N launched`".

**L6. The count is read before the lock, so under the documented stale-lock race two runners count from the same base**

- **Location:** `lib/chain.sh:135` (`chain_count`) before `:144` (`chain_lock`). The race is acknowledged at `:30` (`ponytail: takeover of a stale lock is not atomic; two runners racing for one stale lock both proceed`).
- **Description:** The read-side window against a live runner is microseconds, and the second runner dies at the lock anyway. That case is fine and the baton's reasoning holds. But when two runners both take over a stale lock, both read the same `LAUNCHED`, both launch `LAUNCHED+1`, and each rename overwrites the other. The file then under-counts by up to one run's worth, and the numbers in `run.log` repeat. The race is pre-existing; this commit makes the cap depend on it. LOW.
- **Suggested fix:** Move `chain_count` after `chain_lock` (before the traps is fine: a `die` there leaves a lock whose pid is dead, which the next runner takes over as stale). The double-runner race itself stays a ponytail ceiling.

**L7. Jobs already in flight when this lands have no `child-count`, so they restart at child 1 with a full cap once**

- **Location:** `lib/chain.sh:118`. No migration note in `README.md` or `docs/spec.md`.
- **Description:** The first relaunch of any running job after upgrading counts from 0. That is the issue's own over-run class (27→30), once per job. LOW: it is one-time and visible as a second `child 1 launched`.
- **Suggested fix:** Either the M2(b) seed from `run.log`, or one sentence in the spec's `child-count` text: a job started before this version counts from its first run after it.

**L8. Test gaps around the new state file**

- **Location:** `tests/10-chain-done.sh:79-96,127-130`, `tests/21-soft-cap.sh:34-44`.
- **Description:**
  - No assertion reads `child-count`'s content (for example `2 0` after test 10's cap-2 run, or `3 2` after test 21's resume). Every check goes through `run.log` lines, so a save that wrote the wrong `base` would show only in a later run.
  - No case covers the hard cap plus `paused-cap` (M1).
  - The garbled list has no overflow (L1), symlink, directory or dangling-symlink case (L2, L3, M2).
  - Criterion 3 rests on the pre-existing `child 1 launched` (test 10:16) and `^child=1 ` (test 10:77), plus the new `grep -c 'child 1 launched' -eq 1` (test 10:86, test 21:35). No new assertion targets it, as the baton states.
- **Suggested fix:** Add `[ "$(cat "$JOB/child-count")" = "2 0" ]` after test 10:89, add the M1 probe, and add `'9223372036854775807 0'` to the garbled list.

**L9. `tests/11-unit-smoke.sh` has the same `rm -f "$JOB/child-count"` line twice, with two different comments**

- **Location:** `tests/11-unit-smoke.sh:58-59`.
- **Description:** The baton (`baton-phase-4-work.md:35`) describes one line. The commit carries two, each with its own comment. This is harmless, but it shows a merge or edit slip in a test that touches systemd.
- **Suggested fix:** Delete one of the two lines.

**L10. `preflight` and `status` do not show the count, so a preflight that passes can precede an immediate exit 4 or exit 6**

- **Location:** `lib/preflight.sh` (prints `cap:` from `chain_cap` only); `lib/units.sh:70-75` (`unit_status`).
- **Description:** After this commit, a job's remaining allotment is `MAXC - (LAUNCHED - BASE)`, but nothing outside `run.log` shows it. An owner who adds a Phase plan table as README row 4 advises (P4-22b) can see preflight pass, then get `paused-cap` before any child. The work unit already flagged this as outside the criteria. LOW, for usability rather than safety.
- **Suggested fix:** Have `status` and `preflight` print `child-count: L launched, base B` (read-only, no die; show "garbled" when it does not parse).

### Validated

**Acceptance criteria (issue 22):**
- **(1) Cap reached across two runs stops the job (exit 4): met.**
  - `tests/10-chain-done.sh:81-83` re-runs at cap 1, gets exit 4 and no new launch.
  - `:84-89` re-runs at cap 2: exit 4, launches `child 2`, has exactly one `child 1 launched`, no `child 3`, and the line `child cap 2 reached`.
  - `:127-130` re-runs the SIGHUP job at cap 1: exit 4, no new launch. This proves the save happens before launch, which is the reboot case.
  - Soft-cap analogue: `tests/21-soft-cap.sh:37-44` (two stalls, then exit 6 with no child on re-run).
- **(2) Numbering continues after a relaunch: met.** `tests/10-chain-done.sh:86-87` (`child 2` on the re-run, one `child 1`) and `tests/21-soft-cap.sh:35` (`child 3` after the paused-cap resume).
- **(3) A fresh job starts at 1: met.** This rests on the existing `tests/10-chain-done.sh:16`, `:77`, `:110` with no file present (see L8).

**Baton decisions:**
- **Two-number file:** implemented at `:115-125`. The paused-cap fresh allotment is asserted by test 21:30-35, and the baton's mutation evidence shows test 21 goes red without `base`.
- **Save before launch:** `:194`, after every cap and backoff exit, so a cap exit writes nothing. Asserted by test 10:127-130 and by the baton's mutation (save after `child_wait` turns it red).
- **Garbled exits 1:** six values asserted, before any child and with the file unchanged (test 10:91-96). Values over `INT64_MAX` also fail closed (my probe: `[` errors, `die`). `INT64_MAX` itself does not (L1).
- **Paused-cap base reset:** `:163`. It is idempotent: if `cp_set_status` aborts after the save, the next run moves `base` to the same value. It has no unattended trigger, because the resume timer is armed only by `usage_pause`, which sets `paused-limit` (`lib/usage.sh:47-48`). A child writing `paused-cap` mid-run does not move `base` within the run, since the `case` runs once at start. The one gap is that it is not gated to the soft cap (M1).

**Fail-closed under `set -e`:**
- `chain_run` is called as a plain command (`bin/blast-off:65`, under `set -euo pipefail` at `:39`), so errexit is live inside it.
- If `echo >` or `mv` fails in `chain_count_set`, the function returns non-zero, and the call at `:194` aborts the runner before `child_launch`. The EXIT trap logs `runner exit 1 without a state`. At `:163` an abort leaves `paused-cap`, so a re-run retries.
- `c="$(cat "$f")" || die` uses a `local` declared on a separate line, so `cat`'s status is not masked.

**Input handling:**
- The regex rejects a leading zero, so no octal error in `$(( ))`. It also rejects a sign, CR (`$(cat)` strips only trailing newlines), extra fields and an empty value.
- `base <= launched` is enforced.
- `die` goes only to stderr, so file content cannot forge `run.log` lines.

**Integrity within a run:** a child's write to `child-count` during a run is overwritten from the runner's in-memory `LAUNCHED` before the next launch (`:194`). Tampering matters only to the next run (M2).

**Atomicity and permissions:**
- `mv -f` within `$JOB` is `rename(2)`, so a reader sees the old or new file, never half of one. Durability is a separate question (L5).
- The file is created with the runner's umask (systemd user default 0022, so 0644). The content is two counters, not secret.

**Dirty-tree check:** `chain_dirty` skips `$JOBREL/*` (`lib/chain.sh:66`), which covers `child-count` and `child-count.tmp` when the job dir is inside the repo (the default, `WORKDIR=dirname JOB`, `bin/blast-off:54`). When the job dir is outside, it is not in the porcelain at all.

**Blast radius:**
- `git grep` finds no reader or writer of `child-count`, `LAUNCHED` or `chain_count` outside `lib/chain.sh`.
- `preflight` (`lib/preflight.sh`) calls `chain_nums`/`chain_cap` only and never reads the file, as `phase-4/findings.md:6` intends.
- `status`, `stop`, `resume` and `lib/units.sh` are unchanged.
- Test 11 resets the file per `start_hang`. Test 40 changed comments only.
- The baton's scan of re-run scenarios (12, 22, 23, 30, 31, 40, 41) matches what I read.
- The full gate at f388962: `GATE: PASS passed=18 failed=0 shellcheck=ok` (`gate-phase-4-iter-1/tests-run.log`, last line).

**Owner questions:**
- P4-22a (fresh soft allotment versus a lifetime cap) is an owner call. The security-relevant part is only that the reset must stay soft-only (M1).
- P4-22b: the two-start remedy for exit 4 is accurate as the work unit describes it.

### Confidence

- **High:** M1's mechanism (a direct read of `:151`, `:162-163` and `:184`, with no `CAP_SOFT` test on the reset), L1 (measured), L2 and L3 (standard bash and coreutils semantics), and the acceptance mapping.
- **Medium:** M2's likelihood, which rests on how often a confused child cleans untracked files in the job dir as the last child of a run. The mechanism itself is certain.
- **Not verified by running (UNREPRODUCED):** M1's predicted failure and L2's write-through. A probe command is given for each.
