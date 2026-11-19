# penetration-tester review: phase 3 round 2

Target: `git diff feat/br-1115-issues/phase-2...HEAD` (HEAD `ecc6e90`), the `done` gate in `lib/ci.sh`.
Counts: 0 CRITICAL, 3 HIGH, 7 MEDIUM, 4 LOW. Three of the MEDIUM and two of the LOW are pre-existing code
this diff did not write; they are listed because the brief asks for everything.

How the attacks were run. I ran no `tests/run`, no `scripts/gate.sh`, nothing with `install_units`. All
experiments ran from my own temp dir
`/tmp/claude-1000/-home-alex-blast-off--claude-worktrees-pending-items-53932d/60b15296-819e-491a-8ffe-34b3bd988f86/scratchpad/pen2.scGKTU`
(left in place: scripts `h.sh`, `b1.sh` to `b12.sh`, outputs under `new/`, the phase-2 comparison under `p2/`). The harness
`h.sh` sources the real `lib/ci.sh`, `lib/checkpoint.sh` and `lib/receipt.sh`, and for each case runs the
checks of `lib/chain.sh:137-159` in a `set -euo pipefail` subshell: `TOP` from the same `git rev-parse`
lines, `chain_dirty`, `receipt_check`, `cp_status`, `receipt_all_done`, `ci_check`, `chain_end 0`. Every
done row has a real PASS receipt in a throwaway git repo, so "exit 0" below means the dirty-tree check,
the receipt checks and `ci_check` all let `done` through, not `ci_check` alone. Not in the harness: the
lock, the tmux server, the cap, any child. The cases share a repo, so `jobs/` is in that repo's
`.git/info/exclude`; a real job has one job dir, which `chain_dirty` skips by prefix. `gh` is an executable first on `PATH` (a copy of
`tests/fakes/gh`, or a mode stub in `bin2/gh`); its calls and cwd are recorded per case. Throwaway repos
use `GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null`.

Tools: GNU grep 3.11, gawk 5.2.1 (`awk`) and mawk (six shapes re-run), GNU sed 4.9, jq 1.7, git 2.43.0,
bash 5.2.21. Byte cases ran under `LC_ALL=C` and `LC_ALL=C.UTF-8`; the two locales gave the same result
for every case.

## Findings

### PEN-1 | HIGH | lib/ci.sh:71-73 | One PR token in any Status cell turns the whole-file read off: a done row's PR named only under Completed phases passes `done` with no record, a red record or a stale record

- Failure path: two done rows. Row 0's Status cell is `done (<sha>) · PR #7`, row 1's is `done (<sha>)`,
  and `## Completed phases` says `PR #8; CI conclusion read` (the template's own wording, line 47).
  `prs` is `7`, so the fallback never runs and PR 8 is logged and skipped. `done` passes when PR 8 has
  no record, when `gate-logs/ci-pr-8.json` says `failure`, when it is `success` of an older head, and
  when it is `absent`. The phase-2 code refused the first three and passed the absent one. Following the
  fallback's own hint makes it worse: with
  no PR in any Status cell the same checkpoint is refused on the red PR 8 (`fb_red`, exit 10); do what
  the log line asks ("name this job's PR in its row's Status cell") for PR 7 alone and the red PR 8
  stops being read (`mixed_red`, exit 0).
- Evidence: RAN `b1.sh` on HEAD, and the same script on `git show feat/br-1115-issues/phase-2:lib/ci.sh`
  (`p2/`).

  | Case | Records | run.log at HEAD | HEAD | Phase 2 |
  |---|---|---|---|---|
  | `mixed_norec` | 7 success; 8 none | `CI read for the PRs Phase plan Status cells name: 7; named elsewhere in checkpoint.md and not read: 8` then `job done` | exit 0 | exit 10, `PR #8 CI unread` |
  | `mixed_red` | 7 success; 8 `failure` | same two lines | exit 0 | exit 10, `PR #8 CI red or unfinished` |
  | `mixed_stale` | 7 success; 8 success of head `111…`, PR head now `222…` | same two lines; gh called for 7 only | exit 0 | exit 10, `PR #8 CI unread for head 222…` |
  | `mixed_absent_wf` | 7 success; 8 absent | same two lines | exit 0 | exit 0, `PR #8: no CI runs (absent, not a pass)` |
  | `mixed_7unread` | 7 none; 8 success | `PR #7 CI unread …` | exit 10 | exit 10 |
  | `fb_red` (row 0 has no token; prose names 7 and 8) | 7 success; 8 `failure` | `no Phase plan Status cell names a PR; CI read for every PR … 7 8 …` then `PR #8 CI red or unfinished …` | exit 10 | exit 10 |

- New in this diff (the Status-cell-only read); the fix commit logs it and leaves it open (round-1
  P3R1-2, owner question 4).
- Suggested fix: in the Status-cell branch, also read each PR in `other` that has a
  `gate-logs/ci-pr-<n>.json` in this job. A record is there only because `ci-wait <n>` ran in this
  workdir, so the PR is this repo's. That closes the red, stale and absent rows above and keeps
  criterion 3 for a PR nobody ran `ci-wait` on. Two limits. The no-record row stays open; closing it
  needs the owner's call (for example: once any done row names a PR, refuse a done row whose cell names
  none). And a record can exist for an unrelated PR of this repo: PEN-3's refusal gets `ci-wait 99` run,
  which writes `ci-pr-99.json`; with this fix that PR would go on being read after the job's own PR is
  named, until the record is deleted or the prose reworded.

