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

echo "Built: $(pwd)/build/Build/Products/Release/B-Side.app"
