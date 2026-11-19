# Phase 1: issue 30, tests/run opt-in keep dir

Target set (confirmed by the brief): `tests/run`, `tests/00-harness.sh`, `.github/workflows/ci.yml`, `docs/spec.md` (00-harness row only).

| Slice | Done when | Skill | Status |
|---|---|---|---|
| 1 Tracer bullet: KEEP set moves each work dir to `<keep>/<name>` | 00-harness set-case assertions green (red first) | tdd | done |
| 2 KEEP unset removes work dirs (characterization, green before and after) | 00-harness unset-case green | tdd | done |
| 3 ci.yml env + upload-artifact under `if: failure()` | YAML parses, careful read | none | done |
| 4 header comment + spec row 00-harness | text present | none | done |
| 5 full gate | `tests/run` GATE: PASS | none | done |

Decisions
| Decision | Why |
|---|---|
| Unset the var inside the scenario subshell | 00-harness re-runs tests/run on fixtures; inherited, they would land in the CI artifact dir |
| `mv` the whole work dir (out + cwd/) | already holds the captured output; no copy code |
| Clear a stale `<keep>/<name>` first | mv onto an existing dir nests |
| Seam = tests/run CLI | fixed by acceptance criterion 4 |
