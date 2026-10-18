#!/usr/bin/env bash
# Builds the iOS app, runs its UI tests on a simulator and exports the screenshots they keep.
# macOS with Xcode 16 or newer only. CI's `ios` job runs it and uploads build/ios/screenshots.
# Usage: scripts/ios-test.sh            (SIMULATOR="iPhone 16 Pro" to pick another device)
set -euo pipefail
cd "$(dirname "$0")/.."

out=build/ios
rm -rf "$out"
mkdir -p "$out/screenshots"

# The named simulator if this Xcode has it, else the first available iPhone.
want="${SIMULATOR:-iPhone 16}"
devices="$(xcrun simctl list devices available)"
if grep -q "    $want (" <<<"$devices"; then
  sim="$want"
else
  sim="$(grep -Eo '    iPhone [^(]+' <<<"$devices" | head -n 1 | sed -E 's/^ +//; s/ +$//')"
  [ -n "$sim" ] || { echo "no iPhone simulator available" >&2; exit 1; }
  echo "$want isn't available; using $sim"
fi

echo "==> xcodebuild test on $sim"
status=0
xcodebuild test \
  -project ios/Wildcard.xcodeproj \
  -scheme Wildcard \
  -destination "platform=iOS Simulator,name=$sim" \
  -derivedDataPath "$out/DerivedData" \
  -resultBundlePath "$out/Wildcard.xcresult" \
  CODE_SIGNING_ALLOWED=NO \
  || status=$?

# Export screenshots even when a test failed: they show what went wrong.
if [ -d "$out/Wildcard.xcresult" ]; then
  raw="$out/attachments"
  xcrun xcresulttool export attachments --path "$out/Wildcard.xcresult" --output-path "$raw"
  # Name each file after its XCTAttachment name; the manifest maps exported files to names.
  python3 - "$raw" "$out/screenshots" <<'PY'
import json, pathlib, re, shutil, sys
raw, dest = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
for test in json.loads((raw / "manifest.json").read_text()):
    for item in test.get("attachments", []):
        name = item.get("suggestedHumanReadableName") or item["exportedFileName"]
        name = re.sub(r"_\d+_[0-9A-Fa-f-]{36}(\.\w+)$", r"\1", name)
        shutil.copy(raw / item["exportedFileName"], dest / name)
        print(f"screenshot: {dest / name}")
PY
fi

[ "$status" -eq 0 ] && echo "ios-test: ok"
exit "$status"
