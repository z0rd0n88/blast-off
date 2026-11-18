# tdd-guide: phase 6 (issue 14), round 1

### Summary

Static review only. I ran nothing and edited nothing except this file. Diff: `git diff 62eeb5c...b010b90 -- . ':!baton-runner'`.

The test-first evidence is real. RED is recorded, and 9 code mutants plus 2 docs mutants each have a recorded kill
(D1 survived). Every issue-14 criterion has at least one assertion in `tests/13-wait.sh`. Gaps, worst first:

- The issue's first clause, "blocks until the **status line** changes", has no test where only the status changes.
  That includes the documented "paused-limit written while the unit is still active -> 11" path. A mutant that drops
  the status line from the change comparison survives.
- A fired resume timer whose `resume` failed stays `ActiveState=active` (SubState `elapsed`). `wait` then blocks
  forever on a job that will never move: the devil's-advocate case, one variant over. The fake `systemctl` cannot
  express it.
- The machine-sleep test only kills mutants that read the clock through `date`. The code under test never calls
  `date`, so the fake clock only ever affects mutants.
- The fake `systemctl` checks neither the property nor `--value`, and no scenario runs `wait` against real systemd.
- `blocks` assumes the first snapshot lands within 1 s. Under load, a change can fold into the baseline and hang the
  check: a false FAIL, never a false PASS.
- 70-docs checks only that `wait` is mentioned. Nothing pins the 0/11/12 table against the code, or the skill's
  "never a recurring loop or cron" wording.

No CRITICAL findings.

### Criterion -> test map

| Issue-14 criterion | Assertion in tests/13-wait.sh | Plausible surviving mutant |
|---|---|---|
| returns on child launch | 48-53: `child-count` `0 0` -> `1 0`; `ends c 11 'child 1'` plus the full-line shape regex at 52 | none found (M1 killed). A race makes it flaky (L1) |
| returns on phase change | 56-59: `ck phase '2 of 3 — build'`; `ends p 11 'phase: 2 of 3 — build'` | none found (M2 killed) |
| returns on status-line change (issue text: "status line") | **none in isolation.** The status changes only to `done` (final, 0) or together with a unit change (84, 87-90) | **survives:** drop `$s` from the compared SNAP and keep it in the printed line (H1) |
| done | 62-67: `ck status done` with unit active -> `ends d 0 'wait: final · status: done'`; 66-67 already done with unit inactive -> `ends d2 0` | none found (M3, M3b killed) |
| blocked | 68-69: **only "already blocked at start"** with unit inactive -> `ends b 0 'wait: final · status: blocked'`. No running -> blocked transition | drop `blocked` from the final case: killed by 69 (the stuck path gives 12). Weak but adequate (L2) |
| paused | **paused-cap:** 82-85, unit set inactive first, then `paused-cap` -> `ends pc 12 'wait: stuck'` (the line text does not prove paused-cap); 86 already paused-cap -> `ends pc2 12 'status: paused-cap'`. **paused-limit:** 87-90 with timer active, `blocks`, then unit active -> `ends pl 11 'unit active · timer active'`; 91-92 with no timer -> `ends pl2 12`. Expected exits: paused-cap 12, paused-limit+timer 11, paused-limit without timer 12. Never 0 (owner Q1) | **survives:** running -> paused-limit while the unit is still active (the 11 path findings.md documents) has no test (H1). Timer `elapsed` after a failed resume: untestable with this fake (H2) |
| unit inactive | 72-75: unit active -> inactive with status running -> `ends g 12 'wait: stuck · status: running'`; 77 already inactive -> `ends g2 12`; 78-79 `failed` -> `ends g3 12 'unit failed'` | `failed` ignored: killed (g3 hangs to timeout). `deactivating` dropped: **survives**. Treating `activating`/`reloading` as stuck: **survives** (M5) |
| missing job dir, non-zero with a reason | 95-99: rc 1 and `no job dir $PWD/no-such-job`; 100-103: no argument, rc 1 and `missing <job-dir>`; 104-108: no checkpoint.md, rc 1 and `missing $JOB/checkpoint.md` | empty-but-present checkpoint.md: **survives** (L5) |
| machine sleep is not a change | 110-129: fake `sleep` counts polls, fake `date` jumps 10 h per poll; at least 5 polls with no return (126-127), then a real change -> `ends s 11 'child 1'` | `$EPOCHSECONDS`, `$SECONDS`, `printf '%(%s)T'` and `/proc/uptime` stall checks all **survive**. A clock-free "give up after N unchanged polls" with N >= 20 also **survives** (M4). Only `date`-based M7 is killed |
| devil's advocate: unit gone, status still running | 72-77 (g, g2) and 76: the stuck line names `blast-off status $JOB` | reboot = transient unit gone = `inactive`, same as g2, but only against the fake (M3). Fired timer plus failed resume: **hangs** (H2) |
| exit 0 on terminal status | d, d2, b (above) | none found |
| prints one line | `ends` line 42: `wc -l` = 1 on merged stdout+stderr | line printed to stderr instead of stdout: **survives** (L4) |