### PEN-2 | HIGH | lib/ci.sh:86-87 (same remedy at README.md:132) | The absent refusal's remedy cannot work for a stacked PR whose branch has no workflow file; the only exit that works is taking the PR out of its Status cell, which the gate then passes

- Failure path: the skill's default delivery is one stacked draft PR per phase
  (`skills/blast-off/SKILL.md:33-34`). Phase 0 is PR 7 (branch `a`, base `main`, no workflow file).
  Phase 1 adds `.github/workflows/ci.yml` and is PR 8 (branch `b`, base `a`). The workdir's HEAD is `b`.
  `ci-wait 7` records `absent`; `ci-wait 8` records `success`. At done the runner reads HEAD, finds the
  workflow file and refuses PR 7 with "push to the PR branch for a run that is not a workflow_dispatch".
  A push to branch `a` starts nothing: GitHub takes a `push` workflow from the pushed commit and a
  `pull_request` workflow from the PR's merge with its base, and neither holds the file. `ci-wait 7`
  records `absent` again and the refusal repeats without end. The same holds, by the same reasoning,
  where the workflow exists but filters the stacked PR out (`pull_request: branches: [main]` on a PR
  whose base is the phase branch below it), and for a dispatch-only workflow. What does get the job to
  exit 0 is deleting ` · PR #7` from row 0's Status cell: PR 7 becomes "named elsewhere" and is not read
  (PEN-1). So the refusal that was meant to hold the gate shut steers a stuck agent to the one edit that
  opens it.
- Evidence: RAN `b9.sh` for the runner's half (the fixture's workflow is a plain `on: pull_request`; its
  content plays no part locally, the fake gh decides which commit has runs); REASONED for GitHub's half
  (assumption stated above: which commit's workflow file GitHub uses for `push` and `pull_request` runs;
  not tested against GitHub).

  | Step | Output | Result |
  |---|---|---|
  | `ci-wait 7`, `ci-wait 8`, run | `CI read for the PRs Phase plan Status cells name: 7 8` then `PR #7 CI absent: no runs, but HEAD has a workflow file (.github/workflows/ci.yml); push to the PR branch for a run that is not a workflow_dispatch, …` | exit 10 |
  | new commit on branch `a` (no workflow there), `ci-wait 7`, run | `ci PR #7 at 156e571…: absent ()`, then the same refusal | exit 10 |
  | ` · PR #7` removed from row 0's Status cell | `CI read for the PRs Phase plan Status cells name: 8; named elsewhere in checkpoint.md and not read: 7` then `job done` | exit 0 |

- New in this diff (criteria 1 and 4 together); round-1 P3R1-3, P3R1-4 and P3R1-22 are open, and the
  fix commit's reworded message names a way out that does not exist for this case.
- Suggested fix: decide "runs were due" from the commit the record is of, not from HEAD:
  `git -C "$TOP" ls-tree -r --name-only "$head_sha" -- .github/workflows` with the record's `head_sha`
  (fall back to HEAD, and say so, when the object is not local). PR 7 then passes as absent with no
  workflow file at its own head, logged, and PR 8 is still held to its runs. Whatever is decided, the
  message must stop promising that a push starts a run when the PR's branch has no workflow file.

### PEN-3 | HIGH | lib/ci.sh:74-76, 90 | In the fallback, a link to another repo's PR is read as this repo's PR; the hint does not apply to a link and the refusal sends the agent to `ci-wait` the wrong PR

