#!/usr/bin/env bash
# Every check that runs without a Mac. The cloud stop hook and agents run this before every push.
set -euo pipefail
cd "$(dirname "$0")/.."

ran=0
if compgen -G "ios/Packages/*/Package.swift" >/dev/null; then
  echo "==> swift format lint"
  swift format lint --strict --recursive ios
  # SwiftLint isn't part of the Swift toolchain. CI must have it; elsewhere a missing
  # binary makes this one check inconclusive, and says so.
  if type -P swiftlint >/dev/null; then
    echo "==> swiftlint"
    swiftlint lint --strict --quiet
  elif [ "${CI:-}" = "true" ]; then
    echo "swiftlint is not installed on this CI runner" >&2
    exit 1
  else
    echo "==> swiftlint: not installed, so this check is inconclusive"
  fi
fi

for pkg in ios/Packages/*/; do
  [ -f "$pkg/Package.swift" ] || continue
  echo "==> swift test $pkg"
  swift test --package-path "$pkg"
  ran=1
done

if [ -f web/package.json ]; then
  echo "==> web"
  pnpm --dir web install --frozen-lockfile
  pnpm --dir web lint
  pnpm --dir web test
  ran=1
fi

# The Supabase CLI runs through npx unless it's installed.
supabase() { if type -P supabase >/dev/null; then command supabase "$@"; else npx --yes supabase "$@"; fi; }

if [ -d supabase/migrations ]; then
  echo "==> supabase"
  supabase db reset
  supabase test db
  ran=1
fi

[ "$ran" = 1 ] || echo "nothing to check yet"
echo "verify: ok"
