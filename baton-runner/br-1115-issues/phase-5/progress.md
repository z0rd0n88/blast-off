# Phase 5 progress

- RED probes and new scenarios run on a `git archive c4e2a41` copy (scratchpad p5/old): 10, 21, 60, 11 and probes 90 (run.log), 91 (dangling link), 92 (preflight garbled) all FAIL as expected; old 21 passes its P4R2-1/P4R2-2 blocks (old code is correct there; mutants prove those tests).
- Code: lib/chain.sh (chain_nums bound, chain_count returns COUNT_ERR/COUNT_SAY, garbled refusal logged, start count logged, comments), lib/preflight.sh (child-count line + refusal), lib/units.sh (status line).
- GREEN, one at a time: 10 (47s), 21 (15s), 60 (5s), 11 (14s), 70-docs; neighbours 22, 23, 30, 50, 31 pass.
- Mutants on copies of the new code: MA (BASE=0 on read) FAIL 21; MB (file only) FAIL 21; MT (save in EXIT trap) FAIL 10 at the `1 0` check; MT2 (same, `1 0` check removed) FAIL 10 at the SIGKILL re-run; MG (start_hang without rm) FAIL 11 at the new pid guard.
- ExecStart checked before the first run and after every run: always `ExecStart=/home/alex/blast-off/.worktrees/blast-off-build/bin/blast-off run %f`.
- shellcheck -S warning clean on all 7 changed scripts.
