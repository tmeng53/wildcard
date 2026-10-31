#!/usr/bin/env bash
# Refuses an API change that the app builds already installed can't read: compares
# api/apps/server/openapi.json with the one at the base commit using oasdiff, and fails on any
# breaking change (a response field removed or made optional, a new enum value in a response,
# a route removed, a request rule tightened). Builds on TestFlight decode replies strictly, so
# one such change empties a screen for everyone who hasn't updated (#180).
# Usage: scripts/api-compat.sh [base-commit]   (default: $API_COMPAT_BASE, which CI sets, else
# where this branch left origin/main)
# A breaking change made on purpose, once no installed build uses what it changes, is listed in
# api/apps/server/openapi-breaking-allowed.txt (oasdiff's --err-ignore format) in the same PR.
set -euo pipefail
cd "$(dirname "$0")/.."

version="$(cat scripts/oasdiff-version)"
spec=api/apps/server/openapi.json
allowed=api/apps/server/openapi-breaking-allowed.txt

base="${1:-${API_COMPAT_BASE:-}}"
if [ -z "$base" ]; then
  git rev-parse --verify -q origin/main >/dev/null || git fetch -q --depth=1 origin main
  base="$(git merge-base HEAD origin/main 2>/dev/null || git rev-parse origin/main)"
fi
# CI checks out one commit, so fetch the base when it isn't here.
git cat-file -e "$base^{commit}" 2>/dev/null || git fetch -q --depth=1 origin "$base"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
if ! git show "$base:$spec" >"$tmp/base.json" 2>/dev/null; then
  echo "api-compat: no $spec at $base, nothing to compare"
  exit 0
fi

# The pinned oasdiff, downloaded once into build/tools and checked against its sha256.
bin="build/tools/oasdiff-$version/oasdiff"
if [ ! -x "$bin" ]; then
  case "$(uname -s)-$(uname -m)" in
    Linux-x86_64) asset="oasdiff_${version}_linux_amd64.tar.gz" ;;
    Linux-aarch64) asset="oasdiff_${version}_linux_arm64.tar.gz" ;;
    Darwin-*) asset="oasdiff_${version}_darwin_all.tar.gz" ;;
    *) echo "no oasdiff build for $(uname -sm)" >&2; exit 1 ;;
  esac
  url="https://github.com/oasdiff/oasdiff/releases/download/v$version"
  curl -fsSL -o "$tmp/$asset" "$url/$asset"
  curl -fsSL -o "$tmp/checksums.txt" "$url/checksums.txt"
  sha="$(command -v sha256sum || echo "shasum -a 256")"
  (cd "$tmp" && grep " $asset\$" checksums.txt | $sha -c --quiet -)
  mkdir -p "$(dirname "$bin")"
  tar -xzf "$tmp/$asset" -C "$(dirname "$bin")" oasdiff
fi

ignore=()
[ -f "$allowed" ] && ignore=(--err-ignore "$allowed")
echo "==> api-compat: $spec against $(git rev-parse --short "$base")"
if ! "$bin" breaking "$tmp/base.json" "$spec" --fail-on ERR "${ignore[@]}"; then
  echo "api-compat: installed builds can't read this API change. Keep the old shape (add, never" >&2
  echo "remove or tighten), or list the change in $allowed once no installed build needs it." >&2
  exit 1
fi
