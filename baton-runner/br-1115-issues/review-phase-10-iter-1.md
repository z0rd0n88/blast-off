VERDICT: CLEAN

# Phase 10 review, round 1

Diff: `git diff origin/main...HEAD` (0a5d3b1, db14a67, c45292a): 10 files, +374 -40. No line of
`bin/blast-off`, `lib/*.sh` or `systemd/` code changed (comments only); `tests/70-docs.sh` gained
8 test lines (P10R1-16); `templates/brief.md` has no diff, so section 9 is unchanged.

- Gate (run once, `BLAST_OFF_TEST_ONLY` unset): `GATE: PASS passed=19 failed=0 shellcheck=ok`
- ExecStart: `ExecStart=/home/alex/blast-off/.worktrees/blast-off-build/bin/blast-off run %f` (as expected)
- Fixed and deleted rows: 40 checked (38 fixed, 2 deleted; the 11 "counted above" rows repeat them).
  39 of 40 pass. The one that fails is ledger line 32 (README.md:69-70), see P10R1-2. Both deletions
  were right: no code backs "the caller's background command has one", and test 13-wait.sh:132
  checks only the exit code, not "after 10 s on wait's clock".
- Random sample of "ok" rows: 31 rows, drawn with `shuf --random-source=<(yes 10)` (script
  `scratchpad/r10/rows.sh sample`). 15 from unit B (ledger lines 13, 15, 16, 19, 22, 25, 28, 33,
  36, 39, 68, 71, 74, 77, 80) and 16 from unit C (313, 316, 319, 320, 323, 325, 326, 327, 328,
  332, 335, 362, 365, 369, 372, 376). 29 of 31 pass (93.5%): unit B 14 of 15, unit C 15 of 16.
  - Fail, line 16: the Requirements list leaves out `git` and `realpath`, which the runner
    refuses to start without (P10R1-6).
  - Fail, line 332: "writes nothing" is false. `preflight` runs `git fetch origin <JOB_BASE>`
    (P10R1-5).
  - True but stale, line 15: README.md:12 no longer links the `bin/blast-off` header, because unit C
    changed it (P10R1-15).
- Probe: `blast-off status` and `blast-off resume` on a job dir with no `checkpoint.md` both exit 2
  (`sed: can't read ...`), so the Options guide is right on that.
