#!/usr/bin/env bash
set -euo pipefail

# E2E for crun ABI driver via nexcage CLI routing
# Requirements:
#  - Prepared OCI bundle at /var/lib/nexcage/bundles/<name>/config.json

NAME=${NAME:-e2e-crun-abi}
BUNDLE_DIR=${BUNDLE_DIR:-/var/lib/nexcage/bundles/$NAME}

echo "[e2e] crun ABI E2E start: $NAME"

if [[ ! -f "$BUNDLE_DIR/config.json" ]]; then
  echo "[e2e] missing bundle: $BUNDLE_DIR/config.json" >&2
  exit 2
fi

set -x
./zig-out/bin/nexcage create --runtime crun --name "$NAME" "$NAME" || true
./zig-out/bin/nexcage start --runtime crun "$NAME" || true
./zig-out/bin/nexcage stop --runtime crun "$NAME" || true
./zig-out/bin/nexcage delete --runtime crun "$NAME" || true
set +x

echo "[e2e] done"

