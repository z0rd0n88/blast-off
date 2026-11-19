# security-reviewer review: phase 3 round 2

Lens: the trust boundary. `checkpoint.md` and `gate-logs/ci-pr-N.json` are written by the agent the gate
holds; `run.log` is read by the owner. Method: read `lib/ci.sh` (HEAD and `feat/br-1115-issues/phase-2`),
`lib/chain.sh`, `lib/checkpoint.sh`, `lib/receipt.sh`, `bin/blast-off`, the diff of docs, template, test 41
and `tests/fakes/gh`; ran scratch scripts that source `lib/ci.sh` with stubs in my own temp dir
(`.../scratchpad/secrev.D6j176/probe2.sh`, `probe3.sh`, `probe4.sh`); ran `shellcheck -S warning` and
`bash -n` on `lib/ci.sh` and `tests/fakes/gh` (both clean); ran read-only `gh run list --help`,
`gh run list --limit 8 --json databaseId,event,...` and `gh issue view 26`. No `tests/run`, no git or gh
write. Tools: GNU grep 3.11, jq 1.7, gawk 5.2.1, gh 2.101.0, `LANG=C.UTF-8`.

Baseline that frames every severity below: a gate-avoiding agent with the owner's uid can already write
`ci-pr-N.json` and `run.log` by hand, or name its PR with no `#` (P3R1-40 and the template's own
`other PR <n>` rule). That was true in phase 2 and is true now. So the gate's real work is holding an
honest-but-sloppy or stuck agent, and telling the owner the truth in `run.log`. Findings are graded on that.

Injection result, stated once: the values this diff newly moves are safe. `$pr`, `$prs`, `$all`, `$other`
come out of `ci_prs` as `[1-9][0-9]*` and spaces only (grep -o of `PR ?#[0-9]+|/pull/[0-9]+`, then
`sed 's/.*[#/]//; s/^0*//'`), so `jq --argjson n`, the path `gate-logs/ci-pr-$pr.json`, `gh pr view "$1"`
and the new log lines cannot take an option, a `../`, a quote or a newline from the checkpoint (RAN: 20-odd
checkpoint shapes; a 23-digit number is read as a number and refused as unread). The workflow path in the
refusal is the first line of `git ls-tree --name-only`, which C-quotes control characters, `"` and `\`
whatever `core.quotePath` says (git-config(1), read), so it cannot add a line or an escape sequence;
with `core.quotePath=false` in the agent-held repo config raw bytes above 0x80 pass (bidi or look-alike
characters only).

Two questions from my prompt with a plain answer. Can a record for one PR stand in for another? Not a
machine-written one: the file name and `.pr` must both be N (RAN `r_strpr`, `r_array`, `r_multi`, `big`:
all unread, rc 10) and its `head_sha` must be PR N's head now; the exceptions are SEC-5 (any PR of the
repo satisfies the gate) and SEC-11 (no repository identity). Is there a path from `status: done` to exit 0
that skips `ci_check`? None found: `chain_end 0` appears once, at `lib/chain.sh:159`, after `ci_check`
(RAN grep over `lib` and `bin`), and `chain_run` is called outside any `||` or `if`, so errexit is on.

## Findings

### SEC-1 | HIGH | lib/ci.sh:71-73 | One PR token in any Status cell switches off the read of every other PR the checkpoint names; a red record then passes with exit 0
- Failure path: row 0 `done (abc1234) · PR #7` (green record), row 1 `done (abc1234)` with its PR only
  under "Completed phases" as `PR #8` (the template's own line 49 shape), `ci-pr-8.json` verdict `failure`.
  `ci_check` logs `...Status cells name: 7; named elsewhere in checkpoint.md and not read: 8`, then
  `job done`, exit 0. Phase 2 read 7 and 8 and refused with exit 10. The same holds when PR 8 has no
  record at all (REASONED: PR 8 never enters the loop at line 80). An agent whose `ci-wait 8` just exited 10 and who closes the row without the token gets
  there by accident; a gate-avoiding one can put any green PR of the repo in one cell as a decoy.
- Evidence: RAN `probe.sh` case `mixed` (second run) and my `decoy` case with errexit on: `[phase-2 rule
  would read: 1 8]`, `LOG: CI read for the PRs Phase plan Status cells name: 1; named elsewhere in
  checkpoint.md and not read: 8`, `=> DONE PASSES (exit 0)`.
- New in this diff (b9c39ad narrowed the read; ecc6e90 added the log line and kept exit 0). Round-1 P3R1-2,
  reshaped. It is the default of owner question 4.
- Suggested fix: when any digit-keyed row's Status cell names no PR, read the union (`prs` plus `all`), and
  log which rows had no token. Criterion 3 still holds for a table where every row names its PR.

### SEC-2 | MEDIUM | templates/checkpoint.md:29-32 | The rule comment the held agent reads first every session now states which edit takes a PR out of the gate
- Failure path: "A row closed without one gets no CI check, and a PR named only outside the Status cells is
  not read" plus "Name any other PR ... as `other PR <n>`, no '#'". An agent stuck at exit 10 (red CI, or
  the absent case of SEC-4) reads the exact edit that ends the refusal: drop the token from that row and
  leave another row's in place (SEC-1), or write every one as `PR 7`. The file is headed "Rules the runner
  enforces", and `tests/51-templates.sh:74-75` now pins the two sentences. `README.md:115-117` and
  `docs/spec.md:97` say the same to the owner, which is fine; the problem is the copy addressed to the agent.
