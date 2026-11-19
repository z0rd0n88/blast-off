# architect-reviewer: phase 3 (issue 26), review round 3

13 findings: 0 CRITICAL, 1 HIGH, 4 MEDIUM, 8 LOW.
The HIGH is the row boundary. Ruling 1 moved all PR discovery onto `cp_plan_rows`, which reads only lines matching `^| *[0-9]` inside `## Phase plan`. A done row it does not read (key `P1`, bold key, indented, a row after a stray `## ` line) is skipped by the receipt gate, the all-rows-done gate and now the CI gate. Phase 2 refused the same checkpoints; this diff ends `job done`, and `tests/41-ci-wait.sh:93-99,132` pins the skip.
Rows the parser does read behave as the rulings say; the four round-2 HIGHs are gone for those rows.
Texts: twenty sentences are untrue, stale or at odds with another (ARCH-5, ARCH-6), and `templates/brief.md` §9.4 contradicts §9.9 (ARCH-2).
The fake's `fin` masks no assertion in scenarios 10, 11, 12, 20, 21, 22, 23, 30, 31, 32, 40, 50 (ARCH-8).

Method. Read-only. No scenario run. `bash -n` on `lib/ci.sh`, `lib/checkpoint.sh`, `lib/chain.sh`, `tests/fakes/claude`, `tests/fakes/gh`, `tests/41-ci-wait.sh`, `tests/51-templates.sh`: clean. `shellcheck -S warning` on `lib/ci.sh`, `lib/checkpoint.sh`, `tests/fakes/claude`, `tests/fakes/gh`: clean. Probes: `lib/checkpoint.sh` + `lib/ci.sh` sourced in a throwaway bash with stubs (`chain_end`, `log`, `gh`, `JOB`, `TOP=`), HEAD's copy beside phase-2's copy (`git show feat/br-1115-issues/phase-2:lib/...`), in `/tmp/p3r3-architect-reviewer.6KJ1sQ` (left in place; script `probe.sh` there). End-to-end exits are cited from the coordinator's `review-phase-3-iter-3/unit-mutants.log` (probes q1 to q61, mutants m1 to m10).

### ARCH-1: a done row the parser does not read is skipped by every gate; phase 2 refused the same checkpoint, and test 41 pins the skip
- Severity: HIGH
- File: lib/checkpoint.sh:43 (`/^## Phase plan/,/^## /{/^| *[0-9]/p}`), lib/ci.sh:70-84, tests/41-ci-wait.sh:93-99 and :132, templates/checkpoint.md:24
- Reachable by a template-following job: only by an off-template checkpoint. A child or owner must have written a Phase plan row whose line does not start `|`, spaces, digit (key `P1` or `Phase 1`, a bold key `**1**`, an indented table, a tab after the pipe, no leading pipe), or put a `## ` line (a sub-heading, a second `## Phase plan`) in the middle of the table. The template says "Each row's first cell starts with a digit"; nothing refuses a row that does not.
- Direction: fail-open
- Origin: introduced by this diff for the CI gate (phase-2 `ci_check` read `PR #N` from the whole file and refused every case below). Pre-existing for the receipt gate (exit 9) and the all-rows-done gate (cases F and S4 pass on both sides).
- Failure path: checkpoint with `status: done`, one read row `| 0 | a | b | done (abc1234) · no PR |`, one unread done row that names PR #7, and a red `gate-logs/ci-pr-7.json`. `cp_done_cells` prints only row 0. `ci_check` sees one cell, `no PR`, logs `CI at done: PRs read: none; rows that say no PR: 0`, returns; `chain_end 0 "job done"`. `cp_open_rows` is empty too, so `receipt_all_done` passes, and `receipt_check` asks no receipt for the unread row. The run.log line is the only trace, and it reads as a clean pass.

  | Case | Second row (after row 0 `no PR`) | HEAD | phase-2 lib |
  |---|---|---|---|
  | A | `\| P1 \| a \| b \| done (abc1234) · PR #7 \|` | job done | exit 10, PR #7 red |
  | B | `\| **1** \| ...PR #7 \|` | job done | exit 10 |
  | C | two spaces, then `\| 1 \| ...PR #7 \|` | job done | exit 10 |
  | D | `1 \| a \| b \| done (abc1234) · PR #7 \|` (no leading pipe) | job done | exit 10 |
  | E | `\|<TAB>1 \| ...PR #7 \|` | job done | exit 10 |
  | L | `\| Phase 1 \| ...PR #7 \|` | job done | exit 10 |
  | K | `### Later`, then `\| Phase 2 \| ...PR #7 \|` | job done | exit 10 |
  | S1 | `## Phase 1 notes`, then `\| 1 \| ...PR #7 \|` (a digit row cut off by a `## ` line) | job done | exit 10 |
  | S2 | a second `## Phase plan` line mid-table, then `\| 1 \| ...PR #7 \|` | job done | exit 10 |
  | F | `\| P1 \| a \| b \| pending \|` (an open phase) | job done | job done |
  | S4 | `## Note`, then `\| 1 \| a \| b \| pending \|` | job done | job done |
  | H (control) | only a `P1` row, no read row | exit 10, no done row | exit 10 |
  | S3 (control) | a second `## Phase plan` section later in the file | exit 10, PR #7 read | exit 10 |

