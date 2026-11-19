---
source: runner
scope: br-1115-issues
parent_session: ""
---
# Pass-Baton: phase 6 review round 2 (issue 14, narrow), VERDICT CLEAN: 0 CRITICAL, 0 HIGH, 5 MEDIUM, 14 LOW, 3 skill-sheriff Gaps

**Date:** 2026-11-18
**Scope:** br-1115-issues
**Branch:** feat/br-1115-issues/phase-6
**Worktree:** /home/alex/blast-off/.claude/worktrees/pending-items-53932d
**HEAD:** d5e27e2 fix(units): wait trusts the runner's run.log for done and blocked (#14)

## Where things stand

VERDICT: CLEAN, by the contract's rule. The gate exited 0, the report has no CRITICAL or HIGH finding, and every
issue-14 criterion has a passing test (table in the report). CLEAN is close: it rests on the review unit holding
P6R2-1 at MEDIUM where silent-failure-hunter filed it HIGH. If the owner takes HIGH, the verdict is ISSUES. CLEAN
does not mean nothing to fix: 5 MEDIUM and 14 LOW are open, and the manager triages them.

Read P6R2-1 first. P6R1-1's path is closed: a child's `status: done` no longer ends the watch while the runner checks
receipts and CI, and an accepted done always ends run.log on the exact `job done` line. But `wait_logged` anchors on
run.log's last line that starts with a timestamp, not the last line the runner wrote. Child text copied raw into
run.log (`child_report`'s last message, `child_screen`) can carry `<ts> job done`, and between that copy and
`log "child $n usage"` a poll reads `final`. Its comment says only a killed runner opens that gap; that is false.
Then P6R2-2: a read that never clears mid-watch (job dir deleted, user bus gone) now hangs forever with no output.

- **Gate.** `scripts/gate.sh baton-runner/br-1115-issues/gate-phase-6-iter-2` ran once, alone, before any reviewer.
  Exit 0; last line `GATE: PASS passed=19 failed=0 shellcheck=ok`. Log: `gate-phase-6-iter-2/tests-run.log`.
- **ExecStart.** `ExecStart=/home/alex/blast-off/.worktrees/blast-off-build/bin/blast-off run %f` before the gate,
  after it, after the mutant run and at the end. Never changed.
- **Review.** code-reviewer and silent-failure-hunter, each a `general-purpose` agent reading its parked definition
  read-only, static only; both returned (2/2). skill-sheriff-cc audited `skills/blast-off/SKILL.md` (0 Fail, 3 Gap, all
  from before phase 6). Report: `review-phase-6-iter-2.md`. Outputs: `review-phase-6-iter-2/{code-reviewer,
  silent-failure-hunter,skill-sheriff}.md`.
- **My checks.** One bash probe of `wait_logged` on crafted run.log files: a forged line in a child's last message ->
  final; with the runner's usage line after it -> not final; a timestamped line after `job done` -> not final
  (P6R2-1, P6R2-3). One mutant run on a `git archive d5e27e2` copy: "`blocked` always final" PASSES 13-wait (P6R2-5).
  Both copies deleted.
- **Side effects.** No tracked file changed, no git operation, `STATE.md` and `log.md` untouched. Scratch under the
  session scratchpad only. The skill-sheriff subagent's report-file write was refused by the harness; it returned
  the text and this unit saved it (quotes re-verified, exit 0). The advisor was rate-limited.
- **New dependencies.** None.

## Findings

Every finding, unfiltered. The full rows are in the report.

| ID | Sev | Title | Location |
|---|---|---|---|
| P6R2-1 | MEDIUM (silent-failure-hunter: HIGH) | Anchor is run.log's last timestamped line, not the runner's: child text copied into run.log can end the watch `final`; `wait_logged`'s comment is false | `lib/units.sh:145-152`; `lib/child.sh:97-120`; `lib/chain.sh:212-230` |
| P6R2-2 | MEDIUM | A read that never clears mid-watch blocks forever with no output (regression from the P6R1-5 fix) | `lib/units.sh:123`, `:131`, `:133-135` |
| P6R2-3 | MEDIUM | Any timestamped line after `job done`/`job blocked` (`receipt`, `ci-wait`, a kept child) turns an accepted end into a permanent stuck that reads as refused | `lib/units.sh:148-152`; `lib/receipt.sh:12`, `:37`; `lib/ci.sh:27-45` |
| P6R2-4 | MEDIUM | Two-poll stuck counts polls, not time: at poll 0.1 or a slow resume the timer handoff reads stuck | `lib/units.sh:109-121`, `:62-64` |
| P6R2-5 | MEDIUM | The `blocked` half of the ruling has no killing test; mutant "blocked always final" passes. Reproduced | `lib/units.sh:108`, `:121`; `tests/13-wait.sh:101-103` |
| P6R2-6 | LOW | TERM between `log "job done"` and `trap ''` logs after the end | `lib/chain.sh:6`, `:16`, `:159` |
| P6R2-7 | LOW | A failed `tee` in `chain_end` drops the end line | `bin/blast-off:52`; `lib/chain.sh:6` |
| P6R2-8 | LOW | `deactivating` as down still untested (P6R1-8 half done) | `lib/units.sh:111` |
| P6R2-9 | LOW | Docs describe 12 and the line differently from the code (blocked hold, refused blocked, "no end", run.log not listed, ~135-char status, every `·`, `resume` advice) | `README.md:99-113`; `docs/spec.md:55`; `bin/blast-off:12-14` |
| P6R2-10 | LOW | spec 13-wait row says 12 "at once" on an already stuck job; now one poll later | `docs/spec.md:234` |
| P6R2-11 | LOW | SKILL step 8 says never rerun exit 1 unchanged, but a transient read at start exits 1 | SKILL.md step 8; `lib/units.sh:106`, `:131` |
| P6R2-12 | LOW | The stuck line for done/blocked gives no reason; run.log read errors swallowed | `lib/units.sh:115-116`, `:151` |
| P6R2-13 | LOW | P6R1-17 worse: unlogged done/blocked plus a leftover waiting timer blocks until it fires | `lib/units.sh:108-121` |
| P6R2-14 | LOW | Field cleaning leaves lookalike separators, bidi and zero-width characters | `lib/units.sh:142-143` |
| P6R2-15 | LOW | 13-wait does not cover the new failure modes | `tests/13-wait.sh:88-102`, `:179-187` |
| P6R2-16 | LOW | A change past character 80, or after the status word, is not a change | `lib/units.sh:137`, `:143` |
| P6R2-17 | LOW | At-start errors guess the cause and drop the real error | `lib/units.sh:131`, `:133-135` |
| P6R2-18 | LOW | `BLAST_OFF_WAIT_POLL=.5` and `1.` refused though in range | `lib/units.sh:104-105` |
| P6R2-19 | LOW | Fix notes and `phase-6/findings.md:51` record the false anchor claim as a decision | `phase-6/findings.md:51-52` |
| P6R2-S1 | Gap | SKILL description says when, not what the skill does | `SKILL.md:3` |
| P6R2-S2 | Gap | README (182 lines) and `templates/brief.md` (192) have no contents list | `SKILL.md:13-14`, `:76` |
| P6R2-S3 | Gap | No evaluations / with-without baseline | skill folder |

## Open owner questions

1. P6R2-1: HIGH or MEDIUM? To close it: prefix child text in run.log and flatten newlines in `log()`, an end file,
   or also require the unit down before final?
2. P6R2-3: may `receipt`/`ci-wait` after `job done` turn a finished job stuck? If not: anchor on the last end-or-start
   line, or an end file?
3. P6R2-2: bound the mid-watch retry (how many polls; exit 1 or 12), or keep it unbounded and document it?
4. P6R2-4: read the resume service's state, a minimum down time, or a higher poll floor?
5. P6R2-6/-7: should `chain_end` ignore signals before logging and write the file before stdout?

## Next

The manager triages: a fix round for P6R2-1..-5 (a single end file would answer P6R2-1, -3, -6 and -7 at once), or
deliver with them filed.
