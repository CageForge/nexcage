#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 <version> [artifact-dir]" >&2
  echo "Example: $0 0.6.0" >&2
  echo "Example: $0 0.6.0 /tmp/artifacts" >&2
  echo "" >&2
  echo "This script verifies SHA256 checksums and GPG signatures of release artifacts." >&2
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

VERSION="$1"
ARTIFACT_DIR="${2:-.}"

echo "Verifying artifacts for version $VERSION in $ARTIFACT_DIR"

# Check if artifacts exist
TAR_FILE="$ARTIFACT_DIR/nexcage-linux-x86_64-v$VERSION.tar.gz"
DEB_FILE="$ARTIFACT_DIR/nexcage_${VERSION}-1_amd64.deb"
BIN_FILE="$ARTIFACT_DIR/nexcage"

if [[ ! -f "$TAR_FILE" ]]; then
  echo "Error: $TAR_FILE not found" >&2
  exit 1
fi

echo "Found artifacts:"
ls -la "$ARTIFACT_DIR"/*v$VERSION* 2>/dev/null || true

# Verify SHA256 checksums
echo ""
echo "Verifying SHA256 checksums..."

if [[ -f "$TAR_FILE.sha256" ]]; then
  if sha256sum -c "$TAR_FILE.sha256"; then
    echo "✓ $TAR_FILE checksum verified"
  else
    echo "✗ $TAR_FILE checksum verification failed" >&2
    exit 1
  fi
else
  echo "⚠ $TAR_FILE.sha256 not found, skipping checksum verification"
fi

if [[ -f "$DEB_FILE" && -f "$DEB_FILE.sha256" ]]; then
  if sha256sum -c "$DEB_FILE.sha256"; then
    echo "✓ $DEB_FILE checksum verified"
  else
    echo "✗ $DEB_FILE checksum verification failed" >&2
    exit 1
  fi
fi

if [[ -f "$BIN_FILE.sha256" ]]; then
  if sha256sum -c "$BIN_FILE.sha256"; then
    echo "✓ $BIN_FILE checksum verified"
  else
    echo "✗ $BIN_FILE checksum verification failed" >&2
    exit 1
  fi
fi

# Verify GPG signatures
echo ""
echo "Verifying GPG signatures..."

for file in "$TAR_FILE" "$DEB_FILE" "$BIN_FILE"; do
  if [[ -f "$file" && -f "$file.asc" ]]; then
    if gpg --verify "$file.asc" "$file" 2>/dev/null; then
      echo "✓ $(basename "$file") signature verified"
    else
      echo "✗ $(basename "$file") signature verification failed" >&2
      exit 1
    fi
  elif [[ -f "$file" ]]; then
    echo "⚠ $(basename "$file") has no signature file"
  fi
done

echo ""
echo "✅ All verifications completed successfully!"
