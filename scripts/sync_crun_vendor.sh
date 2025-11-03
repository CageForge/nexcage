#!/usr/bin/env bash
set -euo pipefail

# Sync selected upstream crun sources/headers into deps/crun
# Usage:
#   scripts/sync_crun_vendor.sh --latest [--check-only]
#   scripts/sync_crun_vendor.sh --version v1.17.1
#   scripts/sync_crun_vendor.sh --force --version v1.17.1
# Exits with non‑zero when --check-only finds newer version available.

OWNER_REPO="containers/crun"
DEPS_DIR="$(cd "$(dirname "$0")/.." && pwd)/deps/crun"
TMP_DIR="/tmp/crun_sync.$$"
MARKER_FILE="$DEPS_DIR/.upstream_tag"

VERSION=""
CHECK_ONLY=false
FORCE=false
VERBOSE=false

log() { echo "[sync-crun] $*"; }
err() { echo "[sync-crun][ERROR] $*" >&2; }
dbg() { [[ "$VERBOSE" == true ]] && echo "[sync-crun][DEBUG] $*" >&2 || true; }

usage() {
  cat <<EOF
Sync upstream crun into deps/crun

Options:
  --latest              Use latest release tag from GitHub
  --version TAG         Use explicit tag (e.g. v1.17.1)
  --check-only          Only check for updates; exit 2 if update available
  --force               Overwrite even if same version
  --verbose             Verbose logging
  -h|--help             Show help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --latest) VERSION="latest"; shift ;;
    --version) VERSION="$2"; shift 2 ;;
    --check-only) CHECK_ONLY=true; shift ;;
    --force) FORCE=true; shift ;;
    --verbose) VERBOSE=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) err "Unknown arg: $1"; usage; exit 1 ;;
  esac
done

if [[ -z "$VERSION" ]]; then
  err "Specify --latest or --version <tag>"; exit 1
fi

current_tag=""
if [[ -f "$MARKER_FILE" ]]; then
  current_tag=$(head -n1 "$MARKER_FILE" | tr -d '\n')
fi

if [[ "$VERSION" == "latest" ]]; then
  # Query latest tag
  latest_json=$(curl -fsSL "https://api.github.com/repos/$OWNER_REPO/releases/latest")
  VERSION=$(printf '%s' "$latest_json" | sed -n 's/.*"tag_name"\s*:\s*"\([^"]*\)".*/\1/p')
  if [[ -z "$VERSION" ]]; then
    err "Failed to determine latest tag"; exit 1
  fi
fi

log "Requested tag: $VERSION (current: ${current_tag:-none})"

if [[ "$CHECK_ONLY" == true ]]; then
  if [[ "$VERSION" != "$current_tag" ]]; then
    log "Update available: $current_tag -> $VERSION"; exit 2
  else
    log "Already up to date ($current_tag)"; exit 0
  fi
fi

if [[ "$VERSION" == "$current_tag" && "$FORCE" != true ]]; then
  log "Already at $VERSION; use --force to re-sync"; exit 0
fi

trap 'rm -rf "$TMP_DIR"' EXIT
mkdir -p "$TMP_DIR"

asset_url="https://github.com/$OWNER_REPO/releases/download/$VERSION/crun-$VERSION.tar.gz"
tarball="$TMP_DIR/crun-$VERSION.tar.gz"
log "Downloading $asset_url"
curl -fsSL "$asset_url" -o "$tarball"

log "Extracting..."
tar -C "$TMP_DIR" -xzf "$tarball"
SRC_ROOT="$TMP_DIR/crun-$VERSION"

[[ -d "$SRC_ROOT/src" ]] || { err "Invalid archive layout"; exit 1; }

log "Syncing selected directories into deps/crun"
mkdir -p "$DEPS_DIR"

# Keep only what build includes: src/, src/libcrun, libocispec/src, LICENSE
rsync -a --delete "$SRC_ROOT/src/" "$DEPS_DIR/src/"
mkdir -p "$DEPS_DIR/libocispec"
rsync -a --delete "$SRC_ROOT/libocispec/src/" "$DEPS_DIR/libocispec/src/"
cp -f "$SRC_ROOT/LICENSE" "$DEPS_DIR/" || true

# Marker with upstream tag and date
echo "$VERSION" > "$MARKER_FILE"
date -u +%Y-%m-%dT%H:%M:%SZ >> "$MARKER_FILE"

log "Synced deps/crun to $VERSION"

