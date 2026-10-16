#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "=========================================="
echo "Installing Flowback CLI ('flowback')"
echo "=========================================="

BINARY_PATH=""
if [ -f "$PROJECT_ROOT/dist/bin/flowback" ]; then
    BINARY_PATH="$PROJECT_ROOT/dist/bin/flowback"
elif [ -f "$PROJECT_ROOT/.build/release/flowback-cli" ]; then
    BINARY_PATH="$PROJECT_ROOT/.build/release/flowback-cli"
elif [ -f "$PROJECT_ROOT/.build/debug/flowback-cli" ]; then
    BINARY_PATH="$PROJECT_ROOT/.build/debug/flowback-cli"
else
    echo "CLI binary not found. Building..."
    cd "$PROJECT_ROOT"
    swift build -c release --product flowback-cli
    BINARY_PATH="$PROJECT_ROOT/.build/release/flowback-cli"
fi

# Determine target directory
TARGET_DIR="/usr/local/bin"
if [ ! -w "$TARGET_DIR" ]; then
    TARGET_DIR="$HOME/.local/bin"
    mkdir -p "$TARGET_DIR"
fi

DESTINATION="$TARGET_DIR/flowback"
echo "Installing to $DESTINATION..."
cp "$BINARY_PATH" "$DESTINATION"
chmod +x "$DESTINATION"

echo "Flowback CLI successfully installed!"
echo "Version check:"
"$DESTINATION" --help || true

if [[ ":$PATH:" != *":$TARGET_DIR:"* ]]; then
    echo ""
    echo "NOTE: $TARGET_DIR is not in your PATH."
    echo "Add the following line to your ~/.zshrc or ~/.bashrc:"
    echo "  export PATH=\"$TARGET_DIR:\$PATH\""
fi
