#!/usr/bin/env bash
# Stop hook (.claude/settings.json): a Claude cloud session can't end its turn while
# scripts/verify.sh is red on a branch with changes of its own. On failure it exits 2,
# which blocks the stop and hands the error to Claude so it keeps working.
# It blocks once per turn: when Claude stops again after a block (`stop_hook_active`),
# it lets the stop through, so a check Claude can't fix (no toolchain, main already red)
# ends in a report to the user instead of an endless loop.
# Does nothing outside the cloud, and nothing when the branch has no changes of its own.
set -uo pipefail
[ "${CLAUDE_CODE_REMOTE:-}" = "true" ] || exit 0
cd "${CLAUDE_PROJECT_DIR:-$(dirname "$0")/..}"

input="$(cat)"
field() { python3 -c 'import json,sys
try:
    v = json.loads(sys.argv[1]).get(sys.argv[2])
    if v is not None: print(str(v).lower() if isinstance(v, bool) else v)
except Exception: pass' "$input" "$1"; }
[ "$(field stop_hook_active)" = "true" ] && exit 0

base="$(git merge-base HEAD origin/main 2>/dev/null)" || exit 0
if git diff --quiet "$base" && [ -z "$(git ls-files --others --exclude-standard)" ]; then
  exit 0
fi

log="/tmp/verify-on-stop-$(field session_id | tr -cd 'a-zA-Z0-9_-').log"
if scripts/verify.sh >"$log" 2>&1; then
  exit 0
fi

{
  echo "scripts/verify.sh failed, so this turn can't end yet. Last lines (full log: $log):"
  tail -n 40 "$log"
  echo
  echo "Fix the failure and run it again. If you can't fix it, tell the user exactly which check is red and why; your next stop will be allowed."
} >&2
exit 2