- Evidence: my stub probe, both libs, same input (table above). The HEAD column is `ci_check` returning in the stub, with `cp_phases=1 done_rows=[0] open_rows=[]` in every fail-open case; that the two receipt gates also pass is from reading `lib/receipt.sh:50,69` (they loop over those same two lists). End to end, cases A, B and C only: `unit-mutants.log` q1 (`P1`), q2 (`**1**`), q3 (indented): `exit 0 ... job done`, `PRs read: none`, with PR #7's red record in the job. `tests/41-ci-wait.sh:97` puts `| P1 | a | b | c | done (abc1234) · PR #96 |` inside the table and `:132` fails the scenario if PR #96 is read; the comment at `:93` says it "must not hold done back". Lineage: round 1's P3R1-29 (row recognition), carried in round 2 under P3R2-1 and P3R2-20; `baton-phase-3-fix-2.md:38` calls it a "deliberate limit, open". In round 2 the whole-file fallback still caught some of these; it is gone now. S1 and S2 are new here: q61 covered only two adjacent headings, which fail closed.
- The boundary, exactly: a row the parser reads but does not class as done fails closed at exit 9, "phase row <k> is not done" (`unit-mutants.log` q6 no trailing pipe, q7 `✅ done`, q8 `**done**`, q9 `complete`, q11 key `1)`, q12 a cell after Status). Only a line the first `sed` drops is skipped.
- Why it matters under ruling 1: the ruling says every done row's Status cell must hold `PR #N` or `no PR` and that prose is never read. These are table rows, not prose. Before the ruling the whole-file read was the net under the parser; the ruling removed the net, so the parser's whitelist became the gate. A whitelist is sound only if what it does not recognise is refused, not skipped.
- Suggested fix: keep ruling 1 (no whole-file read). At `status: done`, refuse (exit 10, or 9 beside `receipt_all_done`) when the `## Phase plan` section holds a table line the parser did not read: any line matching `^[[:space:]]*\|` or `^[[:space:]]*[0-9A-Za-z*_]+ *\|`, less the first such line (header) and the `|---|` separator, counted against `cp_phases`. One function in `lib/checkpoint.sh`, one call. S1 and S2 need one more rule: a `|` line directly under a `## ` heading with no header and separator of its own is a table fragment, refuse it. Then turn `tests/41-ci-wait.sh:97,132` round: the `P1` row is refused, not skipped. Add to `templates/checkpoint.md:24` what happens to a row keyed otherwise.

### ARCH-2: `templates/brief.md` §9.4 tells the child to set `status: blocked`; §9.9 says only when nothing independent is left; and §9.4 is silent on `absent` where the head has no workflow file
- Severity: MEDIUM
- File: templates/brief.md:135-137 (new), :169-171, tests/51-templates.sh:87-88 (pins the new phrase)
- Reachable by a template-following job: yes
- Direction: fail-closed (the job stops, or the child guesses)
- Origin: introduced by this diff
- Failure path: (a) Phase 1's PR gets no run and its head has a workflow file. §9.4: "push once more for a run, and if none starts leave the row open, set `status: blocked`". §9.9: "Blocked parts do not stop the job ... continue the independent work. Set `status: blocked` only when nothing independent is left." Phases 2..N of a stacked job are independent work. The child must break one of the two; following §9.4 ends the job with exit 3 at the first PR a branch filter keeps CI off. (b) "push once more" names nothing to push: with the tree committed and pushed, `git push` is a no-op and no run can start, so this branch always ends in `blocked`. (c) A repo with no workflow file: `ci-wait` exits 10 on `absent`, the text says "`absent`, no runs, is not a pass", then gives an instruction only for "where the PR's head has a file under `.github/workflows/`". For the other case there is no sentence. An obedient child reaches criterion 2 only by reading the silence as "go on to `After ci-wait, set the row's Status`"; a careful one treats exit 10 plus "not a pass" as a stop.
- Evidence: file:line read. `SKILL.md:35-37` states the no-workflow rule to the scoping session, the brief does not state it to the child.
- Suggested fix: one sentence in §9.4: "where the head has no file there, close the row: the runner lets it through, logged"; and replace "set `status: blocked`" with "record it under Open or blocked (step 9)", so §9.9 alone decides the status. Say what to push (an empty commit) or drop "push once more".

