#!/bin/bash
# Remote installer for FanCtl. Downloads the latest GitHub release,
# verifies the SHA-256, drops the .app into /Applications, removes the
# quarantine flag, and opens it.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/Juanipis/fanctl/main/scripts/install.sh | bash
#
# Or, pin a specific version:
#   curl -fsSL .../install.sh | VERSION=1.1.0 bash

set -euo pipefail

REPO="Juanipis/fanctl"
VERSION="${VERSION:-latest}"
APP_NAME="FanCtl.app"
DEST="/Applications/$APP_NAME"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# Apple Silicon only — the SMC backend ships zero Intel code.
ARCH="$(uname -m)"
if [ "$ARCH" != "arm64" ]; then
    echo "❌ FanCtl supports Apple Silicon Macs only (you have: $ARCH)."
    exit 1
fi

echo "==> Resolving version"
if [ "$VERSION" = "latest" ]; then
    # GitHub redirects /releases/latest → /releases/tag/vX.Y.Z. Follow it
    # to learn the version string.
    LATEST_URL="$(curl -fsSLI -o /dev/null -w '%{url_effective}' \
        "https://github.com/$REPO/releases/latest")"
    VERSION="${LATEST_URL##*/v}"
fi
TAG="v$VERSION"
ZIP="FanCtl-$VERSION.zip"
SHA="$ZIP.sha256"
BASE="https://github.com/$REPO/releases/download/$TAG"
echo "    using $TAG"

echo "==> Downloading $ZIP"
curl -fsSL -o "$TMP_DIR/$ZIP" "$BASE/$ZIP"
curl -fsSL -o "$TMP_DIR/$SHA" "$BASE/$SHA"

echo "==> Verifying SHA-256"
EXPECTED="$(cat "$TMP_DIR/$SHA" | tr -d '[:space:]')"
ACTUAL="$(shasum -a 256 "$TMP_DIR/$ZIP" | awk '{print $1}')"
if [ "$EXPECTED" != "$ACTUAL" ]; then
    echo "❌ Hash mismatch:"
    echo "    expected: $EXPECTED"
    echo "    actual:   $ACTUAL"
    exit 2
fi
echo "    OK ($ACTUAL)"

echo "==> Unzipping"
( cd "$TMP_DIR" && unzip -q "$ZIP" )

if [ ! -d "$TMP_DIR/$APP_NAME" ]; then
    echo "❌ Zip didn't contain $APP_NAME"
    exit 3
fi

# If a previous install exists, quit it first so we can overwrite cleanly.
if pgrep -x "FanCtlApp" >/dev/null; then
    echo "==> Stopping running FanCtl"
    osascript -e 'tell application id "com.jpdiaz.FanCtl" to quit' 2>/dev/null || \
        pkill -x FanCtlApp || true
    sleep 1
fi

echo "==> Installing to $DEST"
rm -rf "$DEST"
cp -R "$TMP_DIR/$APP_NAME" "$DEST"

# Ad-hoc signed builds carry a quarantine xattr; clear it so Gatekeeper
# doesn't shame the user with a "downloaded from the internet" dialog.
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

echo "==> Launching"
open "$DEST"

cat <<EOF

✔ FanCtl $TAG installed at $DEST

Next:
  1. Click the new fan icon in your menu bar.
  2. Click "Install Helper" — macOS will ask you to approve in
     System Settings → General → Login Items & Extensions → Background.
  3. Click "Retry" in the popover. The hero will light up.

Logs:
  sudo log stream --predicate 'subsystem == "com.jpdiaz.FanCtl"' --style compact

EOF
