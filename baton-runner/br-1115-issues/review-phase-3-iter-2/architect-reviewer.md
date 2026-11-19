# architect-reviewer review: phase 3 round 2

Reviewed `git diff feat/br-1115-issues/phase-2...HEAD` (HEAD `ecc6e90`) for the nine named paths, by reading
and by a copy of `rev2/probe.sh` extended in my own temp dir (`/tmp/arch-rev2.5XoBp4`, removed at the end).
The probe sources `lib/ci.sh` with `log`, `chain_end`, `die` and `ci_head` stubbed; no `tests/run`, no gate,
no real `gh` call except one read-only `gh issue view 26`. "RAN" below means that probe; "=> DONE PASSES"
is the probe's line for `ci_check` returning 0 (the runner would then exit 0, "job done").

Architectural impact: Medium. The change is small (one function, one helper), but it sets the rule every
later phase and every job inherits for "which PRs gate `done`", and that rule has a wrong key (ARCH-1).

## Findings

### ARCH-1 | HIGH | lib/ci.sh:71-76 | The fallback is keyed on the whole table, so naming one PR in one Status cell shrinks the set read; a done row closed without its PR passes with a red record
- Failure path: the rule switches on "no Status cell names a PR", a property of the table, while the
  failure it guards ("a row closed without its PR") is a property of one row. A two-phase job where row 0
  has `PR #7` in its cell and row 1 was closed as `done (<sha>)` with `PR #8` only under `## Completed
  phases` (the shape `templates/checkpoint.md:47-49` prompts) exits 0 with `gate-logs/ci-pr-8.json`
  red on disk. The gate is non-monotonic: with no cell naming a PR it reads 7 and 8; add `PR #7` to one
  cell and it reads 7 only. The same holds for a row the runner does not see (key `P1`) whose own Status
  cell names its PR. The one line that says so goes to `run.log` right before `job done`, exit 0.
