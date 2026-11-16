# Skill Sheriff: blast-off
Docs fetched 2026-11-15: https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview.md, https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.md, https://code.claude.com/docs/en/skills.md
Summary: 0 Fail, 3 Gap, 42 Pass, 3 N/A, 3 Can't verify (of 51 ledger rows)

Target: `skills/blast-off/` (one file, `SKILL.md`, 88 lines; body 83 lines, 831 words; description 199 characters). Surface: Claude Code. `README.md:26` installs the skill with `ln -s ~/blast-off/skills/blast-off ~/.claude/skills/blast-off`, and the repo has no plugin manifest, so rows are judged by the Claude Code docs where the two surfaces differ, and no plugin, API or SDK page was fetched. Linked files read: `README.md`, `templates/brief.md`, `templates/checkpoint.md` (all at the repo root, outside the skill folder).

## Fail

None.

## Gap

### Description says what the skill does and when to use it (Recommended on Claude Code; Required on the platform)
Evidence: `SKILL.md:3`. The description (199 characters) is one when-clause, from its first words `Use when` to its last `not for quick edits`. It names the situation and three trigger phrases but never states the skill's own action, which the body gives at `SKILL.md:9-10` (it turns the owner's request into the job dir and hands over the start line). Surface split: Claude Code, where this skill ships, marks the field Recommended, so this is a Gap; uploaded to claude.ai or the API the same text would be a Fail against the platform's wording.
> "What the skill does and when to use it." — https://code.claude.com/docs/en/skills.md § Frontmatter reference
> "The `description` must include both what the Skill does and when Claude should use it." — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview.md § Skill structure
Fix: put one what-clause before the when-clause, for example `Writes a blast-off job dir (brief.md and checkpoint.md), runs preflight and hands the owner the start line. Use when ...`. The result stays far below both length limits.

### Table of contents in reference files over 100 lines (Recommended)
Evidence: `SKILL.md:13-14` sends Claude to the repo's `README.md` (exit codes, watch, resume) and to `templates/`. `README.md` is 153 lines and `templates/brief.md` is 187 lines; neither opens with a contents list (`README.md:1-12` is an overview and three links to other files; `templates/brief.md:1-9` is the child's preamble). `templates/checkpoint.md` is 58 lines, under the threshold. Both long files sit outside the skill folder; they are in scope because `SKILL.md` names them as the material to read and fill.
> "For reference files longer than 100 lines, include a table of contents at the top." — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.md § Structure longer reference files with a table of contents
Fix: add a short contents list (the `##` section names) at the top of `README.md` and of `templates/brief.md`, or have `SKILL.md:13` name the README sections it means (`Exit codes`, `Watch, stop, resume`).

### At least three evaluations (Recommended)
Evidence: measure lists `files: ["SKILL.md"]`; the skill folder has no `evals/` directory and no evaluation file. `tests/70-docs.sh:6-30` greps `SKILL.md` for its frontmatter and hand-over lines, which checks the text, not what a Claude session does with the skill.
> "At least three evaluations created" — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.md § Checklist for effective Skills
Fix: add three evaluation scenarios in the skill folder (a prompt-only brief request, a run request, and a quick edit that should not trigger the skill), each with its expected behavior.

## Pass

- SKILL.md with YAML frontmatter: `skills/blast-off/SKILL.md:1-4`.
  > "Every Skill requires a `SKILL.md` file with YAML frontmatter" — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview.md § Skill structure
- Frontmatter opens on line 1: measure `frontmatter_starts_line_1: true`.
  > "Claude Code reads the frontmatter only when the opening `---` is the file's first line." — https://code.claude.com/docs/en/skills.md § Frontmatter reference
- Field names match the reference table: measure `frontmatter_fields: name, description`.
  > "A field name must match the table exactly, hyphens included" — https://code.claude.com/docs/en/skills.md § Frontmatter reference
- Frontmatter YAML parses: `yaml.safe_load` of `SKILL.md:2-3` returns the keys `description` and `name`, description 199 characters.
  > "If the YAML between the markers doesn't parse, the skill still loads with no fields set" — https://code.claude.com/docs/en/skills.md § Frontmatter reference
