VERDICT: CLEAN

# Review: phase 9, round 1 (issue #21), commits 9f9bec8 and 0c98d4d

Gate: `GATE: PASS passed=19 failed=0 shellcheck=ok` (full suite, BLAST_OFF_TEST_ONLY unset, log under the reviewer's scratchpad `gate-p9r1/tests-run.log`)
ExecStart: `ExecStart=/home/alex/blast-off/.worktrees/blast-off-build/bin/blast-off run %f` (as expected)

Counts: CRITICAL 0, HIGH 0, MEDIUM 1, LOW 4.

## What was checked

1. Spec match. Checkbox 1: README.md:55-57 and skills/blast-off/SKILL.md:25-27 both say to start the session inside
   the target repo. Checkbox 2: docs/2026-11-04-large-job-launcher-prompt.md added. Beyond scope: only the
   README.md:13 link (supports checkbox 2), the tests/70-docs.sh check and spec row, and the docs/spec.md:8-9 pointer
   (0c98d4d). Nothing else.
2. Copy fidelity. `tail -n +4 docs/2026-11-04-large-job-launcher-prompt.md | cmp - <(git -C /home/alex/vista-root/vbe show db41485ce:docs/handoff/2026-11-04-large-job-launcher-prompt.md)`: identical.
   Lines 1-2 are the HTML-comment provenance note, line 3 blank. Secret scan (sk-, ghp_, github_pat_, AKIA, bearer,
   api key, password, secret, token, email): no secrets or tokens. Private data present: see P9R1-5.
3. Facts. `git -C vbe diff afc647e0 db41485ce -- docs/handoff/2026-11-04-large-job-launcher-prompt.md` is empty and
   the file exists at afc647e0, so "same text at afc647e0 and db41485ce" is true. vbe's origin is
   `git@github.com:VistaMarkets/vbe.git`, so "VistaMarkets/vbe commit db41485ce" is true. Note: neither commit is on
   vbe `origin/main` (only on `claude/moonpay-spec-analysis-c4ea2f`, local and remote), and the file is absent on
   vbe main; that is a reason the in-repo copy is worth having, not a defect. Links: README.md:13
   `docs/2026-11-04-...` resolves from the repo root; docs/spec.md:8 `2026-11-04-...` resolves from docs/.
4. Wording. No em dashes or curly quotes in any added line outside the verbatim copy (the provenance note has none).
   SKILL.md step 5 exists ("Write the job dir"); the new sentence's reference to it is P9R1-1.
5. tests/70-docs.sh:66-71. Mutation runs against a temp copy of the repo: dropping the phrase from README, dropping it
   from SKILL.md, deleting the docs file, and changing the README link target each produce the matching FAIL line.
   `shellcheck -S warning` (what tests/run uses) is clean; the plain `shellcheck` run shows only pre-existing
   info-level SC1091/SC2016 on lines 4, 50, 60, 61, none on the new lines. docs/spec.md 70-docs row matches what the
   test checks.
6. Other readers. Only 70-docs reads the real README/SKILL.md; 41/22/60/61 use README only as fixture names;
   00-harness reads docs/spec.md rows K/F/verbs/exit codes, untouched by the line 8-9 edit (gate passes). The repo
   has no ARCH.md to regenerate.

## Findings

### P9R1-1 MEDIUM skills/blast-off/SKILL.md:27
"If this session started elsewhere, tell the owner before step 5." is too late and gives no action. Steps 1 to 4 (read
the repo's AGENTS.md, build and confirm the Target set, settle phases, gate, flags) all run before step 5, so the
whole scoping conversation has already run under the other repo's AGENTS.md/CLAUDE.md and hooks, which is the cost
issue #21 names. In prompt-only mode step 5 is the last step, so the warning lands as the brief is written. Nothing
in step 5 depends on the session's start dir more than steps 1 to 4 do. The sentence also does not say what the
owner should do with the warning.
Fix, replace the sentence with:
`If this session started elsewhere, say so to the owner before step 1 and recommend starting a new session in the target repo; go on here only if the owner says to.`

### P9R1-2 LOW README.md:55-57
The sentence sits under "Check, then start", after "Write a job dir" (README.md:36-51), whose last paragraph
(README.md:50-51) is where a reader learns the skill walks a Claude session through scoping and writing the files.
That session is already open by the time a reader reaches "Check, then start". It is still visible to a reader about
to launch, so this is optional.
Fix (optional): move the paragraph to directly after README.md:50-51, or append to that paragraph:
`Start that session inside the target repo (the repo the job changes), not in another project's checkout or worktree: a session loads that directory's `AGENTS.md`/`CLAUDE.md` and hooks on every turn.`
(the 70-docs phrase check still matches either placement).

### P9R1-3 LOW tests/70-docs.sh:69
`[[ -f ... ]]` passes for an empty or truncated copy. A cheap content check pins it to the original:
`grep -qx '# Prompt: build the standalone unattended job launcher' "$REPO/docs/2026-11-04-large-job-launcher-prompt.md" || fail "docs/2026-11-04-large-job-launcher-prompt.md does not hold the launcher prompt"`
(replaces the `-f` line; grep on a missing file also fails). The docs/spec.md:256 row wording can stay.

### P9R1-4 LOW docs/spec.md:9
The edited line is 176 characters where the surrounding prose wraps at about 100, and it names the source repo
`VistaMobileBE` while the copy's provenance note (docs/2026-11-04-large-job-launcher-prompt.md:1) names
`VistaMarkets/vbe`. Both are the same repo (old local dir and PR prefix vs current remote), but a reader cannot tell.
Fix, replace lines 8-10 with:
```
Source of the keep and fix lists: [`docs/2026-11-04-large-job-launcher-prompt.md`](2026-11-04-large-job-launcher-prompt.md)
§4 and §5, copied from VistaMarkets/vbe (then VistaMobileBE) `docs/handoff/`, same text at commits
`afc647e0` and `db41485ce`. Source of the directive table: `~/.claude/docs/guides/system-d-guide.md`
§5 (commit `ad995d4`). blast-off never reads or writes the installed `big-next-job` skill at runtime (D1).
```

### P9R1-5 LOW docs/2026-11-04-large-job-launcher-prompt.md (lines 7, 77-89 and others)
The verbatim copy carries private working detail from another org's repo into z0rd0n88/blast-off: absolute local
paths under /home/alex, Claude session transcript file names with session UUIDs (lines 79-82), memory names, and
VistaMarkets business detail (MoonPay on-ramp job, VistaMarkets/VistaMobileBE PR numbers #1120 to #1135). No secrets
or tokens. Both repos are private and the issue asks for the copy, so this is the owner's call, not a defect.
Fix: none required; if the owner prefers, keep the copy verbatim (fidelity is the point) and accept it, or redact
the transcript paths (lines 79-82) and note the redaction in the provenance comment.

## Questions for the owner

1. P9R1-5: is copying VistaMarkets/vbe working detail (local paths, session ids, MoonPay job facts) into the
   z0rd0n88/blast-off repo acceptable as is, or should the transcript paths be redacted?
