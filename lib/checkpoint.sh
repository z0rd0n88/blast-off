# shellcheck shell=bash
# checkpoint.sh: read the job's checkpoint.md. JOB is set by job_init.

# First `status:` line's word (running, done, blocked, ...). sed quits at the match: no head, no SIGPIPE.
cp_status() { sed -n '/^status:/{s/^status: *\([a-z-]*\).*/\1/p;q}' "$JOB/checkpoint.md"; }

# Changes whenever a child rewrites the checkpoint; equal before and after a child = a stall.
cp_fingerprint() { sha256sum "$JOB/checkpoint.md" | cut -c1-16; }
