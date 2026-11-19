# Skill Sheriff: blast-off
Docs fetched 2026-11-18: https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview.md, https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.md, https://code.claude.com/docs/en/skills.md
Summary: 0 Fail, 3 Gap, 43 Pass, 4 N/A, 3 Can't verify (of 53 ledger rows)

Target: `skills/blast-off/` (one file, `SKILL.md`, 98 lines; body 93 lines from line 4, 1,031 words; description 199 characters, unchanged). Surface: Claude Code. `README.md:26` installs the skill with `ln -s ~/blast-off/skills/blast-off ~/.claude/skills/blast-off`, and the repo has no plugin manifest, so rows are judged by the Claude Code docs where the two surfaces differ; no plugin, API or SDK page was fetched. Linked files read: `README.md` (182 lines), `templates/brief.md` (192 lines), `templates/checkpoint.md` (66 lines), all at the repo root, outside the skill folder. The ledger carries the phase-3 audit's 51 rows (all 54 of its quotes re-verified on today's pages) plus two new rows (52, 53).

## Fail

None.

## Gap

### Description says what the skill does and when to use it (Recommended on Claude Code; Required on the platform)
Evidence: `SKILL.md:3`. The description (199 characters) is one when-clause, from `Use when` to `not for quick edits`. It names the situation and three trigger phrases but never states the skill's own action, which the body gives at `SKILL.md:9-10` (it turns the owner's request into the job dir and hands over the start line). Surface split: on Claude Code, where this skill ships, the field is Recommended, so this is a Gap; uploaded to claude.ai or the API the same text would be a Fail against the platform's wording.
> "What the skill does and when to use it." — https://code.claude.com/docs/en/skills.md § Frontmatter reference
> "The `description` must include both what the Skill does and when Claude should use it." — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview.md § Skill structure
Fix: put one what-clause before the when-clause, for example `Writes a blast-off job dir (brief.md and checkpoint.md), runs preflight and hands the owner the start line. Use when ...`. The result stays far below both length limits.

### Table of contents in reference files over 100 lines (Recommended)
Evidence: `SKILL.md:13-14` sends Claude to the repo's `README.md` (exit codes, watch, resume) and to `templates/`; `SKILL.md:76` sends it to `README, Watch` for `blast-off wait`. `README.md` is 182 lines and `templates/brief.md` is 192 lines; neither opens with a contents list (`README.md:1-12` is an overview and three links to other files; `templates/brief.md:1-9` is the child's preamble). `templates/checkpoint.md` is 66 lines, under the threshold. Both long files sit outside the skill folder; they are in scope because `SKILL.md` names them as the material to read and fill.
> "For reference files longer than 100 lines, include a table of contents at the top." — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.md § Structure longer reference files with a table of contents
Fix: add a short contents list (the `##` section names) at the top of `README.md` and of `templates/brief.md`, or have `SKILL.md:13` and `:76` name the exact README sections (`Exit codes`, `Watch, stop, resume`; the latter is already half-named at `:76` as `Watch`).

### At least three evaluations (Recommended)
Evidence: measure lists `files: ["SKILL.md"]`; the skill folder has no `evals/` directory and no evaluation file, so neither the platform's three evaluations nor Claude Code's with-and-without baseline prompts are in the files. Repo tests that grep `SKILL.md` check the text, not what a Claude session does with the skill.
> "At least three evaluations created" — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.md § Checklist for effective Skills
> "Collect a few realistic prompts, run each one in a fresh session with the skill available and again with it turned off, and compare the results." — https://code.claude.com/docs/en/skills.md § Evaluate and iterate on a skill
Fix: add three evaluation scenarios in the skill folder (a prompt-only brief request, a run request that ends with the hand-over and an optional `wait`, and a quick edit that should not trigger the skill), each with its expected behavior, run with the skill on and off.

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
- `description` specific, with key terms: `SKILL.md:3` names multi-phase coding job, unattended, chain of Claude sessions, systemd, three quoted trigger phrases a user would say, and one exclusion.
  > "Be specific and include key terms" — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.md § Writing effective descriptions
- Key use case first: `SKILL.md:3` opens with the use case; trigger phrases and the exclusion follow.
  > "Put the key use case first" — https://code.claude.com/docs/en/skills.md § Frontmatter reference