### ARCH-3: a job with no Phase plan table cannot end `done` as it stands, yet the runner starts it and spends children on it without a word
- Severity: MEDIUM
- File: lib/chain.sh:94-109 and :160, lib/ci.sh:82, README.md:128, docs/spec.md:91
- Reachable by a template-following job: no (the template has a table); yes for a mis-typed heading (`## Phase Plan`), a header-only table, or rows keyed without a digit, where `cp_phases` is 0 (probe H)
- Direction: fail-closed
- Origin: introduced by this diff (the hard-cap job could end `done` in phase 2; `ci_check` now refuses it)
- Failure path: checkpoint with `## Phase Plan` (capital P). `chain_cap`: `cp_phases` 0, hard cap 12, logged `hard: no Phase plan table`. Up to 12 children run and are paid for. Unless one of them adds a readable table with a done row, the last sets `status: done` and gets exit 10, no done row. At `status: done` no child is launched (`chain.sh:160` exits before the launch), so only the owner can repair the checkpoint by hand. The runner could tell at second 0 that the checkpoint, as written, cannot end `done`; the start log says only `child cap 12 (hard: no Phase plan table in checkpoint.md)`.
- Evidence: file:line read; probe H; `unit-mutants.log` q4, q61.
- Suggested fix: the small one: at start, when `cp_phases` is 0, log "no Phase plan row the runner reads: this job cannot end done until the checkpoint has one" and print the same as a `preflight` line. The larger one, the owner's call: refuse to start such a job and retire exit 4. That is not one line: `tests/lib.sh` `new_job` writes no table, so every `done` scenario and test 10's exit 4 case would change with it.

