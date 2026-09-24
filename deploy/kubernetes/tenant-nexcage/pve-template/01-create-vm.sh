#!/usr/bin/env bash
# Step 1 of building the Proxmox VE template the E2E node is cloned from.
# Creates a VM on the Proxmox host from the Debian 13 cloud image, with a
# serial console — the network is reconfigured in step 2 and ssh can be lost.
#
# Run on the Proxmox host (prox-home).
set -euo pipefail

VMID=${VMID:-119}
NAME=${NAME:-nexcage-pve-build}
STORAGE=${STORAGE:-main-pool}
IP=${IP:-192.168.3.80}
GW=${GW:-192.168.3.1}
IMG=${IMG:-/var/lib/vz/template/iso/debian-13-generic-amd64.qcow2}
PUBKEY=${PUBKEY:-/root/.nexcage-e2e.pub}

[ -f "$IMG" ] || { echo "no cloud image at $IMG" >&2; exit 1; }
[ -f "$PUBKEY" ] || { echo "no public key at $PUBKEY" >&2; exit 1; }

if qm config "$VMID" >/dev/null 2>&1; then
  echo "VM $VMID already exists"; exit 0
fi

qm create "$VMID" \
  --name "$NAME" \
  --memory 8192 --cores 4 --sockets 1 --cpu host \
  --net0 virtio,bridge=vmbr0 \
  --scsihw virtio-scsi-single \
  --serial0 socket --vga serial0 \
  --ostype l26 --agent enabled=1 \
  --onboot 1

qm importdisk "$VMID" "$IMG" "$STORAGE" >/dev/null
qm set "$VMID" --scsi0 "$STORAGE:vm-$VMID-disk-0,discard=on,ssd=1" >/dev/null
qm disk resize "$VMID" scsi0 60G
qm set "$VMID" --ide2 "$STORAGE:cloudinit" --boot order=scsi0 >/dev/null
qm set "$VMID" \
  --ciuser root --sshkeys "$PUBKEY" \
  --ipconfig0 "ip=$IP/24,gw=$GW" \
  --nameserver 1.1.1.1 >/dev/null

qm start "$VMID"
echo "started $VMID ($NAME) at $IP; wait for ssh, then run 02-install-pve.sh on it"
