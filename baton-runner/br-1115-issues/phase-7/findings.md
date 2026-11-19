# Phase 7 findings

- lib/units.sh unit_env builds the --setenv=NAME list for both `start` (unit_start) and the resume timer (usage_arm);
  GH_TOKEN is always passed (unit_check refuses it unset/empty). The timer's service therefore carries whatever names
  unit_env adds, and its `blast-off resume` -> unit_start passes them again: one change covers both paths.
- preflight forced `OPENROUTER_API_KEY=''` (start passed none). jev_flags logs the pick in jev_pick only, preflight
  writes nothing (jev_flags' mktemp err file is removed).
- Children inherit the runner's environment through the job's tmux server (child_server scrubs only CLAUDE*), so under
  start the children now also see OPENROUTER_API_KEY, as they already did under a foreground run with the key.
- tests/lib.sh unsets OPENROUTER_API_KEY, TYPESAFE_API_KEY, JEV_BASE_URL for every scenario; fake jev records only the
  key's first 6 chars.

## Decisions
- D-P7-1: the key is passed by name only when set and not empty (`${OPENROUTER_API_KEY:-}`), unlike the JOB_* names
  (passed when set, even empty): an empty --setenv would hand the unit an empty key for nothing.
- D-P7-2: threshold compare in jq (already a dependency) on jev's JSON; at the threshold the pick is taken (only
  "below" keeps static); a confidence that is not a number keeps static with its own reason.
- D-P7-3: JOB_JEV_MIN_CONF validated in chain_nums (run and preflight refuse, like a bad JOB_* count):
  `^(0(\.[0-9]{1,3})?|1(\.0{1,3})?)$` - 0..1, at most 3 decimals, leading digit (`.7` refused), as BLAST_OFF_WAIT_POLL's
  3-decimal rule. Empty means default, like the other JOB_* names.
- D-P7-4: preflight now asks Jev (one call) with the caller's environment, since that is what start gives the unit.
  The old "no jev call" rested only on start passing no key. Cost: one OpenRouter call per preflight when the key is set.
- D-P7-5: the low-confidence fallback keeps JEV_LEVEL=static, so decisions.tsv says `model level static` with the
  reason; the pick line and decisions.tsv `why` now also carry `threshold <t>`.
