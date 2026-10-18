#!/usr/bin/env bash
# Runs the Avatar package's tests on an iOS simulator and keeps the previews they render:
# stills of the placeholder character and its clips as GIFs, frame by frame through the
# player's own view. macOS with Xcode only. CI's `avatar-preview` job runs it and uploads
# build/avatar.
# Usage: scripts/avatar-preview.sh            (SIMULATOR="iPhone 16 Pro" to pick another device)
set -euo pipefail
cd "$(dirname "$0")/.."

out="$PWD/build/avatar"
rm -rf "$out"
mkdir -p "$out/previews"

# The named simulator if this Xcode has it, else the first iPhone on the newest iOS runtime.
want="${SIMULATOR:-iPhone 16}"
devices="$(xcrun simctl list devices available)"
if grep -q "    $want (" <<<"$devices"; then
  sim="$want"
else
  sim="$(awk '/^-- iOS/ { first = ""; ios = 1; next } /^-- / { ios = 0 }
    ios && first == "" && /^    iPhone / { first = $0; newest = $0 } END { print newest }' <<<"$devices" |
    sed -E 's/ \(.*$//; s/^ +//')"
  [ -n "$sim" ] || { echo "no iPhone simulator available" >&2; exit 1; }
  echo "$want isn't available; using $sim"
fi

# xcodebuild passes TEST_RUNNER_-prefixed variables to the tests without the prefix.
echo "==> xcodebuild test Avatar on $sim"
(cd ios/Packages/Avatar && TEST_RUNNER_AVATAR_PREVIEW_DIR="$out/previews" xcodebuild test \
  -scheme Avatar-Package \
  -destination "platform=iOS Simulator,OS=latest,name=$sim" \
  -derivedDataPath "$out/DerivedData" \
  -resultBundlePath "$out/Avatar.xcresult" \
  CODE_SIGNING_ALLOWED=NO)

ls -l "$out/previews"
for file in 01-outfits.png 02-cheer-frames.png 03-check-in-cheer.gif 04-idle-hoodie.gif timings.txt; do
  [ -s "$out/previews/$file" ] || { echo "missing preview: $file" >&2; exit 1; }
done
cat "$out/previews/timings.txt"

# Previews in the log, for agents whose network can't download artifacts: decode the lines
# between the markers with `base64 -d`.
if [ "${PRINT_PREVIEWS:-}" = "1" ]; then
  for file in "$out"/previews/*.png "$out"/previews/*.gif; do
    echo "----- preview begin: $(basename "$file") -----"
    base64 -b 76 -i "$file"
    echo "----- preview end -----"
  done
fi
echo "avatar-preview: ok"