- `name` and `description` present: both set at `SKILL.md:2-3`, so the row passes on the platform (which requires them) and on Claude Code (which does not).
  > "**Required fields:** `name` and `description`" — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview.md § Skill structure
  > "All fields are optional." — https://code.claude.com/docs/en/skills.md § Frontmatter reference
- `name` at most 64 characters: measure `name_chars: 9`.
  > "Maximum 64 characters" — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview.md § Skill structure
- `name` uses lowercase letters, numbers and hyphens: `blast-off`; measure `name_chars_outside_a-z0-9-: []`.
  > "Must contain only lowercase letters, numbers, and hyphens" — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview.md § Skill structure
- `name` has no reserved word: `blast-off` holds neither word.
  > "Cannot contain reserved words: `anthropic`, `claude`" — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview.md § Skill structure
- No XML tags in `name` or `description`: measure `xml_like_tags_in_frontmatter: []`.
  > "Cannot contain XML tags" — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview.md § Skill structure
- `name` has no character Claude Code refuses: nine ASCII characters, `a-z` and one hyphen.
  > "Claude Code refuses a command name or a frontmatter `name` that contains characters such as these" — https://code.claude.com/docs/en/skills.md § Characters a skill name can't hold
- Folder not named `synced`: measure `dir_name: blast-off`.
  > "don't name a skill folder `synced`, in any capitalization" — https://code.claude.com/docs/en/skills.md § Choose where skills load
- Folder not named `anthropic-skills`: measure `dir_name: blast-off`.
  > "outside a plugin, a skill folder or command file whose name is `anthropic-skills` or starts with `anthropic-skills:` doesn't load" — https://code.claude.com/docs/en/skills.md § Choose where skills load
- `description` non-empty: measure `description_chars: 199`.
  > "Must be non-empty" — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview.md § Skill structure
- `description` length: 199 characters, under the platform's 1,024 limit and under Claude Code's 1,536 listing cut-off (measure `description_plus_when_to_use_chars: 199`).
  > "Maximum 1,024 characters" — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview.md § Skill structure
  > "the combined `description` and `when_to_use` text is truncated at 1,536 characters in the skill listing to reduce context usage" — https://code.claude.com/docs/en/skills.md § Frontmatter reference
- `description` in third person: `SKILL.md:3` has no first- or second-person wording; it uses the imperative `Use when`, the form the docs' own examples use.
  > "Always write in third person" — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.md § Writing effective descriptions
- `description` specific, with key terms: `SKILL.md:3` names multi-phase coding job, unattended, chain of Claude sessions, systemd, three quoted trigger phrases and one exclusion.
  > "Be specific and include key terms" — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.md § Writing effective descriptions
- Key use case first: `SKILL.md:3` opens with the use case; trigger phrases and the exclusion follow.
  > "Put the key use case first" — https://code.claude.com/docs/en/skills.md § Frontmatter reference
- Name pattern: `blast-off` is not a gerund; it is the action-oriented form the same section lists as an acceptable alternative, matches the command the skill drives (`SKILL.md:12`), and is neither vague nor generic.
  > "Consider using **gerund form** (verb + -ing) for Skill names" — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.md § Naming conventions
- Concise body: 83 lines, 831 words (measure). Every paragraph is about blast-off's own commands, files and rules; nothing explains git, systemd or tmux in general. The longest single item is the delivery clause at `SKILL.md:33-37`.
  > "Only add context Claude doesn't already have." — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.md § Concise is key
- Specificity matches fragility: scoping is free text (`SKILL.md:25-31`); the fragile steps give exact commands (`SKILL.md:42`, `45`, `49`, `56-63`) and forbid additions to `CLAUDE_FLAGS` (`SKILL.md:39-40`).
  > "Match the level of specificity to the task's fragility and variability." — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.md § Set appropriate degrees of freedom
- Body under 500 lines: measure `body_lines: 83`.
  > "Keep the `SKILL.md` body under 500 lines for optimal performance." — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.md § Progressive disclosure patterns
- Progressive disclosure: `SKILL.md` holds the procedure; exit codes, watch and resume stay in `README.md`, and the brief and checkpoint bodies stay in `templates/` (`SKILL.md:13-14`).
  > "`SKILL.md` serves as an overview that points Claude to detailed materials as needed" — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.md § Progressive disclosure patterns
