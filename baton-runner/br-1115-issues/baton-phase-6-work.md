---
source: runner
scope: br-1115-issues
parent_session: ""
---
# Pass-Baton: phase 6 work unit, issue 14 (`blast-off wait <job-dir>`) implemented

**Date:** 2026-11-17
**Scope:** br-1115-issues
**Branch:** feat/br-1115-issues/phase-6
**Worktree:** /home/alex/blast-off/.claude/worktrees/pending-items-53932d
**HEAD:** 62eeb5c Merge pull request #41 (changes uncommitted; the manager owns git)

## Where things stand

Issue 14 is implemented test-first. `blast-off wait <job-dir>` blocks until the job changes, then prints one line
and exits. All three acceptance criteria and the devil's-advocate case ("unit gone but status still running") have a
test in the new scenario `tests/13-wait.sh`, and a mutant kills each one. Scenarios were run alone, one at a time:
13-wait, 70-docs and 12-start-env all PASS. I did not run the full gate, 11 or 31. `shellcheck -S warning` is clean on
the 4 changed scripts. Nothing is committed, and STATE.md and log.md are untouched.

Files changed (tracked, 6; `git diff --stat`: 65 insertions, 4 deletions), plus 1 new file:
- `lib/units.sh`: new `unit_wait` and `wait_snap`, appended after `unit_logs`.
- `bin/blast-off`: `wait` added to the `start|status|stop|logs|resume` dispatch through `job_init`. The usage header
  gets a `wait` entry with its exit codes, and the env list gets `BLAST_OFF_WAIT_POLL=5`. The `# Exit:` block is
  unchanged, so 70-docs still counts 10 codes.
- `tests/13-wait.sh` (new, 131 lines): uses a fake `systemctl` local to the scenario and `BLAST_OFF_WAIT_POLL=0.1`.
  It never touches a real unit or the installed template. On exit it TERMs its background waits (`pkill -P <subshell>`,
  by parent pid, never `-f`). It runs in about 24 s.
- `tests/70-docs.sh`: `wait` added to README's command loop, and `^   blast-off wait <job-dir>` added to the SKILL.md
  hand-over lines.
- `docs/spec.md`: a §2 `wait` row (Phase `issue 14`), a §3 paragraph on wait's own codes, and a §6 `13-wait` row.
- `README.md`: the Watch block opens with `blast-off wait`. A new "Watching from a Claude session" paragraph and a
  Line | Exit | What to do table follow it. The Line column comes first so 70-docs' `^| N |` exit-row check cannot be
  satisfied by this table.
- `skills/blast-off/SKILL.md`: the step 7 later-lines block opens with `blast-off wait <job-dir>`. Step 8 says to run
  it as a background command, never a recurring loop or cron, and what 11, 0 and 12 mean.

Untracked: `baton-runner/br-1115-issues/phase-6/{task_plan,findings,progress}.md`, this file, `tests/13-wait.sh`.

## Decisions (also in `phase-6/findings.md`)

