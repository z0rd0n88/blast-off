# Phase 10 coverage: every change merged in run br-1115 -> where a reader finds it

Line numbers are at the phase 10 fix round 1 commit (README, spec, bin/blast-off and SKILL.md refreshed from 0a5d3b1; fix round 1 also corrected README.md:61 to :63 and :18-19 to :202). "added" = described by this unit; "already present" = text was there at 9c86128 (lines may have shifted).

| PR (issue) | User-visible change | Doc file:line | Status |
|---|---|---|---|
| 32 (#29) | Child's exit status read from an exit file the pane shell writes, else `#{pane_dead_status}` | docs/spec.md:150-155 (child command), :185 (exit 75 read from the exit file) | added (:148-153); :183 already present |
| 32 (#29) | `run.log` warning: `its pane is dead but neither its shell nor tmux gave a status` (CHILD_NOSTATUS) | docs/spec.md:152-154; test row docs/spec.md:251 (`20-dead-child`) | added (:150-152); :249 already present |
| 33 | `scripts/gate.sh <log-dir>`: runs tests/run, tees `<log-dir>/tests-run.log`, exits with its status | README.md:263-264 | added |
| 34 (#30) | `BLAST_OFF_TEST_KEEP=<dir>` keeps scenario work dirs | README.md:262-263; docs/spec.md:246 (`00-harness`) | README added; spec already present |
| 34 (#30) | CI uploads the kept work dirs (`blast-off-tests`, `blast-off-tests.tgz`) on a red run | README.md:265-267; docs/spec.md:246 (tar line) | README added; spec already present |
| 34 (#30) | CI job timeout 30 min, gate step 25 min | README.md:265-266 | added |
| 35 (#31) | `BLAST_OFF_TEST_ONLY` runs named scenarios; a missing name fails | README.md:260-262; docs/spec.md:236-237, :246 | README added; spec already present |
| 35 (#31) | `GATE-ONLY: PASS/FAIL ... only=<names>` verdict, refused by `blast-off receipt` | README.md:261-262; docs/spec.md:246 | README added; spec already present |
| 35 (#31) | CI `only` dispatch input -> `BLAST_OFF_TEST_ONLY` | README.md:267; docs/spec.md:246 | README added; spec already present |
| 37 (#26) | `done` refused when a PR's CI is absent and its head has a workflow file | README.md:158-161, :237 (exit 10 row); docs/spec.md:104 | already present |
| 37 (#26) | Every done row names its PR (`PR #<n>`) or `no PR` | README.md:153-159, :237; docs/spec.md:104; templates/checkpoint.md:35-40 | already present |
| 37 (#26) | `ci-wait` ignores `workflow_dispatch` runs | docs/spec.md:65 (`ci-wait` row), :104 | already present |
| 38 (#22) | Per-job `child-count` (`<launched> <base>`), numbering across relaunches | docs/spec.md:68 (`JOB_MAX_CHILDREN`), :98, :100; README.md:231 (exit 4 row) | already present |
| 38 (#22) | Hard cap counts every child of the job; soft cap gets a fresh allotment on resume | docs/spec.md:68, :98, :100; README.md:231, :233 | already present |
| 41 (#39) | Garbled `child-count` refused, reason in run.log, content never shown | docs/spec.md:68, :96 | already present (wording fixed for the unreadable case, P5R2-6) |
| 41 (#39) | `status` and `preflight` print the child count (preflight: `<n> left under cap`) | docs/spec.md:57, :63; README.md:63, :105 | already present |
| 41 (#39) | `JOB_*` counts: at most 9 digits, no leading zero | docs/spec.md:96; README.md:70 ("a bad `JOB_*` number"), :67-68 (preflight) | already present; README preflight list extended |
| 43 (#14) | `blast-off wait`, its line, exit 0/11/12/1 | README.md:104, :116-134; docs/spec.md:61, :114-120; bin/blast-off:12-17 | already present (fixed: P6R3-12, -14, P6R1-18, -19) |
| 43 (#14) | `runner-end` file | docs/spec.md:47-51; README.md:119, :127, :130 | already present (fixed: P6R3-9, -11) |
| 45 (#27) | Jev key `OPENROUTER_API_KEY` passed by `start`/resume timer by name when Jev can use it | README.md:70-82; docs/spec.md:56, :69; skills/blast-off/SKILL.md:68-74 | already present (SKILL.md: `JOB_JEV` condition added, P7R2-4) |
| 45 (#27) | A pick below `JOB_JEV_MIN_CONF` (default 0.7) keeps `CLAUDE_FLAGS` | README.md:202 (moved by unit C from the Requirements); docs/spec.md:27, :69; bin/blast-off:38 | already present |
| 45 (#27) | Children never get the key | README.md:81-82; docs/spec.md:69, :134 | already present |
| 45 (#27) | Real-unit key pass-through test | docs/spec.md:248 (`11-unit-smoke`) | added (P7R2-16) |
| 48 (#16) | Brief §9 step 9: a refused tool call comes from the harness, a blocked part | templates/brief.md:171-176; docs/spec.md:261 (`51-templates`) | already present |
| 49 (#21) | Start the launching session in the target repo | README.md:55-57; skills/blast-off/SKILL.md:25-28; docs/spec.md:264 | already present |
| 49 (#21) | Launcher prompt copied to `docs/2026-11-04-large-job-launcher-prompt.md` | README.md:14; docs/spec.md:8, :264 | already present |
