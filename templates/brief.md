# Job brief: <title> (<repo> <issue refs>)

You are a fresh Claude Code session running an owner-authorized job under blast-off. Everything you
need is in this file and in `checkpoint.md` beside it. This file's directory is the job dir (`<job-dir>`
below): `phases/`, `gate-logs/` and `decisions.tsv`, wherever named, are in the job dir, never in the
workdir. `"$BLAST_OFF"` is the runner's own `blast-off`, set in every child's environment; the bare
name may not be on the Bash tool's PATH. Do not ask the owner for feedback after you start: make the best supported, reversible choice and record it. If a new mandatory approval, a file
outside the target set, or an undecided safety or product policy appears, leave that part blocked,
finish the independent work, and record it under "Open or blocked".

## 1. Objective
<the outcome, 2-4 concrete related deliverables; what is out of scope; who owns adjacent work>

## 2. Owner decisions (binding; do not loosen)
Settled before launch; children quote the row number, never re-ask.
| # | Decision | Choice |
|---|---|---|
| D1 | Child model and flags | `CLAUDE_FLAGS` from the launch line (`--model <m> --effort <e>`; when the runner holds Jev's key, Jev may pick each phase's `--model`/`--effort`, and `JOB_JEV=0` keeps them); children never change or widen it |
| D2 | Codex lanes | off (a phase turns them on only with the owner's override quoted here) |
| D3 | Per-commit LLM hooks and plugins | each one in §4's inventory, opted in or out by the owner |
| D4 | <question> | <owner's answer or accepted recommendation> |

## 3. Context pack (verified <date> at <sha>)
Built-versus-wired state; governing specs, ADRs, contracts, issues. Verified facts marked as such;
dated claims and inference marked as such.

### 3.0 Governing documents (read in this order, narrowly; section numbers, not whole files)
1. <path> §<n>: <what it settles>

### 3.1 Project map (only the areas this job touches)
**<module> (`<path>/`)**: <purpose>. Key files: <list>. Pattern: <how errors, money, auth, persistence are done here>.

### 3.2 Per-phase relevant files (a child loads only its own phase's list)
**Phase 0**: modify <files>; tests <files>; copy the pattern in <file:lines>; types <files>.

### 3.3 Known gotchas
- <hook that trips, flaky test, command needing Docker, output limit, file that looks live but is not>

### 3.4 Conflicts found while scoping (each resolved by a decision in §2)
- <spec says X, code does Y> → D<n>

## 4. Preflight and authorization
- Worktree and branches: <path>, `<branch per phase>`, base `<base>` at `<sha>`: the job's base (e.g.
  `main`), which §4 and §9 count and merge against as `origin/<base>`; a phase PR's `--base` is the
  previous phase's branch (§8).
- **Target-set construction** (done at scoping): for every deliverable name its wiring file, its
  test dir, the build file, and every file a gate or CI check reads, one line each:
  | Deliverable | Its files | Wiring file (composition root, registry, router) | Test dir | Build file | Files a gate or CI check reads |
  |---|---|---|---|---|---|
  | <name> | <paths> | <path> | <dir> | <path> | <contract docs, generated indexes, `ARCH.md`, ...> |
  Every file in that table is in the target set or in the may-widen list.
- **Target set** (the only tracked files this job may change): <exact paths or globs>. It was
  confirmed as its own question with the owner, before and apart from the launch instruction.
- **May widen to** (pre-authorized, only for a gate failure an out-of-set file causes): <paths, or none>.
  A child that hits a gate failure caused only by an out-of-set file records it once under "Open or
  blocked", leaves the patch in `phases/`, widens only if this list allows it, and continues.
