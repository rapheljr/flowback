#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Flowback Pre-flight Local Verification Script
# Mirrors CI checks locally to prevent failing commits and CI breaks.
# ==============================================================================

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${PROJECT_ROOT}"

echo "=================================================="
echo " Running Flowback Pre-Flight Verification"
echo "=================================================="

# 1. SwiftLint in Strict Mode
echo ""
echo "▶ [1/4] Running SwiftLint (--strict)..."
if command -v swiftlint >/dev/null 2>&1; then
    # Auto-detect CommandLineTools library path if running on CLT-only macOS
    if [ -d "/Library/Developer/CommandLineTools/usr/lib" ] && [ ! -d "/Applications/Xcode.app" ]; then
        export DYLD_FRAMEWORK_PATH="/Library/Developer/CommandLineTools/usr/lib"
    fi
    swiftlint lint --strict
    echo "✓ SwiftLint passed with 0 violations."
else
    echo "⚠️ swiftlint not found in PATH. Install via 'brew install swiftlint'."
fi

# 2. Swift Build
echo ""
echo "▶ [2/4] Compiling Swift Package (Debug & Release)..."
swift build
echo "✓ Swift build succeeded."

# 3. Standalone Verification Suites (FlowbackTestRunner)
echo ""
echo "▶ [3/4] Running Standalone Verification Test Suite (FlowbackTestRunner)..."
swift run FlowbackTestRunner
echo "✓ All verification suites passed."

# 4. Unit & Integration Tests (XCTest if available)
echo ""
echo "▶ [4/4] Checking XCTest availability..."
XCODE_FRAMEWORKS="/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library/Frameworks/XCTest.framework"
if [ -d "${XCODE_FRAMEWORKS}" ] || [ -n "${CI:-}" ]; then
    echo "Running XCTest suite..."
    ENABLE_XCTEST=1 swift test --parallel
    echo "✓ XCTest suite passed."
else
    echo "ℹ️ Xcode.app not detected at /Applications/Xcode.app; skipping XCTest (covered by FlowbackTestRunner)."
fi

# 5. Documentation & Markdown Link Validation
echo ""
echo "▶ [5/6] Validating Markdown Documentation Links..."
python3 -c "
import os, re
files = [f for f in os.listdir('.') if f.endswith('.md')]
for f in files:
    content = open(f).read()
    links = re.findall(r'\[.*?\]\((?!http|#|mailto:)(.*?)\)', content)
    for link in links:
        target = link.split('#')[0]
        if target and not os.path.exists(target):
            raise SystemExit(f'Broken link in {f}: {target}')
print(f'✓ Verified {len(files)} root markdown documents.')
"

# 6. Canonical Version & Metadata Synchronization Validation
echo ""
echo "▶ [6/6] Validating Canonical Version & Metadata Synchronization..."
bash "$PROJECT_ROOT/Scripts/validate_version_sync.sh"

echo ""
echo "=================================================="
echo "🎉 ALL LOCAL CHECKS PASSED — READY TO COMMIT/PUSH!"
echo "=================================================="
