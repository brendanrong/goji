#!/bin/bash
# Cut a Goji release: build, DMG, (notarize), push to GitHub, publish the release,
# and make sure the download site is live. Run on the Mac. Never in Cowork's
# Linux sandbox (builds are Mac-only).
#
# Usage:
#   bash scripts/release.sh              # build + notarize + publish
#   NOTARIZE=0 bash scripts/release.sh   # skip notarization (quick DMG, Gatekeeper will warn)
#
# One-time prereqs:
#   - gh CLI authed:                    gh auth login
#   - Notary profile (for notarizing):  xcrun notarytool store-credentials goji-notary
#   - Release signing set to Developer ID in Xcode (Signing & Capabilities),
#     otherwise notarization will reject the build.
set -euo pipefail
cd "$(dirname "$0")/.."   # repo root

REPO="brendanrong/goji"
PAGES_URL="https://brendanrong.github.io/goji/"

# --- version lives in the hand-written pbxproj (MARKETING_VERSION), not Info.plist ---
VERSION=$(grep -m1 'MARKETING_VERSION' Goji.xcodeproj/project.pbxproj | sed 's/.*= //; s/;//' | tr -d ' ')
[[ -n "$VERSION" ]] || { echo "Could not read MARKETING_VERSION from project.pbxproj"; exit 1; }
TAG="v${VERSION}"
echo "==> Releasing Goji ${TAG}"

# --- preflight ---
command -v gh >/dev/null || { echo "gh not found. brew install gh"; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "gh not authenticated. Run: gh auth login"; exit 1; }
BRANCH=$(git rev-parse --abbrev-ref HEAD)
[[ "$BRANCH" == "main" ]] || { echo "On '$BRANCH', not main. Switch first."; exit 1; }
[[ -z "$(git status --porcelain)" ]] || { echo "Working tree not clean. Commit or stash first."; git status -s; exit 1; }

NOTES="release-notes/${TAG}.md"
[[ -f "$NOTES" ]] || { echo "No release notes at $NOTES. Create it, then re-run."; exit 1; }

# --- build + dmg (+ notarize) ---
echo "==> Building and packaging with Xcode (a few minutes)..."
NOTARIZE="${NOTARIZE:-1}" bash make-dmg.sh
DMG="dist/Goji.dmg"
[[ -f "$DMG" ]] || { echo "Expected $DMG but it is missing."; exit 1; }

# --- push code (create the repo on first run) ---
if git remote get-url origin >/dev/null 2>&1; then
  echo "==> Pushing main to origin"
  git push origin main
else
  echo "==> No origin yet. Creating $REPO (public) and pushing"
  gh repo create "$REPO" --public --source=. --remote=origin --push
fi

# --- tag ---
git rev-parse "$TAG" >/dev/null 2>&1 || git tag "$TAG"
git push origin "$TAG"

# --- github release ---
if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  echo "==> Release $TAG exists, replacing the DMG"
  gh release upload "$TAG" "$DMG" --repo "$REPO" --clobber
else
  echo "==> Creating release $TAG"
  gh release create "$TAG" "$DMG" --repo "$REPO" --title "Goji ${VERSION}" --notes-file "$NOTES"
fi

# --- enable GitHub Pages on /docs (first run; harmless if already on) ---
echo "==> Ensuring GitHub Pages serves /docs"
echo '{"source":{"branch":"main","path":"/docs"}}' | gh api -X POST "repos/${REPO}/pages" --input - >/dev/null 2>&1 \
  && echo "   Pages enabled." \
  || echo "   Pages already on, or enable it once in Settings > Pages (branch main, /docs)."

echo ""
echo "Done."
echo "  Release:  https://github.com/${REPO}/releases/tag/${TAG}"
echo "  Site:     ${PAGES_URL}  (Pages takes 30-60s to deploy)"
echo "  Download: https://github.com/${REPO}/releases/latest/download/Goji.dmg"
