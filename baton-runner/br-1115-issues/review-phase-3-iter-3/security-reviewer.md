# security-reviewer: blast-off phase 3 (issue 26), review round 3

No CRITICAL and no HIGH. 3 MEDIUM, 11 LOW. Every `gh` failure, timeout, empty or `null` output, a missing `jq`, an unset
`GH_TOKEN` and every malformed record field ends in exit 10 or a runner abort, never in `job done`; no checkpoint or
record text reaches a shell, a `jq` program or a path unquoted. The three MEDIUM are fail-open paths an honest but sloppy
child can hit with an off-template checkpoint, each a weakening against phase 2: an unread table row (SEC-1), the words
`no PR` beside a PR spelled without `#<digit>` (SEC-2), a second PR written without `#` (SEC-3). The hostile-only items
sit inside the baseline: such a child can already forge a record (P3R2-10) or write `no PR` (ruling 1).

## How the probes were run

Temp dir `/tmp/p3r3-sec.JoNdB8` (made with `mktemp -d /tmp/p3r3-sec.XXXXXX`, left in place so the
probes can be re-run). No scenario, no `tests/run`, no gate, nothing written to the worktree but this
file. Git ran with `GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null` on a throwaway
`git init` repo: commit `c2ba299` has no workflow file (NOWF), its child `d54ecca` has
`.github/workflows/ci.yml` (WF). A fake `gh` executable sits first on `PATH` (a shell function would
be skipped by `timeout gh`).

Harness (`/tmp/p3r3-sec.JoNdB8/harness.sh`), errexit in force, `ci_check` called plainly:

```bash
set -euo pipefail
W=/home/alex/blast-off/.claude/worktrees/pending-items-53932d
chain_end() { echo "END $1: $2"; exit "$1"; }
log() { echo "LOG $*"; }
die() { echo "DIE $*"; exit 1; }
source "$W/lib/checkpoint.sh"; source "$W/lib/ci.sh"
echo "phases=$(cp_phases) done_rows=[$(cp_done_rows | paste -sd' ')] open_rows=[$(cp_open_rows | paste -sd' ')]"
ci_check
echo "PASSED: job done"
```

Three outcomes: `END 10` is a refusal, `PASSED` is done let through, a non-zero exit with no `END`
is an errexit abort (the real runner turns it into exit 1, `runner exit <n> without a state`). The
harness does not call `receipt_all_done`; a row listed in `open_rows` is refused by it (exit 9)
before `ci_check` runs, so `PASSED` beside a non-empty `open_rows` is not a pass in the runner.

Baseline, all as the spec says:

```
== baseline success                    PASSED: job done                     rc=0
== baseline absent, wf at head         END 10: PR #7 CI absent: no runs, but its head d54ecca has a workflow file (.github/workflows/ci.yml); ...   rc=10
== baseline absent, no wf at head      LOG PR #7: no CI runs and no workflow file at its head c2ba299 (no CI configured; absent, not a pass)  PASSED  rc=0
== baseline failure                    END 10: PR #7 CI red or unfinished at d54ecca4... rc=10
== baseline no record                  END 10: PR #7 CI unread: no readable record for PR 7 ... rc=10
```

`bash -n lib/ci.sh lib/checkpoint.sh`: ok. `shellcheck lib/ci.sh lib/checkpoint.sh`: ok.
Tools on this box: jq 1.7, git 2.43.0, GNU sed 4.9, GNU Awk 5.2.1, GNU grep 3.11, `LANG=C.UTF-8`.

## Findings

