#!/usr/bin/env bash
set -euo pipefail

# Generate config.h and git-version.h for vendored crun using local toolchain
# Requires: autoconf/automake/libtool, pkg-config, gcc, make, and dev libs: libyajl-dev, libcap-dev, libseccomp-dev, libsystemd-dev

OWNER_REPO="containers/crun"
DEPS_DIR="$(cd "$(dirname "$0")/.." && pwd)/deps/crun"
TMP_DIR="/tmp/crun_headers.$$"

TAG=""

usage() {
  echo "Usage: $0 [--tag vX.Y]";
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag) TAG="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1"; usage; exit 1;;
  esac
done

if [[ -z "$TAG" ]]; then
  if [[ -f "$DEPS_DIR/.upstream_tag" ]]; then
    TAG=$(head -n1 "$DEPS_DIR/.upstream_tag")
  else
    TAG=$(curl -fsSL "https://api.github.com/repos/$OWNER_REPO/releases/latest" | sed -n 's/.*"tag_name"\s*:\s*"\([^"]*\)".*/\1/p')
  fi
fi

mkdir -p "$TMP_DIR"
trap 'rm -rf "$TMP_DIR"' EXIT

TARBALL_URL="https://github.com/$OWNER_REPO/releases/download/$TAG/crun-$TAG.tar.gz"
echo "[local-headers] Downloading $TARBALL_URL"
curl -fsSL "$TARBALL_URL" -o "$TMP_DIR/crun.tar.gz"
tar -C "$TMP_DIR" -xzf "$TMP_DIR/crun.tar.gz"
SRC="$TMP_DIR/crun-$TAG"

pushd "$SRC" >/dev/null
echo "[local-headers] Configuring..."
if [[ -x ./configure ]]; then
  ./configure >/dev/null
else
  ./autogen.sh >/dev/null
  ./configure >/dev/null
fi
popd >/dev/null

mkdir -p "$DEPS_DIR"
cp -f "$SRC/config.h" "$DEPS_DIR/config.h"
echo "#define GIT_VERSION \"$TAG\"" > "$DEPS_DIR/git-version.h"
echo "[local-headers] Wrote $DEPS_DIR/config.h and git-version.h"