- Failure path: a job with no PR in any Status cell (no PR of its own, or its PR written only in prose)
  whose checkpoint says `waits on the upstream fix https://github.com/o/other/pull/99`. The fallback
  reads 99. The hint in the log says "write any other PR with no '#'": the link has no '#', so the hint
  gives nothing to change (`e_out_hint_nohash`, still exit 10). The last run.log line, the one
  `README.md:132` tells the reader to act on, says `blast-off ci-wait <job-dir> 99`. That calls
  `gh pr view 99` in the workdir with no `--repo`, so it reads this repo's PR 99:
  - no such PR here: `gh pr view 99 failed`, exit 1, and the refusal repeats without end;
  - an unrelated green PR 99 here: a `success` record, `done` passes, and run.log claims CI was read;
  - an unrelated red PR 99 here: `PR #99 CI red … fix and push if red`, an instruction to push to a PR
    that is not the job's;
  - an unrelated PR 99 with no runs and no workflow file at HEAD: `done` passes as absent.
  This is issue 26's "related edge case" back for every checkpoint with no PR in a Status cell, so
  criterion 3 ("a `PR #N` in prose is ignored") holds only when some Status cell names a PR
  (`e_status_dummy`: PR 7 in a Status cell, the link is logged as not read).
- Evidence: RAN `b8.sh`.

  | Case | run.log | Result |
  |---|---|---|
  | `e_norec` | `no Phase plan Status cell names a PR; CI read for every PR checkpoint.md names instead: 99 (name this job's PR in its row's Status cell; write any other PR with no '#')` then `PR #99 CI unread: … blast-off ci-wait <job-dir> 99, then run again` | exit 10 |
  | `ci-wait 99`, no PR 99 in this repo | gh call `pr view 99 --json headRefOid`, `cwd=<workdir>`; `gh pr view 99 failed` | exit 1, then exit 10 again |
  | `e_green` | `ci PR #99 at 222…: success`, then `job done` | exit 0 |
  | `e_red` | `PR #99 CI red or unfinished at 222… ; fix and push if red, …` | exit 10 |
  | `e_absent` | `PR #99: no CI runs and no workflow file at HEAD (absent, not a pass)`, `job done` | exit 0 |

  Ways out that do work (all exit 0 with `no PR named in checkpoint.md; CI not read`): `other PR 99 in
  o/other`, `o/other branch fix/thing`, `o/other#99`, `github.com/o/other pull 99`. Only the first two
  are in any text (`templates/checkpoint.md:32`), and neither text says a link counts.
- New in the fix commit (the fallback restores the phase-2 read for these checkpoints). It is the cost
  owner question 1 names, but the question understates it: it says the log line tells the agent what to
  do, and for a link it does not.
- Suggested fix: keep the fallback; fix the texts. In fallback mode end each per-PR refusal with "read
  because no Status cell names a PR; if PR N is not this job's, write it as `other PR N` or drop the
  link". Change the hint and `templates/checkpoint.md:32` from "no '#'" to "no '#' and no /pull/ link".

### PEN-4 | MEDIUM | lib/ci.sh:97 | One NUL byte makes `ci_prs` read nothing: `no PR named in checkpoint.md; CI not read`, exit 0, with a PR named in plain text

- Failure path: GNU grep treats stdin holding a NUL as binary and prints no match (`grep: (standard
  input): binary file matches` on stderr). `sed` and `awk` are not affected, so receipts and the
  all-done check still pass. With the PR only in prose and a NUL anywhere in the file, or with a NUL
  inside the Status row that names the PR, both `all` and `prs` are empty and `done` passes. With the
  NUL elsewhere and the PR in a Status cell, the PR is still read but `all` is empty, so "named
  elsewhere and not read" is silently dropped. The log line "no PR named in checkpoint.md" is false in
  each passing case. Invalid UTF-8 did not trigger this in either locale (grep -o prints only the
  match).
