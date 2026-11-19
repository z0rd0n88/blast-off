# silent-failure-hunter review: phase 3 round 2

Reviewed at `ecc6e90` (no tracked file modified). Diff: `git diff feat/br-1115-issues/phase-2...HEAD` for the nine named paths.

Summary: the fix closes the round-1 HIGH only for a checkpoint where **no** Status cell names a PR. Where one row names its PR and another does not, `done` still exits 0 with that PR unread, now with a log line, even with a red `ci-pr-N.json` for it on disk (SFH-1). The fallback fails closed but brings issue 26's own bug back for those jobs, with a hint that does not work for a link (SFH-2). 2 HIGH, 5 MEDIUM, 6 LOW. Of 27 mutants run on the scenario, 23 were killed; 4 survived (one is a proposed fix, not a defect).

How things were run. Copy of the tracked files: `git archive HEAD | tar -x` into `/tmp/sfh2.aWjOTf`. Scripts and outputs: `/tmp/sfh2w.BuzXns` (`mut.py` holds every mutant's exact text, `batch.sh`, `run1.sh`, `out-<mutant>.txt`, `probe.sh` copied from the brief, my `probe2.sh`, `cw.sh`). Only `BLAST_OFF_TEST_ONLY=41-ci-wait tests/run`, in that copy, one at a time, foreground; `tests/41-ci-wait.sh` has 0 `install_units` calls (grep). Baseline on the unmutated copy: `PASS 41-ci-wait`, `GATE-ONLY: PASS passed=1 failed=0 shellcheck=ok only=41-ci-wait`, 23 s. The first attempt started nothing: the guard matched my own shell line (the same trap the fix baton hit). Probes source `lib/ci.sh` with `log`, `chain_end`, `die`, `ci_head` stubbed, run with `bash` (GNU grep 3.11, not the tool shell's ugrep). No real `gh` call was made except the read-only `gh issue view 26`.

Two things outside the letter of the allow-list, both in my own temp dirs, both harmless, named here so nobody has to find them:

1. `cw.sh` ran the copy's real `bin/blast-off ci-wait` three times against the fake `gh` (the script stops unless `command -v gh` is `tests/fakes/gh`). That is neither the filtered scenario nor a stub-sourced scratch script. `ci-wait` starts no runner, no tmux and no unit; it wrote only under `/tmp/sfh2w.BuzXns/cw`. Findings SFH-8 and SFH-12 and one row of the focus-1 table rest on it.
2. One of the 29 scenario runs (the soft run of m1) used a `fail()` patched in the copy's `tests/lib.sh` to report and go on; the file was restored after it (the copy's `lib/ci.sh` and `tests/lib.sh` compare equal to the archive's).

`ExecStart` in `~/.config/systemd/user/blast-off@.service` read the same before the first run and after the last: `ExecStart=/home/alex/blast-off/.worktrees/blast-off-build/bin/blast-off run %f`.

## Findings

### SFH-1 | HIGH | lib/ci.sh:71-73 | A done row with no PR in its Status cell is not gated once any other row names one; a red record on disk for its PR is ignored and `done` exits 0

