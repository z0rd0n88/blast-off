# penetration-tester: phase 6 (issue 14), round 1

### Summary

Static, read-only review of `git diff 62eeb5c...b010b90 -- . ':!baton-runner'`: `unit_wait`/`wait_snap` (lib/units.sh:96-126), the `wait` dispatch (bin/blast-off:70), tests/13-wait.sh, and the docs. I ran nothing from the repo. A few pure-bash one-liners in the scratchpad checked `cd`, `sed` and `sleep` semantics.

Verified safe: the unit name cannot be injected. `NAME` must match `^[A-Za-z0-9_-]+$` (bin/blast-off:60) and gets the `blast-off-` prefix, so no leading dash, space or glob reaches `systemctl`. `wait` writes nothing: no `log`, no `cp_set_status`, no `chain_count_set`. A garbled `child-count` is shown as `?` and its content is never echoed. The test's fake `systemctl` is first on PATH for the scenario's whole process tree. `cleanup`'s `systemctl --user stop` also hits the fake, so the scenario never reaches real systemd or the installed template. The scenario runs in tests/run's `mktemp -d` cwd. `pkill -P` matches by parent pid, never `-f`.

The main problem: `wait` reports `final` (exit 0, "stop watching") on any `status: done`. The runner has not accepted that `done` yet. It can still refuse it (exit 9 or 10), and the refusal leaves `status: done` in place. A child, or a hostile edit, can therefore end the watch with a false success. Lesser findings:
- unvalidated `BLAST_OFF_WAIT_POLL`
- exit 1 on transient read or bus failures, which the docs map to "fix the path"
- child-controlled content echoed raw into the line the watching Claude session reads
- small races in snapshot order
- coverage gaps where the fake `systemctl` stands in for real systemd behavior

### Findings

#### CRITICAL

None.

#### HIGH

**H1. `status: done` is reported as `final` (exit 0) before the runner accepts it, and stays `final` after the runner refuses it**
- Location: lib/units.sh:105; the runner side is lib/chain.sh:194 (`done) ci_plan; receipt_all_done; ci_check; chain_end 0`), lib/receipt.sh:53-70 (`chain_end 9`) and lib/ci.sh:62-134 (`chain_end 10`). The docs say the same thing at README.md:106 ("stop watching; read `checkpoint.md`") and in skills/blast-off/SKILL.md step 8 ("0 means `done` or `blocked`").
- Failure path / evidence:
  - A child writes `status: done`. `wait` exits 0 `wait: final · status: done ...` on the next poll. At that point the child may still be running, and the runner has not yet run `ci_plan`/`receipt_all_done`/`ci_check`.
  - Those checks can take up to `BLAST_OFF_CI_APPEAR` + `BLAST_OFF_CI_WATCH` (60 + 3600 s by default). They end in `chain_end 9` or `chain_end 10` when a row names no commit, a receipt is missing, or CI is red, unread or absent. No `cp_set_status` runs on that path; the only callers are chain.sh:178/183/202 and usage.sh:47. So `checkpoint.md` keeps `status: done` and the runner unit goes inactive (a `--collect` unit that failed is unloaded).
  - Each later `blast-off wait` returns `final` 0 at once ("already done at start"). The watcher can never see the refusal. The owner is told to stop watching, and `checkpoint.md` says `done`. Only `run.log` holds the exit-9/10 line.
  - phase-6/findings.md ("Unit gone" decision) says a runner exit `9/10` leaves the "status stays running". That is wrong for 9 and 10: they fire only when the status is `done`.
  - Abuse angle: any writer of `checkpoint.md` can end the watch with a false success by writing `status: done`. That includes a child session steered by hostile input (PR text, web content, a poisoned file) and anything else with write access to the workdir. The runner's done gates exist to stop exactly that, and `wait` bypasses them.
