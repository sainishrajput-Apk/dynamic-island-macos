#!/bin/bash
# Run ./build.sh first. Creates build/DynamicIsland.dmg
set -euo pipefail
cd "$(dirname "$0")"
rm -rf build/dmg build/DynamicIsland.dmg
mkdir -p build/dmg
cp -R "build/Dynamic Island.app" build/dmg/
ln -s /Applications build/dmg/Applications
hdiutil create -volname "Dynamic Island" -srcfolder build/dmg -ov -format UDZO build/DynamicIsland.dmg
echo "Created build/DynamicIsland.dmg"
