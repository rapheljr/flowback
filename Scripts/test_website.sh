#!/bin/bash
set -euo pipefail

# Flowback Website Build & Validation Script
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WEBSITE_DIR="$PROJECT_ROOT/Website"

echo "=========================================="
echo "Validating Flowback Marketing Website"
echo "=========================================="

cd "$WEBSITE_DIR"

# 1. Required HTML Pages Check
PAGES=(
  "index.html"
  "features/index.html"
  "download/index.html"
  "docs/index.html"
  "contributing/index.html"
  "changelog/index.html"
  "privacy/index.html"
  "404.html"
)

echo "Checking required pages..."
for page in "${PAGES[@]}"; do
  if [ ! -f "$page" ]; then
    echo "❌ Missing required page: $page"
    exit 1
  fi
  echo "  ✓ $page found"
done

# 2. Asset Integrity Check
ASSETS=(
  "css/main.css"
  "js/main.js"
  "assets/flowback-icon.svg"
  "assets/flowback-banner.svg"
  "assets/architecture-diagram.svg"
  "assets/dashboard-preview.svg"
  "release-manifest.json"
  "sitemap.xml"
  "robots.txt"
)

echo "Checking assets and manifests..."
for asset in "${ASSETS[@]}"; do
  if [ ! -f "$asset" ]; then
    echo "❌ Missing asset: $asset"
    exit 1
  fi
  echo "  ✓ $asset verified"
done

# 3. Release Manifest JSON Validation
echo "Validating release-manifest.json format..."
python3 -c "
import json
with open('release-manifest.json') as f:
    data = json.load(f)
assert data.get('schemaVersion') == 1, 'Missing schemaVersion'
assert 'version' in data, 'Missing version'
assert 'artifacts' in data and len(data['artifacts']) > 0, 'No artifacts declared'
print('  ✓ release-manifest.json schema version 1 valid with', len(data['artifacts']), 'artifacts')
"

# 4. Internal Link Validation
echo "Validating internal link references across all HTML files..."
python3 -c "
import os, re

errors = 0
checked = 0

for root, _, files in os.walk('.'):
    for f in files:
        if f.endswith('.html'):
            page_path = os.path.join(root, f)
            with open(page_path, 'r', encoding='utf-8') as handle:
                html = handle.read()
            
            # Find relative hrefs and srcs
            links = re.findall(r'(?:href|src)=[\"\']([^#\"\'\s:]+)(?:#[^\"\']*)?[\"\']', html)
            for link in links:
                if link.startswith(('http', 'mailto:', 'javascript:', 'data:')):
                    continue
                checked += 1
                dir_path = os.path.dirname(page_path)
                resolved = os.path.normpath(os.path.join(dir_path, link))
                
                # Check file directly or index.html if pointing to directory
                if os.path.isdir(resolved):
                    resolved = os.path.join(resolved, 'index.html')
                    
                if not os.path.exists(resolved):
                    print(f'❌ Broken link in {page_path}: {link} -> {resolved}')
                    errors += 1

if errors > 0:
    print(f'Failed with {errors} broken link(s)!')
    exit(1)
print(f'  ✓ All {checked} internal link references verified successfully!')
"

echo "=========================================="
echo "ALL WEBSITE VALIDATIONS PASSED! ✓"
echo "=========================================="
