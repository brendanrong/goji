#!/bin/bash
# Release build + Developer ID sign + swap into /Applications + relaunch.
# For testing a fix on this Mac without cutting a release. Run on the Mac.
set -euo pipefail
cd "$(dirname "$0")/.."

IDENTITY="${IDENTITY:-Developer ID Application}"
DERIVED=/tmp/goji-build
rm -rf "$DERIVED"
xcodebuild -scheme Goji -configuration Release -derivedDataPath "$DERIVED" build | grep -E 'error:|BUILD' || true
APP="$DERIVED/Build/Products/Release/Goji.app"
[[ -d "$APP" ]] || { echo "build failed"; exit 1; }

if [[ -d "$APP/Contents/Frameworks" ]]; then
  find "$APP/Contents/Frameworks" -depth \( -name "*.dylib" -o -name "*.framework" \) -print0 \
    | while IFS= read -r -d '' item; do
        codesign --force --options runtime --timestamp --sign "$IDENTITY" "$item"
      done
fi
codesign --force --options runtime --timestamp \
  --entitlements Goji/Goji.entitlements --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"
echo "signed with: $IDENTITY"

osascript -e 'quit app "Goji"' >/dev/null 2>&1 || true
sleep 1
pkill -x Goji >/dev/null 2>&1 || true
rm -rf /Applications/Goji.app
ditto "$APP" /Applications/Goji.app
xattr -dr com.apple.quarantine /Applications/Goji.app >/dev/null 2>&1 || true
open /Applications/Goji.app
echo "installed and relaunched /Applications/Goji.app"
