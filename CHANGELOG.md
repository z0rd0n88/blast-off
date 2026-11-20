# Changelog

To keep it updated: each merged PR adds its line under the day it lands (create the day heading if
it is new). Newest day first. Dates are git author dates as recorded, all at UTC-8 (-0800) so far.

## 2026-11-19

- Jev model picks now work under `start`: `start` and the resume timer pass `OPENROUTER_API_KEY` to
  the job by name, a pick below `JOB_JEV_MIN_CONF` (default 0.7) keeps the static `CLAUDE_FLAGS`,
  and preflight shows what `start` will do (#27, PR #45).
- The child protocol in the templates now says a refused tool call comes from the harness, never
  the owner, and is no reason to ask the owner in chat (#16, PR #48).
- Docs: blast-off is launched from the target repo, the original launcher prompt is kept in
  `docs/`, and the spec's keep and fix lists point at that copy (#21, PR #49).
- Merged `blast-off wait` (PR #43), built on 2026-11-17 and 2026-11-18.
- Docs: the README gains an Options guide (every command with its exit codes, every environment
  variable with its default and effect) and a Technical details section (systemd units and the
  resume timer, the runner loop, the child, job-dir files); every claim in the README, spec, skill
  and code comments was checked against the code and fixed where wrong; this changelog
  (PR #<n>).

## 2026-11-18

- `blast-off wait` fixes from review: the runner now writes the end it accepts (`done` or
  `blocked`) to a `runner-end` file and `wait` reads only that, so text copied into `run.log`
  cannot fake or hide the end; a read that keeps failing for 60 s ends `wait` as stuck (#14).

## 2026-11-17

- Merged the test tooling from 2026-11-15 (PR #34, PR #35) and the absent-CI done check
  (PR #37).
- The child count is saved per job, so the soft cap survives relaunches, and the hard child cap
  never resets for a job; deleting the `child-count` file is the one owner reset (#22, PR #38).
- Child-count follow-ups: `preflight` and `status` show the count, a garbled count file is
  refused and logged, and `JOB_*` numbers with leading zeros or over 9 digits are refused
  (#39, PR #41).
- New `blast-off wait` command that blocks until the job changes (#14, merged 2026-11-19).

## 2026-11-16

- More fixes to the absent-CI done check from review: done is refused on any Phase plan line the
  parser cannot read, one reader handles the Phase plan section, the checkpoint template names a
  PR only as `PR #<n>`, and the spec and README state the check's threat model (#26).

## 2026-11-15

- A dead child pane that gave no exit status is now logged, and the flag clears for the next
  child (#29, PR #32).
- Added `scripts/gate.sh`, a gate wrapper around `tests/run` (PR #33).
- Test tooling: `tests/run` keeps scenario work dirs under `BLAST_OFF_TEST_KEEP` and CI uploads
  them when the gate fails (#30); `BLAST_OFF_TEST_ONLY` runs a subset, also from a CI `only`
  input (#31).
- Done is refused when the repo has CI workflows but the PR has no CI result, first round of
  review fixes included (#26).

## 2026-11-10

- Test pinning the exit-status read to the pane shell's exit file; merged the dead-child fix
  (PR #28).

## 2026-11-09

- Fix: a dead child's exit status is read from the pane shell, not from tmux.

## 2026-11-07

- Merged the whole first build, PRs #1 to #9: spec and test gate, the tracer chain, liveness,
  usage pause, receipts and CI, templates, Jev and preflight, docs and skill, and CI with the
  decision log. All of it was written on 2026-11-05 and 2026-11-06.

## 2026-11-06

- Receipts and CI checks tightened: a receipt must match HEAD's code, its own gate log and a clean
  tree; `ci-wait` watches late runs; done checks the PR's current head; exit 9 and 10 messages
  name the action that clears them.
- Templates: `checkpoint.md` and the brief carry the child protocol and the runner's rules; the
  runner warns in `run.log` when `checkpoint.md` passes 150 lines.
- Jev picks each phase's model level, falling back to `CLAUDE_FLAGS`; `blast-off preflight`
  prints what a launch uses and refuses a job estimated over the 7-day usage left.
- Docs: the blast-off skill wrapper, README, and the systemd guide deviations table, with a test
  that keeps them in line with the CLI.
- CI runs the tests on pull requests with a user systemd manager; the build's decision log is
  committed.

## 2026-11-05

- Spec and test harness: the spec maps keep and fix items, the CLI, exit codes and units; three
  review rounds applied.
- Core commands: `blast-off run` (the chain loop ported from run-job), and `install`, `start`,
  `status`, `stop`, `logs` under `blast-off.slice`; child scopes and the job's tmux server stop on
  every exit.
- Runner checks: a dead child is seen in about 1 s with its last screen logged, a soft child cap
  pauses the job (exit 6), a dirty tree the checkpoint does not name is refused (exit 7), and
  only one runner runs per job.
- Usage limits: the job pauses with the reset time (exit 8), `blast-off resume` restarts it after
  the reset, and each phase row records its usage.
- `blast-off receipt` (exit 9) and `blast-off ci-wait` (exit 10) gate a done phase on a passing
  receipt and green CI. Each feature came with its tests written first.

## 2026-11-04

- Repository created (empty first commit).