- CHANGELOG: there are 11 worked days in `git log --date=short` (2026-11-04 to 11-19), and every one
  has an entry, newest first, with the update note at the top. I spot-checked 11-18 (d5e27e2,
  b917cec), 11-10 (ed18476, 8bc3164), 11-09 (acf9051) and 11-17 (#22 PR 38, #39 PR 41, b010b90);
  all match.
- Coverage: PRs 32, 33, 34, 35, 37, 38, 41, 43, 45, 48 and 49 each have a doc location. All of that
  text still exists at HEAD, but the README line numbers in coverage.md are from 0a5d3b1 and have
  since shifted (P10R1-15).
- Env vars: every name from `grep -ho '\b\(JOB\|BLAST_OFF\)_[A-Z_]*' bin/blast-off lib/*.sh` is in
  the README except `BLAST_OFF_HOME`, which the script computes and never reads from the
  environment, and the bare `JOB_` prefix. `JOB_DIR`, `JOB_CHILD`, `TYPESAFE_API_KEY` and
  `JEV_BASE_URL` are covered in Technical details. Every verb that `bin/blast-off` dispatches has an
  Options guide row.
- Style: added lines have no em or en dashes and no curly quotes. Some lines run long (P10R1-14).

Counts: CRITICAL 0, HIGH 0, MEDIUM 3, LOW 13.

## Findings

### P10R1-1 MEDIUM bin/blast-off:26: `JOB_KEEP_WINDOWS=1` header line disagrees with the code and README
The header's env lines read `NAME=default`, as in `JOB_CHILD_TIMEOUT=7200` and `JOB_JEV=1`. So
`JOB_KEEP_WINDOWS=1` reads as "default 1", and it suggests `0` turns the feature off. The code
tests only whether the value is non-empty (`[ -n "${JOB_KEEP_WINDOWS:-}" ]`, lib/chain.sh:22,
lib/child.sh:137, :144). That makes the default off, and `JOB_KEEP_WINDOWS=0` keeps windows.
README.md:206 now says "any non-empty value, `0` too", which matches the code. The header was not
changed, and the ledger checked it only as the coarse row "env defaults and meanings ... ok"
(fact-ledger.md:210).
Fix, replace line 26 with:
`#        JOB_KEEP_WINDOWS          set to any value (0 too): leave finished children's windows open`

### P10R1-2 MEDIUM README.md:69-70 (fixed ledger row, line 32): "every set `JOB_*` and `BLAST_OFF_*` name the runner reads" is not the list `start` passes
`unit_env` (lib/units.sh:24-26) passes `BLAST_OFF_CI_APPEAR` and `BLAST_OFF_CI_WATCH`. The runner
never reads either one. Only `ci-wait` reads them (lib/ci.sh:21, :26), and a child runs it. So the
sentence says these two names are not passed, but they are. `BLAST_OFF_WAIT_POLL` is correctly
left out, but nothing says so. README.md:291 ("a `--setenv=NAME` ... for each name [Check, then
start] lists") points back at this sentence, so the error carries into Technical details.
Fix, replace "every set `JOB_*` and `BLAST_OFF_*` name the runner reads (not `JOB_BASE` or
`BLAST_OFF_ESTIMATE_FROM`, which only `preflight` reads)" with:
"every set `JOB_*` and `BLAST_OFF_*` name the runner or its children read (not `JOB_BASE` or
`BLAST_OFF_ESTIMATE_FROM`, which only `preflight` reads, nor `BLAST_OFF_WAIT_POLL`, which only
`wait` reads)"

### P10R1-3 MEDIUM README.md:393: job-dir table says `runner-end` is "deleted at each run's start"
P6R3-11 corrected this exact wording, and unit B fixed it in docs/spec.md:49-51 and
lib/chain.sh:8-10. The runner deletes the file only after it takes the lock (lib/chain.sh:165,
:170). A run that exits before the lock leaves an earlier `runner-end` in place: for example
`CLAUDE_FLAGS` empty, a missing dependency, a bad `JOB_*` number, a garbled `child-count`, or a
live lock (:148-156, :42). Step 3 of the same section ("Setup. It deletes `runner-end`", after
"1. Lock") is right, so the table contradicts it.
Fix, replace "deleted at each run's start" with "deleted by each run once it holds the lock".

### P10R1-4 LOW docs/spec.md:121: "Code 2 is unused" is now contradicted by the Options guide
`status` and `resume` exit 2 when `checkpoint.md` is missing (I probed both: rc=2, sed's code
under `set -euo pipefail`; lib/units.sh:61, :77), and README.md:176 and :179 now say so. Ledger
row fact-ledger.md:160 used `grep exit 2` as evidence, which misses an implicit exit under
`set -e`.
Fix: "The runner never exits 2 (bash reserves it for builtin misuse); `status` and `resume` exit 2
only when `checkpoint.md` is missing. Every non-zero code except 1 is a state, ..."

### P10R1-5 LOW README.md:182, docs/spec.md:63, lib/preflight.sh:6: `preflight` "writes nothing"
`pf_behind` runs `git fetch -q origin "$base"` (lib/preflight.sh:142). That updates the workdir
repo's `origin/<JOB_BASE>` ref and `FETCH_HEAD`. What stays unwritten is the job dir (`LOG=/dev/null`,
test 60 checks "job dir unchanged").
Fix, README row: "Prints what a start would use and meet; writes nothing to the job dir (`behind`
runs `git fetch origin <JOB_BASE>`)". Spec: "writing nothing to the job dir". lib/preflight.sh:6:
"It writes nothing to the job dir: log lines go to stdout only."