### Findings

#### CRITICAL

None.

#### HIGH

**H1. No test proves `wait` returns when only the status line changes; the documented paused-limit-while-active 11 path is untested**
- Location: tests/13-wait.sh:82-92 (paused block), 84 (`echo inactive ...; ck status paused-cap  # unit first`); lib/units.sh:110 (`[ "$SNAP" = "$was" ]`) and 125 (SNAP includes `$s`).
- Failure path / evidence: issue 14 says "blocks until the status line, the phase or the child number changes". Every status change in the scenario either goes to a final word (`done`/`blocked` are caught by the final check, lines 64 and 68) or comes with a unit or timer change (84 sets the unit inactive first, 87-89 change the timer and the unit). Mutant: compare `"${SNAP#* · }"`, or a snapshot built without `$s`, while still printing the full SNAP. The shape check at 52 still sees `status: running`, d/b still exit through `WAIT_STATUS`, g/pc/pl still exit through the unit/timer, so every assertion passes. phase-6/findings.md bullet 4 calls "usage_pause writes paused-limit before it arms the timer ... a poll can see paused-limit with the unit still active: that is a change (11)" a designed behaviour, and no test covers it. With the mutant, production still returns, but one poll later and for the wrong reason (the timer or unit change). The criterion as written goes unproven.
- Fix: add one case. Job with unit active, `bw`, `blocks`, `ck status 'paused-limit until 2099-01-01T00:00:00Z'` with unit and timer untouched, then `ends <n> 11 'status: paused-limit until'`. Optionally also `ck status paused-cap` with the unit active -> 11 (the runner's moment before exit 6).

**H2. A fired resume timer whose `resume` failed reads `active` for good: `wait` blocks forever on a job that cannot move, and no test can express it**
- Location: lib/units.sh:106-108 (`*' active') ;;` treats any timer `active` as scheduled), lib/units.sh:122 (reads only `ActiveState`); lib/units.sh:66 (unit_resume `exit 1` on a failed start leaves the timer loaded); lib/usage.sh:69-70 (`systemd-run --collect --on-calendar`, default `RemainAfterElapse=yes`); tests/13-wait.sh:12-16 (the fake returns a single word per unit).
- Failure path / evidence: in systemd's timer state table, `elapsed` maps to `ActiveState=active`. A calendar timer with the default `RemainAfterElapse=yes` stays loaded in `elapsed` after it fires, and `--collect` only collects inactive or failed units. If the timer's `blast-off resume` fails (`unit_start ||` -> `exit 1`, or `exit 8` on an early fire), the timer is never stopped. Status stays `paused-limit until <past>`, the runner unit is `inactive`, the timer is `active (elapsed)`. `wait` is not stuck (the timer reads active) and nothing changes, so it blocks until the caller's background timeout. This is the issue's "state never changes on its own" case. The phase-6 work note already lists it as "not verified on real systemd". The fake's one-word-per-unit model cannot produce it, so it cannot be tested as built.
- Fix: read the timer's `SubState` too (`-p ActiveState,SubState` or a second `show -p SubState --value`), and count timer `elapsed` as not armed. Teach the fake to answer per property, e.g. file `sd/<unit>.SubState`, falling back to `dead`. Add a case: paused-limit, unit inactive, timer active+elapsed -> `ends 12`. Before choosing, verify on real systemd that a fired one-shot calendar timer created with `systemd-run --collect --on-calendar` stays active/elapsed (owner question 1).

#### MEDIUM

**M1. `blocks` assumes `wait` took its first snapshot within 1 s; if it has not, the change becomes the baseline**
- Location: tests/13-wait.sh:37 (`blocks() { sleep 1; [ ! -e "$1.rc" ] ... }`), used at 49, 57, 63, 73, 83, 88.
- Failure path / evidence: `blocks` only shows that `wait` has not returned yet. It cannot tell "blocking on an unchanged job" from "still sourcing lib/*.sh". On a loaded CI box or a cold WSL start, if `bin/blast-off` reaches its first `wait_snap` after the test's write, the changed state is `was`. Cases c, p and pl then never see a change and fail after `ends`' 10 s with "wait did not return": a false FAIL. Cases g, d and pc pass anyway through the at-start path, so the "transition while waiting" property they claim quietly degrades into the at-start property that g2, d2 and pc2 already test.
- Fix: make the fake `systemctl` append one line per call to `sd/calls`. `blocks` then waits (`wait_until`) until the call count has grown by at least 4 (two complete snapshots) and `.rc` is still absent, before the test writes. This also removes the fixed 1 s sleep (see L9).

**M2. The machine-sleep test only kills mutants that call `date`; the code under test never calls the fake clock**
- Location: tests/13-wait.sh:110-129 (fake `date` at 118-122, `polled` at 125); lib/units.sh:101-126 (no `date`, `SECONDS` or `EPOCHSECONDS`).
- Failure path / evidence: `unit_wait`/`wait_snap` call no `date`, so the fake `date` is never invoked against the real code. It exists only to kill M7. A stall check written as `now=$EPOCHSECONDS`, `$SECONDS`, `printf -v now '%(%s)T'` or `read up _ </proc/uptime` sees the real ~0.05 s per poll and survives (the work note admits the `EPOCHSECONDS`/`SECONDS` case). The sleep section and `blocks` also run at most ~10 unchanged polls, so a clock-free mutant ("stuck after 20 unchanged polls") survives too. That mutant breaks "blocks until a change" for any child longer than ~100 s in production. The fake `sleep` part does carry weight: it shows the loop goes through PATH's `sleep`, so a fake can drive it.
- Fix: (a) a static guard in 13-wait: extract `unit_wait` and `wait_snap` with `declare -f` (source lib/units.sh in a subshell) and fail on `date|EPOCHSECONDS|SECONDS|%\(|/proc/uptime|stat `, which kills the whole clock family in one line; (b) make the fake `sleep` a no-op (no real 0.05) and require `polls >= 200` before the change, which kills poll-count give-up mutants cheaply.

**M3. The fake `systemctl` ignores the property and `--value`; no scenario runs `wait` against real systemd**
- Location: tests/13-wait.sh:12-16 (`[ "${2:-}" = show ] || exit 0; cat "$FAKE_SD/$3" ...`); tests/11-unit-smoke.sh (starts a real runner unit, never calls `wait`).
- Failure path / evidence: the fake answers with the file content whatever follows `$3`. Mutants `-p SubState --value` (real values `running`/`dead`/`exited`: the stuck rule never matches `dead`, so a gone unit blocks forever) and dropping `--value` (real output `ActiveState=active`, so nothing ever matches) both pass 13-wait. (Dropping `--user` is killed: `$2` would be the unit name and the fake returns empty.) The work note's claim that "a `--collect` unit that is gone reads `inactive`" is never checked against real systemd.
- Fix: make the fake strict: `[ "$*" = "--user show $3 -p ActiveState --value" ] || { echo "fake systemctl: unexpected $*" >&2; exit 2; }` for `show` calls (and for SubState if H2 is adopted). Add one real-systemd assertion to tests/11-unit-smoke.sh, which already owns a real unit: after the unit stops with the status left `running`, `timeout 30 blast-off wait $JOB` exits 12. That covers "unit gone reads inactive" end to end.

**M4. `activating`, `reloading` and `deactivating` are untested; both sides of the stuck pattern can mutate freely**
- Location: lib/units.sh:106-108; tests/13-wait.sh (only `active`, `inactive` and `failed` are ever written).
- Failure path / evidence: the simplest rewrite of the rule, `[ "$WAIT_UNIT" = active ] || [ "$WAIT_TIMER" = active ] || stuck`, passes every case. In production it reports `stuck` (12) on a unit that is `activating`, which `wait` can see right after `start` or during the timer's `resume`. Dropping `deactivating*` from line 108 also survives.
- Fix: two at-start cases: unit `activating`, timer inactive, status running -> `blocks` (not stuck), then `active` -> 11; and unit `deactivating`, status running -> 12. `reloading` can share the `activating` case.

**M5. A transient failure exits 1, which the docs map to "fix the path"; untested**
- Location: lib/units.sh:119 (`cp=... && [ -n "$cp" ] || die "missing $JOB/checkpoint.md"`), 121-122 (`WAIT_UNIT="$(systemctl ...)"` under `set -e`); README wait table row "no job dir or no `checkpoint.md` | 1 | fix the path".
- Failure path / evidence: (a) if the user bus is briefly unreachable, `systemctl --user show` exits non-zero. The plain assignment carries that status, so `set -e` ends `wait` with exit 1 and systemctl's stderr, and no `wait:` line. (b) If a child rewrites checkpoint.md without an atomic rename, a poll can read it empty and `die "missing ... checkpoint.md"`. Over an hours-long run polled every 5 s, that is plausible. In both cases a watcher following the README "fixes the path", which is not the problem. No test pins either.
- Fix: decide the behaviour first (retry next poll, or a distinct exit code), then add a test. Fake `systemctl` exits 1 once (a flag file) and `wait` keeps blocking or returns the chosen code. Truncate checkpoint.md to empty for one poll and assert the same.

**M6. 70-docs pins only that `wait` is mentioned; the exit-code table and the skill's "never a recurring loop" are free to drift**
- Location: tests/70-docs.sh:17 (SKILL hand-over line), 34 (`for c in ... wait ...` -> `grep -qE "blast-off $c( |\`|$)"`); README wait table; SKILL.md step 8.
- Failure path / evidence: D1 survived: renaming one README line is invisible because any other `blast-off wait` mention satisfies the check. The issue's requirement is "name it as the way to watch a job, **in place of a recurring loop**". Deleting SKILL.md step 8's "background command, never a recurring loop or cron" passes. So does changing README's table to say 11 means stuck, or a code change to `exit 13`, while the README still says 12.
- Fix: in 70-docs, (a) assert README's table has rows `| *\`final\`.* \| 0 \|`, `\`changed\`.* \| 11 \|` and `\`stuck\`.* \| 12 \|`; (b) assert `grep -oE 'exit 1[0-9]' lib/units.sh` (unit_wait's codes) equals the codes in that table; (c) assert SKILL.md and README contain `background command` and `never a recurring loop or cron` (flattened, as the P3R3-7 block does).