- Evidence: RAN `b2.sh` (both locales, same results), `b10.sh` (mawk), `b11.sh` (the fix).

  | Case (no CI record anywhere) | run.log | Result |
  |---|---|---|
  | `nul_elsewhere_prosePR`: row `done (<sha>)`, prose `shipped as PR #7`, a line `a\0b` | `no PR named in checkpoint.md; CI not read`, `job done` | exit 0 |
  | `nul_in_status_cell`: `… done (<sha>) · PR #7 \0\|` | same | exit 0 |
  | `nul_elsewhere_statusPR`: PR #7 in the Status cell, NUL in a later line | `CI read for … 7` (nothing about elsewhere), `PR #7 CI unread` | exit 10 |
  | `nul_first_line` | `PR #7 CI unread` | exit 10 |
  | invalid UTF-8 on the PR's line, in the Status cell, elsewhere | PR 7 read | exit 10 |

- Pre-existing mechanism (the phase-2 line on the same file also prints nothing; RAN). It is not one of
  P3R1-1's listed shapes, but it is the same outcome by another input: zero PRs read and `done` passes.
  New in the fix commit is only the log line, which states something untrue here.
- Suggested fix: `command grep -aoiE …` in `ci_prs`. RAN: with `-a` all three NUL cases above are
  refused, exit 10.

### PEN-5 | MEDIUM | lib/ci.sh:97 | PR tokens the regex misses in a Status cell still pass `done`; in the list forms the second PR appears nowhere in run.log

- Failure path: the Status cell is the only place the PR is named, written in a form the regex does not
  read. `prs` and `all` are both empty, so `done` passes with `no PR named in checkpoint.md; CI not
  read`. In the list forms the first number is read and the rest are not, and because `all` uses the same
  regex the unread number is not in "named elsewhere" either. Round-1 P3R1-9 was closed as "fixed by the
  log lines"; for these shapes the log line is either false or silent about the PR.
- Evidence: RAN `b3.sh`, each with no CI record and nothing else in the file.

  | Status cell after `done (<sha>) · ` | Read | Result |
  |---|---|---|
  | `PRs #7, #8` | none; `no PR named in checkpoint.md; CI not read` | exit 0 |
  | `PR #7, #8`, `PR #7/#8`, `PR #7 and #8` | 7 only | exit 10 on 7; with a success record for 7: exit 0, PR 8 never mentioned (`list_rec`) |
  | `PR 7`, `#7`, `PR  #7` (two spaces), `PR-7`, `PR: #7`, `PR # 7`, `PR number 7`, `draft PR (#7)` | none | exit 0 |
  | `pull request #7`, `Pull Request #7`, `**PR** #7`, `` `PR` #7 ``, `PR \#7`, `PR &#35;7` | none | exit 0 |
  | `…/repos/o/r/pulls/7`, `pull/7` (no leading slash), `o/r#7`, `GH-7`, `[PR 7][pr7]` | none | exit 0 |
  | `PR` + NBSP + `#7`, narrow NBSP, zero-width space, tab, `PR ＃7`, `PR #７` | none | exit 0 |
  | `PR #7`, `pr#7`, `PR #007`, `[#7](https://github.com/o/r/pull/7)`, `…/pull/7/files` | 7 | exit 10 |
  | `upstream https://github.com/o/other/pull/99` | 99, as this job's own | exit 10 |
  | `PR #0`, `PR #-7` | none | exit 0 |
  | `PR #99999999999999999999999` | that number | exit 10 (unread) |

- Pre-existing regex, made worse by this diff: before it a second mention anywhere in the file caught
  most of these; now a second mention is read only when no Status cell names any PR.
- Suggested fix: fail closed on a cell the runner cannot fully read rather than widening the regex.
  Where a done row's Status cell holds more `#<digits>` tokens than `ci_prs` reads from it, or holds
  `PR` or `pull` and `ci_prs` reads nothing, refuse with exit 10 and "write `PR #N` for each of this
  job's PRs in row k".

### PEN-6 | MEDIUM | lib/ci.sh:86-88 | The workflow read is of the workdir's HEAD only: absent passes when the PR's own branch has a workflow file that HEAD lacks

- Failure path: absent record for PR 7, and the workflow file is on the PR's branch but not at the
  workdir's HEAD (a linked worktree or side branch checked out, a HEAD that deleted the workflow, a
  workflow only on the default branch while HEAD is an old PR branch), or it is uncommitted and the
  checkpoint names its path. Runs were due and did not come; `done` passes as "no workflow file at
  HEAD".
