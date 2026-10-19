#!/usr/bin/env bash
# Turns the API's OpenAPI document (api/apps/server/openapi.json) into the app's Swift types in
# ios/Packages/Contracts/Sources/APIContract/Generated, with Apple's Swift OpenAPI Generator
# pinned in ios/Tools/OpenAPI. Run it after `pnpm --dir api openapi`. With --verify it changes
# nothing and fails when the committed Swift is stale; scripts/verify.sh runs that.
set -euo pipefail
cd "$(dirname "$0")/.."

out=ios/Packages/Contracts/Sources/APIContract/Generated
tools=ios/Tools/OpenAPI

swift build --package-path "$tools" -c release --product swift-openapi-generator >/dev/null
generator="$(swift build --package-path "$tools" -c release --show-bin-path)/swift-openapi-generator"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
if ! "$generator" generate api/apps/server/openapi.json \
  --config ios/Packages/Contracts/openapi-generator-config.yaml \
  --output-directory "$tmp/swift" >"$tmp/log" 2>&1; then
  cat "$tmp/log" >&2
  exit 1
fi

if [ "${1:-}" = "--verify" ]; then
  if ! diff -r "$tmp/swift" "$out" >/dev/null; then
    echo "$out is stale: run scripts/swift-openapi.sh" >&2
    exit 1
  fi
else
  rm -rf "$out"
  mkdir -p "$out"
  cp "$tmp"/swift/*.swift "$out"/
fi
