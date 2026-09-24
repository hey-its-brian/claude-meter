#!/usr/bin/env bash
# Generates the Xcode project, builds ClaudeMeter.app into ./build. Pass --install to copy it to /Applications and launch it.
set -euo pipefail

cd "$(dirname "$0")/.."
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

xcodegen generate --quiet
xcodebuild -project ClaudeMeter.xcodeproj -scheme ClaudeMeter -configuration Release \
  -derivedDataPath build/DerivedData -allowProvisioningUpdates -quiet build

rm -rf build/ClaudeMeter.app
cp -R build/DerivedData/Build/Products/Release/ClaudeMeter.app build/
echo "Built build/ClaudeMeter.app"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x ClaudeMeter 2>/dev/null || true
  rm -rf /Applications/ClaudeMeter.app
  cp -R build/ClaudeMeter.app /Applications/
  open /Applications/ClaudeMeter.app
  echo "Installed and launched /Applications/ClaudeMeter.app"
fi
