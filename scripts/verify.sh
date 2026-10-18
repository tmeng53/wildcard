#!/usr/bin/env bash
# Every check that runs without a Mac. The cloud stop hook and agents run this before every push.
set -euo pipefail
cd "$(dirname "$0")/.."

# With no arguments it runs every check. CI's jobs name the parts their runner can run:
# swift and web on macOS, supabase on Linux (macOS runners have no Docker).
parts="${*:-swift web supabase}"
want() { [[ " $parts " == *" $1 "* ]]; }

ran=0
inconclusive=()
if want swift && compgen -G "ios/Packages/*/Package.swift" >/dev/null; then
  echo "==> swift format lint"
  swift format lint --strict --recursive ios
  # SwiftLint isn't part of the Swift toolchain; scripts/install-swiftlint.sh installs the
  # pinned version. CI must have it. Elsewhere a missing or different SwiftLint makes this one
  # check inconclusive, and the run ends saying so instead of "ok".
  pinned="$(cat scripts/swiftlint-version)"
  installed="$(swiftlint version 2>/dev/null || true)"
  if [ "$installed" = "$pinned" ]; then
    echo "==> swiftlint"
    swiftlint lint --strict --quiet
  elif [ "${CI:-}" = "true" ]; then
    echo "swiftlint $pinned is not installed on this CI runner (found '${installed:-none}')" >&2
    exit 1
  else
    echo "==> swiftlint: need $pinned, found '${installed:-none}' (run scripts/install-swiftlint.sh)"
    inconclusive+=("swiftlint")
  fi

  for pkg in ios/Packages/*/; do
    [ -f "$pkg/Package.swift" ] || continue
    echo "==> swift test $pkg"
    swift test --package-path "$pkg"
    ran=1
  done
fi

if want web && [ -f web/package.json ]; then
  echo "==> web"
  pnpm --dir web install --frozen-lockfile
  pnpm --dir web lint
  pnpm --dir web test
  ran=1
fi

# The Supabase CLI runs through npx, pinned, unless it's installed.
supabase() { if type -P supabase >/dev/null; then command supabase "$@"; else npx --yes supabase@2.121.0 "$@"; fi; }

if want supabase && [ -d supabase/migrations ]; then
  echo "==> supabase"
  supabase db reset
  supabase test db
  ran=1
fi

[ "$ran" = 1 ] || echo "nothing to check yet"
if [ "${#inconclusive[@]}" -gt 0 ]; then
  echo "verify: inconclusive (${inconclusive[*]} did not run)" >&2
  exit 2
fi
echo "verify: ok"