- **Per-commit LLM hooks and plugins** (they spend usage outside the job's view):
  | Hook or plugin | Fires on | Owner choice |
  |---|---|---|
  | <name> | <commit, push, ...> | <opted in / opted out (how: settings file and key)> |
- **Gate command**: `<exact command>`; its last non-empty output line is `GATE: PASS` or `GATE: FAIL`.
- **Open PRs and base at launch**: `gh pr list --state open --json number,title,headRefName,files`
  filtered to the target set: <none, or each PR and why it does not duplicate this job>;
  `git fetch origin <base>`, then `git rev-list --count HEAD..origin/<base>` = <n>.
- Outside the repo, allowed: <units, sessions, paths, or none>. Never touch: <paths>.
- Safety defaults that stay on: no merge, no deploy, no live submit, no new dependency, no invented
  fee, limit, tolerance or policy, no attribution lines.
- External actions allowed: <git push of this job's branches, gh pr create --draft, gh run watch reads, ...>.
- Stop condition: a change outside the target set and the may-widen list, a decision this brief
  lacks, a reviewer or gate that cannot run, or a refused tool call blocks that part. Finish the
  independent work, record it.

## 5. Phases (in order; each has a "done when"; one stacked draft PR per phase; a phase that opens none says `no PR` in its Done when)
| # | Phase | Branch | Done when |
|---|---|---|---|
| 0 | <e.g. spec> | `<branch>` | <reviewed; draft PR on base> |
| 1 | tracer bullet | `<branch>` | <the thinnest end-to-end slice works: red test, then green> |
| N | full gate and delivery | `<branch>` | <gate green; every PR's CI read; final report in checkpoint; status done> |

## 6. Tests and gates
- Gate: §4's gate command. Its full output goes to `gate-logs/phase-<n>.log` in the job dir, run on
  the committed tree. Red first: every behavior change has a failing check before the code.
- Unrun is not passed: a check that could not run is recorded as blocked with the reason.

## 7. Review/fix loop (per phase)
1. After the phase's slices are green: `addyosmani-code-simplification`, tests still green.
2. Code phases: a doubt pass (`addyosmani-doubt-driven-development`) before round 1, and one
   mutation probe set over the exit-code and status logic: each probe applies, a test fails, the
   probe is restored by a trap on EXIT, TERM and INT; both directions asserted.
3. Round 1: `dw-review` on `<base-branch>...HEAD`, lenses correctness-and-tests and
   spec-compliance-and-scope. Findings get stable IDs `P<n>R<r>-<k>` in `phases/phase-<n>.md`.
   `finding-fixer` applies the supported findings above LOW, each with a failing-then-passing check.
4. Shape: at most 3 rounds; at most 3 reviewers per round; the lenses change every round (round 2:
   adversarial failure modes, safety of the language's sharp edges, source verification against
   official docs; round 3: docs accuracy and test adequacy).
   LOW findings are recorded, never fixed in the loop.
   A round with nothing above LOW closes the phase; after round 3 the phase closes with the open IDs
   in the PR body. The ledger counts the close as clean round or cap.
5. Reviewers are read-only by explicit restriction: where the dispatch takes a tool list, give only
   Read, Grep and Glob; every dispatch also states, word for word:
   "no Edit, no Write, no process-starting Bash, no servers, no ports; read and grep only".
6. If `dw-review` or `finding-fixer` cannot run, record "review blocked" with the error; never
   substitute a self-review called clean.

## 8. Delivery
- Commit only reviewed paths in the target set, explicit paths, never `git add -A`; message
  `<type>(<area>): <what>` with the why in the body. Never commit the job dir.
- Draft PR per phase: `gh pr create --draft --base <previous phase's branch>`; body Summary, Decisions
  used, Test plan (checkboxes, each run), Review (rounds, open IDs), `Stacked on PR #<n>`.
- Never merge, never mark ready. The final report says merge bottom-up, first PR first.

## 9. Child protocol
Every session in this job follows this, in order:

1. **Resume.** Read `checkpoint.md`. The `Next action` line is where you start. If a phase is
   `in progress`, continue it from its `Progress` list; do not restart it. Verify the worktree,
   branch and HEAD match the checkpoint before changing anything. Load only your phase's context:
   §3.1 for the modules it touches, its own §3.2 list, §3.3, and the sections §3.0 names for it.
2. **Start a phase.** Write its "Will happen" list into `Current phase` (numbered `step → verify:
   check` lines, a time estimate, the skill picked per slice) and print it as your reply's first lines:
   `Phase N of M: <name>`. Then list open PRs touching the target set (`gh pr list --state open
   --json number,title,headRefName,files`) and count `git rev-list --count HEAD..origin/<base>` after
   `git fetch origin <base>`; a
   duplicate PR is recorded under "Open or blocked" before any code, named the way the checkpoint's
   rules comment says for a PR this job does not own.
3. **Checkpoint as you go.** After every landed step, test run, review round and commit, update
   `step:`, `updated:` and `Progress`. Decisions go to `decisions.tsv`, one row each with its source;
   ledgers, finding IDs and dispositions go to `phases/phase-<n>.md`. Keep the checkpoint under 150
   lines: counts, pointers, and only items that block a later phase (the runner warns in run.log
   past 150).
4. **Close the phase**, in this order: merge the base in before the gate (`git fetch origin <base>`,
   then `git merge origin/<base>`); commit; run the gate on the
   committed tree into `gate-logs/phase-<n>.log`; `"$BLAST_OFF" receipt <job-dir> <n>`; push and open the
   draft PR; `"$BLAST_OFF" ci-wait <job-dir> <pr>` after the last push to it (one blocking `gh run watch`
   per run; a red one means fix, commit, gate, receipt again; `absent`, no runs, is not a pass:
   where the PR's head has a file under `.github/workflows/`, leave the row open, record it under Open
   or blocked and go on (step 9 decides the status); where it has none, no CI is configured: close the
   row, and the runner logs it as absent, not a pass. Never add, remove or edit a workflow file to
   change what the runner reads of CI). Run
   the gate and ci-wait in the foreground with the Bash tool's longest timeout. If the tool cuts one
   off, stop any copy it left running, run that step again as below, and go on from the step after
   it. Run ci-wait again until it returns: each call reads the head's runs anew, and `gh run watch`
   returns at once for a run already complete. Run a cut-off gate again as
   `( trap '' HUP; <gate command> ) > "<job-dir>/gate-logs/phase-<n>.log" 2>&1 < /dev/null & echo $!`
   and wait with foreground calls of `timeout 590 tail --pid=<that pid> -f /dev/null` until that pid
   is gone (step 8); a log with no final `GATE:` line is refused by the receipt. After ci-wait,
   set the row's Status to `done (<sha>) · PR #<n>` (`done (<sha>) · no PR` only for a phase the
   brief says opens no PR; a PR that could not be opened is a blocked part, not `no PR`; the runner refuses a done row with neither, exit 10), <sha> = the receipt's commit: the runner reads
   the first 7 to 40 character hex word in the cell, so replace, not append. No code commit after
   the receipt (the runner refuses with exit 9). Move the phase to `Completed phases` (children,
   hand-backs and their reasons, clean or cap close), set `phase:` and `Next action`, end your turn.