### SEC-1: a table row the parser does not read drops its PR from every gate; phase 2 refused the same checkpoint
- Severity: MEDIUM
- File: lib/checkpoint.sh:43-46 (the row filter), lib/ci.sh:70-84
- Reachable by a template-following job: only by an off-template checkpoint. The child must have written a row whose first cell does not start with a digit (`P1`, `**1**`, `Phase 1`, `~~1~~`), indented the row or put a tab after the first pipe, put a second `## Phase plan` heading straight after the first table, or put a `## ` line inside the plan before more rows. The template says "the runner only sees rows like that".
- Direction: fail-open
- Origin: introduced by this diff. Phase 2 read `PR #N` from the whole file, so the red or missing record of a PR in such a row gave exit 10. Ruling 1 removed the whole-file read; the ruling speaks of prose and of done rows, not of table rows the parser skips. `tests/41-ci-wait.sh:91-99` pins the skip as wanted (PR #96 on a `P1` row, PR #97 under another heading) for the no-record case.
- Threat model: honest but sloppy child. Not covered by P3R2-10 (no record is forged) and only loosely by ruling 1 (the row never says `no PR`).
- Failure path: checkpoint has `| 0 | a | x | done (abc1234) · no PR |` and `| P1 | b | y | done (def5678) · PR #7 |`; `gate-logs/ci-pr-7.json` is `failure`. `cp_plan_rows` keeps only lines matching `^| *[0-9]`, so row `P1` is in none of `cp_phases`, `cp_open_rows`, `cp_done_cells`. `receipt_all_done` sees no open row, `ci_check` reads one cell (`no PR`), logs `PRs read: none; rows that say no PR: 0`, returns, `chain_end 0 "job done"`. The second-heading case: `sed -n '/^## Phase plan/,/^## /'` ends its range on the second `## Phase plan` line and does not start a new one on that same line, so the whole second table is outside every range.
- Evidence: probe, red record for PR 7, each row beside `| 0 | a | x | done (abc1234) · no PR |`:
  ```
  row=[| P1 | b | y | done (def5678) · PR #7 |]      phase2-would-read=[7]  phases=1 open_rows=[]  PRs read: none  PASSED rc=0
  row=[| **1** | b | y | done (def5678) · PR #7 |]   phase2-would-read=[7]  phases=1 open_rows=[]  PRs read: none  PASSED rc=0
  row=[ | 1 | b | y | done (def5678) · PR #7 |]      (leading space)        phases=1 open_rows=[]  PASSED rc=0
  row=[|<TAB>1 | b | y | done (def5678) · PR #7 |]                          phases=1 open_rows=[]  PASSED rc=0
  row=[| Phase 1 | b | y | done (def5678) · PR #7 |]                        phases=1 open_rows=[]  PASSED rc=0
  row=[| ~~1~~ | b | y | done (def5678) · PR #7 |]                          phases=1 open_rows=[]  PASSED rc=0
  == two headings back to back: old table (row 0, no PR) then `## Phase plan` with rows 0 and 1 (PR #7)
     phases=1 done_rows=[0] open_rows=[]  PRs read: none; rows that say no PR: 0  PASSED rc=0  phase2-would-read=[7]
  == rows after a `## Phase 1 detail` line inside the plan      phases=1  PASSED rc=0  phase2-would-read=[7]
  ```
  `phase2-would-read` is the phase-2 expression `grep -oiE 'PR ?#[0-9]+|/pull/[0-9]+' checkpoint.md` run on the same file; with a red record phase 2 took its `failure)` arm, exit 10 (`git show feat/br-1115-issues/phase-2:lib/ci.sh` lines 55-60). Rows that fail closed instead (they read as open, exit 9): no trailing pipe, an extra cell after Status, `**done**`, `✅ done`, key `1/2`. Two headings with another section between them are both read (refused, rc=10).
- Suggested fix: at `status: done`, refuse when the `## Phase plan` section holds a table line the row filter skipped: count lines matching `^[[:space:]]*\|` in the section, less the header and the `|---|` line, and compare with `cp_phases`; and refuse a second `^## Phase plan` heading. Both stay inside ruling 1: no prose is read, and the refusal names the row to fix.

