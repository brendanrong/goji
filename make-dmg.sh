#!/bin/bash
# Build Goji.app (Release) and package a DMG. Run on the Mac, never in Cowork's sandbox.
#
# Usage:
#   bash make-dmg.sh                  # build + DMG (recipients download the model on first run)
#   BUNDLE_MODEL=1 bash make-dmg.sh   # also copy your local Parakeet model into the app (~600 MB DMG, zero-download install)
#   NOTARIZE=1 bash make-dmg.sh      # submit to Apple notary + staple. One-time setup first:
#                                     #   xcrun notarytool store-credentials goji-notary
#                                     # and set Developer ID signing for Release in Xcode.
set -euo pipefail
cd "$(dirname "$0")"

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
  # Adding resources invalidates the signature; re-sign with the app's entitlements.
  # Ad-hoc (-) is fine for personal use. For distribution use your Developer ID identity.
  codesign --force --options runtime --entitlements Goji/Goji.entitlements --sign - "$APP"
  echo "Bundled model into the app."
fi

hdiutil create -volname Goji -srcfolder "$APP" -ov -format UDZO dist/Goji.dmg

if [[ "${NOTARIZE:-0}" == "1" ]]; then
  xcrun notarytool submit dist/Goji.dmg --keychain-profile goji-notary --wait
  xcrun stapler staple dist/Goji.dmg
fi

echo "Done: dist/Goji.dmg"
