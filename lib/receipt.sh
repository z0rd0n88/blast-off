# shellcheck shell=bash
# receipt.sh: machine-written gate evidence (F8). JOB, WORKDIR set by job_init; TOP, JOBREL by chain_run.

# receipt_verdict <log>: the log's last non-empty line when it is a `GATE:` line, else fail: an appended
# log whose newest run died before its verdict has none, never the run before's (D4-8).
receipt_verdict() {
  local v; v="$(sed '/^[[:space:]]*$/d' "$1" 2>/dev/null | tail -n 1)"
  [[ $v == "GATE: "* ]] && printf '%s\n' "$v"
}

# receipt_refuse <msg>: a refused receipt leaves one run.log line (newlines flattened), then dies.
receipt_refuse() { log "receipt refused: ${1//$'\n'/ }" || true; die "$1"; }

# receipt_write <phase>: the verdict of gate-logs/phase-<phase>.log (the tests/run output the child saved)
# and the workdir's HEAD into gate-logs/phase-<phase>.json, from templates/receipt.json. Refused while the
# tree has uncommitted paths outside the job dir: the gate ran on a tree HEAD does not hold (D4-3). A FAIL
# verdict is written too, as evidence the runner refuses by name; exit 0 PASS, 1 otherwise. A refusal is
# logged to run.log and writes nothing: an earlier receipt stays, and its gate-log match refuses it (D4-8).
receipt_write() {
  local k="${1:-}" g v sha r top rel dirty
  [[ $k =~ ^[0-9A-Za-z._-]+$ ]] || receipt_refuse "phase '$k' must be a Phase plan row key: letters, digits, '.', '-' or '_'"
  g="gate-logs/phase-$k.log" r="$JOB/gate-logs/phase-$k.json"
  [ -s "$JOB/$g" ] || receipt_refuse "no gate log $JOB/$g; save the tests/run output there first"
  v="$(receipt_verdict "$JOB/$g")" || receipt_refuse "the last line of $JOB/$g is not a GATE: verdict; run the gate again and save its whole output there"
  top="$(git -C "$WORKDIR" rev-parse --show-toplevel)" || die "$WORKDIR is not in a git repo; a receipt names a commit"
  rel="$(realpath --relative-to="$top" "$JOB")"; [[ $rel != ..* && $rel != . ]] || rel=
  dirty="$(git -C "$top" status --porcelain -uall -- ${rel:+":(exclude)$rel"})" || die "git status failed in $top"
  [ -z "$dirty" ] || receipt_refuse "uncommitted paths outside the job dir; commit or revert them, run the gate again, then the receipt:"$'\n'"$dirty"
  sha="$(git -C "$WORKDIR" rev-parse HEAD)" || die "git rev-parse HEAD failed in $WORKDIR"
  jq --arg k "$k" --arg v "$v" --arg g "$g" --arg sha "$sha" --arg t "$(date -u +%FT%TZ)" '
    .phase = $k | .verdict = (if ($v | startswith("GATE: PASS")) then "PASS" else "FAIL" end)
    | .verdict_line = $v | .gate_log = $g | .head_sha = $sha | .utc = $t
    | .tally = (($v | capture("passed=(?<passed>[0-9]+) failed=(?<failed>[0-9]+) shellcheck=(?<shellcheck>[a-z]+)")
                   | .passed |= tonumber | .failed |= tonumber) // .tally)' \
    "$BLAST_OFF_HOME/templates/receipt.json" > "$r.tmp"
  mv "$r.tmp" "$r"
  log "receipt phase $k: $v at $sha"
  [[ $v == "GATE: PASS"* ]]
}

# receipt_check <rows done before the last child>: exit 9 unless every done Phase plan row names its commit
# (a 7 to 40 hex sha in its Status cell) in HEAD's history, and gate-logs/phase-<row>.json records a PASS
# for that commit whose own gate log still ends in that verdict (D4-2). A row done by the last child must
# also hold HEAD's code: nothing outside the job dir changed since its commit (D4-1). Off outside git.
receipt_check() {
  [ -n "$TOP" ] || return 0
  local k sha r v h g l ex=()
  [ -z "$JOBREL" ] || ex=(":(exclude)$JOBREL")
  rf() { jq -r ".$1 // \"\"" "$r" 2>/dev/null || true; }
  for k in $(cp_done_rows); do
    sha="$(cp_row_sha "$k")" r="$JOB/gate-logs/phase-$k.json"
    [ -n "$sha" ] || chain_end 9 "phase row $k is done but names no commit; put its sha in the Status cell, then blast-off receipt <job-dir> $k"
    git -C "$TOP" merge-base --is-ancestor "$sha" HEAD 2>/dev/null ||
      chain_end 9 "phase row $k commit $sha is not in HEAD's history; name the phase's commit on this branch"
    [ -s "$r" ] || chain_end 9 "phase row $k is done at $sha but has no receipt $r; blast-off receipt <job-dir> $k"
    v="$(rf verdict)" h="$(rf head_sha)" g="$(rf gate_log)" l="$(rf verdict_line)"
    [ "$v" = PASS ] || chain_end 9 "phase row $k receipt $r has verdict ${v:-unreadable}; fix and re-run the gate, then blast-off receipt <job-dir> $k"
    [[ $h == "$sha"* ]] || chain_end 9 "phase row $k receipt is for ${h:-no commit}, not $sha; run the gate on $sha's tree and write the receipt again"
    [[ -n $g && $l == "GATE: PASS"* && $(receipt_verdict "$JOB/$g" || true) == "$l" ]] ||
      chain_end 9 "phase row $k receipt does not match its gate log ${g:-(none)}; run the gate, save it there, then blast-off receipt <job-dir> $k"
    [[ " $1 " == *" $k "* ]] || git -C "$TOP" diff --quiet "$sha" HEAD -- "${ex[@]}" ||
      chain_end 9 "phase row $k is done at $sha but code changed after it (git diff $sha HEAD); run the gate on HEAD, blast-off receipt <job-dir> $k, and name HEAD's commit in the row"
  done
}

# receipt_all_done: at status done, exit 9 while a Phase plan row is not done (D4-4); status unchanged.
receipt_all_done() {
  local k; k="$(cp_open_rows)"; k="${k%%$'\n'*}"
  [ -z "$k" ] || chain_end 9 "status done but phase row $k is not done; close it (done, its commit, a receipt) or set the status back, then run again"
}
