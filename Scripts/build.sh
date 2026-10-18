#!/bin/bash
set -euo pipefail

ARCH_REQ="${1:-${ARCH:-native}}"
HOST_ARCH="$(uname -m)"

if [ "$ARCH_REQ" = "native" ]; then
    TARGET_ARCH="$HOST_ARCH"
else
    TARGET_ARCH="$ARCH_REQ"
fi

echo "=========================================="
echo "Building Flowback (Release Mode - ${TARGET_ARCH})"
echo "=========================================="

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

mkdir -p "$PROJECT_ROOT/dist/bin"

# Suppress harmless Command Line Tools SDK path warnings on CLT-only macOS
LINKER_FLAGS=(-Xlinker -w)

build_swift_release() {
    # On CLT-only macOS installations, Apple's Swift 6 build engine adds non-existent
    # /Library/Developer/CommandLineTools/Developer search paths during intermediate module linking.
    # We pass -Xlinker -w for product linking and filter harmless CLT search path warnings.
    swift build -c release "$@" "${LINKER_FLAGS[@]}" 2>&1 | \
        sed -E "/ld: warning: search path '\/Library\/Developer\/CommandLineTools\/Developer/d"
}

if [ "$TARGET_ARCH" = "universal" ]; then
    echo "Compiling Universal 2 binaries (arm64 + x86_64)..."
    STAGING_DIR="$(mktemp -d /tmp/flowback-universal.XXXXXX)"
    trap 'rm -rf "$STAGING_DIR"' EXIT

    echo "  -> Compiling arm64 slice..."
    build_swift_release --triple arm64-apple-macosx14.0
    cp "$PROJECT_ROOT/.build/release/Flowback" "$STAGING_DIR/Flowback-arm64"
    cp "$PROJECT_ROOT/.build/release/flowback-cli" "$STAGING_DIR/flowback-cli-arm64"

    echo "  -> Compiling x86_64 slice..."
    build_swift_release --triple x86_64-apple-macosx14.0
    cp "$PROJECT_ROOT/.build/release/Flowback" "$STAGING_DIR/Flowback-x86_64"
    cp "$PROJECT_ROOT/.build/release/flowback-cli" "$STAGING_DIR/flowback-cli-x86_64"

    echo "  -> Creating universal fat binaries with lipo..."
    rm -f "$PROJECT_ROOT/.build/release/Flowback" "$PROJECT_ROOT/.build/release/flowback-cli"
    lipo -create -output "$PROJECT_ROOT/.build/release/Flowback" \
        "$STAGING_DIR/Flowback-arm64" "$STAGING_DIR/Flowback-x86_64"
    lipo -create -output "$PROJECT_ROOT/.build/release/flowback-cli" \
        "$STAGING_DIR/flowback-cli-arm64" "$STAGING_DIR/flowback-cli-x86_64"
    chmod +x "$PROJECT_ROOT/.build/release/Flowback"
    chmod +x "$PROJECT_ROOT/.build/release/flowback-cli"

    cp "$PROJECT_ROOT/.build/release/flowback-cli" "$PROJECT_ROOT/dist/bin/flowback"
    chmod +x "$PROJECT_ROOT/dist/bin/flowback"

    # Strict architecture validation
    LIPO_OUT="$(lipo -info "$PROJECT_ROOT/.build/release/Flowback")"
    if ! echo "$LIPO_OUT" | grep -q "x86_64" || ! echo "$LIPO_OUT" | grep -q "arm64"; then
        echo "Error: Universal build failed to produce fat binary with both arm64 and x86_64: $LIPO_OUT" >&2
        exit 1
    fi
elif [ "$TARGET_ARCH" = "arm64" ]; then
    echo "Compiling dedicated Apple Silicon (arm64) binary..."
    rm -f "$PROJECT_ROOT/.build/release/Flowback" "$PROJECT_ROOT/.build/release/flowback-cli"
    build_swift_release --triple arm64-apple-macosx14.0
    cp "$PROJECT_ROOT/.build/release/flowback-cli" "$PROJECT_ROOT/dist/bin/flowback"
    chmod +x "$PROJECT_ROOT/dist/bin/flowback"

    # Strict architecture validation
    LIPO_OUT="$(lipo -info "$PROJECT_ROOT/.build/release/Flowback")"
    if echo "$LIPO_OUT" | grep -q "x86_64" || ! echo "$LIPO_OUT" | grep -q "arm64"; then
        echo "Error: arm64 build produced unexpected architecture: $LIPO_OUT" >&2
        exit 1
    fi
elif [ "$TARGET_ARCH" = "x86_64" ]; then
    echo "Compiling dedicated Intel (x86_64) binary..."
    rm -f "$PROJECT_ROOT/.build/release/Flowback" "$PROJECT_ROOT/.build/release/flowback-cli"
    build_swift_release --triple x86_64-apple-macosx14.0
    cp "$PROJECT_ROOT/.build/release/flowback-cli" "$PROJECT_ROOT/dist/bin/flowback"
    chmod +x "$PROJECT_ROOT/dist/bin/flowback"

    # Strict architecture validation
    LIPO_OUT="$(lipo -info "$PROJECT_ROOT/.build/release/Flowback")"
    if echo "$LIPO_OUT" | grep -q "arm64" || ! echo "$LIPO_OUT" | grep -q "x86_64"; then
        echo "Error: x86_64 build produced unexpected architecture: $LIPO_OUT" >&2
        exit 1
    fi
else
    echo "Compiling host architecture ($TARGET_ARCH)..."
    rm -f "$PROJECT_ROOT/.build/release/Flowback" "$PROJECT_ROOT/.build/release/flowback-cli"
    build_swift_release
    cp "$PROJECT_ROOT/.build/release/flowback-cli" "$PROJECT_ROOT/dist/bin/flowback"
    chmod +x "$PROJECT_ROOT/dist/bin/flowback"
fi

echo "Build complete."
echo "Binaries located at:"
echo "  - $PROJECT_ROOT/.build/release/Flowback ($(file -b "$PROJECT_ROOT/.build/release/Flowback"))"
echo "  - $PROJECT_ROOT/dist/bin/flowback ($(file -b "$PROJECT_ROOT/dist/bin/flowback"))"
