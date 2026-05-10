#!/bin/bash
# Adds a new <item> to docs/appcast.xml for a freshly published release.
# Sparkle clients poll that XML and use SUPublicEDKey in Info.plist to
# verify the EdDSA signature before installing.
#
# Usage:
#   VERSION=2.1.0 \
#   SPARKLE_PRIVATE_KEY="$(cat path/to/key)" \
#   bash scripts/update-appcast.sh
#
# Required env:
#   VERSION              SemVer (no leading v)
#   SPARKLE_PRIVATE_KEY  Base64 EdDSA private key (44 chars). Stored in
#                        the SPARKLE_PRIVATE_KEY repo secret.

set -euo pipefail

VERSION="${VERSION:?VERSION env var required}"
KEY_DATA="${SPARKLE_PRIVATE_KEY:?SPARKLE_PRIVATE_KEY env var required}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APPCAST="$ROOT/docs/appcast.xml"
ZIP_PATH="$ROOT/.build/FanCtl-$VERSION.zip"
ZIP_URL="https://github.com/Juanipis/fanctl/releases/download/v$VERSION/FanCtl-$VERSION.zip"
RELEASE_NOTES_URL="https://github.com/Juanipis/fanctl/releases/tag/v$VERSION"

[ -f "$ZIP_PATH" ] || { echo "❌ $ZIP_PATH does not exist — run Bundle/build-app.sh + package-zip.sh first"; exit 1; }
[ -f "$APPCAST"  ] || { echo "❌ $APPCAST missing — initialise it first"; exit 1; }

ZIP_SIZE="$(stat -f %z "$ZIP_PATH" 2>/dev/null || stat -c %s "$ZIP_PATH")"

# Persist the key to a temp file because sign_update reads from --ed-key-file.
KEY_FILE="$(mktemp)"
trap 'rm -f "$KEY_FILE"' EXIT
printf '%s' "$KEY_DATA" > "$KEY_FILE"
chmod 600 "$KEY_FILE"

# Locate sign_update. On the macOS GitHub Actions runner Sparkle ships via
# brew; locally we already installed the cask.
SIGN_UPDATE=""
for c in \
    "/opt/homebrew/Caskroom/sparkle/2.9.1/bin/sign_update" \
    "$(command -v sign_update || true)"; do
    if [ -n "$c" ] && [ -x "$c" ]; then SIGN_UPDATE="$c"; break; fi
done
if [ -z "$SIGN_UPDATE" ]; then
    SPARKLE_DIR="$(ls -d /opt/homebrew/Caskroom/sparkle/*/ 2>/dev/null | head -1)"
    [ -n "$SPARKLE_DIR" ] && SIGN_UPDATE="${SPARKLE_DIR}bin/sign_update"
fi
[ -x "$SIGN_UPDATE" ] || { echo "❌ sign_update not found"; exit 1; }

echo "==> signing $ZIP_PATH"
SIGNATURE="$("$SIGN_UPDATE" --ed-key-file "$KEY_FILE" "$ZIP_PATH")"
echo "    $SIGNATURE"

# Sparkle accepts RFC 2822 dates.
PUB_DATE="$(LC_ALL=C TZ=UTC date '+%a, %d %b %Y %H:%M:%S +0000')"

# Stage the new <item> in a temp file. Multi-line strings + awk -v fight
# enough that piping the block in via cat is the cleaner option.
ITEM_FILE="$(mktemp)"
cat > "$ITEM_FILE" <<XML
    <item>
      <title>FanCtl $VERSION</title>
      <pubDate>$PUB_DATE</pubDate>
      <sparkle:version>$VERSION</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>$RELEASE_NOTES_URL</sparkle:releaseNotesLink>
      <enclosure
          url="$ZIP_URL"
          type="application/zip"
          $SIGNATURE/>
    </item>
XML

# Insert immediately before </channel>. Most-recent first so older Sparkle
# clients still find the latest entry.
TMP_OUT="$(mktemp)"
inserted=""
while IFS= read -r line || [ -n "$line" ]; do
    if [ -z "$inserted" ] && [[ "$line" == *"</channel>"* ]]; then
        cat "$ITEM_FILE" >> "$TMP_OUT"
        inserted=1
    fi
    printf '%s\n' "$line" >> "$TMP_OUT"
done < "$APPCAST"
mv "$TMP_OUT" "$APPCAST"
rm -f "$ITEM_FILE"

echo "==> appended <item> for $VERSION to $APPCAST"
