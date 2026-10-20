#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin ]]; then
  echo 'Notarization requires macOS and Xcode command line tools.' >&2
  exit 1
fi
: "${FRONTSTAGE_SIGNING_IDENTITY:?Set a Developer ID Application signing identity.}"
: "${FRONTSTAGE_NOTARY_PROFILE:?Set an existing notarytool Keychain profile.}"
./scripts/build-macos-app.sh
xcrun notarytool submit build/Frontstage-macOS.zip --keychain-profile "$FRONTSTAGE_NOTARY_PROFILE" --wait
xcrun stapler staple build/Frontstage.app
xcrun stapler validate build/Frontstage.app
spctl --assess --type execute --verbose build/Frontstage.app
ditto -c -k --keepParent build/Frontstage.app build/Frontstage-macOS-notarized.zip