### SEC-2: the `no PR` phrase anywhere in the cell is read as the explicit `no PR`, also beside a PR spelled a way the `stray` check misses
- Severity: MEDIUM
- File: lib/ci.sh:69,72,74-76
- Reachable by a template-following job: only by an off-template checkpoint. The child must have written the PR without an ASCII `#<digit>` (`PR 7`, `PR # 7`, `pull request 7`, `gh pr 7`, `.../pulls/7`) and the words `no PR` somewhere in the same cell.
- Direction: fail-open
- Origin: introduced by this diff (the `no PR` token and the `stray` check are new), and a weakening against phase 2 for a checkpoint that otherwise follows the template: the template's Completed-phases entry names the phase's `PR #<n>`, phase 2 read it from there, phase 3 reads nothing outside the cell (ruling 1). Where no other line names the PR, phase 2 passed these cells too. It is ruling 1's "explicit `no PR`" and P3R2-6 ("a PR written a way the runner does not read is refused, never passed as no PR named") enforced only for `#<digit>` and `/pull/`.
- Threat model: honest but sloppy child for the first two rows below; the unicode and entity forms need intent, and a hostile child can simply write `no PR`.
- Failure path: cell `done (abc1234) · PR 7 · no PR checks failed`. Line 71 `ci_prs` finds no `PR ?#[0-9]+`, so `n` is empty. Line 72: nothing left matches `#[0-9]|/pull/`. Line 74: `(^|[^[:alnum:]])no PR([^[:alnum:]]|$)` matches inside "no PR checks". Line 75: `n` empty, no refusal. The row is logged under "rows that say no PR" and PR 7 is never looked up.
- Evidence: probe, no record for PR 7 present (so a read of PR 7 would refuse):
  ```
  cell=[done (abc1234) · PR 7 · no PR checks failed]                 PRs read: none; rows that say no PR: 0   PASSED rc=0
  cell=[done (abc1234) · no PR yet, PR 7 open]                       PASSED rc=0
  cell=[done (abc1234) · pull request 7 merged, no PR template used] PASSED rc=0
  cell=[done (abc1234) · no pr · gh pr 7]                            PASSED rc=0
  cell=[done (abc1234) · https://github.com/o/r/pulls/7 · no PR]     PASSED rc=0
  cell=[done (abc1234) · PR # 7 · no PR]                             PASSED rc=0
  cell=[done (abc1234) · PRs 7 and 8 · no PR]                        PASSED rc=0
  cell=[done (abc1234) · PR ＃7 · no PR] (fullwidth #)   PASSED    cell=[... PR #７ · no PR] (fullwidth 7)  PASSED
  cell=[done (abc1234) · PR #٧ · no PR] (Arabic-Indic 7) PASSED    cell=[... PR #<ZWSP>7 · no PR]           PASSED
  cell=[done (abc1234) · PR &num;7 · no PR]  PASSED   cell=[... PR `#`7 · no PR]  PASSED   cell=[... PR #<7> · no PR]  PASSED
  cell=[done (abc1234) · PR #0 · no PR]      PASSED   cell=[... PR #-1 · no PR]   PASSED   cell=[... MR !7 · no PR]    PASSED
  ```
  Against phase 2, on a template-shaped checkpoint (Completed-phases line `- **Phase 0, a** (done ..., children 1-2). works; gate PASS; PR #7; CI conclusion read.`), red record for PR 7:
  ```
  cell=[done (abc1234) · PR 7 · no PR checks failed]   LOG CI at done: PRs read: none; rows that say no PR: 0   PASSED: job done rc=0
  phase2-would-read=[7] => phase 2: failure arm, exit 10
  ```
  Caught, as intended: `PR &#35;7 · no PR`, `PR \#7 · no PR`, `PR&nbsp;#7 · no PR`, `o/r#7`, `no PR #7`, `<!-- PR #7 --> no PR` (all END 10). Refused as neither: `no PRs`, `no  PR`, `no-PR`, `no<NBSP>PR`, `piano PR`. Locale note: under `LC_ALL=C` the cell `éno PR` reads as `no PR` (the bytes of `é` are not alnum there); under `C.UTF-8` it is refused.
- Suggested fix: whitelist instead of blacklist. After stripping the leading `done (<sha>)` and the runner's own trailing ` · usage ...`, require the rest of the cell to be exactly one or more `PR #<n>` / `/pull/<n>` tokens, or exactly `no PR`, and refuse anything else with the same message. That closes SEC-2 and SEC-3 in one test and makes `stray` unnecessary.

### SEC-3: a second PR written without `#` is dropped silently, and a number with a separator is read as another PR
- Severity: MEDIUM
- File: lib/ci.sh:72,104
- Reachable by a template-following job: only by an off-template checkpoint (the child must have closed one row with two PRs, or written a thousands separator).
- Direction: fail-open
- Origin: the cell was read the same way in phase 2, but phase 2 also read the rest of the file, so a second PR named as `PR #8` in the Completed-phases entry was checked; now it is not. Pre-existing and made worse. The new `stray` check, added for this case (`PR #7, #8`), covers only tokens that carry `#<digit>` or `/pull/`.
- Threat model: honest but sloppy child.
- Failure path: cell `done (abc1234) · PR #7, 8`. `ci_prs` returns `7`. `sed` removes `PR #7`, leaving `, 8`, which holds no `#<digit>`: no refusal. PR 8 is never read. Cell `PR #1,234` is read as PR 1: with a green record for this repo's PR 1 (an earlier phase's), done passes and PR 1234 is never read.
- Evidence: probe, no records present:
  ```
  cell=[done (abc1234) · PR #7, 8]      PRs read: 7   END 10: PR #7 CI unread ...   (8 is not asked for)
  cell=[done (abc1234) · PR #7-9]       PRs read: 7
  cell=[done (abc1234) · PR #7 and 8]   PRs read: 7
  cell=[done (abc1234) · PR #1,234]     PRs read: 1
  cell=[done (abc1234) · PR #8.5]       PRs read: 8        cell=[... PR #8e3]  PRs read: 8
  ```
  Those runs had no records. With records (7 green, 8 red; then 1 green, none for 1234):
  ```
  cell=[PR #7, 8], Completed-phases entry "PR #7, PR #8"   PRs read: 7   PASSED: job done rc=0    phase2-would-read=[7 8] => PR 8 red, exit 10
  cell=[PR #7, 8], entry also "PR #7, 8"                    PRs read: 7   PASSED: job done rc=0    phase2-would-read=[7] (phase 2 passed too)
  cell=[PR #1,234], green record for PR 1                   PRs read: 1   PASSED: job done rc=0    phase2-would-read=[1]
  ```
  `PRs read: 7` in `run.log` looks healthy, so this one is harder to see afterwards than SEC-2's `PRs read: none`.
- Suggested fix: the whitelist of SEC-2 (a token must end at a non-word boundary and nothing else may stand in the cell).

