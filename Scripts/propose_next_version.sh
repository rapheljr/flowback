#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Flowback Read-Only Next-Version Calculation Tool
# Analyzes Git history following the latest valid release tag and proposes
# the next semantic version according to SemVer 2.0.0 and Flowback release policy.
#
# INVARIANT: This script is STRICTLY READ-ONLY. It never tags, commits, or pushes.
# ==============================================================================

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${PROJECT_ROOT}"

echo "=================================================================="
echo " Flowback Semantic Version Proposal & Change Classifier (Read-Only)"
echo "=================================================================="

# 1. Resolve repository state
HEAD_SHA=$(git rev-parse HEAD)
HEAD_SHORT=$(git rev-parse --short HEAD)
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)

# 2. Resolve latest valid release tag (filtering out legacy v1.0.0 per pure pre-1.0 policy)
LATEST_TAG=$(git describe --tags --match "v0.*" --abbrev=0 2>/dev/null || echo "")

CANONICAL_VERSION=$(cat "$PROJECT_ROOT/VERSION" 2>/dev/null || echo "0.4.1")
CANONICAL_BUILD=$(cat "$PROJECT_ROOT/BUILD" 2>/dev/null || echo "2")

if [ -z "$LATEST_TAG" ]; then
    echo "Notice: No pre-1.0 Git release tag detected (ignoring legacy v1.0.0)."
    echo "Baseline established from canonical metadata: v$CANONICAL_VERSION"
    LATEST_TAG="v$CANONICAL_VERSION"
    COMMITS_SINCE=0
    COMMIT_RANGE=""
else
    COMMITS_SINCE=$(git rev-list --count "${LATEST_TAG}..HEAD")
    COMMIT_RANGE="${LATEST_TAG}..HEAD"
fi

echo "Current Repository State:"
echo "  Branch:               $CURRENT_BRANCH"
echo "  HEAD SHA:             $HEAD_SHA ($HEAD_SHORT)"
echo "  Latest Release Tag:   $LATEST_TAG"
echo "  Commits Ahead of Tag: $COMMITS_SINCE"
echo "  Canonical Metadata:   v$CANONICAL_VERSION (build $CANONICAL_BUILD)"
echo ""

if [ "$COMMITS_SINCE" -eq 0 ]; then
    echo "No unreleased commits detected. Repository HEAD matches latest release tag $LATEST_TAG."
    exit 0
fi

# 3. Classify commits in range
FEAT_COUNT=0
FIX_COUNT=0
DOCS_COUNT=0
TEST_COUNT=0
CHORE_COUNT=0
BREAKING_COUNT=0
OTHER_COUNT=0

while IFS= read -r line; do
    if echo "$line" | grep -qiE "BREAKING CHANGE|!:"; then
        BREAKING_COUNT=$((BREAKING_COUNT + 1))
    elif echo "$line" | grep -qE "^[a-f0-9]+ feat(\(.*\))?:"; then
        FEAT_COUNT=$((FEAT_COUNT + 1))
    elif echo "$line" | grep -qE "^[a-f0-9]+ fix(\(.*\))?:"; then
        FIX_COUNT=$((FIX_COUNT + 1))
    elif echo "$line" | grep -qE "^[a-f0-9]+ docs(\(.*\))?:"; then
        DOCS_COUNT=$((DOCS_COUNT + 1))
    elif echo "$line" | grep -qE "^[a-f0-9]+ test(\(.*\))?:"; then
        TEST_COUNT=$((TEST_COUNT + 1))
    elif echo "$line" | grep -qE "^[a-f0-9]+ (chore|build|ci)(\(.*\))?:"; then
        CHORE_COUNT=$((CHORE_COUNT + 1))
    else
        OTHER_COUNT=$((OTHER_COUNT + 1))
    fi
done < <(git log --oneline "$COMMIT_RANGE")

echo "Commit Change Classification (${COMMIT_RANGE}):"
echo "  Breaking Changes: $BREAKING_COUNT"
echo "  Features (feat):  $FEAT_COUNT"
echo "  Fixes (fix):      $FIX_COUNT"
echo "  Tests (test):     $TEST_COUNT"
echo "  Docs (docs):      $DOCS_COUNT"
echo "  Chore/Build/CI:   $CHORE_COUNT"
echo "  Other / Merges:   $OTHER_COUNT"
echo ""

# 4. Calculate proposed SemVer increment
# Strip leading 'v'
BASE_SEMVER="${LATEST_TAG#v}"
IFS='.' read -r MAJOR MINOR PATCH <<< "$BASE_SEMVER"

MAJOR=${MAJOR:-0}
MINOR=${MINOR:-0}
PATCH=${PATCH:-0}

INCREMENT_REASON=""
if [ "$BREAKING_COUNT" -gt 0 ]; then
    if [ "$MAJOR" -eq 0 ]; then
        # In pre-1.0, breaking changes increment MINOR
        PROPOSED_MAJOR=0
        PROPOSED_MINOR=$((MINOR + 1))
        PROPOSED_PATCH=0
        INCREMENT_REASON="Breaking change in pre-1.0 development increments MINOR"
    else
        PROPOSED_MAJOR=$((MAJOR + 1))
        PROPOSED_MINOR=0
        PROPOSED_PATCH=0
        INCREMENT_REASON="Breaking change detected: requires MAJOR version bump"
    fi
elif [ "$FEAT_COUNT" -gt 0 ]; then
    PROPOSED_MAJOR=$MAJOR
    PROPOSED_MINOR=$((MINOR + 1))
    PROPOSED_PATCH=0
    INCREMENT_REASON="New backwards-compatible features detected ($FEAT_COUNT feats): requires MINOR version bump"
elif [ "$FIX_COUNT" -gt 0 ]; then
    PROPOSED_MAJOR=$MAJOR
    PROPOSED_MINOR=$MINOR
    PROPOSED_PATCH=$((PATCH + 1))
    INCREMENT_REASON="Backwards-compatible bug fixes detected ($FIX_COUNT fixes): requires PATCH version bump"
else
    PROPOSED_MAJOR=$MAJOR
    PROPOSED_MINOR=$MINOR
    PROPOSED_PATCH=$((PATCH + 1))
    INCREMENT_REASON="Maintenance, documentation, or tooling updates: candidate PATCH increment"
fi

PROPOSED_VERSION="v${PROPOSED_MAJOR}.${PROPOSED_MINOR}.${PROPOSED_PATCH}"
NEXT_BUILD=$((CANONICAL_BUILD + 1))

echo "=================================================================="
echo " Proposed Release Recommendation:"
echo "  Candidate Version:   $PROPOSED_VERSION"
echo "  Candidate Commit:    $HEAD_SHORT ($HEAD_SHA)"
echo "  Recommended Build:   $NEXT_BUILD"
echo "  Rationale:           $INCREMENT_REASON"
echo "=================================================================="
echo ""
echo "Safety Notice:"
echo "  This tool is strictly read-only. No tags or commits have been created."
echo "  To create this release, review the diff, update canonical metadata,"
echo "  and seek explicit user authorization before tagging."
