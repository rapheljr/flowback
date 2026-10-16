#!/bin/bash
set -euo pipefail

ARCH="$(uname -m)"
echo "=========================================="
echo "Building Flowback (Release Mode - ${ARCH})"
echo "=========================================="

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

swift build -c release

mkdir -p "$PROJECT_ROOT/dist/bin"
cp "$PROJECT_ROOT/.build/release/flowback-cli" "$PROJECT_ROOT/dist/bin/flowback"
chmod +x "$PROJECT_ROOT/dist/bin/flowback"

echo "Build complete."
echo "Binaries located at:"
echo "  - $PROJECT_ROOT/.build/release/Flowback ($(file -b "$PROJECT_ROOT/.build/release/Flowback"))"
echo "  - $PROJECT_ROOT/dist/bin/flowback ($(file -b "$PROJECT_ROOT/dist/bin/flowback"))"
echo "  - $PROJECT_ROOT/.build/release/FlowbackTestRunner ($(file -b "$PROJECT_ROOT/.build/release/FlowbackTestRunner"))"
