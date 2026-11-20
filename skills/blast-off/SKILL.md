---
name: blast-off
description: Use when a multi-phase coding job should run unattended as a chain of Claude sessions under systemd ("blast off", "run this overnight with blast-off", "write a blast-off brief"); not for quick edits.
---

# blast-off

blast-off runs a **job dir** (`brief.md` + `checkpoint.md`) as a chain of checkpointed Claude
sessions in a systemd user unit; no session stays open to drive it. This skill turns the owner's
request into that job dir and hands the owner the start line. The owner starts the job.

`blast-off` below is the command on `PATH`, else `bin/blast-off` two directories above this file
(`readlink -f` through a symlinked skill dir). The repo's `README.md` holds exit codes, watch and
resume; `templates/` holds the brief and checkpoint you fill.

## Pick the mode

- **Prompt-only** ("write/draft the brief"): steps 1 to 5 below, delivering `brief.md` and
  `checkpoint.md` as text or at a path the owner names. No worktree, no preflight, no launch. Decisions
  the owner has not answered go in brief §2 marked as your recommendations.
- **Run** ("run it", "blast off", "start the job"): steps 1 to 8.

## Steps

Run this skill in a Claude Code session started inside the target repo (the repo the job changes),
not in another project's checkout or worktree: a session loads that directory's `AGENTS.md`/`CLAUDE.md`
and hooks on every turn. If this session started elsewhere, tell the owner before step 5.

1. **Scope read-only.** The repo's `AGENTS.md`/`CLAUDE.md`, `ARCH.md`, `.claude/big-next-job.md`
   (project notes: sources of truth, gate, review tooling), the specs the job touches, open PRs.
2. **Build the Target set.** For each deliverable name: its wiring or composition-root file, its test
   dir, the build file, and every file a gate or CI check reads (contract docs, generated indexes,
   `ARCH.md`). Anything a phase might need beyond that goes on a "may widen to" list.
3. **Confirm the Target set** with the owner as its own question, apart from and before any launch
   question: the exact paths, then the may-widen list. Done when the owner answers that question.
4. **Settle the rest**, one question at a time, each with your recommendation: phases and their
   "done when", the gate command (its last output line `GATE: PASS` or `GATE: FAIL`), delivery (one
   stacked draft PR per phase, never merged; a phase that opens no PR says `no PR` in brief §5 and closes its row with `no PR`; when a
   PR gets no CI runs, `blast-off ci-wait` records `absent` and exits 10, and the runner lets `done`
   through, logged "absent, not a pass", only where that PR's head commit has no file under
   `.github/workflows/`: ask whether the repo's workflows start on the stacked PR branches, and
   put the answer in brief §2; if none starts on them, tell the owner before launch that such a PR is
   refused at `done` with no override and that `no PR` is no way out, that the PR base and the
   trigger filter are theirs to change, and record their choice there too),
   per-commit LLM plugins opt-in or out (look in `.claude/settings.json` `enabledPlugins`,
   `git config core.hooksPath`, `.git/hooks`), and `CLAUDE_FLAGS`. `CLAUDE_FLAGS` is the owner's string, verbatim: it must hold `--model` and
   `--effort`; you add nothing to it.
