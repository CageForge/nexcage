#!/usr/bin/env bash
set -euo pipefail

PVE_HOST="mgr.cp.if.ua"
PVE_USER="root"
BIN_LOCAL="zig-out/bin/nexcage"
BIN_REMOTE="/usr/local/bin/nexcage"
CONF_LOCAL="config.json"
CONF_REMOTE="/etc/nexcage/config.json"
BUNDLES_DIR="/var/lib/nexcage/bundles"
LOG_DIR="/var/log/nexcage"

log() { echo "[e2e] $*"; }

log "Building binary..."
zig build >/dev/null

log "Copying binary and config to PVE..."
ssh -o StrictHostKeyChecking=no ${PVE_USER}@${PVE_HOST} 'mkdir -p /etc/nexcage /var/lib/nexcage /var/run/nexcage /var/log/nexcage'
scp -o StrictHostKeyChecking=no "$BIN_LOCAL" ${PVE_USER}@${PVE_HOST}:"$BIN_REMOTE"
scp -o StrictHostKeyChecking=no "$CONF_LOCAL" ${PVE_USER}@${PVE_HOST}:"$CONF_REMOTE"
ssh -o StrictHostKeyChecking=no ${PVE_USER}@${PVE_HOST} 'chmod +x /usr/local/bin/nexcage'

log "Environment checks..."
ssh -o StrictHostKeyChecking=no ${PVE_USER}@${PVE_HOST} 'export PATH=/usr/sbin:/usr/bin:/bin:$PATH; if [ -x /usr/sbin/pct ]; then /usr/sbin/pct help | head -n 1; else echo "pct not found"; fi'
ssh -o StrictHostKeyChecking=no ${PVE_USER}@${PVE_HOST} 'export PATH=/usr/sbin:/usr/bin:/bin:$PATH; command -v crun >/dev/null 2>&1 || echo "crun not found"; command -v runc >/dev/null 2>&1 || echo "runc not found"'

# LXC flow (should route to LXC by routing)
LXC_NAME="e2e-lxc-$(date +%s)"
log "LXC flow for \"$LXC_NAME\""
ssh -o StrictHostKeyChecking=no ${PVE_USER}@${PVE_HOST} "PROXMOX_LXCRI_LOG=debug $BIN_REMOTE list || true"
ssh -o StrictHostKeyChecking=no ${PVE_USER}@${PVE_HOST} "$BIN_REMOTE create --name $LXC_NAME ubuntu-20.04 || true"
ssh -o StrictHostKeyChecking=no ${PVE_USER}@${PVE_HOST} "$BIN_REMOTE start --name $LXC_NAME || true"
ssh -o StrictHostKeyChecking=no ${PVE_USER}@${PVE_HOST} "$BIN_REMOTE exec --name $LXC_NAME -- echo lxc-ok || true"
ssh -o StrictHostKeyChecking=no ${PVE_USER}@${PVE_HOST} "$BIN_REMOTE state --name $LXC_NAME || true"
ssh -o StrictHostKeyChecking=no ${PVE_USER}@${PVE_HOST} "$BIN_REMOTE stop --name $LXC_NAME || true"
ssh -o StrictHostKeyChecking=no ${PVE_USER}@${PVE_HOST} "$BIN_REMOTE delete --name $LXC_NAME || true"

# OCI flow (should route to crun by routing pattern)
OCI_NAME="kube-ovn-e2e-$(date +%s)"
BUNDLE_PATH="$BUNDLES_DIR/$OCI_NAME"
log "OCI flow for \"$OCI_NAME\" (bundle: $BUNDLE_PATH)"
ssh -o StrictHostKeyChecking=no ${PVE_USER}@${PVE_HOST} "mkdir -p $BUNDLE_PATH/rootfs; test -f $BUNDLE_PATH/config.json || echo '{\"ociVersion\":\"1.0.2\",\"process\":{\"args\":[\"/bin/sh\"]},\"root\":{\"path\":\"rootfs\"}}' > $BUNDLE_PATH/config.json"
ssh -o StrictHostKeyChecking=no ${PVE_USER}@${PVE_HOST} "$BIN_REMOTE create --name $OCI_NAME $BUNDLE_PATH || true"
ssh -o StrictHostKeyChecking=no ${PVE_USER}@${PVE_HOST} "$BIN_REMOTE start --name $OCI_NAME || true"
ssh -o StrictHostKeyChecking=no ${PVE_USER}@${PVE_HOST} "$BIN_REMOTE exec --name $OCI_NAME -- echo oci-ok || true"
ssh -o StrictHostKeyChecking=no ${PVE_USER}@${PVE_HOST} "$BIN_REMOTE state --name $OCI_NAME || true"
ssh -o StrictHostKeyChecking=no ${PVE_USER}@${PVE_HOST} "$BIN_REMOTE stop --name $OCI_NAME || true"
ssh -o StrictHostKeyChecking=no ${PVE_USER}@${PVE_HOST} "$BIN_REMOTE delete --name $OCI_NAME || true"

log "Collecting logs..."
ssh -o StrictHostKeyChecking=no ${PVE_USER}@${PVE_HOST} "tail -n 200 $LOG_DIR/runtime.log || true"

log "E2E tests finished"
