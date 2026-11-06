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
# A name holding a newline is never named: grep would split it into two patterns (P2R2-1).
cp_names() {
  [[ $1 != *$'\n'* ]] || return 1
  [[ $1 == */* || $1 == *.* ]] || { command grep -qF -- "\`$1\`" "$JOB/checkpoint.md"; return; }
  local esc; esc="$(printf '%s' "$1" | sed 's#[][\.*^$+?(){}|]#\\&#g')"
  command grep -qE -- "(^|[^[:alnum:]_./-])$esc([^[:alnum:]_./-]|\.([^[:alnum:]_]|$)|$)" "$JOB/checkpoint.md"
}

# cp_done_rows: first cells of the Phase plan rows whose Status cell (the last) starts with "done".
cp_done_rows() {
  sed -n '/^## Phase plan/,/^## /{/^| *[0-9]/p}' "$JOB/checkpoint.md" |
    awk -F'|' '{ k = $2; st = $(NF-1); gsub(/[ \t]/, "", k); sub(/^[ \t]+/, "", st)
                 if (st ~ /^done/ && k ~ /^[0-9A-Za-z_-]+$/) print k }'
}

# cp_row_sha <key>: the first 7 to 40 character lower-case hex word in that Phase plan row's Status cell.
cp_row_sha() {
  sed -n '/^## Phase plan/,/^## /{/^| *[0-9]/p}' "$JOB/checkpoint.md" |
    awk -F'|' -v k="$1" '{ key = $2; gsub(/[ \t]/, "", key); if (key != k) next
      n = split($(NF-1), w, /[^0-9A-Za-z]+/)
      for (i = 1; i <= n; i++) if (w[i] ~ /^[0-9a-f]+$/ && length(w[i]) >= 7 && length(w[i]) <= 40) { print w[i]; exit } }'
}

# cp_mark_usage <rows done before the child> <usage>: each Phase plan row done now and not before gets
# " · usage <usage>" at the end of its Status cell, the account's usage at the close of that phase (F10).
cp_mark_usage() {
  local k
  for k in $(cp_done_rows); do
    [[ " $1 " != *" $k "* ]] || continue
    sed -i "/^## Phase plan/,/^## /{/^| *$k *|/{/ · usage /!s/[[:space:]]*|[[:space:]]*\$/ · usage $2 |/}}" "$JOB/checkpoint.md"
    log "phase row $k done; usage $2"
  done
}
