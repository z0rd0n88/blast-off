# Phase 4 review round 2: code-reviewer

Scope: `git diff e766e00..43c5dd8 -- . ':!baton-runner'` (fix round 1), read against the whole phase diff `7867255...43c5dd8`. Static review only: no tests run. The full-gate verdict cited below is the runner's own log, not a run of mine.

**Summary:** CRITICAL 0, HIGH 0, MEDIUM 1, LOW 9. **Verdict: APPROVE with notes.** The P4R1-1 fix is correct: the hard cap now has no reset path through `base` or `paused-cap`. Soft-cap behaviour matches P4-22a. Three of the six rows are only partly closed (P4R1-6, -8, -10), each against a half its own row named and the fixer disclosed. The fix added no runtime regression. It added one small test weakening (F6) and one overstated doc sentence (F7).

## Findings

### F1 [MEDIUM] P4R1-8 residual: reading `base` from the file is still unpinned (test gap)
- **Location:** `lib/chain.sh:123` (`BASE="${BASH_REMATCH[2]}"`), `lib/chain.sh:164`; `tests/21-soft-cap.sh:28-40`
- **Failure path:** after a soft-cap resume, the file holds `L L` and the status is `running`. That run can end before its allotment is used: exit 5, a pre-child exit 7, `stop`, a reboot, or `paused-limit` (exit 8). The next relaunch is then not a paused-cap resume, so `base` comes only from the file. If `:123` regresses to `BASE=0`, that relaunch computes `n - 0 > MAXC` and exits 6 at once with a false "soft cap reached". The owner then needs one extra start. The fixer ran this mutant and it survived test 21: every run in test 21 that reads a nonzero `base` is a paused-cap resume, and that resume sets `base` again at `:164`. The swap mutant (`cp_set_status running` before `chain_count_set`) also still survives. It differs only in the crash window between the two writes, and is harmless there because the resume is idempotent.
- **Suggested fix:** a soft job with status `running` and `child-count` `2 2`, at cap 2 (or after the cap-0 run, `sed` the status to `running` before the final re-run). It must launch child 3, not exit 6.
- **Status:** UNREPRODUCED by me. The fixer's own mutant log in `baton-phase-4-fix-1.md` records the survival.
- Severity is kept at the round-1 row's MEDIUM. The current code is correct; this is a test gap.

### F2 [LOW] P4R1-6 residual: `chain_nums` still accepts any length, and a 20-digit `JOB_MAX_CHILDREN` turns the hard cap off
- **Location:** `lib/chain.sh:90`, `:107`, `:186`
- **Failure path:** `JOB_MAX_CHILDREN=99999999999999999999` with no Phase plan row gives `MAXC` that 20-digit string. `[ "$n" -gt "$MAXC" ]` fails with "integer expression expected" (rc 2). Inside `if` that reads as false, so no child is ever capped: the hard cap is off for that run. I probed it: `if [ 1 -gt 99999999999999999999 ]` takes the else branch. A huge `JOB_CAP_FACTOR` overflows `phases * factor` to a negative cap (probed: `2*4611686018427387904` = `-9223372036854775808`). That fails closed, as an immediate exit 6.
- These values come from the owner's environment, and the behaviour predates this phase. It is listed because the round-1 row's fix named "the same bound in `chain_nums`", and because spec `:61` now says the hard cap "never resets" (F7).
- **Suggested fix:** use the same `^(0|[1-9][0-9]{0,8})$` in `chain_nums`.
- **Status:** reproduced as a bash probe (arithmetic and `test` only), not end to end.

### F3 [LOW] The 9-digit bound is unpinned at its edge
- **Location:** `lib/chain.sh:121`; `tests/10-chain-done.sh:97`
- **Failure path:** the only overflow case has 19 digits. A mutant that widens `{0,8}` to `{0,17}` survives, and so does one that tightens it to `{0,7}`. No in-bound maximum (`999999999 0` accepted) and no first out-of-bound value (`1000000000 0` refused) is tested. I probed both values against the regex: accepted and refused, as intended.
- **Suggested fix:** add `1000000000 0` to the garbled loop. Optionally add a positive `999999999 999999999` case at cap 1, expecting exit 4 with no child.
- **Status:** UNREPRODUCED (mutant reasoning).

