#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin ]]; then
  echo 'App bundling requires macOS and the Xcode command line tools.' >&2
  exit 1
fi
swift build -c release --product Frontstage
bin_path="$(swift build -c release --show-bin-path)"
app_path="$PWD/build/Frontstage.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$bin_path/Frontstage" "$app_path/Contents/MacOS/Frontstage"
cp Resources/Info.plist "$app_path/Contents/Info.plist"
# Ad-hoc signing is for local development, not distribution or notarization.
codesign --force --sign - "$app_path"
plutil -lint "$app_path/Contents/Info.plist"
codesign --verify --strict "$app_path"
ditto -c -k --keepParent "$app_path" build/Frontstage-macOS.zip
echo "Built $app_path"
