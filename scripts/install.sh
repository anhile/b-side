#!/bin/bash
# Builds B-Side and puts it in /Applications, replacing the copy there, then
# opens it. macOS treats the copy in /Applications as the app: Open at login,
# and menu bar managers that go by the app's identifier (Hidden Bar on
# macOS 27), do not work for a copy run from the build folder.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build.sh
osascript -e 'tell application id "com.anhile.bside" to quit' >/dev/null 2>&1 || true
sleep 1
rm -rf "/Applications/B-Side.app"
ditto "build/Build/Products/Release/B-Side.app" "/Applications/B-Side.app"
open "/Applications/B-Side.app"
echo "Installed: /Applications/B-Side.app"
