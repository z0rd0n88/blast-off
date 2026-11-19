# Phase 5 findings

- `chain_count` (lib/chain.sh:116) died on a garbled file before the lock and trap, so only stderr had it (P4R1-2).
- `[ -e "$f" ]` follows a symlink: a dangling `child-count` read as a fresh job and was then replaced by the rename (P4R1-5).
- preflight already calls `chain_cap`; `chain_count` can follow it. preflight sets `LOG=/dev/null`.
- Test 11 already SIGKILLs the runner during child 1 (systemd unit); test 10 can do the same on a foreground runner with no unit, and the re-run's `child_server` -> `child_stop_all` clears the scope, tmux server and child dir the dead runner left.

## Decisions

- **chain_count no longer dies.** It returns 1 with `COUNT_ERR` set, so preflight and status can show a garbled file without exiting. `chain_run` refuses it with `log "$COUNT_ERR" >&2; exit 1`: run.log and stderr, exit 1, before any child, file never rewritten.
- **Missing file stays a fresh job** (owner ruling P4R2-11: deleting `child-count` is the one deliberate reset). No recovery from run.log. Each run logs the count it starts from (`child-count: none, a fresh job; first child 1` or `child-count: L launched, base B; next child L+1`), right after the cap line.
- **A dangling symlink is garbled** (exit 1, "cannot read"), not fresh: `[ -e ] || [ -L ]`. A symlink to a real file is read as before (not changed).
- **preflight** prints the same count line plus `N left under cap M` (soft paused-cap counts as a fresh allotment, as the run would give it); a garbled file is printed and is a refusal reason. No refusal at the cap (display only, minimal).
- **status** prints the count line only, no "left": status takes no env of the unit's, so the cap it would compute can differ from the runner's.
- **chain_nums** bound: `^[0-9]{1,9}$` (digits only bounded; leading zeros keep their old behaviour).
- **P4R2-2:** re-seed `2 0` before test 21's re-run (the reviewers' second option; smaller than a new job).
