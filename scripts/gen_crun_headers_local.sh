#!/usr/bin/env bash
set -euo pipefail

# Generate config.h and git-version.h for vendored crun using local toolchain
# Requires: autoconf/automake/libtool, pkg-config, gcc, make, and dev libs: libjson-c-dev, libcap-dev, libseccomp-dev, libsystemd-dev
#
# config.h decides what libcrun is compiled with (seccomp, capabilities,
# systemd), and it comes from running the release tarball's ./configure -- as
# root, in the build of the release binary. So the release is the one
# deps/crun/.upstream_tag names, never whatever crun's latest release is that
# day, and the tarball must have the sha256 pinned below before anything in it
# is unpacked or run.

OWNER_REPO="containers/crun"
DEPS_DIR="$(cd "$(dirname "$0")/.." && pwd)/deps/crun"

TAG=""

# sha256 of crun-<tag>.tar.gz as containers/crun publishes it in the release's
# CHECKSUMS file. Moving the vendored crun to another release adds its line.
tarball_sha256() {
  case "$1" in
    1.30.1) echo 99d036d95113552b6df66c7c879432835504bf0e525fc0372745071df129527b ;;
    *) return 1 ;;
  esac
}

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
    echo "[local-headers] $DEPS_DIR/.upstream_tag is missing, so the crun release the pin follows is unknown; pass --tag" >&2
    exit 1
  fi
fi
if ! SHA256=$(tarball_sha256 "$TAG"); then
  echo "[local-headers] no sha256 is pinned for crun-$TAG.tar.gz; add it to tarball_sha256 in $0" >&2
  exit 1
fi

# A directory of its own, made here: a fixed name such as /tmp/crun_headers.$$
# can be created first by another local user, who then owns what is unpacked
# and run from it.
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/crun_headers.XXXXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT

TARBALL_URL="https://github.com/$OWNER_REPO/releases/download/$TAG/crun-$TAG.tar.gz"
echo "[local-headers] Downloading $TARBALL_URL"
curl -fsSL "$TARBALL_URL" -o "$TMP_DIR/crun.tar.gz"
if ! echo "$SHA256  $TMP_DIR/crun.tar.gz" | sha256sum -c - >/dev/null; then
  echo "[local-headers] crun-$TAG.tar.gz does not have the pinned sha256 $SHA256; not using it" >&2
  exit 1
fi
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

