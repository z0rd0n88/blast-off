# shellcheck shell=bash
# checkpoint.sh: read the job's checkpoint.md. JOB is set by job_init.

# First `status:` line's word (running, done, blocked, ...). sed quits at the match: no head, no SIGPIPE.
cp_status() { sed -n '/^status:/{s/^status: *\([a-z-]*\).*/\1/p;q}' "$JOB/checkpoint.md"; }

# Changes whenever a child rewrites the checkpoint; equal before and after a child = a stall.
cp_fingerprint() { sha256sum "$JOB/checkpoint.md" | cut -c1-16; }

# Rows of the `## Phase plan` table whose first cell is a number: the job's phase count (0 = no table).
cp_phases() { sed -n '/^## Phase plan/,/^## /{/^| *[0-9]/p}' "$JOB/checkpoint.md" | wc -l; }

# cp_set_status <word>: rewrite the first `status:` line, the one cp_status reads.
cp_set_status() { sed -i "0,/^status:.*/s//status: $1/" "$JOB/checkpoint.md"; }

# cp_names <path>: checkpoint.md holds the path whole, with no path character touching either end
# (README is not named by README.md); a trailing '.' that ends a sentence still counts (D2-5).
# A bare name, no '/' and no '.', counts only in backticks (`status`): prose such as every
# checkpoint's `status: running` must not name a file called status (P2R1-2; owner P2Q1 open).
cp_names() {
  [[ $1 == */* || $1 == *.* ]] || { command grep -qF -- "\`$1\`" "$JOB/checkpoint.md"; return; }
  local esc; esc="$(printf '%s' "$1" | sed 's#[][\.*^$+?(){}|]#\\&#g')"
  command grep -qE -- "(^|[^[:alnum:]_./-])$esc([^[:alnum:]_./-]|\.([^[:alnum:]_]|$)|$)" "$JOB/checkpoint.md"
}
