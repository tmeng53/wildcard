#!/usr/bin/env bash
# Turns the API's OpenAPI document (api/apps/server/openapi.json) into the app's Swift, with
# Apple's Swift OpenAPI Generator pinned in ios/Tools/OpenAPI: the wire types in
# ios/Packages/Contracts/Sources/APIContract/Generated and the client that sends them in
# ios/Packages/Backend/Sources/Backend/Generated. Run it after `pnpm --dir api openapi`. With --verify it changes
# nothing and fails when the committed Swift is stale; scripts/verify.sh runs that.
set -euo pipefail
cd "$(dirname "$0")/.."

tools=ios/Tools/OpenAPI

swift build --package-path "$tools" -c release --product swift-openapi-generator >/dev/null
generator="$(swift build --package-path "$tools" -c release --show-bin-path)/swift-openapi-generator"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
stale=0
# generate PACKAGE OUT: the Swift that PACKAGE's openapi-generator-config.yaml asks for, into OUT.
generate() {
  if ! "$generator" generate api/apps/server/openapi.json \
    --config "$1/openapi-generator-config.yaml" \
    --output-directory "$tmp/$1" >"$tmp/log" 2>&1; then
    cat "$tmp/log" >&2
    exit 1
  fi
  if [ "${verify:-}" = 1 ]; then
    if ! diff -r "$tmp/$1" "$2" >/dev/null; then
      echo "$2 is stale: run scripts/swift-openapi.sh" >&2
      stale=1
    fi
  else
    rm -rf "$2"
    mkdir -p "$2"
    cp "$tmp/$1"/*.swift "$2"/
  fi
}

[ "${1:-}" = "--verify" ] && verify=1
generate ios/Packages/Contracts ios/Packages/Contracts/Sources/APIContract/Generated
generate ios/Packages/Backend ios/Packages/Backend/Sources/Backend/Generated
exit "$stale"