- Evidence: RAN `b5.sh` and `b12.sh`, each with an absent record of the PR's current head.

  | Repo state | run.log | Result |
  |---|---|---|
  | workflow only on branch `pr`, HEAD on `main` (`pr_branch_only`); the same from a linked worktree (`wt`) | `PR #7: no CI runs and no workflow file at HEAD (absent, not a pass)` | exit 0 |
  | workflow only on `main`, HEAD on `pr` (`default_only`) | same | exit 0 |
  | workflow committed then removed at HEAD (`deleted_at_head`); detached at the commit before it (`detached`) | same | exit 0 |
  | workflow untracked (`untracked`) or staged, not committed (`staged_only`); checkpoint does not name the path | `dirty tree before child 1: checkpoint.md does not name .github/workflows/ci.yml` | exit 7 |
  | the same two, checkpoint names `.github/workflows/ci.yml` | `tree before child 1: uncommitted, named in checkpoint.md: …` then no workflow file at HEAD, `job done` | exit 0 |
  | workflow at HEAD, deleted on disk (`deleted_on_disk`) | exit 7 unnamed; named: `PR #7 CI absent: … HEAD has a workflow file` | exit 10 |
  | workflow at HEAD, workdir a subdirectory (`subdir_workdir`) | `PR #7 CI absent: … HEAD has a workflow file` | exit 10 |
  | `.github/workflows` an empty directory (`emptydir`); `sub/.github/workflows/ci.yml` (`nested_wf_in_subdir`); `.github/Workflows/ci.yml` (`case_dir`) | no workflow file at HEAD | exit 0 |
  | repo with no commit, files staged (`nocommit`) | dirty tree | exit 7 |
  | repo with no commit and no files, no table, PR in prose (`unborn`) | fallback line, then `git ls-tree HEAD failed in …` | exit 1 |
  | bare repo, or a workdir inside `.git` | `git rev-parse in … failed: fatal: this operation must be run in a work tree` | exit 1 |