- Fix (runner-side fix needs an owner ruling):
  - In `unit_wait`, treat `done` as final only when the runner unit is not `active`/`activating`/`deactivating`, and the last line of `$JOB/run.log` is the runner's own `job done` (`chain_end 0`).
  - Otherwise, report `changed` (a status change while the unit runs) or `stuck` (unit gone, `done` not accepted), with the run.log reason pointer.
  - Alternatively, have the runner rewrite the status on a 9/10 refusal, e.g. `cp_set_status running` or a new `done-refused` word. That also fixes `blast-off status`.
  - Add a 13-wait case: `status: done` with the unit active must block. `status: done` with the unit inactive and a run.log ending in a refusal must not exit 0.

#### MEDIUM

**M1. `BLAST_OFF_WAIT_POLL` is not validated: `0` busy-loops against the user manager, `inf` or huge values block forever, and junk exits 1, which the docs call "fix the path"**
- Location: lib/units.sh:111; bin/blast-off:32 (env doc); README.md:109 (exit 1 row).
- Failure path / evidence (checked in the scratchpad with GNU sleep):
  - `sleep 0` returns at once. Each loop iteration then runs `cat`, three `sed`s, `stat` and two `systemctl --user show` D-Bus round-trips with no pause. That pins a core and floods the user systemd manager for as long as the job runs, which can be hours.
  - `sleep inf` and `sleep 1e9` never return (both hit a 1 s `timeout`, rc 124). GNU sleep also accepts `5d`/`1h` suffixes. After the first snapshot, `wait` never polls again and blocks forever, so the watcher misses every change, including `stuck`.
  - `sleep abc` and `sleep -1` exit 1. Under `set -e` that ends `wait` with rc 1 after one full poll. README maps rc 1 to "no job dir or no `checkpoint.md` → fix the path".
  - The repo validates every other numeric env var (`chain_nums`, lib/chain.sh:89-94, `^(0|[1-9][0-9]{0,8})$`) but not this one.
- Fix: validate once at the top of `unit_wait`, for example `[[ ${BLAST_OFF_WAIT_POLL:-5} =~ ^([1-9][0-9]{0,3}|0\.[0-9]*[1-9][0-9]*)$ ]] || die "BLAST_OFF_WAIT_POLL='…' …"`. A floor like 0.1 keeps the test's 0.1, and a cap of a few minutes is enough. Add a test row for `0` or junk.

**M2. A transient read or bus failure mid-watch exits 1 and claims the job dir or checkpoint is missing**
- Location: lib/units.sh:119 (`cp=... && [ -n "$cp" ] || die "missing $JOB/checkpoint.md"`), lib/units.sh:121-122 (`systemctl` inside an assignment under `set -e`); README.md:109.
- Failure path / evidence:
  - `wait_snap` runs every poll, not only at start. Two kinds of writer can leave `checkpoint.md` empty or briefly absent at a poll:
    - Children edit `checkpoint.md` with their editor's write path. The runner uses `sed -i`, which renames and so is atomic; a truncate-then-write editor is not.
    - A git operation in the workdir (checkout, rebase or stash, whose files are unlinked and recreated) leaves it briefly absent.
  - Such a poll hits `die "missing …/checkpoint.md"` with exit 1. README tells the watcher "fix the path" and the session stops watching a healthy job.
  - Same for `systemctl --user show`. A user-manager hiccup (daemon-reexec, D-Bus restart after resume from suspend, which issue 14 calls out as a condition to ride through) makes the substitution fail. `set -e` aborts with rc 1 and only systemctl's stderr ("Failed to connect to bus").
  - The "missing `checkpoint.md`" branch with an empty file (`[ -n "$cp" ]`) is not covered by any test. 13-wait only tests `rm`.
- Fix: only the first snapshot should `die` on a missing or empty checkpoint. On later polls, an empty or missing read or a failed `systemctl` means "no snapshot this round, poll again", perhaps after N consecutive failures before giving up. A real failure should use its own exit code and text, not "missing checkpoint". Add a test that empties `checkpoint.md` for one poll.

