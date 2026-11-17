---
source: runner
scope: br-1115-issues
parent_session: ""
---
# Pass-Baton: phase 3 fix 2 (issue 26): COMPLETE, both owner rulings implemented, 4 HIGH fixed, 39 findings dispositioned, gate green

**Date:** 2026-11-15
**Scope:** br-1115-issues
**Branch:** feat/br-1115-issues/phase-3
**Worktree:** /home/alex/blast-off/.claude/worktrees/pending-items-53932d
**HEAD:** e8587c2 chore(phase-3): owner rulings recorded; run resumed (nothing committed by this unit; the manager owns git)

## Where things stand

STATUS: COMPLETE. This unit continues a fix unit that died on an API error before it wrote a baton. Its work was read back from the diff against HEAD and its two logs, and is kept: nothing was reverted. The four HIGH findings are fixed under the owner's rulings, each with a test that fails without the fix; every MEDIUM has a disposition; LOW findings are listed. This unit added one test case (a table with no rows) and one clause in the spec's test table, then ran six mutants and one full `tests/run`: `GATE: PASS passed=18 failed=0 shellcheck=ok`, after the last tracked edit. Nothing is committed: the 15 tracked files are waiting on the manager, who owns git. Blocking state: none.

### Reconstruction (what the dead unit left)

- 15 tracked product files modified, uncommitted (list under "Files changed").
- `fix-phase-3-iter-2/red-41-51.log` (23:38:19): RED evidence. New tests 41 and 51 run against HEAD's code with `fail()` not exiting: 30 FAIL lines for 41, 7 for 51, 3 brief pins at count 0. Line numbers below are of that file.
- `fix-phase-3-iter-2/tests-run-full.log` (23:41:48): a full `tests/run`: 18 PASS lines, `GATE: PASS passed=18 failed=0 shellcheck=ok`, no FAIL block.
- mtimes: the newest tracked product file was `tests/51-templates.sh` at 23:38:19, before that full run. So the dead unit's last full run postdates its last tracked edit. It recorded no ExecStart check.
- `shellcheck` on the ten touched shell files (by me): nothing at warning level; info notes only (SC1091, SC2015, SC2016), the level the gate (`-S warning`) does not count.

### HIGH findings (all four fixed under the rulings)

