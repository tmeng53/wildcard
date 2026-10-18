#!/usr/bin/env bash
# Installs the pinned SwiftLint, so CI, cloud sessions and laptops lint with the same rules.
# A new SwiftLint release can add default rules, so the version only changes in a PR.
# Usage: scripts/install-swiftlint.sh [install-dir]   (default /usr/local/bin)
set -euo pipefail
version="$(cat "$(dirname "$0")/swiftlint-version")"
dir="${1:-/usr/local/bin}"

if [ "$(swiftlint version 2>/dev/null || true)" = "$version" ]; then
  echo "swiftlint $version already installed"
  exit 0
fi

case "$(uname -s)-$(uname -m)" in
  Darwin-*) asset=portable_swiftlint.zip ;;
  Linux-x86_64) asset=swiftlint_linux_amd64.zip ;;
  Linux-aarch64) asset=swiftlint_linux_arm64.zip ;;
  *) echo "no SwiftLint build for $(uname -sm)" >&2; exit 1 ;;
esac

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
curl -fsSL -o "$tmp/swiftlint.zip" "https://github.com/realm/SwiftLint/releases/download/$version/$asset"
unzip -q "$tmp/swiftlint.zip" -d "$tmp/out"
mkdir -p "$dir"
# The Linux zip also ships a static build, which runs without Swift's shared libraries.
binary="$tmp/out/swiftlint"
[ -f "$tmp/out/swiftlint-static" ] && binary="$tmp/out/swiftlint-static"
install -m 0755 "$binary" "$dir/swiftlint"
echo "installed swiftlint $("$dir/swiftlint" version) to $dir"