- Supporting files referenced with what they hold: `SKILL.md:12-14` says where `bin/blast-off`, `README.md` and `templates/` are and what each is for; `SKILL.md:46-48` says when the two templates are filled.
  > "Reference supporting files from `SKILL.md` so Claude knows what each file contains and when to load it" — https://code.claude.com/docs/en/skills.md § Add supporting files
- References one level deep: `README.md`, `templates/brief.md` and `templates/checkpoint.md` are each named in `SKILL.md` itself (`SKILL.md:13-14`, `46-47`); the templates link no further file, and what `SKILL.md` sends Claude to the README for (exit codes, watch, resume) is in the README itself (`README.md:83-135`).
  > "Keep references one level deep from `SKILL.md`" — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.md § Avoid deeply nested references
- Workflow in clear sequential steps: eight numbered steps (`SKILL.md:25-66`), with the mode choice saying which steps apply (`SKILL.md:18-21`).
  > "Break complex operations into clear, sequential steps." — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.md § Use workflows for complex tasks
- Feedback loop: step 6 runs `blast-off preflight` and has Claude fix what a `preflight: refused` line names before going on (`SKILL.md:49-51`).
  > "Run validator → fix errors → repeat" — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.md § Implement feedback loops
- Validation steps for critical operations: the Target set is confirmed as its own question before any launch question (`SKILL.md:30-31`); preflight runs before the hand-over (`SKILL.md:49-52`).
  > "Validation/verification steps for critical operations" — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.md § Checklist for effective Skills
- No time-sensitive information: `SKILL.md` has no date, version number or before/after condition.
  > "Don't include information that will become outdated" — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.md § Avoid time-sensitive information
