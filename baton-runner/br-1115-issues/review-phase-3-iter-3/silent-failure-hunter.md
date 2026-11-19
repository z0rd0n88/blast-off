# silent-failure-hunter: phase 3 (issue 26), review round 3

ExecStart check after my last scenario run: `ExecStart=/home/alex/blast-off/.worktrees/blast-off-build/bin/blast-off run %f` (correct, untouched).

## Summary

- 1 HIGH, 3 MEDIUM, 10 LOW. No CRITICAL.
- The HIGH is a fail-open this diff introduced: a Phase plan row the parser does not read (key `P1` or `**1**`, an indented or tab-led row, a row under a second `## Phase plan` heading) is dropped from every gate without a word. Beside one readable `no PR` row, a done row naming a red PR ends `job done`, exit 0. The phase-2 code refused the same checkpoints with exit 10. I ran both trees.
- I found no fail-open that a job following `templates/checkpoint.md` and `templates/brief.md` as written can reach through this diff's code. Two pre-existing ones sit in `ci_wait`: SFH-5, reachable by timing alone, and SFH-7, reachable only by a child that goes on after `ci-wait` exits 1.
- The line walk found no place where a failing tool, an empty output or a malformed record turns into exit 0 on its own. Each `|| true`, `2>/dev/null` and unchecked status falls to "unread" or "refused", except where a record is hand-written (SFH-8).
- Tests: 7 mutants of mine killed (4 by message text only, the exit code did not change), 5 survived. The README, spec and skill text for the new rules has no test.
- Scenario runs used: 12 of 14, one at a time, all on `/tmp/p3r3-sfh.EaN615/copy` (or a phase-2 tree in the same temp dir). No tracked file touched.

## Findings

### SFH-1: a Phase plan row the parser does not read is dropped from the done gate without a refusal
- Severity: HIGH
- File: lib/checkpoint.sh:43 (the `/^| *[0-9]/` filter and the `/^## Phase plan/,/^## /` range), lib/ci.sh:70-84 (reads only what `cp_done_cells` returns), tests/41-ci-wait.sh:97 and :132 (pin the drop for key `P1`)
- Reachable by a template-following job: only by an off-template checkpoint. The child or owner must have written a row whose line does not start `|`, optional spaces, digit (a key such as `P1`, `R1`, `Phase 1`, `**1**`; a leading space or a tab), or a second `## Phase plan` heading, or a cell after Status. `templates/checkpoint.md:24` states the digit rule.
- Direction: fail-open
- Origin: introduced by this diff for the PR read (phase 2 read the whole file, so it refused all of these). The same blind spot in the all-rows-done check (probe A7) is pre-existing.
- Failure path: checkpoint at `status: done` with `| 0 | a | b | done (abc1234) · no PR |` and `| P1 | a | b | done (abc1234) · PR #7 |`; `gate-logs/ci-pr-7.json` is red. `cp_plan_rows` prints only row 0. `receipt_all_done` sees no open row. `ci_check` sees one done row that says `no PR`, logs `PRs read: none`, returns. `chain_end 0 "job done"`. PR #7 is never read. A done row with neither token in such a line is not refused either, which ruling 1 asks for ("a done row with neither is refused").
- Evidence: run 2 and run 12 on HEAD, run 3 on the phase-2 tree (`git archive feat/br-1115-issues/phase-2`), same probe file:

  | Probe (beside a readable `no PR` row, PR 7 red) | HEAD | phase 2 |
  |---|---|---|
  | A1 key `P1` | exit 0, `job done` | exit 10, `PR #7 CI red` |
  | A2 key `**1**` | exit 0 | exit 10 |
  | A3 indented row | exit 0 | exit 10 |
  | A4 row under a second `## Phase plan` heading | exit 0 | exit 10 |
  | A10 tab before the key | exit 0 | exit 10 |
  | A13 keys `Phase 1` and `R1` | exit 0 | exit 10 |
  | A5 a cell after Status that starts `done` | exit 0 | exit 10 |
  | A7 open rows `P1`, `**2**` (no PR) | exit 0 | exit 0 |
  | A6, A8, A9, A11, A12 (no trailing pipe, `**done**`, key `1)`, escaped pipe, empty cell after Status) | exit 9 | exit 9 |

- Earlier record: the `P1` case is known and was left open on purpose. Round 1's P3R1-17 (a test gap: dropping the digit-key filter survived) was closed by adding the `P1` row to the `fin` fixture, which pins the drop. Round 2 marked that "resolved, with a catch: the `P1` row test pins P3R2-1's behaviour as wanted" (`baton-phase-3-review-2.md:120`, P3R2-20). The fix baton says "A row whose key is no digit (`P1`) is still not a row ... the rulings do not change row recognition (P3R1-29, pre-existing). Deliberate limit, open" (`baton-phase-3-fix-2.md:38`). What this report adds: (1) measured against the diff's base, the effect on the PR gate is new, because phase 2 read these PRs and refused; (2) the same drop takes digit-keyed rows too: an indented or tab-led row and a row under a second `## Phase plan` heading, which that note does not cover; (3) ruling 1's "a done row with neither is refused" is not applied to any of them. The severity is mine to propose and the synthesizer's to set with those facts.
- Suggested fix: keep ruling 1 (no prose fallback) and refuse what cannot be parsed. At `status: done`, exit 10 when the Phase plan section holds a line starting (after optional blanks) with `|` that is not the header, not the `|---|` separator and not a row `cp_plan_rows` returned, and when the file has more than one `## Phase plan` heading. Name the line in the message. Turn 41:97 from "must not hold done back" into "is refused".

### SFH-2: the brief gives no step for `absent` on a head with no workflow file, and ci-wait's exit 10 explains nothing
- Severity: MEDIUM
- File: templates/brief.md:135-137, lib/ci.sh:45-46
- Reachable by a template-following job: yes (any repo with no workflow file)
- Direction: fail-closed
- Origin: introduced by this diff (the brief text is new; `ci_wait` exiting 10 on absent is pre-existing)
- Failure path: the child runs `ci-wait`; it prints one log line, `ci PR #9 at <sha>: absent ()`, and exits 10 (probe G3). Brief step 4 says "`absent`, no runs, is not a pass: where the PR's head has a file under `.github/workflows/` push once more for a run, and if none starts leave the row open, set `status: blocked`". For a head with no such file it says nothing. A careful child, told that a command which just exited 10 "is not a pass", sets `status: blocked`. Criterion 2 is reached only by a child that reads the silence as "go on". The skill text (skills/blast-off/SKILL.md:35-37) states the rule, but the child reads the brief.
- Evidence: templates/brief.md:131-137 read; probe G3; tests/51-templates.sh:87-88 pins only the "is not a pass" and "set `status: blocked`" phrases.
- Suggested fix: add the other half to the brief ("where it has none, write the row `done (<sha>) · PR #<n>` and go on: the runner lets it through and logs it") and pin it in 51. Have `ci_wait` print one line on absent that says which case this is and what to do.

