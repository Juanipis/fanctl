#!/bin/bash
# Copies FanCtl.app into /Applications and tells launchd via SMAppService to
# load the privileged helper. The first time you run this macOS will
# prompt you to approve in System Settings → General → Login Items &
# Extensions → Background.
#
# Usage:
#   Bundle/install.sh                    # debug build, install to /Applications
#   Bundle/install.sh release            # release build
#   Bundle/install.sh release ~/Apps     # install elsewhere

set -euo pipefail

CONFIG="${1:-debug}"
DEST_DIR="${2:-/Applications}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

bash "$ROOT/Bundle/build-app.sh" "$CONFIG"

SRC="$ROOT/.build/FanCtl.app"
DEST="$DEST_DIR/FanCtl.app"

echo "==> copying to $DEST"
rm -rf "$DEST"
mkdir -p "$DEST_DIR"
cp -R "$SRC" "$DEST"
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

echo "==> launching FanCtl.app (it will register the helper on first run)"
open "$DEST"

cat <<EOF

✔ FanCtl.app installed at: $DEST

Next steps:
 1. Click the new fan icon in your menu bar.
 2. Click "Install Helper". macOS will redirect you to System Settings.
 3. Toggle "FanCtl" ON under Login Items & Extensions → Background.
 4. The helper will start. Live RPM and temps appear in the popover.

To inspect the helper:
   sudo log stream --predicate 'subsystem == "com.jpdiaz.FanCtl"' --style compact
   sudo launchctl print system/com.jpdiaz.FanCtl.Helper

To uninstall:
   Bundle/uninstall.sh
EOF