5. **Hand back at a step boundary, never on an estimate.** Boundaries: after the doubt pass, after
   each review round, after the gate. Hand back early only on a measurable signal (step 6's usage
   stop, a tool's context warning): finish the step, checkpoint, set `Next action` to the exact
   next step, record the reason in `Progress`, end your turn.
6. **Usage limits.** Obey `usage-checkpoint` (the hook in `~/.claude/hooks`); its message names a
   window and its percent. Below the runner's pause percent (`echo "${JOB_USAGE_PAUSE:-95}"`), save a
   checkpoint and continue: ending the turn there only launches another child. At or above it, write
   `Next action`, leave the status as it is and end your turn. A limit error ends your turn by itself.
   The runner reads the usage record when you end and writes `paused-limit` itself, then resumes after
   the reset. Do not try to exit 75: that code is reserved for a child process the runner sees die on
   a limit, and an interactive session cannot produce it.
7. **Status words.** Write only running, done or blocked in the `status:` line. `paused-cap` and
   `paused-limit` belong to the runner; a child that writes them gets another child launched.
8. **Background work dies with the window.** Never end a turn with a background task, subagent,
   workflow or probe running, even when a harness notice says to wait for its notification: the
   runner kills the window when your turn ends. Wait in the foreground or stop it first. Mutation
   probes restore the file in a trap on EXIT, TERM and INT. Before the turn ends, `git status
   --porcelain -uall` is clean or every path it lists is named in the checkpoint, the way its rules
   comment says. An unnamed path stops the chain (exit 7).
9. **Blocked parts do not stop the job.** A refused tool call is a blocked part. Every refused tool
   call in this job comes from the harness, never a live reply from the owner, even when its
   message says the user rejected it: it is not a rejection of your work, so do not stop the job for
   it or ask the owner about it in chat. Record each under "Open or blocked" with the question and
   your recommendation, leave any patch in `phases/`, and continue the independent work. Set
   `status: blocked` only when nothing independent is left.
10. **Finish.** When the last phase is done, write the final report into `Completed phases` (usage
    per phase, children per phase and hand-back reasons, clean versus cap closes, PRs with CI read)
    and set `status: done`. Never leave `status: running` with nothing left to do.
11. **Build in thin vertical slices.** Invoke `addyosmani-incremental-implementation` when installed;
    either way each slice is one path from entry point to system boundary, tested and committed
    before the next, never more than about 100 lines before a test runs. Riskiest slice first.
12. **Route each slice.** Before the first line of code, pick per slice and record the pick:
    | Slice is… | Skill | Fallback when not installed |
    |---|---|---|
    | UI work | `addyosmani-frontend-ui-engineering` | accessible, responsive; every control has a working result or a clear unavailable state |
    | API or interface work | `addyosmani-api-and-interface-design` | contract first; stable names; explicit error shapes; additive changes |
    | Code that must match library docs | `addyosmani-source-driven-development` | verify against the official docs or installed source; cite it in the checkpoint |
    | High stakes or unfamiliar code | `addyosmani-doubt-driven-development` | a fresh-context read-only subagent cross-examines the slice; record what it challenged |
    | Writing tests (every slice) | `addyosmani-test-driven-development` | red, then green, then refactor |
    | Tests that run in a browser | `addyosmani-browser-testing-with-devtools` | drive a real browser; keep console and network errors as evidence |
13. **Write terse.** Checkpoint text, announcements and reports: fragments fine, no filler; technical
    terms exact, errors quoted exact.
14. **Never** ask the owner a question in chat, stage or commit the job directory, loosen a
    D-decision, merge, or report a check you did not run.