### SEC-4: the record's `head_sha` and gh's `headRefOid` are never checked to be a 40-hex sha at `done`; any text that matches reaches `git ls-tree` as a revision
- Severity: LOW
- File: lib/ci.sh:89,92,112-115
- Reachable by a template-following job: no. It needs a hand-written record and a `gh pr view` that prints the same non-sha text (`null`, `{}`, a ref name). A real `gh` prints the PR's 40-hex head.
- Direction: fail-open, in theory
- Origin: the unchecked comparison is pre-existing (`ci_head`); passing the text to `git ls-tree "$h^{commit}"` is introduced by this diff. `ci_wait` does check the shape (line 19); the reader does not.
- Threat model: hostile child plus an abnormal gh. Inside the P3R2-10 baseline (the record is trusted).
- Failure path: record `{"pr":7,"verdict":"success","head_sha":"null"}`; `gh pr view` prints `{}` or `{"headRefOid":null}`; `jq -r .headRefOid` prints the word `null`; `[ "$cur" = "$h" ]` holds; done passes. With `"verdict":"absent"` and a local ref of that name pointing at a commit with no workflow file, `git ls-tree -r --name-only "null^{commit}"` resolves the ref and the absent record passes too.
- Evidence:
  ```
  == success record head_sha "null" + gh headRefOid null         PASSED: job done  rc=0
  == success record head_sha "null" + gh prints {}                PASSED: job done  rc=0
  == absent record head_sha=[clean] (a tag on the no-workflow commit), gh returns the same text
     LOG PR #7: no CI runs and no workflow file at its head clean (no CI configured; absent, not a pass)   PASSED rc=0
  == absent record head_sha=[null] (a branch named null)          PASSED rc=0
  == absent record head_sha=[HEAD~1]                              PASSED rc=0
  == absent record head_sha=[c2ba299] (7-hex abbreviation)        PASSED rc=0
  == absent record head_sha=[HEAD]      END 10: ... its head HEAD has a workflow file (.github/workflows/ci.yml)
  == absent record head_sha=[--help], [-h], [.*], [a b], a tree sha    END 10: ... is no commit git can read ...
  == absent record head_sha=[$(touch .../PWNED)], [HEAD; touch .../PWNED2]   END 10; no PWNED file: no shell evaluation
  ```
  With a real gh output every one of these is refused by the comparison. Option-shaped text does reach git's option parser: run directly, `git ls-tree -r --name-only '--help^{commit}' -- .github/workflows` prints ``error: unknown option `help^{commit}'`` and the usage, exit non-zero, hence the refusal. I found no option that survives the appended `^{commit}`; `--end-of-options` before the revision would end the question.
- Suggested fix: in `ci_head`, `[[ $cur =~ ^[0-9a-f]{40}$ ]] || cur=` before the comparison (the test `ci_wait` already applies). One line, and the text that reaches `git ls-tree` and the log is then always a sha.

### SEC-5: `git replace` changes the tree `git ls-tree` reads for the PR's head
- Severity: LOW
- File: lib/ci.sh:92
- Reachable by a template-following job: no. The child must run `git replace <PR head> <a commit with no workflow file>` in the workdir's repo.
- Direction: fail-open
- Origin: introduced by this diff (the `ls-tree` read is new).
- Threat model: hostile child. Inside the baseline: the same child could write a `success` record.
- Failure path: PR head `d54ecca` has `.github/workflows/ci.yml`, the record is `absent`. `refs/replace/d54ecca...` points at `c2ba299`. `git ls-tree` honours replace refs, lists nothing under `.github/workflows`, and line 95 logs "no workflow file at its head d54ecca".
- Evidence:
  ```
  --- git replace: PR head d54ecca4... (has ci.yml) replaced by c2ba2991... (none)
  LOG PR #7: no CI runs and no workflow file at its head d54ecca (no CI configured; absent, not a pass)
  PASSED: job done   rc=0
  --- control after `git replace -d`:  END 10: PR #7 CI absent: no runs, but its head d54ecca has a workflow file (.github/workflows/ci.yml)
  ```
- Suggested fix: `git --no-replace-objects -C "$TOP" ls-tree ...`.

