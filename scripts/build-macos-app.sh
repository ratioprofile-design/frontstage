#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin ]]; then
  echo 'App bundling requires macOS and the Xcode command line tools.' >&2
  exit 1
fi
swift build -c release --product Frontstage --arch arm64 --scratch-path .build/mac-arm64
swift build -c release --product Frontstage --arch x86_64 --scratch-path .build/mac-x86_64
arm_path="$(swift build -c release --arch arm64 --scratch-path .build/mac-arm64 --show-bin-path)"
intel_path="$(swift build -c release --arch x86_64 --scratch-path .build/mac-x86_64 --show-bin-path)"
app_path="$PWD/build/Frontstage.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
xcrun lipo -create "$arm_path/Frontstage" "$intel_path/Frontstage" -output "$app_path/Contents/MacOS/Frontstage"
xcrun lipo "$app_path/Contents/MacOS/Frontstage" -verify_arch arm64 x86_64
cp Resources/Info.plist "$app_path/Contents/Info.plist"
# Ad-hoc signing is for local development, not distribution or notarization.
codesign --force --sign - "$app_path"
plutil -lint "$app_path/Contents/Info.plist"
codesign --verify --strict "$app_path"
ditto -c -k --keepParent "$app_path" build/Frontstage-macOS.zip
echo "Built $app_path"
