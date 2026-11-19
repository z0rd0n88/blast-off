# Phase 2 (issue 31): `only` dispatch input, filtered tests/run

## Brief
- Target set (tracked): `tests/run`, `tests/00-harness.sh`, `tests/40-receipt-required.sh`, `.github/workflows/ci.yml`, `docs/spec.md`.
- Pattern to copy: phase 1's `BLAST_OFF_TEST_KEEP` (read into a local, `unset` before scenarios, header doc, 00-harness block, spec row 215).
- Gotchas: 00-harness pins unfiltered verdict lines with `grep -qx`, two `if: failure()` lines, one `run: tar` line, two literals in ci.yml. One suite at a time on this box.
- Conflicts: none.

## Decisions
| Decision | Why |
|---|---|
| `BLAST_OFF_TEST_ONLY="<name>[, <name>...]"` env var on tests/run | criterion 2: filter lives in tests/run, testable locally; CI passes the input through `env:` |
| Filtered verdict `GATE-ONLY: PASS|FAIL ... only=<names>` | does not start `GATE: `, so `receipt_verdict` finds no verdict and the receipt is refused, nothing written; no change to lib/receipt.sh |
| Names compared as strings to scenario basenames, never used in a path or glob | `*`, `../x` match nothing and fail loudly |
| Unmatched name: `FAIL only <name>: ...`, counted as a failure, matched ones still run | loud, one code path, verdict still printed |
| Set-but-empty (or only separators) = unset | CI exports `''` on pull_request |
| Var unset before scenarios | `only=00-harness` would filter its nested fixture runs to nothing |
| Shellcheck still runs on a filtered real-suite run | not a scenario; seconds; no extra branch |
| `.sh` suffix in a name not accepted | YAGNI; fails loudly with the name |

## Slices
| # | Slice | Done when | Status |
|---|---|---|---|
| 1 | Tests first: 00-harness filter block + ci.yml pin; 40-receipt refusal of a real filtered log | RED recorded | done |
| 2 | tests/run filter + verdict + header | 00-harness and 40 green via symlink dir | done |
| 3 | ci.yml input + env line | YAML parses; 00-harness pin green | done |
| 4 | docs/spec.md row | 70-docs green | done |
| 5 | shellcheck by hand, one full `tests/run`, ExecStart check | GATE: PASS | done |
