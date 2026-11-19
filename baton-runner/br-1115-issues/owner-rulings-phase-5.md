# Owner rulings, phase 5 (issue 39), 2026-11-17

- Q1: preflight refuses a job at its HARD child cap (0 left) and names the way on: add a Phase plan table, raise JOB_MAX_CHILDREN, or delete child-count. Soft cap stays ok (resume gives a fresh allotment).
- Q2: `start` and `resume` run the child-count and JOB_* checks before systemd-run; on a bad value they print the reason, exit 1, launch nothing, and leave the resume timer alone.
- Q3 (manager default, applied in d059301): JOB_* numbers with a leading zero are refused.
- Q4: no guard against a child deleting or lowering child-count; children are trusted (phase 3 threat model) and run.log's start-count line shows any reset.
- Q5 (manager default, applied in d059301): a child-count refusal never echoes the file's content.
- Q6: move the child-count check after chain_lock, so a second runner reports "lock held" and writes nothing.
- Q7 (not asked; work unit's reasoning kept): `status` omits "left", since it runs in the caller's environment, not the unit's.
Q1, Q2 and Q6 go to a follow-up issue, not this phase.
