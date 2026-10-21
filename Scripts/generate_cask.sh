#!/bin/bash
set -euo pipefail

# Flowback Homebrew Cask Generator
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$PROJECT_ROOT/dist"
CASKS_DIR="$PROJECT_ROOT/Casks"

CANONICAL_VERSION=$(cat "$PROJECT_ROOT/VERSION" 2>/dev/null || echo "0.4.1")
VERSION="${1:-${FLOWBACK_VERSION:-$CANONICAL_VERSION}}"
ZIP_PATH="$DIST_DIR/Flowback-${VERSION}-macos.zip"

echo "=========================================="
echo "Generating Homebrew Cask for v${VERSION}"
echo "=========================================="

mkdir -p "$CASKS_DIR"

if [ ! -f "$ZIP_PATH" ]; then
    # Fallback to arm64 or unversioned if macos.zip not present
    if [ -f "$DIST_DIR/Flowback-${VERSION}-arm64.zip" ]; then
        ZIP_PATH="$DIST_DIR/Flowback-${VERSION}-arm64.zip"
    elif [ -f "$DIST_DIR/Flowback.dmg" ]; then
        ZIP_PATH="$DIST_DIR/Flowback.dmg"
    else
        echo "Error: Release artifact not found in $DIST_DIR to compute Cask SHA-256." >&2
        echo "Expected $DIST_DIR/Flowback-${VERSION}-macos.zip" >&2
        exit 1
    fi
fi

SHA256="$(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')"
echo "Target Artifact: $(basename "$ZIP_PATH")"
echo "Verified SHA-256: $SHA256"

CASK_FILE="$CASKS_DIR/flowback.rb"

cat << EOF > "$CASK_FILE"
cask "flowback" do
  version "${VERSION}"
  sha256 "${SHA256}"

  url "https://github.com/rapheljr/flowback/releases/download/v#{version}/Flowback-#{version}-macos.zip"
  name "Flowback"
  desc "Focus and context orchestration across developer applications"
  homepage "https://rapheljr.github.io/flowback/"

  depends_on macos: :sonoma

  app "Flowback.app"
  binary "#{appdir}/Flowback.app/Contents/Resources/flowback"

  uninstall quit: "com.flowback.app"

  zap trash: [
    "~/.flowback",
    "~/Library/Preferences/com.flowback.app.plist",
    "~/Library/Saved Application State/com.flowback.app.savedState",
  ]
end
EOF

echo "Staged Cask successfully written to:"
echo "  $CASK_FILE"
cat "$CASK_FILE"

# If brew is installed, validate the staged cask with brew audit & brew style
if command -v brew >/dev/null 2>&1; then
    echo ""
    echo "Auditing staged cask with local Homebrew installation..."
    TMP_TAP="flowback-audit-staging/tap"
    brew tap-new --no-git "$TMP_TAP" >/dev/null 2>&1 || true
    TMP_TAP_DIR="$(brew --repo "$TMP_TAP" 2>/dev/null || true)"
    
    if [ -n "$TMP_TAP_DIR" ] && [ -d "$TMP_TAP_DIR" ]; then
        mkdir -p "$TMP_TAP_DIR/Casks"
        cp "$CASK_FILE" "$TMP_TAP_DIR/Casks/flowback.rb"
        
        echo "Running 'brew style --cask $TMP_TAP/flowback'..."
        brew style --cask "$TMP_TAP/flowback"
        
        echo "Running 'brew audit --cask $TMP_TAP/flowback'..."
        brew audit --cask "$TMP_TAP/flowback"
        
        brew untap "$TMP_TAP" >/dev/null 2>&1 || true
        echo "✓ Homebrew audit & style checks passed with 0 offenses."
    fi
fi