### F4 [LOW] Under the hard cap, a `paused-cap` status is still rewritten to `running` and logged as "the chain continues", then the runner exits 4
- **Location:** `lib/chain.sh:164-165`, `:186-187`. Contradicted by `docs/spec.md:91` (row 4, status column "unchanged"), the `lib/chain.sh:97` comment ("exit 4, status kept") and the `tests/21-soft-cap.sh:4` header ("exit 4, status unchanged"). `tests/10-chain-done.sh:90-93` pins neither the status nor the log line.
- **Failure path:** a hard job at its cap with a forged or left-over `status: paused-cap` goes through `run` or `blast-off resume`. `run.log` gets `status paused-cap -> running; the chain continues` and then `child cap N reached`. The checkpoint ends `running`, though the spec says exit 4 leaves the status unchanged. No child launches and `base` does not move, so this is cosmetic and misleading, not a cap bypass.
- The transition itself predates this phase, and the fixer disclosed it. Before this fix the same path launched children.
- **Suggested fix:** keep the transition. `tests/31-resume-after-reset.sh:58-61` resumes a hard-cap (no Phase plan) `paused-cap` job and needs it to reach `running`. Correct the docs instead: row 4's status column could read "unchanged (a `paused-cap` is first set to `running`)", with the same change to `chain.sh:97`. Optionally, skip the "the chain continues" wording when `CAP_SOFT` is empty and `LAUNCHED+1 > MAXC`.
- **Status:** UNREPRODUCED (read from code).

### F5 [LOW] P4R1-10 residual: `start_hang` still has no `[ -n "$pid" ]` guard
- **Location:** `tests/11-unit-smoke.sh:58`, `:61`
- **Failure path:** if the `rm -f "$JOB/child-count"` at `:58` is ever removed, the hung child is child 2. `pid` comes back empty, `gone ""` is true, the child-1 scope never exists, and the stop/trap/kill assertions all pass vacuously. The round-1 row named this guard. The fix deleted only the duplicate line.
- The wrong reason in `baton-phase-4-work.md` (lines 35 and 121) is corrected only in `baton-phase-4-fix-1.md`.
- **Suggested fix:** add `[ -n "$pid" ] || fail "no child=1 line ($1): $(cat "$JOB/fake-marker")"` after `:61`.
- **Status:** UNREPRODUCED (the round-1 reviewer probed the vacuity).

### F6 [LOW] New, introduced by this fix: test 21's resume-log assertion is now satisfied by the cap-0 run
- **Location:** `tests/21-soft-cap.sh:28` (new cap-0 run), `:36` (`grep -q 'status paused-cap -> running; the chain continues' "$log"`)
- **Failure path:** `run.log` is cumulative. The new `JOB_MAX_CHILDREN=0` run logs the same `paused-cap -> running` line before the final re-run. So `:36` no longer shows that the final re-run took the paused-cap branch. Coverage is only partly lost: if the final re-run skipped the branch, its child would record `status_at_start=paused-cap`, and `:37` would catch that.
- **Suggested fix:** `[ "$(grep -c 'status paused-cap -> running; the chain continues' "$log")" -eq 2 ]`.
- **Status:** UNREPRODUCED.

### F7 [LOW] New doc claim: "so it never resets for a job" is stronger than the code
- **Location:** `docs/spec.md:61` (new text); the same wording in the `lib/chain.sh:185` comment
- **Failure path:** the runner's own die message (`lib/chain.sh:122`) tells the owner to "delete it to count this job's children from 0 again". A deleted or dangling file reads as a fresh job (P4R1-5, open). A child can write `0 0` (P4R1-12, open). A 20-digit `JOB_MAX_CHILDREN` turns the cap off (F2). Those findings are open, not worsened, but this sentence now denies them.
- **Suggested fix:** say "never resets on a re-run or a paused-cap resume; only deleting or rewriting `child-count` restarts it".
- **Status:** UNREPRODUCED (docs versus code).

