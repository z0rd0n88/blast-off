# Phase 6 progress

- Oriented: bin/blast-off, lib/units.sh, lib/checkpoint.sh, lib/chain.sh, tests/lib.sh, tests/run, spec §2/§3/§6, README, SKILL.md, 70-docs.
- ExecStart before any run: `ExecStart=/home/alex/blast-off/.worktrees/blast-off-build/bin/blast-off run %f` (ok).
- RED: 13-wait on code without `wait`: `FAIL: wait returned before any change (child-count 0 0): rc 1: blast-off: unknown command 'wait' (see blast-off --help)`.
- GREEN 13-wait after lib/units.sh unit_wait + dispatch; fixed a stale-status line (status word now from the snapshot's own read).
- Mutants M1-M7 and D1/D2 each killed, each restored and confirmed with cmp; ExecStart checked after every run (unchanged).
- Docs: bin/blast-off header, spec §2/§3/§6, README watch + table, SKILL.md steps 7-8, tests/70-docs.sh. 70-docs GREEN, 12-start-env GREEN.
- shellcheck -S warning clean on bin/blast-off, lib/units.sh, tests/13-wait.sh, tests/70-docs.sh.
