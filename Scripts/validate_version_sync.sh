#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Flowback Canonical Version & Metadata Synchronization Validator
# Enforces that all single-source version references are strictly synchronized.
#
# Usage:
#   bash Scripts/validate_version_sync.sh [--tag <git-tag>]
# ==============================================================================

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${PROJECT_ROOT}"

EXPECTED_TAG=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --tag)
            EXPECTED_TAG="$2"
            shift 2
            ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 1
            ;;
    esac
done

echo "=================================================================="
echo " Validating Flowback Canonical Version & Metadata Synchronization"
echo "=================================================================="

# 1. Validate VERSION file
if [ ! -f "VERSION" ]; then
    echo "❌ Error: Root 'VERSION' file is missing." >&2
    exit 1
fi
VERSION=$(cat "VERSION" | tr -d '[:space:]')
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$ ]]; then
    echo "❌ Error: VERSION '$VERSION' does not adhere to Semantic Versioning (SemVer 2.0.0)." >&2
    exit 1
fi
echo "✓ Root VERSION file: $VERSION"

# 2. Validate BUILD file
if [ ! -f "BUILD" ]; then
    echo "❌ Error: Root 'BUILD' file is missing." >&2
    exit 1
fi
BUILD_NUMBER=$(cat "BUILD" | tr -d '[:space:]')
if [[ ! "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
    echo "❌ Error: BUILD '$BUILD_NUMBER' must be a positive integer." >&2
    exit 1
fi
echo "✓ Root BUILD file: $BUILD_NUMBER"

# 3. Validate Sources/FlowbackCore/FlowbackVersion.swift
SWIFT_VERSION_FILE="Sources/FlowbackCore/FlowbackVersion.swift"
if [ ! -f "$SWIFT_VERSION_FILE" ]; then
    echo "❌ Error: '$SWIFT_VERSION_FILE' is missing." >&2
    exit 1
fi

SWIFT_MKT_VER=$(python3 -c "
import re
src = open('$SWIFT_VERSION_FILE').read()
m = re.search(r'marketingVersion:\s*String\s*=\s*\"([^\"]+)\"', src)
print(m.group(1) if m else '')
")
SWIFT_BLD_NUM=$(python3 -c "
import re
src = open('$SWIFT_VERSION_FILE').read()
m = re.search(r'buildNumber:\s*String\s*=\s*\"([^\"]+)\"', src)
print(m.group(1) if m else '')
")

if [ "$SWIFT_MKT_VER" != "$VERSION" ]; then
    echo "❌ Error: FlowbackVersion.marketingVersion ('$SWIFT_MKT_VER') does not match VERSION ('$VERSION')." >&2
    exit 1
fi
if [ "$SWIFT_BLD_NUM" != "$BUILD_NUMBER" ]; then
    echo "❌ Error: FlowbackVersion.buildNumber ('$SWIFT_BLD_NUM') does not match BUILD ('$BUILD_NUMBER')." >&2
    exit 1
fi
echo "✓ Sources/FlowbackCore/FlowbackVersion.swift matches VERSION and BUILD"

# 4. Validate CHANGELOG.md contains section for current VERSION
if [ ! -f "CHANGELOG.md" ]; then
    echo "❌ Error: 'CHANGELOG.md' is missing." >&2
    exit 1
fi
if ! grep -qE "## \[${VERSION}\]" "CHANGELOG.md"; then
    echo "❌ Error: CHANGELOG.md does not contain a release entry for '## [${VERSION}]'." >&2
    exit 1
fi
echo "✓ CHANGELOG.md contains release entry for [${VERSION}]"

# 5. Validate Sources/FlowbackUI/Common/ReleaseNotesModel.swift latest note
RELEASE_NOTES_FILE="Sources/FlowbackUI/Common/ReleaseNotesModel.swift"
if [ -f "$RELEASE_NOTES_FILE" ]; then
    LATEST_NOTE_VER=$(python3 -c "
import re
src = open('$RELEASE_NOTES_FILE').read()
m = re.search(r'ReleaseNote\(\s*id:\s*\"[^\"]+\",\s*version:\s*\"([^\"]+)\"', src)
print(m.group(1) if m else '')
")
    if [ "$LATEST_NOTE_VER" != "$VERSION" ]; then
        echo "❌ Error: ReleaseNotesModel.bundledNotes latest entry ('$LATEST_NOTE_VER') does not match VERSION ('$VERSION')." >&2
        exit 1
    fi
    echo "✓ ReleaseNotesModel.bundledNotes latest entry matches VERSION ('$VERSION')"
fi

# 6. Validate Homebrew Formula
FORMULA_FILE="Formula/flowback-cli.rb"
if [ -f "$FORMULA_FILE" ]; then
    if ! grep -q "version \"${VERSION}\"" "$FORMULA_FILE"; then
        echo "❌ Error: $FORMULA_FILE does not specify version \"${VERSION}\"." >&2
        exit 1
    fi
    echo "✓ $FORMULA_FILE matches VERSION ('$VERSION')"
fi

# 7. Validate Homebrew Cask
CASK_FILE="Casks/flowback.rb"
if [ -f "$CASK_FILE" ]; then
    if ! grep -q "version \"${VERSION}\"" "$CASK_FILE"; then
        echo "❌ Error: $CASK_FILE does not specify version \"${VERSION}\"." >&2
        exit 1
    fi
    echo "✓ $CASK_FILE matches VERSION ('$VERSION')"
fi

# 8. Validate Website release-manifest.json
MANIFEST_FILE="Website/release-manifest.json"
if [ -f "$MANIFEST_FILE" ]; then
    MANIFEST_VER=$(python3 -c "
import json
data = json.load(open('$MANIFEST_FILE'))
print(data.get('version', ''))
")
    if [ "$MANIFEST_VER" != "$VERSION" ]; then
        echo "❌ Error: $MANIFEST_FILE version ('$MANIFEST_VER') does not match VERSION ('$VERSION')." >&2
        exit 1
    fi
    echo "✓ $MANIFEST_FILE matches VERSION ('$VERSION')"
fi

# 9. Optional: Validate Git tag alignment (if provided via --tag)
if [ -n "$EXPECTED_TAG" ]; then
    EXPECTED_VER="${EXPECTED_TAG#v}"
    if [ "$EXPECTED_VER" != "$VERSION" ]; then
        echo "❌ Error: Tag '$EXPECTED_TAG' corresponds to version '$EXPECTED_VER', but repository canonical VERSION is '$VERSION'." >&2
        exit 1
    fi
    echo "✓ Target Git tag '$EXPECTED_TAG' matches repository canonical VERSION ('$VERSION')"
fi

echo ""
echo "=================================================================="
echo "🎉 ALL VERSION SYNCHRONIZATION CHECKS PASSED: v${VERSION} (Build ${BUILD_NUMBER})"
echo "=================================================================="
