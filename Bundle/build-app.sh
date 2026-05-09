#!/bin/bash
# Assembles FanCtl.app from `swift build` output and ad-hoc signs everything.
#
# Layout produced:
#   FanCtl.app/Contents/Info.plist
#   FanCtl.app/Contents/MacOS/FanCtlApp
#   FanCtl.app/Contents/MacOS/com.jpdiaz.FanCtl.Helper
#   FanCtl.app/Contents/Library/LaunchDaemons/com.jpdiaz.FanCtl.Helper.plist
#
# Usage:
#   Bundle/build-app.sh [release|debug]
#
# Environment:
#   VERSION       Semantic version baked into Info.plist (default: 0.0.0-dev)
#   BUILD_NUMBER  Build counter (default: 1)
#   SIGN_IDENTITY Codesign identity (default: "-" for ad-hoc)

set -euo pipefail

CONFIG="${1:-debug}"
VERSION="${VERSION:-0.0.0-dev}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN_DIR="$ROOT/.build/$( [ "$CONFIG" = "release" ] && echo "release" || echo "debug" )"
APP="$ROOT/.build/FanCtl.app"
HELPER_BUNDLE_NAME="com.jpdiaz.FanCtl.Helper"

echo "==> swift build ($CONFIG, version $VERSION build $BUILD_NUMBER)"
if [ "$CONFIG" = "release" ]; then
    swift build -c release --product FanCtlApp
    swift build -c release --product FanCtlHelper
else
    swift build --product FanCtlApp
    swift build --product FanCtlHelper
fi

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"
mkdir -p "$APP/Contents/Library/LaunchDaemons"

cp "$ROOT/Bundle/AppInfo.plist"      "$APP/Contents/Info.plist"
cp "$BIN_DIR/FanCtlApp"              "$APP/Contents/MacOS/FanCtlApp"
cp "$BIN_DIR/FanCtlHelper"           "$APP/Contents/MacOS/$HELPER_BUNDLE_NAME"
cp "$ROOT/Bundle/HelperLaunchd.plist" "$APP/Contents/Library/LaunchDaemons/$HELPER_BUNDLE_NAME.plist"

# Stamp version + build into Info.plist.
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION"  "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER"        "$APP/Contents/Info.plist"

echo "==> signing ($SIGN_IDENTITY)"
codesign --force --sign "$SIGN_IDENTITY" \
    --identifier "com.jpdiaz.FanCtl.Helper" \
    --options runtime \
    --timestamp=none \
    "$APP/Contents/MacOS/$HELPER_BUNDLE_NAME"

codesign --force --sign "$SIGN_IDENTITY" \
    --identifier "com.jpdiaz.FanCtl" \
    --options runtime \
    --timestamp=none \
    "$APP"

codesign -dv --verbose=2 "$APP" 2>&1 | head -10
echo
echo "==> done: $APP (v$VERSION, build $BUILD_NUMBER)"
