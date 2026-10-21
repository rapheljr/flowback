#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Flowback Milestone GitHub Releases Publisher
# Publishes defensible, historical GitHub Releases for each pre-1.0 milestone.
#
# Usage:
#   bash Scripts/publish_milestone_releases.sh [--dry-run | --execute]
# ==============================================================================

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${PROJECT_ROOT}"

MODE="dry-run"
if [[ $# -gt 0 ]]; then
    case "$1" in
        --execute)
            MODE="execute"
            ;;
        --dry-run)
            MODE="dry-run"
            ;;
        *)
            echo "Usage: $0 [--dry-run | --execute]" >&2
            exit 1
            ;;
    esac
fi

echo "=================================================================="
echo " Flowback Milestone GitHub Releases Publisher (Mode: $MODE)"
echo "=================================================================="

# 1. Verify GitHub CLI installation and authentication
if ! command -v gh >/dev/null 2>&1; then
    echo "❌ Error: GitHub CLI ('gh') is not installed. Install via 'brew install gh'." >&2
    exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
    echo "❌ Error: GitHub CLI is not authenticated. Run 'gh auth login' first." >&2
    exit 1
fi
echo "✓ GitHub CLI authenticated."

# 2. Check if local main is ahead of remote
if git status -s -b | grep -q "ahead"; then
    echo "⚠️ Warning: Local branch 'main' has unpushed commits."
    if [ "$MODE" = "execute" ]; then
        echo "Pushing 'main' to origin so latest commit is available on GitHub..."
        git push origin main
        echo "✓ Pushed main to origin."
    else
        echo "  (In --execute mode, 'git push origin main' will be run first)."
    fi
fi

# 3. Define the 7 Reconstructed Milestones
# Format: Tag|Commit|Title|IsLatest
MILESTONES=(
    "v0.0.1|35caa54|v0.0.1: First Working Prototype (IPC & SQLite Safety)|false"
    "v0.1.0|2ba8fd5|v0.1.0: Deterministic 12-Step Focus Engine & Standalone Daemon|false"
    "v0.1.1|3b2c454|v0.1.1: Apple HIG Compliance & Brand Identity|false"
    "v0.1.2|cdcd2d0|v0.1.2: Packaging, Socket Hardening & Degraded WAL Recovery|false"
    "v0.2.0|d017217|v0.2.0: Multi-Agent Provider Expansion (Windsurf, OpenCode, Cursor, agy)|false"
    "v0.3.0|c25464f|v0.3.0: Conversation Intelligence & Burst UI Coalescing|false"
    "v0.4.0|435de41|v0.4.0: macOS Card Design System, Copilot Provider & General Sidebar Destinations|false"
    "v0.4.1|HEAD|v0.4.1: Focus Hardening, Concurrency Safety & Codebase Audit Remediation|true"
)

# Temporary directory for release notes
TEMP_NOTES_DIR="$(mktemp -d /tmp/flowback-rel-notes.XXXXXX)"
trap 'rm -rf "$TEMP_NOTES_DIR"' EXIT

# Helper function to extract release notes from CHANGELOG.md for a given version
extract_notes() {
    local version="$1"
    python3 -c "
import re, sys
changelog = open('CHANGELOG.md').read()
pattern = r'## \[' + re.escape('$version') + r'\] - [^\n]+\n(.*?)(?=\n## \[|\Z)'
m = re.search(pattern, changelog, re.DOTALL)
if m:
    print(m.group(1).strip())
else:
    print('Release notes for milestone $version')
"
}

echo ""
echo "Milestone Release Pipeline (${#MILESTONES[@]} releases):"
echo "------------------------------------------------------------------"

for entry in "${MILESTONES[@]}"; do
    IFS='|' read -r TAG COMMIT TITLE IS_LATEST <<< "$entry"
    VERSION="${TAG#v}"
    FULL_COMMIT=$(git rev-parse "$COMMIT")
    NOTES_FILE="$TEMP_NOTES_DIR/notes-${TAG}.md"
    extract_notes "$VERSION" > "$NOTES_FILE"

    echo ""
    echo "▶ Target: $TAG"
    echo "  Commit:    $FULL_COMMIT ($COMMIT)"
    echo "  Title:     $TITLE"
    echo "  Is Latest: $IS_LATEST"
    echo "  Notes preview: $(head -n 2 "$NOTES_FILE" | tr '\n' ' ')..."

    # Build release command
    GH_CMD=(gh release create "$TAG" --target "$FULL_COMMIT" --title "$TITLE" --notes-file "$NOTES_FILE")

    if [ "$IS_LATEST" = "true" ]; then
        GH_CMD+=(--latest)
        if [ "$MODE" = "execute" ] && [ ! -f "dist/Flowback-${VERSION}-arm64.dmg" ]; then
            echo "  Packaging distribution artifacts for v${VERSION}..."
            bash "$PROJECT_ROOT/Scripts/package_release_artifacts.sh" "$VERSION" universal 1
        fi
        # Check if assets exist in dist/
        ASSETS=()
        for f in "dist/Flowback-${VERSION}-arm64.dmg" "dist/Flowback-${VERSION}.dmg" "dist/Flowback-${VERSION}-arm64.zip" "dist/Flowback-${VERSION}-macos.zip" "dist/release-manifest.json" "dist/SHA256SUMS"; do
            if [ -f "$f" ]; then
                ASSETS+=("$f")
            fi
        done
        if [ ${#ASSETS[@]} -gt 0 ]; then
            GH_CMD+=("${ASSETS[@]}")
            echo "  Assets:    ${#ASSETS[@]} binaries attached (${ASSETS[*]})"
        fi
    else
        GH_CMD+=(--prerelease)
    fi

    if [ "$MODE" = "dry-run" ]; then
        echo "  [Dry Run Command]: ${GH_CMD[*]}"
    elif [ "$MODE" = "execute" ]; then
        echo "  Publishing $TAG to GitHub..."
        "${GH_CMD[@]}"
        echo "  ✓ Published: https://github.com/rapheljr/flowback/releases/tag/$TAG"
    fi
done

echo ""
echo "=================================================================="
if [ "$MODE" = "dry-run" ]; then
    echo "Dry-run complete! All 7 milestone releases validated."
    echo "To publish for real on GitHub, run:"
    echo "  bash Scripts/publish_milestone_releases.sh --execute"
else
    echo "🎉 ALL 7 MILESTONES PUBLISHED TO GITHUB RELEASES!"
    echo "View at: https://github.com/rapheljr/flowback/releases"
fi
echo "=================================================================="
