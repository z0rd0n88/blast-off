# Phase 7 progress

- Oriented: lib/jev.sh, lib/units.sh, lib/usage.sh (usage_arm), lib/preflight.sh, lib/chain.sh (chain_nums, jev_pick
  call), lib/child.sh (child_server env), bin/blast-off, tests 12/30/60/61/70, tests/lib.sh, tests/run, fakes/jev,
  spec K8/preflight/env/D21 text, decision log rows 138-140, issue 27.
- ExecStart before any run: `ExecStart=/home/alex/blast-off/.worktrees/blast-off-build/bin/blast-off run %f` (ok).
- RED C1 (12-start-env, stub systemd-run): `FAIL: start does not pass --setenv=OPENROUTER_API_KEY: --user`
- GREEN after unit_env adds `--setenv=OPENROUTER_API_KEY` when set and not empty (and JOB_JEV_MIN_CONF to the JOB_* names).
- Mutants M1 (always passed), M2 (empty passed), M3 (timer drops it), M10 (value on argv) killed; restored, cmp equal.
- RED log line (61): `FAIL: pick not in run.log: ...`; RED C3 (61, after the log change only):
  `FAIL: low: child flags '--model sonnet --effort medium --foo bar', want static`; RED validation:
  `FAIL: JOB_JEV_MIN_CONF=abc: exit 0, want 1: ...`. GREEN after jev_flags' threshold check and chain_nums' check.
- Mutants M4 (<=), M5 (no low branch), M6 (no validation), M7 (non-number taken), M11 (key logged), M12 (default 0.5) killed.
  M11 first SURVIVED (61 never checked run.log for the value); a check was added, then it was killed.
- RED preflight (60): `FAIL: no line /^flags: --model opus --effort xhigh --foo bar$/ in p1.out: ...`; GREEN after
  preflight asks Jev with the caller's environment. Mutants M8 (key forced empty again), M9 (key printed) killed.
- Docs: bin/blast-off env header, spec K8/preflight/env/test rows 12, 60, 61, README requirements and Check-then-start.
- Final single runs: 70-docs, 12-start-env, 60-preflight, 61-jev-pick all GATE-ONLY: PASS; shellcheck -S warning clean
  on the 9 changed scripts. ExecStart checked after every run: unchanged.
