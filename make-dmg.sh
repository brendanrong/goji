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
# Notary: uses the account-level keychain profile stored for LiveWall releases
# (notary profiles aren't app-specific). Override with NOTARY_PROFILE=...
set -euo pipefail
cd "$(dirname "$0")"

IDENTITY="${IDENTITY:-Developer ID Application}"
NOTARY_PROFILE="${NOTARY_PROFILE:-LiveWall-Notary}"

DERIVED=/tmp/goji-build
rm -rf "$DERIVED" dist
mkdir -p dist

xcodebuild -scheme Goji -configuration Release -derivedDataPath "$DERIVED" build
APP="$DERIVED/Build/Products/Release/Goji.app"

if [[ "${BUNDLE_MODEL:-0}" == "1" ]]; then
  MODEL_SRC="$HOME/Library/Application Support/FluidAudio/Models/parakeet-tdt-0.6b-v3-coreml"
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

hdiutil create -volname Goji -srcfolder "$APP" -ov -format UDZO dist/Goji.dmg

if [[ "${NOTARIZE:-0}" == "1" ]]; then
  xcrun notarytool submit dist/Goji.dmg --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple dist/Goji.dmg
fi

echo "Done: dist/Goji.dmg"