### F8 [LOW] The zero-byte case asserts less than the garbled loop
- **Location:** `tests/10-chain-done.sh:104-106`
- **Failure path:**
  - It does not check that the message names `child-count`. The loop does, with `grep -q "$JOB/child-count" badcount.out`. So any unrelated exit 1 before a child passes.
  - `[ ! -s "$JOB/child-count" ]` is also true if the runner deleted the file, so "left as it was" is not pinned here.
  - The M11 mutant (`-e` to `-s`) is still killed, by exit 4 and a child launching.
- **Suggested fix:** add `grep -q "$JOB/child-count" badcount.out`, and use `[ -e "$JOB/child-count" ] && [ ! -s "$JOB/child-count" ]`.
- **Status:** UNREPRODUCED.

### F9 [LOW] P4R1-11 residual: the `cat`-failure die is untested
- **Location:** `lib/chain.sh:120` (`c="$(cat "$f")" || die "cannot read $f"`)
- **Failure path:** an unreadable `child-count` (mode 000, or a directory) should exit 1 before any child. No test covers it. Round 1 called it near-equivalent, because without the `|| die` an empty `c` fails the regex anyway, though with a less precise message.
- **Suggested fix:** optional `chmod 000` case. Unless the harness runs as root, it must exit 1 with "cannot read".
- **Status:** UNREPRODUCED.

### F10 [LOW] Counter rollover at the 9-digit bound
- **Location:** `lib/chain.sh:121`, `:196`
- **Failure path:** launching child 1000000000 saves a 10-digit `launched`, and every later run refuses it as garbled (exit 1). This is unreachable in practice, and the fixer disclosed it.
- **Suggested fix:** none needed. Optionally add one clause to the spec.
- **Status:** UNREPRODUCED.

## Round-1 closure

| ID | Verdict | Evidence |
|---|---|---|
| P4R1-1 | **Closed** | All three routes are shut. The paused-cap branch moves `base` only under the soft cap (`chain.sh:164`). The hard cap compares `n` alone (`:186`, `CAP_SOFT ? BASE : 0`; probed: hard `6`, soft `1` for `n=6 BASE=5`). Route (a), a forged or left-over `paused-cap` under the hard cap: `tests/10-chain-done.sh:90-93` expects exit 4, no child 3, `2 0`; the fixer's mutant M1a (guard removed) was killed. Routes (b) and (c), a `base` > 0 on a hard job: `basehard` `5 5` at `:108-110`; mutant M1b (hard subtracts `base`) was killed. The exit-4 message (`:187`) is now accurate: the `LAUNCHED` it prints is what the cap compares, so "a larger JOB_MAX_CHILDREN goes on" is true. Cosmetic residue is F4. |
| P4R1-6 | **Partly closed** | `child-count` is bounded to 9 digits (`:121`). The `9223372036854775807 0` case at `10:97` was RED before the fix, and the unbounded-regex mutant was killed (fixer log). Not done: the `chain_nums` bound the row's fix named (F2). The edge of the bound is unpinned (F3). |
| P4R1-8 | **Partly closed** | Write side: the cap-0 run at `21:28-30` expects `2 2`, and mutant M8 (save dropped) was killed. Read side: `BASE=0` at `:123` survives (fixer log), and so does the swap mutant (F1). |
| P4R1-9 | **Closed** | The final re-run in test 21 reads `2 2` from the file. Mutant M9 (`-le` to `-lt`) was killed, and its run died on `holds '2 2'` (fixer log). |
| P4R1-10 | **Partly closed** | The duplicate line was deleted (`11:58` remains, with one comment). The `[ -n "$pid" ]` guard the row asked for is not added (F5). The baton correction is in the fix baton only. |
| P4R1-11 | **Closed** | A true zero-byte file is tested at `10:104-106`. Mutant M11 (`-e` to `-s`) was killed (exit 4, child launched). The assertions are weaker than the loop's (F8), and the `cat` die is untested (F9). |

