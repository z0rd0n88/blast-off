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

# a work-tree rename (git add -N; porcelain ` R new<NUL>old<NUL>`, Y column R) whose new name the
# checkpoint names passes: the old-name field is not a path of its own
new_job rename 'done'
repo
w="$(dirname "$JOB")"
echo x > "$w/orig-qz.txt"
git -C "$w" add orig-qz.txt && git -C "$w" -c user.name=t -c user.email=t@t commit -q -m old
mv "$w/orig-qz.txt" "$w/moved.txt" && git -C "$w" add -N moved.txt
git -C "$w" status --porcelain | command grep -qx ' R orig-qz.txt -> moved.txt' || fail "setup: not a work-tree rename: $(git -C "$w" status --porcelain)"
echo '- moved.txt renamed, left uncommitted' >> "$JOB/checkpoint.md"
rc=0; "$bo" run "$JOB" > rename.out 2>&1 || rc=$?
[ "$rc" -eq 0 ] || fail "named work-tree rename run exit $rc: $(cat rename.out; cat "$JOB/run.log")"

# "named" means the whole path, not a substring: doc/README is not named by doc/README.md (D2-5)
new_job token 'done'
repo
mkdir -p "$(dirname "$JOB")/doc"; echo x > "$(dirname "$JOB")/doc/README"
echo '- doc/README.md updated' >> "$JOB/checkpoint.md"
rc=0; "$bo" run "$JOB" > token.out 2>&1 || rc=$?
[ "$rc" -eq 7 ] || fail "README named only by README.md, under doc/: run exit $rc, want 7: $(cat token.out; cat "$JOB/run.log")"

# a bare name (no '/', no '.') is named only in backticks: `status: running` does not name a file
# called status, `status` does (P2R1-2)
new_job bare 'done'
repo
echo x > "$(dirname "$JOB")/status"
rc=0; "$bo" run "$JOB" > bare.out 2>&1 || rc=$?
[ "$rc" -eq 7 ] || fail "file status named by its status: line: run exit $rc, want 7: $(cat bare.out; cat "$JOB/run.log")"
echo '- left `status` uncommitted' >> "$JOB/checkpoint.md"
rc=0; "$bo" run "$JOB" > bare2.out 2>&1 || rc=$?
[ "$rc" -eq 0 ] || fail "backticked bare name not taken: run exit $rc: $(cat bare2.out; cat "$JOB/run.log")"

# a path at the end of a sentence is named; so is a path spelled relative to the workdir (D2-5).
# The workdir's basename names the unit, socket and lock, so it keeps the test prefix (P2R1-1)
new_job sentence 'done'
repo
SUFFIXES+=(sentence-sub); w="$(dirname "$JOB")"; sub="$w/test-$$-sentence-sub"; mkdir -p "$sub"
echo x > "$w/a.c"; echo x > "$sub/rel.txt"
printf -- '- edited a.c.\n- left rel.txt for the next child\n' >> "$JOB/checkpoint.md"
rc=0; "$bo" run "$JOB" "$sub" > sentence.out 2>&1 || rc=$?
[ "$rc" -eq 0 ] || fail "sentence-end or workdir-relative name not taken: run exit $rc: $(cat sentence.out; cat "$JOB/run.log")"
grep -q "tmux -L $TEST_ID-sentence-sub attach" "$JOB/run.log" || fail "sentence case ran outside the test namespace: $(cat "$JOB/run.log")"

# a git status that fails is not a clean tree (D2-6)
new_job gitfail 'done'
repo
echo garbage > "$(dirname "$JOB")/.git/index"
rc=0; "$bo" run "$JOB" > gitfail.out 2>&1 || rc=$?
[ "$rc" -eq 1 ] || fail "failing git status run exit $rc, want 1: $(cat gitfail.out; cat "$JOB/run.log")"
[ ! -e "$JOB/fake-marker" ] || fail "a child ran after git status failed"

# a workdir outside git is not checked
new_job nogit dirty 'done'
rc=0; "$bo" run "$JOB" > nogit.out 2>&1 || rc=$?
[ "$rc" -eq 0 ] || fail "non-git workdir run exit $rc: $(cat nogit.out; cat "$JOB/run.log")"
echo ok
