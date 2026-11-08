#!/usr/bin/env bash
# Compiles the app, its extensions and its UI tests for the iOS simulator, without running
# anything: the packages' SwiftUI code and the app target compile only on a Mac, so this catches
# what the Linux checks can't, in minutes rather than the UI tests' hour. macOS with Xcode only;
# CI's `ios-build` job runs it on every ready PR that changes ios/.
# Usage: scripts/ios-build.sh
set -euo pipefail
cd "$(dirname "$0")/.."

out="$PWD/build/ios-build"
mkdir -p "$out"
echo "==> xcodebuild build-for-testing Wildcard"
status=0
xcodebuild build-for-testing \
  -project ios/Wildcard.xcodeproj \
  -scheme Wildcard \
  -destination "generic/platform=iOS Simulator" \
  -derivedDataPath "$out/DerivedData" \
  -clonedSourcePackagesDirPath "$PWD/build/spm" \
  CODE_SIGNING_ALLOWED=NO \
  >"$out/xcodebuild.log" 2>&1 || status=$?
# The whole log is long; the errors and the result line are what a reader needs.
grep -E "error:|\*\* (TEST )?BUILD" "$out/xcodebuild.log" || true
if [ "$status" -ne 0 ]; then
  echo "ios-build: failed; last lines of the log:" >&2
  tail -n 40 "$out/xcodebuild.log" >&2
  exit "$status"
fi
echo "ios-build: ok"
