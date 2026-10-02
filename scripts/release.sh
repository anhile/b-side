#!/bin/bash
# Builds a release of B-Side: a universal app signed with Developer ID and the
# hardened runtime, notarised by Apple and stapled, in a disk image.
#
#   scripts/release.sh 1.0.0           the real thing, into dist/B-Side-1.0.0.dmg
#   scripts/release.sh 1.0.0 --adhoc   the same steps without a certificate and
#                                      without Apple, to try the script itself
#
# Needs once on this Mac (docs/RELEASING.md):
#   - a "Developer ID Application" certificate in the keychain
#   - notary credentials stored as the keychain profile "b-side-notary"
# BSIDE_SIGN_IDENTITY and BSIDE_NOTARY_PROFILE name others.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-}"
ADHOC="${2:-}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "usage: scripts/release.sh <version, as 1.0.0> [--adhoc]" >&2
  exit 2
fi

# xcode-select may still point at the Command Line Tools; use Xcode.app directly.
if ! xcodebuild -version >/dev/null 2>&1; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

PROFILE="${BSIDE_NOTARY_PROFILE:-b-side-notary}"
if [[ "$ADHOC" == "--adhoc" ]]; then
  IDENTITY="-"
else
  IDENTITY="${BSIDE_SIGN_IDENTITY:-$(security find-identity -v -p codesigning \
    | sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' | head -1)}"
  if [[ -z "$IDENTITY" ]]; then
    echo "No Developer ID Application certificate in the keychain. See docs/RELEASING.md." >&2
    exit 1
  fi
  # Fail now, not after the build, when the notary credentials are missing.
  if ! xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
    echo "No notary credentials under the keychain profile \"$PROFILE\". See docs/RELEASING.md." >&2
    exit 1
  fi
  if [[ -n "$(git status --porcelain)" ]]; then
    echo "The working tree has changes; a release is built from a commit." >&2
    exit 1
  fi
fi

BUILD_NUMBER="$(git rev-list --count HEAD)"
DERIVED="build/release"
APP="$DERIVED/Build/Products/Release/B-Side.app"
DIST="dist"
STAGE="$DIST/stage"
DMG="$DIST/B-Side-$VERSION.dmg"

echo "Building B-Side $VERSION ($BUILD_NUMBER), arm64 and x86_64"
xcodegen generate --quiet
xcodebuild -project BSide.xcodeproj -scheme BSide -configuration Release \
  -destination "generic/platform=macOS" -derivedDataPath "$DERIVED" -quiet \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  clean build

rm -rf "$DIST"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/B-Side.app"

# Signing again drops the build's get-task-allow entitlement, which the notary
# refuses. B-Side needs no entitlements: it is not sandboxed, and the page
# plays in WebKit's own processes.
echo "Signing as: $IDENTITY"
if [[ "$IDENTITY" == "-" ]]; then
  codesign --force --options runtime --sign - "$STAGE/B-Side.app"
else
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$STAGE/B-Side.app"
fi
codesign --verify --deep --strict "$STAGE/B-Side.app"

notarise() {
  xcrun notarytool submit "$1" --keychain-profile "$PROFILE" --wait
}

# The app is notarised and stapled on its own first, so the copy a user drags
# out of the image opens without asking Apple, even offline.
if [[ "$IDENTITY" != "-" ]]; then
  echo "Notarising the app"
  ditto -c -k --keepParent "$STAGE/B-Side.app" "$DIST/B-Side.zip"
  notarise "$DIST/B-Side.zip"
  xcrun stapler staple "$STAGE/B-Side.app"
  rm "$DIST/B-Side.zip"
fi

ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "B-Side" -srcfolder "$STAGE" -format UDZO -quiet "$DMG"
rm -rf "$STAGE"

if [[ "$IDENTITY" != "-" ]]; then
  codesign --timestamp --sign "$IDENTITY" "$DMG"
  echo "Notarising the disk image"
  notarise "$DMG"
  xcrun stapler staple "$DMG"
  spctl --assess --type open --context context:primary-signature --verbose "$DMG"
fi

echo "Done: $DMG"
shasum -a 256 "$DMG"
