#!/bin/bash
set -euo pipefail

# Flowback Clean Uninstaller Script

echo "=========================================="
echo "Flowback macOS Uninstallation"
echo "=========================================="

echo "This script safely removes Flowback application binaries, CLI tools, and background hooks."
echo "It will NEVER delete your source code repositories or project directories."
echo ""

# 1. Terminate running instances
if pgrep -x "Flowback" >/dev/null 2>&1; then
    echo "Stopping Flowback application..."
    pkill -x "Flowback" || true
    sleep 1
fi

# 2. Remove hooks across all supported providers
echo "Cleaning up agent hooks..."
for HOOKS_CONFIG in "$HOME/.gemini/config/hooks.json" "$HOME/.codeium/windsurf/hooks.json" "$HOME/.claude/settings.json"; do
    if [ -f "$HOOKS_CONFIG" ]; then
        python3 -c "
import json, os
path = os.path.expanduser('$HOOKS_CONFIG')
try:
    with open(path, 'r') as f:
        data = json.load(f)
    changed = False
    for key in ('flowback-antigravity', 'flowback-antigravity-cli', 'flowback-agent-focus'):
        if key in data:
            del data[key]
            changed = True
    if 'hooks' in data and isinstance(data['hooks'], dict):
        for event, cmd_list in list(data['hooks'].items()):
            if isinstance(cmd_list, list):
                original_len = len(cmd_list)
                data['hooks'][event] = [c for c in cmd_list if 'flowback' not in str(c)]
                if len(data['hooks'][event]) != original_len:
                    changed = True
                if not data['hooks'][event]:
                    del data['hooks'][event]
    if changed:
        with open(path, 'w') as f:
            json.dump(data, f, indent=2)
        print(f'  ✓ Cleaned Flowback entries from {path}')
except Exception:
    pass
" || true
    fi
done

if [ -f "$HOME/.config/opencode/plugins/flowback.js" ]; then
    rm -f "$HOME/.config/opencode/plugins/flowback.js"
    echo "  ✓ Removed OpenCode plugin (~/.config/opencode/plugins/flowback.js)"
fi

# 3. Remove application bundle
if [ -d "/Applications/Flowback.app" ]; then
    echo "Removing /Applications/Flowback.app..."
    rm -rf "/Applications/Flowback.app"
fi

# 4. Remove CLI binary
CLI_PATHS=(
    "/opt/homebrew/bin/flowback"
    "/usr/local/bin/flowback"
    "$HOME/.local/bin/flowback"
)

for path in "${CLI_PATHS[@]}"; do
    if [ -f "$path" ]; then
        echo "Removing CLI from $path..."
        rm -f "$path"
    fi
done

# 5. Persistent local data handling
DB_DIR="$HOME/.flowback"
if [ -d "$DB_DIR" ]; then
    echo ""
    echo "Persistent local database found at: $DB_DIR"
    echo "This directory contains session history, local settings, and SQLite databases."
    
    # Check if run with --force-clean-data flag or interactively
    if [[ "${1:-}" == "--purge-data" ]]; then
        echo "Purging $DB_DIR..."
        rm -rf "$DB_DIR"
    else
        echo "Keeping $DB_DIR to preserve history. To remove it manually, run:"
        echo "  rm -rf $DB_DIR"
    fi
fi

echo ""
echo "=========================================="
echo "Flowback uninstallation complete."
echo "=========================================="
