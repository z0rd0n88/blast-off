# Phase 10 fix round 1

Commit: a0946fd `docs: phase 10 review round 1 fixes` on feat/br-1115-issues/phase-10 (parent c45292a).
11 files, comments and docs only: every changed line in bin/, lib/, scripts/, systemd/ and tests/ is a
`#` comment (checked with `git diff -U0 | grep -v '^[+-] *#'`: no output).

Outcome: 15 applied, 0 refuted, 0 blocked. P10R1-16 kept as is (owner ruling).

| finding | outcome | file:line | old -> new |
|---|---|---|---|
| P10R1-1 | applied | bin/blast-off:27 | `JOB_KEEP_WINDOWS=1        leave finished children's windows open` -> `JOB_KEEP_WINDOWS          set to any value (0 too): leave finished children's windows open` (code: lib/chain.sh:22, lib/child.sh:137, :144 test only `-n`/`-z`) |
| P10R1-2 | applied | README.md:70-73 | "every set `JOB_*` and `BLAST_OFF_*` name the runner reads (not `JOB_BASE` or `BLAST_OFF_ESTIMATE_FROM`, which only `preflight` reads)" -> reviewer's text: "... the runner or its children read (not `JOB_BASE` or `BLAST_OFF_ESTIMATE_FROM`, which only `preflight` reads, nor `BLAST_OFF_WAIT_POLL`, which only `wait` reads)"; rewrapped near 100 |
| P10R1-3 | applied | README.md:397 | "deleted at each run's start" -> "deleted by each run once it holds the lock" (lib/chain.sh:166, :171) |
| P10R1-4 | applied | docs/spec.md:122-124 | "Code 2 is unused (bash reserves it for builtin misuse)." -> "The runner never exits 2 (bash reserves it for builtin misuse); `status` and `resume` exit 2 only when `checkpoint.md` is missing." |
| P10R1-5 | applied | README.md:185; docs/spec.md:63; lib/preflight.sh:6-7; tests/60-preflight.sh:8 | README "writes nothing" -> "writes nothing to the job dir (`behind` runs `git fetch origin <JOB_BASE>`)"; spec "writing nothing" -> "writing nothing to the job dir"; preflight.sh "It writes nothing:" -> "It writes nothing to the job dir:"; sibling found in the test 60 header, "It writes nothing." -> "It writes nothing to the job dir." (fetch: lib/preflight.sh:144) |
| P10R1-6 | applied | README.md:19-20 | "bash, tmux 3.2 or later, jq, python3, systemd" -> "bash, tmux 3.2 or later, jq, python3, git, coreutils `realpath`, systemd" (lib/chain.sh:89, :150) |
| P10R1-7 | applied | README.md:193-194 | "(children inherit the unit's environment through the job's tmux server)" -> "(children inherit the unit's environment, less every `CLAUDE*` name and `OPENROUTER_API_KEY`, through the job's tmux server)" (lib/child.sh:14, :22) |
| P10R1-8 | applied | docs/spec.md:116-118 | "(no job dir, a missing or empty ..." -> "(no `<job-dir>` argument or job dir, a workdir name blast-off refuses, a missing or empty ..." (bin/blast-off:66) |
| P10R1-9 | applied | lib/child.sh:39-40 | "so '; exit' makes the shell fork systemd-run" -> "so the commands after claude make the shell fork systemd-run" (lib/child.sh:51); rewrapped |
| P10R1-10 | applied (owner ruling) | scripts/gate.sh:2-5 | "tests/run (every scenario, then shellcheck)" -> "tests/run (every scenario, or those BLAST_OFF_TEST_ONLY names, then shellcheck)"; "its GATE: PASS\|FAIL verdict" -> "its GATE: (GATE-ONLY: under BLAST_OFF_TEST_ONLY) PASS\|FAIL verdict"; wrapped near 100 (shellcheck runs under ONLY too: tests/run:66) |
| P10R1-11 | applied (owner ruling) | systemd/blast-off@.service:6 | "every [Service] directive below as a -p property" -> "every [Service] directive below but ExecStart= as a -p property" (lib/units.sh:46) |
| P10R1-12 | applied | CHANGELOG.md:16-20 | placeholder "(Phase 10, adjust when it lands) Documentation update and fact check: ..." -> reviewer's final wording, marker dropped; `(PR #<n>)` left for the PR number |
| P10R1-13 | applied | CHANGELOG.md:47-48 | "is now logged, with a test for the reset (#29, PR #32)" -> "is now logged, and the flag clears for the next child (#29, PR #32)" (lib/child.sh:83-85, tests/20-dead-child.sh:99-101) |
| P10R1-14 | applied | lib/chain.sh:129-131, lib/preflight.sh:4-7 and :22-24, skills/blast-off/SKILL.md:68-72, tests/60-preflight.sh:4-5, bin/blast-off:10-11, README.md:70-74 | rewrapped near 100, words unchanged (SKILL.md: no instruction cut or softened, whitespace only). One edited line stays over 105: docs/spec.md:116 (112 cols, was 127; spec lines around it run 115-120) |
| P10R1-15 | applied | baton-runner/br-1115-issues/phase-10/fact-ledger.md rows at lines 15, 16, 18, 160; coverage.md | row 15 claim -> links docs/spec.md, deviations doc, Options guide, Technical details, launcher prompt copy, CHANGELOG.md at README.md:10-15; row 16 marked fixed (P10R1-6); row 18 location -> "moved by unit C: README.md:202 (row 342)"; row 160 -> new claim and evidence incl. implicit `set -e` exit; `## Fix round 1` section added (20 rows). coverage.md: every README, spec, bin/blast-off and SKILL.md line number remapped to a0946fd by a diff map from 0a5d3b1, plus two hand fixes: PR 41 README.md:61 (a code fence) -> :63, PR 45 README.md:18-19 -> :202 |
| P10R1-16 | kept (owner ruling) | tests/70-docs.sh:37-44 | no change |

Blocked: none (templates/brief.md untouched; no SKILL.md instruction cut or softened).
Refuted: none; each finding checked against the cited code before applying.

Tests (targeted, `BLAST_OFF_TEST_ONLY='00-harness 51-templates 70-docs'`, scripts/gate.sh into a fresh
scratchpad dir):
`GATE-ONLY: PASS passed=3 failed=0 shellcheck=ok only=00-harness,51-templates,70-docs`

ExecStart: `ExecStart=/home/alex/blast-off/.worktrees/blast-off-build/bin/blast-off run %f` (as expected).

Style: added lines have no em or en dashes and no curly quotes.

Note: a PostToolUse hook asked for `skill-sheriff-cc` on skills/blast-off after the SKILL.md rewrap;
that skill is not available in this session and the edit is whitespace only, so it was not run.
