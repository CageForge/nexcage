#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"/../.. && pwd)"
cd "$ROOT_DIR"

VERSION=$(tr -d '\n\r' < VERSION)
ARCH=amd64
BIN_PATH="zig-out/bin/nexcage"

echo "Building release binary..."
zig build -Doptimize=ReleaseSafe

if [[ ! -f "$BIN_PATH" ]]; then
  echo "Binary not found at $BIN_PATH" >&2
  exit 1
fi

OUT_DIR="$ROOT_DIR/dist"
mkdir -p "$OUT_DIR"

echo "Creating tar.gz artifact..."
TAR_NAME="nexcage-linux-x86_64-v$VERSION.tar.gz"
tar -C "$ROOT_DIR/zig-out/bin" -czf "$OUT_DIR/$TAR_NAME" nexcage

echo "Building Debian package..."
export DEBEMAIL="ci@cageforge.org"
export DEBFULLNAME="CI"

# Update debian changelog with current version if needed
if command -v dch >/dev/null 2>&1; then
  dch --create --package nexcage --newversion "$VERSION-1" --distribution unstable "Automated release $VERSION" || true
fi

sudo apt-get update >/dev/null
sudo apt-get install -y build-essential debhelper devscripts >/dev/null

dpkg-buildpackage -us -uc -b

DEB_NAME="nexcage_${VERSION}-1_${ARCH}.deb"
if [[ -f "$ROOT_DIR/../$DEB_NAME" ]]; then
  mv "$ROOT_DIR/../$DEB_NAME" "$OUT_DIR/"
else
  echo "Debian package not found, expected ../$DEB_NAME" >&2
  exit 1
fi

echo "Artifacts ready in $OUT_DIR:"
ls -la "$OUT_DIR"

echo "Generating SHA256 checksums..."
pushd "$OUT_DIR" >/dev/null
sha256sum nexcage-linux-x86_64-v$VERSION.tar.gz > nexcage-linux-x86_64-v$VERSION.tar.gz.sha256
if [[ -f "nexcage_${VERSION}-1_${ARCH}.deb" ]]; then
  sha256sum nexcage_${VERSION}-1_${ARCH}.deb > nexcage_${VERSION}-1_${ARCH}.deb.sha256
fi
sha256sum ../zig-out/bin/nexcage > nexcage.sha256 || true
popd >/dev/null

if [[ -n "${GPG_SIGN:-}" ]]; then
  echo "Signing artifacts with GPG..."
  if [[ -z "${GPG_PRIVATE_KEY:-}" || -z "${GPG_PASSPHRASE:-}" ]]; then
    echo "GPG_SIGN is set but GPG_PRIVATE_KEY/GPG_PASSPHRASE not provided" >&2
    exit 1
  fi
  echo "$GPG_PRIVATE_KEY" | gpg --batch --import
  for f in "$OUT_DIR"/*.{tar.gz,deb,sha256} "$ROOT_DIR/zig-out/bin/nexcage"; do
    [[ -f "$f" ]] || continue
    gpg --batch --yes --pinentry-mode loopback --passphrase "$GPG_PASSPHRASE" --armor --output "$f.asc" --detach-sign "$f"
  done
  echo "GPG signatures generated (.asc)"
fi


