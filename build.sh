#!/bin/bash
# Builds "Dynamic Island.app" natively (on an Intel Mac this produces x86_64).
set -euo pipefail
cd "$(dirname "$0")"
APP="build/Dynamic Island.app"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/DynamicIsland"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/DynamicIsland"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --deep --sign - "$APP"

echo ""
echo "Built: $APP"
file "$APP/Contents/MacOS/DynamicIsland"
