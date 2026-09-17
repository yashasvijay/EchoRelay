#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "xcodebuild is required. Open EchoRelay.xcodeproj in Xcode and build the EchoRelay scheme."
  exit 1
fi
xcodebuild -project EchoRelay.xcodeproj -scheme EchoRelay -configuration Release -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
APP_PATH="build/Build/Products/Release/EchoRelay.app"
echo "Built: $APP_PATH"
