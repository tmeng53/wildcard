#!/usr/bin/env bash
# Stop hook (.claude/settings.json): a Claude cloud session can't end its turn while
# scripts/verify.sh is red on a branch with changes of its own.
# From sponge-ai-lab/engineering-skills (cloud-test-environment skill's template).
# On failure it exits 2, which blocks the stop and hands the error to Claude.
# It blocks once per turn: on the next stop (`stop_hook_active`) it lets it through,
# so a check Claude can't fix (no toolchain, main already red) ends in a report to the
# user, not a loop. Does nothing outside the cloud, or when the branch has no changes.
set -uo pipefail
VERIFY=(scripts/verify.sh)
LIMIT=840   # seconds; with the 20 s kill grace, stays under the hook's 900 s timeout

[ "${CLAUDE_CODE_REMOTE:-}" = "true" ] || exit 0

# Read a field of the hook's JSON input (booleans print as true/false).
input="$(cat)"
field() {
  python3 -c 'import json, sys
v = json.loads(sys.argv[1]).get(sys.argv[2])
print("" if v is None else str(v).lower() if isinstance(v, bool) else v)' "$input" "$1" 2>/dev/null
}
[ "$(field stop_hook_active)" = "true" ] && exit 0

# The input's cwd follows the session into a worktree; CLAUDE_PROJECT_DIR doesn't.
# Use cwd only when it's a checkout of this repo (same git common dir); a session can
# also sit in another repo or outside any repo, and then the project dir is checked.
project="${CLAUDE_PROJECT_DIR:-$(dirname "$0")/..}"
common() { (cd "$1" 2>/dev/null && cd "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd -P); }
target="$project"
dir="$(field cwd)"
if [ -n "$dir" ] && [ -n "$(common "$dir")" ] && [ "$(common "$dir")" = "$(common "$project")" ]; then
  target="$dir"
fi
top="$(cd "$target" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)"
[ -n "$top" ] && cd "$top" || exit 0   # cwd may be a subdirectory

# Explicit refspec: some clones have none configured, which would leave origin/main missing.
git rev-parse --verify --quiet origin/main >/dev/null ||
  git fetch --quiet origin '+refs/heads/main:refs/remotes/origin/main' 2>/dev/null
# With no merge base (main unknown, or a shallow clone) every change counts as the branch's own.
if base="$(git merge-base HEAD origin/main 2>/dev/null)"; then
  if git diff --quiet "$base" && [ -z "$(git ls-files --others --exclude-standard)" ]; then
    exit 0
  fi
fi

# One log per checkout, inside .git so it's never committed; each run overwrites it.
log="$(git rev-parse --absolute-git-dir)/verify-on-stop.log"
# timeout runs the check in its own process group (pgid = its pid). After a
# timeout, kill whatever is left of that group: --kill-after only covers the
# command itself, not children that outlive it.
NO_COLOR=1 timeout --kill-after=20 "$LIMIT" "${VERIFY[@]}" >"$log" 2>&1 &
pid=$!
wait "$pid"
status=$?
{ [ "$status" -eq 124 ] || [ "$status" -eq 137 ]; } && kill -KILL -- "-$pid" 2>/dev/null
if [ "$status" -eq 0 ]; then
  rm -f "$log"   # a log left behind is the last failure
  exit 0
fi

{
  { [ "$status" -eq 124 ] || [ "$status" -eq 137 ]; } && echo "${VERIFY[*]} timed out after ${LIMIT}s."
  echo "${VERIFY[*]} failed, so this turn can't end yet. Last lines (full log: $log):"
  tail -n 40 "$log"
  echo
  echo "Fix it and run it again. If you can't, tell the user exactly which check is red and why; your next stop will be allowed."
} >&2
exit 2
