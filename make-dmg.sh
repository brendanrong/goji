#!/bin/bash
# Build Goji.app (Release), sign it for distribution, and package a DMG.
# Run on the Mac, never in Cowork's sandbox.
#
# Usage:
#   bash make-dmg.sh                  # build + Developer ID sign + DMG
#   BUNDLE_MODEL=1 bash make-dmg.sh   # also copy your local Parakeet model into the app (~600 MB DMG, zero-download install)
#   NOTARIZE=1 bash make-dmg.sh       # additionally submit to Apple notary + staple
#
# Signing: apps are signed with the Developer ID Application cert in the login
# keychain (hardened runtime, timestamped), which is what Gatekeeper wants for
# apps distributed outside the App Store. Override with IDENTITY=... if needed.
# Notary: uses the goji-notary keychain profile. One-time setup:
#   xcrun notarytool store-credentials goji-notary --apple-id "<your Apple ID>" --team-id VTMKE23N5G
# (prompts for an app-specific password from account.apple.com).
# Override with NOTARY_PROFILE=...
set -euo pipefail
cd "$(dirname "$0")"

IDENTITY="${IDENTITY:-Developer ID Application}"
NOTARY_PROFILE="${NOTARY_PROFILE:-goji-notary}"

DERIVED=/tmp/goji-build
rm -rf "$DERIVED" dist
mkdir -p dist

xcodebuild -scheme Goji -configuration Release -derivedDataPath "$DERIVED" build
APP="$DERIVED/Build/Products/Release/Goji.app"

if [[ "${BUNDLE_MODEL:-0}" == "1" ]]; then
  # FluidAudio's cache folder drops the -coreml suffix from the repo name.
  MODEL_SRC="$HOME/Library/Application Support/FluidAudio/Models/parakeet-tdt-0.6b-v3"
  if [[ ! -d "$MODEL_SRC" ]]; then
    echo "No local model at: $MODEL_SRC"
    echo "Run Goji once so it downloads the model, then retry."
    exit 1
  fi
  mkdir -p "$APP/Contents/Resources/FluidAudioModels"
  cp -R "$MODEL_SRC" "$APP/Contents/Resources/FluidAudioModels/"
  echo "Bundled model into the app."
fi

# Distribution signing: nested code first, then the app with its entitlements.
# This replaces whatever signature the build produced (dev cert or ad-hoc) and
# strips debug-only entitlements like get-task-allow, which notarization rejects.
if [[ -d "$APP/Contents/Frameworks" ]]; then
  find "$APP/Contents/Frameworks" -depth \( -name "*.dylib" -o -name "*.framework" \) -print0 \
    | while IFS= read -r -d '' item; do
        codesign --force --options runtime --timestamp --sign "$IDENTITY" "$item"
      done
fi
codesign --force --options runtime --timestamp \
  --entitlements Goji/Goji.entitlements --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"
echo "Signed with: $IDENTITY"

# Stage the app next to an /Applications symlink plus the background art,
# then script Finder to lay the window out LiveWall-style: Goji on the left,
# arrow, Applications on the right, drag instructions underneath.
STAGING=/tmp/goji-dmg
rm -rf "$STAGING"
mkdir -p "$STAGING/.background"
ditto "$APP" "$STAGING/Goji.app"
ln -s /Applications "$STAGING/Applications"
cp dmg-background.png "$STAGING/.background/background.png"

RW=/tmp/goji-rw.dmg
rm -f "$RW"
hdiutil detach /Volumes/Goji >/dev/null 2>&1 || true
hdiutil create -volname Goji -srcfolder "$STAGING" -ov -format UDRW -fs HFS+ "$RW"
hdiutil attach -readwrite -noverify -noautoopen "$RW" >/dev/null

# First run: macOS asks to let Terminal control Finder. Allow it, then rerun
# if the layout step got skipped.
osascript <<'OSA'
tell application "Finder"
  tell disk "Goji"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 860, 520}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 112
    set background picture of viewOptions to file ".background:background.png"
    set position of item "Goji.app" of container window to {165, 175}
    set position of item "Applications" of container window to {495, 175}
    update without registering applications
    delay 1
    close
  end tell
end tell
OSA

sync
hdiutil detach /Volumes/Goji
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -ov -o dist/Goji.dmg
rm -f "$RW"

if [[ "${NOTARIZE:-0}" == "1" ]]; then
  xcrun notarytool submit dist/Goji.dmg --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple dist/Goji.dmg
fi

echo "Done: dist/Goji.dmg"
