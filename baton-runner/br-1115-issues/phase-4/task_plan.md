# Phase 4 task plan: issue 22, persist the child count per job

Goal: JOB_MAX_CHILDREN / the derived cap is per job, not per runner run; run.log child numbers continue across relaunches.

1. Tracer bullet: RED test in tests/10-chain-done.sh (cap job re-run with JOB_MAX_CHILDREN=2 -> child 2, exit 4) -> verify: fails on current code by an assertion
2. More RED: hup job re-run with cap 1 launches nothing (count saved before launch); garbled counter file -> exit 1 before any child -> verify: assertions fail
3. GREEN: lib/chain.sh counter file read/write, cap compares launched-since-base -> verify: 10-chain-done passes
4. Soft cap keeps its fresh allotment on a paused-cap re-run (base = total) -> verify: 21-soft-cap passes; add numbering-continues assertion
5. Blast radius: every scenario that re-runs one job dir -> verify: read each rerun site, update numbers where numbering now continues, run each edited scenario alone
6. Docs: docs/spec.md rows 1/4/6, JOB_MAX_CHILDREN text, test table rows 10 and 21; README exit 6 -> verify: 70-docs passes
7. shellcheck -S warning on changed scripts -> verify: clean
8. Baton baton-phase-4-work.md