### P10R1-6 LOW README.md:19: Requirements leaves out `git` and `realpath`
`DEPS="claude tmux python3 jq systemd-run systemctl git realpath"` (lib/chain.sh:89). The runner
stops with `<b> not on PATH` when either is missing (:149). The `PATH` row at README.md:215 lists
both, so the two places disagree.
Fix: "bash, tmux 3.2 or later, jq, python3, git, coreutils `realpath`, systemd (user manager),
`claude`, `gh`; ..."

### P10R1-7 LOW README.md:189-190: "children inherit the unit's environment through the job's tmux server"
The server drops every `CLAUDE*` name and `OPENROUTER_API_KEY` (lib/child.sh:14, :22), so
`CLAUDE_FLAGS` itself never reaches a child's environment. The `OPENROUTER_API_KEY` row is
right, and so is Technical details (:350-351). Only this parenthesis is too broad.
Fix: "(children inherit the unit's environment, less every `CLAUDE*` name and
`OPENROUTER_API_KEY`, through the job's tmux server)".

### P10R1-8 LOW docs/spec.md:116-117: wait's exit-1 summary in section 3 misses two causes
Unit B added "no `<job-dir>` argument" and "a workdir name that is not letters, digits, `-` or
`_`" to section 2 (:61) and to README.md:129. The section 3 summary still lists only "no job dir,
a missing or empty `checkpoint.md`, a bad `BLAST_OFF_WAIT_POLL`, `systemctl --user` failing".
Fix: "(no `<job-dir>` argument or job dir, a workdir name blast-off refuses, a missing or empty
`checkpoint.md`, a bad `BLAST_OFF_WAIT_POLL`, `systemctl --user` failing)".

### P10R1-9 LOW lib/child.sh:39: comment still says "'; exit' makes the shell fork"
Unit B fixed the same claim in docs/spec.md:153 ("the commands after `claude`"), because the
command is now `...; rc=$?; echo $rc > $CHILD_DIR/exit; exit $rc` (lib/child.sh:50). The
comment is in scope (a lib doc comment) and was cited as evidence in ledger row 167.
Fix: "so the commands after claude make the shell fork systemd-run rather".

### P10R1-10 LOW scripts/gate.sh:2-4: says "every scenario" and a `GATE:` verdict
Under `BLAST_OFF_TEST_ONLY`, `tests/run` runs only the named scenarios (tests/run:46). Its last
line is then `GATE-ONLY: ...` (:86-88), not `GATE:`. README.md:259-260 now documents
`scripts/gate.sh`. My view: fix it in this PR, because it is a two-line comment on a script this
PR documents. But `scripts/` is outside the spec's file list, so it needs the owner's OK
(scope rule).
Fix, lines 3-4:
`# repo's own gate, tests/run (every scenario, or those BLAST_OFF_TEST_ONLY names, then shellcheck), tees`
`# the output to <log-dir>/tests-run.log and exits with tests/run's status; the last line is its GATE: (GATE-ONLY: under BLAST_OFF_TEST_ONLY) PASS|FAIL verdict.`

### P10R1-11 LOW systemd/blast-off@.service:5-6 (outside the spec file list): "reading every [Service] directive below as a -p property"
`unit_start` skips `ExecStart=` (lib/units.sh:46). The comment is out of scope, so this is for the
owner to decide. Fix: "reading every [Service] directive below but ExecStart= as a -p property".