#### LOW

**L1. Test writes are not atomic; a poll that lands mid-write gives a false FAIL**
- Location: tests/13-wait.sh:50 and 128 (`echo '1 0' > "$JOB/child-count"`), 66/74/78/84/89/91 (`echo <state> > "sd/$UNIT.service"`), 87.
- Failure path / evidence: `>` truncates, then writes. A poll between the two reads empty: `chain_count` fails its regex and gives `child ?` (11 with `child ?`, and `ends c` wants `child 1`), or the fake prints nothing (`unit ` empty: g gets 11, not 12). The window is microseconds, so this is rare, but it is a real nondeterminism. Production avoids it: `chain_count_set` writes tmp then `mv`, and `cp_set_status`/`ck` use `sed -i`.
- Fix: a helper `put() { printf '%s\n' "$2" > "$1.tmp" && mv -f "$1.tmp" "$1"; }` for every state write.

**L2. `blocked` is tested only as "already blocked at start" with the unit inactive**
- Location: tests/13-wait.sh:68-69.
- Failure path / evidence: no running -> blocked transition with the unit active (the runner's real order: write `blocked`, then exit 3). Today's plausible mutants are still killed by 69, so the risk is low. It is the one terminal state without a transition case.
- Fix: in the `fin` job, a second `bw` with the unit active: `ck status blocked` -> `ends 0 'wait: final · status: blocked'`.

**L3. The pc assertion does not prove paused-cap**
- Location: tests/13-wait.sh:85 (`ends pc 12 'wait: stuck'`).
- Failure path / evidence: by design (comment at 84) it passes whether `wait` saw `running` or `paused-cap`. Only pc2 (86) shows paused-cap in the line. That is fine, but the pc case adds little beyond g.
- Fix: none needed. Or drop pc and keep pc2 to save ~2 s.

**L4. stdout and stderr are merged; "one line on stdout" is not proven**
- Location: tests/13-wait.sh:35 (`> "$n.out" 2>&1`), 42.
- Failure path / evidence: a mutant that prints the `wait:` line with `>&2` passes. Stray stderr would also be counted as "the line" in the `grep -qF`.
- Fix: redirect `2> "$n.err"` and assert `.err` is empty on the 0/11/12 paths, and that the reason is on stderr for the exit-1 paths.

**L5. Empty-but-present checkpoint.md is untested**
- Location: lib/units.sh:119 (`&& [ -n "$cp" ]`); tests/13-wait.sh:104-108 covers only a deleted file.
- Failure path / evidence: dropping `&& [ -n "$cp" ]` survives. An empty checkpoint then gives an empty status; with the unit active, `wait` blocks with no reason.
- Fix: `: > "$JOB/checkpoint.md"` -> rc 1 and `missing $JOB/checkpoint.md`, or whatever M5 decides.

**L6. `BLAST_OFF_WAIT_POLL` default and validation are unpinned**
- Location: lib/units.sh:111 (`sleep "${BLAST_OFF_WAIT_POLL:-5}"`); bin/blast-off usage line `BLAST_OFF_WAIT_POLL=5`.
- Failure path / evidence: a default changed to 300 survives (only 70-docs-style text mentions 5). A non-number makes `sleep` fail, and `set -e` exits 1 with sleep's error, again read as "fix the path".
- Fix: optional. Validate it (`[[ $p =~ ^[0-9]+(\.[0-9]+)?$ ]] || die`) and test one bad value -> rc 1 with the env name.

**L7. Status-word parsing is only tested with bare `done`/`blocked`**
- Location: lib/units.sh:124; tests/13-wait.sh:64, 68.
- Failure path / evidence: a mutant that compares the whole remainder (`${s#status: }`) still passes, because the tests write bare words. A child writing `status: done (all phases)` would then get 11, not 0. The template teaches bare `status: done`, so this is unlikely.
- Fix: write `ck status 'done — all phases merged'` in case d.

**L8. Background cleanup: sound on the failure paths, small edge cases remain**
- Location: tests/13-wait.sh:22-23 (`stop_bg` via `jobs -p` + `pkill -P`).
- Failure path / evidence: on `fail`, the EXIT trap TERMs each `bw` subshell's child (`timeout`, after `env` execs it). GNU `timeout` passes the TERM to `blast-off wait` and its `sleep`, so nothing is orphaned, and each wait is also capped by `timeout 30`. Edge cases: (a) `jobs -p` can list a subshell that already finished, and a reused pid would make `pkill -P` hit an unrelated process's children (very unlikely); (b) when tests/run's outer `timeout 300` fires, the inner `timeout 30` processes are in their own process groups, so only the scenario's EXIT trap (bash runs it on TERM) or the 30 s cap ends them. That is bounded. No zombies: bash reaps the subshells.
- Fix: optional. Record each `$!` in an array at `bw` time and kill only those.

**L9. Runtime ~24 s comes mostly from fixed 1 s sleeps, not from `wait`**
- Location: tests/13-wait.sh:37 (`sleep 1` in each of 6 `blocks`), tests/lib.sh:63-66 (`wait_until` checks once a second, so each of ~13 `ends` costs ~1 s even when `wait` returns in 0.1 s).
- Failure path / evidence: deterministic apart from M1 and L1, but about 5x slower than it needs to be. The 10 s `ends` margin against a 0.1 s poll is generous and fine.
- Fix: the M1 call-count `blocks`, plus a local fast poll for `ends` (`for i in $(seq 100); do test -s "$1.rc" && break; sleep 0.1; done`).

**L10. A job run with its own workdir is watched under the wrong unit name and reads `stuck`; untested and undocumented as a limit**
- Location: bin/blast-off:70 (`wait` takes only `${2:-}`, so `WORKDIR` defaults to the job's parent); README wait section.
- Failure path / evidence: same limitation as `status` (noted in the work note's risks). `wait` returns 12 at once for a healthy run whose unit is `blast-off-<other>`. No test or README line says so; README only says a foreground `run` reads as stuck.
- Fix: one README sentence, or take an optional `[workdir]` like `preflight`/`receipt` and add a case.

**L11. bin/blast-off's `# Exit:` block does not list 11 or 12**
- Location: bin/blast-off:37-42 (unchanged); the usage line at 11-13 names them.
- Failure path / evidence: by design. The block is the runner's range, and 70-docs counts exactly 10 codes. A reader who checks `--help`'s Exit block for wait's codes will not find them there, only in the usage line.
- Fix: none required. Optionally add `wait: 0 · 11 · 12, see usage` outside the counted pattern.

### Open questions for the owner

1. **Timer `elapsed` (H2):** confirm on real systemd that a fired `systemd-run --user --collect --on-calendar=... ` timer whose service failed stays `ActiveState=active` (SubState `elapsed`). If yes, should `wait` treat an elapsed timer as not armed (12), and should `unit_resume` stop the timer on its failure paths too?
2. **Q1 carry-over:** paused-cap is 12 (stuck), never 0. The issue says "exit 0 on a terminal status" and lists "paused" among the returns. Keep 12, or make paused-cap 0?
3. **Transient failures (M5):** should a bus error or a momentarily empty checkpoint.md retry on the next poll, or exit with its own code? Today it exits 1, which the README calls "fix the path".
4. **Real-systemd coverage (M3):** is one `wait` assertion in 11-unit-smoke acceptable (it already starts and stops a real unit), or does 13-wait stay fake-only by policy?
5. **Clock guard (M2):** is a static `declare -f` grep for clock reads in `unit_wait`/`wait_snap` acceptable as the sleep criterion's mutant killer, given `faketime` is not a dependency?
