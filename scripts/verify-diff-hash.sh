#!/usr/bin/env bash
# Prints the hash that names the exact diff a verifier checked
# (raise-pr skill, Independent verification).
# Usage: scripts/verify-diff-hash.sh <full head SHA>
# It hashes, for every file the PR changes, its path, mode and content id (git blob
# hash) on the merge base with main and on the pushed head. That pins the exact bytes
# of the change without rendering a text diff, so no git config, attribute or diff
# option can change the result, and no working tree is read.
set -euo pipefail
# Replace refs and grafts are local and could rewrite history for this script.
export GIT_NO_REPLACE_OBJECTS=1 GIT_GRAFT_FILE=/nonexistent/no-grafts

sha="${1:?usage: scripts/verify-diff-hash.sh <full head SHA>}"
[[ "$sha" =~ ^[0-9a-f]{40}$ ]] || { echo "need a full 40-character commit SHA, got: $sha" >&2; exit 2; }

# Explicit refspec: some clones have none configured, which would leave origin/* stale.
git fetch --quiet --prune origin '+refs/heads/*:refs/remotes/origin/*'
if [ -z "$(git branch --remotes --list 'origin/*' --contains "$sha" 2>/dev/null)" ]; then
  echo "$sha is not on any pushed branch; push it first" >&2
  exit 1
fi

base="$(git merge-base origin/main "$sha")" || {
  echo "no merge base between origin/main and $sha (a shallow clone? run git fetch --unshallow)" >&2
  exit 1
}
git diff-tree -r -z --raw --no-renames --full-index "$base" "$sha" | sha256sum | cut -d' ' -f1