### P10R1-12 LOW CHANGELOG.md:16-17: final wording for the phase 10 bullet
Replace the placeholder with:
"- Docs: the README gains an Options guide (every command with its exit codes, every environment
  variable with its default and effect) and a Technical details section (systemd units and the
  resume timer, the runner loop, the child, job-dir files); every claim in the README, spec, skill
  and code comments was checked against the code and fixed where wrong; this changelog
  (PR #<n>)."
Keep it under 2026-11-19 if its commits keep that author date. The ledger notes that GitHub's
`mergedAt` for 48 and 49 is already 2026-11-20Z.

### P10R1-13 LOW CHANGELOG.md:44: "with a test for the reset" is unclear
Test 20-dead-child checks that `CHILD_NOSTATUS` clears for the next child.
Fix: "A dead child pane that gave no exit status is now logged, and the flag clears for the next
child (#29, PR #32)."

### P10R1-14 LOW style: edited lines over 110 columns, where the text around them wraps near 100
lib/chain.sh:129 (135), lib/preflight.sh:5 (122), :21 (134), skills/blast-off/SKILL.md:69 (128),
tests/60-preflight.sh:4 (121), bin/blast-off:10 (122), README.md:70 (116). Fix: rewrap each one
near 100 with no change to the words. (The long docs/spec.md lines were already long, and so are
many README table rows.)

### P10R1-15 LOW baton records: stale locations after unit C moved text
- fact-ledger.md:18 ("pick below `JOB_JEV_MIN_CONF` ... README.md:19"): that text is now at
  README.md:198, which is ledger row 342. Fix: change the location to "moved by unit C: README.md:198
  (row 342)", or drop the row and its count.
- fact-ledger.md:15: README.md:10-13 no longer links the `bin/blast-off` header. Fix the claim to
  "links docs/spec.md, docs/systemd-guide-deviations.md, the Options guide and Technical details,
  the launcher prompt copy and CHANGELOG.md" at README.md:10-15.
- fact-ledger.md:160: the evidence misses implicit exits under `set -e` (see P10R1-4).
- coverage.md: the README line numbers are from 0a5d3b1. Text after README.md:165 has since moved
  about 57 lines (for example, Tests :198-205 is now :256-263). The PR 45 row's README.md:18-19 is
  now README.md:198. Fix: refresh the README line numbers at the final commit.

### P10R1-16 LOW tests/70-docs.sh:37-44: executable test lines added in a "docs only" phase
The spec's file list covers only "header/doc comments in ... tests/*.sh", and the brief says no
code line should change. The 8 new lines check that README has `## Technical details` and an
Options guide row for every verb read from `bin/blast-off`'s `case`. They change no blast-off
behaviour, and spec section 6 (row 70-docs) records them. My view: keep them. Question 2 below
asks the owner.

## Checks with no finding
- Every Options guide command row, and every env row, matches the code. Checked: the exit codes
  of `start` (systemd-run's code via `|| return` under `set -e`), `stop`, `logs`, `resume`, `wait`,
  `receipt`, `ci-wait` and `--help`; who reads each env var; the defaults; the
  `JOB_JEV_MIN_CONF` regex; `JOB_KEEP_WINDOWS` semantics.
- Technical details: the systemd paragraphs (template lines, transient `-p` properties, the
  resume timer's calendar time, margin, minimum 5 s, `AccuracySec=1s`, the no-timer cases, no
  `loginctl`), runner steps 1-4 in code order, child (server env, Jev call, launch command,
  exit file, wait order, trust keys, end handling, `JOB_KEEP_WINDOWS`), the job-dir table except
  P10R1-3, receipts and CI. All match lib/*.sh.
- Diagram present (README.md:267-278). The duplication with Usage limits and Closing a phase is
  short, and each overlap links the other section.
- skills/blast-off/SKILL.md: one clause added (`and JOB_JEV is not 0`). No instruction was cut or
  softened. templates/brief.md: no diff.

## Questions for the owner
1. P10R1-10 and P10R1-11: may this PR also fix the `scripts/gate.sh` header and the
   `systemd/blast-off@.service` comment? Both are outside the spec's file list.
2. P10R1-16: keep the 8 new lines in tests/70-docs.sh (my recommendation), or move them to a
   follow-up so this PR stays docs only?
