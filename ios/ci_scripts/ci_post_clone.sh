#!/bin/sh
# Xcode Cloud runs this right after it clones the repository (it must sit next to
# Wildcard.xcodeproj, in ios/ci_scripts). Xcode Cloud builds with automatic package resolution
# turned off, so it needs the app project's Package.resolved, which the repo doesn't keep (the
# packages pin their own dependencies, and GitHub's CI resolves them on every build): resolve
# them here, once, before Xcode Cloud runs xcodebuild.
# https://developer.apple.com/documentation/xcode/writing-custom-build-scripts
# https://developer.apple.com/documentation/xcode/making-dependencies-available-to-xcode-cloud
set -eu

cd "$CI_PRIMARY_REPOSITORY_PATH"
echo "Xcode Cloud: workflow ${CI_WORKFLOW:-?}, ${CI_START_CONDITION:-?} build of ${CI_COMMIT:-?}"
xcodebuild -version
xcodebuild -resolvePackageDependencies -project ios/Wildcard.xcodeproj -scheme Wildcard
