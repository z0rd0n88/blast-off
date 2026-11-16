# Owner rulings, phase 3 (issue 26), 2026-11-15

1. PR rule (P3R2-1, criterion 3): every done row's Status cell must hold either `PR #N` or an explicit `no PR`. A done row with neither is refused (exit 10). Nothing in prose is ever read: no whole-file fallback. Existing checkpoints and the template add `no PR` to rows that have none.
2. CI due (P3R2-3, P3R2-7): when a PR shows no CI runs, whether runs were due is decided at the PR record's head commit (`.github/workflows` at head_sha), not the workdir's HEAD. A PR whose head has no workflow file is allowed through as "no CI configured", logged; one whose head has a workflow file is refused. This departs from the issue's literal wording by the owner's choice.
