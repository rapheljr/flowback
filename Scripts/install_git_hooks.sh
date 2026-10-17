#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

chmod +x .githooks/pre-commit
chmod +x Scripts/verify_all.sh

git config core.hooksPath .githooks
echo "✓ Git hooks successfully configured! Pre-commit verification is now active."