- Name pattern: `blast-off` is not a gerund; it is the action-oriented form the same section lists as an acceptable alternative, matches the command the skill drives (`SKILL.md:12`), and is neither vague nor generic.
  > "Consider using **gerund form** (verb + -ing) for Skill names" — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.md § Naming conventions
- Concise body: 93 lines, 1,031 words (measure; phase 3 had 83 and 831). Every paragraph is about blast-off's own commands, files and rules; nothing explains git, systemd or tmux in general. The two longest items are the delivery clause in step 4 (`SKILL.md:34-40`) and step 8 (`SKILL.md:70-76`), which restates the four exit codes of `blast-off wait` that `README.md:106-113` tabulates; those codes are blast-off's own and the watch loop depends on them, so they are context Claude doesn't have.
  > "Only add context Claude doesn't already have." — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.md § Concise is key
- Specificity matches fragility: scoping is free text (`SKILL.md:25-31`); the fragile steps give exact commands (`SKILL.md:45`, `48`, `52`, `58-68`), forbid additions to `CLAUDE_FLAGS` (`SKILL.md:42-43`), and step 8 fixes how the watch runs (background command, never a loop or cron) and what each exit code means (`SKILL.md:70-76`).
  > "Match the level of specificity to the task's fragility and variability." — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.md § Set appropriate degrees of freedom
- Body under 500 lines: measure `body_lines: 93`.
  > "Keep the `SKILL.md` body under 500 lines for optimal performance." — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.md § Progressive disclosure patterns
- Progressive disclosure: `SKILL.md` holds the procedure; exit codes, watch and resume stay in `README.md`, and the brief and checkpoint bodies stay in `templates/` (`SKILL.md:13-14`). Step 8 keeps only the four `wait` exit codes the watch loop branches on and points to `README, Watch` for the rest (`SKILL.md:76`).
  > "`SKILL.md` serves as an overview that points Claude to detailed materials as needed" — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.md § Progressive disclosure patterns
- Supporting files referenced with what they hold: `SKILL.md:12-14` says where `bin/blast-off`, `README.md` and `templates/` are and what each is for; `SKILL.md:48-51` says when and how the two templates are filled; `SKILL.md:76` names the README section for `wait`.
  > "Reference supporting files from `SKILL.md` so Claude knows what each file contains and when to load it" — https://code.claude.com/docs/en/skills.md § Add supporting files
- References one level deep: `README.md`, `templates/brief.md` and `templates/checkpoint.md` are each named in `SKILL.md` itself (`SKILL.md:13-14`, `49-50`, `76`); the templates link no further file Claude must read for this skill, and what `SKILL.md` sends Claude to the README for (exit codes, watch, resume) is in the README itself (`README.md:83-122`, `148-165`).
  > "Keep references one level deep from `SKILL.md`" — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.md § Avoid deeply nested references
- Workflow in clear sequential steps: eight numbered steps (`SKILL.md:25-76`), with the mode choice saying which steps apply (`SKILL.md:16-21`).
  > "Break complex operations into clear, sequential steps." — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.md § Use workflows for complex tasks
- Feedback loop: step 6 runs `blast-off preflight` and has Claude fix what a `preflight: refused` line names before going on (`SKILL.md:52-54`); step 8's watch loop re-runs `wait` on exit 11 and, on exit 1, says to fix the cause and not re-run unchanged (`SKILL.md:72-76`).
  > "Run validator → fix errors → repeat" — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.md § Implement feedback loops
- Validation steps for critical operations: the Target set is confirmed as its own question before any launch question (`SKILL.md:30-31`); preflight runs before the hand-over (`SKILL.md:52-54`).
  > "Validation/verification steps for critical operations" — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.md § Checklist for effective Skills
- No time-sensitive information: `SKILL.md` has no date or version number (regex scan for years and `vN.N`: none) and no before/after condition; `the 7-day window` (`SKILL.md:53`) is a standing limit, not a date.
  > "Don't include information that will become outdated" — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.md § Avoid time-sensitive information
