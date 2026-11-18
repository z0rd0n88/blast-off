### Summary

I reviewed commit dcee737 against base c4e2a41 (`git diff c4e2a41...dcee737 -- . ':!baton-runner'`, 9 files) and issue 39. The review was static only. I read in full the diff, `lib/chain.sh` (lines 1-215), `bin/blast-off`, `lib/preflight.sh` `preflight_run`, `lib/units.sh` `unit_status`/`unit_resume`, the changed tests, test 50, the work baton `baton-phase-5-work.md`, `phase-5/findings.md`, and the phase-4 iter-1 rows P4R1-14 to P4R1-17 and P4R1-25. I ran read-only `git`/`grep`/`sed` and two bash one-liners that print only: one checks `test -gt` against `$(( ))` on a leading-zero number, the other a multi-line `child-count` through the regex and `log`'s printf. I ran no test, gate, scenario or `blast-off`.

Every issue 39 checkbox and the doc changes for all three rulings are in place. Each new behaviour except P4R1-4 (doc only) has a test that kills its main mutant (table below). Preflight's `left` matches `chain_run`'s cap test in every case the brief lists: soft `paused-cap`, hard cap `5 5`, hard cap at `paused-cap`, and `JOB_MAX_CHILDREN=0`. The one exception is a cap written with a leading zero (M2). The new `child-count:` run.log line matches no other scenario's `child N` check today. Test 50's loose `grep 'child 2' | head -n 1` is latent only (L5).

No CRITICAL or HIGH. Two MEDIUM:
- **M1:** the P4R1-2 fix sends the raw `child-count` content into `run.log` and into `status`/`preflight` stdout. It is read through any symlink and is neither bounded nor escaped. This voids the premise that kept phase 4's P4R1-16 at LOW ("It cannot reach `run.log`"): a link to a secrets file now copies it into `run.log`, and a multi-line file forges timestamped `run.log` lines.
- **M2:** `chain_nums` still accepts leading zeros. Preflight's new `left` does arithmetic on `MAXC`, which reads `010` as octal 8, while `run`'s `test -gt` reads it as 10. With `08`/`09`, preflight aborts mid-output with a bash error instead of a `preflight: refused:` line.

Seven LOW findings follow.

### Findings

#### CRITICAL
None.

#### HIGH
None.

#### MEDIUM

