# Phase 9 work: issue #21 (docs: start the launching session in the target repo; move the launcher prompt into blast-off)

Commit: 9f9bec8 (docs: launch from the target repo; copy the launcher prompt into docs (#21))

## What changed

- `skills/blast-off/SKILL.md:25-27`, a paragraph directly under `## Steps`, before step 1:
  "Run this skill in a Claude Code session started inside the target repo (the repo the job changes),
  not in another project's checkout or worktree: a session loads that directory's `AGENTS.md`/`CLAUDE.md`
  and hooks on every turn. If this session started elsewhere, tell the owner before step 5."
- `README.md:55-57`, first paragraph of `## Check, then start`, before the code block:
  "Start the Claude Code session that writes and launches a job inside the target repo (the repo the job
  changes), not in another project's checkout or worktree: a session loads that directory's
  `AGENTS.md`/`CLAUDE.md` and hooks on every turn."
- `README.md:13`, after the `bin/blast-off` line:
  "The original spec blast-off was built from: [`docs/2026-11-04-large-job-launcher-prompt.md`](docs/2026-11-04-large-job-launcher-prompt.md)."
- `docs/2026-11-04-large-job-launcher-prompt.md` (new, 331 lines): a 2-line HTML-comment provenance note and a
  blank line, then `git -C /home/alex/vista-root/vbe show db41485ce:docs/handoff/2026-11-04-large-job-launcher-prompt.md`
  byte-for-byte (checked: `tail -n +4 | cmp` against the source, identical). Note text:
  "Copied unchanged from VistaMarkets/vbe commit db41485ce (docs/handoff/2026-11-04-large-job-launcher-prompt.md).
  It is the original spec blast-off was built from; docs/spec.md is the current design and wins where they differ."
  Secret scan (sk-, ghp_, github_pat_, api key, password, secret, token, bearer, AKIA): one hit, a false
  positive (`disk-is` in the memory name `workflow-script-on-disk-is-not-what-ran`). No secrets.
- `tests/70-docs.sh:66-71`: new #21 check. The flattened README and SKILL.md each contain
  `inside the target repo (the repo the job changes)`; the docs file exists; README links it.
- `docs/spec.md:256`: the 70-docs row names the new check (#21).

## Red

`  | FAIL: README does not say 'inside the target repo (the repo the job changes)'`
(`GATE-ONLY: FAIL passed=1 failed=1 shellcheck=ok only=70-docs,51-templates`)

## Green

`GATE-ONLY: PASS passed=2 failed=0 shellcheck=ok only=70-docs,51-templates`

Only 70-docs reads the repo's README.md / SKILL.md (other README hits in tests are fixtures). After the
runs, `grep ExecStart ~/.config/systemd/user/blast-off@.service` still reads
`ExecStart=/home/alex/blast-off/.worktrees/blast-off-build/bin/blast-off run %f`.

## Split check

`git diff --stat origin/main...HEAD`: 5 files changed, 347 insertions(+), 1 deletion(-). 331 of those are
the verbatim docs copy; code and test lines are 6 (tests/70-docs.sh). Well under 750: no split.

## Reviewer should check

- Placement: SKILL.md puts it as a lead paragraph under `## Steps` (it applies before step 1 reads the repo's
  AGENTS.md). README puts it at the top of `## Check, then start`. The SKILL.md second sentence ("tell the
  owner before step 5") is my addition so the agent knows what to do when it is already in the wrong place;
  cut it if the brief meant one sentence only.
- 70-docs lints nothing under docs/ (no link, em dash, line length or banned-word checks), so the verbatim
  copy needed no exclusion. The copy keeps whatever em dashes/curly quotes the original has; none were edited.
- Provenance note is an HTML comment so the rendered file still opens on the original `# Prompt:` heading.
- Not changed, out of scope: `docs/spec.md:8` still cites the source as
  `VistaMobileBE/docs/handoff/2026-11-04-...`; it could now point at the docs/ copy.
- A PostToolUse hook asked for `skill-sheriff-cc` on the edited skill before commit; that skill is not
  available in this session, so it was not run.
