# Phase 10 coverage: every change merged in run br-1115 -> where a reader finds it

Line numbers are at commit 0a5d3b1 (work unit B). "added" = described by this unit; "already present" = text was there at 9c86128 (lines may have shifted).

| PR (issue) | User-visible change | Doc file:line | Status |
|---|---|---|---|
| 32 (#29) | Child's exit status read from an exit file the pane shell writes, else `#{pane_dead_status}` | docs/spec.md:148-153 (child command), :183 (exit 75 read from the exit file) | added (:148-153); :183 already present |
| 32 (#29) | `run.log` warning: `its pane is dead but neither its shell nor tmux gave a status` (CHILD_NOSTATUS) | docs/spec.md:150-152; test row docs/spec.md:249 (`20-dead-child`) | added (:150-152); :249 already present |
| 33 | `scripts/gate.sh <log-dir>`: runs tests/run, tees `<log-dir>/tests-run.log`, exits with its status | README.md:201-202 | added |
| 34 (#30) | `BLAST_OFF_TEST_KEEP=<dir>` keeps scenario work dirs | README.md:200-201; docs/spec.md:244 (`00-harness`) | README added; spec already present |
| 34 (#30) | CI uploads the kept work dirs (`blast-off-tests`, `blast-off-tests.tgz`) on a red run | README.md:203-205; docs/spec.md:244 (tar line) | README added; spec already present |
| 34 (#30) | CI job timeout 30 min, gate step 25 min | README.md:203-204 | added |
| 35 (#31) | `BLAST_OFF_TEST_ONLY` runs named scenarios; a missing name fails | README.md:198-200; docs/spec.md:234-235, :244 | README added; spec already present |
| 35 (#31) | `GATE-ONLY: PASS/FAIL ... only=<names>` verdict, refused by `blast-off receipt` | README.md:199-200; docs/spec.md:244 | README added; spec already present |
| 35 (#31) | CI `only` dispatch input -> `BLAST_OFF_TEST_ONLY` | README.md:205; docs/spec.md:244 | README added; spec already present |
| 37 (#26) | `done` refused when a PR's CI is absent and its head has a workflow file | README.md:152-155, :175 (exit 10 row); docs/spec.md:104 | already present |
| 37 (#26) | Every done row names its PR (`PR #<n>`) or `no PR` | README.md:147-153, :175; docs/spec.md:104; templates/checkpoint.md:35-40 | already present |
| 37 (#26) | `ci-wait` ignores `workflow_dispatch` runs | docs/spec.md:65 (`ci-wait` row), :104 | already present |
| 38 (#22) | Per-job `child-count` (`<launched> <base>`), numbering across relaunches | docs/spec.md:68 (`JOB_MAX_CHILDREN`), :98, :100; README.md:169 (exit 4 row) | already present |
| 38 (#22) | Hard cap counts every child of the job; soft cap gets a fresh allotment on resume | docs/spec.md:68, :98, :100; README.md:169, :171 | already present |
| 41 (#39) | Garbled `child-count` refused, reason in run.log, content never shown | docs/spec.md:68, :96 | already present (wording fixed for the unreadable case, P5R2-6) |
| 41 (#39) | `status` and `preflight` print the child count (preflight: `<n> left under cap`) | docs/spec.md:57, :63; README.md:61, :99 | already present |
| 41 (#39) | `JOB_*` counts: at most 9 digits, no leading zero | docs/spec.md:96; README.md:68 ("a bad `JOB_*` number"), :63-64 (preflight) | already present; README preflight list extended |
| 43 (#14) | `blast-off wait`, its line, exit 0/11/12/1 | README.md:98, :110-128; docs/spec.md:61, :114-119; bin/blast-off:11-16 | already present (fixed: P6R3-12, -14, P6R1-18, -19) |
| 43 (#14) | `runner-end` file | docs/spec.md:47-51; README.md:113, :121, :124 | already present (fixed: P6R3-9, -11) |
| 45 (#27) | Jev key `OPENROUTER_API_KEY` passed by `start`/resume timer by name when Jev can use it | README.md:68-76; docs/spec.md:56, :69; skills/blast-off/SKILL.md:68-73 | already present (SKILL.md: `JOB_JEV` condition added, P7R2-4) |
| 45 (#27) | A pick below `JOB_JEV_MIN_CONF` (default 0.7) keeps `CLAUDE_FLAGS` | README.md:18-19; docs/spec.md:27, :69; bin/blast-off:37 | already present |
| 45 (#27) | Children never get the key | README.md:75-76; docs/spec.md:69, :132 | already present |
| 45 (#27) | Real-unit key pass-through test | docs/spec.md:246 (`11-unit-smoke`) | added (P7R2-16) |
| 48 (#16) | Brief §9 step 9: a refused tool call comes from the harness, a blocked part | templates/brief.md:171-176; docs/spec.md:259 (`51-templates`) | already present |
| 49 (#21) | Start the launching session in the target repo | README.md:51-53; skills/blast-off/SKILL.md:25-28; docs/spec.md:262 | already present |
| 49 (#21) | Launcher prompt copied to `docs/2026-11-04-large-job-launcher-prompt.md` | README.md:13; docs/spec.md:8, :262 | already present |