- Failure path: two done rows, row 0 `done (abc1234) · PR #7`, row 1 `done (def5678)` with its PR only under `## Completed phases` (`- **Phase 1, b** (done). PR #8; CI read.`, the shape `templates/checkpoint.md:47-49` prompts). `gate-logs/ci-pr-7.json` green, `gate-logs/ci-pr-8.json` verdict `failure`. `prs` is `7`, so the fallback at `:74` never runs; PR 8 goes into `other`, gets one log clause, and `chain_end 0 "job done"` follows. The same holds with no record for PR 8 at all, and for a row keyed `P1` (the `fin` fixture pins that PR #96 there must not hold `done` back).
- Evidence: RAN `probe2.sh` case `tworows` (and the brief's `mixed`): `LOG: CI read for the PRs Phase plan Status cells name: 7; named elsewhere in checkpoint.md and not read: 8` / `(head ok for 7)` / `=> DONE PASSES`. REASONED for the runner end to end from `lib/chain.sh:159` (no other check between `ci_check` and `chain_end 0`).
- Why HIGH (rubric: "a round-1 HIGH reshaped instead of resolved", "a fail-open a realistic input reaches"): round 1's H1 named three shapes; "a done row with no PR token" is fixed only when no row at all names a PR. A multi-phase job, the normal one, has other rows that do. The template now says so in plain words to the child being gated (`templates/checkpoint.md:30`: "A row closed without one gets no CI check"), and SFH-5's dead end gives it a reason to use it. The log line is written at exit 0, where nobody is made to read it.
- New in the fix commit (the log); the pass itself is new in this diff (b9c39ad).
- Suggested fix: only one option closes this: refuse a done row whose Status cell names no PR while another row's does (baton alternative b, owner's call). A smaller change closes part of it: a PR in `other` that has a `gate-logs/ci-pr-<N>.json` in this job is this job's (someone ran `ci-wait` for it here), so read it like a Status-cell PR: `for pr in $other; do [ ! -e "$JOB/gate-logs/ci-pr-$pr.json" ] || prs+=" $pr"; done` before the loop. RAN as `m23`: the scenario still passes (no test forbids it), and `probe2.sh` case `tworows` against it ends `END 10: PR #8 CI red or unfinished`. It is partial: RAN `probe3.sh` with PR 8's record deleted, still `=> DONE PASSES`. A row closed without its PR and never `ci-wait`ed, the round-1 HIGH's own shape, stays open under it, and deleting the record file becomes the way out. Do not count the HIGH resolved by the small change alone.

### SFH-2 | HIGH | lib/ci.sh:74-76,90 | The fallback brings back issue 26's bug for a job with no Status-cell PR: another repo's `/pull/N` link is read, the hint does not apply to a link, and the refusal tells the agent to `ci-wait` that number in the wrong repo

- Failure path: a checkpoint with no PR in any Status cell (no table, a job with no PR, a row the parser does not read) whose prose holds `https://github.com/o/other/pull/99`. `all` is `99`, the fallback reads it, there is no record, exit 10. The log hint says `write any other PR with no '#'`; a link has no `#`. Rewriting as the hint and the template say (`other PR 99`) while keeping the link is still refused. The refusal says `blast-off ci-wait <job-dir> 99`, which runs `gh pr view 99` in the workdir: this repo's PR 99. Either that PR does not exist (`die`, stuck) or an unrelated PR's CI is recorded and then decides `done`.
- Evidence: RAN `probe.sh` case `xrepo_link_nopr` and `probe2.sh` case `xrepo_and_fix`: `LOG: no Phase plan Status cell names a PR; CI read for every PR checkpoint.md names instead: 99 (name this job's PR in its row's Status cell; write any other PR with no '#')` / `END 10: PR #99 CI unread: ... blast-off ci-wait <job-dir> 99, then run again`. REASONED that `ci-wait 99` reads the workdir repo (`lib/ci.sh:17-18`).
- Why HIGH (rubric: "an acceptance criterion not met", "instruction text that tells an agent to do the wrong thing"): criterion 3 and the issue's third checkbox ("another repo's PR mentioned in prose is ignored") do not hold for these jobs; `tests/41-ci-wait.sh:141-152` pin prose being read. The gate itself fails closed here; this is a false refusal with a wrong remedy, not a fail-open. It is owner question 1.
- New in the fix commit.
- Suggested fix: make the hint true and complete: `...; a PR of another repo: no '#', and no /pull/<n> link`. Say in the unread refusal, when the PR came from the fallback, that it was read from prose. Or take the owner's alternative (a): fall back only when `cp_phases` is 0, which `m13` shows the suite currently forbids (`np` case), so that needs the owner's word.

### SFH-3 | MEDIUM | lib/ci.sh:78,97 | A Status cell that names PRs in a spelling the regex misses passes with the false line "no PR named in checkpoint.md; CI not read"; `PR #7, #8` reads 7 and drops 8 with no line at all

- Failure path: Status cell `done (abc1234) · PRs #7, #8`, or `PR 7`, `#7`, `PR  #7`, `PR: #7`, `PR **#7**`, `o/r#7`, `.../pulls/7`, `pull request #7`: both reads use the same `ci_prs`, so the fallback sees nothing either and `done` exits 0. With `PR #7, #8` (or `PR #7 & #8`) and a red record for PR 8, 8 is neither read nor listed as "named elsewhere".
- Evidence: RAN `probe.sh` cases `plural`, `nohash`, `barehash`, `twospace`, `pullreq` and `probe2.sh` cases `bold`, `colon`, `ghshort`, `pulls`: each `LOG: no PR named in checkpoint.md; CI not read` / `=> DONE PASSES`. `list8`, `amp`: `LOG: CI read for the PRs Phase plan Status cells name: 7` / `=> DONE PASSES` with `ci-pr-8.json` red.
- New in the fix commit (the false log line); the regex is pre-existing; P3R1-9 reshaped.
- Suggested fix: say what was looked for: `no 'PR #<n>' or /pull/<n> token in checkpoint.md; CI not read`. And refuse, or at least log, when a done row's Status cell holds `#<digits>` more times than PRs were read from it.

### SFH-4 | MEDIUM | lib/ci.sh:97 | One NUL byte makes grep print nothing; `|| true` and the pipeline hide it and `done` passes with "no PR named"

- Failure path: a NUL anywhere in `checkpoint.md` empties the whole-file read (`all`); a NUL in a Status row empties the Status read too. GNU grep writes `grep: (standard input): binary file matches` to stderr and exits 0, so neither `set -e` nor `pipefail` sees anything. Result: `no PR named in checkpoint.md; CI not read`, exit 0. With a Status-cell PR and the NUL elsewhere the gate still works, but the "named elsewhere and not read" list is silently empty.
- Evidence: RAN `probe2.sh` under `LC_ALL=C` and `C.UTF-8`: `nul_prose`, `nul_prose_after`, `nul_row` all `=> DONE PASSES`. Invalid UTF-8 (`\xff`, a Latin-1 `\xb7` in the row) does not trigger it with `-o` on grep 3.11 (`utf8_sameline_prose`, `latin1_dot_row` refuse correctly).
- Pre-existing made worse: phase 2 swallowed it the same way; the fix adds a log line that states the opposite of the file. P3R1-28 disposition "`grep -a` not added" stands.
- Suggested fix: `grep -a` in `ci_prs`.

### SFH-5 | MEDIUM | lib/ci.sh:87 | The absent refusal's remedy cannot work for an earlier stacked PR whose branch holds no workflow file; there is no other way out but SFH-1

- Failure path: a job adds its first workflow in phase k. At `done` HEAD has it, so PRs 1 to k-1 (absent records, correct head) are refused with "push to the PR branch for a run that is not a workflow_dispatch". A `pull_request` run uses the workflow file of the PR's own merge ref; neither that PR's head nor its base (the previous phase's branch, `templates/brief.md:108`) has one, so a push starts nothing and `ci-wait` records absent again. README says "there is no override". The exits left are hand-editing the record or deleting the PR token from that row's Status cell, which then passes (SFH-1).
- Evidence: REASONED; GitHub's side cannot be run here. Local facts: `.github/workflows/ci.yml` triggers are `pull_request` and `workflow_dispatch`, no `push`, no branch filter; `git log --diff-filter=A -- .github/workflows` gives one commit, `376fa07` (2026-11-06), and issue 26's own incident is "PRs 1-8 merged with no CI". Round 1's critical-thinking item 5 measured that the heads of PRs 1 to 8 hold no workflow file; I did not re-measure it.
- New in this diff (the refusal); message reworded in the fix commit. Owner questions 2 and 3.
- Suggested fix: the message should say the PR's branch must hold the workflow file for a push to start a run; decide the override (owner question 3) before relying on this gate, because today the cheapest way out is the fail-open one.

### SFH-6 | MEDIUM | tests/41-ci-wait.sh:94-131,139-156 | No test pins what happens to a PR named outside the Status cells when a record for it exists, nor a mis-spelled Status cell, nor a NUL

- Failure path: `m23` (read every "named elsewhere" PR that has a `ci-pr-N.json`) SURVIVED: the suite pins "not read" only for PRs with no record (96 to 99). So owner question 4 is untested in both directions, and SFH-1's input has no case. No case has a Status cell with `PRs #7, #8` or `PR #7, #8`; none has a NUL.
- Evidence: RAN `m23`: `PASS 41-ci-wait`.
- New in the fix commit (the tests added there).
- Suggested fix: one job with two done rows, one PR in a Status cell (green record), one only under Completed phases with a red record, asserting whatever the owner decides; one `PR #7, #8` row.

### SFH-7 | MEDIUM | lib/ci.sh:86-88 | Outside git no workflow read happens, but run.log says "no workflow file at HEAD"

- Failure path: `TOP` empty skips `ls-tree`; an absent record then passes with `PR #N: no CI runs and no workflow file at HEAD (absent, not a pass)`. Nothing was read and there is no HEAD. `lib/chain.sh:139` logs "dirty-tree check off, receipt check off" and does not name this third check.
- Evidence: RAN `probe2.sh` case `absent_nogit` (`TOP=`): that log line, then `=> DONE PASSES`. `tests/41-ci-wait.sh:130` pins the wording for exactly this non-git case. With the real `gh`, `ci_head` fails outside a repo unless `GH_REPO` is set (REASONED), so reach is narrow.
- New in this diff; P3R1-32 left open by the fix.
- Suggested fix: log `workdir is in no git repo; workflow files not read` on that branch.

### SFH-8 | LOW | lib/ci.sh:45,52-55 | `ci-wait` leaves dispatch runs out with no word in run.log

- Failure path: a head whose only run is a green `workflow_dispatch` logs `ci PR #9 at <sha>: absent ()` and exits 10; nothing says one run was left out.
- Evidence: RAN `cw.sh` case C: exactly that line.
- New in this diff; P3R1-25 open.
- Suggested fix: have `ci_runs` count what it drops and add `, N workflow_dispatch runs left out` to the log line.

### SFH-9 | LOW | lib/ci.sh:81 | A record whose first JSON value is valid and the rest is not reads as its first verdict

- Failure path: `ci-pr-7.json` holding `{"pr":7,"verdict":"success",...}` then a line of garbage: jq prints `success`, then fails; `2>/dev/null || true` hides the failure and the record counts. `ci_wait` writes through a temp file and `mv`, so only a hand-edited or appended file reaches this.
- Evidence: RAN `probe2.sh` case `garbage`: `=> DONE PASSES`; case `twodoc` (two verdicts) is refused as unread.
- Pre-existing.
- Suggested fix: `jq -rs 'if length == 1 and .[0].pr == $n then .[0].verdict // "" else "" end'`.

### SFH-10 | LOW | lib/ci.sh:107 | The `[ -n "$cur" ]` guard in `ci_head` has no test

- Failure path: `m10` removes it and the scenario passes. It matters only for a record with no `head_sha` while `gh pr view` fails (both sides empty, equal). `ci_wait` always writes a 40-hex head, so reach is hand-written records.
- Evidence: RAN `m10`: `PASS 41-ci-wait`.
- Pre-existing.
- Suggested fix: in the `d3d` step, also try a record with `head_sha` deleted.

### SFH-11 | LOW | tests/41-ci-wait.sh:173-186 | Three more survivors or near-survivors on the workflow read and the run list

- Failure path: three changes to `lib/ci.sh` that the scenario does not catch, or catches only by accident. `m26` (pathspec `.github/workflows/ci.yml` only) SURVIVED: "any file under the directory" is pinned for no name but `ci.yml` (P3R1-44, left open on purpose). `m25` (`--limit 1`) SURVIVED: the fake ignores `--limit` (P3R1-24, P3R1-33 open). `m9` (`git ls-files` for `ls-tree HEAD`) was KILLED, but only by the last case, `ub` (`ls-tree failing at done: exit 0`): case `a4` deletes the file on disk and leaves it in the index, so it does not separate the index from HEAD; a staged, uncommitted workflow is the unpinned shape.
- Evidence: RAN each (`out-m26-*.txt`, `out-m25-limit1.txt`, `out-m9-lsfiles.txt`).
- New in the fix commit (the tests added there).
- Suggested fix: in `a4`, `git rm --cached` the file as well; a second workflow file name in `a2`; a fake that honours `--limit`.

### SFH-12 | LOW | lib/ci.sh:36-43 | A `ci-wait` that dies part-way leaves `ci-pr-N.json.tmp` with verdict success for the runs read so far; its reason is on stderr only

- Failure path: `gh run view` of the second run fails; `die` ends only the pipeline's left side, `jq -s` still writes a `success` verdict over one run into the `.tmp`; `pipefail` plus `set -e` then stop before `mv`, exit 1. Fail-closed (the runner reads only `ci-pr-N.json`), but a green-looking file sits in `gate-logs/` and run.log has no line.
- Evidence: RAN `cw.sh` case A: `rc=1`, `blast-off: gh run view 12 failed`, `ls gate-logs` shows only `ci-pr-7.json.tmp` = `{"verdict":"success","runs":[{"id":11,...}]}`.
- Pre-existing.
- Suggested fix: collect the views into a variable first (`views="$(for ...)" || die`), then jq.

### SFH-13 | LOW | lib/ci.sh:83 | Criterion 4 at `done` rests on the record alone; records written before this phase carry no event

- Failure path: a `success` record written by phase-2 code from a green dispatch run still passes `done`; a `failure` one from a red dispatch still refuses until `ci-wait` is run again. Jobs in flight across the upgrade only.
- Evidence: REASONED from `:81-83` (only `.pr` and `.verdict` are read) and `:38` (the record holds no event).
- New in this diff (the exposure); P3R1-23 left open by the fix.
- Suggested fix: record `event` per run, or say in the PR body that records written before this change must be re-made with `ci-wait`.

## Focus 1: swallowed errors and fallbacks in lib/ci.sh

| Line | Construct | What it hides | Can it end in `done` exit 0 with CI not passed? | Logged? |
|---|---|---|---|---|
| 97 | `{ grep ... \|\| true; }` | grep exit 1 (no token), exit 2, and binary input (exit 0, no output) | Yes: NUL byte (SFH-4), unread spelling (SFH-3) | "no PR named in checkpoint.md; CI not read", false in both cases; grep's own message on stderr only |
| 69-70 | `all=`, `prs=` assignments | nothing: `local` is declared apart, so a failing `sed`, `awk`, `sort`, `paste` or a missing file stops the runner (`pipefail` is inherited by `$(...)`; `set -e` is not, but the assignment's status is checked) | No (exit 1) | "runner exit N without a state" (`lib/chain.sh:21`) |
| 71-73 | `other` list | a PR named outside the Status cells | Yes (SFH-1) | one clause on a line written at exit 0 |
| 74-76 | fallback | none; reads more, not less | No; false refusal instead (SFH-2) | yes |
| 77-79 | no PR anywhere | by design | Yes, by design (a job with no PR) | yes |
| 81 | `2>/dev/null \|\| true` | missing, unreadable or malformed record | No: `v` empty, refused as unread. Exception: valid first value plus garbage (SFH-9) | refusal names the file, not jq's error |
| 86 | `[ -z "$TOP" ] \|\|` | the whole workflow read outside git | Yes, by design (absent passes) | yes, with untrue wording (SFH-7) |
| 86 | `\|\| die` | nothing | No (exit 1; fix unit's M12, case `ub`) | stderr only; run.log gets "runner exit 1 without a state" |
| 105 | `h="$(jq ...)"`, no handler | nothing: jq failing stops the runner | No | as above |
| 106 | `\|\| cur=` | `gh pr view` failing, timing out, or jq failing | No: empty `cur` is refused ("head unknown (gh pr view N failed)") | yes |
| 107 | `[ -n "$cur" ] &&` | n/a (a guard) | Only if removed, with a head-less record (SFH-10) | n/a |
| 20, 30 | `ci_runs ... \|\| die` | nothing: gh or jq failing gives "gh run list failed", exit 1 (RAN `cw.sh` B) | No | stderr only |
| 20-23 | empty list after `BLAST_OFF_CI_APPEAR` | runs listed later than 60 s | Record is absent: refused with a workflow at HEAD, passes without | "absent ()" |
| 26 | `> /dev/null 2>&1 \|\| [ $? -ne 124 ] \|\|` | every `gh run watch` failure but a timeout (auth, network, unknown run) | No: the run is recorded as `gh run view` shows it; unfinished is `failure` | not logged |
| 36 | `\|\| die` inside a pipeline | ends only the subshell; `pipefail` carries it | No (SFH-12) | stderr only |
| 45 | `$(jq ...)` inside the `log` argument | jq failing: the list in the log line is empty | No | cosmetic |
| 53 | `--limit 100` | runs past the 100th | Mostly fails closed (absent); a red run could drop out | no (P3R1-24 open) |
| 54 | `select(.event != "workflow_dispatch")` | dispatch runs, silently | Not by itself | no (SFH-8) |

What `set -euo pipefail` does and does not stop here: it is live at the call site (`lib/chain.sh:159` is a plain statement, not a condition), so every bare assignment from a failing pipeline in `ci_check` and `ci_head` ends the runner with exit 1. It does not see a command that exits 0 with empty output (grep on binary input, `gh run list` printing `[]`), anything on the left of `||`, or a `$(...)` inside another command's argument. The only `chain_end 0` is `lib/chain.sh:159`, after `ci_check`; I found no path from `status: done` to exit 0 around it (REASONED).

## Focus 2: mutants run on the scenario (lib/ci.sh, one change each)

| Mutant | Result | First failing assertion |
|---|---|---|
| m1 drop `select(.event != "workflow_dispatch")` | KILLED | `green dispatch run counted: exit 0` (line 76) |
| m2 always read the union (`prs="$all"`) | KILLED | `green and absent records: exit 10` (126) |
| m3 drop the `elif [ -n "$all" ]` fallback only | KILLED | `no table, PR in prose, no record: exit 0` (144) |
| m4 drop `ci_head` on the absent branch | KILLED | `absent record gh could not check: exit 0` (123) |
| m5 absent-with-workflow logs instead of refusing | KILLED | `absent CI with a workflow at HEAD: exit 0` (176) |
| m6 drop the "named elsewhere and not read" part | KILLED | `PRs read at done not logged` (129) |
| m7 `s/^0*//` removed | KILLED | `done with unread CI: exit 10` (101; message names `#07`) |
| m8 `-i` removed from grep | KILLED | `done with unread CI: exit 10` (101) |
| m9 `git ls-files` for `ls-tree ... HEAD` | KILLED, by `ub` only | `ls-tree failing at done: exit 0` (197); see SFH-11 |
| m10 `[ -n "$cur" ]` guard removed | SURVIVED | SFH-10 |
| m11 unfiltered run list at line 20 only | KILLED | `green dispatch run counted: exit 0` (76) |
| m12 unfiltered run list at line 30 only | KILLED | `green dispatch run counted: exit 0` (76) |
| m13 fallback only when there is no table | KILLED | `done row with no PR, PR named below: exit 0` (152) |
| m14 `/pull/N` dropped from the regex | KILLED | `second PR unread: exit 0` (110) |
| m15 drop `ci_head` on the success branch | KILLED | `green record of an old head: exit 0` (120) |
| m16 drop the `.pr == $n` check | KILLED | `PR 8's record for PR 9: exit 0` (114) |
| m17 whole row read, not the last cell | KILLED | `green and absent records: exit 10` (126) |
| m18 `--json databaseId` without `event` | KILLED | `green dispatch run counted: exit 0` (76) |
| m19 `PR #` with the space required | KILLED | `done with unread CI: exit 10` (101) |
| m20 `ci_head` without the head comparison | KILLED | `green record of an old head: exit 0` (120) |
| m21 line 81 without `2>/dev/null \|\| true` | KILLED | `done with unread CI: exit 1` (101) |
| m22 Phase plan range left open to end of file | KILLED | `green and absent records: exit 10` (126) |
| m23 read "named elsewhere" PRs that have a record | SURVIVED | a proposed fix, not a defect: SFH-1, SFH-6 |
| m24 `ls-tree` also outside git | KILLED | `green and absent records: exit 1` (126) |
| m25 `--limit 1` | SURVIVED | SFH-11 (known, fake ignores `--limit`) |
| m26 pathspec `.github/workflows/ci.yml` | SURVIVED | SFH-11 (known, P3R1-44) |
| m27 no log on absent with no workflow | KILLED | `absent not logged` (130) |

Every kill is a `FAIL 41-ci-wait` line with a `| FAIL:` assertion; shellcheck passed on each mutant, and none died of a syntax error or unbound variable. One extra run of m1 with `fail` made to report and go on (in the copy's `tests/lib.sh`) listed ten failing assertions, among them `green dispatch run counted`, `red dispatch runs counted: exit 10`, `a dispatch run was watched or viewed`, `dispatch-only head in the wf job`, `absent CI with a workflow at HEAD: exit 0`.

## Focus 3: the five acceptance criteria and their test lines (tests/41-ci-wait.sh)

1. No runs plus a workflow file at HEAD: exit 10. Lines 169-170 (the record is `ci-wait`'s own, absent), 173-176 (refused, file named), 178-179 (remedy text, status unchanged), 181-182 (workdir a subdirectory), 184-186 (HEAD, not the working tree), 193-197 (a failing read is exit 1). Proved; live under m5, m9, m24.
2. No runs and no workflow file: allowed and logged. Lines 171-172 (git repo whose HEAD has `README.md` and `.github/dependabot.yml`), 125-126 and 130 (non-git workdir, PR 9). Proved; live under m27 and the fix unit's M18a/b.
3. Status cells only. Lines 94-98 (fixture: `pr#07` and `/pull/9` in Status cells; 98 in another cell, 96 in a `P1` row, 97 under `## Decisions`, 99 in prose), 100-101, 109-110, 125-127, 129. Proved where a Status cell names a PR. Lines 141-152 pin the opposite when none does (the fallback): prose is read. So the criterion as written holds only in the first case (SFH-2).
4. `workflow_dispatch` in neither direction:

| | green dispatch is no pass | red dispatch is no failure |
|---|---|---|
| `ci-wait` | 75-76 (PR 14: exit 10, absent, runs `[]`), 79 (not watched or viewed), 169-170 | 77-78 (PR 15: exit 0, success, runs `[71]`; 72 listed at once, 73 late), 79 |
| `done` | 169-176: `ci-wait`'s absent record of the dispatch-only head, then `done` refused with a workflow at HEAD (and allowed, logged "absent, not a pass", with none: 171-172) | no direct assertion: no `done` run uses PR 15's record |

   The empty cell is a note, not a finding: `ci_check` reads only the record's verdict (`lib/ci.sh:81-83`), so it follows from 77-78 plus 125-126 and 188-190 (a success record passes `done`). I found no one-line change to the shipped code that breaks that cell and passes the suite. The real gap for it is SFH-13 (old records).
5. Tests and docs. Tests: above. Docs: I read `docs/spec.md` rows F7, `ci-wait`, exit 10 and `41-ci-wait`, `README.md`, `bin/blast-off`, `skills/blast-off/SKILL.md` step 4 and `templates/checkpoint.md:29-32` against `lib/ci.sh`; they state what the code does. Two remedies in them inherit SFH-5 (README exit 10 row: "Absent: push to the PR branch so a run starts") and one inherits SFH-2 (template: "Name any other PR by its branch or as `other PR <n>`, no '#'" does not warn about a `/pull/<n>` link).

## Round-1 findings checked

| ID | resolved / reshaped / open / not checked | why |
|---|---|---|
| P3R1-1 (HIGH) | reshaped | Resolved when no Status cell names a PR (RAN m3, m13; probes `notrail`, `escpipe`, `xrepo_link_nopr` refuse). Still passes for a row closed without its PR beside a row that names one (SFH-1), and for an unread spelling (SFH-3); both now leave a log line |
| P3R1-2 | reshaped | Logged, not read, exit 0, also with a red record on disk (SFH-1) |
| P3R1-3 | open | Owner question 2; the spec states the limit. See SFH-5 |
| P3R1-4 | open | Owner question 3; the message is reworded but its remedy cannot work for the stacked case (SFH-5, REASONED) |
| P3R1-5 | resolved | Template lines 29-32 match the code; they also tell the child how to skip the check (SFH-1) and do not cover a link (SFH-2) |
| P3R1-6 | resolved | SKILL step 4 states both cases, by reading |
| P3R1-7 | resolved | README names absent and the Status cell; the absent remedy inherits SFH-5 |
| P3R1-8 | resolved | `bin/blast-off` header, by reading |
| P3R1-9 | reshaped | A log line exists and is false for these cells ("no PR named"); `PR #7, #8` drops 8 with no line (SFH-3, RAN) |
| P3R1-10 | resolved | Cases `nt`, `np`, third `np` run; m3, m13 killed |
| P3R1-11 to P3R1-19 | resolved | Killed by the fix unit (not repeated, as told). Next to them: m9 killed only by `ub`, m26 survived (SFH-11) |
| P3R1-20 | resolved | Lines 169-176; live in the soft run of m1 |
| P3R1-23, -24, -25, -28, -32, -33, -44 (LOW, left open) | open | SFH-13, SFH-11, SFH-8, SFH-4, SFH-7, SFH-11, SFH-11 |

## Owner questions (1-4): is the default the safe one?

1. Fallback to every PR named anywhere when no Status cell names one. Safe as a gate: it refuses (RAN). Its cost is larger than the baton states: the hint does not work for a `/pull/N` link, and the refusal sends the agent to `ci-wait` another repo's number in this repo (SFH-2). It also leaves alternative (b) undone, which is where the real hole is (SFH-1).
2. The workdir's HEAD decides "runs were due". Safe in the common direction (a workflow at HEAD refuses), unsafe to rely on in the other: an uncommitted or staged workflow counts as none. The stated remedy cannot work for an earlier stacked PR whose branch holds no workflow file (SFH-5, REASONED).
3. Any file counts, no override. Fail-closed, so safe alone. Not safe together with question 4's default: the only exits from the dead end are the record file and the Status cell, and removing the PR token from the cell passes with a log line.
4. A PR named only under Completed phases is logged and not read. Not the safe default: this is the fail-open of SFH-1 (RAN, red record ignored). Reading it when this job holds a `ci-pr-N.json` for it keeps issue 26's fix for another repo's PR (no record here) and passes the present suite (m23).

## What I did not check

- Any other scenario (`51-templates`, `70-docs`, the full suite, `scripts/gate.sh`): not run, by rule.
- SFH-1, SFH-3, SFH-4, SFH-7 through the real runner end to end: shown with the stubbed harness on the real `ci_check`, not with a `blast-off run`.
- GitHub's behaviour (which workflow file a stacked PR's run uses, the literal `workflow_dispatch` event value, ordering under `--limit`): reasoned, no live repository.
- grep other than GNU 3.11; locales other than `C` and `C.UTF-8`.
- `lib/receipt.sh`, `lib/checkpoint.sh` beyond the functions `ci_check` shares a parser with; docs outside the changed rows.
- Left in place, not deleted: my two temp dirs `/tmp/sfh2.aWjOTf` and `/tmp/sfh2w.BuzXns`. After the last run: no `tests/run` process, no `blast-off-test-*` unit.