**M1. The garbled-count refusal copies raw, unbounded file content, read through any symlink, into `run.log`, `status` and `preflight` (P4R1-16 made worse by the P4R1-2 fix)**
- Location: `lib/chain.sh:123-125` (`c="$(cat "$f" 2>&1)"`, `COUNT_ERR="$f holds '$c', ..."`); `lib/chain.sh:142` (`log "$COUNT_ERR" >&2`); `lib/preflight.sh:35`; `lib/units.sh:74`; `bin/blast-off:47` (`log` = `printf '%s %s\n' ... | tee -a "$LOG"`).
- Failure path, secret copy: `child-count` is a symlink to a regular file, for example `~/.secrets`. `[ -e ]` follows the link, `cat` reads the target whole, and the regex fails. `COUNT_ERR` embeds the whole file, and `chain_run` writes it with `log` into `$JOB/run.log`. `run.log` is a lasting file: owners `tail`/paste it, `blast-off logs` prints it, and `BLAST_OFF_TEST_KEEP` packs kept job dirs into a CI upload. `blast-off status` and `blast-off preflight` print the same content to stdout. A child Claude session that writes the job dir, a confused tidy-up, or an owner's mistaken `ln -s` can all plant the link. In phase 4 this went to stderr (the journal) only. The phase-4 security row P4R1-16 was kept LOW on the stated premise "It cannot reach `run.log`" (`review-phase-4-iter-1.md:57`; also `:128`: "`die` goes only to stderr, so file content cannot forge `run.log` lines"). This commit removes that premise.
- Failure path, log forging: a `child-count` holding `1 0\n2026-11-17T00:00:00Z job done` fails the regex, because bash ERE `$` anchors at the end of the string. `log`'s printf then writes two lines. The second reads `2026-11-17T00:00:00Z job done', not '<launched> <base>' ...`, a timestamped line beginning with `job done`. A child can write that file. Probe (stdout only): `c=$(printf "1 0\n2026-...Z job done"); [[ $c =~ ^(0|[1-9][0-9]{0,8})\ (0|[1-9][0-9]{0,8})$ ]] || echo GARBLED; printf "%s %s\n" TS "f holds '$c', not..."` printed `GARBLED`, then `TS f holds '1 0` and `2026-11-17T00:00:00Z job done', not...` on two lines. Raw ESC bytes reach the owner's terminal through `status`/`preflight` the same way. `status` already prints the checkpoint header raw, so the terminal half is not new.
- Evidence: `git show c4e2a41:lib/chain.sh` line 121 sent `$c` to stderr only, through `die`. The new line 142 adds `tee -a "$LOG"`. Preflight and status now call `chain_count` at all.
- Suggested fix, smallest: stop echoing the content. Name the shape instead, for example `"$f is not '<launched> <base>' (...)"`. If a sample is wanted, use a bounded escaped one: `c="$(head -c 40 -- "$f")"`, then `printf -v c '%q' "$c"`. Also refuse a non-regular file or a symlink before reading: `[ -f "$f" ] && [ ! -L "$f" ] || { COUNT_ERR="$f is not a regular file"; return 1; }`. That also closes L1. It changes the baton decision "a symlink to a real file is read as before"; that decision is the owner's.

**M2. `chain_nums` accepts leading zeros, so preflight's new `left` arithmetic disagrees with `run` (`010`) or aborts preflight (`08`, `09`)**
- Location: `lib/chain.sh:107` (`^[0-9]{1,9}$`); `lib/chain.sh:105,109` (`MAXC="$JOB_MAX_CHILDREN"`, raw string); `lib/preflight.sh:32` (`local left=$((MAXC - LAUNCHED + ...))`); compare `lib/chain.sh:194` (`[ ... -gt "$MAXC" ]`).
- Failure path: with `JOB_MAX_CHILDREN=010` and `child-count` absent, `run` compares with `test -gt`, which reads 10 in decimal, so 10 children are allowed. Preflight computes `$((010 - 0))` = 8 (octal) and prints `child-count: none, a fresh job; first child 1; 8 left under cap 010`. With `JOB_MAX_CHILDREN=08` (or `09`), `$((08 ...))` is a bash expansion error under `set -e`. Preflight exits 1 right after the `cap:` line. Nothing from `timeout:` on is printed, and there is no `preflight: refused:` line, against the spec's "exit 1, every line still printed". `run` with the same value works and caps at 8.
- Evidence: one-liner probe printed `test: 9<=010 => decimal 10`, `arith: 8`, then `08: value too great for base (error token is "08")`, `rc=1`, and never reached `survived`. The work baton names this class only for `JOB_CAP_FACTOR=08` ("predates this phase and is noted only"). The `MAXC` arithmetic in preflight is new in this commit. `chain_count`'s own regex already rejects leading zeros (`08 0` is in test 10's garbled list), so the two validators disagree.
- Suggested fix: `chain_nums`: `[[ ${!v:-0} =~ ^(0|[1-9][0-9]{0,8})$ ]]`, the same shape as `chain_count`. Add `JOB_MAX_CHILDREN=010` to test 21's bad-number loop. Alternative: `$((10#$MAXC ...))` in preflight, but that leaves `JOB_CAP_FACTOR=08` aborting `chain_cap`.

#### LOW

**L1. `status` and `preflight` now hang (or spin) on a FIFO or device `child-count` (P4R1-15 extended to two new paths)**
- Location: `lib/chain.sh:122-123`; callers `lib/units.sh:74` and `lib/preflight.sh:30`.
- Failure path: `mkfifo $JOB/child-count`, or `ln -s /dev/urandom $JOB/child-count`. `[ -e ]` is true, and `cat` blocks on the FIFO open forever or reads without bound. Before this commit only `run` read the file, so `status`, the owner's diagnostic for a stuck job, could not be hung by it. Now `status` and `preflight` hang too. `/dev/urandom` grows the command substitution's memory without limit, and `/dev/zero` spins, since bash drops the NULs.
- Suggested fix: the `[ -f ] && [ ! -L ]` guard and the `head -c` bound in M1.

**L2. The refusal is logged before the lock: beside a live runner it lands in that runner's `run.log`, with an exit reason that hides the lock (P4R1-17 adjacent)**
- Location: `lib/chain.sh:142` (before `chain_lock` at `:151`).
- Failure path: a runner is live (unit active). The owner (or a child) garbles `child-count` and the owner runs `blast-off run <job>` in the foreground. The second process reads the garbled file, appends `<ts> .../child-count holds 'x', ...` to the live runner's `run.log`, and exits 1 without reaching `chain_lock`. A reader of `run.log` sees a refusal line in the middle of a live run, with no `runner exit` line and no word that it came from another process. The live runner goes on, and its next `chain_count_set` silently overwrites the garbled file. The second invocation reports "garbled" when the more urgent fact is "another runner holds the lock". The baton calls this harmless. It does not lose data, but it misleads.
- Evidence: `bin/blast-off:61` sets `LOG` in `job_init` for every command. The `run` path reaches `chain_count` with `LOG` set, and the file is opened with `tee -a`. A missing job dir dies in `job_init` (`bin/blast-off:53`) before `LOG` is used, so no stray `run.log` is created.
- Suggested fix: take the lock first. Read and refuse after `chain_lock` and the trap; the trap would then add the usual `runner exit 1 without a state` line. Or prefix the line with the pid, e.g. `refused (pid $$, before the lock): ...`. Moving the read after the lock also closes P4R1-17's stale-read window.

**L3. Preflight's `left` and status's `next child N` say a done, blocked or still-paused-limit job will launch children**
- Location: `lib/preflight.sh:31-33`; `lib/units.sh:74`; `docs/spec.md` preflight row ("`<n> left under cap <cap>`: what the next run may launch").
- Failure path: a job at `status: done` with `child-count` `3 0` under soft cap 9. Preflight prints `...; next child 4; 6 left under cap 9`, but `run` ends at `chain_end 0` (or 9/10) before any child (`lib/chain.sh:188`). The same holds for `blocked` (exit 3) and for `paused-limit` before its `until` (exit 8, `:175-176`). This does not touch the cap arithmetic, which matches. Only the "what the next run may launch" claim is wrong.
- Suggested fix: append the status when it is not `running`/`paused-cap`, e.g. `(status done: run launches none)`. Or narrow the spec sentence to "under the cap".

**L4. P4R1-3 is half done: a capped job still passes preflight, and the soft and hard caps lack preflight pins**
- Location: `lib/preflight.sh:30-36`; `tests/60-preflight.sh:110-125`.
- Failure path: the issue text is "a garbled or capped job passes preflight and exits at once". The garbled half now refuses. A hard-capped job (`12 0`, no Phase plan) prints `0 left under cap 12`, then `preflight: ok`, exit 0, and `start` then exits 4 at once. The baton files this as an owner question; I list it under Open questions too. Test gaps: (a) no preflight case under the hard cap. Mutant: drop `[ -z "$CAP_SOFT" ] ||` at `:31`, so a hard-cap `paused-cap` job gets a fresh allotment in preflight. It survives, because test 60 is soft-only (cap 9). (b) No soft `running` job with `base` > 0. Mutant: `local b=0` at `:31` survives, because p7 is `9 0` and p8 is `paused-cap`. (c) `p8` does not check `rc`.
- Suggested fix: add a hard-cap `paused-cap` case and a soft `running` `9 3` case to test 60, plus the owner's call on refusing at `0 left`.

**L5. Test 50's loose `grep -n 'child 2' | head -n 1` now also matches the new `child-count:` line of any non-fresh job**
- Location: `tests/50-checkpoint-size.sh:37`; new line `lib/chain.sh:160`.
- Failure path: the `grow` job is fresh, so the new line reads `... first child 1` and the test passes. If the scenario ever reuses a job, or seeds `child-count` with `1 0`, the first `child 2` match is the line `child-count: 1 launched, base 0; next child 2`, which sits before the size warning, and `[ "$w" -lt "$c2" ]` fails falsely. I checked every other `tests/*.sh` run.log grep that names `child` (single- and double-quoted). Every other one uses `child N launched` or a longer exact phrase (`timed out`, `exited without`, `usage:`, `ended on API error`, `left checkpoint.md unchanged`). Neither `child-count: L launched` nor `next child N` matches those, and test 10:174's `tail -n 1` is unaffected. `next child` appears in `next child resumes from checkpoint` and `next child in 5s` (tests 10:49, 30:130/138); the new line holds `next child <digit>$`, so neither matches.
- Suggested fix: `grep -n 'child 2 launched'` in test 50.

**L6. Refusal-to-run.log is pinned only for the regex and dangling-link cases; the stream and the other read failures are unpinned**
- Location: `tests/10-chain-done.sh:104,107,112,115-117`.
- Failure path: (a) The zero-byte case (`:115-117`) does not check `run.log`. (b) Test 10 sends stdout and stderr to the same file (`> badcount.out 2>&1`). A mutant `log "$COUNT_ERR"` without `>&2` survives. It is low impact, since under the unit both streams reach the journal, but it is the documented "on stderr". (c) No case for a directory or an unreadable `child-count` (the `cannot read` branch, `:123`), which is now a distinct `COUNT_ERR` path that preflight and status also print.
- Suggested fix: add `grep -q "$JOB/child-count" "$JOB/run.log"` to the zero-byte case, use `2>badcount.err` for one case, and add a `mkdir "$JOB/child-count"` case.

**L7. Docs and help that this change left behind**
- Location: `bin/blast-off:9,12` (help: `status` is "checkpoint header + unit state"; `preflight` lists "cap, account, ..." without the child count); `docs/spec.md` `run` row (it lists lock, cap log, `paused-cap` reset and the dirty-tree check before child 1, but not the new `child-count:` line or the garbled-count refusal written before the lock); `README.md` exit-4 row (no test pins the two-step remedy, P4R1-4).
- Failure path: the `--help` text no longer matches `status`/`preflight` output. The baton marks the help header P4R1-26 out of scope; I list it so it is not lost. The README's "that start can pause at `paused-cap` before any child ... so `blast-off resume` then" is correct by `lib/chain.sh:171,191-196`. For a hard-capped `12 0` job given a 3-row plan, the first start pauses with exit 6, and resume sets `base` to 12 and continues. No scenario walks that path, so a regression there would pass the gate.
- Suggested fix: update the help lines, add one clause to the spec `run` row, and optionally a test 21 case: no plan, hard exit 4, add a plan, run → 6, run → child 13.

Not re-filed, still open from phase 4 and untouched by this diff: P4R1-14 (`child-count.tmp` written through a planted symlink, `lib/chain.sh:131`); P4R1-17 (count read before the lock, `lib/chain.sh:142` vs `:151`; see L2).

### Issue 39 checklist

| Item | Done? | Pinning test (file:line) | Notes |
|---|---|---|---|
| P4R2-1 `base` read back | Yes | `tests/21-soft-cap.sh:45-53` (`base` job, `2 2` at cap 2 → children 3, 4, pause at `4 2`) | Kills `BASE=0` at `chain.sh:127` (baton mutant MA). |
| P4R2-2 in-memory `BASE` on paused-cap | Yes | `tests/21-soft-cap.sh:32-33,37-41` (`2 0` re-seeded, re-run must reach done) | Kills "file only" mutant MB: in-memory `BASE` 0 → `3 > 2` → exit 6. |
| P4R1-2 refusal reaches run.log | Yes | `tests/10-chain-done.sh:107` (per garbled value), `:112` (dangling link) | Each case uses a fresh `new_job`, so `run.log` holds only the refusal and the grep is not vacuous. The zero-byte case is unchecked, and so is stderr vs stdout (L6). Side effect: M1, L2. |
| P4R1-3 preflight/status show the count | Yes, partly | `tests/60-preflight.sh:57,110-125`; `tests/11-unit-smoke.sh:42` | Garbled → refused: pinned (`p9`). Capped → still `preflight: ok` (L4, owner question). Hard-cap and `base` > 0 preflight mutants survive (L4). Status's garbled branch is unpinned. |
| P4R1-4 / P4-22b README exit-4 remedy | Yes (doc) | none | Wording is correct against `chain.sh:171,194`. No scenario walks hard → add plan → pause → resume (L7). |
| P4R1-5 count logged; dangling link garbled | Yes | `tests/10-chain-done.sh:76,85` (count lines); `:110-113` (dangling link) | Kills dropping `|| [ -L "$f" ]` and dropping `log "$COUNT_SAY"`. |
| P4R1-7 save-before-launch on SIGKILL | Yes | `tests/10-chain-done.sh:158-166` (`1 0` while child 1 runs; KILL rc 137; re-run cap 1 → 4, one launch) | Kills "save in EXIT trap" (MT, MT2). A save between `child_launch` and `child_wait` would survive (baton says near-equivalent). |
| P4R2-9 `chain_nums` 9-digit bound | Yes | `tests/21-soft-cap.sh:86` (20-digit `JOB_MAX_CHILDREN`, 10-digit `JOB_CAP_FACTOR`) | Kills `^[0-9]+$` and `{1,10}`. Leading zeros still pass (M2). |
| P4R2-10 `start_hang` pid guard | Yes | `tests/11-unit-smoke.sh:63` | Baton mutant MG shows it fires. |
| Ruling P4-22a (soft fresh allotment via `base`, hard never resets) | Unchanged, consistent | `tests/10-chain-done.sh:94-97`, `:119-121`; `tests/21-soft-cap.sh` | Preflight follows it (`preflight.sh:31` gates on `CAP_SOFT`). |
| Ruling P4R2-4 docs (exit-4 status may read `running`) | Yes | `tests/10-chain-done.sh:97` (`status: running` after exit 4 from `paused-cap`) | Spec exit-4 column, `chain.sh:98-99` comment and test 21 header (`:4-5`) all reworded. The assertion passes on old code too, which is intended: it pins existing behaviour. |
| Ruling P4R2-11 docs (delete `child-count` = one reset) | Yes | `tests/10-chain-done.sh:76` (missing file → fresh, logged) | Spec env text, README exit-4 row, `chain.sh:116,192-193` comments and `COUNT_ERR`'s "delete it" all say so. |

Work-unit decisions:
- `chain_count` returns instead of dying: sound. Every caller handles the return: `chain.sh:142` with `||`, and `preflight.sh:30`/`units.sh:74` inside `if`. `set -e` cannot fire inside a function called in those contexts. The globals `LAUNCHED`, `BASE`, `COUNT_SAY` and `COUNT_ERR` are set at the top on every path, and `status`/`preflight` use nothing else. `local b` at `preflight.sh:31` re-declares the function's own `b` (declared at `:9`, used only by the deps loop at `:16`), so nothing is shadowed.
- Missing file stays fresh: consistent with P4R2-11, and now visible in `run.log`.
- Dangling symlink garbled: sound. A symlink to a real file is still read; see M1.
- Preflight shows `left` but does not refuse at the cap: an owner call (L4).
- Status shows no `left`: sound, since the caller's env is not the unit's.
- `chain_nums` bounds digits only: see M2. Preflight's new arithmetic makes leading zeros reachable.
- The `2 0` re-seed: sound, and it kills the mutant.

Preflight vs `chain_run` cap check (brief item 3). `chain_run` allows `MAXC - LAUNCHED + (soft ? BASE' : 0)` children, where `BASE'` is `LAUNCHED` after a soft `paused-cap` resume. Preflight matches it in each case:
- soft `paused-cap`: preflight gives `MAXC` (equal);
- hard `5 5` at cap 12: 7 in both (preflight drops `base` under the hard cap);
- hard cap at `paused-cap`: `MAXC - L` in both;
- `JOB_MAX_CHILDREN=0`: soft gives `0 - L + L = 0`, or a clamped negative; hard gives a clamped `-L`, which is 0. Both match `run`'s immediate exit 6 or 4.
- `done`/`blocked`/`paused-limit`: the arithmetic matches, but `run` launches none (L3).
- A leading-zero cap: mismatch or abort (M2).

### Open questions for the owner

1. M1: should a `child-count` that is a symlink to a regular file be refused like a dangling one (baton decision: read it)? And may the refusal echo the file's content, or only name its shape? This also settles P4R1-16.
2. L4: should `preflight` refuse when `0 left`? At least under the hard cap, where `start` exits 4 at once and only a larger `JOB_MAX_CHILDREN`, a Phase plan, or deleting `child-count` goes on.
3. L2: should the garbled-count refusal move after `chain_lock`, so it goes to the lock holder's `run.log` only and ends with the usual `runner exit` line?
