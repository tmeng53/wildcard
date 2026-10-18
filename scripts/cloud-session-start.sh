#!/usr/bin/env bash
# SessionStart hook (.claude/settings.json): gives a Claude cloud session the services
# scripts/verify.sh needs, so checks run before a push. Does nothing outside the cloud.
# Cloud sessions are Linux: they run the Swift package tests, the web page and Supabase,
# never the iOS simulator (that runs in CI's macOS job, added with the Xcode project).
# Each step reports its own failure and the rest still run, so the session always learns
# which checks will be inconclusive.
set -uo pipefail
[ "${CLAUDE_CODE_REMOTE:-}" = "true" ] || exit 0
cd "${CLAUDE_PROJECT_DIR:-$(dirname "$0")/..}"

ready=()
missing=()

if command -v swift >/dev/null 2>&1; then
  ready+=("Swift")
else
  missing+=("Swift (allow swift.org in the cloud environment)")
fi

# The pinned SwiftLint, the same one CI lints with.
if scripts/install-swiftlint.sh >/tmp/swiftlint-install.log 2>&1; then
  ready+=("SwiftLint")
else
  missing+=("SwiftLint (see /tmp/swiftlint-install.log)")
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
  if ! docker info >/dev/null 2>&1; then
    missing+=("Docker (see /tmp/dockerd.log)")
  # Same CLI choice as scripts/verify.sh: a real binary if installed, else npx.
  elif { if type -P supabase >/dev/null; then supabase start; else npx --yes supabase@2.121.0 start; fi; } >/tmp/supabase-start.log 2>&1; then
    ready+=("Docker" "local Supabase")
  else
    missing+=("local Supabase (see /tmp/supabase-start.log)")
  fi
fi

if [ -f web/package.json ]; then
  if pnpm --dir web install --frozen-lockfile --prefer-offline >/tmp/pnpm-install.log 2>&1; then
    ready+=("web dependencies")
  else
    missing+=("web dependencies (see /tmp/pnpm-install.log)")
  fi
fi

[ "${#ready[@]}" -gt 0 ] && echo "Ready: ${ready[*]}."
[ "${#ready[@]}" -eq 0 ] && [ "${#missing[@]}" -eq 0 ] && echo "Ready: nothing to start yet."
if [ "${#missing[@]}" -gt 0 ]; then
  printf 'Not available, so their checks are inconclusive: %s\n' "${missing[*]}"
fi
exit 0