**M3. Child-written `status:`/`phase:` lines are echoed raw into the one line the watching Claude session reads (prompt injection, field forging, terminal escapes)**
- Location: lib/units.sh:123,125 (`sed -n '/^status:/{p;q}'`, `sed -n '/^phase:/{p;q}'` copied whole into `SNAP`), printed at :105/:108/:110.
- Failure path / evidence:
  - `checkpoint.md` is written by children, Claude sessions that may be processing untrusted input. Whatever follows `status:` or `phase:` on those lines reaches the owner's interactive session verbatim, with no length cap and no control-character filter.
  - The line is designed as a machine-read wake-up message, so it is a direct prompt-injection channel from a less trusted session to the owner's more trusted one.
  - Fields can be forged: `status: running · phase: 9 of 9 · child 99 · unit active · timer active` prints a fake field set ahead of the real one, separated by the same `·`. A reader that takes the first `unit` field is fooled; only the leading `wait: <verdict>` and the exit code come from code.
  - ESC/OSC bytes pass through: OSC 52 can write the clipboard, OSC 8 adds links, title sequences rename the window. That works when the owner runs `wait` in a terminal.
  - `\r`, for example from CRLF line endings on this WSL box, makes a terminal overwrite the `wait: changed` prefix with the rest of the line.
  - NUL bytes print `bash: warning: command substitution: ignored null byte in input` on stderr every poll (verified). A watcher capturing `2>&1` then gets many lines, not one.
  - A multi-MB status line goes in whole and floods the session context.
  - The project already ruled the same way for `child-count` (P5R1-5, owner Q5: "names the file and the shape it wants, never the content"). `wait` did apply that to `child-count` (it prints `?`) but not to the checkpoint lines.
  - Pre-existing in kind: `blast-off status` prints the header raw. This diff, however, creates the channel that is meant to be read by an agent.
- Fix:
  - Print only what code derives. That means `WAIT_STATUS` (already `[a-z-]*`) and, for `paused-limit`, `usage_until`'s validated time.
  - For the phase, use a pattern such as `phase: *([0-9]+ of [0-9]+)`, or strip control characters and cap the text (`LC_ALL=C tr -d '\000-\037\177' | cut -c1-120`) and replace `·`.
  - Keep the "read checkpoint.md" advice for the human.

#### LOW

**L1. The snapshot reads checkpoint, then unit, then timer, so it can pair a stale status with a newer unit state (false `stuck`)**
- Location: lib/units.sh:119-125.
- Failure path / evidence:
  - (a) `wait` reads `status: running`. The child then writes `blocked` and exits, and the runner reaches `chain_end 3` and the unit goes inactive, all before the `systemctl show` a few ms later. Result: `wait: stuck · status: running …` exit 12 on a job that is final. README then says "`resume` or `start`".
  - (b) The unit is read `inactive` while `$UNIT.resume.service` is still starting the new runner. Before the timer is read, resume.service finishes and the transient timer (RemainAfterElapse=no from systemd-run) unloads to `inactive`. Result: `inactive inactive` reads as stuck while the new runner is active.
  - Both windows are milliseconds wide, but each produces the wrong exit code.
- Fix: read the timer first, then the unit, then `checkpoint.md`. A non-final status read after an inactive unit was seen is then really stuck. A timer read inactive means resume.service had already started the runner before the unit read. Alternatively, re-take the snapshot once before reporting `stuck`.

**L2. An active timer left over from an earlier pause masks a crashed runner until it fires**
- Location: lib/units.sh:107 (`*' active'`); lib/chain.sh:179-183 vs lib/usage.sh:45 (the runner accepts `until`, the timer fires at `until + JOB_RESUME_MARGIN`).
- Failure path / evidence:
  - The owner runs `blast-off start` between the reset and reset+margin. `chain_run` sets `running`, but `unit_start` (unlike `unit_resume`) does not stop the pending timer.
  - If that runner then crashes, the state is `failed active`, which is not stuck. `wait` blocks until the timer fires (up to `JOB_RESUME_MARGIN`, default 60 s, any value the owner sets). Then `unit_resume` dies on `status is 'running'` and only the next poll says stuck.
