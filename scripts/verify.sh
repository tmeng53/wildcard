#!/usr/bin/env bash
# Every check that runs without a Mac. The cloud stop hook and agents run this before every push.
set -euo pipefail
cd "$(dirname "$0")/.."

# With no arguments it runs every check. CI's jobs name the parts their runner can run:
# swift and web on macOS, supabase, api and backend on Linux (macOS runners have no Docker).
parts="${*:-swift web supabase api backend}"
want() { [[ " $parts " == *" $1 "* ]]; }

ran=0
inconclusive=()
# Without a Swift toolchain (cloud sessions where swift.org is blocked) the Swift checks are
# inconclusive and the rest still run, so the database and API checks aren't skipped. CI must
# have Swift.
if want swift && compgen -G "ios/Packages/*/Package.swift" >/dev/null && ! command -v swift >/dev/null; then
  if [ "${CI:-}" = "true" ]; then
    echo "swift is not installed on this CI runner" >&2
    exit 1
  fi
  echo "==> swift: not installed, so swift format, swiftlint and swift test did not run"
  inconclusive+=("swift")
elif want swift && compgen -G "ios/Packages/*/Package.swift" >/dev/null; then
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

  # The app's API types are generated from api/apps/server/openapi.json and committed.
  echo "==> swift openapi types are current"
  scripts/swift-openapi.sh --verify

  for pkg in ios/Packages/*/; do
    [ -f "$pkg/Package.swift" ] || continue
    # Backend's tests talk to local Supabase, so they run in the backend part; here it only builds.
    if [ "$pkg" = "ios/Packages/Backend/" ]; then
      echo "==> swift build $pkg"
      swift build --package-path "$pkg" --build-tests
      ran=1
      continue
    fi
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

if want api && [ -f api/package.json ]; then
  echo "==> api"
  pnpm --dir api install --frozen-lockfile
  pnpm --dir api lint
  pnpm --dir api typecheck
  pnpm --dir api boundaries
  # The tests query local Supabase's database, sign members up through its Auth and upload to
  # its Storage, so they need `supabase start`. A subshell keeps the status variables out of the
  # rest of this script.
  (
    status="$(supabase status -o env 2>/dev/null)" || {
      echo "api: local Supabase isn't running (supabase start)" >&2
      exit 1
    }
    eval "$status"
    # The Kysely table types must match the migrations: `pnpm --dir api db-types` rewrites them.
    DATABASE_URL="$DB_URL" pnpm --dir api db-types --verify
    DATABASE_URL="$DB_URL" SUPABASE_URL="$API_URL" SUPABASE_PUBLISHABLE_KEY="$PUBLISHABLE_KEY" \
      SUPABASE_SECRET_KEY="$SECRET_KEY" \
      pnpm --dir api test
  )
  ran=1
fi

# The app's adapters, against local Supabase's Auth and the built API (needs `supabase start`).
if want backend && [ -f ios/Packages/Backend/Package.swift ] && ! type -P swift >/dev/null && [ "${CI:-}" != "true" ]; then
  echo "==> backend: Swift isn't installed here"
  inconclusive+=("backend")
elif want backend && [ -f ios/Packages/Backend/Package.swift ]; then
  echo "==> backend"
  (
    status="$(supabase status -o env 2>/dev/null)" || {
      echo "backend: local Supabase isn't running (supabase start)" >&2
      exit 1
    }
    eval "$status"
    # The API client's tests call the built API, so it runs for as long as they do.
    . scripts/lib/api-server.sh
    start_api_server
    SUPABASE_URL="$API_URL" SUPABASE_PUBLISHABLE_KEY="$PUBLISHABLE_KEY" WILDCARD_API_URL="$api" \
      swift test --package-path ios/Packages/Backend
  )
  ran=1
fi

[ "$ran" = 1 ] || echo "nothing to check yet"
if [ "${#inconclusive[@]}" -gt 0 ]; then
  echo "verify: inconclusive (${inconclusive[*]} did not run)" >&2
  exit 2
fi
echo "verify: ok"
