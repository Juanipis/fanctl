#!/bin/bash
# Packages the built FanCtl.app into a versioned zip suitable for a GitHub
# release asset. Run after `Bundle/build-app.sh release`.
#
# Output:  .build/FanCtl-<version>.zip   (next to FanCtl.app)
#          plus a SHA256 sidecar file for verification.

set -euo pipefail

VERSION="${VERSION:-0.0.0-dev}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/.build/FanCtl.app"
OUT_ZIP="$ROOT/.build/FanCtl-$VERSION.zip"
OUT_SHA="$ROOT/.build/FanCtl-$VERSION.zip.sha256"

[ -d "$APP" ] || { echo "error: $APP does not exist — run build-app.sh first"; exit 1; }

rm -f "$OUT_ZIP" "$OUT_SHA"

# `ditto -c -k --sequesterRsrc --keepParent` is the way Apple recommends
# zipping .app bundles: preserves resource forks, code signature, and the
# top-level FanCtl.app directory.
ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUT_ZIP"

shasum -a 256 "$OUT_ZIP" | awk '{print $1}' > "$OUT_SHA"

echo "==> packaged $OUT_ZIP"
echo "    sha256: $(cat "$OUT_SHA")"
echo "    size:   $(du -h "$OUT_ZIP" | cut -f1)"
