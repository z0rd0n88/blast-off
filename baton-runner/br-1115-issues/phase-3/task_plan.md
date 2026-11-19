# Phase 3 (issue 26 + P2R1-1): absent CI refused when HEAD has workflows; PRs read from Status cells; dispatch runs not counted

## Brief
- Target set (tracked): `lib/ci.sh`, `tests/41-ci-wait.sh`, `tests/fakes/gh`, `docs/spec.md`.
- Pattern to copy: `cp_plan_rows` (`lib/checkpoint.sh:39-44`) for the Phase plan sed and the `$(NF-1)` Status cell; test 40's `repo`/`plan`/`gate` fixture for a git workdir with a receipt.
- Gotchas: scenario stops at its first `fail`, so build in file order (4, 3, 2, 1). A done row in a git workdir needs a receipt (exit 9 otherwise); outside git `TOP` is empty and the receipt check is off. One suite at a time on this box.
- Conflicts: `templates/checkpoint.md:29-30`, `skills/blast-off/SKILL.md:34-35`, `templates/brief.md:135` go stale; outside the target set, reported in the baton, not edited.

## Decisions
| Decision | Why |
|---|---|
| Filter `workflow_dispatch` in both `gh run list` calls (ask for `event`) | such runs are then never watched nor recorded: not a pass, not a failure (P2R1-1) |
| Fake gh: `event-<id>` file, `event` emitted only when `--json` asks for it | a ci.sh that forgets to ask reads null and the test goes red |
| PR numbers from Status cells of digit-keyed Phase plan rows only | same rows the runner already reads (`cp_plan_rows`) |
| Workflow check: `git -C "$TOP" ls-tree -r --name-only HEAD -- .github/workflows`; no git repo (`TOP` empty) = no workflow; a git failure dies | HEAD per the issue; a failed read must not pass as "no workflow" |
| `ci_head` runs before the workflow check | stale-head and gh-failure messages stay as they are |

## Slices
| # | Slice | Done when | Status |
|---|---|---|---|
| 1 | Criterion 4: dispatch runs left out | 41 cases red then green | done |
| 2 | Criterion 3: Status cells only | red then green | done |
| 3 | Criterion 2 then 1: workflow check | red then green | done |
| 4 | Spec + header comments | 70-docs green | done |
| 5 | shellcheck, one full `tests/run`, ExecStart check | GATE: PASS | done |