Open round-1 findings checked for "made worse" (P4R1-2, -3, -4, -5, -7, -12 to -30): **none are worse.**
- P4R1-4: the hard cap no longer moves `base`, so the exit-4 remedy (add a Phase plan, start again) starts from `base` 0 as before.
- P4R1-23 (forged `paused-cap`): this fix made it harmless under the hard cap.
- P4R1-27(a): "two whole numbers" still does not say "no leading zeros". The new spec text keeps the omission without widening it.
- P4R1-5, -12, -18: unchanged, but now contradicted by new spec wording (F7).

## Q3: does the hard cap truly never reset?

`chain_cap` runs once per run (`chain.sh:152`), before the status `case`. The cap mode is therefore fixed for a run, and transitions happen only across runs.
- **Hard job, `status: paused-cap`** (forged, left over, or `blast-off resume`): `base` is not moved, and the cap compares the total. No reset (tested at `10:90-93`). Status residue: F4.
- **Soft to hard with `base` > 0** (rows lost or unreadable after soft pauses): the hard cap counts every child. A job past 12 now exits 4 at once, where before the fix it got up to 12 more. That is the behaviour change P4-22a asks for. `basehard` covers the read side. No reset.
- **Hard to soft** (an owner or child adds a Phase plan row): the soft cap counts from `base` 0, so hard-era children use up the first soft allotment (P4R1-4, open, not worse). After that, paused-cap resumes give fresh allotments, which is soft-cap behaviour under P4-22a. A child that adds a row leaves the hard cap's domain: this is the design, in the P4R1-23 family, and not new.
- **Values written by children:** `0 0` or a deleted file resets the count (P4R1-12 and P4R1-5, open, unchanged). Garbled, negative or huge values fail closed with exit 1 (`:121`).
- **Owner environment:** a 20-digit `JOB_MAX_CHILDREN` turns the hard cap off (F2, pre-existing).
- **Within a run:** a child cannot move `BASE` or `CAP_SOFT`. Both are runner memory, and `chain_count` runs once (`:136`).

No new reset path was found beyond those already filed.

## Q4: soft cap against P4-22a

It matches.
- A paused-cap resume under the soft cap sets `base` to `launched` and saves it before anything else (`:164`).
- A `paused-limit` resume, or any other relaunch, keeps `base` from the file.
- The cap test is `n - BASE > MAXC` (`:186`), and numbering continues from `launched`.
- A failing save inside the guarded brace group still aborts under `set -e` (probed: `[ -z "$x" ] || { ...; f; ... }` with `f` failing exits 1). The runner never proceeds on an unsaved `base`.

## Q5: docs against code

- `docs/spec.md:61`: true, except the "never resets for a job" clause (F7).
- `docs/spec.md:91` (row 4): "unchanged" is false for a hard job at `paused-cap` (F4). The rest is true, including "the cap counts every child of the job across runs".
- `docs/spec.md:93` (row 6): true under the soft cap.
- `docs/spec.md:225` (test 10 row): matches the test, including the paused-cap and `5 5` cases, the zero-byte and newline files, and the overflow value.
- `docs/spec.md:229` (test 21 row): matches the cap-0 run and `2 2`. Its "status unchanged" for test 10 is subject to F4.
- `README.md:136` (exit 4): "counted over every run of the job in its `child-count`" is now true. Its remedy is still P4R1-4 (open).
- `README.md:138` (exit 6): true.

## Acceptance criteria (issue 22)

The full gate `GATE: PASS passed=18 failed=0 shellcheck=ok` is in `baton-runner/br-1115-issues/gate-phase-4-iter-2/tests-run.log`. It was written at 10:43, after 43c5dd8 was committed at 10:39, and `lib`/`tests`/`docs`/`README.md` have no uncommitted changes. I did not run it myself.

