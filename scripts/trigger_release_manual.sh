#!/bin/bash
# Manual script to trigger release workflow via GitHub API
# This can be used if automatic tag push doesn't trigger the workflow

set -euo pipefail

VERSION="${1:-v0.7.2}"
REPO="${GITHUB_REPOSITORY:-CageForge/nexcage}"

echo "Triggering release workflow for ${VERSION}..."

# Check if GITHUB_TOKEN is set
if [ -z "${GITHUB_TOKEN:-}" ]; then
    echo "⚠️  GITHUB_TOKEN not set. You need to:"
    echo "   1. Create a Personal Access Token (PAT) with 'workflow' scope"
    echo "   2. Export it: export GITHUB_TOKEN=your_token"
    echo "   3. Or run: gh auth login"
    exit 1
fi

# Use GitHub CLI if available, otherwise use curl
if command -v gh &> /dev/null; then
    echo "Using GitHub CLI to trigger workflow..."
    gh workflow run release.yml \
        --ref main \
        --field version="${VERSION}"
    echo "✅ Workflow triggered! Check: https://github.com/${REPO}/actions"
else
    echo "Using curl to trigger workflow via API..."
    curl -X POST \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer ${GITHUB_TOKEN}" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "https://api.github.com/repos/${REPO}/actions/workflows/release.yml/dispatches" \
        -d "{\"ref\":\"main\",\"inputs\":{\"version\":\"${VERSION}\"}}"
    echo "✅ Workflow triggered! Check: https://github.com/${REPO}/actions"
fi

echo ""
echo "To check workflow status:"
echo "  gh run list --workflow=release.yml"
echo "  or visit: https://github.com/${REPO}/actions/workflows/release.yml"