- Consistent terminology: `job dir`, `workdir`, `Target set`, `owner`, `CLAUDE_FLAGS` and `unit` each keep one meaning from first use to last (`SKILL.md:8`, `44`, `27`, `10`, `42`, `9`). One mixed pair remains from phase 3: a chained session is `sessions` in the prose (`SKILL.md:9`) but `child` at `SKILL.md:49` (the brief template's `Child protocol` heading) and `SKILL.md:66` (`the live child`).
  > "Choose one term and use it throughout the Skill" — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.md § Use consistent terminology
- Templates for output format: `templates/brief.md` and `templates/checkpoint.md`, with how strictly to follow them (`SKILL.md:48-51`), plus the two hand-over blocks (`SKILL.md:58-68`).
  > "Provide templates for output format." — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.md § Template pattern
- Concrete examples: full command lines with named placeholders (`SKILL.md:45`, `48`, `52`, `58-68`, `85`) and a six-row mistake-and-fix table (`SKILL.md:91-98`).
  > "Examples are concrete, not abstract" — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.md § Checklist for effective Skills
- Decision points guided: `Pick the mode` maps the owner's wording to steps 1-5 or steps 1-8 (`SKILL.md:16-21`); each `wait` exit code has its next action (`SKILL.md:72-76`); the classifier-denial branch is spelled out (`SKILL.md:84-86`).
  > "Guide Claude through decision points" — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.md § Conditional workflow pattern
- Forward slashes in paths: measure `backslash_paths: []`.
  > "Always use forward slashes in file paths, even on Windows" — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.md § Avoid Windows-style paths
- One default, not many options: each choice is a default with one named fallback (`blast-off` on `PATH`, else `bin/blast-off`, `SKILL.md:12-13`; the bare start line, else the owner's `!` line, `SKILL.md:82-86`); watching has one way, a background `wait`, with loops and cron ruled out (`SKILL.md:70-71`).
  > "Don't present multiple approaches unless necessary" — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.md § Avoid offering too many options
- Run-versus-read intent clear: Claude runs preflight (`SKILL.md:52`) and, when asked to watch, `blast-off wait` (`SKILL.md:70-71`); the start line is handed over, and Claude runs it only when the owner asks and has added the allow rule (`SKILL.md:10`, `55-61`, `80-82`); the templates are filled, the README is read (`SKILL.md:13-14`, `76`).
  > "Make clear in your instructions whether Claude should" — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.md § Provide utility scripts
- Scripts for deterministic operations: preflight, start, wait, status and stop are `blast-off` subcommands (`SKILL.md:52`, `60`, `64-67`); Claude is not asked to write equivalent checks or a polling loop.
  > "Prefer scripts for deterministic operations" — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.md § Runtime environment
- Tools not assumed installed: `SKILL.md:12-13` says where the command is when it is not on `PATH`; step 6's preflight refuses when a dependency is missing (`lib/preflight.sh:17`, `48`; `README.md:153`); step 8 names a missing systemd user bus as an exit-1 cause (`SKILL.md:75`). `SKILL.md` itself does not list the requirements; `README.md:14-18` does.
  > "Don't assume packages are available" — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.md § Avoid assuming tools are installed
- Descriptive file names: `SKILL.md`, `templates/brief.md`, `templates/checkpoint.md`, `README.md`.
  > "Use names that indicate content" — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.md § Runtime environment
- Standing instructions: the rules that hold for the whole task are written as standing statements, not steps (`SKILL.md:10`, `42-43`, the watch rule `70-76`, `78-87`, and the mistakes table `91-98`).
  > "write guidance that should apply throughout a task as standing instructions rather than one-time steps" — https://code.claude.com/docs/en/skills.md § Skill content lifecycle
- Most important instructions near the top: what the skill produces and who starts the job are in the first paragraph (`SKILL.md:8-10`); the whole body is 1,031 words.
  > "put the most important instructions near the top of `SKILL.md`" — https://code.claude.com/docs/en/skills.md § Claude stops following a skill
- Frontmatter kept to the spec's fields: only `name` and `description` (measure `frontmatter_fields`).
  > "Restricting frontmatter to the spec's six fields avoids the unexpected-key error above." — https://code.claude.com/docs/en/skills.md § Using skill frontmatter outside Claude Code
- Skill folder symlinked into a skills location: `README.md:26` links `skills/blast-off` to `~/.claude/skills/blast-off`; `SKILL.md:12-13` resolves the repo through that symlink with `readlink -f`.
  > "a `<skill-name>` entry in the enterprise, personal, or project location can be a symlink to a directory elsewhere on disk" — https://code.claude.com/docs/en/skills.md § Choose where skills load
- No angle brackets in the description (new row): `yaml.safe_load` of the frontmatter finds no `<` or `>` in the 199-character description; the `<job-dir>`-style placeholders are all in the body (`SKILL.md:52`, `60`, `64-67`), where they render as written.
  > "To show a placeholder such as `<branch>`, use square brackets" — https://code.claude.com/docs/en/skills.md § Angle brackets in a skill description show as `&lt;` and `&gt;`

## N/A and Can't verify

- MCP tools fully qualified: N/A. `SKILL.md` names no MCP tool.
  > "always use fully qualified tool names" — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.md § MCP tool references
- Packages installed locally only: N/A. The skill installs no package.
  > "Skills should only install packages locally to avoid interfering with the user's computer." — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview.md § Runtime environment constraints
- `disable-model-invocation` for side-effect workflows: N/A. The field is not set, and the skill is written to be model-invoked (trigger phrases at `SKILL.md:3`). Its one unattended, usage-spending action, `blast-off start`, is given to the owner in the body (`SKILL.md:10`, `80-87`), so Claude loading the skill starts nothing by itself. The phase-6 addition, `blast-off wait` (`SKILL.md:70-76`), only reads the checkpoint and unit state and runs only when the owner asks Claude to watch. A reader who wants the whole workflow (which also creates a worktree, `SKILL.md:44-45`) to be manual-only can still set the field; borderline, arguable as a Gap.
  > "Use this for workflows with side effects or that you want to control timing" — https://code.claude.com/docs/en/skills.md § Control who invokes a skill
- A rule that must hold every time goes in a hook (new row): N/A. The section is a remedy for a skill Claude was seen to stop following; no file records such a lapse, and the skill's must-hold rules are already enforced outside Claude by the tool it drives (`preflight: refused`, `SKILL.md:52-53`; `receipt` refusal and done-row exit 9, `SKILL.md:97`; the `start`-only launch, `SKILL.md:86-87`).
  > "Claude skipped a rule that must hold every time" — https://code.claude.com/docs/en/skills.md § Claude stops following a skill
- Tested with the models used: Can't verify. No file records which models the skill was run with.
  > "Tested with Haiku, Sonnet, and Opus" — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.md § Checklist for effective Skills
- Tested with real usage: Can't verify. Usage history is outside the files.
  > "Tested with real usage scenarios" — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.md § Checklist for effective Skills
- Team feedback: Can't verify. Outside the files.
  > "Team feedback incorporated (if applicable)" — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.md § Checklist for effective Skills

## Changes since the phase-3 audit

No ledger row changed its verdict. All three Gaps are the same three, and none rests on the phase-6 change: the description (`SKILL.md:3`, 199 characters) is unchanged; the contents-list Gap rests on `README.md` and `templates/brief.md`, which grew (153 to 182 and 187 to 192 lines) but were over 100 lines with no contents list before; the skill folder still holds only `SKILL.md`.

- Two rows added, from Claude Code page sections this run found: row 52, angle brackets in the description (Pass), and row 53, a must-hold rule moved into a hook (N/A). Row 48 (evaluations) gained the Claude Code baseline-comparison quote; its verdict stays Gap.
- Re-measured, verdict unchanged: body 83 to 93 lines and 831 to 1,031 words (concise, body-under-500 and near-the-top rows still Pass). Step 8 (`SKILL.md:70-76`) now restates `blast-off wait`'s exit codes 11, 0, 12 and 1 from `README.md:106-113`; the concise and progressive-disclosure rows weighed that and stay Pass, because the watch loop branches on those codes and the README keeps the full table.
- Evidence line numbers moved throughout (preflight 49-51 to 52-54, hand-over 55-64 to 58-68, start-line section 70-77 to 78-87, mistakes table 81-88 to 91-98).
- Where step 8's description of `wait` disagrees with the code, see the review synthesis (`review-phase-6-iter-2.md`, P6R2-9 and P6R2-11), not this audit.