1. **A cap reached across two runner runs stops the job (exit 4):**
   - `tests/10-chain-done.sh:81-83`: a re-run at cap 1 exits 4 with no child.
   - `:84-89`: at cap 2, child 2 launches, then exit 4 with `child cap 2 reached`.
   - `:142-143`: after SIGHUP during child 1, a re-run at cap 1 exits 4.
   - `:90-93`: a `paused-cap` gives no reset.
   - Soft analogue: `tests/21-soft-cap.sh:44-49` (exit 6 with no child).
   - **Covered.**
2. **Child numbers in run.log continue after a relaunch:**
   - `tests/10-chain-done.sh:86-87`: one `child 1 launched`, then `child 2 launched` on the re-run.
   - `tests/21-soft-cap.sh:40`: `child 3 launched` after the paused-cap resume, and one `child 1`.
   - **Covered.**
3. **A fresh job starts at child 1:**
   - `tests/10-chain-done.sh:16`: `child 1 launched` on a job with no `child-count`.
   - `:77`: `child=1` in the fake marker.
   - **Covered.** P4R1-24 is still open: no assertion runs against a left-over file.

The new tests are real. `tests/fakes/claude:20-21` writes `fake-marker` before acting on its mode, so the `! -e fake-marker` checks in the noop garbled loop are not vacuous. Each new case was RED or killed a mutant in the fixer's log:
- M1a: `10:93`
- M1b: `10:110`
- M6: `10:97`
- M8: `21:29`
- M9: `21` re-run
- M11: `10:106`

Switching the garbled loop from `step` to `noop` does not weaken the other six values: all of them exit 1 before any child, so the mode is never read.

## Validated

- In `$((n - (CAP_SOFT ? BASE : 0)))`, `CAP_SOFT` is always `1` or empty (`chain_cap` `:101`, `:107`). Empty evaluates to 0 under `set -u` (`bin/blast-off:39`), and the ternary evaluates only the branch it takes. Probed.
- The regex `^(0|[1-9][0-9]{0,8})\ (0|[1-9][0-9]{0,8})$`:
  - accepts `999999999 999999999`;
  - refuses `1000000000 0` and a trailing CR;
  - accepts trailing newlines, which `$(cat)` strips;
  - refuses a leading newline (`^` anchors to the string). Probed.
- The `[ -le ]` after the regex cannot overflow now, since both numbers are at most 9 digits.
- The guard at `:164` is the last element of the `||` list, so `set -e` still applies inside the brace group (probed).
- The new die text is quoted nowhere else (`git grep`). The fixer's blast-radius grep agrees.
- `CAP_SOFT`, `BASE` and `child-count` are used only in `lib/chain.sh` (`git grep` over `lib bin templates README.md`).
- The test 10 paused-cap case runs on the job left at `2 0`, `running`, with no Phase plan, so it is the hard cap.
- The test 21 cap-0 run gets `MAXC` 0 soft, because `-n "0"` is true and phases > 0. It pauses at `n - BASE = 1 > 0` before any launch.
- Test 31's `cap` job (`tests/31-resume-after-reset.sh:58-61`) is fresh and hard-capped, and still passes, because nothing changed for `LAUNCHED` 0.
- The test 11 change is a pure deletion of the duplicate line.

## Not examined

- Running any test, mutant or the gate. All "killed" claims rest on the fixer's log in `baton-phase-4-fix-1.md`.
- `lib/preflight.sh` and `lib/units.sh` `status`, beyond confirming they do not read `CAP_SOFT` or `BASE`.
- `lib/checkpoint.sh` `cp_scan`/`cp_unread`, beyond their use as the cap-mode switch.
- The rest of the phase diff beyond `lib/chain.sh`, the four test files, the spec rows and the README rows named above.
- Open round-1 findings, except to check that none got worse.
