# shellcheck shell=bash
# ci.sh: read a PR's CI before done (F7). JOB, WORKDIR set by job_init.

# ci_wait <pr>: every run of the PR's head commit, watched with one blocking `gh run watch <id>
# --exit-status` each, then its conclusion recorded in gate-logs/ci-pr-<pr>.json. Runs are listed a few
# seconds after a push, so an empty list is re-read every 5 s for up to BLAST_OFF_CI_APPEAR (60) s: a
# wait for runs to exist, not a poll for them to finish. After the watches the list is read again and new
# runs (a workflow queued late or chained after the first) are watched too, at most 3 rounds (D4-6); a run
# still unwatched then is recorded as it stands. Exit 0 green (success, skipped or neutral), 10 red or no
# runs: absent checks are not a pass.
ci_wait() {
  local pr="${1:-}" sha all new seen=' ' id i=0 round v r
  [[ $pr =~ ^[1-9][0-9]*$ ]] || die "PR '$pr' must be a PR number"
  r="$JOB/gate-logs/ci-pr-$pr.json"
  cd "$WORKDIR" || die "no workdir $WORKDIR"  # gh reads the repo from the workdir's remote
  sha="$(gh pr view "$pr" --json headRefOid | jq -r .headRefOid)" || die "gh pr view $pr failed"
  [[ $sha =~ ^[0-9a-f]{40}$ ]] || die "gh pr view $pr gave head '$sha', not a commit sha"
  while new="$(gh run list --commit "$sha" --limit 100 --json databaseId | jq -r '.[].databaseId')" || die "gh run list failed"
        [ -z "$new" ] && [ "$i" -lt "${BLAST_OFF_CI_APPEAR:-60}" ]; do
    sleep 5; i=$((i+5))
  done
  for round in 1 2 3; do
    for id in $new; do gh run watch "$id" --exit-status > /dev/null 2>&1 || true; seen+="$id "; done
    all="$(gh run list --commit "$sha" --limit 100 --json databaseId | jq -r '.[].databaseId')" || die "gh run list failed"
    new=; for id in $all; do [[ $seen == *" $id "* ]] || new+="$id "; done
    [ -n "$new" ] || break
  done
  [ "$round" -lt 3 ] || [ -z "$new" ] || log "ci PR #$pr: runs $new listed after 3 watch rounds; recorded unwatched"
  mkdir -p "$JOB/gate-logs"
  for id in $seen $new; do gh run view "$id" --json databaseId,name,conclusion || die "gh run view $id failed"; done |
    jq -s --argjson pr "$pr" --arg sha "$sha" --arg t "$(date -u +%FT%TZ)" '
      [.[] | {id: .databaseId, name, conclusion}] as $runs
      | {pr: $pr, head_sha: $sha, utc: $t, runs: $runs,
         verdict: (if $runs == [] then "absent"
                   elif all($runs[]; .conclusion | IN("success", "skipped", "neutral")) then "success"
                   else "failure" end)}' > "$r.tmp"
  mv "$r.tmp" "$r"
  v="$(jq -r .verdict "$r")"
  log "ci PR #$pr at $sha: $v ($(jq -r '[.runs[] | "\(.name) \(.conclusion)"] | join(", ")' "$r"))"
  [ "$v" = success ] || exit 10
}

# ci_check: at status done, exit 10 while a PR the checkpoint names (`PR #N` in any case, `PR#N`, or
# `/pull/N`; leading zeros dropped) has no ci-wait record for that PR, a red one, or one of an older head
# than the PR's now (ci_head). An absent record (no runs) of the current head passes, logged as not a
# pass: a repo with no workflow never gets runs, and refusing done there forever helps nobody (owner
# question P4Q1).
ci_check() {
  local pr v
  for pr in $({ command grep -oiE 'PR ?#[0-9]+|/pull/[0-9]+' "$JOB/checkpoint.md" || true; } | sed 's/.*[#/]//; s/^0*//; /^$/d' | sort -un); do
    v="$(jq -r --argjson n "$pr" 'if .pr == $n then .verdict // "" else "" end' "$JOB/gate-logs/ci-pr-$pr.json" 2>/dev/null || true)"
    case "$v" in
      success) ci_head "$pr" ;;
      absent) log "PR #$pr: no CI runs (absent, not a pass)"; ci_head "$pr" ;;
      failure) chain_end 10 "PR #$pr CI red (gate-logs/ci-pr-$pr.json); done refused, status unchanged" ;;
      *) chain_end 10 "PR #$pr CI unread: no readable record for PR $pr in gate-logs/ci-pr-$pr.json; blast-off ci-wait <job-dir> $pr, then run again" ;;
    esac
  done
}

# ci_head <pr>: a passing record must be of the PR's head now, read with one `gh pr view` in the workdir
# (P4R1-1; whether the runner may call gh is owner question P4Q4). A push after ci-wait, or a gh failure,
# reads as unread.
ci_head() {
  local h cur
  h="$(jq -r '.head_sha // ""' "$JOB/gate-logs/ci-pr-$1.json")"
  cur="$(cd "$WORKDIR" && gh pr view "$1" --json headRefOid | jq -r .headRefOid)" || cur=
  [ -n "$cur" ] && [ "$cur" = "$h" ] ||
    chain_end 10 "PR #$1 CI unread for head ${cur:-unknown (gh pr view $1 failed)}: gate-logs/ci-pr-$1.json is of '$h'; blast-off ci-wait <job-dir> $1, then run again"
}