- Fix: count an active timer only while the status is `paused-limit`, for example `[ "$WAIT_STATUS" = paused-limit ] && [ "$WAIT_TIMER" = active ]`. Or have `unit_start` stop a pending resume timer.

**L3. The job-dir path is printed unquoted and unchecked: spaces break the advice line, a newline breaks the "one line" contract**
- Location: lib/units.sh:108 (`see blast-off status $JOB`), :119 (`die "missing $JOB/…"`); bin/blast-off:57.
- Failure path / evidence:
  - Only the workdir basename is validated. A job dir under `/home/a b/` prints `see blast-off status /home/a b/job`, and a session that copies it runs `status /home/a`.
  - A job-dir component holding `\n` (allowed by `cd`) makes the stuck line two lines, and the second line's text is the directory name, for example a fake `wait: final · status: done`.
- Fix: `printf '…; see blast-off status %q\n' "$JOB"`, or reject control characters in `JOB` in `job_init`.

**L4. `job_init`'s `cd "$1" && pwd` takes option-like and CDPATH-resolved arguments, so `wait` can watch the wrong job or unit (pre-existing; `wait` inherits it)**
- Location: bin/blast-off:57-59.
- Failure path / evidence (verified with `bash -c 'cd "$1" && pwd'`):
  - `-L` and `--` resolve to `$HOME`, so `UNIT=blast-off-home`, the parent dir's basename.
  - `-` gives `$'$OLDPWD\n$OLDPWD'` (cd prints the path), a two-line `JOB`.
  - With `CDPATH` set, a relative `job` resolves under CDPATH before `./job`, and `JOB` again holds two lines.
  - A symlinked job dir keeps its logical parent, so `wait` via the link and `start` via the real path derive different units. `wait` then reads the other unit as inactive, which gives a false `stuck`, or watches an unrelated job whose workdir basename matches.
  - Two job dirs in one workdir, or two repos with the same basename, share one unit name. `wait` on one job reports the other job's runner.
- Fix: `JOB="$(CDPATH= cd -P -- "$1" && pwd -P)"`, and reject a `JOB` containing a newline. Two jobs per workdir need either a documented rule or a unit name that includes the job.

**L5. FIFO or device as `checkpoint.md` or `child-count` makes `wait` hang or grow without bound**
- Location: lib/units.sh:119 (`cat "$JOB/checkpoint.md"`); lib/chain.sh:129 (`cat "$f"` in `chain_count`, called each poll).
- Failure path / evidence:
  - A FIFO named `child-count` or `checkpoint.md` blocks `cat` with no writer, and `wait` never reaches its stuck check.
  - A symlink to `/dev/zero` reads forever, with a NUL warning per chunk. A symlink to `/dev/urandom` grows the substitution until OOM.
  - Writable by any child. The runner's own `cp_status`/`chain_count` would hang too, so this is pre-existing in kind, but a hung `wait` is a watcher that never wakes.
- Fix: test with `[ -f ]` and not `-p`, and bound the read: `head -c 1M`, or `cat` under `timeout`.

**L6. Coverage gaps from my angle**
- Location: tests/13-wait.sh.
- Failure path / evidence:
  - No case for a `done` the runner refuses, or `done` while the unit is still active (H1).
  - No case for `deactivating`, `activating`, `reloading` (expected to keep blocking) or a timer `failed`.
  - No transition `running → paused-limit` while the unit is active. The issue's "returns on … paused" is only covered with the unit flipped at the same time.
  - `blocked` is tested only "already at start", never as a transition.
  - No empty `checkpoint.md` and no invalid POLL.
  - The machine-sleep case fakes `date`, which `wait` never calls. It proves five unchanged polls do not return, but it would not catch a clock read through `$SECONDS`, `printf '%(%s)T'` or `/proc/uptime`.
  - Every systemd assumption rests on the fake:
    - a gone `--collect` unit reads `inactive`
    - a transient OnCalendar timer that elapsed reads `inactive`, not `active`/`elapsed`, which relies on systemd-run's `RemainAfterElapse=no`
    - `show` exits 0 on unknown units
  - If systemd-run ever left an elapsed timer `active`, `*' active'` would never let `wait` report stuck.