- Evidence: REASONED from `templates/checkpoint.md:29-32`, `tests/51-templates.sh:73-76`, and the RAN results
  of SEC-1 and `x_hint_followed` (`LOG: no PR named in checkpoint.md; CI not read`, exit 0).
- New in the fix commit (P3R1-5 asked for this wording before the fallback existed). It stands or falls
  with SEC-1: if SEC-1 is fixed the sentence becomes false and must go.
- Grade: MEDIUM, not HIGH. The sentence is accurate and describes; it does not instruct, so the rubric's
  "instruction text that tells an agent to do the wrong thing" does not fit. The fail-open it points at is
  SEC-1, which carries the HIGH. Of the changed docs only this copy describes a bypass to the agent:
  `skills/blast-off/SKILL.md` step 4, `README.md` and `bin/blast-off` do not.
- Suggested fix: tell the agent only the duty and claim no more than the code does, for example "Every done
  row's Status cell names its PR as `PR #<n>`: at done the runner wants a CI record for each PR named
  (exit 10)". Keep the read rules in `docs/spec.md`. `tests/51-templates.sh:74-75` pins the two sentences,
  so that test changes in the same commit.

### SEC-3 | HIGH | lib/ci.sh:74-76, 87, 89-90 | With no PR in any Status cell, another repo's PR link is still read as this repo's PR, the hint offers no way out for a URL, and the refusal sends the agent to this repo's PR of that number
- Failure path: a job with no PR of its own (or whose cells say `PR 7`) and prose
  `https://github.com/o/other/pull/99`. Log: `no Phase plan Status cell names a PR; CI read for every PR
  checkpoint.md names instead: 99 (name this job's PR in its row's Status cell; write any other PR with no
  '#')`, then `PR #99 CI unread ... blast-off ci-wait <job-dir> 99, then run again`. The URL has no `#`, so
  the hint cannot be followed as written. Following the refusal runs `gh pr view 99` in the workdir: no
  such PR, `die`, and the loop is issue 26's "blocks done forever"; or an unrelated PR 99 of this repo
  exists, and then (a) green: done passes on an unrelated PR's CI while the job's own `PR 7` is never read,
  and run.log shows a CI read; (b) red: "fix and push if red"; (c) absent with a workflow at HEAD: "push to
  the PR branch", which is new text in this diff and points at someone else's branch. The only real way
  out is to break the link text (`o/other pull 99`), which nothing says.
