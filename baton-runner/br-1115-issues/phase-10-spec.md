# Phase 10 spec: documentation update and fact check (owner request, 2026-11-19)

Runs after phase 9, branched from main once phase 9 is merged. Docs only: no behaviour change.

## Scope (files)
README.md, CHANGELOG.md (new), docs/spec.md, skills/blast-off/SKILL.md, templates/brief.md, templates/checkpoint.md,
`bin/blast-off` usage/help header, and header/doc comments in lib/*.sh and tests/*.sh that state behaviour.
Not in scope: code behaviour, other repos (Z0rd0nZords, ClaudeConfig), baton-runner/ records. Scope confirmed by the owner 2026-11-19: the blast-off repo's own docs only.

## 1. Every change included
Each change merged in this run must be described where a reader would look for it. Source list
(re-read each PR's diff and body; add phases 7-9's PRs when they exist):
- PR 32 (issue 29): CHILD_NOSTATUS warning in run.log
- PR 33: scripts/gate.sh
- PR 34 (issue 30): BLAST_OFF_TEST_KEEP, CI artifact upload on failure, job timeouts
- PR 35 (issue 31): BLAST_OFF_TEST_ONLY, GATE-ONLY verdict, CI `only` dispatch input
- PR 37 (issue 26): done gate refuses absent CI when workflows exist; PR per done row; ci-wait ignores workflow_dispatch
- PR 38 (issue 22): per-job child-count, hard/soft cap across relaunches
- PR 41 (issue 39): child-count refusals in run.log (content never shown), preflight/status count, JOB_* 9 digits and no leading zero, owner rulings P4R2-4, P4R2-11, P4-22b
- PR 43 (issue 14): `blast-off wait`, exit 0/11/12/1, runner-end
- Phases 7-9 (issues 27, 16, 21): to be added when merged
Output: a coverage table (change -> doc file:line that describes it).

## 2. Every fact verified
Inventory every factual claim in the scope files: commands and arguments, env vars and defaults,
exit codes, file names in the job dir, statuses, log line texts, limits and timeouts, test-scenario
rows in spec §6, and cross-references. For each claim record evidence: the code file:line that makes
it true, or the test that pins it. A claim with no evidence is fixed to match the code or deleted;
never changed to match a guess. Doc-only findings left open in #36, #40, #42 (e.g. P5R2-6/-7,
P6R1-18/-19, P6R3-9/-11/-12/-14) are in scope as claims to verify.
Output: a ledger `baton-runner/br-1115-issues/phase-10/fact-ledger.md` (claim, location, evidence, result: ok / fixed / deleted).

## 3. README: options guide and technical details (owner request 2026-11-19)
- **Options guide** in README: every command (`run`, `start`, `status`, `stop`, `logs`, `resume`, `wait`,
  `install`, `preflight`, `receipt`, `ci-wait`, and any added by phases 7-9) with its arguments, what it
  does and its exit codes; every environment variable (`JOB_*`, `BLAST_OFF_*`, `CLAUDE_FLAGS`, `GH_TOKEN`,
  `OPENROUTER_API_KEY`, ...) with its default, allowed values and effect. Complete: built from
  `bin/blast-off`, `lib/*.sh` and `systemd/`, not from the existing docs; each row in the fact ledger.
- **A separate "Technical details" section** (its own top-level heading, kept apart from the user guide),
  explaining at a technical level how blast-off works under the hood:
  - systemd: the `blast-off@.service` template and what `install` writes; how `start` and `resume` use
    `systemd-run` (unit names, `--setenv` by name, properties); the resume timer (calendar time, transient,
    what fires it, what happens when it elapses); `stop`; user bus and lingering requirements; journal.
  - the runner process: lock, traps and signals, the loop (read checkpoint -> pick flags/Jev -> launch child
    -> wait -> report), exit codes and how status words move.
  - the child: tmux session/window, the Claude CLI invocation, trust dialog handling, stall and hang
    detection, Stop payload, how a child ends and is reaped.
  - job-dir state files and who writes them: `checkpoint.md`, `run.log`, `child-count`, `runner-end`,
    `gate-logs/`, `decisions.tsv`, `phases/`; usage-limit pause and resume; CI wait and receipts.
  - a small diagram (ASCII or Mermaid) of start -> unit -> runner -> child sessions -> checkpoint.
  Every statement in it gets a fact-ledger row with code evidence.

## 4. CHANGELOG.md (new separate file, owner request 2026-11-19)
- A new `CHANGELOG.md` at the repo root covering ALL work to date, from the first commit.
- One entry per day the project was worked on (dates from `git log --date=short`, author dates, UTC
  stated), newest first; under each day a short high-level overview of what changed (features, fixes,
  docs, tests) grouped in plain words. Not one line per PR; PR/issue numbers only as references where
  they help.
- Built from `git log` and merged PR titles/bodies, every day checked against the commits of that day
  (record the commit range per day in the ledger). Add a one-line note at the top on how to keep it
  updated (each merged PR adds its line under its day).
- Include phases 7-10 of this run once merged.

## Done when
- coverage table complete (every change above has a doc location);
- fact ledger has a row per claim with evidence, no row "unverified";
- tests/70-docs.sh and tests/51-templates.sh pass; the full gate passes (review unit, alone);
- review: one reviewer re-checks a random sample of ledger rows against the code and every row marked fixed;
- README has the options guide and a separate Technical details section; CHANGELOG.md exists with one entry per worked day up to the phase's own date;
- one draft PR.
