#!/usr/bin/env bash
# Step 3: make the Proxmox node usable by proxmox_e2e.yml, and unpack the
# Actions runner without registering it — a registration belongs to one
# machine, so it must not be baked into a template.
#
# Run inside the VM, as root, after 02-install-pve.sh reports PVE_INSTALLED.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

RUNNER_VERSION=${RUNNER_VERSION:-2.337.0}
RUNNER_USER=${RUNNER_USER:-github-runner}
E2E_BRIDGE=${E2E_BRIDGE:-vmbr50}
E2E_BRIDGE_ADDR=${E2E_BRIDGE_ADDR:-10.60.0.1/24}
TEMPLATE=${TEMPLATE:-debian-13-standard_13.6-1_amd64.tar.zst}

# The Debian cloud image upgrades packages on first boot, and cloud-init holds
# the dpkg lock while it does — including after 04-seal-template.sh clears its
# state, which makes the next boot a first boot again. Without this wait, apt
# dies with "Could not get lock /var/lib/dpkg/lock-frontend".
if command -v cloud-init >/dev/null 2>&1; then
  echo "=== waiting for cloud-init to let go of apt ==="
  cloud-init status --wait >/dev/null 2>&1 || true
fi

echo "=== packages the workflow needs ==="
apt-get update -qq
apt-get install -y -qq --no-install-recommends \
  curl git tar xz-utils zstd python3 jq ca-certificates sudo bridge-utils >/dev/null
for t in curl git tar xz zstd python3 jq unshare pct pvesh; do
  printf '%-10s %s\n' "$t" "$(command -v $t || echo MISSING)"
done

echo "=== $E2E_BRIDGE, which proxmox_e2e.yml looks for ==="
# The E2E job refuses to run if its bridge is missing. It has no ports: the
# containers it creates only have to come up, not reach anything.
if ! grep -q "$E2E_BRIDGE" /etc/network/interfaces; then
  cat >> /etc/network/interfaces <<EOF

auto $E2E_BRIDGE
iface $E2E_BRIDGE inet static
	address $E2E_BRIDGE_ADDR
	bridge-ports none
	bridge-stp off
	bridge-fd 0
EOF
  ifreload -a 2>&1 | tail -2 || true
fi
ip -br -4 addr | grep vmbr

echo "=== an LXC template to create containers from ==="
pveam update >/dev/null 2>&1 || true
pveam list local | grep -q "$TEMPLATE" || pveam download local "$TEMPLATE" 2>&1 | tail -1
pveam list local

echo "=== runner user ==="
# nexcage runs pct and pvesh and writes /run/nexcage, so the E2E job needs
# root; the workflow calls it through sudo -n when it is not already root.
id "$RUNNER_USER" >/dev/null 2>&1 || useradd -m -s /bin/bash "$RUNNER_USER"
echo "$RUNNER_USER ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/99-github-runner
chmod 0440 /etc/sudoers.d/99-github-runner

echo "=== runner software, unconfigured ==="
DIR=/home/$RUNNER_USER/actions-runner
if [ ! -x "$DIR/config.sh" ]; then
  install -d -o "$RUNNER_USER" -g "$RUNNER_USER" "$DIR"
  su - "$RUNNER_USER" -c "curl -fsSL -o /tmp/runner.tar.gz \
    https://github.com/actions/runner/releases/download/v$RUNNER_VERSION/actions-runner-linux-x64-$RUNNER_VERSION.tar.gz \
    && tar -xzf /tmp/runner.tar.gz -C '$DIR' \
    && mv /tmp/runner.tar.gz '$DIR/actions-runner-linux-x64-$RUNNER_VERSION.tar.gz'"
fi
ls "$DIR/config.sh"
echo "RUNNER_HOST_PREPARED"
