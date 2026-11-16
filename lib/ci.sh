# shellcheck shell=bash
# ci.sh: read a PR's CI before done (F7). JOB, WORKDIR set by job_init; TOP (ci_check) by chain_run.

# ci_wait <pr>: every run of the PR's head commit, watched with one blocking `gh run watch <id>
# --exit-status` each, then its conclusion recorded in gate-logs/ci-pr-<pr>.json. Runs are listed a few
# seconds after a push, so an empty list is re-read every 5 s for up to BLAST_OFF_CI_APPEAR (60) s: a
# wait for runs to exist, not a poll for them to finish. After the watches the list is read again and new
# runs (a workflow queued late or chained after the first) are watched too, at most 3 rounds (D4-6); a run
# still unwatched then is recorded as it stands. Each watch ends after BLAST_OFF_CI_WATCH (3600) s: a run
# that never completes (a runner label nobody serves, an approval) is logged and recorded as it stands, not
# success (P4R2-3). Exit 0 green (success, skipped or neutral), 10 red or no runs: absent checks are not a pass.
# workflow_dispatch runs are left out throughout (ci_runs).
ci_wait() {
  local pr="${1:-}" sha all new seen=' ' id i=0 round v r
  [[ $pr =~ ^[1-9][0-9]*$ ]] || die "PR '$pr' must be a PR number"
  r="$JOB/gate-logs/ci-pr-$pr.json"
  cd "$WORKDIR" || die "no workdir $WORKDIR"  # gh reads the repo from the workdir's remote
  sha="$(gh pr view "$pr" --json headRefOid | jq -r .headRefOid)" || die "gh pr view $pr failed"
  [[ $sha =~ ^[0-9a-f]{40}$ ]] || die "gh pr view $pr gave head '$sha', not a commit sha"
  while new="$(ci_runs "$sha")" || die "gh run list failed"
        [ -z "$new" ] && [ "$i" -lt "${BLAST_OFF_CI_APPEAR:-60}" ]; do
    sleep 5; i=$((i+5))
  done
  for round in 1 2 3; do
    for id in $new; do
      timeout "${BLAST_OFF_CI_WATCH:-3600}" gh run watch "$id" --exit-status > /dev/null 2>&1 || [ $? -ne 124 ] ||
        log "ci PR #$pr: run $id watch timed out after ${BLAST_OFF_CI_WATCH:-3600} s; recorded as it stands"
      seen+="$id "
    done
    all="$(ci_runs "$sha")" || die "gh run list failed"
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

# ci_runs <sha>: ids of that commit's runs, less the workflow_dispatch ones. A dispatch is a person's
# diagnostic (ci.yml's `only` input can make it one scenario), not the PR's CI: a green one is no pass and
# a red one no failure, so it is neither watched nor recorded (P2R1-1).
ci_runs() {
  gh run list --commit "$1" --limit 100 --json databaseId,event |
    jq -r '.[] | select(.event != "workflow_dispatch") | .databaseId'
}

# ci_check: at status done, exit 10 while a PR this job's Phase plan names in a Status cell (`PR #N` in
# any case, `PR#N`, or `/pull/N`; leading zeros dropped) has no ci-wait record for that PR, a red one, or
# one of an older head than the PR's now (ci_head). A PR named anywhere else in the checkpoint (prose,
# another cell) may be another repo's and is not read (issue 26). An absent record (no runs) of the
# current head is refused too while HEAD has a file under .github/workflows: runs were due, so absent
# is not a pass (D18). With no workflow file it passes, logged as not a pass: such a repo never gets
# runs, and refusing done there forever helps nobody (owner question P4Q1).
# The gate fails closed (P3R1-1): when no Status cell names a PR (no table, a heading or row the runner
# does not read, a row closed without its PR), every PR the checkpoint names anywhere is read instead, as
# before issue 26. What was read, what was named and left unread, and "nothing read" all go to run.log.
ci_check() {
  local pr v wf prs all other=
  all="$(ci_prs < "$JOB/checkpoint.md")"
  prs="$(sed -n '/^## Phase plan/,/^## /{/^| *[0-9]/p}' "$JOB/checkpoint.md" | awk -F'|' '{ print $(NF-1) }' | ci_prs)"
  if [ -n "$prs" ]; then
    for pr in $all; do [[ " $prs " == *" $pr "* ]] || other+=" $pr"; done
    log "CI read for the PRs Phase plan Status cells name: $prs${other:+; named elsewhere in checkpoint.md and not read:$other}"
  elif [ -n "$all" ]; then
    prs="$all"
    log "no Phase plan Status cell names a PR; CI read for every PR checkpoint.md names instead: $all (name this job's PR in its row's Status cell; write any other PR with no '#')"
  else
    log "no PR named in checkpoint.md; CI not read"
  fi
  for pr in $prs; do
    v="$(jq -r --argjson n "$pr" 'if .pr == $n then .verdict // "" else "" end' "$JOB/gate-logs/ci-pr-$pr.json" 2>/dev/null || true)"
    case "$v" in
      success) ci_head "$pr" ;;
      absent) ci_head "$pr"
        # read failing is not "no workflow": only no git repo at all (TOP empty, chain.sh) skips the read
        wf="$([ -z "$TOP" ] || git -C "$TOP" ls-tree -r --name-only HEAD -- .github/workflows)" || die "git ls-tree HEAD failed in $TOP"
        [ -z "$wf" ] || chain_end 10 "PR #$pr CI absent: no runs, but HEAD has a workflow file (${wf%%$'\n'*}); push to the PR branch for a run that is not a workflow_dispatch, then blast-off ci-wait <job-dir> $pr, then run again; done refused, status unchanged"
        log "PR #$pr: no CI runs and no workflow file at HEAD (absent, not a pass)" ;;
      failure) chain_end 10 "PR #$pr CI red or unfinished at $(jq -r '.head_sha // "?"' "$JOB/gate-logs/ci-pr-$pr.json") (gate-logs/ci-pr-$pr.json); fix and push if red, then blast-off ci-wait <job-dir> $pr (once its runs finish, if one was only unfinished), then run again; done refused, status unchanged" ;;
      *) chain_end 10 "PR #$pr CI unread: no readable record for PR $pr in gate-logs/ci-pr-$pr.json; blast-off ci-wait <job-dir> $pr, then run again" ;;
    esac
  done
}

# ci_prs: the PR numbers named on stdin, on one line, ascending.
ci_prs() {
  { command grep -oiE 'PR ?#[0-9]+|/pull/[0-9]+' || true; } | sed 's/.*[#/]//; s/^0*//; /^$/d' | sort -un | paste -sd' '
}

# ci_head <pr>: a passing record must be of the PR's head now, read with one `gh pr view` in the workdir
# (P4R1-1; whether the runner may call gh is owner question P4Q4). A push after ci-wait, or a gh failure,
# reads as unread; so does a call past BLAST_OFF_CI_HEAD (60) s, which would otherwise hold the lock (P4R2-2).
ci_head() {
  local h cur
  h="$(jq -r '.head_sha // ""' "$JOB/gate-logs/ci-pr-$1.json")"
  cur="$(cd "$WORKDIR" && timeout "${BLAST_OFF_CI_HEAD:-60}" gh pr view "$1" --json headRefOid | jq -r .headRefOid)" || cur=
  [ -n "$cur" ] && [ "$cur" = "$h" ] ||
    chain_end 10 "PR #$1 CI unread for head ${cur:-unknown (gh pr view $1 failed)}: gate-logs/ci-pr-$1.json is of '$h'; blast-off ci-wait <job-dir> $1, then run again"
}
