#!/usr/bin/env bash
# 22-dirty-tree: after each child (and before child 1), uncommitted paths in the workdir's repo that
# checkpoint.md does not name stop the chain with exit 7 and `git status --porcelain` in run.log.
# Named paths pass; the job dir's own files never count; a workdir outside git is not checked.
source "$REPO/tests/lib.sh"
use_fakes
export CLAUDE_FLAGS="--model fake --effort low" GH_TOKEN=dummy-not-a-token JOB_CHILD_TIMEOUT=30
bo="$REPO/bin/blast-off"
repo() { # repo: make the job's workdir a git repo with one commit; the job dir stays untracked
  local w; w="$(dirname "$JOB")"
  git -C "$w" init -q && git -C "$w" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
}

# a child leaves an unnamed untracked file -> exit 7, porcelain logged, no next child
new_job dirty dirty 'done'
repo
rc=0; "$bo" run "$JOB" > dirty.out 2>&1 || rc=$?
log="$JOB/run.log"
[ "$rc" -eq 7 ] || fail "dirty run exit $rc, want 7: $(cat dirty.out; cat "$log")"
grep -q 'dirty tree after child 1: checkpoint.md does not name stray.txt; git status --porcelain:' "$log" || fail "no dirty line: $(cat "$log")"
grep -qx '?? stray.txt' "$log" || fail "porcelain not in run.log: $(cat "$log")"
grep -q 'child 2 launched' "$log" && fail "child 2 launched on a dirty tree"
grep -q '^status: running$' "$JOB/checkpoint.md" || fail "exit 7 changed the status"

# a re-run on the same dirty tree refuses before child 1
rc=0; "$bo" run "$JOB" > dirty2.out 2>&1 || rc=$?
[ "$rc" -eq 7 ] || fail "re-run on a dirty tree exit $rc, want 7"
grep -q 'dirty tree before child 1: checkpoint.md does not name stray.txt' "$log" || fail "no pre-launch refusal: $(cat "$log")"
[ "$(grep -c '^child=' "$JOB/fake-marker")" -eq 1 ] || fail "a child ran on a dirty tree: $(cat "$JOB/fake-marker")"

# a path the checkpoint names passes; the untracked job dir never counts
new_job named dirty-named 'done'
repo
rc=0; "$bo" run "$JOB" > named.out 2>&1 || rc=$?
[ "$rc" -eq 0 ] || fail "named dirty path run exit $rc: $(cat named.out; cat "$JOB/run.log")"
grep -q 'child 2 launched' "$JOB/run.log" || fail "named path stopped the chain"
grep -q 'tree after child 1: uncommitted, named in checkpoint.md: named.txt' "$JOB/run.log" || fail "named dirty path not logged: $(cat "$JOB/run.log")"

# a clean child in a repo whose job dir is untracked and not ignored
new_job clean 'done'
repo
rc=0; "$bo" run "$JOB" > clean.out 2>&1 || rc=$?
[ "$rc" -eq 0 ] || fail "clean run exit $rc (job dir counted as dirty?): $(cat clean.out; cat "$JOB/run.log")"
grep -q 'dirty tree' "$JOB/run.log" && fail "clean tree reported dirty"

# a workdir outside git is not checked
new_job nogit dirty 'done'
rc=0; "$bo" run "$JOB" > nogit.out 2>&1 || rc=$?
[ "$rc" -eq 0 ] || fail "non-git workdir run exit $rc: $(cat nogit.out; cat "$JOB/run.log")"
echo ok
