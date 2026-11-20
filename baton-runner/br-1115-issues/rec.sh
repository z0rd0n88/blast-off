#!/usr/bin/env bash
# rec.sh "<message>": commit baton-runner/ to the run branch run/br-1115-issues without switching branches
# (owner ruling 2026-11-19: run records stay off phase branches and PRs; z0rd0n88/my-skills#47).
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
B=run/br-1115-issues idx=$(mktemp)
trap 'rm -f "$idx"' EXIT
GIT_INDEX_FILE=$idx git read-tree --empty
GIT_INDEX_FILE=$idx git add -f baton-runner
tree=$(GIT_INDEX_FILE=$idx git write-tree)
git fetch -q origin "$B" 2>/dev/null || true
parent=$(git rev-parse -q --verify "refs/remotes/origin/$B" || true)
if [ -n "$parent" ] && [ "$(git rev-parse "$parent^{tree}")" = "$tree" ]; then echo "records unchanged"; exit 0; fi
c=$(git commit-tree "$tree" ${parent:+-p "$parent"} -m "$1")
git push -q origin "$c:refs/heads/$B"
git update-ref "refs/remotes/origin/$B" "$c"
echo "records -> $B ${c:0:7}"