### SFH-3: no owner procedure for a PR that no workflow can start on; the README tells its reader to "ask the owner"
- Severity: MEDIUM
- File: README.md:134, lib/ci.sh:94, docs/spec.md:97
- Reachable by a template-following job: yes (stacked draft PRs, the delivery the skill prescribes, in a repo whose workflows filter on the base branch)
- Direction: fail-closed, with a push toward a fail-open edit
- Origin: introduced by this diff
- Failure path: a stacked PR whose base is the previous phase's branch gets no run where the workflow says `on: pull_request: branches: [main]` (GitHub behaviour, from recall). Record `absent`, workflow file at head, exit 10: "there is no override: ask the owner". The owner opens the README, whose row for exit 10 ends "ask the owner". Nothing says what the owner may do. The edits that work are the ones the phase set out to close: change `PR #7` to `no PR`, or hand-edit the record's verdict. The refusal itself is ruling 2 and is not questioned here.
- Evidence: README.md:134 and lib/ci.sh:94 read. `command grep -n -i 'override' README.md docs/spec.md` hits README.md:134 and docs/spec.md:39, :61, :97, :221; only README.md:134 and docs/spec.md:97 are about this, and :97 ends "that is the owner's to settle".
- Suggested fix: name the owner's allowed ways out in the README (retarget the PR to a base the filter matches, widen the filter, or a recorded owner waiver the runner logs), and say that `no PR` is not one of them.

### SFH-4: a job started before this change is refused at `done` for each phase that opened no PR, no child runs, and no text says so
- Severity: LOW
- File: lib/ci.sh:78, README.md (no line), docs/spec.md (no line)
- Reachable by a template-following job: yes, a job whose brief and checkpoint came from the templates before this diff and that closed a phase with no PR
- Direction: fail-closed
- Origin: introduced by this diff
- Failure path: the earlier templates (main and phase 2: `templates/brief.md:143`, `templates/checkpoint.md:27`) tell a child to write `done (<sha>) · PR #<n>`; they have no `no PR`. A phase that opened no PR is closed as `done (<sha>)`. The job reaches `status: done`; the runner exits 10. On every later start the status is still `done`, so no child is launched (probe H1: `child launched after the refusal: no`). Only a person can edit the row. The refusal says what to write, but not that a person must do it, and it does not offer "set the status back" as `receipt_all_done` does (lib/receipt.sh:70).
- Evidence: probe H1 (exit 10, no fake-marker); the phase-2 tree passed the same checkpoint (run 3, H1 exit 0); `command grep -n -i -E 'no PR|PR #'` on main's and phase 2's two templates shows `PR #<n>` and no `no PR`; `command grep -n -i -E 'before this|started before|existing (job|checkpoint)|live job|older (job|checkpoint)|upgrade|migrat|already running' README.md docs/spec.md skills/blast-off/SKILL.md templates/*.md` has one hit, docs/spec.md:107, on another subject.
- Suggested fix: one README line under exit 10 ("a job started before <version>: add `PR #<n>` or `no PR` to each done row by hand, or set `status: running` so a child does it"), and the same choice in the refusal text.

### SFH-5: ci-wait lists runs once more after the watches, so a run listed later is never read
- Severity: MEDIUM
- File: lib/ci.sh:20-33
- Reachable by a template-following job: yes, by timing
- Direction: fail-open
- Origin: pre-existing (out of this diff; reported because it is the one template-reachable fail-open I found)
- Failure path: the wait for runs to appear (lines 20-23) applies only while the list is empty. With one run listed at once, `ci_wait` watches it, re-lists once, finds nothing new and writes `success`. A second workflow's run listed after that re-list is not in the record, and `ci_check` does not list runs at `done`: it compares only the head sha.
- Evidence: probe I3: head with green run 95 and red run 96 listed from the third `run list` on: `ci-wait` exit 0, record `{"verdict":"success","runs":[95]}`, 2 lists made. How often GitHub lists a push's runs apart is from recall.
- Suggested fix: at `done`, `ci_check` lists the head's runs (`ci_runs`) and treats an id missing from the record as unread.

### SFH-6: `no PR` beside a PR written without `#` passes, and the stray-check message invites dropping the `#`
- Severity: LOW
- File: lib/ci.sh:69-76
- Reachable by a template-following job: only by an off-template checkpoint (a cell that says `no PR` and also names a PR as `PR 7`, `pull 7`, `pull/7`, `GH-7`, `PR # 7`, `PR #0`)
- Direction: fail-open
- Origin: pre-existing (phase 2 passed the same cells, run 3); the stray check added here narrows it but stops at `#<digit>` and `/pull/`
- Failure path: `done (abc1234) · no PR · PR 7`: `ci_prs` finds nothing, the stray pattern finds nothing, `no PR` matches, the row counts as "no PR". For `no PR (#7 dropped)` the refusal says "write each of the phase's PRs as `PR #<n>` and no other '#<n>' there": deleting the `#` satisfies it.
- Evidence: probes B1 to B7, exit 0, `PRs read: none; rows that say no PR: 0`, PR 7's record red.
- Suggested fix: in a cell that says `no PR`, refuse any other digit run outside the sha and the ` · usage ` tail; or accept only the exact forms `done (<sha>) · no PR` and `done (<sha>) · PR #<n>` plus the usage tail.

### SFH-7: a failed ci-wait leaves the older record in force, and a half-written `.tmp` beside it
- Severity: LOW
- File: lib/ci.sh:36-43
- Reachable by a template-following job: only by a child that goes on after `ci-wait` exits 1 (the brief does not tell it to)
- Direction: fail-open
- Origin: pre-existing
- Failure path: `die` at line 36 runs on the left side of a pipeline, so it ends only that subshell. `jq -s` still writes `$r.tmp` from the runs read so far (verdict `success` for a partial list). pipefail and errexit then end the command with exit 1 before `mv`. The record of the earlier read stays, and at `done` it passes while the head is unchanged.
- Evidence: probe G1: `ci-wait exit 1 | blast-off: gh run view 92 failed | record now: {"utc":"old","verdict":"success"} | files: ci-pr-18.json ci-pr-18.json.tmp | tmp: {"verdict":"success","runs":[91]}`; probe G2: `done` exit 0 on that record.
- Suggested fix: remove `$r` (and `$r.tmp`) at the start of `ci_wait`, so a failed read leaves "unread".

