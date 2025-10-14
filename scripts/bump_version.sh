#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"
VERSION_FILE="$ROOT_DIR/VERSION"

usage() {
  echo "Usage: $0 <new_version>" >&2
  echo "Example: $0 0.6.0" >&2
}

if [[ $# -ne 1 ]]; then
  usage
  exit 1
fi

NEW_VERSION="$1"

if [[ ! "$NEW_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Error: version must be in semver format MAJOR.MINOR.PATCH" >&2
  exit 1
fi

echo "$NEW_VERSION" > "$VERSION_FILE"

# Update docs references if needed (example patterns)
sed -i "s/v[0-9]\+\.[0-9]\+\.[0-9]\+/v$NEW_VERSION/g" "$ROOT_DIR"/docs/**/*.md || true
sed -i "s/Proxmox VM support is planned for v[0-9]\+\.[0-9]\+\.[0-9]\+/Proxmox VM support is planned for v$NEW_VERSION/g" "$ROOT_DIR"/docs/**/*.md || true

echo "Version updated to $NEW_VERSION"
echo "Don't forget to:"
echo "  - Commit: git commit -am \"chore(release): bump version to $NEW_VERSION\""
echo "  - Tag:    git tag v$NEW_VERSION && git push --tags"
echo "  - Build:  zig build"


