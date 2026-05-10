#!/bin/bash
# Assembles FanCtl.app from `swift build` output and ad-hoc signs everything.
#
# Layout produced:
#   FanCtl.app/Contents/Info.plist
#   FanCtl.app/Contents/MacOS/FanCtlApp
#   FanCtl.app/Contents/MacOS/com.juanipis.FanCtl.Helper
#   FanCtl.app/Contents/Library/LaunchDaemons/com.juanipis.FanCtl.Helper.plist
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
HELPER_BUNDLE_NAME="com.juanipis.FanCtl.Helper"

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
mkdir -p "$APP/Contents/Frameworks"
mkdir -p "$APP/Contents/Library/LaunchDaemons"

cp "$ROOT/Bundle/AppInfo.plist"      "$APP/Contents/Info.plist"
cp "$BIN_DIR/FanCtlApp"              "$APP/Contents/MacOS/FanCtlApp"
cp "$BIN_DIR/FanCtlHelper"           "$APP/Contents/MacOS/$HELPER_BUNDLE_NAME"
cp "$ROOT/Bundle/HelperLaunchd.plist" "$APP/Contents/Library/LaunchDaemons/$HELPER_BUNDLE_NAME.plist"

# SwiftPM emits localizations + processed resources into a sidecar bundle
# named "<package>_<target>.bundle". Bundle.module looks for it next to
# the executable, so we copy it into Contents/Resources alongside the
# .icns. Without this, NSLocalizedString returns the raw key.
SPM_BUNDLE="$BIN_DIR/fanctl_FanCtlApp.bundle"
if [ -d "$SPM_BUNDLE" ]; then
    cp -R "$SPM_BUNDLE" "$APP/Contents/Resources/fanctl_FanCtlApp.bundle"
fi

# Sparkle ships as a versioned .framework with embedded XPC services
# (Autoupdate.app, downloader, installer). The app's @rpath points to
# Contents/Frameworks, so we copy the whole thing there. -R preserves
# the version symlinks Sparkle relies on; codesign then re-seals it
# under the parent app's signature in the final pass.
SPARKLE_FW="$ROOT/.build/arm64-apple-macosx/$( [ "$CONFIG" = "release" ] && echo "release" || echo "debug" )/Sparkle.framework"
if [ -d "$SPARKLE_FW" ]; then
    cp -R "$SPARKLE_FW" "$APP/Contents/Frameworks/Sparkle.framework"
else
    echo "❌ Sparkle.framework not found at $SPARKLE_FW"
    exit 1
fi

# SwiftPM builds the executable with @executable_path rpaths suitable for
# `swift run`, not for an .app bundle. Append the canonical bundle rpath
# so dyld finds Sparkle inside Contents/Frameworks at runtime.
install_name_tool -add_rpath "@executable_path/../Frameworks" \
    "$APP/Contents/MacOS/FanCtlApp" 2>/dev/null || true

# App icon. Re-render from source if the .icns is missing — keeps CI
# self-contained without checking a binary blob into the repo (we keep
# only the generator script).
if [ ! -f "$ROOT/Bundle/AppIcon.icns" ]; then
    echo "==> AppIcon.icns missing, regenerating"
    bash "$ROOT/Bundle/make-icon.sh"
fi
cp "$ROOT/Bundle/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# Stamp version + build into Info.plist.
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION"  "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER"        "$APP/Contents/Info.plist"

echo "==> signing ($SIGN_IDENTITY)"
# Sparkle's nested bundles (Autoupdate.app + Downloader/Installer XPCs)
# must be signed before the framework, and the framework before the app.
# We deliberately drop --options=runtime: hardened runtime requires a
# proper Developer ID + entitlements chain, which doesn't apply to an
# ad-hoc redistribution. Signing without that flag keeps Sparkle's
# pre-built binaries loadable by an ad-hoc-signed parent.
SPARKLE_VER="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
for inner in \
    "$SPARKLE_VER/Updater.app/Contents/MacOS/Autoupdate" \
    "$SPARKLE_VER/Updater.app" \
    "$SPARKLE_VER/XPCServices/Downloader.xpc/Contents/MacOS/Downloader" \
    "$SPARKLE_VER/XPCServices/Downloader.xpc" \
    "$SPARKLE_VER/XPCServices/Installer.xpc/Contents/MacOS/Installer" \
    "$SPARKLE_VER/XPCServices/Installer.xpc"; do
    if [ -e "$inner" ]; then
        codesign --force --sign "$SIGN_IDENTITY" --timestamp=none "$inner" 2>/dev/null || true
    fi
done
codesign --force --sign "$SIGN_IDENTITY" --timestamp=none \
    "$APP/Contents/Frameworks/Sparkle.framework"

codesign --force --sign "$SIGN_IDENTITY" \
    --identifier "com.juanipis.FanCtl.Helper" \
    --timestamp=none \
    "$APP/Contents/MacOS/$HELPER_BUNDLE_NAME"

codesign --force --sign "$SIGN_IDENTITY" \
    --identifier "com.juanipis.FanCtl" \
    --timestamp=none \
    "$APP"

codesign -dv --verbose=2 "$APP" 2>&1 | head -10
echo
echo "==> done: $APP (v$VERSION, build $BUILD_NUMBER)"
