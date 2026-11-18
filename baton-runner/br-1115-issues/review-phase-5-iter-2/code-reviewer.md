# code-reviewer: phase 5 review round 2 (fix diff 35c07d3..d059301, issue 39)

Static review only. Read: the fix diff, the phase diff context, `lib/chain.sh`, `lib/preflight.sh`,
`lib/units.sh` (status, unit env), `lib/usage.sh` callers, `bin/blast-off` header, `tests/lib.sh`,
the changed tests, `docs/spec.md` rows, `README.md`, `skills/blast-off/SKILL.md`, `.github/workflows/ci.yml`,
round-1 report and fix baton. Print-only regex checks run with `bash -c` (results below). Nothing
executed against the repo; no tests run.

## Verdict on the four targeted findings

| Finding | Closed? | Would the new test fail on revert? |
|---|---|---|
| P5R1-4 (leading zero read as octal) | Yes. `chain_nums` regex `^(0|[1-9][0-9]{0,8})$` covers all six JOB_* names; every arithmetic use of a JOB_* number (`chain_cap` factor, preflight `left`, `usage_pause` margin) runs only after `chain_nums` in `chain_run` / `preflight_run`. `status`, `start`, `resume` do no JOB_* arithmetic. | Yes. Test 21: `08`/`010`/`03` all exit 0 on the old regex (fixer's RED shows `08`). Test 60 p13: `08` aborted preflight with no `refused` line, `010` passed; both fail `has`. `0` stays allowed (tests use `JOB_MAX_CHILDREN=0`, `JOB_RESUME_MARGIN=0`), so a regex that drops `0` would also be caught. |
| P5R1-5 (refusal echoed content) | Yes for the shape refusal and cannot-read refusal. `cat ... 2>/dev/null` drops cat's stderr; COUNT_ERR now carries only the path, `stat -Lc %s` size and wanted shape. No other reader of `child-count` exists (`grep child-count lib bin`: only `chain_count`, `chain_count_set`, the cap message, comments). No `set -x`/xtrace anywhere. `stat`'s own stderr (on failure) names only the path. | Yes. Test 10 `badcount-forged` and test 60 p10 grep `job done` out of run.log, stdout+stderr and status / preflight output; fixer's mutant M2 (content back in COUNT_ERR) fails both. |
| P5R1-1 (`left` unpinned) | Yes. p11 (soft running `4 2`, cap 9, want 7) kills `b=0`; p12 (hard `5 5`, cap 12, running and paused-cap, want 7) kills `(CAP_SOFT ? b : 0)` -> `b`. Arithmetic checked by hand against `chain_run`'s cap tests: 9-4+2 = 7 children (5..11); hard 12-5 = 7 (6..12). | Yes (mutants M3, M4 in the fix baton). These pin existing behaviour, so they pass on the old code by design. |
| P5R1-9 (test 50 loose grep) | Yes. `child 2 launched` matches neither `child-count: ...; next child 2` nor `child 12 launched` / `child 20 launched`. | No test can fail on revert (the grow job is fresh, so the old grep passed too); this was a latent false failure, as round 1 said. |

Regression sweep (focus item 2):

- Leading-zero JOB_* values in the repo: none outside the new negative tests. Searched `bin lib tests templates docs README.md skills .github` for each of the six names followed by `=`/`:`/space and `0[0-9]`; the full value list in tests is `0, 1, 2, 5, 30, 50, 60, x, 9x, 2O, 20-digit, 1000000000` plus the new `08, 010, 03`. `ci.yml` only unsets JOB_* names. No unit file or template sets a JOB_* default (`lib/units.sh:20-23` passes names only).
- `chain_nums` now returns 1 instead of `die`: its only callers are `lib/chain.sh:146` (`|| die "$NUMS_ERR"`) and `lib/preflight.sh:15` (`|| { echo ...; exit 1; }`), both in `||` context, so set -e cannot fire inside it and the failure cannot be swallowed. `${!v}` inside NUMS_ERR is reached only when the value is set (unset reads as `0` and matches), so `set -u` is safe.
- No test greps the old `die` prefix for this message; test 21 greps `is not a whole number`, test 30's `9x` case checks only exit 1 and no child.
- Print-only regex check: `0` y, `00` n, `08` n, `010` n, `7` y, `123456789` y, `1234567890` n, ` 5` n, `5 ` n; the forged two-line content does not match the count regex.

## Findings

0 CRITICAL, 0 HIGH, 0 MEDIUM, 6 LOW.

### CR2-1 [LOW] P5R1-6 widened: values the old runner ran with now fail silently under `start` and the resume timer

- File: `lib/chain.sh:92-93,146` (refusal via `die`, stderr only); `lib/units.sh:19-23` (`start` / resume pass JOB_* by name, never validate).
- Failure path: before this fix, `JOB_MAX_CHILDREN=08`, `JOB_CHILD_TIMEOUT=0600` or `JOB_API_BACKOFF=0600` ran: their uses are `[ -gt ]`, `[ -le ]` and `sleep`, all decimal (the fixer's RED for test 21 shows `08` running to exit 0). Now `chain_run` refuses them through `die`, before the lock, to stderr only. Under `start` the command still reports success and the unit dies at once; run.log's last line is the previous run's. Worst case is a job paused (`paused-limit`) before this change lands, with such a value stored in its resume timer's environment: the timer fires, the runner exits 1 before the lock, the pause is never cleared, and `status` shows `paused-limit` past its time with the reason only in `journalctl`. This is round 1's P5R1-6 (owner question Q2), not a new defect, but this fix adds a class of previously-accepted input that reaches it. `preflight` now refuses these values first, which covers new jobs whose owner follows SKILL step 6.
- Fix: as P5R1-6 suggests: `log` the NUMS_ERR refusal too (`chain_nums || { log "$NUMS_ERR" >&2; exit 1; }`, as the count refusal does at `:148`), or have `unit_check` run `chain_nums` before `systemd-run` (owner Q2).

### CR2-2 [LOW] spec preflight row points "above" to an exit-code table that is below it

- File: `docs/spec.md:56` (preflight row): "A `JOB_*` count `run` refuses (exit 1 above) is refused at once, before any other line".
- Failure path: the preflight row is in §2 (CLI, line 41ff); the exit-1 row that defines the JOB_* rule is in §3 (line 89), below it. The §2 `run` row (line 49) does not mention JOB_* refusal at all. A reader following "above" finds nothing. Same row also keeps "(exit 1, every line still printed)" before the new exception; the exception sentence does follow, so it is consistent, but the order reads as a contradiction until the end of the row. Related: `docs/spec.md:61` says the count refusal gives "the file's name, byte size and the shape it wants"; the cannot-read refusal (`lib/chain.sh:128`) gives the name and possible causes, no size or shape.
- Fix: "(exit 1, §3)" or "(as `run` refuses it, exit 1 in §3)"; optionally "(exit 1; every line still printed, except ...)". For line 61: "the file's name (and, for a file it can read, its byte size and the shape it wants)".

### CR2-3 [LOW] test 60 header now false for the bad-JOB_* case

- File: `tests/60-preflight.sh:7-8`: "Exit 1, every line still printed, when the estimate is over what is left of the seven_day window or a launch would refuse (CLAUDE_FLAGS empty)".
- Failure path: a bad JOB_* count is a launch that would refuse, and the fix makes preflight print only the `preflight: refused:` line (`lib/preflight.sh:15`), which p13 (`:146-150`) now tests. The header claims every line is printed. (P5R1-23, open, already notes the header omits the child count; this is a new inaccuracy the fix introduced.)
- Fix: add "; a bad JOB_* count refuses before any other line" to the header.

### CR2-4 [LOW] "before any other line" is not pinned by test 60

- File: `tests/60-preflight.sh:146-150` (p13); contract at `lib/preflight.sh:14-15`, `docs/spec.md:56`.
- Failure path: p13 asserts exit 1 and the `preflight: refused: JOB_MAX_CHILDREN='<v>' ...` line only. A mutant that moves `chain_nums || { echo ...; exit 1; }` below the `job:`/`flags:`/`model:`/`level:` lines (anywhere before `chain_cap`) passes p13 while breaking the spec's "refused at once, before any other line". (A mutant that turns it into `probs+=` is caught: `08` then aborts in `$((...))` with no refused line.)
- Fix: in the loop, `[ "$(wc -l < p13.out)" -eq 1 ]` or `! grep -q '^job: ' p13.out`.

### CR2-5 [LOW] the reworded cannot-read refusal is unpinned

- File: `lib/chain.sh:127-129`; only test: `tests/10-chain-done.sh:110-113` (dangling link) greps the path alone.
- Failure path: reverting to the old `c="$(cat "$f" 2>&1)" ... COUNT_ERR="cannot read $f: $c"` passes every test. For the dangling link `$c` is only cat's error text, so the practical leak is small (cat would have to fail after partial output, e.g. an I/O error mid-read), but the Q5 rule "never the content" holds for this branch by code only.
- Fix: in the dangling-link case also assert the new wording, e.g. `grep -q "cannot read $JOB/child-count (a dangling link" "$JOB/run.log"`, and that `No such file` (cat's stderr) is absent.

### CR2-6 [LOW] owner-facing docs do not state the new JOB_* rule or the new preflight refusal

- File: `README.md:59-60` (preflight refusal list: `CLAUDE_FLAGS`, dependency, estimate); `bin/blast-off:15-24` (`--help` env list with defaults, no format rule).
- Failure path: an owner who sets `JOB_CHILD_TIMEOUT=0900` (which ran before this fix) now gets exit 1 from `run`/`preflight`; neither the README nor `--help` says JOB_* numbers must be plain decimal with no leading zero, or that preflight refuses a bad one before printing anything. The error message itself is clear, so impact is small; the README list was already partial (it omitted the garbled child-count, as the fixer noted), and this adds one more omission.
- Fix: one clause in README's preflight paragraph ("a `JOB_*` number that is not plain decimal, at most 9 digits, no leading zero") and/or one line under `env:` in `bin/blast-off`.

## Checked and not filed

- `stat -Lc %s` through a symlink reveals the target's byte size in run.log: the owner's Q5 ruling allows the size. It runs only after `cat` succeeded, in `||`/`if` context, so a `stat` failure cannot abort under set -e; a delete between `cat` and `stat` would print `( bytes;`, cosmetic and racy only.
- `NUMS_ERR` echoes the raw env value (possible newline) to preflight stdout / stderr: owner's own environment, not the file; the fixer already lists it. Not child-count content.
- Early preflight refusal hides other problems (missing brief etc.) in that run: matches the spec's "refused at once".
- p9 now runs with status `running` (p11 reset it) instead of `paused-cap`: irrelevant to a garbled refusal.
- `has` uses `grep -E`, so `\\(2 bytes; ` is a literal paren; `$JOB` paths contain only mktemp-safe characters.
- `pfhard` preflight runs do not assert exit code (fixer noted); they pin the child-count line, which is the finding's purpose.
- `BLAST_OFF_*` numbers are outside Q3 and are used only with `[ -lt ]` / `timeout`, which read decimal: no octal path.

## Review Summary

| Severity | Count | Status |
|----------|-------|--------|
| CRITICAL | 0     | pass   |
| HIGH     | 0     | pass   |
| MEDIUM   | 0     | pass   |
| LOW      | 6     | note   |

Verdict: APPROVE. The four targeted findings are closed, and the tests for P5R1-1, -4 and -5 fail on revert. P5R1-9 cannot fail on revert by its nature. Only LOW items remain: CR2-1 is round-1 P5R1-6 (owner Q2), slightly widened by this fix; the rest are doc and test-pinning gaps.