### SFH-8: the runner trusts the record as written; no shape check on what it reads back
- Severity: LOW
- File: lib/ci.sh:86, :89-92, :112-114 (against :19, which does check the sha)
- Reachable by a template-following job: no (needs a hand-written record; C11, D5 and D7 also need a `gh` that returns a non-sha)
- Direction: fail-open
- Origin: pre-existing for the verdict read; introduced by this diff for the unvalidated `$h` passed to `git ls-tree "$h^{commit}"`
- Failure path and evidence (run 2):
  - C5 `verdict: success` over a failed run in `runs`: exit 0. The scenario relies on this itself (tests/41-ci-wait.sh:109).
  - C3 two JSON values, a success then another PR's failure: exit 0 (the second prints an empty line, which `$(...)` strips).
  - C6 `pr: 8.0`: exit 0.
  - C11 record `head_sha: "null"` and gh printing `{"headRefOid":null}`: exit 0.
  - D5 head `HEAD`, D7 a 12-character sha: accepted and resolved by git.
  - Refused as they should be: C1 `pr` a string, C2 success then failure, C4 no head_sha with gh failing, C7 empty file, C8 verdict `skipped`, C9 gh printing nothing, C10 gh head null, C12 gh printing the head but exiting 1.
- Suggested fix: one `jq -e` shape test per record at `done` (one value, `.pr` the integer, `.head_sha` 40 hex, `.verdict` in the three words, and `success` only when every run's conclusion is green).

### SFH-9: every `git ls-tree` failure gets the "fetch" advice, and any path under `.github/workflows` counts as a workflow
- Severity: LOW
- File: lib/ci.sh:92-94
- Reachable by a template-following job: yes for the second half (a repo whose `.github/workflows` holds only a README or `.gitkeep`)
- Direction: fail-closed
- Origin: introduced by this diff
- Failure path: `2>/dev/null` hides why git failed, so a tree sha (probe D6), a corrupt repo or a `safe.directory` refusal all read "git -C <top> fetch origin pull/<n>/head". `.github/workflows` as a plain file (D1), a symlink (D2), a directory with only `README.md` (D3) or only `sub/x.yml` (D4) is "a workflow file", refused with "no override".
- Evidence: probes D1 to D6, all exit 10 with those messages. The spec says "any file" on purpose (docs/spec.md:97); GitHub reading only `*.yml` and `*.yaml` directly in that directory is from recall.
- Suggested fix: keep git's stderr in the message; count only `.github/workflows/*.yml` and `*.yaml` blobs, or say in the README that any file there counts.

### SFH-10: `BLAST_OFF_CI_APPEAR`, `_WATCH` and `_HEAD` are not checked as numbers; a bad value switches the wait or the watch off
- Severity: LOW
- File: lib/ci.sh:21, :26, :113; lib/chain.sh:89-91 (`chain_nums` does not list them)
- Reachable by a template-following job: yes (owner sets `BLAST_OFF_CI_APPEAR=60s`)
- Direction: fail-closed
- Origin: pre-existing
- Evidence: probe I4: `BLAST_OFF_CI_APPEAR=60s` gives `[: 60s: integer expression expected`, an `absent` record and exit 10 after 0 s. Probe I5: `BLAST_OFF_CI_WATCH=abc`: `timeout` exits 125, which `|| [ $? -ne 124 ]` swallows with no log line; the run is recorded unwatched, `failure`, after 0 s (the "watch calls for 51: 1" it prints is the scenario's own call at 41:69; the probe added none).
- Suggested fix: validate the three in `ci_wait` and `ci_head` as `chain_nums` does.

### SFH-11: statuses dropped on the gate's read path (fail-closed today, silent)
- Severity: LOW
- File: lib/ci.sh:72, :81, :104
- Reachable by a template-following job: no
- Direction: neither today
- Origin: introduced by this diff
- Failure path: (a) line 72 does not check sed's status: if that sed fails, `$(...)` is empty and the stray check passes everything. The one cause I can name is a sed without the GNU `I` flag, and the runner already needs GNU sed (`0,/re/` at lib/checkpoint.sh:21), so this is reasoned, not run, and not a new dependence. (b) line 81 reads `cp_done_cells` through process substitution, so a failing sed or awk is not seen; an empty stream is caught by the "no done row" refusal, a cut-short one is not. (c) line 104 turns a grep error (exit 2) into "no PR named"; the row then needs `no PR` to pass.
- Evidence: code read; `chain_end` is never called from a subshell in `ci_check` (the loop reads from `< <(...)`, not from a pipe), so every refusal does exit the runner: probes and the scenario's `refused` helper confirm exit 10.
- Suggested fix: `cells="$(cp_done_cells)" || die ...` then loop over the variable; write the stray strip without `I` (`[Pp][Rr] ?#`).

### SFH-12: test gaps and loose assertions
- Severity: LOW
- File: tests/41-ci-wait.sh:115, :204, :209; tests/70-docs.sh
- Reachable by a template-following job: n/a
- Direction: neither
- Origin: introduced by this diff
- Evidence:
  - 41:115 greps the cumulative `run.log` for `PR #9 CI unread: no readable record for PR 9`, a line the run at 41:110 already wrote. Only `rc` tells there (mutant M1 was killed by `rc`).
  - 41:204 accepts any refusal that starts `phase row 0 ` for seven different cells; which refusal fires is not pinned.
  - 41:209 accepts exit 9 or 10 for the NUL cell and does not assert that PR 7 was read (on HEAD it is: `PRs read: 7`, exit 10).
  - Mutants M2, M3, M6 and M7 change no exit code; they are killed only by a message grep.
  - Five mutants survive (table below): the `[ -n "$cur" ]` guard, `^{commit}`, the word boundary of `no PR`, `sort -un`, `grep -a`.
  - tests/70-docs.sh pins none of the new rule text in README.md, docs/spec.md or skills/blast-off/SKILL.md (it checks only that the README has a row for each exit code). Criterion 5 for those three files rests on reading.
- Suggested fix: per-run log files or `tail -n 1` in the `fin` job's greps; one case each for a record with no `head_sha` while gh fails, a tree-sha head, `no PRs`, and a PR named twice.

### SFH-13: the pass line says "no CI configured", which is more than was read
- Severity: LOW
- File: lib/ci.sh:95
- Reachable by a template-following job: yes
- Direction: neither (the pass is ruling 2; this is the wording of the log the ruling asks for)
- Origin: introduced by this diff
- Failure path: `ci_runs` lists GitHub Actions runs of the head only. A repo checked by another CI service through commit statuses has no workflow file and no runs: the log says "no CI configured". A PR that deletes `.github/workflows` logs the same line.
- Evidence: lib/ci.sh:53-54 (`gh run list --commit`, the only read of CI) and :95 (the log text) read; probe D0 prints the line. That `gh run list` shows only Actions runs, and that a PR without the directory gets none, is from recall of GitHub's behaviour.
- Suggested fix: log what was read: "no Actions runs and no file under .github/workflows at its head <sha>".

### SFH-14: small text drift
- Severity: LOW
- File: bin/blast-off:37-38, templates/checkpoint.md:33-34
- Reachable by a template-following job: n/a
- Direction: neither
- Origin: introduced by this diff
- Evidence: the exit-code header for 10 leaves out "no done row", "both tokens or a stray `#<n>`" and "head commit cannot be read", which README.md:134 and docs/spec.md:97 list. The template still says "It reads PRs nowhere else in this file ... name another PR in prose, outside the table": true and wanted for another repo's PR, but it also tells a child where a PR is invisible to the gate (what is left of P3R2-4; the sentence before it, "Write `no PR` only for a phase that opened no PR", is the guard).
- Suggested fix: bring the header in line; in the template say "another repo's PR" in place of "another PR".

## Line walk: `ci_check`, `ci_prs`, `ci_head`, `ci_wait`, `ci_runs`, `cp_plan_rows`

errexit and pipefail are in force for all of it: `bin/blast-off:39` sets `-euo pipefail`, and `chain_run` and `ci_wait` are called as plain commands from the `case` at the end of `bin/blast-off`, never inside a condition.

| Line | Construct | A failing tool or empty output becomes |
|---|---|---|
| ci.sh:18 | `sha="$(gh pr view | jq)" || die` | exit 1 (pipefail carries gh's failure); empty output: exit 1 at :19 (probe I1) |
| ci.sh:20, :30 | `new="$(ci_runs)" || die` | exit 1; a gh that prints nothing with exit 0 gives `absent`, exit 10 (probe I2; real gh prints `[]`) |
| ci.sh:21 | `[ "$i" -lt "${BLAST_OFF_CI_APPEAR:-60}" ]` | non-number: wait skipped, SFH-10 |
| ci.sh:26 | `timeout ... gh run watch > /dev/null 2>&1 || [ $? -ne 124 ] || log` | any watch failure but a timeout is silent; the run is then read as it stands, so not green unless it finished green |
| ci.sh:36 | `for ...; gh run view || die; done | jq -s > "$r.tmp"` | exit 1, old record kept, SFH-7 |
| ci.sh:44-46 | `v="$(jq -r .verdict "$r")"; [ "$v" = success ] || exit 10` | jq failure: exit by errexit, not 0 |
| ci.sh:53-54 | `gh run list | jq` | pipefail returns gh's failure to the callers above |
| ci.sh:70, :81 | `while IFS='|' read -r k cell; ... done < <(cp_done_cells)` | status of sed and awk lost; empty: refused at :82; cut short: SFH-11 |
| ci.sh:71, :83 | `n="$(ci_prs <<< ...)"` | sed, sort or paste failing: errexit, runner exit 1 (no state) |
| ci.sh:72 | `[[ ! $(sed -E ...Ig) =~ $stray ]]` | sed failing: stray check off, SFH-11 |
| ci.sh:74 | `command grep -qiE ... <<< "$cell"` | grep error reads as "does not say no PR": the row then needs a PR, refused otherwise |
| ci.sh:86 | `v="$(jq ... 2>/dev/null || true)"` | missing, empty or malformed record: `v` empty, "unread", exit 10 (probes C1, C2, C7, C8) |
| ci.sh:89 | `h="$(jq -r .head_sha ...)"` | errexit on failure; runs after `ci_head` has matched it against gh |
| ci.sh:91 | `[ -n "$TOP" ]` | no repo: refused (41:128; probe I6 with the runner's cwd inside another repo that holds the head: still refused) |
| ci.sh:92 | `wf="$(git ls-tree ... 2>/dev/null)" || chain_end 10` | any git failure: refused; `wf` is not declared on this line, so `local` does not mask the status |
| ci.sh:104 | `{ grep -aoiE ... || true; } | sed | sort -un | paste` | grep exit 1 or 2: empty list, see :74; the others: errexit |
| ci.sh:112 | `h="$(jq -r '.head_sha // ""' ...)"` | errexit |
| ci.sh:113 | `cur="$(cd && timeout gh pr view | jq)" || cur=` | gh failing, timing out or printing nothing: `cur` empty, refused at :114 (41:124, 41:139; probes C9, C12) |
| ci.sh:114 | `[ -n "$cur" ] && [ "$cur" = "$h" ] || chain_end 10` | the `-n` guard is what stops "both empty"; no test pins it (mutant S3) |
| checkpoint.sh:43-46 | `sed -n ... | awk` | a missing file: no output, so "no done row" at `done`; rows outside the grammar: SFH-1 |
| chain.sh:6 | `chain_end() { CHAIN_END=1; log "$2"; exit "$1"; }` | a failing `tee` in `log` ends the runner by errexit with tee's status before `exit 0`: never `job done` |

## Mutants I ran (the coordinator's and the fixer's are not repeated)

Each is one exact string replaced in the copy, checked by a diff against a read-only pristine copy before the run and restored after (diff empty). Baseline run 1 on the unmodified copy: `PASS 41-ci-wait`.

| Mutant | File:line | Result | First failing assertion | Note |
|---|---|---|---|---|
| M1 the `.pr == $n` record check removed | lib/ci.sh:86 | killed | 41:115 `PR 8's record for PR 9: exit 0` | by exit code; the grep on that line is already satisfied |
| M2 `ci_head` dropped on the success path | lib/ci.sh:88 | killed | 41:121 `green record of an old head: exit 10` | by message only |
| M3 `[ -n "$TOP" ]` replaced by `:` | lib/ci.sh:91 | killed | 41:128 `absent record outside git: exit 10` | by message only (git then fails in the scenario's cwd, which is in no repo) |
| M6 `-r` dropped from `ls-tree` | lib/ci.sh:92 | killed | 41:237 `absent CI, workflow file at the PR's head: exit 10` | by message only (`(.github/workflows)` in place of the file name); same gate outcome |
| M7 `tolower` dropped in `cp_plan_rows` | lib/checkpoint.sh:45 | killed | 40:182 `Done row 2.5: exit 9` | by message only; run against 40-receipt-required |
| M33 `git -C "$WORKDIR"` in place of `"$TOP"` | lib/ci.sh:92 | killed | 41:243 `workdir a subdirectory of the repo: exit 0` | by exit code |
| M38 the table range never ends (`/^## NEVER/`) | lib/checkpoint.sh:43 | killed | 41:131 `green records: exit 10` (`PRs read: 7 9 97`) | by exit code |
| S1 `sort -un` replaced by `cat` | lib/ci.sh:104 | survived | none | probe E1 prints `[10 7 9 9 12 7]`; same gate outcome, repeated gh calls and log order only |
| S2 `-a` dropped from `ci_prs`' grep | lib/ci.sh:104 | survived | none | no probe differs; in the bundle run the scenario's NUL job still logged `PRs read: 7` and exit 10 without `-a`; probe E2: on this machine (GNU grep 3.11, `C.UTF-8`) grep prints the match on a `\377` byte without `-a` too. bash drops NUL bytes from `$cell` before grep sees them, so I could not find an input where `-a` changes the outcome here |
| S3 `[ -n "$cur" ] &&` dropped in `ci_head` | lib/ci.sh:114 | survived | none | coverage gap: probe C4 (record with no `head_sha`, gh failing) goes from exit 10 to exit 0 |
| S4 `^{commit}` dropped | lib/ci.sh:92 | survived | none | coverage gap: probe D6 (a tree sha) is then read as a tree; not reachable with a real gh |
| S5 `no PR` matched with no word boundary | lib/ci.sh:74 | survived | none | coverage gap: probe B8 (`no PRs`) goes from exit 10 to exit 0 |

S1 to S5 ran as one bundle (run 9, `PASS 41-ci-wait`): none of the five is killed in the presence of the other four. I did not run each alone.

`fin` in the fake: none of my six scenarios reaches its table-append branch (41's `fin` and `wf` jobs, 21, 32 and 40 write their own table before a child runs; 21's `bad-*` jobs exit 1 before any child), so I answered that lead by reading. `fin` adds a one-row `done (<sha>) · no PR` table and, in a git workdir, a hand-made PASS receipt. The assertions it could mask have their own cases: a job with no table refused at `done` is 41:160-162 (status set by the test, mode `noop`); the hard cap, exit 4, is 10-chain-done:71-76 with mode `step`, and the cap is fixed before any child runs; receipts are 40, whose jobs all carry a table. I found nothing masked.

## Tests for the acceptance criteria: are they real

| Criterion | Assertion | Mutant that kills it |
|---|---|---|
| 1 absent, workflow file at the head: exit 10 | 41:237 (and :243, :248) | coordinator: absent+workflow refusal dropped; mine: M33 at :243 |
| 2 absent, no workflow file at the head: allowed, logged | 41:228-229, :233-234 | coordinator: absent pass not logged; fixer: HEAD in place of the record head |
| 3 PRs only from Status cells; neither token refused | 41:132, :162, :171, :180, :184, :190, :194 | fixer: neither-refusal dropped, whole-file read, no-done-row refusal dropped; mine: M38 at :131 |
| 4 `workflow_dispatch` does not count either way | 41:77, :79, :80 (ci-wait); 41:225 with :228 and :237 (at done) | coordinator: dispatch filter dropped |
| 5 tests and texts | templates: 51:74-88; README, spec, skill: no test | see SFH-12 |

## Round-2 HIGH status

- P3R2-1: reshaped. For rows the parser reads it is resolved (41:177-180, 41:192-194). For rows it does not read, one readable row still lets a done row with a red PR, or with neither token, through: SFH-1, probes A1 to A4, A10, A13.
- P3R2-2: resolved. Nothing outside done rows' Status cells is read (41:187-190; M38 killed at 41:131 shows the section end is enforced).
- P3R2-3: resolved for a head with no workflow file (41:230-234, `passes` with a workflow file at HEAD only). A head whose workflow cannot start on the PR stays refused by ruling 2; the missing owner procedure is SFH-3.
- P3R2-4: resolved in the text (templates/checkpoint.md:30-32, pinned at 51:75-82). What is left is the "name another PR in prose" sentence, SFH-14.

## Acceptance criteria

1. Met. 41:237: exit 10, `PR #17 CI absent: no runs, but its head <sha> has a workflow file (.github/workflows/release.yaml)`.
2. Met in the runner (41:228-229). Met in part for the child's path to it: the brief has no step for this case (SFH-2).
3. Met in part. Prose and other cells are never read (41:132, :162, :190) and a readable done row with neither token is refused (41:171). A done row the parser does not read is neither read nor refused (SFH-1).
4. Met. 41:77, :79, :80.
5. Met in part. Tests for 1 to 4 are in 41 and real; template text is pinned in 51; the README, spec and skill state the rules (read: README.md:114-119 and :134, docs/spec.md:35 and :97, skills/blast-off/SKILL.md:34-37) but no test pins them, and three texts have gaps (SFH-2, SFH-3, SFH-4).

## New dependencies or reliance

- `git ls-tree -r --name-only <sha>^{commit} -- <path>` in the workdir's repo, and the PR's head commit being in that repo's object store (a shallow or other clone without it is refused: probe D8, `fatal: Not a valid object name`, rc 128).
- `TOP` from `chain_run` is now read by `ci_check`.
- `gh run list --json databaseId,event`: the `event` field.
- GNU sed's `I` flag on `s` (lib/ci.sh:72; GNU sed was already needed, lib/checkpoint.sh:21); `paste -sd' '`; `grep -a`.
- A GitHub rule taken as given: with no file under `.github/workflows` at the PR's head, no run was due. From recall, `pull_request` workflows are read from the PR's merge commit, so a base that gained a workflow after the branch was cut can make a run due on a head that has none; the brief's "merge the base in before the gate" keeps a template-following job out of that case.
- Only GitHub Actions runs are read; commit statuses from other CI are not (SFH-13).

## Runs

| # | Copy | Scenario | What | Scenario line |
|---|---|---|---|---|
| 1 | HEAD copy | 41-ci-wait | unmodified baseline | PASS |
| 2 | HEAD copy | 41-ci-wait | probes D, A, B, H, C, G, E appended | PASS |
| 3 | phase-2 tree | 41-ci-wait | setup lines of 41 plus probes A, B, H only | PASS |
| 4 | HEAD copy | 41-ci-wait | M1 | FAIL |
| 5 | HEAD copy | 41-ci-wait | M2 | FAIL |
| 6 | HEAD copy | 41-ci-wait | M3 | FAIL |
| 7 | HEAD copy | 41-ci-wait | M6 | FAIL |
| 8 | HEAD copy | 40-receipt-required | M7 | FAIL |
| 9 | HEAD copy | 41-ci-wait | S1 to S5 bundled | PASS |
| 10 | HEAD copy | 41-ci-wait | M33 | FAIL |
| 11 | HEAD copy | 41-ci-wait | M38 | FAIL |
| 12 | HEAD copy | 41-ci-wait | all probes plus I | PASS |

One attempt before run 1 printed `NOT STARTED` and ran nothing: the `pgrep` matched my own shell, whose command line held the runner's path. From then on the checks and the run sat in a helper script (`go.sh`).

Before each run: `grep -c install_units <copy>/tests/<name>.sh` printed 0 and `pgrep -af '[t]ests/ru[n]'` printed nothing. Runs with probes appended show `FAIL shellcheck` for the copy (my probe lines); the scenario line above is the verdict. The temp dir `/tmp/p3r3-sfh.EaN615` is left in place with the probe files (`probes-*.sh`), kept work dirs (`keep/`) and mutant specs (`m/`).

## Probe output, HEAD (run 12; groups D to E are line for line the same as run 2 once shas, temp paths and times are masked)

Each probe is a job already at `status: done` (the `done_job` helper), or the scenario's `wf` job for group D. Lines are cut at 250 characters; temp paths are shortened.

```
== D: odd trees at the PR's head; PR 17's record is absent, written by hand for each head ==
PROBE D0 control: no workflows dir at head     exit 0  | CI at done: PRs read: 17; rows that say no PR: none | last: job done
PROBE D1 .github/workflows is a file           exit 10 | CI at done: PRs read: 17; rows that say no PR: none | last: PR #17 CI absent: no runs, but its head 963a277 has a workflow file (.github/workflows); push to the PR branch for a run that is not 
PROBE D2 .github/workflows is a symlink        exit 10 | CI at done: PRs read: 17; rows that say no PR: none | last: PR #17 CI absent: no runs, but its head b516eb3 has a workflow file (.github/workflows); push to the PR branch for a run that is not 
PROBE D3 only README.md under workflows        exit 10 | CI at done: PRs read: 17; rows that say no PR: none | last: PR #17 CI absent: no runs, but its head a14485d has a workflow file (.github/workflows/README.md); push to the PR branch for a run th
PROBE D4 only workflows/sub/x.yml              exit 10 | CI at done: PRs read: 17; rows that say no PR: none | last: PR #17 CI absent: no runs, but its head f07874b has a workflow file (.github/workflows/sub/x.yml); push to the PR branch for a run th
PROBE D5 head_sha and gh head are the word HEAD (HEAD has sub/x.yml) exit 10 | CI at done: PRs read: 17; rows that say no PR: none | last: PR #17 CI absent: no runs, but its head HEAD has a workflow file (.github/workflows/sub/x.yml); push to the PR 
PROBE D6 head is a tree sha (of the commit with release.yaml) exit 10 | CI at done: PRs read: 17; rows that say no PR: none | last: PR #17 CI absent: no runs, and its head 37c62d93651f253db3018752e9ae396bf6dd36d1 is no commit git can read in test-254
PROBE D7 head is a 12-char short sha of that commit exit 10 | CI at done: PRs read: 17; rows that say no PR: none | last: PR #17 CI absent: no runs, but its head 07a8e8b has a workflow file (.github/workflows/release.yaml); push to the PR branch for 
D8 shallow clone (depth 1), ls-tree of an older commit: [fatal: Not a valid object name 07a8e8be77afd9db2f26942f550a6c722a5d66b7^{commit}] rc=128
D9 git status of the fixture repo after the probes: [?? job/ ]
== A: rows the parser may not see, beside a readable no-PR row; PR 7's record is red ==
PROBE A0 control: readable row, red PR 7       exit 10 | CI at done: PRs read: 7; rows that say no PR: 0 | last: PR #7 CI red or unfinished at 1111111111111111111111111111111111111111 (gate-logs/ci-pr-7.json); fix and push if red, then blast-off ci-w
PROBE A1 key P1                                exit 0  | CI at done: PRs read: none; rows that say no PR: 0 | last: job done
PROBE A2 bold key                              exit 0  | CI at done: PRs read: none; rows that say no PR: 0 | last: job done
PROBE A3 indented row                          exit 0  | CI at done: PRs read: none; rows that say no PR: 0 | last: job done
PROBE A4 second Phase plan heading             exit 0  | CI at done: PRs read: none; rows that say no PR: 0 | last: job done
PROBE A5 extra cell after Status               exit 0  | CI at done: PRs read: none; rows that say no PR: 0 1 | last: job done
PROBE A6 no trailing pipe                      exit 9  |  | last: status done but phase row 1 is not done; close it (run the gate on HEAD into gate-logs/phase-1.log, blast-off receipt <job-dir> 1, then a Status cell of done and HEAD's commit, replaci
PROBE A7 open rows with unread keys            exit 0  | CI at done: PRs read: none; rows that say no PR: 0 | last: job done
PROBE A8 bold done                             exit 9  |  | last: status done but phase row 1 is not done; close it (run the gate on HEAD into gate-logs/phase-1.log, blast-off receipt <job-dir> 1, then a Status cell of done and HEAD's commit, replaci
PROBE A9 key 1)                                exit 9  |  | last: status done but phase row 1) is not done; close it (run the gate on HEAD into gate-logs/phase-1).log, blast-off receipt <job-dir> 1), then a Status cell of done and HEAD's commit, repl
PROBE A10 tab before key                       exit 0  | CI at done: PRs read: none; rows that say no PR: 0 | last: job done
PROBE A11 escaped pipe in Status               exit 9  |  | last: status done but phase row 1 is not done; close it (run the gate on HEAD into gate-logs/phase-1.log, blast-off receipt <job-dir> 1, then a Status cell of done and HEAD's commit, replaci
PROBE A12 empty cell after Status              exit 9  |  | last: status done but phase row 1 is not done; close it (run the gate on HEAD into gate-logs/phase-1.log, blast-off receipt <job-dir> 1, then a Status cell of done and HEAD's commit, replaci
PROBE A13 keys 'Phase 1' and R1                exit 0  | CI at done: PRs read: none; rows that say no PR: 0 | last: job done
== B: no PR beside a PR written a way the stray check does not know; PR 7's record is red ==
PROBE B1 'no PR · PR 7'                       exit 0  | CI at done: PRs read: none; rows that say no PR: 0 | last: job done
PROBE B2 'no PR (pull 7)'                      exit 0  | CI at done: PRs read: none; rows that say no PR: 0 | last: job done
PROBE B3 'no PR · see pull/7'                 exit 0  | CI at done: PRs read: none; rows that say no PR: 0 | last: job done
PROBE B4 'no PR · PR #0'                      exit 0  | CI at done: PRs read: none; rows that say no PR: 0 | last: job done
PROBE B5 'no PR · GH-7'                       exit 0  | CI at done: PRs read: none; rows that say no PR: 0 | last: job done
PROBE B6 'PR 7 · no PR yet'                   exit 0  | CI at done: PRs read: none; rows that say no PR: 0 | last: job done
PROBE B7 'no PR · PR # 7'                     exit 0  | CI at done: PRs read: none; rows that say no PR: 0 | last: job done
PROBE B8 'no PRs'                              exit 10 |  | last: phase row 0 is done but its Status cell says neither `PR #<n>` nor `no PR`: after the sha write `PR #<n>` (the phase's own PR) or `no PR` (the phase opened none), then run again; done 
PROBE B9 'NO  PR'                              exit 10 |  | last: phase row 0 is done but its Status cell says neither `PR #<n>` nor `no PR`: after the sha write `PR #<n>` (the phase's own PR) or `no PR` (the phase opened none), then run again; done 
PROBE B10 'no-PR'                              exit 10 |  | last: phase row 0 is done but its Status cell says neither `PR #<n>` nor `no PR`: after the sha write `PR #<n>` (the phase's own PR) or `no PR` (the phase opened none), then run again; done 
PROBE B11 'none'                               exit 10 |  | last: phase row 0 is done but its Status cell says neither `PR #<n>` nor `no PR`: after the sha write `PR #<n>` (the phase's own PR) or `no PR` (the phase opened none), then run again; done 
PROBE B12 'PR #7 · NO pr'                     exit 10 |  | last: phase row 0 Status cell says `no PR` and names PR #7: keep the one that is true, then run again; done refused, status unchanged
PROBE B13 'no PR'                              exit 0  | CI at done: PRs read: none; rows that say no PR: 0 | last: job done
== H: a row closed the pre-change way (no token), status done ==
PROBE H1 old-shape done row                    exit 10 |  | last: phase row 0 is done but its Status cell says neither `PR #<n>` nor `no PR`: after the sha write `PR #<n>` (the phase's own PR) or `no PR` (the phase opened none), then run again; done 
H1 child launched after the refusal: no; status line: status: done
== C: record shapes for PR 8 (gh says head 2222222222222222222222222222222222222222) ==
PROBE C0 control: green record                 exit 0  | CI at done: PRs read: 8; rows that say no PR: none | last: job done
PROBE C1 pr is a string                        exit 10 | CI at done: PRs read: 8; rows that say no PR: none | last: PR #8 CI unread: no readable record for PR 8 in gate-logs/ci-pr-8.json; blast-off ci-wait <job-dir> 8, then run again
PROBE C2 two values: success, failure          exit 10 | CI at done: PRs read: 8; rows that say no PR: none | last: PR #8 CI unread: no readable record for PR 8 in gate-logs/ci-pr-8.json; blast-off ci-wait <job-dir> 8, then run again
PROBE C3 two values: success, PR 9 failure     exit 0  | CI at done: PRs read: 8; rows that say no PR: none | last: job done
PROBE C4 no head_sha, gh pr view fails         exit 10 | CI at done: PRs read: 8; rows that say no PR: none | last: PR #8 CI unread for head unknown (gh pr view 8 failed): gate-logs/ci-pr-8.json is of ''; blast-off ci-wait <job-dir> 8, then run again
PROBE C5 verdict success over a failed run     exit 0  | CI at done: PRs read: 8; rows that say no PR: none | last: job done
PROBE C6 pr 8.0                                exit 0  | CI at done: PRs read: 8; rows that say no PR: none | last: job done
PROBE C7 empty record file                     exit 10 | CI at done: PRs read: 8; rows that say no PR: none | last: PR #8 CI unread: no readable record for PR 8 in gate-logs/ci-pr-8.json; blast-off ci-wait <job-dir> 8, then run again
PROBE C8 verdict skipped                       exit 10 | CI at done: PRs read: 8; rows that say no PR: none | last: PR #8 CI unread: no readable record for PR 8 in gate-logs/ci-pr-8.json; blast-off ci-wait <job-dir> 8, then run again
PROBE C9 gh pr view prints nothing, exit 0     exit 10 | CI at done: PRs read: 8; rows that say no PR: none | last: PR #8 CI unread for head unknown (gh pr view 8 failed): gate-logs/ci-pr-8.json is of '2222222222222222222222222222222222222222'; blast
PROBE C10 gh pr view headRefOid null           exit 10 | CI at done: PRs read: 8; rows that say no PR: none | last: PR #8 CI unread for head null: gate-logs/ci-pr-8.json is of '2222222222222222222222222222222222222222'; blast-off ci-wait <job-dir> 8,
PROBE C11 same, record head_sha "null"         exit 0  | CI at done: PRs read: 8; rows that say no PR: none | last: job done
PROBE C12 gh prints the head, exits 1          exit 10 | CI at done: PRs read: 8; rows that say no PR: none | last: PR #8 CI unread for head unknown (gh pr view 8 failed): gate-logs/ci-pr-8.json is of '2222222222222222222222222222222222222222'; blast
== G: ci-wait when gh run view fails for one run, an older green record of the same head in place ==
G1 ci-wait exit 1 | output: cat: gh/run-92: No such file or directory blast-off: gh run view 92 failed  | record now: {"utc":"old","verdict":"success"} | files: ci-pr-18.json ci-pr-18.json.tmp  | tmp: {"verdict":"success","runs":[91]}
PROBE G2 done with that older record           exit 0  | CI at done: PRs read: 18; rows that say no PR: none | last: job done
G3 what ci-wait prints on absent (PR 9, from the scenario): [2026-11-16T08:36:39Z ci PR #9 at 3333333333333333333333333333333333333333: absent () ]
== E: function level ==
E1 ci_prs mixed: [7 9 10 12]
E2 ci_prs on a bad byte: [7] ; the same grep without -a: [PR #7]
E3 no-PR grep (no -a) on a bad byte: rc=0
E4 locale: LANG=C.UTF-8 LC_ALL=
== I: ci-wait edges and the no-repo guard ==
I1 ci-wait, gh prints nothing and exits 0: exit 1 | blast-off: gh pr view 8 gave head '', not a commit sha | record: 
I2 ci-wait, gh run list prints nothing and exits 0: exit 10 | 2026-11-16T08:37:01Z ci PR #8 at 2222222222222222222222222222222222222222: absent () | record: {"verdict":"absent","runs":[]}
I3 ci-wait, a red run listed only from the third list on: exit 0 | record: {"verdict":"success","runs":[95]} | run lists made: 2
I4 ci-wait with BLAST_OFF_CI_APPEAR=60s: exit 10 after 0 s | /tmp/p3r3-sfh.EaN615/copy/lib/ci.sh: line 21: [: 60s: integer expression expected | record: {"verdict":"absent","runs":[]}
I5 ci-wait with BLAST_OFF_CI_WATCH=abc on the hanging run 51: exit 10 after 0 s | out: 2026-11-16T08:37:01Z ci PR #13 at 8888888888888888888888888888888888888888: failure (ci-51 )  | watch calls for 51: 1
I6 absent record, workdir in no repo, cwd inside a repo that has the head: exit 10 | last: PR #19 CI absent: no runs, and the workdir is in no git repo, so whether runs were due at the PR's head c50887531f017ca600b605acd35542f57b860bfd cannot be read
PROBE I7 one PR named three times in two rows  exit 0  | CI at done: PRs read: 8; rows that say no PR: none | last: job done
```

## Probe output, phase-2 tree (run 3)

```
== A: rows the parser may not see, beside a readable no-PR row; PR 7's record is red ==
PROBE A0 control: readable row, red PR 7       exit 10 |  | last: PR #7 CI red or unfinished at 1111111111111111111111111111111111111111 (gate-logs/ci-pr-7.json); fix and
PROBE A1 key P1                                exit 10 |  | last: PR #7 CI red or unfinished at 1111111111111111111111111111111111111111 (gate-logs/ci-pr-7.json); fix and
PROBE A2 bold key                              exit 10 |  | last: PR #7 CI red or unfinished at 1111111111111111111111111111111111111111 (gate-logs/ci-pr-7.json); fix and
PROBE A3 indented row                          exit 10 |  | last: PR #7 CI red or unfinished at 1111111111111111111111111111111111111111 (gate-logs/ci-pr-7.json); fix and
PROBE A4 second Phase plan heading             exit 10 |  | last: PR #7 CI red or unfinished at 1111111111111111111111111111111111111111 (gate-logs/ci-pr-7.json); fix and
PROBE A5 extra cell after Status               exit 10 |  | last: PR #7 CI red or unfinished at 1111111111111111111111111111111111111111 (gate-logs/ci-pr-7.json); fix and
PROBE A6 no trailing pipe                      exit 9  |  | last: status done but phase row 1 is not done; close it (run the gate on HEAD into gate-logs/phase-1.log, blas
PROBE A7 open rows with unread keys            exit 0  |  | last: job done
PROBE A8 bold done                             exit 9  |  | last: status done but phase row 1 is not done; close it (run the gate on HEAD into gate-logs/phase-1.log, blas
PROBE A9 key 1)                                exit 9  |  | last: status done but phase row 1) is not done; close it (run the gate on HEAD into gate-logs/phase-1).log, bl
PROBE A10 tab before key                       exit 10 |  | last: PR #7 CI red or unfinished at 1111111111111111111111111111111111111111 (gate-logs/ci-pr-7.json); fix and
PROBE A11 escaped pipe in Status               exit 9  |  | last: status done but phase row 1 is not done; close it (run the gate on HEAD into gate-logs/phase-1.log, blas
PROBE A12 empty cell after Status              exit 9  |  | last: status done but phase row 1 is not done; close it (run the gate on HEAD into gate-logs/phase-1.log, blas
PROBE A13 keys 'Phase 1' and R1                exit 10 |  | last: PR #7 CI red or unfinished at 1111111111111111111111111111111111111111 (gate-logs/ci-pr-7.json); fix and
== B: no PR beside a PR written a way the stray check does not know; PR 7's record is red ==
PROBE B1 'no PR · PR 7'                       exit 0  |  | last: job done
PROBE B2 'no PR (pull 7)'                      exit 0  |  | last: job done
PROBE B3 'no PR · see pull/7'                 exit 0  |  | last: job done
PROBE B4 'no PR · PR #0'                      exit 0  |  | last: job done
PROBE B5 'no PR · GH-7'                       exit 0  |  | last: job done
PROBE B6 'PR 7 · no PR yet'                   exit 0  |  | last: job done
PROBE B7 'no PR · PR # 7'                     exit 0  |  | last: job done
PROBE B8 'no PRs'                              exit 0  |  | last: job done
PROBE B9 'NO  PR'                              exit 0  |  | last: job done
PROBE B10 'no-PR'                              exit 0  |  | last: job done
PROBE B11 'none'                               exit 0  |  | last: job done
PROBE B12 'PR #7 · NO pr'                     exit 10 |  | last: PR #7 CI red or unfinished at 1111111111111111111111111111111111111111 (gate-logs/ci-pr-7.json); fix and
PROBE B13 'no PR'                              exit 0  |  | last: job done
== H: a row closed the pre-change way (no token), status done ==
PROBE H1 old-shape done row                    exit 0  |  | last: job done
H1 child launched after the refusal: no; status line: status: done
```

## What the survivor bundle changed in the probes (run 9 against run 2)

```
D6 tree sha:  HEAD 'is no commit git can read'  ->  bundle 'has a workflow file (.github/workflows/release.yaml)'
B8 'no PRs':  HEAD exit 10 (neither)        ->  bundle exit 0, rows that say no PR: 0
C4 no head_sha, gh pr view fails: HEAD exit 10 ->  bundle exit 0, job done
E1 ci_prs mixed: HEAD [7 9 10 12]            ->  bundle [10 7 9 9 12 7]
```
