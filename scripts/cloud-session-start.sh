#!/usr/bin/env bash
# SessionStart hook (.claude/settings.json): gives a Claude cloud session the services
# scripts/verify.sh needs, so checks run before a push. Does nothing outside the cloud.
# Cloud sessions are Linux: they run the Swift package tests, the web page and Supabase,
# never the iOS simulator (that runs on the self-hosted Mac).
set -euo pipefail
[ "${CLAUDE_CODE_REMOTE:-}" = "true" ] || exit 0
cd "${CLAUDE_PROJECT_DIR:-$(dirname "$0")/..}"

ready=()

if command -v swift >/dev/null 2>&1; then
  ready+=("Swift $(swift --version 2>/dev/null | head -1 | sed -E 's/.*version ([0-9.]+).*/\1/')")
else
  echo "No Swift toolchain: swift test is inconclusive until swift.org is allowed in the cloud environment." >&2
fi

if [ -d supabase ]; then
  # Docker is installed in the cloud image but not running.
  if ! docker info >/dev/null 2>&1; then
    nohup dockerd >/tmp/dockerd.log 2>&1 &
    for _ in $(seq 1 60); do
      docker info >/dev/null 2>&1 && break
      sleep 0.5
    done
  fi
  npx --yes supabase start >/tmp/supabase-start.log 2>&1
  ready+=("Docker" "local Supabase")
fi

if [ -f web/package.json ]; then
  pnpm --dir web install --frozen-lockfile --prefer-offline >/tmp/pnpm-install.log 2>&1
  ready+=("web dependencies")
fi

if [ "${#ready[@]}" -gt 0 ]; then
  echo "Ready: ${ready[*]}. Logs in /tmp/*.log."
else
  echo "Ready: nothing to start yet."
fi
