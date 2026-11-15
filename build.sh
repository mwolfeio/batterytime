#!/bin/bash
# Builds BatteryTime.app next to this script and signs it ad hoc. Needs only the Command Line Tools.
set -euo pipefail
cd "$(dirname "$0")"

APP=BatteryTime.app
ARCH=$(uname -m)

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp Resources/Info.plist "$APP/Contents/Info.plist"

swiftc -O -swift-version 5 \
    -target "$ARCH-apple-macos14.0" \
    -framework AppKit -framework IOKit \
    -o "$APP/Contents/MacOS/BatteryTime" \
    Sources/*.swift

codesign --force --sign - --timestamp=none "$APP"
echo "Built $(pwd)/$APP"
