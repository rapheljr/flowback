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

# 2. Remove hooks
echo "Cleaning up agent hooks..."
HOOKS_CONFIG="$HOME/.gemini/config/hooks.json"
if [ -f "$HOOKS_CONFIG" ]; then
    python3 -c "
import json, os
path = os.path.expanduser('$HOOKS_CONFIG')
try:
    with open(path, 'r') as f:
        data = json.load(f)
    changed = False
    if 'flowback-agent-focus' in data:
        del data['flowback-agent-focus']
        changed = True
    if 'hooks' in data and isinstance(data['hooks'], dict):
        for event, cmd_list in data['hooks'].items():
            if isinstance(cmd_list, list):
                original_len = len(cmd_list)
                data['hooks'][event] = [c for c in cmd_list if 'flowback' not in str(c)]
                if len(data['hooks'][event]) != original_len:
                    changed = True
    if changed:
        with open(path, 'w') as f:
            json.dump(data, f, indent=2)
        print('  ✓ Cleaned Flowback entries from hooks.json')
except Exception as e:
    pass
" || true
fi

# 3. Remove application bundle
if [ -d "/Applications/Flowback.app" ]; then
    echo "Removing /Applications/Flowback.app..."
    rm -rf "/Applications/Flowback.app"
fi

# 4. Remove CLI binary
CLI_PATHS=(
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
