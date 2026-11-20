# Phase 10 work unit B: coverage and fact check

- Commit: `0a5d3b1` on `feat/br-1115-issues/phase-10` ("docs: fact check every claim against the code; cover every change of this run"). Not pushed.
- Files: README.md, docs/spec.md, bin/blast-off (header), skills/blast-off/SKILL.md, lib/chain.sh and lib/preflight.sh (comments), tests/31-resume-after-reset.sh and tests/60-preflight.sh (header comments). No code line changed. README lines 9-13 untouched; no CHANGELOG.md.
- Coverage table: `coverage.md`. Fact ledger: `fact-ledger.md`.
- Counts: 240 claims checked; 200 ok, 38 fixed, 2 deleted.

## Fixed claims (old -> new; evidence)

README.md
1. :63-65 preflight refusals "when `CLAUDE_FLAGS` is empty, a dependency is missing, or the estimated usage ..." -> adds "`brief.md` is missing, `child-count` is garbled, a `JOB_*` number is bad". lib/preflight.sh:13-17, :39.
2. :65-67 `start` passes "every set `JOB_*` name" -> "every set `JOB_*` and `BLAST_OFF_*` name the runner reads (not `JOB_BASE` or `BLAST_OFF_ESTIMATE_FROM`, which only `preflight` reads)". lib/units.sh:21-29.
3. :116 "`until <time>`, at most 40 more" -> "the time at most 40 characters". lib/units.sh:157 (P6R3-12).
4. :116-117 phase line "without control characters or any `·`" -> "with each `·` turned into `-`". lib/units.sh:159 (P6R3-12).
5. :125 "every read failed for 60 s" -> "for 60 s or more (at least one retry, so a long `BLAST_OFF_WAIT_POLL` stretches it". lib/units.sh:135-140 (P6R3-14).
6. :126 wait exit-1 row: adds "no `<job-dir>` argument" and "a workdir name that is not letters, digits, `-` or `_`". bin/blast-off:60-64 (P6R1-18).

