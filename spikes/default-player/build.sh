#!/bin/bash
# Builds the spikes, one ad-hoc signed bundle per variant or round, so no
# system state carries over between them.
set -euo pipefail
cd "$(dirname "$0")"
if ! xcodebuild -version >/dev/null 2>&1; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
mkdir -p build

# bundle <path> <executable> <bundle id> <name> <extra plist keys>
bundle() {
  local app=$1 exe=$2 id=$3 name=$4 extra=$5
  rm -rf "$app"
  mkdir -p "$app/Contents/MacOS"
  cp "build/$exe" "$app/Contents/MacOS/$exe"
  cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>$id</string>
  <key>CFBundleName</key><string>$name</string>
  <key>CFBundleExecutable</key><string>$exe</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSUIElement</key><true/>
  $extra
</dict></plist>
PLIST
  codesign --force -s - "$app" 2>/dev/null
}

# Experiment 1: eligibility at launch.
xcrun swiftc -O eligibility/main.swift -o build/Eligibility
for variant in none paused playpaused playstopped; do
  bundle "build/Eligibility-$variant.app" Eligibility "dev.bside.spike.eligibility.$variant" \
    "Eligibility $variant" "<key>SpikeVariant</key><string>$variant</string>"
done

# Experiment 2: does the Play key come back after another player. The
# bundle IDs carry the build time, so every build starts with fresh ones.
xcrun swiftc -O stack/main.swift -o build/Stack
rm -rf build/Stack-*.app
stamp=$(date +%y%m%d%H%M%S)
for round in paused quit-paused quit-playing cleared browser; do
  roles="home intruder"
  [ "$round" = browser ] && roles=home # the intruder is a real browser tab
  for role in $roles; do
    bundle "build/Stack-$round-$role.app" Stack "dev.bside.spike.stack.$stamp.$round.$role" \
      "Stack $round $role" "<key>SpikeRole</key><string>$role</string><key>SpikeRound</key><string>$round</string>"
  done
done
echo "Built: $(pwd)/build"