5. **Write the job dir.** Workdir = a dedicated worktree on a feature branch
   (`git worktree add <repo>/.worktrees/<name> -b <branch> origin/<base>`); its name (letters,
   digits, `-`, `_`) names the unit `blast-off-<name>` and the tmux session `job-<name>`. Job dir =
   `<worktree>/.big-next-job/`, directly inside it (the workdir is the job dir's parent), excluded with
   `echo .big-next-job/ >> "$(git rev-parse --git-common-dir)/info/exclude"`. Fill every section of
   `templates/brief.md` (§9 Child protocol verbatim; the confirmed Target set in §4). From
   `templates/checkpoint.md`: `status: running`, `phase: 0 of N`, one Phase plan row per phase keyed
   `0`, `1`, `2`..., each from the left margin, the first `Next action`, and its HTML comment kept.
6. **Preflight**: `CLAUDE_FLAGS='<owner flags>' blast-off preflight <job-dir>`. Fix what a
   `preflight: refused` line names before going on; a usage estimate over what the 7-day window has
   left is the owner's call: report it and stop.
7. **Hand over** these two blocks, filled in, then the phase table and the first phase's plan. The
   first starts the job; the second's lines are for later, one at a time:

   ```bash
   export GH_TOKEN CLAUDE_FLAGS='<owner flags>'
   blast-off start <job-dir>          # transient unit blast-off-<name>.service
   ```

   Tell the owner with it: when the shell that runs `start` has `OPENROUTER_API_KEY` (an OpenRouter
   `sk-or-` key), `start` passes it to the unit by name and Jev then picks `--model` and `--effort` for
   each phase in place of those in `CLAUDE_FLAGS` (its other flags stay; a pick below `JOB_JEV_MIN_CONF`,
   default 0.7, keeps them); `JOB_JEV=0`, exported before `start`, keeps `CLAUDE_FLAGS` for every phase.
   Step 6's `level` line is preflight's own Jev call from your environment, a forecast: the runner asks
   again with the environment `start` passes from the owner's shell, so the two can differ.

   ```bash
   blast-off wait <job-dir>     # to watch: a background command; returns on a change, prints one line
   blast-off status <job-dir>
   tmux -L blast-off-<name> attach -t job-<name>   # watch the live child
   blast-off stop <job-dir>
   ```

8. **End your turn.** The chain runs without you. Asked to watch it, run `blast-off wait <job-dir>` after
   `start` (or `resume`) returns, as a background command, never a recurring loop or cron; it watches the
   unit, so before `start` it reads as stuck. When it returns, exit 11 means run it again, 0 means the
   runner accepted the job's end, `done` or `blocked`, 12 means nothing is running, or the job could not
   be read for 60 s, and the owner must act (the line says why; `run blast-off resume` at `paused-cap`),
   1 means it could not start watching (wrong job dir, a missing or empty `checkpoint.md`, a bad
   `BLAST_OFF_WAIT_POLL`, no systemd user bus; the reason is on stderr): rerun it once unchanged only
   when the cause can clear on its own (`checkpoint.md` empty mid-rewrite, a bus hiccup), else fix it
   first (README, Watch).

## The start line and permissions

The owner runs `blast-off start`. You run it only when the owner asks you to and has added an allow
rule for its command text to `permissions.allow` in the session's project `.claude/settings.json`: `"Bash(blast-off start:*)"`,
or the absolute-path form if that is how you call it. Type it bare, `blast-off start <job-dir>`: the rule
does not match past a `CLAUDE_FLAGS=...` prefix, so `GH_TOKEN` and `CLAUDE_FLAGS` must already be in
your environment (exported before `claude` started, or `CLAUDE_FLAGS` in that settings file's `env`). When the auto-mode classifier denies it, that is
final: the owner runs it with `! CLAUDE_FLAGS='<owner flags>' blast-off start <job-dir>`
(`GH_TOKEN` exported) or step 7's export and start lines in a terminal. Hand over `blast-off start`, not
`systemctl --user start blast-off@...`: a template instance gets no `CLAUDE_FLAGS` and exits 1.

## Common mistakes

| Mistake | Instead |
|---|---|
| Target set confirmed inside the "go" question | its own question, before launch (step 3) |
| `phase: 1 of 2`, rows keyed from 1 | the template numbers from 0 |
| Flags added to `CLAUDE_FLAGS` (`--allowedTools`, permission bypasses) | the owner's string as given |
| Job dir nested deeper than the worktree root | `<worktree>/.big-next-job/`: `start` takes no workdir |
| A gate whose last line is not a `GATE:` line | `blast-off receipt` refuses it and done rows exit 9 |
| Removing the blast-off checkout while a job runs | the unit runs `bin/blast-off` from that path |