- New in this diff; round-1 P3R1-3 open (owner question 2).
- Suggested fix: the one in PEN-2 (read the record's `head_sha`). It closes `pr_branch_only`, `wt`,
  `deleted_at_head` and `detached`. It does not close `default_only` (by the assumption in PEN-2 a
  `pull_request` workflow comes from the merge with the base, so the base's tree would have to be read
  too) or the uncommitted-and-named rows.

### PEN-7 | MEDIUM | lib/ci.sh:86-87 | Any path under `.github/workflows` counts as a workflow file, so absent is refused for good on files that never start a run

- Failure path: absent record, and HEAD holds `.github/workflows/.gitkeep`, `README.md`,
  `ci.yml.disabled`, `sub/ci.yml`, a dispatch-only `manual.yml`, a symlink, a gitlink, or a plain file
  named `.github/workflows`. Each refuses `done` and the message calls it "a workflow file"
  (`HEAD has a workflow file (.github/workflows/README.md)`). No push can start a run. Fail-closed, but
  with PEN-2's exit: the Status-cell edit.
- Evidence: RAN `b5.sh` cases `gitkeep`, `notyaml`, `disabled_ext`, `nested`, `dispatch_only`,
  `symlink_dir`, `symlink_file`, `file_named_workflows`: all exit 10 with that message. `gitlink`: exit
  10 from `ci_check` in the first harness; with the dirty-tree check it ends exit 7 first, because my
  fixture has no submodule checkout.
- New in this diff; round-1 P3R1-4 open (owner question 3).
- Suggested fix: count only `*.yml` and `*.yaml` directly under the directory
  (`git ls-tree --name-only <rev> .github/workflows/ | grep -E '\.ya?ml$'`). A dispatch-only or
  branch-filtered workflow still needs the owner's answer to question 3.

### PEN-8 | MEDIUM | lib/ci.sh:81, 105-107 | The gate trusts whatever sits in `gate-logs/ci-pr-<n>.json`; the gated child can write it

- Failure path: the child writes the record by hand instead of running `ci-wait`. `ci_head` only checks
  that `head_sha` equals the PR's head now, which the child can read with `gh pr view`.
- Evidence: RAN `b7.sh`, `b6.sh`; PR 7 in the Status cell, gh says the head is `111…`.

  | Record | Result |
  |---|---|
  | `{"pr":7,"verdict":"success","head_sha":"111…"}`, no `runs` | exit 0 |
  | `{"pr":7,"verdict":"absent","head_sha":"111…"}` in a repo with no workflow file | exit 0 |
  | `verdict` `"success\n"` (the trailing newline is stripped by `$(…)`) | exit 0 |
  | duplicate key `"verdict":"failure","verdict":"success"` | exit 0 |
  | `verdict` success with `runs` holding a `failure` | exit 0 |
  | `"pr":7.0` | exit 0 |
  | a symlink to another job's green record for PR 7 | exit 0 |
  | `head_sha` `"null"` while gh returns `{"headRefOid":null}`; `head_sha` `"abc"` while gh returns `abc` | exit 0 |
  | `" success"`, `"success "`, `"SUCCESS"`, `["success"]`, `"*"`, `"pr":"7"`, `pr` missing, `"pr":8`, a JSON array, an empty file | exit 10 (unread) |
  | two documents, `failure` then `success`; other PR then `success` | exit 10 (unread) |
  | two documents, `success` then another PR's | exit 10 (head reads as two lines) |
  | `success` document then `not json` | the runner aborts on jq's status (exit 1 after `chain_exit`), no state |
  | `PR #9007199254740993` with a record whose `pr` is `9007199254740992` (jq 1.7) | exit 10 |

- Pre-existing (phase 2); not made worse here. Listed once for all forged shapes.
- Suggested fix: an owner decision. The runner already calls gh at done; one `ci_runs "$head"` there,
  compared with the record's run ids, would make the record a cache of what the runner can check.

### PEN-9 | MEDIUM | lib/checkpoint.sh:11, 40-45; lib/ci.sh:70 | A table the runner cannot read turns the receipt and all-done checks off; a second `## Phase plan` heading straight after the first hides its rows

- Failure path: (1) indented rows, `### Phase plan`, `## Phase Plan`, `##  Phase plan`, a BOM before the
  heading, CR-only line ends, a key `P0`, or rows with no leading `|`: `cp_phases` is 0 and
  `cp_done_rows`/`cp_open_rows` are empty, so no receipt is checked and no open row is seen. CI now falls
  back to the whole file, so `done` is refused only if a readable PR token exists somewhere; with an
  unreadable one it passes with nothing checked at all (`indented_nopr_elsewhere`: Status `PR 7`, exit 0,
  `no PR named in checkpoint.md; CI not read`). (2) `## Phase plan`, rows, `## Phase plan`, rows: sed's
  range ends on the second heading and does not start again on it, so a `pending` row in the second
  table is not seen (`two_adjacent`: `phases=1`, `open_rows=[]`, the all-done check passes with a
  pending row; it was refused only because the fallback read PR 7).
- Evidence: RAN `b4.sh`. Every table shape with a canonical `PR #7` somewhere ended exit 10 or exit 9:
  no trailing `|` (9, row reads as open), `\|` in the Status cell (9), an extra column after Status
  (9; fallback and 10 when that column starts `done`), indented, `### Phase plan`, `## Phase Plan`,
  two sections, a row inside an HTML comment (read as a row, 10), a PR only in an HTML comment or a code
  fence (fallback, 10), `## Phase plan (revised)` (read as the heading, 10), a heading inside a code
  fence (read as the heading, 10). The shipped template with its rows closed and no PR written passes
  with `no PR named in checkpoint.md; CI not read` (`tpl_asis`): its own comment text holds no token.
- Pre-existing (receipt code is outside this diff); the CI half is what the fix commit closed.
- Suggested fix: at `status: done`, refuse when `cp_phases` is 0 and the file holds a line matching
  `^[[:space:]]*\|[[:space:]]*[0-9A-Za-z]` or a heading matching `phase plan` in any case.

### PEN-10 | MEDIUM | lib/ci.sh:41 | A PR whose only runs were skipped is recorded `success`; the default delivery is draft PRs

- Failure path: a workflow whose jobs carry `if: github.event.pull_request.draft == false` (common) on a
  draft PR ends with conclusion `skipped`. `ci-wait` records verdict `success` and `done` passes with
  no check having run.
- Evidence: RAN `b6.sh`: conclusion `skipped` gives `ci-wait rc=0 verdict=success`; so does `neutral`.
  `cancelled`, `failure`, `timed_out`, `action_required`, `stale`, `startup_failure` and `null` give
  `failure`. REASONED: that GitHub reports such a run as `skipped`.
- Pre-existing (phase 2, documented in `docs/spec.md:58`).
- Suggested fix: `success` needs at least one run whose conclusion is `success`; all skipped or neutral
  is `absent`. This helps only if GitHub reports such a run as `skipped`; if it reports `success`, neither
  the code nor this fix can tell it from a real pass.

### PEN-11 | LOW | lib/ci.sh:86-88 | With the workdir outside git the absent pass is logged as "no workflow file at HEAD" though nothing was read

- Failure path: `TOP` is empty (gh still works there with `GH_REPO` set). The workflow read is skipped
  and the log says `PR #7: no CI runs and no workflow file at HEAD (absent, not a pass)` while
  `.github/workflows/ci.yml` sits on disk.
- Evidence: RAN `b5.sh` case `nogit`: that line, then `job done`, exit 0.
- New in this diff.
- Suggested fix: log "workdir is not in a git repo; workflow files not checked" in that branch.

### PEN-12 | LOW | lib/ci.sh:97 | The regex reads PRs out of ordinary words and paths, which the fallback now turns into refusals

- Failure path: no PR in a Status cell and prose such as `fixed the awk expr #2 bug`, `see docs/pull/3`,
  `PR#12 of the old repo`. The fallback reads 2, 3, 12 and refuses with `blast-off ci-wait <job-dir> 2`.
  In a Status cell `expr #2 is fine` is read as this job's PR 2.
- Evidence: RAN `b8.sh` (`e_expr`, `e_gitpull`, `e_issue`: exit 10) and `b3.sh` (`expr`: PR 2).
  `merge_requests/5` and `/pull-requests/6` are not read.
- Pre-existing regex; reachable in prose again through the fix commit's fallback.
- Suggested fix: `(^|[^[:alnum:]])PR ?#[0-9]+`.

### PEN-13 | LOW | lib/ci.sh:106 | `BLAST_OFF_CI_HEAD=0` switches the head read's timeout off

- Failure path: `timeout 0` means no limit, so a stalled `gh pr view` holds the lock, the case P4R2-2
  bounded. A non-number (`soon`) makes `timeout` fail and reads as unread (exit 10).
- Evidence: RAN `b6.sh` `head_t0` (gh sleeps 5 s, then `job done`), `head_tbad` (exit 10).
- Pre-existing.
- Suggested fix: document it, or treat 0 as the default.

### PEN-14 | LOW | lib/checkpoint.sh:5 | A BOM or UTF-16 at the top hides `status:`; the runner keeps launching children

- Failure path: `cp_status` reads nothing, so `done` is never reached and children are launched until
  the stall or cap exit. Not a fail-open.
- Evidence: RAN `b2.sh` `bom_file_start`, `utf16`: `status=[]`, the harness reports "the chain would
  launch a child".
- Pre-existing.
- Suggested fix: none needed for the gate; a log line when `cp_status` is empty would save children.

**Other shapes tried, nothing to report**

- CRLF line ends: the PR is read and refused (exit 10) under both awks.
- `ci_head`, success record of the current head (RAN `b6.sh`): gh printing nothing, `null`,
  `{"headRefOid":null}`, non-JSON, HTML, a 3-character head, valid JSON with exit 1, exit 1 with nothing,
  or hanging past `BLAST_OFF_CI_HEAD=1` all end exit 10. Two JSON documents end exit 10 and put a newline
  into the run.log line.
- `ci_wait` (RAN `b6.sh`): `gh run list` printing `null`, non-JSON, an object, or failing with or without
  JSON all die with `gh run list failed`, exit 1, no record. `[]` or nothing gives `absent`, exit 10. A
  dispatch-only list gives `absent`. A run with no `event` field is counted. `gh pr view` giving an
  empty, `null`, short or non-JSON head, or failing, dies with no record.
- No path from `status: done` to exit 0 skips `ci_check`: `grep -n 'chain_end 0\|exit 0' lib/*.sh
  bin/blast-off` (RAN) finds one exit, `lib/chain.sh:159`, after `receipt_all_done; ci_check`.
- Re-running every batch with `chain_dirty` added changed no outcome except the uncommitted-workflow rows
  in PEN-6 and the `gitlink` row in PEN-7.
- `shellcheck -S warning lib/ci.sh` and `bash -n lib/ci.sh`: clean.

## Round-1 findings checked

| ID | resolved / reshaped / open / not checked | why |
|---|---|---|
| P3R1-1 | resolved for its listed shapes | No table, `## Phase Plan`, `### Phase plan`, indented rows, key `P0`, PR column not last, done row with no token: all end exit 10 when a readable token is anywhere in the file (RAN `b4.sh`). Residual, by inputs P3R1-1 did not list and code older than this diff: zero PRs read and `done` passing through a NUL (PEN-4) or a token the regex misses (PEN-5); now logged, with a log line that is untrue there. |
| P3R1-2 | reshaped | Logged, not read. `done` passes with a red or stale record for the PR (PEN-1). |
| P3R1-3 | open | PEN-2 (refused for good) and PEN-6 (passes). |
| P3R1-4 | open | PEN-7. The reworded message's way out does not work (PEN-2). |
| P3R1-5 | resolved, one gap | `templates/checkpoint.md:29-32` matches the code (read; `tpl_asis` RAN). Gap: "no '#'" does not say a `/pull/` link also counts (PEN-3). |
| P3R1-6 | not checked | Read `skills/blast-off/SKILL.md:33-37` only: both cases are stated. |
| P3R1-7 | reshaped | `README.md:132` now gives a remedy for absent ("push to the PR branch so a run starts") that cannot work in PEN-2's case. |
| P3R1-8 | not checked | |
| P3R1-9 | open | PEN-5: the shapes still pass; for the list forms nothing about the second PR is logged. |
| P3R1-10 | not checked | No `tests/run` allowed for this role. |
| P3R1-11 | resolved (behaviour) | RAN `subdir_workdir`: refused from a subdirectory. Test not run. |
| P3R1-12 | resolved (behaviour) | RAN `unborn`: a repo with no commit ends `git ls-tree HEAD failed`, exit 1. Test not run. |
| P3R1-13 | resolved (behaviour) | RAN `deleted_on_disk`: refused; `untracked` passes, which is P3R1-3. |
| P3R1-14 to P3R1-20 | not checked | Test findings. |
| P3R1-22 | reshaped | The message no longer says "re-run it"; what it says now is wrong for a branch with no workflow file (PEN-2). |
| P3R1-21, 23, 24 and the other LOWs | not checked | |

## Owner questions (1-4): is the default the safe one?

1. **Fallback reads every PR named (P3R1-1).** Yes for the gate, with two holes that are not the
   owner's choice to make: PEN-4 (NUL) and PEN-5 (unreadable tokens). The stated cost is larger than
   the baton says: for a link the log hint does not apply, and the refusal points `ci-wait` at this
   repo's PR of the same number (PEN-3). Alternative (a) would reopen the done-row-with-no-token case.
   Keep the default; fix the texts.
2. **HEAD decides "runs were due" (P3R1-3).** No. It fails open when HEAD lacks a workflow the PR's
   branch has (PEN-6) and it refuses for good an earlier stacked PR once a later phase adds a workflow
   (PEN-2). The stated remedy cannot work there: a push to a branch with no workflow file starts no
   run (REASONED), and `ci-wait` records absent again (RAN). The record's `head_sha` is the safer
   commit to read.
3. **Any file counts, no override (P3R1-4).** Safe for the gate on paper, not in practice. The remedy
   cannot work for a non-workflow file, a dispatch-only workflow or a branch filter (PEN-7), and the
   exit left to a stuck agent is to take the PR out of its Status cell, which passes (RAN, PEN-2's third
   row). A logged owner override is safer than that edit. Narrowing to `*.yml`/`*.yaml` is safe.
4. **A PR named only under Completed phases is logged, not read (P3R1-2).** No. `done` passes with a
   red record for that PR in the job's own `gate-logs` (RAN, PEN-1); phase 2 refused it (RAN). Reading
   the "elsewhere" PRs that have a record in this job brings issue 26's bug back only for a PR someone
   already ran `ci-wait` on here (PEN-1's second limit); a PR with no record stays unread.

## What I did not check

- `tests/run` in any form, `scripts/gate.sh`, and so every round-1 test finding (P3R1-10, 14 to 20).
- GitHub's real behaviour: which commit's workflow file a `push` or `pull_request` run uses, and that an
  all-skipped run has conclusion `skipped`. Both are REASONED and marked so.
- The real `gh`: every gh output came from a stub.
- `docs/spec.md`, `README.md`, `bin/blast-off` and `SKILL.md` beyond the lines cited.
- The locale and `PATH` a systemd user unit gives the runner; mawk beyond six shapes; awks other than
  gawk and mawk; grep older than 3.5 (where the binary-file line went to stdout).
- `--limit 100` (P3R1-24), `preflight`, the round-1 LOW findings.
- One harness case was invalid and is not used: `head_nogh` (my `PATH` lost coreutils). A missing `gh`
  ends in `|| cur=` and exit 10 (REASONED from `lib/ci.sh:106-108`).
- A gitlink at `.github/workflows` with its submodule checked out (my fixture ends at the dirty-tree
  check).
