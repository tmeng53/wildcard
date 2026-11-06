#!/usr/bin/env bash
# Prints "true" when the Mac already tested every commit main gained between BASE and HEAD, so
# the scheduled `ios` run would only repeat it: each commit is a PR's squash, and that PR's head
# passed the `ios` job, on its own run or inside a manual run of a branch that merged it (the
# merge queue's combined screenshot run). Prints "false" otherwise, and on any doubt.
# Needs GH_TOKEN, GITHUB_REPOSITORY and a full clone. Usage: scripts/mac-covered.sh BASE HEAD
set -uo pipefail

base="${1:-}"
head="${2:-}"
repo="${GITHUB_REPOSITORY:?}"
if [ -z "$base" ] || [ -z "$head" ] || ! commits="$(git rev-list "$base..$head" 2>/dev/null)"; then
  echo false
  exit 0
fi

ios_passed() { # run id -> whether its ios job succeeded
  [ "$(gh api "repos/$repo/actions/runs/$1/jobs?per_page=50" \
    --jq '[.jobs[] | select(.name == "ios" and .conclusion == "success")] | length' 2>/dev/null)" \
    = 1 ]
}

# Heads of recent manual runs whose ios passed: a PR head merged into one of them was tested.
tested_heads=()
for line in $(gh api "repos/$repo/actions/workflows/verify.yml/runs?event=workflow_dispatch&per_page=30" \
  --jq '.workflow_runs[] | select(.conclusion == "success" or .conclusion == "failure") | "\(.id):\(.head_sha)"' \
  2>/dev/null); do
  if ios_passed "${line%%:*}"; then tested_heads+=("${line#*:}"); fi
done

for sha in $commits; do
  pr_head="$(gh api "repos/$repo/commits/$sha/pulls" \
    --jq '[.[] | select(.merged_at != null)][0].head.sha // ""' 2>/dev/null)"
  if [ -z "$pr_head" ]; then
    echo "$sha: not from a merged PR" >&2
    echo false
    exit 0
  fi
  covered=false
  for run in $(gh api "repos/$repo/actions/workflows/verify.yml/runs?head_sha=$pr_head&per_page=20" \
    --jq '.workflow_runs[].id' 2>/dev/null); do
    if ios_passed "$run"; then covered=true; break; fi
  done
  if [ "$covered" = false ] && [ "${#tested_heads[@]}" -gt 0 ]; then
    git fetch -q origin "$pr_head" "${tested_heads[@]}" 2>/dev/null || true
    for tested in "${tested_heads[@]}"; do
      if git merge-base --is-ancestor "$pr_head" "$tested" 2>/dev/null; then covered=true; break; fi
    done
  fi
  if [ "$covered" = false ]; then
    echo "$sha: its PR head $pr_head has no passing ios run" >&2
    echo false
    exit 0
  fi
  echo "$sha: tested on the Mac as $pr_head" >&2
done
echo true
