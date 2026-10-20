#!/usr/bin/env bash
# Builds the iOS app, runs its UI tests on a simulator and exports the screenshots they keep.
# macOS with Xcode 26 or newer only. CI's `ios` job runs it and uploads build/ios/screenshots.
# Usage: scripts/ios-test.sh            (SIMULATOR="iPhone 17 Pro" to pick another device)
set -euo pipefail
cd "$(dirname "$0")/.."

out=build/ios
rm -rf "$out"
mkdir -p "$out/screenshots"

# The named simulator if this Xcode has it, else an iPhone on the newest iOS runtime (simctl
# lists runtimes oldest first, and the app needs iOS 26).
want="${SIMULATOR:-iPhone 17}"
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

# Start from a fresh install: iOS remembers the notification prompt's answer for as long as the
# app stays installed, and NotificationPromptUITests needs an app that was never asked.
xcrun simctl boot "$sim" 2>/dev/null || true
xcrun simctl uninstall "$sim" app.wildcard.ios 2>/dev/null || true

echo "==> xcodebuild test on $sim"
status=0
xcodebuild test \
  -project ios/Wildcard.xcodeproj \
  -scheme Wildcard \
  -destination "platform=iOS Simulator,OS=latest,name=$sim" \
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
        # Only the screenshots the tests name ("01-..."); skip XCTest's automatic
        # UI snapshots, synthesized events and failure recordings.
        if not re.match(r"^\d\d-.+\.png$", name):
            continue
        shutil.copy(raw / item["exportedFileName"], dest / name)
        print(f"screenshot: {dest / name}")
PY
fi

shots=$(find "$out/screenshots" -name '*.png' | wc -l | tr -d ' ')
echo "ios-test: $shots screenshots"
if [ "$status" -eq 0 ] && [ "$shots" -eq 0 ]; then
  echo "the UI tests passed but no screenshots were exported" >&2
  status=1
fi
[ "$status" -eq 0 ] && echo "ios-test: ok"

# Small JPEG previews in the log, for agents whose network can't download artifacts:
# decode the lines between the markers with `base64 -d`.
if [ "${PRINT_PREVIEWS:-}" = "1" ]; then
  for png in "$out"/screenshots/*.png; do
    [ -e "$png" ] || continue
    jpg="$out/preview.jpg"
    sips -Z 700 -s format jpeg -s formatOptions 50 "$png" --out "$jpg" >/dev/null
    echo "----- preview begin: $(basename "$png" .png).jpg -----"
    base64 -b 76 -i "$jpg"
    echo "----- preview end -----"
  done
fi

# Failed tests last, so they're in the log's tail after the previews.
if [ "$status" -ne 0 ] && [ -d "$out/Wildcard.xcresult" ]; then
  echo "----- failed tests -----"
  xcrun xcresulttool get test-results summary --path "$out/Wildcard.xcresult" --format json |
    python3 -c 'import json, sys
for f in json.load(sys.stdin).get("testFailures", []):
    print((f.get("testIdentifierString") or f.get("testName", "?")) + ": " + str(f.get("failureText")))' || true
fi

exit "$status"