- Fix: add the rows above. Add one real-systemd assertion in 11-unit-smoke: `show` on an unknown unit, and on an elapsed `systemd-run --on-active=1s` timer, prints `inactive`.

**L7. The test's write to `child-count` is not atomic (possible flake), unlike the runner's**
- Location: tests/13-wait.sh:50, :128 (`echo '1 0' > "$JOB/child-count"`) vs `chain_count_set` (lib/chain.sh:137, tmp + `mv`).
- Failure path / evidence: a poll between the truncate and the write reads an empty file. `chain_count` fails, giving `child ?`, so the result is 11 with `child ?`, and the `grep 'child 1'` check fails. The window is µs against a 0.1 s poll: rare but real.
- Fix: write the way the runner does: `echo '1 0' > "$JOB/child-count.tmp" && mv -f "$JOB/child-count.tmp" "$JOB/child-count"`.

**L8. `stop_bg` kills by pids from `jobs -p` that may already have been reaped and reused**
- Location: tests/13-wait.sh:22.
- Failure path / evidence: `jobs -p` in a non-interactive shell still lists finished, un-notified jobs. If a pid has been reused, `kill "$p"` and `pkill -P "$p"` signal an unrelated process and its children. Each background wait already has `timeout 30`, so the cleanup buys little.
- Fix: only signal pids whose `<n>.rc` has not been written, or use `jobs -pr` (running jobs only).

**L9. Exit-code and stuck-rule docs are incomplete**
- Location: README.md:106-109; bin/blast-off:11-13; docs/spec.md §3.
- Failure path / evidence:
  - Exit 1 also comes from a `systemctl` or bus failure, an invalid POLL, or an unreadable checkpoint, not only "no job dir or no checkpoint.md" (M1, M2).
  - Exit 0 is documented as terminal, but under H1 a `done` is not terminal until the runner accepts it.
  - States the stuck rule does not list (`activating`, `reloading`, `maintenance`, `refreshing`) keep `wait` blocking. Correct, but undocumented.
- Fix: document the actual sources of exit 1 and the non-stuck transitional states once H1, M1 and M2 are settled.

### Open questions for the owner

1. H1: should the runner rewrite the status when it refuses `done` (exit 9/10), for example back to `running` or a new `done-refused`? Or should `wait` alone require the unit to be gone and `run.log` to end in `job done` before it reports `final`? The runner-side fix also corrects `blast-off status` and every other reader of `status:`.
2. M3: may the `wait` line carry child-authored text at all? Or should it print only the derived status word, the `paused-limit` time and the `N of M` phase, as was ruled for `child-count` (P5R1-5/Q5)?
3. M1: what are the bounds for `BLAST_OFF_WAIT_POLL`? I suggest a floor of 0.1 s for tests and a cap of about 300 s, and a refusal with exit 1 and its own message.
4. M2: should a transient missing or empty `checkpoint.md` or a `systemctl` failure after the first snapshot be retried, and how many times before `wait` gives up? Should it give up with its own exit code?
5. L4: is "one job per workdir" a rule? If so, should `start`/`wait` refuse a second job dir under the same workdir? Two job dirs share one unit name today.
6. Q2 (foreground `run` reads as `stuck`): the runner's lock file (`$XDG_RUNTIME_DIR/$UNIT.lock`, pid + start time, lib/chain.sh:31-40) already tells a live foreground runner apart. Is that worth the few lines, given a session that follows README's 12 advice would `start` a second runner? `chain_lock` refuses that second runner, so it is safe, but noisy.
