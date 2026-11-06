# shellcheck shell=bash
# ci.sh: read a PR's CI before done (F7). JOB, WORKDIR set by job_init.

# ci_wait <pr>: every run of the PR's head commit, watched with one blocking `gh run watch <id>
# --exit-status` each, then its conclusion recorded in gate-logs/ci-pr-<pr>.json. Runs are listed a few
# seconds after a push, so an empty list is re-read every 5 s for up to BLAST_OFF_CI_APPEAR (60) s: a
# wait for runs to exist, not a poll for them to finish. Exit 0 green (success, skipped or neutral),
# 10 red or no runs: absent checks are not a pass.
ci_wait() {
  local pr="${1:-}" sha ids='' id i=0 v r
  [[ $pr =~ ^[1-9][0-9]*$ ]] || die "PR '$pr' must be a PR number"
  r="$JOB/gate-logs/ci-pr-$pr.json"
  cd "$WORKDIR" || die "no workdir $WORKDIR"  # gh reads the repo from the workdir's remote
  sha="$(gh pr view "$pr" --json headRefOid | jq -r .headRefOid)" || die "gh pr view $pr failed"
  while ids="$(gh run list --commit "$sha" --limit 100 --json databaseId | jq -r '.[].databaseId')" || die "gh run list failed"
        [ -z "$ids" ] && [ "$i" -lt "${BLAST_OFF_CI_APPEAR:-60}" ]; do
    sleep 5; i=$((i+5))
  done
  for id in $ids; do gh run watch "$id" --exit-status > /dev/null 2>&1 || true; done
  mkdir -p "$JOB/gate-logs"
  for id in $ids; do gh run view "$id" --json databaseId,name,conclusion || die "gh run view $id failed"; done |
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

# ci_check: at status done, exit 10 while a PR the checkpoint names (`PR #N` or `/pull/N`) has no
# ci-wait record or a red one. An absent record (no runs) passes, logged as not a pass: a repo with no
# workflow never gets runs, and refusing done there forever helps nobody (owner question P4Q1).
ci_check() {
  local pr v
  for pr in $({ command grep -oE 'PR #[0-9]+|/pull/[0-9]+' "$JOB/checkpoint.md" || true; } | sed 's/.*[#/]//' | sort -un); do
    v="$(jq -r '.verdict // ""' "$JOB/gate-logs/ci-pr-$pr.json" 2>/dev/null || true)"
    case "$v" in
      success) ;;
      absent) log "PR #$pr: no CI runs (absent, not a pass)" ;;
      failure) chain_end 10 "PR #$pr CI red (gate-logs/ci-pr-$pr.json); done refused, status unchanged" ;;
      *) chain_end 10 "PR #$pr CI unread: no record gate-logs/ci-pr-$pr.json; blast-off ci-wait <job-dir> $pr, then run again" ;;
    esac
  done
}