- **Poll, not inotify.** `inotifywait` is not a dependency (not in `DEPS`, not installed). One process reads a
  snapshot every `BLAST_OFF_WAIT_POLL` s (default 5). The snapshot holds the `status:` line, the `phase:` line, the
  child number (`child-count`'s `<launched>` through `chain_count`, `?` when garbled), the runner unit's ActiveState
  and the resume timer's ActiveState. Polling costs no tokens.
- **Sleep handling.** `wait` compares state only. It calls no `date` and keeps no timestamps, so a machine sleep is
  just one more poll. There is no timeout env: one would bring the clock back in, and the caller's background command
  has its own.
- **Output line:** `wait: <final|changed|stuck> · status: <...> · phase: <...> · child <n> · unit <state> · timer <state>`.
  A `stuck` line ends with `; see blast-off status <job-dir>`.
- **Exit codes**, kept outside the runner's 0-10:
  - 0 `final`: the status is `done` or `blocked`, whatever the unit's state.
  - 11 `changed`: the job still runs or is scheduled; run `wait` again.
  - 12 `stuck`.
  - 1: no job dir (`blast-off: no job dir <path>` from job_init), no argument, or a missing or empty `checkpoint.md`.
- **Unit-gone handling:** the job is `stuck` when the runner unit is `inactive`, `failed` or `deactivating`, the
  resume timer is not `active`, and the status is not final. That covers stop, crash, reboot, a runner exit that
  leaves `running`, `paused-cap`, and `paused-limit` with no timer. A `paused-limit` whose timer is active blocks until
  the timer starts the unit, then returns 11.
- **Already final or stuck at start:** `wait` returns at once with the same line and code.
- **Each poll checks in order** final, then stuck, then changed, all on one snapshot. The status word comes from the
  same read as the line. The first draft re-read `cp_status` and printed a stale line; the test caught it.

## Evidence

RED (13-wait before `wait` existed): `FAIL: wait returned before any change (child-count 0 0): rc 1: blast-off: unknown command 'wait' (see blast-off --help)`

GREEN: `GATE-ONLY: PASS passed=1 failed=0 shellcheck=ok only=13-wait` (24 s), `GATE-ONLY: PASS passed=1 failed=0 shellcheck=ok only=70-docs`, `GATE-ONLY: PASS passed=1 failed=0 shellcheck=ok only=12-start-env`.

Mutants: each was an in-place edit with a backup. I ran 13-wait (or 70-docs) alone, then restored the file, and
`cmp` printed equal every time.
- Child launch, M1 (child dropped from the snapshot): `FAIL: wait did not return (child launch):`
- Phase change, M2 (phase cached at the first read): `FAIL: wait did not return (phase change):`. An earlier M2 that
  dropped the phase entirely was killed by the shape check: `FAIL: wait line not in its documented shape: wait: changed · status: running · child 1 · unit active · timer inactive`
- Done/blocked, M3 (final check removed): `FAIL: wait exit 11, want 0 (status done): wait: changed · status: done · phase: 1 of 1 · child 0 · unit active · timer inactive`
- Already final at start, M3b (final checked only after a change): `FAIL: wait exit 12, want 0 (already done at start): wait: stuck · status: done · ...`
- Unit inactive / unit gone while running, M4 (stuck check removed): `FAIL: wait exit 11, want 12 (unit went inactive): wait: changed · status: running · phase: 1 of 1 · child 0 · unit inactive · timer inactive`
- Paused-limit with timer, M5 (timer ignored): `FAIL: wait returned before any change (paused-limit with its resume timer active): rc 12: wait: stuck · status: paused-limit until 2099-01-01T00:00:00Z · ... · unit inactive · timer active; ...`
- Missing job dir, M6 (wait bypasses job_init): `FAIL: missing job dir: no reason: blast-off: missing /tmp/tmp.KMygh6ZTpt/cwd/no-such-job/checkpoint.md`. An earlier M6 that also broke UNIT was killed by the first case instead.
- Missing checkpoint, M6b (die removed): `FAIL: wait with no checkpoint.md: exit 124:`. Before I wrapped the
  synchronous calls in `timeout 10`, this mutant hung to the scenario timeout. They are wrapped now.
- Machine sleep, M7 (returns `stall` when `date +%s` jumps 600 s or more between polls): `FAIL: a 10 h clock jump per poll ended wait with no change: rc 11: wait: stall · status: running · phase: 1 of 1 · child 0 · unit active · timer inactive`
- Docs, D2 (SKILL.md wait line removed): `FAIL: SKILL.md has no line matching '^   blast-off wait <job-dir>( |$)'`. D1 (one README line renamed) SURVIVED, because the paragraph and table still say `blast-off wait`. D1-all (every README mention renamed): `FAIL: README does not show 'blast-off wait'`.

ExecStart check: before the first run and after every run (RED, GREEN, each mutant, 70-docs, 12), always
`ExecStart=/home/alex/blast-off/.worktrees/blast-off-build/bin/blast-off run %f`. No scenario I ran installs units.

## Open questions / risks

- Q1 (default applied): `paused-cap` exits 12 (`stuck`), not 0, because it needs the owner's `resume`. 0 stays the
  issue's terminal status (done, blocked).
- Q2 (default applied): a foreground `blast-off run` has no unit, so it reads as `stuck`. This is documented in the
  spec and README. Reading the runner lock instead would cover it, at more code.
- The machine-sleep test catches clock reads through `date` only. A mutant using bash `$EPOCHSECONDS`/`$SECONDS` would
  survive it. `faketime` is not installed, and I did not add it as a test dependency.
- Not verified on real systemd: whether a resume timer that fired but whose `resume` failed stays `active (elapsed)`.
  If it does, `wait` blocks on that paused-limit job instead of saying `stuck`.
- `wait`, like `status`, derives the unit from the job dir's parent, so a job run with its own workdir is watched under
  the wrong unit name (it reads `stuck`).
- A fresh job read before `start` (status `running`, no unit) is `stuck`. The docs say to run `wait` after `start`.
- `BLAST_OFF_WAIT_POLL` is not validated. A non-number makes `sleep` fail, and set -e then exits 1 with sleep's error.
- 13-wait's `blocks` helper sleeps 1 s per check (8 checks), which accounts for most of its 24 s.

## Next step for the review unit

Run the full gate alone (`scripts/gate.sh`) and check ExecStart afterwards. Then review `git diff 62eeb5c` on the 6
tracked files plus `tests/13-wait.sh`. Check: the exit-code scheme (Q1, Q2); that the stuck rule is right for a unit
in `activating` during `start`/`resume`; the wording of the SKILL.md step 8 addition against the skill's other steps.