- Evidence: RAN `xrepo_link_nopr` (refused, message as quoted), `x_own_nohash` (record for this repo's 99
  green: `=> DONE PASSES (exit 0)`, PR 7 unread), `x_status` (same link inside a Status cell: read as 99,
  passes on this repo's record). REASONED for the three `ci-wait 99` outcomes from `lib/ci.sh:18,87,89`.
- Pre-existing for the read itself (phase 2 read it too); new in the fix commit for the hint; new in this
  diff for the "push to the PR branch" instruction. Acceptance criterion 3 ("another repo's PR mentioned in
  prose is ignored") holds only when some Status cell names a PR. Direction is fail-closed first, then
  misdirecting; owner question 1. Graded HIGH on two rubric clauses: an acceptance criterion not met for a
  realistic class of checkpoint, and instruction text (the refusal line) that tells the agent to run
  `ci-wait`, and then to push, against a PR that is not the job's.
- Suggested fix: in the fallback read only `PR #N` tokens and `/pull/N` links whose `owner/repo` is absent or
  matches the workdir's remote; make the hint say "write another repo's PR as `other PR <n>` and its link
  without `/pull/<n>`"; and see SEC-5 for a check that makes a wrong-PR read fail closed.

### SEC-4 | MEDIUM | lib/ci.sh:87 (README.md:132, docs/spec.md:97) | The absent refusal names a remedy that cannot work in several real cases, with no owner-held override, so the only exits are the SEC-2 edit or a hand-edited record
- Failure path: a `pull_request` workflow is taken from the PR's merge ref. An earlier stacked PR whose
  branch and base have no workflow file never gets a run however often it is pushed, yet a workflow added
  in a later phase makes HEAD "have a workflow file". Same for `branches: [main]` with a stacked base, a
  `paths:` filter the PR does not touch, a PR with a merge conflict, a dispatch-only workflow, or
  `.github/workflows/README.md`. The message says "push to the PR branch for a run that is not a
  workflow_dispatch"; the agent pushes, re-runs `ci-wait`, gets absent again. A dispatch, the one thing
  that would run CI on such a branch, no longer counts. What then reaches `done`: drop the token (SEC-1,
  SEC-2), or set `"verdict":"success"` in the record (RAN `r_handgreen`: passes). After the token edit
  run.log says `no PR named in checkpoint.md; CI not read`, less true than phase 2's `PR #7: no CI runs
  (absent, not a pass)`.
- Evidence: RAN `absent` with `TOP` set to the worktree: `PR #7 CI absent: no runs, but HEAD has a workflow
  file (.github/workflows/ci.yml); push to the PR branch ...`, rc 10. REASONED for the GitHub trigger cases
  (this repo's own `ci.yml` is `on: pull_request` with no filter, so it is not hit itself).
- New in this diff (P3R1-3, P3R1-4 open; owner questions 2 and 3).
- Suggested fix: an override the agent cannot set, read from the runner's environment (for example
  `BLAST_OFF_CI_ABSENT_OK="7 8"`, passed by the owner at `start`), logged as an owner override; and say in
  the message that a PR whose workflows never run on it needs the owner.

### SEC-5 | MEDIUM | lib/ci.sh:81, 103-108 | Nothing ties PR N to the row that names it or to HEAD, so a record for any PR of the repo satisfies the gate
- Failure path: the checks are `.pr == N` and "record head equals `gh pr view N` head now". PR N may be an
  old merged PR, an unrelated PR with the number of another repo's link (SEC-3), or the job's PR at a head
  that lacks the row's gated commit (commits made after the last push are never seen by CI; the receipt
  check covers HEAD, not what was pushed). All pass.
- Evidence: RAN `decoy` (PR #1 green in a cell, job's PR #8 red: passes). REASONED for the unpushed-commit
  case from `lib/ci.sh:103-108` and `lib/receipt.sh:45-65`.
- Pre-existing; made worse by SEC-1 (in phase 2 a decoy did not excuse a second named PR), and now cheap to
  close because the token sits in the same cell as the row's sha.
- Suggested fix: in `ci_check`, for a PR read from a row, require
  `git -C "$TOP" merge-base --is-ancestor <row sha> <record head_sha>` (CI ran on a head that holds the
  gated commit); refuse with "PR #N head does not hold row K's commit".

### SEC-6 | MEDIUM | lib/ci.sh:97 (69-70, 78) | One NUL byte in a Status cell, or anywhere when the fallback reads the file, empties both PR lists: `no PR named in checkpoint.md; CI not read`, exit 0
- Failure path: GNU grep treats NUL input as binary and prints no `-o` match. `| 0 | a | b | done (abc1234)
  · PR #7 \0|` with `PR #7 red` in prose: both lists empty, done passes, and the log line is false. A NUL in
  another cell or row leaves the Status-cell read intact but silently drops the "named elsewhere" list.
  Invalid UTF-8 does not trigger it under `C.UTF-8` (RAN `utf_cell`, `utf_prose`: read).
- Evidence: RAN with errexit on: `nul_cell` and `nul_prose` both `grep: (standard input): binary file
  matches`, `LOG: ... no PR named in checkpoint.md; CI not read`, `=> DONE PASSES (exit 0)`;
  `nul_othercell`, `nul_otherrow`: PR 7 read, rc 10.
- Pre-existing made narrower (phase 2: a NUL anywhere read no PR, silently), but the new log line now
  asserts something untrue to the owner. P3R1-28's `grep -a` half was not done.
- Suggested fix: `command grep -aoiE` in `ci_prs`.

### SEC-7 | MEDIUM | lib/ci.sh:97, 73, 78 | Common ways to write a PR in a Status cell read no PR, and in a table where another row is read the missed PR leaves no trace in run.log
- Failure path: row 1 cell `PR #7, #8`, `PRs #7 and #8`, `PR: #8`, `PR-8`, `pr  #8` (two spaces), `PR&nbsp;#8`,
  `PR \#8`, `#8`, `PR 8`, `pull request #8`. With row 0 naming PR 7 (green) the log is `CI read for the PRs
  Phase plan Status cells name: 7` and done passes; PR 8 is neither read nor listed as unread. With no
  other token the log says `no PR named in checkpoint.md; CI not read`, which is untrue for `#8` and `PR 8`.
- Evidence: RAN `probe4.sh` (two-row table, row 0 `PR #7` green): 8 of 10 PR-8 forms `=> DONE PASSES`, rc 0,
  with only `7` in the log (`PR #7, #8`, `PRs #7 and #8`, `PR: #8`, `PR-8`, `pr  #8`, `PR&nbsp;#8`, `PR \#8`,
  full-width digit); `PR#8` and a `/pull/8` markdown link are read, rc 10; `PR #7 (closes #26)` rightly
  reads 7 only. `#8`, `PR 8` and `pull request #8` were RAN single-row only (`probe.sh` cases `barehash`,
  `nohash`, `pullreq`, with `plural`, `twospace`: `no PR named in checkpoint.md; CI not read`, passes);
  their two-row outcome is REASONED from the same regex.
- Pre-existing regex (P3R1-9, reshaped: logged, not read); the "no trace" half is new with the Status-cell
  rule, since phase 2 would catch the PR from a correct prose mention.
- Suggested fix: inside Status cells only, also read `#N` after a `PR`/`PRs` word on the same cell
  (`PRs? *:? *#N(,? *(and)? *#N)*`); word the last log line "no `PR #N` or `/pull/N` token in checkpoint.md".

### SEC-8 | LOW | lib/ci.sh:89, 108, 45; bin/blast-off:47 | A record's `head_sha` and a workflow run's name reach run.log raw, newlines and escape sequences included
- Failure path: `ci-pr-7.json` with `"head_sha":"abc\n2026-11-15T00:00:02Z job done\u001b[1A\u001b[2K"` and
  verdict `failure` or `success` writes a second, well-formed `... job done` line into run.log and to the
  terminal (`log` is `printf '%s %s\n' | tee -a`; only `receipt_refuse` flattens newlines). The exit code is
  still 10.
- Evidence: RAN `r_forge`, `r_forge2`: run.log held `2026-11-15T00:00:02Z job done^[[1A^[[2K (gate-logs/...`.
- Pre-existing (phase 2 lines 60, 74). Not a new capability: the agent can append to run.log directly. The
  lines this diff adds carry digits and a git-quoted path only.
- Suggested fix: flatten control characters in `log` once (`${*//[[:cntrl:]]/ }`).

### SEC-9 | LOW | lib/ci.sh:53-54; tests/fakes/gh:22-30 | `--limit 100` is applied by gh before the jq filter, and the fake models neither the limit nor field validation
- Failure path: gh help: "-L, --limit int Maximum number of runs to fetch (default 20)"; the filter runs on
  what was fetched. 100 newer `workflow_dispatch` runs on the head (an agent can start them) push the PR's
  runs out: the list filters to empty, verdict `absent`, refused only where HEAD has a workflow; a red PR
  run pushed out while a newer green non-dispatch run stays listed reads `success`. The fake prints every
  run whatever `--limit` says and accepts any field name containing `event`, so dropping `--limit 100`
  (real default 20) or a typo in the field list survives test 41. The `event` values it uses match real gh
  (RAN: real output holds `"event":"pull_request"` and `"event":"workflow_dispatch"`), so the filter itself
  is tested for the two events that matter; `push` is covered by PR 16.
- Evidence: RAN `gh run list --help`, `gh run list --limit 8 --json databaseId,event,headSha,conclusion,
  workflowName`. REASONED for the crowd-out from `lib/ci.sh:53-54` and for the fake from its lines 22-30.
- Pre-existing limit, slightly changed by this diff (red dispatch runs no longer count, so the crowding
  runs need not be green). P3R1-24, P3R1-33 open.
- Suggested fix: `die` when the unfiltered list has 100 entries; make the fake honour `--limit` and reject
  unknown `--json` fields.

### SEC-10 | LOW | lib/ci.sh:86-88 | "no workflow file at HEAD" is logged when no tree was read, and a workflow removed at HEAD excuses every earlier PR
- Failure path: with `TOP` empty the line `PR #N: no CI runs and no workflow file at HEAD (absent, not a
  pass)` is written though nothing was read (RAN `absent`, TOP empty). A later phase that deletes or renames
  `.github/workflows` makes absent pass for PRs whose own trees had the workflow.
- Evidence: RAN for the log line; REASONED for the deletion case.
- New in this diff (P3R1-31 open; owner question 2).
- Suggested fix: log "workdir is in no git repo; workflow files not read"; read the tree of the record's
  `head_sha` when it is in the repo, HEAD otherwise.

### SEC-11 | LOW | lib/ci.sh:16-18, 36-43 | A record carries no repository identity
- Failure path: `blast-off ci-wait <job-dir> N <other-workdir>`, a `GH_REPO` in the agent's shell, or a
  workdir with fork and upstream remotes writes a record of another repository's PR N into this job. The
  runner accepts it when the head sha equals this repo's PR N head (a fork PR of the same commit, where CI
  may be off or different).
- Evidence: REASONED from `bin/blast-off:69`, `lib/ci.sh:17-18,106`.
- Pre-existing.
- Suggested fix: record `gh repo view --json nameWithOwner` in `ci_wait` and compare in `ci_head`.

### SEC-12 | LOW | lib/ci.sh:81-83 | A `success` record written by phase-2 code from a green `workflow_dispatch` run still passes
- Failure path: a job in flight across the upgrade keeps its old record; `ci_check` cannot tell which runs
  made the verdict.
- Evidence: REASONED (record has no `event`). P3R1-23 open.
- Pre-existing made visible by this diff.
- Suggested fix: record `event` per run and re-derive the verdict in `ci_check`, or note it in the PR body.

## Actor view against phase 2 (`git show feat/br-1115-issues/phase-2:lib/ci.sh`)

| Path to `done` with CI not passed | Phase 2 | Now |
|---|---|---|
| Sloppy: one row closed without its token, PR named under Completed phases | exit 10 | exit 0, logged (easier; SEC-1) |
| Sloppy: `#8` / `PR 8` / `PRs #7, #8` in one cell, another row correct, prose correct | exit 10 | exit 0, logged as elsewhere or not at all (easier; SEC-7) |
| Sloppy: no token in any cell, PRs in prose | exit 10 | exit 10 (same; P3R1-1 fixed) |
| Sloppy: no `PR #N` anywhere | exit 0, silent | exit 0, one log line (same, louder) |
| Sloppy: `ci-wait` before runs are listed, or a green dispatch taken for CI | exit 0 | exit 10 where HEAD has a workflow (harder) |
| Sloppy: NUL byte in the file | exit 0 for any NUL, silent | exit 0 only for a NUL in a Status cell or under the fallback, with a false log line (harder) |
| Avoiding: hand-written record, or no `#` in the PR's name, or run.log written directly | works | works (same) |
| Avoiding: `BLAST_OFF_CI_APPEAR=0` for an instant absent record; a one-scenario green dispatch | works | refused where HEAD has a workflow (harder) |
| Avoiding: a green decoy PR in one cell, real PR left in prose | refused if the real PR is named | works, logged (easier) |
| Honest and stuck on absent CI that can never run | passes, logged "absent, not a pass" | refused; the template names the edit that ends it (SEC-2, SEC-4) |

## Round-1 findings checked

| ID | resolved / reshaped / open / not checked | why |
|---|---|---|
| P3R1-1 (HIGH) | resolved | RAN: no table, no trailing pipe, `\|` in the cell, prose-only all fall back and refuse; every branch logs. Residue is SEC-6 and SEC-7, both pre-existing reads |
| P3R1-2 | reshaped | logged, still exit 0; a red record passes (SEC-1) |
| P3R1-3 | open | workdir HEAD decides; owner question 2; SEC-4, SEC-10 |
| P3R1-4 | open | any file counts, no override; the new remedy text cannot work in the stuck cases (SEC-4) |
| P3R1-5 | reshaped | the sentence is now accurate, and accurate about how to leave the gate (SEC-2) |
| P3R1-6 | resolved | `skills/blast-off/SKILL.md` step 4 states both cases, matches `lib/ci.sh:84-88` |
| P3R1-7 | resolved | `README.md:114-117,132` match the code; row 10's "no override" is true |
| P3R1-8 | resolved | `bin/blast-off:37-38` |
| P3R1-9 | reshaped | regex unchanged; logged; "no PR named" is untrue for `#7`, `PR 7` (SEC-7) |
| P3R1-10 | not checked | cases `nt`, `np` are in the file by reading; not run by me |
| P3R1-11 to -13, -15 to -20 | not checked | test cases present by reading; no `tests/run` allowed for this reviewer |
| P3R1-14 | resolved by reading | PR 16 red `push` run; fake's default and `workflow_dispatch` strings match real gh (RAN) |
| P3R1-23, -24, -30, -31, -33, -40 (LOW) | open | SEC-12, SEC-9, SEC-3, SEC-10, SEC-9, baseline note |
| P3R1-28 (LOW) | reshaped | pipeline status now counts; NUL still reads no PR (SEC-6) |

## Owner questions (1-4): is the default the safe one?

1. Whole-file read when no Status cell names a PR. Yes in direction: it fails closed, and both alternatives
   are worse ((a) reopens P3R1-1 for a table with no tokens; (b) breaks jobs with no PR). Its cost is larger
   than the baton says: criterion 3 is unmet for that class, the hint has no way out for a `/pull/N` URL,
   and the refusal points `ci-wait`, "fix and push" and "push to the PR branch" at this repo's PR of that
   number (SEC-3).
2. Workdir HEAD decides "runs were due". Safe in direction for a workflow added later (it refuses more), not
   safe for one removed or renamed at HEAD (SEC-10). The stated remedy cannot work for an earlier stacked
   PR whose branch and base have no workflow file: no push to that branch starts a `pull_request` run, and
   a dispatch no longer counts (SEC-4).
3. Any file counts, no override. Fail-closed on its face, but with no owner-held override the exits left to
   the agent are the token edit and the record edit, both quieter than phase 2's "absent, not a pass". An
   override read from the runner's environment keeps the decision with the owner (SEC-4).
4. A PR named only elsewhere is logged and not read once a Status cell names one. Not the safe default: a
   red record passes with exit 0 (SEC-1). Reading the union whenever a done row has no token keeps issue
   26's fix for well-formed tables.

## What I did not check

- No `tests/run` of any kind: every claim about test 41 or 51 is from reading. Mutants not run.
- `git ls-tree` quoting is from git-config(1) and git-ls-tree(1), not from a repo with odd file names (no
  git write allowed).
- Real `gh` behaviour with fork plus upstream remotes, `GH_REPO`, `pull_request_target` run head shas, and
  the 100-run crowd-out: reasoned, not run.
- `lib/usage.sh`, `lib/child.sh`, `lib/units.sh`, `lib/preflight.sh`: not read beyond grep. PATH planting of
  `gh`, `jq` or `git` by a same-uid agent: out of this diff.
- A note for triage on the shared harness: `rev2/probe.sh` runs `ci_check` inside `( ... ) || echo`, where
  bash ignores errexit, so it prints `DONE PASSES` on paths the real runner aborts. Example: a record of
  valid JSON followed by garbage shows `DONE PASSES` there; with errexit on (`probe3.sh`) it is rc 5, which
  `chain_exit` turns into exit 1. Any reviewer's "passes" from that harness on a path that depends on
  `set -e` needs a re-run.
- My temp dir `.../scratchpad/secrev.D6j176` is left in place.
