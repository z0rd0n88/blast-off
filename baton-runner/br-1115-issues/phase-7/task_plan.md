# Phase 7 task plan: issue 27 (pass OPENROUTER_API_KEY to the unit; Jev confidence threshold)

Owner sign-off 2026-11-15: pass the key (keep lib/jev.sh); a pick below 0.7 keeps static CLAUDE_FLAGS;
JOB_JEV_MIN_CONF overrides, validated (number 0..1) and documented.
Each step: test first (RED), code (GREEN), scenario run alone (`BLAST_OFF_TEST_ONLY=<name> tests/run`), one named
mutant killed (edit, run, restore, cmp). ExecStart of ~/.config/systemd/user/blast-off@.service checked before the
first run and after every run.

1. Tracer (C1): 12-start-env, scenario-local stub systemd-run records argv: start with a fake sk-or- key passes
   `--setenv=OPENROUTER_API_KEY` (name only), the value never on argv or in start's output. → RED, GREEN (unit_env).
2. C1/C2 resume path: `blast-off resume` (paused-cap) carries the name; the resume timer armed at a pause carries it
   (pass-through stub records only the --on-calendar call). Without the key / with an empty key: no such --setenv.
   → GREEN, mutant (key always passed / never passed) RED.
3. C3: fake jev confidence from $FAKE_JEV/confidence; 61-jev-pick: 0.55 keeps static, logged
   `jev picked light, confidence 0.55 below 0.7`; JOB_JEV_MIN_CONF=0.5 takes it; 0.7 exactly takes it; pick log
   line shows confidence and threshold. Bad JOB_JEV_MIN_CONF refused by run (exit 1) and preflight. → RED, GREEN,
   mutants (no threshold check; <= instead of <; validation removed) RED.
4. Preflight's start view: asks Jev as start would (the key now reaches the unit), prints the pick, confidence and
   threshold, or static with the reason; key value never in its output. → RED, GREEN (60-preflight).
5. Docs: bin/blast-off env header, jev.sh/units.sh/usage.sh comments, spec K8 + preflight row + env paragraph +
   test rows 12/60/61, README requirements. 70-docs alone. shellcheck -S warning on changed scripts.
