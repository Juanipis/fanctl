#!/bin/bash
# Bumps the Homebrew Cask in Juanipis/homebrew-tap to point at a new
# FanCtl release. Pulls the .sha256 sidecar straight from the GitHub
# release, rewrites Casks/fanctl.rb, and pushes a "feat: bump fanctl
# to vX.Y.Z" commit.
#
# Usage:
#   VERSION=1.2.3 bash scripts/bump-cask.sh
#
# Required:
#   - `gh` authenticated (used for git push via SSH/HTTPS auth).
#   - Write access to Juanipis/homebrew-tap.
#
# Triggered automatically by .github/workflows/bump-cask.yml on every
# semantic-release tag, when the HOMEBREW_TAP_TOKEN secret is set.

set -euo pipefail

VERSION="${VERSION:?VERSION env var required, e.g. 1.2.3}"
TAP_REPO="Juanipis/homebrew-tap"
ZIP_NAME="FanCtl-$VERSION.zip"
ZIP_URL="https://github.com/Juanipis/fanctl/releases/download/v$VERSION/$ZIP_NAME"
SHA_URL="$ZIP_URL.sha256"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

echo "==> Fetching SHA-256 for $ZIP_NAME"
SHA="$(curl -fsSL "$SHA_URL" | tr -d '[:space:]')"
[ -n "$SHA" ] || { echo "❌ empty sha"; exit 1; }
echo "    $SHA"

echo "==> Cloning $TAP_REPO"
git clone --depth=1 "https://github.com/$TAP_REPO.git" "$WORK_DIR/tap"
CASK="$WORK_DIR/tap/Casks/fanctl.rb"

echo "==> Rewriting cask"
# Replace `version "..."` and `sha256 "..."` lines.
sed -i.bak -E \
    -e "s|^(  version )\"[^\"]+\"|\\1\"$VERSION\"|" \
    -e "s|^(  sha256 )\"[^\"]+\"|\\1\"$SHA\"|" \
    "$CASK"
rm -f "$CASK.bak"
diff <(git -C "$WORK_DIR/tap" show HEAD:Casks/fanctl.rb) "$CASK" || true

cd "$WORK_DIR/tap"
git config user.name  "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git add Casks/fanctl.rb
if git diff --cached --quiet; then
    echo "==> Cask already at $VERSION, nothing to do"
    exit 0
fi
git commit -q -m "feat(fanctl): bump to $VERSION

sha256: $SHA
release: https://github.com/Juanipis/fanctl/releases/tag/v$VERSION"
git push origin main
echo "==> Pushed bump to $TAP_REPO"