- Consistent terminology: `job dir`, `workdir`, `Target set`, `owner` and `CLAUDE_FLAGS` each keep one meaning from first use to last (`SKILL.md:8`, `27`, `41`, `10`, `39`). One mixed pair: a chained session is `sessions` in the prose (`SKILL.md:9`) but `child` at `SKILL.md:46` (the brief template's `Child protocol` heading) and `SKILL.md:62` (`the live child`).
  > "Choose one term and use it throughout the Skill" — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.md § Use consistent terminology
- Templates for output format: `templates/brief.md` and `templates/checkpoint.md`, with how strictly to follow them (`SKILL.md:45-48`), plus the two hand-over blocks (`SKILL.md:55-64`).
  > "Provide templates for output format." — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.md § Template pattern
- Concrete examples: full command lines with named placeholders (`SKILL.md:42`, `45`, `49`, `56-63`) and a six-row mistake-and-fix table (`SKILL.md:81-88`).
  > "Examples are concrete, not abstract" — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.md § Checklist for effective Skills
- Decision points guided: `Pick the mode` maps the owner's wording to steps 1-5 or steps 1-8 (`SKILL.md:16-21`); the classifier-denial branch is spelled out (`SKILL.md:74-76`).
  > "Guide Claude through decision points" — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.md § Conditional workflow pattern
- Forward slashes in paths: measure `backslash_paths: []`.
  > "Always use forward slashes in file paths, even on Windows" — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.md § Avoid Windows-style paths
- One default, not many options: each choice is a default with one named fallback (`blast-off` on `PATH`, else `bin/blast-off`, `SKILL.md:12-13`; the bare start line, else the owner's `!` line, `SKILL.md:72-76`).
  > "Don't present multiple approaches unless necessary" — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.md § Avoid offering too many options
- Run-versus-read intent clear: Claude runs preflight (`SKILL.md:49`); the start line is handed over, and Claude runs it only when the owner asks and has added the allow rule (`SKILL.md:10`, `52-58`, `70-72`); the templates are filled, the README is read (`SKILL.md:13-14`).
  > "Make clear in your instructions whether Claude should" — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.md § Provide utility scripts
- Scripts for deterministic operations: preflight, start, status and stop are `blast-off` subcommands (`SKILL.md:49`, `57`, `61-63`); Claude is not asked to write equivalent checks.
  > "Prefer scripts for deterministic operations" — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.md § Runtime environment
- Tools not assumed installed: `SKILL.md:12-13` says where the command is when it is not on `PATH`; step 6's preflight refuses when a dependency is missing (`README.md:60`, `lib/preflight.sh:15`). `SKILL.md` itself does not list the requirements; `README.md:16-18` does.
  > "Don't assume packages are available" — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.md § Avoid assuming tools are installed
- Descriptive file names: `SKILL.md`, `templates/brief.md`, `templates/checkpoint.md`, `README.md`.
  > "Use names that indicate content" — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.md § Runtime environment
- Standing instructions: the rules that hold for the whole task are written as standing statements, not steps (`SKILL.md:10`, `39-40`, `70-77`, and the mistakes table `SKILL.md:81-88`).
  > "write guidance that should apply throughout a task as standing instructions rather than one-time steps" — https://code.claude.com/docs/en/skills.md § Skill content lifecycle
- Most important instructions near the top: what the skill produces and who starts the job are in the first paragraph (`SKILL.md:8-10`); the whole body is 831 words.
  > "put the most important instructions near the top of `SKILL.md`" — https://code.claude.com/docs/en/skills.md § Claude stops following a skill
- Frontmatter kept to the spec's fields: only `name` and `description` (measure `frontmatter_fields`).
  > "Restricting frontmatter to the spec's six fields avoids the unexpected-key error above." — https://code.claude.com/docs/en/skills.md § Using skill frontmatter outside Claude Code
- Skill folder symlinked into a skills location: `README.md:26` links `skills/blast-off` to `~/.claude/skills/blast-off`; `SKILL.md:12-13` resolves the repo through that symlink with `readlink -f`.
  > "a `<skill-name>` entry in the enterprise, personal, or project location can be a symlink to a directory elsewhere on disk" — https://code.claude.com/docs/en/skills.md § Choose where skills load

## N/A and Can't verify

- MCP tools fully qualified: N/A. `SKILL.md` names no MCP tool.
  > "always use fully qualified tool names" — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.md § MCP tool references
- Packages installed locally only: N/A. The skill installs no package.
  > "Skills should only install packages locally to avoid interfering with the user's computer." — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview.md § Runtime environment constraints
- `disable-model-invocation` for side-effect workflows: N/A. The field is not set, and the skill is written to be model-invoked (trigger phrases at `SKILL.md:3`). Its one unattended, usage-spending action, `blast-off start`, is given to the owner in the body (`SKILL.md:10`, `70-72`), so Claude loading the skill starts nothing by itself. A reader who wants the launch workflow to be manual-only can still set the field.
  > "Use this for workflows with side effects or that you want to control timing" — https://code.claude.com/docs/en/skills.md § Control who invokes a skill
- Tested with the models used: Can't verify. No file records which models the skill was run with.
  > "Tested with Haiku, Sonnet, and Opus" — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.md § Checklist for effective Skills
- Tested with real usage: Can't verify. Usage history is outside the files.
  > "Tested with real usage scenarios" — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.md § Checklist for effective Skills
- Team feedback: Can't verify. Outside the files.
  > "Team feedback incorporated (if applicable)" — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.md § Checklist for effective Skills

## Phase 3 attribution

Basis: `git diff feat/br-1115-issues/phase-2...HEAD -- skills/blast-off/` changes one sentence of step 4 (`SKILL.md:34-37`; phase 2 had it on two lines, `34-35`). Measured with and without that change (`git show feat/br-1115-issues/phase-2:skills/blast-off/SKILL.md`): body 83 against 81 lines, 831 against 811 words, description 199 characters both times. No limit was crossed and no ledger row changed its verdict. There is no Fail to attribute.

| Finding | Evidence rests on | Attribution |
|---|---|---|
| Gap: description says when to use the skill but not what it does (Recommended on Claude Code; Required on the platform) | `SKILL.md:3` (frontmatter `description`), identical in phase 2 | pre-existing |
| Gap: no table of contents in referenced files over 100 lines | `README.md` (153 lines now, 151 in phase 2, no contents list either time) and `templates/brief.md` (187 lines, unchanged in phase 3), both named at `SKILL.md:13-14`, which phase 3 did not change. Phase 3 edited `README.md` only around lines 112-131 (CI wording), not its opening | pre-existing |
| Gap: fewer than three evaluations in the skill folder | the folder's file list: `SKILL.md` only, in phase 2 (`git ls-tree`) and now | pre-existing |