### ARCH-4: the row grammar ruling 1 rests on is copied six times
- Severity: MEDIUM
- File: lib/checkpoint.sh:11, :43, :51, :57, :69 (as a `sed -i` address), lib/preflight.sh:77
- Reachable by a template-following job: n/a (maintainability)
- Direction: neither
- Origin: pre-existing (round 2's P3R2-21 fixed only the copy phase 3 had added)
- Failure path: the fix for ARCH-1, or any later change to which lines are rows, must be made in six places. Miss one and the gates disagree on which rows exist: the cap counts a row the CI gate does not read, or `cp_mark_usage` marks a row `cp_row_sha` cannot find.
- Evidence: `grep -n "Phase plan/,"` over `lib`.
- Suggested fix: one `cp_rows() { sed -n '...' "${1:-$JOB/checkpoint.md}"; }`; the five readers pipe from it.

### ARCH-5: sentences that are untrue or contradict another
- Severity: MEDIUM (as a set; each alone is LOW)
- File: see table
- Reachable by a template-following job: yes (they are what the owner and child read)
- Direction: neither, except row 1 (points at an edit that does not work) and row 6 (hides ARCH-1)
- Origin: per row
- Failure path / Evidence:

  | # | Where | Sentence | What the code does | Origin |
  |---|---|---|---|---|
  | 1 | README.md:128 | exit 4 remedy: "add a Phase plan table, or raise `JOB_MAX_CHILDREN`, and start again" | The same row now says such a job "cannot end `done` either, exit 10". Raising the cap alone ends in 4 again or in 10 | this diff (meaning cell changed, remedy left) |
  | 2 | README.md:128, lib/chain.sh:97-98 | "such a job cannot end `done` either" | It can once a child adds a table with a done row; `docs/spec.md:91` says "until it has a done row". The suite's own fake does exactly that (`fin`). The cap stays hard for that run (`chain_cap` runs once, chain.sh:134) | this diff |
  | 3 | README.md:128, docs/spec.md:91, bin/blast-off:18, lib/chain.sh:96 | the condition is "no Phase plan table" | The condition is `cp_phases` = 0: no line `^\| *[0-9]` in the section. A header-only table, `## Phase Plan`, or only `P1` rows are all "no table" (probe H: `cp_phases=0`) | pre-existing, now load-bearing for exit 10 |
  | 4 | README.md:117; docs/spec.md:97 in part | exit 10 "while the job has no done row at all" | A table whose rows are all open is exit 9: `receipt_all_done` runs first (chain.sh:160, receipt.sh:68-71), as spec row 9 says. Exit 10 needs no read row at all. The spec's parenthetical ("no table, or a heading or rows the runner does not read") limits it rightly; the README has no such limit | this diff |
  | 5 | docs/spec.md:97, end | "(owner question P4Q1, issue 26), while `ci-wait` itself exits 10 on absent: absent is never reported as green" | P4Q1 is the question ruling 2 settled; it is cited as if open. The "while" clause is the tail of the phase-2 sentence, left hanging on a new one. "Never reported as green" stands in the row that says `done` is let through on `absent` (exit 0, `job done`) | this diff |
  | 6 | docs/spec.md:35, README.md:116, bin/blast-off:37, templates/checkpoint.md:30-32, lib/ci.sh:57-58 and :60-61 | "every done Phase plan row names its PR or says `no PR`"; "refuses done (exit 10) for a closed row with neither"; ci.sh: "exit 10 unless every done Phase plan row's Status cell names ...", and refused is "a job with no done row at all (no table, a heading or rows the runner does not read)" | True only of rows the parser reads (ARCH-1). Rows it does not read are refused only when it reads none; beside one read row they are skipped. Only spec:97 defines the row; the template states the blind spot six lines earlier (:24) with no consequence | this diff |
  | 7 | docs/spec.md:97 | "its Status cell is the last cell" | Only when the row ends in `\|` and Status is the table's last column (ARCH-7; `unit-mutants.log` q6, q12) | this diff |
  | 8 | docs/spec.md:61, lib/checkpoint.sh:10 | rows "whose first cell is a number" | First cell starts with a digit (`2a` counts): spec:97 and templates/checkpoint.md:24 say so. Two wordings in one spec | pre-existing |
  | 9 | docs/spec.md:35 | "`lib/chain.sh` refuses `status: done`"; "`blast-off ci-wait <pr>`" | The refusal is `ci_check` in `lib/ci.sh`; the command is `ci-wait <job-dir> <pr>` | pre-existing, in a sentence this diff edited |
  | 10 | templates/checkpoint.md:33 | "refuses any other '#<n>' in a Status cell" | Only in a done row's cell; an open row's cell is not read | this diff |
  | 11 | tests/fakes/claude:32 | the receipt is "written here as `blast-off receipt` would" | `receipt_write` refuses a dirty tree and writes the eight fields of `templates/receipt.json`; `fin` writes four of them and does so with uncommitted paths present (22 `named`) | this diff |
  | 12 | tests/fakes/claude:17 | close-sha writes "`done (<sha>)`" | It writes `done (<sha>) · no PR` (:81) | this diff |

  The rest of the `lib/ci.sh` comments, checked line by line against the code, are true as written: `:2` (TOP by `chain_run`), `:4-12` (`ci_wait`; "every run" holds up to `--limit 100`, pre-existing), `:49-51` (`ci_runs`; `.github/workflows/ci.yml:13` has the `only` input), `:62-67` (nothing outside the cells is read; the absent rule; the unreadable commit; ruling 2), `:90` (`git -C ""`), `:107-109` (`ci_head`).

- Suggested fix: correct each in place; rows 1 to 5 first. Row 6 goes away with ARCH-1's fix.

### ARCH-6: sentences that are stale or leave a case out
- Severity: LOW
- File: see list
- Reachable by a template-following job: yes
- Direction: neither
- Origin: this diff unless marked
- Failure path / Evidence (file:line read):
  1. README.md:114-119 (prose) and bin/blast-off:37-38 leave out three refusals the code makes: a cell with both, a stray `#<n>` or `/pull/`, and `absent` with a head git cannot read or no git repo. README's own table row (:134) has the last. bin/blast-off:37-38 also leaves out "no done row".
  2. README.md:134 and bin/blast-off:37 call exit 10 "done refused" only. `blast-off ci-wait` itself exits 10 on red or absent (lib/ci.sh:46); spec:58 and :97 say so, README and the header do not (pre-existing).
  3. docs/spec.md:230, the `51-templates` row, is unchanged: it does not name the new pins (tests/51-templates.sh:31, :75-82, :87-88: the `no PR` obligation, the two forbidden sentences, the brief's `absent` text).
  4. docs/spec.md:228, the `41-ci-wait` row, does not say the scenario pins a non-digit row's PR as not read (41:97, :132) or the NUL case (41:206-209). "A run of any event but `workflow_dispatch` counts" is tested for `push` only (41:82-83).
  5. docs/spec.md:21 (K3): "phase row carries PR number"; now PR number or `no PR`.
  6. README.md:143-144, the big-next-job note, lists "digit row keys, `done (<sha>)` cells, receipts, `ci-wait`" as the rules the templates carry; the `PR #<n>` or `no PR` rule is not in the list.
  7. tests/fakes/claude:5-11: `done`, `slow-done`, `slow-hook`, `done-exit`, `bad-payload`, `trust-*` are described as "done"; each now also appends a table and, in git, a receipt (said only in the `fin` comment at :30-32).
  8. templates/brief.md:124-125: a duplicate PR is "named the way the checkpoint's rules comment says for a PR this job does not own". The comment no longer gives a way (it said "by its branch or as `other PR <n>`, no '#'"), only a place: "in prose, outside the table". The pointer is stale; "Open or blocked" already is that place.
  9. `SKILL.md:34-38` is true as written.
- Suggested fix: edit in place; none needs code.

### ARCH-7: "Status cell" is whatever cell is last; the header is never read
- Severity: LOW
- File: lib/checkpoint.sh:44 (`st = $(NF-1)`), :59
- Reachable by a template-following job: only by an off-template checkpoint: the owner or a child added a column after Status
- Direction: fail-open in the narrow case below; otherwise fail-closed (exit 9, "row is not done", with no word about the column)
- Origin: introduced by this diff for the CI gate (phase 2 read PR #7 from the line: exit 10); the positional read itself is pre-existing
- Failure path: header `| # | Phase | Done when | Status | Notes |`, row `| 0 | a | b | done (abc1234) · PR #7 | done (abc1234), no PR for the docs half |`. `cp_done_cells` gives `0|done (abc1234), no PR for the docs half`; `cp_row_sha 0` gives `abc1234` from the Notes cell, so the receipt gate is satisfied by a real receipt; `ci_check` reads `no PR`; PR #7 is never read. Outside git the Notes cell needs no sha.
- Evidence: stub probe case G (HEAD: job done; phase-2 lib: exit 10); `cp_row_sha 0` = `abc1234` for the second Notes text, empty for one with no sha (then exit 9 in git).
- Suggested fix: at done, refuse when the section's header row's last cell is not `Status` (one awk test in the function ARCH-1 adds).

### ARCH-8: `fin` in the fake masks no assertion; four residual couplings
- Severity: LOW
- File: tests/fakes/claude:30-43, :74, :76, :89, :96
- Reachable by a template-following job: n/a (test code)
- Direction: neither
- Origin: introduced by this diff
- Failure path / Evidence (scenarios read, none run):
  - 21 (`:27`): its job has a table, so `fin` returns after the status line; the fixture rows got ` · no PR`; no assertion changed. 32: uses `close`, never `fin`; expected strings gained ` · no PR`, the count of usage marks (3) is unchanged. 40: every `done`-mode job (`nosha`, `nogit`, `open`) has its own `plan`, so `fin` never writes a receipt there; the exit 9 cases still stop before `ci_check`.
  - The hard cap (10 `cap step`, exit 4) uses `step`, not `fin`: still tested. `chain_cap` runs before child 1, so a `fin` job still logs the hard cap and ends done: the suite now covers "no table at start, table at done", not "no table at done". That second path is covered only with a pre-set status (41 `nt`, `hd`, `nr`); same code path (`chain.sh:160`).
  - Re-runs after `fin` (23 `stale` second run, 11 `start_hang`, 31) meet a soft cap of 3 and a done row before child 1. Stub probe of that checkpoint (`done (abc1234) · no PR · usage unknown`): passes. No scenario asserts the cap line there.
  - 22 (git workdirs): `fin`'s files are in the job dir, which the dirty check skips; the row's sha is HEAD, so the D4-1 diff is empty.
  - Residual 1: the fake holds a second copy of the receipt's shape (four of the eight fields) and of the row format; a new field `receipt_check` requires breaks about 25 jobs at once (fail-closed, noisy).
  - Residual 2: `fin` reads the repo from `dirname "$JOB_DIR"`, the runner from `WORKDIR`. A scenario with a git workdir and a job dir outside it would get a row with no sha and exit 9. None exists today.
  - Residual 3: in 22 `named` the forged receipt exists beside an uncommitted path, a state `blast-off receipt` refuses (ARCH-5 row 11). The assertion there (a named path does not stop the chain) is unaffected.
  - Residual 4: stale mode comments (ARCH-5 row 12, ARCH-6 item 7).
- Suggested fix: none needed for correctness. Fix the comments; export the runner's workdir to the fake if residual 2 ever bites.

### ARCH-9: nothing says a job started before this change is refused at `done`, or who can make the edit
- Severity: LOW
- File: README.md:134, docs/spec.md:97, lib/ci.sh:78
- Reachable by a template-following job: yes, for a job written from the old template (rows closed `done (<sha>)` with the PR under Completed phases, or a `done (<sha>) · PR #<n>` row beside one with no PR)
- Direction: fail-closed
- Origin: introduced by this diff
- Failure path: `ci_check` runs only at `status: done`, so children keep working under the old brief, which never mentions `no PR`. The last child sets `done`: exit 10. Every re-run refuses before child 1 (chain.sh:157-160), so no child can fix the rows; the owner edits each by hand. The refusal says what to write and "then run again", not who, and not that the status may stay `done`. `baton-phase-3-fix-2.md:40` says this to the manager; no product text says it.
- Evidence: file:line read; `grep -n "migrat\|started before\|existing checkpoint"` over README, spec, skill, templates: no hit.
- Suggested fix: one sentence in README's exit 10 row: "A job started before <version> needs `PR #<n>` or `no PR` added to each done row by the owner; `no PR` only where the phase opened none."

### ARCH-10: two rows with one key: the receipt gate reads the first row, the CI gate reads each
- Severity: LOW
- File: lib/checkpoint.sh:37-38 (the comment admits it), :52, :60; lib/receipt.sh:50-51
- Reachable by a template-following job: only by an off-template checkpoint (a duplicated key)
- Direction: fail-open for the receipt gate (the second row's sha is never checked); the CI gate is right
- Origin: pre-existing; this diff fixed the CI side only (test `dup`, 41:192-194)
- Failure path: rows `| 1 | ... done (aaa1111) · PR #8 |` and `| 1 | ... done (bbb2222) · no PR |`. `receipt_check` loops over key `1` twice and `cp_row_sha 1` returns `aaa1111` both times; `bbb2222` needs no receipt.
- Evidence: file:line read (`exit` after the first match at checkpoint.sh:52 and :60).
- Suggested fix: refuse a duplicated key at done (it falls out of the ARCH-1 function: `sort | uniq -d` on the keys).

### ARCH-11: exit 10 now has three unrelated meanings, and the plan-shape refusal lives in the CI module
- Severity: LOW
- File: lib/ci.sh:72-82, lib/receipt.sh:68-71, README.md:134
- Reachable by a template-following job: yes (it is how the owner reads the code)
- Direction: neither
- Origin: introduced by this diff
- Failure path: exit 10 used to mean "a PR's CI is red or unread". It now also means "a row's text is malformed" and "the plan has no done row", and `ci-wait` returns it for its own red or absent verdict. The sibling plan-shape check, "status done but a row is not done", is exit 9 in `receipt_all_done`. An owner or a wrapper script that reads 10 as "wait for CI, then run again" loops on a typo. `ci_check` is now 33 lines doing two jobs: row policy (:70-84) and record policy (:85-99).
- Evidence: file:line read.
- Suggested fix: split `ci_check` into `ci_rows` and `ci_records` (no behaviour change). Whether the row refusals move to exit 9 is the owner's call; if they stay on 10, the README row is the place that must stay exact.

### ARCH-12: two rules the spec states have no test that pins them
- Severity: LOW
- File: docs/spec.md:97, tests/41-ci-wait.sh
- Reachable by a template-following job: yes
- Direction: neither today; fail-closed (m3) or fail-open (m8) if the code regresses
- Origin: introduced by this diff
- Failure path: spec:97 says `no PR` counts in "any case" and that a stray `/pull/` in a done cell is refused. Mutant m3 (`grep -qiE` to `grep -qE`) and mutant m8 (the stray pattern without `/pull/`) both survive scenario 41.
- Evidence: `review-phase-3-iter-3/unit-mutants.log`: `m3 ... SURVIVED`, `m8 ... SURVIVED`.
- Suggested fix: two fixture cells in the `sp` loop at 41:201: `No PR` (passes) and `PR #8 see /pull/x` with a stray link (refused).

### ARCH-13: the "cannot be read" refusal hands out a fetch line that assumes a remote named `origin` on GitHub
- Severity: LOW
- File: lib/ci.sh:93
- Reachable by a template-following job: yes, when the PR's head was not made in this clone (GitHub's "Update branch", a push from another clone)
- Direction: fail-closed
- Origin: introduced by this diff
- Failure path: the message says `git -C $TOP fetch origin pull/$pr/head`. `gh` picks the repo from the workdir's remotes and may use `upstream`; the line then fetches from a fork, or fails. `refs/pull/<n>/head` is a GitHub ref; the runner has no other host today, so this is a note, not a bug.
- Evidence: file:line read; GitHub's ref layout is from recall.
- Suggested fix: say "fetch the PR's head (on GitHub: `git fetch <remote> pull/<n>/head`)".

## Round-2 HIGH status

- P3R2-1: resolved as filed, reshaped at the row boundary. For rows the parser reads, every done cell is checked (lib/ci.sh:70-81; tests `np`, `mx`, `dup`, `both` at 41:170-198). For rows it does not read, a done row with a red PR still ends `job done` (ARCH-1, cases A to E, K, L, S1, S2), and the fallback that used to catch some of them is gone.
- P3R2-2: resolved. `ci_prs` is called only on done cells (lib/ci.sh:71, :83); test `lk` (41:186-190) and :132.
- P3R2-3: resolved in the code (lib/ci.sh:89-95 reads `head_sha^{commit}`; tests 41:227-256). The child's text for the same case is incomplete (ARCH-2).
- P3R2-4: resolved. templates/checkpoint.md:30-34 is an obligation; tests/51-templates.sh:75-82 pins it and forbids the old sentence. Residue: :24 still tells the reader which rows the runner does not see (ARCH-1, ARCH-5 row 6).

## Acceptance criteria

1. Met. tests/41-ci-wait.sh:236-237 (`PR #17 CI absent: no runs, but its head ... has a workflow file`, exit 10); mutant m1 killed.
2. Met in the runner: 41:227-229 and :233-234 (pass, logged). Met in part for an obedient child: the brief has no sentence for this case (ARCH-2).
3. Met in part. Prose is never read: 41:132, :160-162, :186-190. A done row with neither is refused: 41:170-171, but only a row the parser reads; 41:97 and :132 pin a done table row whose PR is skipped (ARCH-1).
4. Met. 41:76-80 (green dispatch alone is absent; red dispatch beside a green run is success; none watched), :82-83 (push counts), :222-226.
5. Met in part. Tests for 1 to 4 exist in 41, template text in 51 (:75-88). The texts do not all state the rules as they are (ARCH-2, ARCH-5, ARCH-6), and two stated rules have no pin (ARCH-12).

## New dependencies or reliance

No new program. New reliance, each from the diff:
- `gh run list --json databaseId,event`: the `event` field and the literal value `workflow_dispatch` (lib/ci.sh:53-54).
- `git ls-tree -r --name-only <sha>^{commit} -- .github/workflows` (lib/ci.sh:92): the `^{commit}` peel, and the PR's head commit being an object in the workdir's repo. That is a new operational need: a head made elsewhere must be fetched first.
- The refusal text's `git fetch origin pull/<n>/head`: a remote named `origin` and GitHub's pull refs (ARCH-13).
- `paste -sd' '` (coreutils; first use in `lib/`), `grep -a` (GNU or BSD grep; lib/ci.sh:104), `sed -E 's~...~~Ig'` (the `I` flag is GNU sed only; lib/ci.sh:72). The repo already needs GNU sed (`sed -i`, `0,/re/`).
- `ci_check` now reads `TOP`, which `chain_run` sets (lib/ci.sh:2, :91-92): `lib/ci.sh` depends on `lib/chain.sh` state for the first time.
- Tests: the fake `gh` gains `event-<id>`; the fake `claude` now needs `git` and `jq` and knows the receipt's field names and the row format (ARCH-8).