- Evidence: RAN.
  `mono_a` (neither cell names a PR): `no Phase plan Status cell names a PR; CI read for every PR checkpoint.md names instead: 7 8` then `END 10: PR #7 CI unread`.
  `mono_b` (row 0 names 7, record 7 green): `CI read for the PRs Phase plan Status cells name: 7; named elsewhere in checkpoint.md and not read: 8`, `=> DONE PASSES`.
  `tpl_shape` (template shape with ` · usage` cells, `ci-pr-8.json` verdict `failure`): same log line, `=> DONE PASSES`.
  `p1row` (`| P1 | a | b | done (abc1234) · PR #8 |`, record 8 red): `=> DONE PASSES`.
  REASONED: `tests/41-ci-wait.sh:96,127-129` pins this as wanted (`PR #96` in the `P1` row's own Status cell must stay unread, exit 0).
- New in the fix commit (the three-way rule); it is round 1's HIGH (P3R1-1) and MEDIUM P3R1-2 reshaped:
  the zero-PR case is closed, the some-rows case is open and now only logged.
- Suggested fix: key the fallback per row: read every PR the checkpoint names whenever any digit-keyed
  Phase plan row's Status cell names no PR (and, as now, when there is no row). Checked by reading against
  the fixtures: `fin` (rows 0 and 1 both name a PR) still reads 7 9 only; `np` and `nt` still fall back;
  `wf` (one row, `PR #14`) unchanged. Cost, to state in the spec: a job with one PR-less phase and another
  repo's PR in prose is refused until the prose is reworded (see ARCH-2 for the wording). The `P1` row
  stays unseen either way; that needs the row-recognition decision (P3R1-29), not this fix.

### ARCH-2 | HIGH | lib/ci.sh:76, lib/ci.sh:90 | In the fallback the hint cannot clear a `/pull/N` link, and the refusal tells the agent to run `ci-wait` on another repo's PR number
- Failure path: a job with no PR of its own whose prose links `https://github.com/o/other/pull/99`. The
  fallback reads 99. The hint says "write any other PR with no '#'", but the link has no '#' and still
  matches `/pull/[0-9]+`, so following the hint changes nothing. The last `run.log` line, the one
  `README.md:132` sends the reader to, is `PR #99 CI unread ... blast-off ci-wait <job-dir> 99, then run
  again`. `ci_wait` runs `gh pr view 99` in the workdir (`lib/ci.sh:17-18`), so it reads the workdir
  repo's PR 99: if that exists and is green, `done` passes on an unrelated PR's record; if not, `gh pr
  view 99 failed`, exit 1. The first half of the hint ("name this job's PR in its row's Status cell") has
  no row to act on in a table-less job, which the spec supports. So for these jobs issue 26's own edge
  case ("mentioning another repo's PR blocks done forever") is still there, and criterion 3 ("a `PR #N`
  in prose is ignored") does not hold.
- Evidence: RAN `hint_url` and `xrepo_link_nopr`: `no Phase plan Status cell names a PR; CI read for every PR checkpoint.md names instead: 99 (name this job's PR in its row's Status cell; write any other PR with no '#')` then `END 10: PR #99 CI unread: no readable record for PR 99 in gate-logs/ci-pr-99.json; blast-off ci-wait <job-dir> 99, then run again`. `hint_other` (`other PR 99`): `no PR named in checkpoint.md; CI not read`, passes. REASONED for what `ci-wait 99` then reads, from `lib/ci.sh:17-18`.
- New in the fix commit (hint text and fallback); the unread message is pre-existing, made worse by pairing.
- Suggested fix: reword the hint to cover both tokens ("if a PR here is not this job's, write it as
  `other PR N` and drop any `/pull/N` link"), and in the fallback branch put that sentence in the
  `chain_end` text too, so the last line carries it. `templates/checkpoint.md:32` needs the same
  "/pull/" clause.

### ARCH-3 | HIGH | lib/ci.sh:87 (README.md:132, docs/spec.md:97) | The absent refusal's remedy cannot work for an earlier stacked PR whose branch has no workflow file, and the cheapest exit is the one ARCH-1 leaves open
- Failure path: the workflow is added in phase 3. PRs 1 and 2 (stacked, heads cut before it) have absent
  records; workdir HEAD has `.github/workflows/ci.yml`, so `done` is refused for PR 1 with "push to the PR
  branch for a run that is not a workflow_dispatch, then blast-off ci-wait". A `pull_request` run uses
  the workflow files of the PR's merge ref (head merged into base); neither side holds the file, so no
  push to that branch starts a run unless the push itself adds the workflow, which changes the phase's
  code. An agent that follows the message pushes, waits 60 s in `ci-wait`, gets absent again and loops
  until the soft cap. The spec says "there is no override". The exit a child will find is in
  `templates/checkpoint.md:30`: "A row closed without one gets no CI check": delete ` · PR #1` from the
  cell and, by ARCH-1, `done` passes with a log line. A dead-end refusal beside an opt-in cell makes
  removing the token the cheapest move; the strict branch and the lenient branch are both switched by
  the one cell the gated child writes. This is also the incident issue 26 cites (round-1 open question 5:
  PRs 1 to 8 predate `ci.yml`).
- Evidence: REASONED. Code: `lib/ci.sh:86-87` reads `git -C "$TOP" ls-tree ... HEAD`; spec row 10 states
  "a workflow added in a later phase also refuses the earlier PRs". GitHub's choice of workflow file for
  `pull_request` is from recall, not run. `.github/workflows/ci.yml:9-11` is `on: pull_request` with no
  branch filter, so in this repo a stacked PR whose head has the file does get runs.
- New in this diff (b9c39ad); the remedy text is new in the fix commit.
- Suggested fix: decide "runs were due" per PR from that PR's head: `ls-tree` the record's `head_sha`
  (already proven to be the PR's head by `ci_head`) instead of HEAD; a head object missing locally is a
  refusal. Then the remedy is true wherever the gate refuses. Known limit to state: a workflow only on the
  base is not seen. If HEAD stays the key, the message must say what to do when the PR branch has no
  workflow file (set `blocked` for the owner), not "push".

### ARCH-4 | MEDIUM | docs/spec.md:97, lib/ci.sh:64-66 | The spec and the code comment claim more than the code keeps
- Failure path: spec row 10: "so a missing table, a heading or row the runner does not read, or a row
  closed without its PR never lets done through with a named PR unread, P3R1-1". The comment: "The gate
  fails closed (P3R1-1): when no Status cell names a PR (..., a row the runner does not read, a row
  closed without its PR)". Both are true only when no other cell names a PR; ARCH-1's probes are a row
  closed without its PR and a row the runner does not read, each passing with a named PR unread.
- Evidence: REASONED from those lines against RAN `mono_b`, `tpl_shape`, `p1row`.
- New in the fix commit.
- Suggested fix: fix ARCH-1 and keep the sentence for the "row closed without its PR" case, or change
  "never" to "when no Status cell at all names a PR".

### ARCH-5 | MEDIUM | templates/checkpoint.md:29-32 (tests/51-templates.sh:74-75) | The template now tells the gated child how a row skips the CI check, and a test pins the sentence
- Failure path: "A row closed without one gets no CI check" is accurate, and it is read by every child as
  an instruction file. With ARCH-3 it reads as the way out of a refusal. `tests/51-templates.sh` pins
  three sentences of a rule that four owner questions still leave open, so any answer breaks the test.
- Evidence: REASONED from the diff.
- New in the fix commit.
- Suggested fix: after ARCH-1, the sentence becomes "every closed row names its PR; a row without one
  makes the runner read every PR named anywhere here". Pin one phrase, not three.

### ARCH-6 | MEDIUM | README.md:132, README.md:114-117 | The exit 10 row names only Status-cell PRs and gives no remedy for the fallback or for the dead end
- Failure path: "done refused: the CI of a PR named in a Phase plan Status cell ..." is false in the
  fallback, where a prose PR causes exit 10. "the last `run.log` line names the PR and the case" holds
  (no log follows `chain_end`; `child_stop_all` logs nothing), but in the fallback the line that explains
  why a prose PR was read is the one before it. "Absent: push to the PR branch so a run starts" is the
  ARCH-3 remedy. Lines 114-117 are accurate.
- Evidence: REASONED from `lib/ci.sh:74-76,87-90`, `lib/chain.sh:6`, `lib/child.sh:29-33`.
- New in the fix commit.
- Suggested fix: "a PR named in a Phase plan Status cell (or, with none there, anywhere in
  `checkpoint.md`)"; add "a PR that is not this job's: reword it as `other PR N`, no `/pull/` link".

### ARCH-7 | MEDIUM | lib/ci.sh:97 | A NUL byte in one Status cell, or anywhere in a checkpoint read by the fallback, blanks the PR list and `done` passes
- Failure path: GNU grep 3.11 prints nothing on stdout for binary input ("binary file matches" goes to
  stderr, exit 0). Both reads now go through the one `ci_prs`, so a NUL in a Status cell empties the cell
  read and the whole-file read together: `no PR named in checkpoint.md; CI not read`, exit 0. A NUL
  elsewhere keeps the cell read but silently empties the "named elsewhere" list.
- Evidence: RAN. `nul_cell`: `grep: (standard input): binary file matches` twice, `LOG: no PR named in checkpoint.md; CI not read`, `=> DONE PASSES`. `nul_prose` (no table, `PR #7` in prose, a NUL line): same, passes. `nul` (NUL outside the cell): cell PR 7 read, no "named elsewhere" list. Invalid UTF-8 did not trigger it under `C.UTF-8` (`badutf8`, `badutf8_prose`, `latin1_cell` all refused); other locales not checked.
- Pre-existing (P3R1-28, LOW, "grep -a not added"), made worse: the fallback that closes P3R1-1 shares the hole.
- Suggested fix: `command grep -aoiE` in `ci_prs`.

### ARCH-8 | MEDIUM | lib/ci.sh:78, lib/ci.sh:97 | A cell that visibly names a PR in another spelling ends in "no PR named in checkpoint.md; CI not read" and exit 0
- Failure path: the regex is the gate's whole arming condition, and every spelling it misses lands in the
  third branch, which passes. `PRs #7, #8`, `PR 7`, `PR  #7`, `#7`, `pull request #7` in the only Status
  cell: pass. `PR #7, #8` reads 7; 8 is not read and not listed as "named elsewhere". The log line states
  something untrue ("no PR named").
- Evidence: RAN `plural`, `nohash`, `barehash`, `twospace`, `pullreq`: each `LOG: no PR named in checkpoint.md; CI not read`, `=> DONE PASSES`. `list`: `CI read for the PRs Phase plan Status cells name: 7`.
- Pre-existing regex; P3R1-9 reshaped (silent pass became a logged pass).
- Suggested fix: inside Status cells only, count any `#N` and `/pull/N` (the cell is the job's own
  space; `other PR N` has no '#'); keep the strict token for the whole-file read. At least word the line
  "no `PR #N` or `/pull/N` token found".

### ARCH-9 | MEDIUM | lib/ci.sh:70 | `ci_check` parses the checkpoint table itself: the sixth copy of the row range and the third of `$(NF-1)`
- Failure path: `sed -n '/^## Phase plan/,/^## /{/^| *[0-9]/p}'` now sits in `lib/checkpoint.sh:11,40,48,54`,
  `lib/preflight.sh:77` and `lib/ci.sh:70`; `$(NF-1)` in `lib/checkpoint.sh:41,56` and `lib/ci.sh:70`.
  `lib/checkpoint.sh` is the module that owns the format ("read the job's checkpoint.md"). A later phase
  that changes row recognition (missing trailing pipe, row keys, heading match: all open in round 1) must
  change six places, and no test checks that receipts and CI agree on what a row or a Status cell is.
- Evidence: REASONED; `grep -n "sed -n '/^## Phase plan/" lib/*.sh` gives the six lines.
- Pre-existing made worse (P3R1-29, LOW, left open as "a refactor outside issue 26").
- Suggested fix: one line in `lib/checkpoint.sh`, `cp_status_cells() { <the sed> | awk -F'|' '{ print $(NF-1) }'; }`,
  called by `ci_check`. Folding the other five onto one `cp_rows` can wait.

### ARCH-10 | MEDIUM | README.md:114-117,132; docs/spec.md:97,228; lib/ci.sh:57-66,73-78; templates/checkpoint.md:29-32; tests/51-templates.sh:74-75; tests/41-ci-wait.sh:5-8 | The three-way rule is written out in about eight places while four owner questions on it are open
- Failure path: any owner answer (or ARCH-1's fix) means editing all of them in step; two are pinned by
  tests on exact wording (`51-templates` three sentences, `41-ci-wait` two log lines). Drift between them
  is how round 1's five doc findings arose.
- Evidence: REASONED from the diff.
- New in the fix commit.
- Suggested fix: keep the full rule in spec row 10 and the `ci_check` comment; README, template and
  `--help` state the outcome in one clause and point to the spec. Settle the owner questions before
  pinning more wording.

### ARCH-11 | LOW | lib/ci.sh:97 | `paste`: no dependency list should name it; the baton's declaration is right
- Failure path: none today. `DEPS` (`lib/chain.sh:84`) names no base tool except `realpath`; `sort`, `tr`,
  `cut`, `wc`, `tee`, `date`, `timeout`, `sha256sum`, `mktemp`, `readlink` are used and unlisted, and
  `paste` comes from the same package. Adding it would make the list less consistent, not more. A
  missing `paste` fails closed, but only at `done`, after the whole job ran, as exit 1 with the reason
  on stderr.
- Evidence: RAN a top-level script (`set -euo pipefail`, `paste` stubbed to return 127): `paste: command not found`, script exit 127, no "DONE PASSES"; `printf '' | paste -sd' '` prints one newline, which `$(...)` drops. REASONED that the runner turns 127 into exit 1 (`lib/chain.sh:21-22`).
- New in the fix commit.
- Suggested fix: none needed. If the reliance is unwanted, `tr '\n' ' '` is the idiom already at
  `lib/chain.sh:154,169` (it leaves a trailing space the log pin would see). Separate and pre-existing:
  `README.md:16` Requirements omits `git`, which `DEPS` checks.

### ARCH-12 | LOW | docs/spec.md:228 | "that heading only" is a prefix match
- Failure path: `## Phase planning notes` opens the range, and a second `## Phase plan` heading re-opens it.
- Evidence: RAN `prefixhead`: `CI read for the PRs Phase plan Status cells name: 55`; `twoheads` reads 7 from the second heading.
- Pre-existing parser (`lib/checkpoint.sh`), new doc claim.
- Suggested fix: say "a heading starting `## Phase plan`".

### ARCH-13 | LOW | docs/spec.md:97 | "the Status cell is the last cell" holds only for a row with a trailing pipe
- Failure path: `$(NF-1)` on a row with no trailing `|` is the cell before the last. Alone it falls back
  (refused); beside a well-formed row it is ARCH-1's unread case.
- Evidence: RAN `notrail` and `escpipe`: both fall back and refuse.
- Pre-existing parser, new doc claim.
- Suggested fix: with ARCH-9's helper, strip or require the trailing pipe in one place.

### ARCH-14 | LOW | lib/ci.sh:2,86 | `ci_check` reads the global `TOP` that only `chain_run` sets
- Failure path: a later phase that calls `ci_check` or a "which PRs will be read" line from `status` or
  `preflight` dies on an unbound variable under `set -u`. The header now says so (P3R1-35), which is the
  right minimum.
- Evidence: REASONED.
- New in this diff.
- Suggested fix: none now; pass the repo root as an argument when a second caller appears.

### ARCH-15 | LOW | lib/ci.sh:88 | Outside git the log says "no workflow file at HEAD" though nothing was read
- Evidence: REASONED from `lib/ci.sh:86-88` (`TOP` empty skips the read). P3R1-32, still open.
- Suggested fix: "workdir is in no git repo; workflow files not read".

### ARCH-16 | LOW | bin/blast-off:37-38, docs/spec.md:35 | Header and F7 row are accurate as summaries; two wording nits
- `bin/blast-off:37-38`: "a PR's CI red, unread, or absent (no runs) while HEAD has a workflow file" can
  be read with the last clause on all three. F7 says `lib/chain.sh` refuses; the refusal is `ci_check` in
  `lib/ci.sh` (pre-existing). Neither claims anything the code does not do.
- Evidence: REASONED. `--help` prints lines 2 to 38, so the new line shows.

## Round-1 findings checked
| ID | resolved / reshaped / open / not checked | why |
|---|---|---|
| P3R1-1 (HIGH) | reshaped | zero-PR case refused or logged; one cell naming a PR switches the fallback off (ARCH-1) |
| P3R1-2 | reshaped | now logged, still exit 0 with a red record on disk (ARCH-1) |
| P3R1-3 | open | workdir HEAD still the key; limit stated in spec row 10; remedy false for earlier stacked PRs (ARCH-3) |
| P3R1-4 | open | any file counts, no override; message reworded but still a dead end (ARCH-3) |
| P3R1-5 | reshaped | template now true, and tells the child how a row skips the check (ARCH-5) |
| P3R1-6 | resolved | SKILL step 4 states both cases as the code has them (omits the non-git pass) |
| P3R1-7 | reshaped | README names absent and Status cells; exit 10 row wrong for the fallback (ARCH-6) |
| P3R1-8 | resolved | header names the absent case (ARCH-16 nit) |
| P3R1-9 | reshaped | misses now end in a log line that says "no PR named" (ARCH-8) |
| P3R1-10 | resolved for what it asked | `nt`, `np` cases read; no case for a mixed table |
| P3R1-11 to -14, -18 to -20 | not checked | test-strength findings; I ran no scenario and no mutant |
| P3R1-15 to -17 | resolved, with a catch | fixtures read; -17's `P1` row pins ARCH-1's behaviour as wanted |
| P3R1-21 | reshaped | spec row 10 fuller, and now overclaims (ARCH-4, -12, -13) |
| P3R1-22 | reshaped | "re-run" gone; "push" cannot work for ARCH-3's case |
| P3R1-28 | open, wider | no `grep -a`; fallback shares the hole (ARCH-7) |
| P3R1-29 | open, one copy worse | ARCH-9 |
| P3R1-30 | open | RAN `xrepo_link_status`: another repo's `/pull/99` in a Status cell is read (refused, fail-closed) |
| P3R1-32 | open | ARCH-15 |
| P3R1-35 | resolved | header names `TOP` |
| others | not checked | outside this lens |

## Owner questions (1-4): is the default the safe one?
1. Whole-file read when no Status cell names a PR: yes in direction (it refuses), no as built. Alternative
   (a) is weaker, (b) breaks PR-less jobs. The key should be per row (ARCH-1) and the hint is wrong for
   links and for table-less jobs (ARCH-2).
2. Workdir HEAD decides "runs were due": no. It refuses earlier stacked PRs for which no push can start a
   run (ARCH-3), and passes absent when HEAD dropped the file or it is uncommitted. The PR's own head (the
   record's `head_sha`) is the key under which the refusal and its remedy agree.
3. Any file counts, no override: yes for the narrow question (it only ever refuses more). Counting only
   `*.yml`/`*.yaml` is harmless. An override is worth having only if the child cannot write it (an env
   name passed by `start`, logged); without one, the token-removal exit in ARCH-3 is the real override.
4. Status cells name some PRs, a PR named elsewhere is logged and not read: no. It is the fail-open in
   ARCH-1. The per-row key reads it without bringing back issue 26's bug for jobs whose every row names
   its PR.

## What I did not check
- Any `tests/run` scenario, the gate, or mutants (by rule); `tests/41-ci-wait.sh` was read, not run.
- Real `gh` and GitHub behaviour: which workflow file a `pull_request` run uses, branch and path filters,
  the literal `workflow_dispatch` event value. ARCH-3 rests on recall for the first.
- Locales other than `C.UTF-8` for ARCH-7; awk implementations other than this box's.
- `tests/70-docs.sh`, `tests/51-templates.sh` beyond the diff, `tests/fakes/gh` beyond the diff,
  `lib/child.sh`, `lib/units.sh`, `lib/usage.sh`, `lib/jev.sh` beyond greps.
- Paths from `status: done` to exit 0 outside `lib/chain.sh:159` (the only `chain_end 0`); `unit_resume`
  and the timer were not traced.
