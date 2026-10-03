#!/bin/bash
# Generates the Xcode project and builds B-Side.app (Release).
set -euo pipefail
cd "$(dirname "$0")/.."

# xcode-select may still point at the Command Line Tools; use Xcode.app directly.
if ! xcodebuild -version >/dev/null 2>&1; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

xcodegen generate --quiet
# Naming the destination avoids xcodebuild's "multiple matching destinations" warning.
xcodebuild -project BSide.xcodeproj -scheme BSide -configuration Release \
  -destination "platform=macOS,arch=$(uname -m)" \
  -derivedDataPath build -quiet build

# The widget needs an entitlement to reach the app's message port, and
# Xcode will not sign one in without a provisioning profile; so the widget
# and then the app are signed again here, ad hoc, with the entitlements
# file. (scripts/release.sh does the same with the Developer ID certificate.)
APP="build/Build/Products/Release/B-Side.app"
codesign --force --sign - --entitlements Support/BSideWidget.entitlements "$APP/Contents/PlugIns/BSideWidget.appex"
codesign --force --sign - "$APP"

echo "Built: $(pwd)/build/Build/Products/Release/B-Side.app"