| ID | Disposition | Fix | Test that fails without it | RED |
|---|---|---|---|---|
| P3R2-1 | SUPPORTED, fixed (ruling 1) | `lib/ci.sh:68-84`: `ci_check` walks every done row (`cp_done_cells`, `lib/checkpoint.sh:37-46`) and refuses, exit 10, a row whose Status cell has neither `PR #<n>` nor `no PR`, with the words to write; also a cell with both. The whole-file fallback is deleted | `tests/41-ci-wait.sh` cases `np` (neither; message pinned), `mx` (row 0 `PR #8` green, row 1 neither, PR #7 only in prose with a red record in the job: exit 10; with `no PR` written it passes and PR #7 is not read, as ruled), `dup` (second row of a repeated key), `both` | lines 7-11, 14, 15 (`mixed rows, one with neither (P3R2-1): exit 0, want 10`) |
| P3R2-2 | SUPPORTED, fixed by removal (ruling 1) | No code reads a PR outside the Status cells of done rows: `ci_prs` is called at `lib/ci.sh:71,83` only, on cells. The fallback, its hint and its log lines are gone | `lk` (a `no PR` row, `o/other PR #99` and `https://github.com/o/other/pull/99` in prose: exit 0, no `PR #99` or `pull/99` in run.log, no `gh pr view 99` call); `nt` (no table, PR #7 in prose: refused for having no done row, PR #7 not read); `fin` (PRs 96 to 99 never viewed by gh) | lines 4, 5, 12, 13 |
| P3R2-3 | SUPPORTED, fixed (ruling 2) | `lib/ci.sh:89-95`: on an absent record, `git ls-tree -r <record head_sha>^{commit} -- .github/workflows` in the workdir's repo decides. No file: passes, logged `no CI runs and no workflow file at its head <sha> (no CI configured; absent, not a pass)`. A file: exit 10. Commit not readable or workdir in no git repo: exit 10, the message says which and (for a missing commit) `git -C <top> fetch origin pull/<n>/head`. The refusal adds: if no workflow can start on this PR there is no override, ask the owner | `wf` block of test 41: no file at the PR's head passes; a workflow file at the workdir's HEAD that the PR's head lacks still passes; PR head moved to the commit with `release.yaml` is refused; remedy text pinned; workdir a subdirectory; file removed at HEAD still refused; a green record passes; head not in the repo refused; `d4` (outside git refused) | lines 2, 24-31 |
| P3R2-4 | SUPPORTED, fixed (ruling 1) | `templates/checkpoint.md:27-34`: "Every closed row's Status cell names the phase's own PR, as `PR #<n>` (or its /pull/<n> link), or says `no PR`. Write `no PR` only for a phase that opened no PR. The runner refuses done (exit 10) for a closed row with neither ..." | `tests/51-templates.sh:74-82`: four phrases pinned, and `gets no CI check`, `unless no Status cell` must be absent | lines 36-42 |

Notes the next review should not read as misses:

- **"Done row" for a job with no table or no rows: the fail-closed reading.** `lib/ci.sh:82` refuses `status: done` (exit 10) when the Phase plan has no done row at all. Stated in `docs/spec.md:97` ("refusing the job with no done row is this build's fail-closed reading of that ruling, which names only done rows") and in the exit 4 rows of the spec and README. Tested: `nt` (no table), `hd` (heading `## Phase Plan`, rows not read), and `nr` (a table with a header and no row, no PR named anywhere), which this unit added at `tests/41-ci-wait.sh:166-168`. RED lines 4, 6; for `nr`, `fix-phase-3-iter-2/mutants-41.log`: under HEAD's code `FAIL: table with no rows: exit 0, want 10`. A table whose rows are all open is the older exit 9 (`status done but phase row <k> is not done`).
- **A row whose key is no digit (`P1`) is still not a row.** `fin` in test 41 keeps pinning that such a row's `PR #96` is not read (round 1 asked for that test, P3R1-17). The spec and the template define a row as digit-keyed; the rulings do not change row recognition (P3R1-29, pre-existing). Deliberate limit, open.
- **"It reads PRs nowhere else in this file" (template, pinned) is not a way round the gate.** A closed row must now say `PR #<n>` or `no PR` or done is refused, and the template allows `no PR` only for a phase that opened no PR. Moving a PR to prose gets a refusal, not a pass.
- **"Existing checkpoints add `no PR`" (ruling 1).** The repo tracks no checkpoint but `templates/checkpoint.md` (`git ls-files`); its rows start open and its rule text now asks for `PR #<n>` or `no PR`. Every test fixture and the fake child that close a row were updated (`tests/21`, `32`, `40`, `41`, `tests/fakes/claude`). For the manager and owner: a live job dir outside this worktree is refused at `done` (exit 10) once this lands, until each of its done rows says `PR #<n>` or `no PR`; the refusal line says what to write. I could not edit those (outside my write area).
- **Ruling 2 departs from issue 26's wording** ("when HEAD has `.github/workflows/*`"); `docs/spec.md:97` says so and why.

### MEDIUM findings

| ID | Disposition | Reason / where |
|---|---|---|
| P3R2-5 | SUPPORTED, fixed | `grep -a` in `ci_prs` (`lib/ci.sh:104`); test `nul` (RED line 23). On this box (gawk) the case ends exit 10: the row is read as done, bash drops the NUL, PR #7 is read and has no record (`PR #7 CI unread`, seen in the baseline run of `mutants-41.log`). The test also allows 9, for an awk that cuts the line at the NUL so the row reads as open. The prose half is MOOT (prose is not read) |
| P3R2-6 | SUPPORTED, fixed | `lib/ci.sh:72-73` refuses a done Status cell holding any `#<digit>` or `/pull/` beyond the tokens read; a cell with no token and no `no PR` is refused as "neither". Tests `sp1` to `sp7` (`PR #8, #7`, `PRs #7, #8`, `PR 7`, `#7`, `PR: #7`, `PR  #7`, `no PR (#7 dropped)`); RED lines 16-22. Residue, open: a second PR written with no '#' beside a valid token or `no PR` (`PR #8 and PR 7`) is not seen |
| P3R2-7 | SUPPORTED, fixed (ruling 2) | The record's `head_sha` is read, not HEAD or the working tree (tests: "workflow file at HEAD, none at the PR's head", "removed at HEAD"). Not closed, by the ruling's own key: a workflow file only on the PR's base |
| P3R2-8 | OUT OF SCOPE | Ruling 2 says "hold a file": any file under `.github/workflows` counts (test uses `release.yaml`). Owner question 3 (count only `*.yml`/`*.yaml`; an owner-held override) was not ruled. The refusal now says there is no override and to ask the owner |
| P3R2-9 | OUT OF SCOPE | Pre-existing; no ruling ties a PR to its row's commit. Needs its own design (row sha an ancestor of the PR head); file separately |
| P3R2-10 | OUT OF SCOPE | Pre-existing (P3R1-40): the record file is trusted. Owner decision; file separately |
| P3R2-11 | OUT OF SCOPE | Pre-existing, documented behaviour (`docs/spec.md:58`, P3R1-41): all-skipped records `success` |
| P3R2-12 | SUPPORTED in part | A table or heading the runner cannot read now ends in exit 10 at done (no done row; test `hd`, RED line 6). The second adjacent `## Phase plan` heading hiding rows is the pre-existing parser: OUT OF SCOPE, file separately |
| P3R2-13 | MOOT | The "named elsewhere and not read" path that logged and passed is deleted with the fallback |
| P3R2-14 | SUPPORTED, fixed | Outside git an absent record is refused with a true line (`lib/ci.sh:91`: "the workdir is in no git repo, so whether runs were due ... cannot be read"); test `d4`, RED line 2 |
| P3R2-15 | SUPPORTED, fixed | The `ci_check` comment (`lib/ci.sh:57-67`) and spec row 10 are rewritten to the rule the code keeps; the "never lets done through" and "fails closed (P3R1-1)" claims are gone |
| P3R2-16 | SUPPORTED, fixed with P3R2-4 | The rule is now one fact per sentence with one subject each. Residue, open: the template does not say "last cell" (its table has Status last) |
| P3R2-17 | SUPPORTED, fixed | `skills/blast-off/SKILL.md:34-38`: "when a PR gets no CI runs", and "ask whether the repo's workflows start on the stacked PR branches, and put the answer in brief §2". No test pins this wording |
| P3R2-18 | SUPPORTED, fixed | `templates/brief.md:135-137,145-146`: what to do on `absent` (push once more; if no run starts leave the row open, `status: blocked`), and `no PR` for a phase with none. Pinned in `tests/51-templates.sh:87-88`; RED lines 45-47 |
| P3R2-19 | SUPPORTED, fixed | `README.md:114-119,134`: the exit 10 row names the row case and the PR case with a remedy for each |
| P3R2-20 | SUPPORTED, fixed | Added: the mixed case with a red record (`mx`), mis-spelled cells (`sp1`-`sp7`), a NUL (`nul`); the "not read" log pin is gone; test 51 pins the obligation and forbids the two old sentences. `fin` still pins the `P1` row (see the note above) |
| P3R2-21 | SUPPORTED, fixed for the copy this phase added | `cp_done_cells` in `lib/checkpoint.sh` through the shared `cp_plan_rows`; `lib/ci.sh` parses no table itself. Pinned at `tests/51-templates.sh:31`. The older copies (`lib/preflight.sh:77`, `lib/checkpoint.sh`) are pre-existing: OUT OF SCOPE |
| P3R2-22 | SUPPORTED in part | The owner questions are settled, the full rule is in spec row 10 and the `ci_check` comment. README, template, brief, skill and `bin` header still each state it: ruling 1 names those texts as ones to update, so cutting them to pointers is OUT OF SCOPE here |

### LOW findings

Fixed in passing (each covered by a test or gone with the text):
- P3R2-24: the workflow file in test 41 is now `release.yaml`, and its removal is a commit; the code reads a commit's tree, not the index. That a pathspec narrowed to `ci.yml` is now killed is reasoned from the fixture: I ran no such mutant.
- P3R2-32: MOOT for prose (not read); in a done Status cell such text is refused as a stray `#<n>` (fail closed).
- P3R2-36: the "that heading only" claim is gone from the spec's test table.

Open, not fixed (one line of why each):
- P3R2-23: fake `gh` ignores `--limit`; needs the fake changed, not tiny.
- P3R2-25: `[ -n "$cur" ]` guard untested; pre-existing, not this round's code.
- P3R2-26: dispatch runs left out with no log word; a behaviour change to `ci_runs`.
- P3R2-27: records carry no event; needs a record format change.
- P3R2-28: `ci-pr-N.json.tmp` left by a dying `ci-wait`; fail-closed, pre-existing.
- P3R2-29: refuted by two reviewers (the runner aborts, exit 1, it does not pass); no change.
- P3R2-30: raw `head_sha` and run names in run.log; a change to `log`, wider than this fix.
- P3R2-31: records carry no repository identity; record format change.
- P3R2-33: `BLAST_OFF_CI_HEAD=0` is no timeout; pre-existing, document or default later.
- P3R2-34: BOM hides `status:`; not a fail-open, pre-existing.
- P3R2-35: none needed (`paste` fails closed).
- P3R2-37: "its Status cell is the last cell" holds only with a trailing pipe; parser is pre-existing.
- P3R2-38: none needed now.
- P3R2-39: the `bin` header was reworded for the rulings only; F7 still names `lib/chain.sh`. Wording nits.
- Carried P3R1-30: another repo's `/pull/N` link inside a done Status cell is read as this repo's PR N (refused unless this repo's PR N has a green record of its head). The template says to name another PR in prose, outside the table.

### Files changed (all uncommitted)

By the dead unit: `README.md`, `bin/blast-off`, `docs/spec.md`, `lib/chain.sh`, `lib/checkpoint.sh`, `lib/ci.sh`, `skills/blast-off/SKILL.md`, `templates/brief.md`, `templates/checkpoint.md`, `tests/21-soft-cap.sh`, `tests/32-usage-per-phase.sh`, `tests/40-receipt-required.sh`, `tests/41-ci-wait.sh`, `tests/51-templates.sh`, `tests/fakes/claude`.
By this unit, in two of those same files: `tests/41-ci-wait.sh` (case `nr`, three lines after line 165) and `docs/spec.md:228` (the `41-ci-wait` row now says "no table, a table with no rows, a mis-typed heading"). Untracked, added by this unit: this baton, `fix-phase-3-iter-2/mutants-41.sh`, `mutants-41.log`, `tests-run-full-2.log`.

### Checks by this unit

- **Full run (the last one, after the last tracked edit):** `tests/run`, `BLAST_OFF_TEST_ONLY` unset, alone (`pgrep` printed nothing before it), 07:54:10Z to 07:57:39Z, exit 0. Log `fix-phase-3-iter-2/tests-run-full-2.log`: 18 scenarios PASS, `PASS shellcheck (33 files)`, `GATE: PASS passed=18 failed=0 shellcheck=ok`, no FAIL line. Last tracked edit: `docs/spec.md` at 23:51:01 local (07:51:01Z); the log is 23:57:39.
- **ExecStart check: OK** before my runs, after the mutant runs and after the full run: `ExecStart=/home/alex/blast-off/.worktrees/blast-off-build/bin/blast-off run %f`.
- **Mutants** (`fix-phase-3-iter-2/mutants-41.sh`, output in `mutants-41.log`; scenario 41 only, in a /tmp copy, one run at a time). Baseline `PASS 41-ci-wait`. Six mutants of the new `lib/ci.sh`, all KILLED, first failing assertion each:
  - mA, the no-done-row refusal dropped: `no table: exit 0, want 10`
  - mB, the "neither" refusal dropped: `done row with neither: exit 0, want 10`
  - mC, PRs read from the whole file again: `green records: exit 10` (the `fin` job's prose PRs were read)
  - mD, the workdir's HEAD read in place of the record's head: `workflow file at HEAD, none at the PR's head: exit 10, want 0`
  - mE, the stray `#<n>` check dropped: `Status cell 'PR #8, #7': exit 0, want 10`
  - mF, an unreadable head commit let through: `absent CI, head not in the workdir's repo: exit 0, want 10`
- **RED repeated** with HEAD's `lib/ci.sh` and `lib/checkpoint.sh` under the present tests, `fail()` not exiting: 31 FAIL lines (the dead unit's 30 and the new `nr` case).
- **Method.** The `tdd` skill was not loaded by this unit: the only thing not yet done was the `nr` test case, a test-only change with its RED taken against HEAD's code (above) and no production code written. `tests/70-docs.sh` checks other lines of `SKILL.md`, not step 4's wording (P3R2-17).
- Temp dirs left in place, none deleted: `/tmp/p3f2-mut.UMnZAz`, `/tmp/p3f2-keep.FsFouR`, `/tmp/p3f2-nul.*` (mine), and the dead unit's `scratchpad/red`.

### New dependencies

None. `git ls-tree <sha>^{commit}` is git, already required.

## Next steps

1. Manager: commit the 15 files, then review round 3 (the last): `scripts/gate.sh baton-runner/br-1115-issues/gate-phase-3-iter-3/`, once, alone.

## Open questions / risks

- GitHub's half of P3R2-3 (which commit's workflow file a run uses) is still from recall, not tested against GitHub.
- Owner question 3 (which files count; an owner-held override) is not ruled: P3R2-8 stays open.

## References

- Issue: z0rd0n88/blast-off issue 26
- Rulings: `baton-runner/br-1115-issues/owner-rulings-phase-3.md`
- Review: `baton-runner/br-1115-issues/baton-phase-3-review-2.md`, `baton-runner/br-1115-issues/review-phase-3-iter-2.md`
- RED: `baton-runner/br-1115-issues/fix-phase-3-iter-2/red-41-51.log`; dead unit's full run: `baton-runner/br-1115-issues/fix-phase-3-iter-2/tests-run-full.log`
- Code: `lib/ci.sh:57-105`, `lib/checkpoint.sh:37-46`, `templates/checkpoint.md:27-34`, `tests/41-ci-wait.sh:143-257`, `tests/51-templates.sh:31,74-88`
