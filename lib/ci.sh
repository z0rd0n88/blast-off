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

# ci_check: at status done, exit 10 unless every done Phase plan row's Status cell names the phase's own PR
# (`PR #N` in any case, `PR#N`, or `/pull/N`; leading zeros dropped) or says `no PR` (owner ruling 1,
# phase 3). Refused: a done row with neither or with both, a cell holding another '#<n>' or /pull/ (a PR
# written a way that is not read), and a job with no done row at all (no table, a heading or rows the
# runner does not read), where nothing says which PR to read or that there is none. Nothing outside those
# cells is read: a PR named in prose or another cell may be another repo's (issue 26).
# Each PR named needs a ci-wait record for that PR, of the PR's head now (ci_head), that is not red. An
# absent record (no runs) passes, logged as not a pass, only when that head commit has no file under
# .github/workflows: runs were never due on it. With a file there runs were due and absent is refused
# (D18), and so it is when the commit cannot be read (not fetched, or the workdir in no git repo). The
# PR's head decides, not the workdir's HEAD that issue 26 named: owner ruling 2.
ci_check() {
  local k cell n pr v h wf prs cells='' none='' stray='#[0-9]|/pull/' end='then run again; done refused, status unchanged'
  while IFS='|' read -r k cell; do
    n="$(ci_prs <<< "$cell")"
    [[ ! $(sed -E 's~PR ?#[0-9]+|/pull/[0-9]+~~Ig' <<< "$cell") =~ $stray ]] ||
      chain_end 10 "phase row $k Status cell holds a '#<n>' or /pull/ the runner does not read as a PR: write each of the phase's PRs as \`PR #<n>\` and no other '#<n>' there, $end"
    if command grep -qiE '(^|[^[:alnum:]])no PR([^[:alnum:]]|$)' <<< "$cell"; then
      [ -z "$n" ] || chain_end 10 "phase row $k Status cell says \`no PR\` and names PR #${n// /, #}: keep the one that is true, $end"
      none+=" $k"
    else
      [ -n "$n" ] || chain_end 10 "phase row $k is done but its Status cell says neither \`PR #<n>\` nor \`no PR\`: after the sha write \`PR #<n>\` (the phase's own PR) or \`no PR\` (the phase opened none), $end"
    fi
    cells+="$cell"$'\n'
  done < <(cp_done_cells)
  [ -n "$cells" ] || chain_end 10 "status done but the Phase plan has no done row, so nothing says which PR to read or that there is none: add a \`## Phase plan\` table with a row per phase (first cell a digit, Status cell last) that ends \`done (<sha>) · PR #<n>\` or \`done (<sha>) · no PR\`, $end"
  prs="$(ci_prs <<< "$cells")"
  log "CI at done: PRs read: ${prs:-none}; rows that say no PR:${none:- none}"
  for pr in $prs; do
    v="$(jq -r --argjson n "$pr" 'if .pr == $n then .verdict // "" else "" end' "$JOB/gate-logs/ci-pr-$pr.json" 2>/dev/null || true)"
    case "$v" in
      success) ci_head "$pr" ;;
      absent) ci_head "$pr"; h="$(jq -r .head_sha "$JOB/gate-logs/ci-pr-$pr.json")"
        # git -C "" would read the cwd's repo, so no repo is its own refusal; any failing read is "cannot be read"
        [ -n "$TOP" ] || chain_end 10 "PR #$pr CI absent: no runs, and the workdir is in no git repo, so whether runs were due at the PR's head $h cannot be read; run from a checkout of the PR's repo; done refused, status unchanged"
        wf="$(git -C "$TOP" ls-tree -r --name-only "$h^{commit}" -- .github/workflows 2>/dev/null)" ||
          chain_end 10 "PR #$pr CI absent: no runs, and its head $h is no commit git can read in $TOP, so whether runs were due cannot be read; git -C $TOP fetch origin pull/$pr/head, $end"
        [ -z "$wf" ] || chain_end 10 "PR #$pr CI absent: no runs, but its head ${h:0:7} has a workflow file (${wf%%$'\n'*}); push to the PR branch for a run that is not a workflow_dispatch, then blast-off ci-wait <job-dir> $pr, then run again; if no workflow can start on this PR (a branch or path filter), there is no override: ask the owner; done refused, status unchanged"
        log "PR #$pr: no CI runs and no workflow file at its head ${h:0:7} (no CI configured; absent, not a pass)" ;;
      failure) chain_end 10 "PR #$pr CI red or unfinished at $(jq -r '.head_sha // "?"' "$JOB/gate-logs/ci-pr-$pr.json") (gate-logs/ci-pr-$pr.json); fix and push if red, then blast-off ci-wait <job-dir> $pr (once its runs finish, if one was only unfinished), then run again; done refused, status unchanged" ;;
      *) chain_end 10 "PR #$pr CI unread: no readable record for PR $pr in gate-logs/ci-pr-$pr.json; blast-off ci-wait <job-dir> $pr, then run again" ;;
    esac
  done
}

# ci_prs: the PR numbers named on stdin, on one line, ascending.
ci_prs() {
  { command grep -aoiE 'PR ?#[0-9]+|/pull/[0-9]+' || true; } | sed 's/.*[#/]//; s/^0*//; /^$/d' | sort -un | paste -sd' '
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
