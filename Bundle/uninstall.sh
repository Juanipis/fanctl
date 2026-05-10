#!/bin/bash
# Stops + unregisters the helper, then removes FanCtl.app.

set -euo pipefail

LABEL="com.juanipis.FanCtl.Helper"

echo "==> setting all fans back to AUTO before uninstall"
if pgrep -x FanCtlApp >/dev/null; then
    osascript -e 'tell application "FanCtl" to quit' 2>/dev/null || true
fi

echo "==> unregistering helper via launchctl"
sudo launchctl bootout "system/$LABEL" 2>/dev/null || true
sudo launchctl remove "$LABEL" 2>/dev/null || true

echo "==> removing FanCtl.app"
sudo rm -rf "/Applications/FanCtl.app"

echo "Done. Open System Settings → Login Items & Extensions if you want to clean up the entry."
