# shellcheck shell=bash
# checkpoint.sh: read the job's checkpoint.md. JOB is set by job_init.

# First `status:` line's word (running, done, blocked, ...). sed quits at the match: no head, no SIGPIPE.
cp_status() { sed -n '/^status:/{s/^status: *\([a-z-]*\).*/\1/p;q}' "$JOB/checkpoint.md"; }

# Changes whenever a child rewrites the checkpoint; equal before and after a child = a stall.
cp_fingerprint() { sha256sum "$JOB/checkpoint.md" | cut -c1-16; }

# cp_scan <mode> [file]: the one reader of the `## Phase plan` section (P3R4-12), of this job's checkpoint.md
# or that file. An allow-list (owner direction, P3R4-14): the section (from its level-2 heading, any case, to
# the next heading of level 1 or 2) holds blank lines, then one table: a header whose last cell is Status, a
# separator, then rows, each from the left margin between pipes with the header's cell count and no `\|`. A
# blank line or a `###` heading ends the table; after it only prose with no '|' or code fence (HTML is let be:
# notes write `<sha>`, and crafted HTML is outside the threat model, owner ruling 3). Every row is a phase,
# keyed by its first cell (blanks dropped). A row is done when its Status cell is `done` alone or followed by
# a blank or '(' (any case) and its key is letters, digits, '.', '-' or '_' (the key names gate-logs files
# and is word-split); any other row is open, so done refuses it (exit 9).
# Modes: rows (each row's line), done, open (their keys), cells (done rows as "<key>|<Status cell>"), nums
# (done rows as "<line no> <key>"), row and sha (the first row keyed $CP_KEY: its line, the first 7 to 40
# character hex word of its Status cell), unread (the first line done refuses, as "line <n> '<line>' <why>",
# else nothing). Only unread refuses: mid-run a line it would refuse just stops rows being read. unread also
# refuses a second Phase plan heading anywhere, of any level, ATX, setext or <hN>, through common markup and a
# quote or list marker (P3R4-4, P3R4-6), and a CR inside a line (P3R4-3). Fences and block comments hide
# headings, so a `## ` in one neither ends the section nor counts. It reads what a child writes from the
# template, not what a renderer would show of crafted Markdown (owner ruling 3). POSIX awk (P3R4-43).
cp_scan() {
  awk -v mode="$1" '
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
    function lvl(s) { # ATX heading level, 0 for none
      if (s ~ /^    /) return 0
      sub(/^ +/, "", s)
      if (!match(s, /^#+/) || RLENGTH > 6 || substr(s, RLENGTH + 1, 1) ~ /[^ \t]/) return 0
      return RLENGTH
    }
    function pp(s) { # reads "Phase plan" with markup, entities, odd spaces and leading hashes dropped
      s = tolower(s); gsub(/[*_~`]|<[^>]*>/, "", s); gsub("\342\200\213", "", s)
      gsub("&nbsp;|&#32;|&#x20;|\302\240", " ", s); sub(/^[ \t]*#*[ \t]*/, "", s)
      return s ~ /^phase[ \t]+plan([^a-z]|$)/
    }
    function row(s,   a, n, i) { # a row from the left margin between pipes, no `\|`: sets cn, ck, cs, ns (cells Status)
      if (s !~ /^\|.*\|$/ || index(s, "\\|")) return 0
      n = split(s, a, "|"); cn = n - 2; ck = a[2]; gsub(/[ \t]/, "", ck); cs = a[n - 1]; sub(/^[ \t]+/, "", cs)
      ns = 0; for (i = 2; i < n; i++) if (tolower(trim(a[i])) == "status") ns++
      return 1
    }
    function sep(s,   a, n, i) { n = split(s, a, "|"); for (i = 2; i < n; i++) if (a[i] !~ /^[ \t]*:?-+:?[ \t]*$/) return 0; return 1 }
    function bad(n, t, why) { if (mode != "unread") return; gsub(/\r/, "\\r", t); print "line " n " \047" t "\047 " why; exit }
    function emit(   s, d, w, n, i) {
      s = tolower(trim(cs)); d = s ~ /^done([ \t(]|$)/
      if (!d && s ~ /^done/) bad(NR, l, "has a Status cell that starts with \"done\" and is no done state: write `done (<sha>)`, then each of the phase'"'"'s PRs as `PR #<n>` or `no PR`, or leave the row open")
      if (ck !~ /^[0-9A-Za-z._-]+$/) { bad(NR, l, "is a phase row whose key \047" ck "\047 is not letters, digits, \047.\047, \047-\047 or \047_\047: write the key plainly (0, 1, 2a)"); d = 0 }
      if (mode == "rows" || ((mode == "row" || mode == "sha") && ck == ENVIRON["CP_KEY"] && !got++)) {
        if (mode != "sha") print l
        else for (n = split(cs, w, /[^0-9A-Za-z]+/); i < n; ) if (w[++i] ~ /^[0-9a-f]+$/ && length(w[i]) >= 7 && length(w[i]) <= 40) { print w[i]; break }
      }
      else if (mode == (d ? "done" : "open")) print ck
      else if (d && mode == "cells") print ck "|" cs
      else if (d && mode == "nums") print NR " " ck
    }
    { sub(/\r$/, ""); l = $0; v = l; f = 0 }
    index(l, "\r") { bad(NR, l, "holds a carriage return inside the line: end each line with a newline") }
    # v: the line as rendered, "" in a fence or block comment; a complete inline comment shows nothing
    {
      if (fc != "") { f = 1; v = ""; if (l ~ ("^ ? ? ?" fc)) fc = "" }
      else if (cm) { v = ""; if ((i = index(l, "-->"))) { cm = 0; v = substr(l, i + 3) } }
      else if (l ~ /^ ? ? ?(```+[^`]*|~~~.*)$/) { f = 1; v = ""; fc = substr(trim(l), 1, 3) }
      else if (l ~ /^ ? ? ?<!--/) { v = substr(l, index(l, "<!--") + 4); if ((i = index(v, "-->"))) v = substr(v, i + 3); else { cm = 1; v = "" } }
      while ((i = index(v, "<!--")) && (j = index(substr(v, i + 4), "-->"))) v = substr(v, 1, i - 1) substr(v, i + j + 6)
      c = v; sub(/^ ? ? ?(>[ \t]*|[-*+][ \t]+|[0-9]+[.)][ \t]+)+/, "", c)
      at = NR; t = l; h = (lvl(c) || tolower(c) ~ /^ ? ? ?<h[1-6]/) && pp(c)
      if (!h && !ph && p != "" && v ~ /^ ? ? ?(=+|-+)[ \t]*$/ && pp(p)) { h = 1; at = NR - 1; t = pt }
      ph = h; p = v; pt = l
      if (h) { if (hn) bad(at, t, "is a second Phase plan heading (the first is line " hn "): keep one; rename or delete this one"); else hn = at }
      if (!seen && lvl(v) == 2 && pp(v)) { seen = sec = 1; next }
      if (sec && lvl(v) && lvl(v) <= 2) sec = 0
    }
    !sec { next }
    { s = l; sub(/[ \t]+$/, "", s) }
    st == 0 && s != "" {
      if (row(s) && tolower(trim(cs)) == "status") { # only the last Status column is read (P3R5-11)
        if (ns > 1) bad(NR, l, "is the Phase plan header and has more than one Status cell: keep one Status column, the last")
        hc = cn; st = 1; next
      }
      bad(NR, l, row(s) ? "is the Phase plan header and its last cell is not Status: make Status the last column" : "stands between the `## Phase plan` heading and its table: the table comes first; delete the line or move it under the table after a blank line")
      st = 3; next
    }
    st == 1 { if (row(s) && cn == hc && sep(s)) { st = 2; next }
      bad(NR, l, "is no separator row under the Phase plan header: write one `---` cell for each of its " hc " cells"); st = 3; next }
    st == 2 {
      if (s == "" || lvl(v)) { st = 3; next }
      if (row(s) && cn == hc) { emit(); next }
      if (index(s, "\\|")) bad(NR, l, "holds `\\|`, which no Phase plan table cell may hold: write the cell without a pipe")
      bad(NR, l, "is in the Phase plan table and is no phase row: write each phase as a row from the left margin, `| <key> | ... | <Status> |`, with the header'"'"'s " hc " cells; delete anything else"); st = 3; next
    }
    st == 3 && (f || index(v, "|")) {
      bad(NR, l, "follows the Phase plan table: each phase is a row of that one table, and a note under it is plain text with no \047|\047 and no code fence; move the phase into the table or delete the line")
    }' "${2:-$JOB/checkpoint.md}"
}

cp_rows() { cp_scan rows "${1:-}"; }
cp_phases() { cp_scan rows | wc -l; }
cp_done_rows() { cp_scan "done"; }
cp_open_rows() { cp_scan open; }
cp_done_cells() { cp_scan cells; }
cp_unread() { cp_scan unread; }
cp_row() { CP_KEY="$1" cp_scan row; }
cp_row_sha() { CP_KEY="$1" cp_scan sha; }

# cp_size_warn: log when checkpoint.md is over 150 lines (F3: each child re-reads it whole; ledgers and
# decision detail belong in phases/). Called before every launch, so it repeats while the file stays over.
cp_size_warn() {
  local n; n="$(wc -l < "$JOB/checkpoint.md")"
  [ "$n" -le 150 ] || log "checkpoint.md is $n lines, over 150; move ledgers and detail to phases/, keep counts and pointers"
}

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

# cp_mark_usage <rows done before the child> <usage>: each Phase plan row done now and not before gets
# " · usage <usage>" at the end of its Status cell, the account's usage at the close of that phase (F10).
# The scanner gives each row's line number, so the edit lands on the row it read (P3R4-38).
cp_mark_usage() {
  local n k nums; nums="$(cp_scan nums)" || return 0
  while read -r n k; do
    [[ " $1 " != *" $k "* ]] || continue
    sed -i "${n}{/ · usage /!s/[[:space:]]*|[[:space:]]*\$/ · usage $2 |/}" "$JOB/checkpoint.md"
    log "phase row $k done; usage $2"
  done <<< "$nums"
}
