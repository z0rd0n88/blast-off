# shellcheck shell=bash
# receipt.sh: machine-written gate evidence (F8). JOB, WORKDIR, TOP set by job_init / chain_run.

# receipt_write <phase>: the last `GATE:` line of gate-logs/phase-<phase>.log (the tests/run output the
# child saved) and the workdir's HEAD into gate-logs/phase-<phase>.json, from templates/receipt.json.
# A FAIL verdict is written too, as evidence the runner refuses by name; exit 0 PASS, 1 otherwise.
receipt_write() {
  local k="${1:-}" g v sha r
  [[ $k =~ ^[0-9A-Za-z_-]+$ ]] || die "phase '$k' must be a Phase plan row key: letters, digits, '-' or '_'"
  g="gate-logs/phase-$k.log" r="$JOB/gate-logs/phase-$k.json"
  [ -s "$JOB/$g" ] || die "no gate log $JOB/$g; save the tests/run output there first"
  v="$(command grep -a '^GATE: ' "$JOB/$g" | tail -n 1)" || die "no GATE: verdict line in $JOB/$g"
  sha="$(git -C "$WORKDIR" rev-parse HEAD)" || die "git rev-parse HEAD failed in $WORKDIR"
  jq --arg k "$k" --arg v "$v" --arg g "$g" --arg sha "$sha" --arg t "$(date -u +%FT%TZ)" '
    .phase = $k | .verdict = (if ($v | startswith("GATE: PASS")) then "PASS" else "FAIL" end)
    | .verdict_line = $v | .gate_log = $g | .head_sha = $sha | .utc = $t
    | .tally = ($v | capture("passed=(?<passed>[0-9]+) failed=(?<failed>[0-9]+) shellcheck=(?<shellcheck>[a-z]+)")
                   | .passed |= tonumber | .failed |= tonumber) // .tally' \
    "$BLAST_OFF_HOME/templates/receipt.json" > "$r.tmp"
  mv "$r.tmp" "$r"
  log "receipt phase $k: $v at $sha"
  [[ $v == "GATE: PASS"* ]]
}

# receipt_check: exit 9 unless every done Phase plan row names its commit (a 7 to 40 hex sha in its
# Status cell) and gate-logs/phase-<row>.json records a PASS for that commit. Off outside git: no commit.
receipt_check() {
  [ -n "$TOP" ] || return 0
  local k sha r v h
  for k in $(cp_done_rows); do
    sha="$(cp_row_sha "$k")" r="$JOB/gate-logs/phase-$k.json"
    [ -n "$sha" ] || chain_end 9 "phase row $k is done but names no commit; put its sha in the Status cell, then blast-off receipt <job-dir> $k"
    [ -s "$r" ] || chain_end 9 "phase row $k is done at $sha but has no receipt $r; blast-off receipt <job-dir> $k"
    v="$(jq -r '.verdict // ""' "$r" 2>/dev/null)" h="$(jq -r '.head_sha // ""' "$r" 2>/dev/null)" || true
    [ "$v" = PASS ] || chain_end 9 "phase row $k receipt $r has verdict ${v:-unreadable}; fix and re-run the gate, then blast-off receipt <job-dir> $k"
    [[ $h == "$sha"* ]] || chain_end 9 "phase row $k receipt is for ${h:-no commit}, not $sha; run the gate on $sha's tree and write the receipt again, or name the receipted commit in the row"
  done
}
