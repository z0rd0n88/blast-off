# Checkpoint: <job title>

status: running
phase: 0 of N — <phase name>
step: <what is happening right now, one line>
updated: <UTC timestamp> by child <n>
worktree: <path> · branch <name> · HEAD <sha> · base <branch or sha>
other worktrees: <path · branch · HEAD, or none>

## Next action
<one exact action the next session takes first>

## Phase plan
| # | Phase | Done when | Status |
|---|---|---|---|
| 0 | <name> | <acceptance> | pending |
| 1 | <name> | <acceptance> | pending |
| 2 | <name> | <acceptance> | pending |

<!-- Rules the runner enforces on this file (blast-off; keep this comment):
- The first status line above is the one the runner reads. Children write only running, done or
  blocked there. paused-cap and paused-limit are the runner's: on a usage limit, checkpoint and end
  the turn; the runner pauses the job itself.
- Each row's first cell starts with a digit (0, 1, 2a): the runner only sees rows like that.
- A closed row's Status cell starts `done (<sha>)`, <sha> = the commit `blast-off receipt` recorded
  for the phase (gate-logs/phase-<n>.json head_sha). The runner reads the first 7 to 40 character
  hex word in the cell, so replace an older sha, never append a second. Add `PR #<n>` after it.
- ` · usage ...` at the end of a done cell is written by the runner at the child's end. Never edit it.
- An uncommitted path at a child's end must be named here, whole; a name with no '/' and no '.'
  (`Makefile`) counts only in backticks. An unnamed one stops the chain (exit 7).
- Over 150 lines the runner warns before each child: keep counts and pointers here, detail in phases/. -->

## Current phase: <n> — <name>
**Will happen** (written when the phase starts; skill picked per slice)
1. <step> → verify: <check>
2. <step> → verify: <check>

**Progress** (one line per step as it lands, newest last)
- <UTC time> step 1 done: <result, with the command run>

## Completed phases (summary each, newest last)
- **Phase 0, <name>** (done <UTC>, children <a>-<b>). <what now works; gate verdict and receipt;
  review rounds, closed clean or at cap, open finding IDs; PR #<n>; CI conclusion read>. Hand-backs:
  <child at which step boundary, and the reason, or none>. Ledger `phases/phase-<n>.md`.

## Decisions (append only; source each)
| Decision | Why | Source |
|---|---|---|

## Open or blocked (append only)
- <item needing the owner, with the question and your recommendation; or a blocked part and its patch in phases/>

## Pointers
- Phase reports and review ledgers: `phases/phase-<n>.md`
- Gate logs and receipts: `gate-logs/phase-<n>.log`, `gate-logs/phase-<n>.json`; CI reads `gate-logs/ci-pr-<n>.json`
- Decision log: `decisions.tsv`
