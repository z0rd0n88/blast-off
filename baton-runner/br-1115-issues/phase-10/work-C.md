# Phase 10 work unit C: README options guide and Technical details

- Commit: c45292a `docs: README options guide and technical details` (on db14a67; README.md, docs/spec.md,
  tests/70-docs.sh). Not pushed.
- README.md `## Options guide`: lines 165-219 (commands table 172-185, environment 187-218), placed
  before `## Exit codes`.
- README.md `## Technical details`: lines 265-413 (the last section, after `## Tests`): diagram 267-278,
  systemd 280-314, the runner 316-344, the child 346-383, job-dir state 385-413.
- Fact ledger: 110 rows added under `## README options guide and Technical details (unit C)`, all ok.
- Red: `GATE-ONLY: FAIL passed=0 failed=1 shellcheck=ok only=70-docs` (`FAIL: README has no '## Technical details' heading`).
  Negative probe of the verb check (help row deleted): `FAIL: README options guide has no row for '-h'`.
- Green: `GATE-ONLY: PASS passed=3 failed=0 shellcheck=ok only=00-harness,51-templates,70-docs`.
- ExecStart: `ExecStart=/home/alex/blast-off/.worktrees/blast-off-build/bin/blast-off run %f` (as expected).
- `git diff --stat origin/main...HEAD`: 10 files changed, 374 insertions(+), 40 deletions(-).

## Reviewer should check

- Duplication removed: README:12 no longer sends readers to the `bin/blast-off` header (it now links the
  two new sections); Requirements dropped "a pick below confidence `JOB_JEV_MIN_CONF` (default 0.7)
  keeps `CLAUDE_FLAGS`" in favour of the env table row (unit B's ledger row "pick below
  `JOB_JEV_MIN_CONF` ... README.md:19" now points at text that moved). A draft "Usage pause" paragraph
  in Technical details was cut because **Usage limits** already says it; the resume-timer paragraph
  links there instead and adds only the reset choice.
- Kept, short overlap: the `start` row repeats its refusals in one clause (the full passage stays in
  Check, then start); the `wait` row links the wait table rather than repeating it; exit codes link the
  Exit codes table. The Watch, stop, resume code block was left as is (a workflow example, not a reference).
- Exit codes found by probe, not by comment: `status` and `resume` exit 2 with no `checkpoint.md`
  (sed's code under `set -e`/`pipefail`); documented as such.
- `JOB_KEEP_WINDOWS` is any non-empty value, `0` included (code tests `-n`); the bin header's `=1`
  suggests otherwise. Documented as the code behaves; no code change.
- "Read by" column judgement: validation by `chain_nums` in start/resume is stated once in the
  paragraph above the table rather than per row, except where start reads the value for another reason
  (`JOB_JEV`, `JOB_SESSION`, `GH_TOKEN`).
- Left out: `BLAST_OFF_TEST_TIMEOUT` and `BLAST_OFF_NO_SHELLCHECK` are only pointed at (tests/run
  header), not described, per the brief. `phases/` is described as never written by blast-off (only a
  log hint in lib/checkpoint.sh:114). Lingering is stated only as code fact (no `loginctl` call); systemd
  semantics beyond the code comments (`--collect`, user-manager lifetime) are not claimed.
- The 70-docs check reads verbs from `case "${1:-}" in` ... `esac` lines indented two spaces; a
  reformatted case would trip the "at least 12 verbs" guard rather than pass silently.
- Ledger README line numbers inside a paragraph are approximate ranges within that paragraph.
