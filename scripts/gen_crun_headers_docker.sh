#!/usr/bin/env bash
set -euo pipefail

# Generate config.h and git-version.h for vendored crun inside Docker
#
# It runs scripts/gen_crun_headers_local.sh in the container, so the release
# it fetches and the sha256 that tarball has to have are decided in one place.
# This used to download and configure the tarball itself, unchecked, and fall
# back to crun's latest release when deps/crun/.upstream_tag was missing.

SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
DEPS_DIR="$(cd "$(dirname "$0")/.." && pwd)/deps/crun"
TAG=""
IMAGE="ubuntu:24.04"

usage() { echo "Usage: $0 [--tag vX.Y] [--image ubuntu:24.04]"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag) TAG="$2"; shift 2;;
    --image) IMAGE="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1"; usage; exit 1;;
  esac
done

mkdir -p "$DEPS_DIR"

# The tag reaches the container as a variable, not as script text.
docker run --rm -t \
  -v "$SCRIPTS_DIR":/src/scripts:ro \
  -v "$DEPS_DIR":/src/deps/crun \
  -e TAG="$TAG" \
  -e DEBIAN_FRONTEND=noninteractive \
  "$IMAGE" bash -lc 'set -e
    apt-get update -y >/dev/null && apt-get install -y >/dev/null \
      build-essential autoconf automake libtool pkg-config python3 \
      libjson-c-dev libcap-dev libseccomp-dev libsystemd-dev curl ca-certificates >/dev/null
    bash /src/scripts/gen_crun_headers_local.sh ${TAG:+--tag "$TAG"}'

echo "[docker-headers] Wrote $DEPS_DIR/config.h and git-version.h"
