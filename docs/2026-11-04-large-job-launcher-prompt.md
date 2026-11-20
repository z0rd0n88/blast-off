<!-- Copied unchanged from VistaMarkets/vbe commit db41485ce (docs/handoff/2026-11-04-large-job-launcher-prompt.md).
It is the original spec blast-off was built from; docs/spec.md is the current design and wins where they differ. -->

# Prompt: build the standalone unattended job launcher

Supersedes the 2026-11-03 draft at
`/home/alex/VistaMobileBE/.claude/worktrees/job-launcher-skill-prompt-83e3c7/docs/handoff/2026-11-03-job-launcher-skill-prompt.md`.
Same shape, re-verified against the transcripts and the job dir on 2026-11-04. Corrections: the usage
limit was visible (a hook fired at 90%), the child cap was a near miss (owner set 30, 29 ran), and five
findings the draft lacked are added (hand-back rate, the killed mutation probe, the reviewer that ran a
server, 68 hidden security-review sessions, the implicit scope confirmation).

Re-aimed 2026-11-04 on the owner's instruction: the deliverable is a standalone unattended job launcher,
not a big-next-job v2 skill. `big-next-job` may call it; it does not depend on it. Section 9 lists every
prior run and retrospective this prompt draws on.

Paste everything below the line into a fresh Claude Code session. It stands alone.

---

## Your task

Build a standalone unattended job launcher: a CLI plus a systemd user service that runs a large
multi-phase coding job as a chain of checkpointed Claude sessions with no Claude session open to drive it.
It starts from a confirmed brief and target set, owns the launch under systemd
(`~/.claude/docs/guides/system-d-guide.md` is the guide; section 8 says where a user-scope WSL box must
deviate), polls child liveness, pauses on a usage limit and resumes after the reset, enforces receipts and
the dirty-tree check itself, watches CI, and posts one summary when done, paused or blocked. It stands
alone: `big-next-job` may call it, and the tool never reads or writes `big-next-job`'s installed files
(`~/.claude/skills/big-next-job`, `~/.agents/skills/big-next-job`). Keep what worked in the MoonPay
on-ramp job (2026-11-01 to 2026-11-02, 29 child sessions, 11 stacked draft PRs) and fix what failed
there, in the vista-sign-in chain (2026-10-31 to 2026-11-01, section 9) and in the MoonPay Step 1 run
before them (2026-10-22 to 2026-10-30, Orca, Antigravity and Codex sessions).

Use `superpowers:writing-skills` to build and test the skill wrapper that invokes the tool and
`writing-for-agents` for its SKILL.md and README prose. Skill frontmatter `description` stays under 1024 characters (aim for about 200);
`hooks/frontmatter-guard.py` enforces it. Commits and PR bodies carry no attribution lines.

## Executive summary

The runner worked: 29 children over 23.5 hours, no crash, no timeout, no stall, every resume clean, and a
re-run after completion was correctly refused. The failures were around it: a target set that left out the
wiring file and the docs a gate reads, so the deliverable is unreachable and CI is red on 8 PRs; a launch
the permission classifier refused; 18 of 29 children ending without closing a phase, 14 of them on a
guessed context figure; review loops that hit the three-round cap in 5 of 7 code phases; a killed
background probe that left mutated source behind; a job marked done with CI unread; and 68 headless
security-review sessions nobody budgeted. Build the standalone launcher by porting the chain mechanics as
they are and changing scoping, the child protocol, the review shape and the close gate. The vista-sign-in
chain adds the case MoonPay did not show: three children in a row died silently and each cost the
four-hour timeout, 12 hours lost (section 9).

## 1. Decide first (ask the owner, one question at a time)

1. **Standalone, decided.** The owner decided 2026-11-04: its own unattended job launcher, not a
   big-next-job v2. `big-next-job` may call it. Do not evolve `big-next-job` in place; port what section 4
   keeps. The chain mechanics need no redesign; every failure below is in scoping, the child protocol,
   review shape, closing, or liveness.
