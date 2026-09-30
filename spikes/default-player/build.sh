#!/bin/bash
# Builds the experiment 1 spike: one bundle per variant, ad-hoc signed.
set -euo pipefail
cd "$(dirname "$0")"
if ! xcrun --find swiftc >/dev/null 2>&1 || ! xcodebuild -version >/dev/null 2>&1; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
mkdir -p build
xcrun swiftc -O eligibility/main.swift -o build/eligibility
for variant in none paused playpaused playstopped; do
  app="build/Eligibility-$variant.app"
  rm -rf "$app"
  mkdir -p "$app/Contents/MacOS"
  cp build/eligibility "$app/Contents/MacOS/Eligibility"
  cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>dev.bside.spike.eligibility.$variant</string>
  <key>CFBundleName</key><string>Eligibility $variant</string>
  <key>CFBundleExecutable</key><string>Eligibility</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSUIElement</key><true/>
  <key>SpikeVariant</key><string>$variant</string>
</dict></plist>
PLIST
  codesign --force -s - "$app" 2>/dev/null
done
echo "Built: $(pwd)/build/Eligibility-{none,paused,playpaused,playstopped}.app"
