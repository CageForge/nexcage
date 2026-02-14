#!/usr/bin/env bash
set -euo pipefail

# Generate config.h and git-version.h for vendored crun inside Docker

OWNER_REPO="containers/crun"
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

if [[ -z "$TAG" ]]; then
  if [[ -f "$DEPS_DIR/.upstream_tag" ]]; then
    TAG=$(head -n1 "$DEPS_DIR/.upstream_tag")
  else
    TAG=$(curl -fsSL "https://api.github.com/repos/$OWNER_REPO/releases/latest" | sed -n 's/.*"tag_name"\s*:\s*"\([^"]*\)".*/\1/p')
  fi
fi

mkdir -p "$DEPS_DIR"

docker run --rm -t \
  -v "$DEPS_DIR":/out \
  "$IMAGE" bash -lc "set -e; \
    apt-get update -y >/dev/null && apt-get install -y >/dev/null \
      build-essential autoconf automake libtool pkg-config \
      libyajl-dev libcap-dev libseccomp-dev libsystemd-dev curl ca-certificates >/dev/null; \
    curl -fsSL https://github.com/$OWNER_REPO/releases/download/$TAG/crun-$TAG.tar.gz -o /tmp/crun.tar.gz; \
    mkdir -p /tmp/crun && tar -C /tmp/crun -xzf /tmp/crun.tar.gz; \
    cd /tmp/crun/crun-$TAG; \
    if [[ -x ./configure ]]; then ./configure >/dev/null; else ./autogen.sh >/dev/null && ./configure >/dev/null; fi; \
    cp -f config.h /out/config.h; \
    echo \"#define GIT_VERSION \\\"$TAG\\\"\" > /out/git-version.h; \
    echo done"

echo "[docker-headers] Wrote $DEPS_DIR/config.h and git-version.h"