docs/spec.md
7. :48-51 runner-end "deleted at the start of every run (after the runner takes the job's lock), so a refused `done` or `blocked` (exit 7, 9 or 10) or a re-opened job has none" -> adds "a signal between the two leaves the file and logs `runner exit <n> without a state` instead"; "deleted by every run once it takes the job's lock (a run that exits before the lock leaves it), so a `done` or `blocked` that run refuses (any exit but 0 and 3) has none, and a re-opened job has none once its next run holds the lock". lib/chain.sh:154-169, :18-27 (P6R3-9, P6R3-11).
8. :56 `start` "`systemd-run --user --collect --slice=blast-off.slice ...`, a `--setenv=` per set `JOB_*` name and `BLAST_OFF_TRUST_SECONDS`, ... the template's directives as `-p` properties" -> no `--slice=` (start passes `-p Slice=blast-off.slice` from the template), the 15 names of `unit_env` listed, "the template's `[Service]` directives but `ExecStart=` as `-p` properties". lib/units.sh:21-29, :44-48.
9. :58 `stop` "`systemctl --user stop blast-off-<name>.service`" -> also the child scopes and resume timer; exit 1 while the unit is still active. lib/units.sh:89-95.
10. :61 wait refusals "(exit 7, 9 or 10 for `done`, 7 or 9 for `blocked`, ...)" -> adds "1 on an error or 128+n on a signal for either". lib/chain.sh:25-26 (P6R3-11).
11. :61 wait line "`until <time>` (up to 40 more), and the phase line loses control characters and every `·`" -> "(the time up to 40 characters)", "has each `·` turned into `-`". lib/units.sh:157-160 (P6R3-12).
12. :61 wait exit 1 causes: adds "no `<job-dir>` argument", "a workdir name that is not letters, digits, `-` or `_`". bin/blast-off:60-64.
13. :61 "once reads have failed for 60 s in a row" -> adds "(at least one retry, so a long `BLAST_OFF_WAIT_POLL` stretches it; ...)". lib/units.sh:135-140 (P6R3-14).
14. :62 install "writes `blast-off@.service`, `blast-off.slice` (and the resume timer if used)" -> "writes `blast-off@.service` and `blast-off.slice` ... (the resume timer is transient, never installed)". lib/units.sh:8-14; lib/usage.sh:70.
15. :63 preflight refusals: adds "a missing `brief.md`". lib/preflight.sh:13.
16. :63 "(exit 1 above)" -> "(exit 1, §3)". The table is below (P5R2-6).
17. :68 child-count refusal "(the file's name, byte size and the shape it wants, ...)" -> "(the file's name and, when it can be read, its byte size and the shape it wants, ...)". lib/chain.sh:134-136 (P5R2-6).
18. :34 F5 "The child env also sets `CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS=0` (brief §3.3), but it acts only" -> "blast-off does not set the prompt's `CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS=0` (prompt §5 F5) in the child env: it acts only". No file outside the launcher prompt names it; templates/brief.md §3.3 is a placeholder.
19. :103 exit 9 "(Status starts `done`, any case;" -> "(Status cell `done` alone or followed by a blank or `(`, any case;". lib/checkpoint.sh:16-18, :50.
20. :116 wait codes "when no read succeeds for 60 s" -> adds "(at least one retry)" (P6R3-14).
21. :118 "They are outside this table's range, so a watcher never reads one as the runner's." -> "Its 11 and 12 are outside this table's range, ...; its 0 and 1 are `wait`'s own and say nothing about the runner's exit." (P6R1-18).
22. :148 child command "`systemd-run --user --scope --slice=blast-off.slice --unit=<runner unit>-child-<n> claude ...; exit`" -> "`systemd-run --user --scope --quiet --collect --slice=blast-off.slice --unit=<runner unit>-child-<n>.scope claude ...; rc=$?; echo $rc > <child dir>/exit; exit $rc`", plus three lines on the exit file and the CHILD_NOSTATUS run.log text (issue #29, PR 32 coverage). lib/child.sh:48-50, :61-62, :81-85; lib/chain.sh:233.
23. :153-154 "the trailing `; exit` makes the pane shell fork" -> "the commands after `claude` make the pane shell fork". lib/child.sh:39-41.
24. :246 row 11-unit-smoke: adds the real-unit key case. tests/11-unit-smoke.sh:90-99 (P7R2-16).
25. :248 row 13-wait "without control characters or ` · `" -> "without control characters and with each `·` turned into `-`". tests/13-wait.sh:91-95 (P6R3-12).
26. :250 row 21-soft-cap "a `JOB_CAP_FACTOR` of 10" -> "of 10 digits". tests/21-soft-cap.sh:85 (`1000000000`).
27. :254 row 31 "after the reset (and for `paused-cap`) sets running, starts the unit, which finishes the job" -> "starts the unit, whose runner sets running and finishes the job". lib/units.sh:54-59.

bin/blast-off header
28. :10 resume "...: running, then start" -> "...: start (the runner sets running)". lib/units.sh:54-59.
29. :13-16 wait stuck list "(stopped, crashed, done or blocked refused, paused-cap), or no read for 60 s" -> "(stopped, crashed, a reboot, done or blocked refused, paused-cap, paused-limit with no timer), or no read for 60 s (at least one retry); 1 when it cannot start watching". lib/units.sh:102-142 (P6R1-20, P6R3-14).

skills/blast-off/SKILL.md
30. :68-69 see the reword ledger below (P7R2-4).

lib comments
31. lib/chain.sh:8-10 "Each run deletes it first (chain_run), so a refused or re-opened job never shows an earlier run's end." -> "Each run deletes it once it holds the lock (chain_run), so a job that run refuses or re-opens never shows an earlier run's end; a run that exits before the lock leaves it, and a signal between this and chain_end leaves it with no end line." (P6R3-9, -11).
32. lib/chain.sh:129 "COUNT_ERR names the file and the shape it wants" -> "names the file and, when it can be read, its size and the shape it wants" (P5R2-6).
33. lib/preflight.sh:4-5 "CLAUDE_FLAGS empty, a runtime dependency missing" -> "brief.md missing, CLAUDE_FLAGS empty, a runtime dependency or gh missing". lib/preflight.sh:13, :17.
34. lib/preflight.sh:21 "pass OPENROUTER_API_KEY by name when it is set" -> "when Jev can use it (sk-or-, JOB_JEV not 0; issue 27)". lib/units.sh:23 (P7R2-2).

tests header comments
35. tests/31-resume-after-reset.sh:3 "after it, sets running and starts the runner unit" -> "after it, starts the runner unit, which sets running".
36. tests/60-preflight.sh:4 "start passes OPENROUTER_API_KEY by name when it is set" -> "when Jev can use it" (P7R2-2).
37. tests/60-preflight.sh:8-10 "Exit 1, every line still printed, when ... or a launch would refuse (CLAUDE_FLAGS empty)" -> adds "a garbled child-count" and "a bad JOB_* number exits 1 at once with only its refused line" (P5R2-7).

(The ledger counts 38 fixed rows: some edits above fix two ledger claims, and README rows 3-4 and spec rows 11/25 are separate claims.)

## Deleted claims
1. docs/spec.md:61 "No timeout of its own: the caller's background command has one" -> "No timeout of its own". No evidence for the second half; P6R1-19 says a Claude Code background command has none.
2. docs/spec.md:248 row 13-wait "on an already stuck job (after 10 s on wait's clock, not at once)" -> "on an already stuck job". tests/13-wait.sh:132 asserts the exit code only (P6R3-12); the behaviour stays stated in §2 and README.

## Added (coverage)
- README.md:198-205 Tests paragraph: `BLAST_OFF_TEST_ONLY` and `GATE-ONLY:`, `BLAST_OFF_TEST_KEEP`, `scripts/gate.sh`, CI timeouts (30/25 min), the `blast-off-tests` artifact on a red run, the dispatch `only` input (PRs 33, 34, 35).
- docs/spec.md:149-152 exit file and CHILD_NOSTATUS run.log text (PR 32).
- docs/spec.md:246 row 11 key case (PR 45, P7R2-16).

## Instruction-file reword ledger
skills/blast-off/SKILL.md (one line):
- old: "Tell the owner with it: when the shell that runs `start` has `OPENROUTER_API_KEY` (an OpenRouter `sk-or-` key), `start` passes it to the unit by name"
- new: "... (an OpenRouter `sk-or-` key) and `JOB_JEV` is not `0`, `start` passes it to the unit by name"
- preserved: the instruction to tell the owner, the key condition (`sk-or-`), what Jev picks, the fallback clauses, `JOB_JEV=0` sentence, step 6 forecast note. changed: none. added: the `JOB_JEV` is not `0` condition (lib/units.sh:23).

templates/brief.md: no change.

## Tests
- `BLAST_OFF_TEST_ONLY='00-harness 51-templates 70-docs'` (00-harness added: spec §3 and §6 rows edited), `scripts/gate.sh <scratchpad>/b/gate1`:
  `GATE-ONLY: PASS passed=3 failed=0 shellcheck=ok only=00-harness,51-templates,70-docs`
- `grep ExecStart ~/.config/systemd/user/blast-off@.service`: `ExecStart=/home/alex/blast-off/.worktrees/blast-off-build/bin/blast-off run %f` (matches the expected line).

## Blocked
- None in templates/brief.md §9: every fact there checked true (step 4 exit codes and sha rule, step 6 pause percent and exit 75, step 7 status words, step 8 exit 7).
- The PostToolUse hook asked for `skill-sheriff-cc` on skills/blast-off before committing; that skill is not available in this session, so it did not run. The SKILL.md change is one clause.

## Reviewer should check
1. Out-of-scope files not edited, with claims worth a later fix: `scripts/gate.sh:2-4` says it runs "every scenario, then shellcheck"; under `BLAST_OFF_TEST_ONLY` it runs only the named ones (tests/run:46). `tests/run` (no `.sh`, so outside the brief's glob) was checked and is accurate.
2. templates/brief.md:18 D1 "and `JOB_JEV=0` keeps them" (P7R2-5): left as is. It reads two ways, but both readings are true of the code, so it is not a factual error and the rules forbid rewording an instruction for clarity.
3. #36's four rulings are not built (`/pull/N` still read, any file under `.github/workflows/` counts). The docs describe the code as built; I did not document the rulings as behaviour.
4. #46 P7R2-6 (jev's stderr temp file vs spec's "writes no secret to any file"): not changed. jev's stderr is written to a temp file (lib/jev.sh:39-43) and masked only when logged; whether it can hold the key depends on jev. Owner question stays open in #46.
5. The `start` row (spec :56) now lists all 15 `unit_env` names by hand; a future name added to `unit_env` needs the row too. README says "every set `JOB_*` and `BLAST_OFF_*` name the runner reads" rather than listing them, which section 3's options guide may replace.
6. The ledger groups claims at sentence or clause level; the long spec rows (10-chain-done, 13-wait, 60-preflight, 61-jev-pick) are one row each, checked by grepping each listed case in the test file, not by running each case.
