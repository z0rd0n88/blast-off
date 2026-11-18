# Multi-Agent Review, round 2 (narrow): fix commit d059301 (phase 5, issue 39): lib/chain.sh + lib/preflight.sh + tests/10-chain-done.sh + tests/21-soft-cap.sh + tests/50-checkpoint-size.sh + tests/60-preflight.sh + docs/spec.md (fix diff 35c07d3..d059301, phase base c4e2a41)

## Executive Summary

Two reviewers, code-reviewer and security-reviewer, reviewed the round-1 fix diff `35c07d3..d059301` by static work only, in the context of the whole phase diff `c4e2a41...d059301`. The fix addressed P5R1-1, -4, -5 and -9 under owner decisions Q3 (every JOB_* number with a leading zero is refused) and Q5 (a child-count refusal never shows the file's content). After dedupe there are **0 CRITICAL, 0 HIGH, 0 MEDIUM and 17 LOW**. No refutation round ran. The review unit confirmed six claims by grep or by reading (marked below); no mutant runs were needed.

**Headline.** Both reviewers find all four targeted findings closed:

- **P5R1-4.** `chain_nums` now uses `^(0|[1-9][0-9]{0,8})$` for all six JOB_* names, and every arithmetic use of a JOB_* value comes after it, in both `run` and `preflight`. No other subcommand (`status`, `resume`, `start`, `receipt`, `ci-wait`, `logs`) does arithmetic on them. Both callers handle the new `return 1` with `||`, so `set -e` cannot trip. Nothing in the repo passes a leading-zero JOB_* value except the new negative tests in 21 and 60.
- **P5R1-5.** `chain_count` is the only reader of `child-count`. `cat`'s stderr goes to `/dev/null`, the content is used only in the regex test (which fails on anything multi-line), and `stat` prints digits or, on failure, only a path and an error. No code turns on `set -x`. The fixer's mutant M2 shows tests 10 and 60 fail if the content comes back.
- **P5R1-1.** The soft `4 2` case and the hard `5 5` case (running and paused-cap) each kill one named mutant. code-reviewer checked the numbers by hand against `run`'s cap tests.
- **P5R1-9.** Fixed. It was a latent false failure only, so no test fails on revert.

**What the fix made worse.** One thing: P5R2-1. Values the old runner accepted, such as `JOB_MAX_CHILDREN=08`, are now refused, and under `start` or the resume timer that refusal still reaches only the journal (round-1 P5R1-6, open). A job paused before this lands, with such a value in the unit env, would never resume, and `status` would keep showing `paused-limit` past its time.

**Docs.** Mostly true. The early preflight refusal contradicts test 60's header and points "above" to a table that is below (P5R2-6, P5R2-7). The "byte size and shape" promise does not hold for the cannot-read branch (P5R2-6). README and `--help` do not mention the no-leading-zero rule (P5R2-8).

The gate passes: `GATE: PASS passed=18 failed=0 shellcheck=ok`, exit 0.

**Recommended action: merge (optionally with the small LOW test and doc fixes).** Nothing blocks.

## Critical Findings

None.

## High Findings

None. Both reviewers list CRITICAL, HIGH and MEDIUM as none.

## Medium Findings

None.

## Low Findings

"cr" is code-reviewer and "sr" is security-reviewer. "Confirmed" means the review unit checked it by grep or reading. Every other row was traced by the reviewer's reading only (UNREPRODUCED).

| ID | Severity | Title | Location | Reviewer(s) | One-line description |
|---|---|---|---|---|---|
| P5R2-1 | LOW | The fix makes P5R1-6 a little worse: a leading-zero JOB_* the old runner took is now refused, and under `start` or the resume timer only the journal shows why | `lib/chain.sh:146`; `lib/units.sh:28-32` | cr (CR2-1) | Worst case: a job paused before this lands, whose unit env has e.g. `JOB_MAX_CHILDREN=08`, never resumes; `status` shows `paused-limit` past its time and run.log's last line is the old run's. Fix: `log` the `NUMS_ERR` refusal to run.log too, or settle owner question Q2. |
| P5R2-2 | LOW | The "never show the content" rule is pinned by one word | `tests/10-chain-done.sh:125`; `tests/60-preflight.sh:143` | sr (SR2-1) | Both checks grep only `job done`, the second line. A change that echoes just the first line, or a one-line file (a secret behind a symlink), passes every test. Fix: also assert the first line (`1 0` with a unique marker) is absent, or use a one-line marker file. |
| P5R2-3 | LOW | Test 60's leading-zero case does not pin "before any other line" | `tests/60-preflight.sh:146-150`; `lib/preflight.sh:15` | cr (CR2-4) | It checks exit 1 and the refused line only. Moving `chain_nums` below the `job:` and `flags:` lines still passes. Fix: assert p13.out is exactly one line, or has no `^job: ` line. Confirmed by reading. |
| P5R2-4 | LOW | The new cannot-read refusal wording is untested | `lib/chain.sh:127-129` | cr (CR2-5) | Reverting to the old `cat 2>&1` form, which could carry partial content, passes every test. **Confirmed:** no test greps `cannot read` for child-count (the only hit is an unrelated comment in `tests/41-ci-wait.sh:94`). Fix: add a directory or unreadable-file case asserting the new text. |
| P5R2-5 | LOW | No test refuses a leading-zero `JOB_RESUME_MARGIN` or a bad `JOB_API_BACKOFF` | `lib/chain.sh:91`; `tests/21-soft-cap.sh:86` | sr (SR2-11) | `JOB_RESUME_MARGIN` is the value whose arithmetic actually read `010` as 8. Dropping either name from `chain_nums`'s list goes unnoticed. **Confirmed:** tests set them only to valid values (`tests/30-paused-limit.sh:9,52,128,135`, `tests/31-resume-after-reset.sh:9`). Fix: add `JOB_RESUME_MARGIN=010` and `JOB_API_BACKOFF=x` to the test 21 loop. |
| P5R2-6 | LOW | Spec wording: "exit 1 above" points the wrong way, and the "byte size and shape" promise does not cover the cannot-read branch | `docs/spec.md:56`, `:61`; `lib/chain.sh:121` comment | cr (CR2-2), sr (SR2-5) | The exit-code table is §3 (`docs/spec.md:84`), below the §2 preflight row at line 56 (**confirmed**). The spec and comment say a refusal gives the byte size and shape; the cannot-read refusal gives neither, and its cause list ("a dangling link, a directory, or no read permission") misses a symlink loop, a socket or an I/O error (sr). Fix: "exit 1 in §3"; scope the size/shape wording to the garbled branch; "for example" in the cause list. |
| P5R2-7 | LOW | Test 60's header says every line is still printed on exit 1 | `tests/60-preflight.sh:7-8` | cr (CR2-3) | False now for a bad JOB_* count, which prints only the refused line. **Confirmed** by reading the header. Fix: add the exception. |
| P5R2-8 | LOW | README and `--help` do not mention the no-leading-zero rule or the early refusal | `README.md` (preflight refusal list); `bin/blast-off` (`--help` env list) | cr (CR2-6) | An owner reading either would not learn that `08` is now refused. Fix: one clause in each. |
| P5R2-9 | LOW | `NUMS_ERR` prints the raw JOB_* value; a newline in it can put a bare `preflight: ok` line on stdout or a fake journal line | `lib/chain.sh:93`; `lib/preflight.sh:15` | sr (SR2-2) | Owner input only, and the exit code stays 1, but a script that greps stdout for `^preflight: ok` would be fooled. Fix: `printf %q` the value, or the `head -c 64 \| tr -c '[:print:]' '?'` pattern from `lib/usage.sh:33`. |
| P5R2-10 | LOW | The byte size follows a symlink and shows the linked file's length | `lib/chain.sh:131` (`stat -Lc %s`) | sr (SR2-3) | Within Q5 ("file and byte size only"). Negligible value, since a child that can plant the link can read the target itself. Informational. |
| P5R2-11 | LOW | The byte size is a second read of the file and can disagree with what was refused | `lib/chain.sh:131` | sr (SR2-4); fixer's open risk | It reads 0 for `/proc` and other special files, can report another file's size if a child swaps it between `cat` and `stat`, and reads `( bytes;` if `stat` fails (stat's stderr carries only the path and errno). Fix: take the size from `${#c}` (content length after trailing newlines are stripped), or say "about". |
| P5R2-12 | LOW | Owner-enabled xtrace still prints the content raw | `lib/chain.sh:127-130` | sr (SR2-6) | `bash -x` or an exported `SHELLOPTS=xtrace` traces `c=...` and the `[[ =~ ]]` test, newlines included. No code turns it on. Informational. |
| P5R2-13 | LOW | Pre-existing: run.log can still be forged by other child-written text | `lib/chain.sh` (child's last message, non-JSON Stop payload logged) | sr (SR2-7) | Q5's "a second line could forge a run.log line" reasoning covers `child-count` only. Not made worse by this fix. |
| P5R2-14 | LOW | Pre-existing, at the edge of Q3: `JOB_JEV` is not validated | `lib/` (`JOB_JEV` test) | sr (SR2-8) | `00`, ` 0` or `false` read as "not 0", so Jev is on and row text goes to OpenRouter when the owner meant off. Fix: owner question (extend Q3 to `JOB_JEV`). |
| P5R2-15 | LOW | Pre-existing, outside Q3: numeric `BLAST_OFF_*` settings are not validated | `lib/` (`BLAST_OFF_TRUST_SECONDS` and others) | sr (SR2-9) | A garbled `BLAST_OFF_TRUST_SECONDS` means the trust dialog is never answered and each child hangs to its timeout. |
| P5R2-16 | LOW | Pre-existing, owner input, unverified: `JOB_BASE` reaches `git fetch` with no guard against a leading `-` | `lib/preflight.sh` (`behind` line), wherever `git fetch origin "$JOB_BASE"` runs | sr (SR2-10) | A value like `--upload-pack=<cmd>` could be read as an option. Owner's own environment. Fix: `git fetch origin -- "$JOB_BASE"` or refuse a leading `-`. Not verified by the review unit. |
| P5R2-17 | LOW | A `child-count` of `1 0` followed by a NUL byte is accepted | `lib/chain.sh:127` | sr (SR2-12) | Bash drops the NUL in command substitution with a warning that holds no content. No leak. Informational. |

## Issue 39 checklist (round 1's table, updated for this fix)

| Item | Done? | Pinning test | Change in this round |
|---|---|---|---|
| P4R2-1 base read back | Yes | `tests/21-soft-cap.sh:45-52` | none |
| P4R2-2 in-memory BASE at resume | Yes | `tests/21-soft-cap.sh:33,37-43` | none |
| P4R1-2 refusal in run.log | Yes | `tests/10-chain-done.sh:107,110-113`, plus `:120-125` (forged) | refusal now names file and size only |
| P4R1-3 preflight/status show the count | Partly (capped job still passes; owner Q1) | `tests/60-preflight.sh:57,115,119,122-129`; `tests/11-unit-smoke.sh:42` | hard cap and base > 0 now pinned (P5R1-1 closed; mutants M3, M4 killed) |
| P4R1-4 / P4-22b README exit-4 remedy | Yes (docs only) | none | none |
| P4R1-5 missing/dangling; count logged | Yes | `tests/10-chain-done.sh:76,85,110-113` | none |
| P4R1-7 save before launch | Yes | `tests/10-chain-done.sh:156-166` | none |
| P4R2-9 digit bound | Yes | `tests/21-soft-cap.sh:86` | leading zero added (P5R1-4 closed: `08`, `010`, `JOB_CAP_FACTOR=03`; preflight `tests/60-preflight.sh:146-150`; mutants M1, M1b killed) |
| P4R2-10 start_hang pid guard | Yes | `tests/11-unit-smoke.sh:63` | none |
| Rulings P4R2-4, P4R2-11, P4-22a | Held | as round 1 | none |
| P5R1-5 (Q5) content never shown | Yes | `tests/10-chain-done.sh:120-125`; `tests/60-preflight.sh:135-143` | new; mutant M2 killed; one-word pin (P5R2-2) |
| P5R1-9 test 50 grep | Yes | `tests/50-checkpoint-size.sh:37` | latent only, no revert failure possible |

All cited scenarios passed in the gate (`GATE: PASS passed=18 failed=0 shellcheck=ok`, exit 0).

## Open Questions for the Owner

- Q2 (still open, sharpened by P5R2-1): should a bad JOB_* value (now including a leading zero) also go to run.log, or be refused by `start`/`resume` before `systemd-run`, so a paused job does not silently stop resuming? (cr)
- Q8 (P5R2-14, P5R2-15): does Q3's "validate every JOB_* number" extend to `JOB_JEV` and the numeric `BLAST_OFF_*` settings? (sr)
- Q9 (P5R2-9): should `NUMS_ERR` escape or truncate the value, as `lib/usage.sh:33` does, even though it is owner input? (sr)
- Q10 (P5R2-16): guard `JOB_BASE` against a leading `-` before `git fetch`? (sr)

## Notes

- The review ran inline from this unit. Both reviewers are parked agents, so each ran as a `general-purpose` agent that read its definition read-only from `~/.claude/agents-parked/`. Both were held to static work only (print-only one-liners at most) and both returned (2/2). Outputs: `baton-runner/br-1115-issues/review-phase-5-iter-2/{code-reviewer,security-reviewer}.md`.
- No synthesizer, refutation or auditor agent: I deduplicated and wrote this report myself. CR2-2 and SR2-5 merged into P5R2-6. Severity is the highest any reviewer filed.
- My checks (grep and reading, no scenario runs): P5R2-3, -4, -5, -6 (§ placement), -7 confirmed. No mutant run was needed, so the only test run in this unit was the gate.
- Round-1 findings P5R1-6, -12, -26, -29 are still open; security-reviewer finds this fix did not make them worse except P5R1-6 via P5R2-1 (code-reviewer).
- Reviewer side effects: none. After both returned, `git status` outside `baton-runner/` was empty, HEAD was still d059301, and the review dir held exactly the two files.
