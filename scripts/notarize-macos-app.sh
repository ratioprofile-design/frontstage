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
xcrun notarytool submit build/DOT-macOS.zip --keychain-profile "$FRONTSTAGE_NOTARY_PROFILE" --wait
xcrun stapler staple build/DOT.app
xcrun stapler validate build/DOT.app
spctl --assess --type execute --verbose build/DOT.app
ditto -c -k --keepParent build/DOT.app build/DOT-macOS-notarized.zip
