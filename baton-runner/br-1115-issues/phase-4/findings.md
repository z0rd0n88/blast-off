# Phase 4 findings

- `local n=0` in chain_run (lib/chain.sh:117) is the child number and the cap counter; reset each run.
- Soft cap (exit 6) promises a re-run "continues with a fresh child count" (spec row 6, README exit table, test 21 lines 27-33 re-run at the same cap 2 and expect done). A single persisted count would re-pause that job forever.
- tests/fakes/claude picks its mode line by JOB_CHILD (= n), so continuing numbers shift which fake-mode line a re-run's child gets.
- preflight calls chain_nums and chain_cap; neither should read the counter (preflight writes nothing; a garbled file is the runner's error).
- jev_pick "$n" only uses n as a label in decisions.tsv.

## Decisions (counter file)

- File: `$JOB/child-count`, one line `<launched> <base>`. launched = children launched for this job ever (= the last child's number); base = launched at the last paused-cap -> running. Missing file = `0 0` (a fresh job; first child is 1).
- Cap check: next = launched+1; stop when next - base > MAXC. So the hard cap counts every child of the job; the soft cap counts children since the last paused-cap resume (keeps spec row 6's fresh allotment), but a crash/reboot relaunch of a running job does not reset it.
- Increment: after the cap check passes, before child_launch, written to a temp file in the job dir and mv'd over (atomic rename). A child that was running when the box went down is counted. A cap exit writes nothing.
- Garbled (empty, unreadable, not two whole numbers, a leading zero, base > launched): exit 1 before any child, naming the file and its content. Never treated as 0 (would reset the cap). Fix by hand: write the right numbers, or delete the file to restart the count (owner's choice, logged in the message).
- Read point: in chain_run right after chain_nums, before the lock and the EXIT trap, so a bad file is a clean `die` (exit 1, nothing logged as a runner abort). The write is a rename, so no reader sees a half-written file.
- Hard cap reached is final for the job unless the owner edits or deletes `child-count` or raises JOB_MAX_CHILDREN; the exit-4 message says so.