### SEC-6: bytes after a valid JSON value in the record abort the runner (exit 1, no state) instead of exit 10
- Severity: LOW
- File: lib/ci.sh:86 (`|| true` hides the parse error), 89 and 112 (no guard)
- Reachable by a template-following job: no. `ci_wait` writes the record whole and renames it; the file must have been edited or appended to by hand.
- Direction: fail-closed (not a pass), with no usable message
- Origin: pre-existing in `ci_head` (line 112 is phase-2 code); line 89 adds a second unguarded `jq` on the same file.
- Threat model: hostile or careless hand edit; inside P3R2-10.
- Failure path: record `{"pr":7,"verdict":"success","head_sha":"<sha>"} garbage`. Line 86: jq prints `success`, then fails; `|| true` keeps `success`. `ci_head`, line 112: `h="$(jq -r ...)"` fails with status 5; under errexit the runner exits; the EXIT trap logs `runner exit 5 without a state` and exits 1. The owner gets no "CI unread" line.
- Evidence:
  ```
  == 15 success then garbage     jq: parse error: Invalid numeric literal at EOF at line 1, column 90     rc=5  (no END line)
  == 16 absent then garbage      jq: parse error: Invalid numeric literal at EOF at line 1, column 89     rc=5
  ```
  Related, all refused or correct: `{..failure..}{..success..}` and `{..success..}{..failure..}` read as unread (rc=10); `{}{..success..}` unread; `{..success..}{}` passes (rc=0: a second empty value is ignored, hostile only); a duplicate `verdict` key takes the last one (jq's rule).
- Suggested fix: read the record once with `jq -e -s 'length == 1'` (or `jq -r --argjson n "$pr" -s 'if length == 1 and .[0].pr == $n then ...'`) so a file that is not exactly one value is "unread", exit 10.

### SEC-7: record and gh text is written raw into `run.log`: forged lines and terminal escapes
- Severity: LOW
- File: lib/ci.sh:96 and 115 (pre-existing), 91 and 93 (new), 45 (`ci_wait`, pre-existing)
- Reachable by a template-following job: no for the record fields (a hand-written record). For line 45 the text is the workflow run's `name`, which the PR's own workflow file sets; whether GitHub keeps a newline in a workflow name is recall, not checked.
- Direction: neither (the exit code is not changed)
- Origin: pre-existing; lines 91 and 93 add two more places that print the whole `head_sha`. Lines 94 and 95 print only `${h:0:7}`.
- Threat model: hostile child. The child can also append to `run.log` itself (it is in the job dir), so this adds nothing to the baseline; it matters once the log is treated as the runner's own account.
- Failure path: `"head_sha":"x\n2026-11-16T00:00:00Z job done"` in a `failure` record: line 96 prints `jq -r '.head_sha // "?"'` unescaped, so `run.log` holds a line that reads as the runner's `job done`.
- Evidence:
  ```
  == 20 failure, head_sha with newline
  END 10: PR #7 CI red or unfinished at x
  2026-11-16T00:00:00Z job done (gate-logs/ci-pr-7.json); fix and push if red, ...            rc=10
  == 22 failure, head_sha with ANSI escape (cat -v)
  END 10: PR #7 CI red or unfinished at ^[[2J^[[31mred (gate-logs/ci-pr-7.json); ...
  == ci_wait with a run whose name holds a newline (fake gh)
  LOG ci PR #7 at d54ecca4...: failure (ci failure)
  2026-11-16T00:00:00Z ci PR #7 at d54ecca4...: success (ci success failure)                  rc=10
  ```
  Clean: a workflow file name with a newline or ESC at the PR's head is C-quoted by git before it reaches the line-94 message (`(".github/workflows/\033[2Jx.yml")`), also with `core.quotePath=false`. Row keys are `[0-9A-Za-z._-]+` and PR numbers digits, so the row messages cannot be forged.
- Suggested fix: SEC-4's sha check removes the record-field cases; in `ci_wait` line 45 use `@json` for `.name` (or `gsub("[[:cntrl:]]"; "?")`).

### SEC-8: "no workflow file at the head" is logged as "no CI configured", and the PR's own head commit decides it
- Severity: LOW
- File: lib/ci.sh:92-95
- Reachable by a template-following job: yes for a PR branch cut before the base got its workflows, or a repo whose CI is not GitHub Actions; no for the delete case (the child must delete `.github/workflows` in its own PR).
- Direction: fail-open
- Origin: the head as the decider is owner ruling 2, a fixed fact; this finding is the residue the ruling leaves and the log wording, not the ruling. Phase 2 passed every absent record, so nothing here is weaker than before.
- Threat model: the delete case is a hostile child that needs no forged file, only a commit; covered in spirit by the baseline. The others are honest jobs.
- Failure path: (0) a PR branch cut before the base got its workflows: by recall GitHub builds `pull_request` runs from the merge of head and base, so runs are due though the head has no file; they reach `absent` only when none is listed within `BLAST_OFF_CI_APPEAR` (a slow queue, or a PR with merge conflicts, which by recall gets no `pull_request` run); the head then has no file and done passes. (a) the PR's head commit removes `.github/workflows/`; a `pull_request` run is built from the merge of head and base, which then has no workflow, so no run starts; `ci-wait` records `absent`; `ci_check` finds no file at the head and passes, logged "no CI configured". (b) Case variants `.github/Workflows/ci.yml` and `.GITHUB/workflows/ci.yml`, and a sibling `.github/workflows-old/`, read as no workflow file. (c) CI from a commit status or another app (not Actions) is never read (stated in the spec, pre-existing), yet the log line says "no CI configured". Which of these GitHub would have started a run for is recall, not checked: my recall is that only `.github/workflows` in that exact case is read, that `pull_request` uses the merge commit's workflow files and `pull_request_target` the base's.
- Evidence:
  ```
  == absent, PR head tree: Workflows   LOG PR #7: no CI runs and no workflow file at its head a369c5e (no CI configured; absent, not a pass)   PASSED rc=0
  == absent, PR head tree: GITHUB      PASSED rc=0        == absent, PR head tree: sibling (.github/workflows-old/ci.yml)   PASSED rc=0
  == core.ignorecase=true + Workflows  PASSED rc=0  (the pathspec stays case-sensitive)
  ```
- Suggested fix: none needed for the ruling. Word the log line as what was read ("no file under .github/workflows at its head") and have it name the PR's base when the base has a workflow file the head lacks, so the owner sees the case in `run.log`.

### SEC-9: any path under `.github/workflows` counts as a workflow file, with "no override"
- Severity: LOW
- File: lib/ci.sh:92-94
- Reachable by a template-following job: yes, in a repo whose `.github/workflows/` holds only a `README.md`, a `.gitkeep`, a disabled `*.yml.disabled`, or workflows that never start on a PR.
- Direction: fail-closed
- Origin: introduced by this diff; the spec states it ("any file").
- Threat model: none; an availability cost on honest jobs.
- Failure path: the PR gets no run; the record is `absent`; `ls-tree` prints `.github/workflows/.gitkeep`; exit 10 with "has a workflow file (.github/workflows/.gitkeep) ... there is no override: ask the owner". The one edit that does get such a job through is replacing `PR #<n>` with `no PR`, which drops the PR from the gate for good (ruling 1 trusts the cell).
- Evidence:
  ```
  PR head tree: file (.github/workflows is a blob)      END 10 ... has a workflow file (.github/workflows)
  PR head tree: symlink (.github/workflows -> ci)       END 10 ... (.github/workflows)
  PR head tree: gitlink (a submodule at that path)      END 10 ... (.github/workflows)
  PR head tree: gitkeep / readme / disabled / nested    END 10 ... (.github/workflows/.gitkeep | README.md | ci.yml.disabled | sub/ci.yml)
  PR head tree: symfile (ci.yml is a symlink)           END 10
  PR head tree: missing object                          END 10 ... is no commit git can read ...
  shallow clone, head = tip                             END 10 (workflow file read)
  shallow clone, head = the tip's parent                END 10 ... is no commit git can read ...; git -C ... fetch origin pull/7/head
  TOP empty                                             END 10 ... the workdir is in no git repo ...
  ```
- Suggested fix: count only regular files matching `.github/workflows/*.yml` or `*.yaml` directly in that directory (`git ls-tree --name-only "$h^{commit}" .github/workflows/` then a `grep -E '\.ya?ml$'`), which is what GitHub reads by my recall.

### SEC-10: `git ls-tree` at `done` can start a network fetch with no time limit
- Severity: LOW
- File: lib/ci.sh:92
- Reachable by a template-following job: yes, when the workdir is a partial clone (`--filter=tree:0` or `blob:none`).
- Direction: neither (fail-closed if the fetch fails; the runner holds the job lock while it runs)
- Origin: introduced by this diff. `ci_head` bounds its `gh` call with `BLAST_OFF_CI_HEAD` (P4R2-2) for the same reason; the new git call has no bound.
- Threat model: none; a hang, not a bypass.
- Failure path: the head commit's tree is not local; `ls-tree` asks the promisor remote for it; a stalled remote or an ssh prompt holds the runner at `done`.
- Evidence: treeless partial clone of the throwaway repo, `GIT_TRACE=1 git -C partial ls-tree -r --name-only c2ba299...^{commit} -- .github/workflows`:
  ```
  trace: run_command: git -c fetch.negotiationAlgorithm=noop fetch origin --no-tags --no-write-fetch-head --recurse-submodules=no --filter=blob:none --stdin
  trace: run_command: ... 'git-upload-pack '\''/tmp/p3r3-sec.JoNdB8/repo'\'''
  ```
- Suggested fix: `timeout "${BLAST_OFF_CI_HEAD:-60}" git ...` with `GIT_NO_LAZY_FETCH=1` (in newer gits; the version is recall, not checked: 2.43 here) or accept the fetch and bound it.

### SEC-11: a `/pull/N` link of another repo inside a Status cell is still read as this repo's PR N
- Severity: LOW
- File: lib/ci.sh:104
- Reachable by a template-following job: only by an off-template checkpoint (the template says to name another PR "in prose, outside the table").
- Direction: fail-closed, or fail-open for the linked PR's own number when this repo has a green record of that number
- Origin: pre-existing (P3R2-2's reading), now confined to done Status cells.
- Threat model: honest but sloppy child.
- Failure path: cell `done (abc1234) · PR #7 (needs https://github.com/other/repo/pull/5)`: `ci_prs` returns `5 7`; this repo's PR 5 needs a record.
- Evidence: `cell=[done (abc1234) · [PR #7](https://github.com/o/r/pull/8)]  PRs read: 7 8`; `cell=[... [PR #7](https://github.com/other/repo/pull/7)]  PRs read: 7`.
- Suggested fix: none beyond the template text already there; the SEC-2 whitelist could accept `/pull/N` only without a host, or with the workdir remote's host and path.

### SEC-12: the Status cell is whatever follows the last unescaped-or-escaped pipe; a `\|` or a fifth column moves it
- Severity: LOW
- File: lib/checkpoint.sh:44 (`awk -F'|'`, `$(NF-1)`)
- Reachable by a template-following job: only by an off-template checkpoint (a `\|` inside a cell, or a column after Status).
- Direction: fail-open in the contrived case, fail-closed in the likely ones
- Origin: pre-existing parser; the diff makes the last cell decide which PR is read.
- Threat model: hostile child for the fail-open form (and it could write `no PR` alone); sloppy child for the fail-closed forms.
- Failure path: `| 1 | b | y | PR #7 red \| done (def5678) · no PR |` renders in markdown as one Status cell naming PR #7; awk splits at the escaped pipe and reads ` done (def5678) · no PR`.
- Evidence:
  ```
  row=[| 1 | b | y | PR #7 red \| done (def5678) · no PR |]   done_rows=[0 1]  rows that say no PR: 0 1   PASSED rc=0
  row=[| 1 | b | y | PR #7 red | done (def5678) · no PR |]     done_rows=[0 1]  rows that say no PR: 0 1   PASSED rc=0
  cell=[done (abc1234) · PR #7 \| note]   done_rows=[] open_rows=[0]  END 10: status done but the Phase plan has no done row (exit 9 in the runner: the row reads as open)
  row=[| 1 | b | y | done (def5678) · PR #7 | notes |]         open_rows=[1]  (exit 9 in the runner)
  ```
- Suggested fix: refuse a done row whose cell count differs from the header row's, and treat `\|` as cell text.

### SEC-13: the absent-CI refusal says "there is no override" while the cell itself is one
- Severity: LOW
- File: lib/ci.sh:94; README.md exit-code row 10
- Reachable by a template-following job: yes (any PR that gets no run on a head with a workflow file).
- Direction: fail-open by a later edit, not by the code
- Origin: introduced by this diff (the refusal is new); the trust in the cell is ruling 1.
- Threat model: a lazy or hostile later child, or an owner in a hurry. Covered by ruling 1 (the cell is the declaration); recorded because the gate's strength for a named PR is the cell's.
- Failure path: after exit 10 on PR #7 absent, changing `· PR #7` to `· no PR` passes at the next run. `run.log` then reads `PRs read: none; rows that say no PR: 0`: the only trace is that the row said `PR #7` in an earlier log line.
- Evidence: lib/ci.sh:74-76 read; probe "row says no PR, a red record for PR 7 lies in gate-logs": `LOG CI at done: PRs read: none; rows that say no PR: 0`, `PASSED: job done`, rc=0 (as ruled, and as `tests/41-ci-wait.sh:181-184` pins). The refusal text and the README do not point at that edit; they say push, then `ci-wait`, else ask the owner.
- Suggested fix: at `done`, log a warning (not a refusal, to stay inside ruling 1) when a row says `no PR` while `gate-logs/ci-pr-*.json` records exist that no row names: "record for PR #7 present but no row names it".

### SEC-14: `timeout` without `-k` around `gh pr view`
- Severity: LOW
- File: lib/ci.sh:113
- Reachable by a template-following job: yes, only with a gh process that ignores SIGTERM.
- Direction: neither (a hang at `done`)
- Origin: pre-existing (P4R2-2's fix).
- Threat model: none.
- Failure path: `timeout 60 gh ...` sends TERM at 60 s and then waits without limit.
- Evidence: lib/ci.sh:113 read; the timeout itself works: `== success: gh slower than BLAST_OFF_CI_HEAD=1   END 10: PR #7 CI unread for head unknown (gh pr view 7 failed) ... rc=10`.
- Suggested fix: `timeout -k 5 ...`.

## Checked and clean

- `gh pr view` exit 1, exit 4 with `GH_TOKEN` unset, empty output with exit 0, `null`, `{}`, non-JSON, slower than `BLAST_OFF_CI_HEAD=1`: each `END 10 ... CI unread for head ...`, for `success` and for `absent` records (16 probes).
- `jq` exiting 127 (a fake first on `PATH`): `END 10: PR #7 CI unread`. With every row `no PR`, `jq` is not needed and done passes, as ruled.
- Record with `pr` missing, `pr` a string, `verdict` missing or an array, `head_sha` missing or a number, the record an array, an empty file: each exit 10. `pr: 7.0` and `verdict: "success\n"` read as 7 and success (harmless).
- PR number past 2^53 (`PR #9007199254740993`, record `pr: 9007199254740992`): refused; jq 1.7 keeps the digits. A 26-digit number: refused as unread.
- `PR #7` with a NUL between `#` and `7` is read as PR 7; a zero-width space inside `no PR` beside `PR #7` reads PR 7.
- `git ls-tree` variants that read as "no workflow file" and so pass an absent record: no `.github` at all, `.github/Workflows/` and `.GITHUB/workflows/` (case), `.github/workflows-old/`, files beside the directory (`.github/dependabot.yml`), an empty tree at `.github/workflows` (built with `git mktree`; a checkout cannot make one: `LOG ... no workflow file at its head 411cd94`, PASSED), and a head whose replace ref points at such a commit (SEC-5). Refused: every other variant in SEC-9.
- A commit of another repo fetched into the workdir's repo: the check is by object id, so a local object with the PR head's sha is that commit, whatever remote it came from; a sha not present is refused ("no commit git can read"). A workdir in another repo than the PR cannot arise without `GH_REPO`: gh reads the repo from the workdir's remote, and git reads the same workdir's repo.
- Nothing from the checkpoint or record is evaluated by a shell or spliced into a `jq`, `sed` or `grep` program: `$pr` is digits (`ci_prs` keeps only what follows the last `#` or `/` of a matched token), `$k` is `[0-9A-Za-z._-]+`, `$cell` is only ever stdin, `$h` is one quoted argument.

## What this diff weakens against phase 2 (`git show feat/br-1115-issues/phase-2:lib/ci.sh`)

- A PR named only in prose or in another cell is no longer read, so its red or missing record no longer refuses done. Owner ruling 1; not a finding.
- A PR in a table row the parser does not read is no longer read (SEC-1).
- A done Status cell that hides or drops its PR was backstopped in phase 2 by any other line naming `PR #N`, the template's Completed-phases entry among them; the backstop is gone (SEC-2, SEC-3).
- A red `workflow_dispatch` run on the PR's head no longer makes the record `failure` (`ci_runs`, lib/ci.sh:52-55). Acceptance criterion 4; not a finding.
- Nothing else is weaker: `absent` is stricter than before, `ci_head` is unchanged, the record checks are unchanged.

## Round-2 HIGH status

- P3R2-1: resolved. `ci_check` walks every done row (`lib/ci.sh:70-81`); a row with neither token is refused whatever another row says (`tests/41-ci-wait.sh:175-180`). Residue in another form: a row the parser does not read is not walked (SEC-1).
- P3R2-2: resolved for prose: nothing outside done Status cells is read (probe "commented-out row and prose PR": `PRs read: none`). Inside a Status cell a foreign `/pull/N` is still this repo's PR N (SEC-11, fail-closed in the usual case).
- P3R2-3: resolved. Absent with no workflow file at the record's head passes and is logged; with a file, an unreadable commit, or no repo it is refused (baseline probes; `tests/41-ci-wait.sh:227-256`).
- P3R2-4: resolved. `templates/checkpoint.md:30-34` now states an obligation ("Write `no PR` only for a phase that opened no PR"), pinned at `tests/51-templates.sh:75-76`.

## Acceptance criteria

1. Met. `tests/41-ci-wait.sh:236-237`; probe "baseline absent, wf at head": exit 10.
2. Met. `tests/41-ci-wait.sh:227-229`; probe "baseline absent, no wf at head": pass, logged.
3. Met in part. Met for rows the runner reads: `tests/41-ci-wait.sh:91-102` (other cells, prose), `158-171` (no done row, neither token), `185-198`. Not enforced where a PR is spelled without `#<digit>` beside the words `no PR` (SEC-2) or a row is not read at all (SEC-1).
4. Met. `tests/41-ci-wait.sh:73-83` (green dispatch alone is absent, red dispatch beside green is success, a push run counts).
5. Met as far as this angle read them: the tests above; `docs/spec.md` exit-code row 10, `README.md` row 10, `templates/checkpoint.md:30-34`, `templates/brief.md` section 9, `skills/blast-off/SKILL.md` step 4 state the rules. No test pins SEC-1's second-heading case, SEC-2's cells, a non-sha `head_sha`, or a replace ref.

## New dependencies or reliance

- `gh run list --json databaseId,event`: the `event` field (a gh that does not know it fails the call, and `ci-wait` dies: fail-closed).
- `git ls-tree -r --name-only <sha>^{commit} -- <pathspec>` in the workdir's repo at `done`: the PR's head commit and its trees must be local (a fetch of `pull/<n>/head`); in a partial clone it fetches (SEC-10); it honours replace refs (SEC-5).
- `TOP` (set by `chain_run`) is now read by `ci_check`.
- GNU sed: the `I` flag in `s~...~~Ig` and `-E` (`lib/ci.sh:72`); not POSIX, not BSD sed.
- GNU grep `-a` with `-o -i -E` (`lib/ci.sh:104`); `paste -sd' '`, `sort -un` (coreutils).
- bash `[[ =~ ]]` with the pattern in a variable, and a `while read` fed by process substitution (`lib/ci.sh:70-81`): a failure of `cp_done_cells` is not seen, and reads as "no done row" (refused).
- The current locale's `[:alnum:]` for the `no PR` word boundary (`lib/ci.sh:74`; differs under `LC_ALL=C`, SEC-2).
