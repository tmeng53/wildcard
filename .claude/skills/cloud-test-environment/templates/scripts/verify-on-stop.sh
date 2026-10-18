#!/usr/bin/env bash
# Stop hook: a cloud agent session can't end its turn while the repo's checks are red.
# Template from sponge-ai-lab/engineering-skills (cloud-test-environment skill).
# Replace VERIFY with the repo's own check command (lint, typecheck, tests), the
# `verify` command in AGENTS.md. Prefer one that checks only changed packages if the
# full suite is slow.
# On failure it exits 2, which blocks the stop and hands the error to the agent.
# It blocks once per turn: on the next stop (`stop_hook_active`) it lets it through,
# so a check the agent can't fix ends in a report to the user, not a loop.
# Does nothing outside a cloud session, or when the branch has no changes of its own.
set -uo pipefail
VERIFY=(pnpm verify)
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
dir="$(field cwd)"
cd "${dir:-${CLAUDE_PROJECT_DIR:-$(dirname "$0")/..}}" || exit 0
cd "$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0   # cwd may be a subdirectory

base="$(git merge-base HEAD origin/main 2>/dev/null)" || exit 0
if git diff --quiet "$base" && [ -z "$(git ls-files --others --exclude-standard)" ]; then
  exit 0
fi

log="$(mktemp -t verify-on-stop.XXXXXX.log)"
# timeout runs the check in its own process group (pgid = its pid). After a
# timeout, kill whatever is left of that group: --kill-after only covers the
# command itself, not children that outlive it.
NO_COLOR=1 timeout --kill-after=20 "$LIMIT" "${VERIFY[@]}" >"$log" 2>&1 &
pid=$!
wait "$pid"
status=$?
[ "$status" -eq 124 ] || [ "$status" -eq 137 ] && kill -KILL -- "-$pid" 2>/dev/null
if [ "$status" -eq 0 ]; then
  rm -f "$log"   # keep only failed logs
  exit 0
fi

{
  [ "$status" -eq 124 ] || [ "$status" -eq 137 ] && echo "${VERIFY[*]} timed out after ${LIMIT}s."
  echo "${VERIFY[*]} failed, so this turn can't end yet. Last lines (full log: $log):"
  tail -n 40 "$log"
  echo
  echo "Fix it and run it again. If you can't, tell the user exactly which check is red and why; your next stop will be allowed."
} >&2
exit 2