2. **Where does it live?** Ask before scaffolding (`~/.claude/AGENTS.md` rule): a new repo under
   `z0rd0n88`, `z0rd0n88/my-skills` beside `big-next-job`, or `~/.claude/scripts/`. The installed unit
   files go to `~/.config/systemd/user/` whichever repo holds the source; `~/.claude/skills/` entries are
   symlinks into `~/.agents/skills/`, where edits die on the next install.
3. **Codex lanes on by default?** Recommend off, opt-in per job. VistaMobileBE bans Codex (memory
   `no-codex-in-vistamobilebe-sessions`); the MoonPay job's D17 was a one-off owner override.
4. **Per-commit LLM plugins during a job?** `security-guidance@claude-plugins-official` spawned 68
   headless review sessions inside the job worktree, about one per commit. Recommend the launcher lists every hook or plugin
   that spawns an LLM call per commit or per edit and the owner opts each in or out for the job.

Do not change anything until these four are answered.

## 2. Evidence to read (read-only; never resume or modify these sessions)

Read narrowly: grep, then read with offset and limit. The big transcripts are 2 to 9 MB.

| What | Path |
|---|---|
| Current skill | `~/.claude/skills/big-next-job/SKILL.md`, `templates/brief.md` (§9 child protocol), `templates/checkpoint.md`, `scripts/run-job` (94 lines: exit 0 done, 3 blocked, 4 child cap, 5 two stalls) |
| Repo notes for the skill | `/home/alex/VistaMobileBE/.claude/big-next-job.md` |
| Job dir | `/home/alex/VistaMobileBE/.claude/worktrees/moonpay-spec-execution-e56ed2/.big-next-job/`: `brief.md` (30 KB, D1 to D17, §4 target set, §5 phases), `checkpoint.md` (48 KB, 50 open items, about 80 decision rows), `run.log` (maps `child N` to its session id and holds each child's closing message), `run.out`, `phases/` (172 files: ledgers, review reports, fixer JSON, mutation scripts and outputs, PR bodies, stale patches), `gate-logs/` |
| Launcher session ("MoonPay spec execution prompt") | `~/.claude/projects/-home-alex-VistaMobileBE--claude-worktrees-moonpay-spec-execution-e56ed2/8a002496-e07b-4dfb-a432-1f3c5a36dac3.jsonl` |
| The 29 children | same folder, ids from `run.log`. The other 68 sessions there are the security-guidance plugin's `sdk-py` reviews (64 "Review this change for security vulnerabilities", 4 "You previously flagged" second passes) against 63 non-merge commits on the job branches |
| Step 1 retro session ("VistaMobileBE moonpay session logs", Remote Control id 78b6b0) | `~/.claude/projects/-home-alex-orca-workspaces-VistaMobileBE-moonpay/c157b7a4-3124-4b00-a0cb-c728f9995e17.jsonl` (the `/retro` fix list is at 2026-10-30 13:37; the false-claim hook PR #1089 at 20:35) |
| Follow-up session ("moonpay-followups") | `~/.claude/projects/-home-alex-VistaMobileBE--claude-worktrees-new-session-eb21f6/6b957142-a7a0-42bd-9fc7-4df737b2dc20.jsonl` (found Step 1 stack #1068 to #1072 duplicating merged #1010; listed what Steps 2 to 6 still needed) |
| Delivered PRs | VistaMarkets/VistaMobileBE #1120 to #1128, #1130, #1131 (stacked drafts, none merged; #1131 body holds the owner list), plus owner follow-ups #1134 (mount) and #1135 (three-layer test) |
| Claim-check hooks already on `main` | `.claude/hooks/check-test-claim.py` (#1089), `report-receipts.py`, `run-pending-tests.py`, `warn-unenforced-safety-claim.py`, `lib/receipt.py`, `lib/junit_results.py`, `lib/gate_registry.py` |
| Usage hooks | `~/.claude/hooks/usage-checkpoint.py` (thresholds 90 and 97, says "save a checkpoint now, then continue"), `usage-limit-tee.sh` |
| Memories | `run-job-child-background-agents-die`, `headless-claude-bg-wait-ceiling`, `new-sesh-child-needs-systemd-unit`, `review-loop-does-not-converge`, `review-structure-beats-review-rounds`, `merge-guard-blocks-behind-base`, `stacked-pr-merge-path`, `moonpay-onramp-job-2026-11-02-done` |
| vista-sign-in chain (Flutter repo) | `/home/alex/Flutter-mobile-app/.claude/worktrees/vista-sign-in/.big-next-job/` (`run.log`: 28 children over three launches, 3 timeouts, exit 5 then exit 4, done 2026-11-01 15:07Z; `checkpoint.md` 23 KB) |
| Earlier jobs (memory files, no run log) | `big-next-job-2026-10-16-launches` (Jobs 2 and 3 as Orca worktrees), `deposit-job-2026-10-28-launch` (session-switcher, 13 stacked drafts), `vista-app-sign-in-job-scope`; job 3's `/reflect` output: `/home/alex/VistaMobileBE/orca/briefs/2026-10-16-reflect-skill-edits-handoff.md` |
| Unattended-run lessons (memories) | `nested-subagent-notification-routing`, `gate-certifying-its-own-fix`, `mutation-probe-must-assert`, `baton-runner-full-gate-runs-in-manager`, `gradle-xml-report-write-flake`, `piped-gradle-exit-code-lies`, `never-tail-commit-output`, `git-commit-hook-regex-spans-heredocs`, `workflow-script-on-disk-is-not-what-ran`, `hooks-run-from-primary-checkout`, `verify-target-branch-after-merge`, `ci-all-jobs-red-no-steps-is-billing`, `docker-daemon-down-start-from-wsl`, `docker-cli-sigbus-is-desktop-mount`, `gradle-context-mode-redirect` |
| systemd guide | `~/.claude/docs/guides/system-d-guide.md` (system-scope batch template: slices, `MemoryHigh`/`MemoryMax`, `systemd-oomd`, `KillMode=control-group`, journald) |
| Related skills, to avoid duplicating | `baton-runner`, `baton-runner-managed`, `session-switcher` |

## 3. What the MoonPay run measured

State these as facts in the skill's design notes; do not re-derive them.

**Chain.** Launched 2026-11-01 14:24Z by the owner's hand-typed `systemd-run` line, `status: done` at
2026-11-02 13:57Z. 29 children. `JOB_CHILD_TIMEOUT` 14400 s; longest child 3 h 05 m (child 14). The
two-stall detector never fired, and none of the four longest children had an idle gap over 15 minutes.
The owner set `JOB_MAX_CHILDREN=30` by hand; the default is 12, which would have stopped the chain
inside phase 4. `run-job` allows `n <= MAXC`, so two more hand-backs would have ended the job at exit 4
with phase 10 unwritten. The wait loop watches only the Stop hook's `done.json`: a child that dies
without ending its turn (limit error, crash, OOM) is noticed only when `JOB_CHILD_TIMEOUT` expires, four
hours later at the default, and then counts as a stall. A "Try again" on 2026-11-03 was refused because the checkpoint said
done. Model and effort reached the children only because the owner asked: the launcher found
`~/.claude/settings.json` said `sonnet` while the live session ran Opus 5.5.

**Scoping.** Brief written in 10 minutes (13:00 to 13:10). The owner then asked about model and effort,
said usage was at 66%, asked for one PR per phase (became D16) and for Codex on non-critical phases
(D17), then said "launch the job". The §4 target set was never confirmed as its own answer; the launch
instruction was taken as confirming it. The classifier refused the launch (`Create Unsafe Agents` for
`--dangerously-skip-permissions`); the owner ran the printed command 44 minutes later.

**Children per phase and hand-backs.**

| Phase | Children | Ended without closing | Review rounds | Closed by |
|---|---|---|---|---|
| 0 | 1 | 0 | 3 (Codex) | cap |
| 1 | 2 | 1 | 3 | cap, 1 MEDIUM open |
| 2 | 3 | 2 | 3 | cap, 1 MEDIUM open |
| 3 | 5 | 4 | 3 | clean round (0 MEDIUM) |
| 4 | 3 | 2 | 3 | cap, 3 MEDIUM and 1 HIGH to owner |
| 5 | 1 | 0 | 1 (Codex) | gate FAIL on api-guide only |
| 6 | 1 | 0 | 3 (Codex) | gate FAIL on api-guide only |
| 7 | 7 | 6 | 3 | cap, 2 MEDIUM open |
| 8 | 4 | 3 | 3 | cap, 1 MEDIUM open |
| 9 | 1 | 0 | 2 | clean, reviewers cut to 3 for usage |
| 10 | 1 | 0 | 3 (Codex) | docs only, gate skipped |

18 of 29 children ended without closing a phase. 14 said context had passed the brief's one-third mark
"by my estimate"; child 7 wrote "I can't measure it directly". Each new child re-reads the brief and the
checkpoint, about 78 KB together, before doing anything.

**Review decay.** MEDIUM findings per round: phase 2 went 14, 1, 1; phase 3 went 6, 2, 0; phase 7 went 10,
5, 2; phase 8 went 6, 2 (plus 1 HIGH), 1. LOW findings ran 14 to 41 per round and were carried, not fixed.
Phases 7 and 8 ran 6 or 7 reviewers per round. Of the seven lane A code phases, only 3 and 9 closed on
a clean round; 1, 2, 4, 7 and 8 closed on the cap.

**Scope misses.** Files the job needed and §4 did not allow: `gateway/.../Application.kt` (the mount, so
`POST /webhooks/moonpay` is unreachable), the gateway e2e test dir (no three-layer test),
`docs/api/frontend-api-contract.md` (read by the gate's api-guide check, so phases 5 to 9 closed on
`GATE: FAIL` and Docs hygiene CI is red on #1125 and every PR above it, still red on 2026-11-04),
`accounts/build.gradle.kts` (one finding left untested), `logback.xml`, `internal-asyncapi.yaml`, and a
V031 migration (§4 allowed V030 only, so one unique-constraint finding stayed open). The no-widen rule
held every time; the set was wrong.

**Incidents.** Child 2's "read-only" reviewer compiled and ran a Netty test server on a fixed port.
Child 8 ended its turn with 36 mutation probes running in the background because the harness told it to
wait for the notification while the brief said never to end a turn with background work; `run-job` killed
the window and child 9 found a leftover mutation in `OnrampProviderEvent.kt` and restored it by hand.
Child 14 closed phase 4 with "#1124 CI hasn't been read yet"; child 29 closed the job with #1130
build-and-test pending and #1131 CI never read (both later passed). Phases 1 and 3 exceeded the 400-line
soft cap (431 and 430) and recorded the decision not to split.

**Usage.** 66% of the weekly window at launch; `usage-checkpoint.py` fired at 90% inside child 26, which
checkpointed and continued; the phase 9 child cut its reviewers to 3 because usage was near the limit.
The job finished before the limit, but usage pressure changed the process: the phase 9 child also
skipped `finding-fixer`, wrote code before its tests, and its round 1 orchestrator lost its reviewers to
the nested-notification problem, so the manager re-synthesized by hand. `run-job` has no limit handling:
a child that dies on a limit error sits unnoticed until the four-hour timeout, then counts as a stall.
Nothing records usage per phase. The 68 security-guidance sessions were never counted.

**Step 1 before it (from the retro).** The gate was reinvented four times; the Antigravity run claimed
every gate passed with zero JVM tests; the Step 1 stack #1068 to #1072 (63 files, +3145 lines) duplicated
#1010 (64 files, +3146), which had merged the same day, and nobody noticed for five PRs. The retro built
`scripts/gate.sh`, `--continue` in CI, strict YAML checks, a pre-push test compile, the range-diff rule
and the false-claim hook #1089. The owner asked for "checkpoints when usage limit is about to hit", which
became `usage-checkpoint.py`.

## 4. Keep these (they worked, with proof)

1. **Settle every decision before launch.** D1 to D15 as model recommendations in brief §2, D16 and D17
   from the owner, each a numbered table row a child can quote. No child asked the owner anything; new
   gaps were blocked and recorded. Keep "the owner edits §2 or launches as is".
2. **The context pack in brief §3.** Project map, per-phase file lists, gotchas, and conflicts surfaced
   with options. Children stayed inside their phase's lists.
3. **One stacked draft PR per phase, pushed when the phase closes.** 11 reviewable PRs; a limit stop
   would still have left finished PRs visible. Step 1's one big branch is the counterexample.
4. **The chain mechanics.** `run-job` under `systemd-run --user` with tmux and a Stop hook as the return
   channel, checkpoint-driven resume from `Next action`, idempotent re-run. Port it as is; do not
   redesign it.
5. **Doubt review and mutation probes inside each phase.** Phase 4's doubt pass found 2 HIGH; probes
   killed 19 of 20, 35 of 36, 13 of 14 and 17 of 17 (from `run.log` and the phase 9 ledger) with each
   survivor explained. Phase 4's ledger also saw a writer's temporary mutation of `WalletMonitor.kt`
   appear in `git status` mid-run, a second sighting of mutated source in the tree.
6. **One gate script with one verdict line.** `scripts/gate.sh` printing `GATE: PASS|PARTIAL|FAIL
   profile=...`, logs per phase under `gate-logs/`.
7. **Per-phase ledgers with stable finding IDs** (`R2M-1`, `DOUBT4-2`, `DR3-5`) in `phases/`, a sourced
   decisions table, and PR bodies that carry the owner items for that phase.
8. **Lanes with explicit flags.** Lane A (Claude) for money-path phases; lane B (Codex writes, Claude
   reads every diff, writes the cross-user tests and commits) for docs and read routes: 0 failures, 0
   fallbacks on phases 5, 6 and 10. `--model` and `--effort` passed explicitly.
9. **Blocked parts do not stop the job.** Phases 5 to 9 closed with the api-guide failure recorded once
   and the stale patch left in `phases/`; the job kept moving.
10. **The usage hook inside children.** Child 26 saw the 90% warning and acted on it.

## 5. Fix these (what failed, root cause, required change)

1. **Target-set construction.** Root cause: §4 was copied from the handoff's file list, not derived from
   what makes each deliverable reachable or what each gate reads. Required: at scoping, for every
   deliverable name the composition-root or wiring file, its test dir, the build file, and every file a
   gate or CI check reads (contract docs, generated indexes, `ARCH.md`). Put them in the target set or in a
   pre-authorized "may widen to" list. Confirm the target set with the owner as its own question, before
   and apart from the launch instruction (the scope-confirmation rule). A child that hits a gate failure
   caused only by an out-of-set file records it once, leaves the patch in `phases/`, widens only if the
   "may widen to" list allows it, and continues.
2. **Launch.** Root cause: the classifier refuses a session that starts other sessions with
   `--dangerously-skip-permissions`. Required: the tool owns the launch as a systemd user unit (or a
   `systemd-run --user` transient unit) and prints the resolved model, effort, flags, child cap, timeout
   and account before starting; a Claude session hands it a confirmed brief and one start line, plus the
   status and stop commands. Document the permission rule a session needs to start it; never work around
   the classifier. Derive `JOB_MAX_CHILDREN` from the phase count times an expected hand-back factor, and
   make the cap soft: checkpoint, distinct exit code, resumable, never a hard stop one child short.
   Poll the child process for liveness alongside `done.json`, so a child that exits without ending its
   turn is detected within seconds, not at the four-hour timeout.
3. **Hand-backs on a guess.** Root cause: the protocol says "about a third of context" and a child cannot
   measure it. Required: hand back at brief-defined step boundaries (after the doubt pass, after each
   review round, after the gate) or on a measurable signal the builder finds; never on an estimate. Cut
   the per-child re-read: `run-job` warns when `checkpoint.md` passes 150 lines, ledgers and the decisions
   table live in `phases/`, and the checkpoint keeps counts, pointers and only items that block a later
   phase. Record children per phase and hand-back reasons in the final report.
4. **Review loop shape.** Root cause: fixed three rounds with the same reviewer set; LOW findings in the
   loop; 6 or 7 reviewers per round. Memories `review-loop-does-not-converge` and
   `review-structure-beats-review-rounds`: more rounds do not help. Required: LOW findings are recorded,
   never fixed in the loop; each round changes the reviewer shape (different lenses or file subsets);
   at most 3 reviewers per round; a round with nothing above LOW closes the phase; the report counts
   closes by clean round versus by cap. The final owner list is ranked and capped, with the rest in one
   linked file.
5. **Background work and the kill.** Root cause: the Stop hook fires when a turn ends, `run-job` kills the
   window, and anything still running dies, including a probe that had mutated a source file. Required:
   the child protocol forbids ending a turn with any background task or subagent running, and names the
   harness instruction it overrides; mutation scripts restore the file in a trap on SIGTERM and SIGINT;
   `run-job` logs `git status --porcelain` at every child end and refuses to relaunch over a dirty tree
   the checkpoint does not name. Set `CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS=0` for children that fan out.
6. **Reviewer restrictions.** Root cause: "read-only" was prose; the Agent dispatch carried no tool
   restriction. Required: read-only reviewers get an explicit tool allowlist in the dispatch (no Edit,
   Write, or process-starting Bash), and no reviewer starts a server or binds a port.
7. **Done without reading CI.** Required: the last phase closes only after every PR's checks are read
   with one blocking `gh run watch <id> --exit-status` in the background per PR, never a sleep loop.
   Absent checks are not a pass. Each phase close records its PR's check conclusions in the ledger.
8. **Receipts.** Root cause: nothing stopped a child from reporting a green run it did not get (the
   Step 1 retro's biggest gap). Required: a phase closes only on a machine-written receipt (gate log
   path, its verdict line, JUnit tally, commit SHA) that the next child checks before trusting the
   previous phase. Reuse `check-test-claim.py`, `report-receipts.py` and `lib/receipt.py` where the repo
   has them; the skill's fallback writes the same fields itself.
9. **Stale or duplicate work.** Root cause: nothing compared the job against open PRs and recent `main`.
   Required: at launch and at each phase start, list open PRs touching the target set, check `git
   rev-list --count HEAD..origin/main`, and merge `main` in before the gate (memory
   `merge-guard-blocks-behind-base`).
10. **Usage.** Root cause: the chain has no limit handling and no per-phase usage record, and per-commit
    plugins spend usage outside the job's view. Required: on a limit error a child writes the checkpoint
    and exits with a distinct code; `run-job` records `status: paused-limit` with the reset time and
    resumes after it instead of counting a stall. Read `usage-checkpoint.py`'s saved JSON at every phase
    boundary and write the percentage into the checkpoint's phase row. At scoping, estimate usage per
    phase from the last run's record and refuse to launch a job the remaining window cannot cover. List
    every per-commit LLM hook or plugin in the brief with the owner's opt-in or opt-out (decision 4).
11. **Codex lanes.** Off by default; a brief enables them per phase with the owner's override quoted.

## 6. Standing constraints for anything the skill launches

- Safety defaults stay on: dry-run flags, no live submit, no merge, no deploy, no new dependency, no
  invented fee, limit, tolerance or policy. A financial value the docs leave undecided is an owner decision.
- Stacked PRs: `gh pr merge` refuses a PR based on another open PR (memory `stacked-pr-merge-path`).
  The final report says to merge bottom-up and mark drafts ready in that order.
- `.claude/big-next-job.md` stays the per-repo source for gates, reviewers, fixer and phase names.
- No non-ASCII in Kotlin declaration names (VistaMobileBE gates this).
- Children run inside the desktop app's systemd scope unless launched under `systemd-run --user`
  (memory `new-sesh-child-needs-systemd-unit`).

## 7. Done when

1. The four decisions in section 1 are answered and recorded in the skill's notes.
2. Every item in sections 4 and 5 maps to a line in the tool's README, a template, or its runner, with a
   one-line note of where.
3. The runner has runnable checks with fake children: one exits on a limit (expect
   `paused-limit` and a resume after a fake reset), one leaves the checkpoint untouched twice (exit 5),
   one claims PASS without a receipt (refused), one ends with a dirty tree the checkpoint does not name
   (refused), one hits the derived child cap (checkpoint written, distinct exit, resumable), and one
   exits without firing the Stop hook (detected within seconds, not at the timeout).
4. Prompt-only mode, dry-run against a small real job in a throwaway worktree, produces a brief whose
   target set names the wiring file, the test dir, the build file and the gate-read docs for each
   deliverable, and asks for the target set as its own confirmation.
5. Changes land as a draft PR in the repo chosen in decision 2, with `skill-lock.snapshot.json` refreshed
   if a symlink changed. The unit files, the `daemon-reload` step and one smoke start against a throwaway
   job dir are documented; they run on this machine only if the owner says so.
6. Every directive in the guide's §5 template is listed as adopted, dropped or changed, with why
   (section 8), and the owner is told what was verified on this box and what was not.

Measure on the next real run and record in its final report: usage percent at every phase boundary,
children per phase and hand-back reasons, phases closed by a clean round versus by the cap, LOW findings
excluded from the loop, hidden sessions spawned by plugins, and PRs whose CI was read before close.

## 8. The tool's shape and where it deviates from the systemd guide

A standalone CLI plus a systemd user service: starts from a confirmed brief and target set, owns the
launch, pauses on a usage limit and resumes after the reset, watches CI, enforces receipts and the
dirty-tree check itself, and posts one summary when done, paused or blocked. Built in this task.

The guide (`system-d-guide.md`) describes system-scope batch jobs on a server. This box is WSL2, user
scope, 23 GB RAM and 20 cores (`.wslconfig`: 24 GB, 12 GB swap), cgroup v2, `systemd-oomd` running,
`Linger=yes`, no scripted `sudo`. Keep from the guide: `MemoryHigh`/`MemoryMax` sized to this box, not
48 G; `CPUQuota` against 20 cores; `TasksMax`; `KillMode=control-group`; `TimeoutStopSec`; journald
output; one `.slice` for the chain with `ManagedOOMPreference` on the runner. Change or drop, and say
why in the README: everything under `/etc/systemd/system`, `sudo`, `User=`/`Group=` and `[Install]
WantedBy=multi-user.target` becomes `~/.config/systemd/user/` and `systemctl --user` with no `enable`
(a job runner is not a boot-time service); `ProtectHome`, `ProtectSystem=strict` and `NoNewPrivileges`
conflict with `claude` reading `~/.claude` and writing the worktree, `~/.gradle` and the Docker socket;
`PrivateTmp` hides the tmux socket from the owner's `tmux attach`; `Restart=on-failure` would relaunch
the runner on its own blocked, cap and stall exits, so set `RestartPreventExitStatus` for them or omit
`Restart=`. Verify each kept directive on this box (`systemctl --user show -p MemoryCurrent,...`) and
report what was not verified.

## 9. Prior runs and retrospectives this prompt includes

1. **MoonPay Step 1** (2026-10-22 to 2026-10-30; Orca, Antigravity, Codex): the retro in session
   `c157b7a4` and what it built, summarized at the end of section 3.
2. **MoonPay on-ramp chain** (2026-11-01 to 2026-11-02, 29 children): sections 3 to 5.
3. **vista-sign-in chain** (Flutter repo, 8 phases, 2026-10-31 04:32Z to 2026-11-01 15:07Z, 28 children
   over three launches). Children 3, 4 and 5 each hit the 14400 s timeout back to back (08:35, 12:36,
   16:37); 4 and 5 left the checkpoint untouched, so the chain stopped on two stalls (exit 5) with 12
   hours gone. Relaunched, child 8 stalled once and the default cap of 12 stopped it again at 01:02
   (exit 4); relaunched, it finished. The log does not say why the three children died; the chain cannot
   tell a dead child from a slow one. This is fix 2's liveness gap and fix 2's cap rule, measured.
4. **Crypto deposit job** (2026-10-28, from memory `deposit-job-2026-10-28-launch`): run through
   session-switcher in tmux with bypass permissions, no chain; delivered as two draft PRs that the owner
   had split into 13 stacked drafts afterwards. Lesson kept: one PR per phase from the start (keep 3).
5. **Jobs 2 and 3** (2026-10-16, from memory `big-next-job-2026-10-16-launches`): Orca worktrees, one
   Claude agent each, decision logs on the branch; job 3's `/reflect` produced nine skill and agent edits
   and three issues (the handoff file in the evidence table).
6. **Memories** in the evidence table: each is a lesson from one of these runs; the builder reads them
   all and maps each to a line in the tool or records why it does not apply.
