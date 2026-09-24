#!/usr/bin/env bash
# Step 2: turn the Debian 13 guest from step 1 into a Proxmox VE 9 node.
# Run inside the VM, as root. It reboots once, into the Proxmox kernel;
# run it again afterwards and it carries on from there.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

HOSTNAME_NEW=${HOSTNAME_NEW:-nexcage-e2e}
IP=${IP:-192.168.3.80}
GW=${GW:-192.168.3.1}
NIC=${NIC:-eth0}
DISK=${DISK:-/dev/sda}

case "$(uname -r)" in
  *-pve) PHASE=2 ;;
  *)     PHASE=1 ;;
esac

if [ "$PHASE" = 1 ]; then
  echo "=== identity: cloud-init must not own it ==="
  # A Proxmox node keeps its configuration under /etc/pve/nodes/<hostname>, so
  # a clone cannot be renamed afterwards; and PVE owns
  # /etc/network/interfaces, so cloud-init must not rewrite the address.
  cat > /etc/cloud/cloud.cfg.d/99-nexcage.cfg <<'EOF'
network: {config: disabled}
preserve_hostname: true
manage_etc_hosts: false
EOF
  hostnamectl set-hostname "$HOSTNAME_NEW"
  cat > /etc/hosts <<EOF
127.0.0.1 localhost
$IP $HOSTNAME_NEW.local $HOSTNAME_NEW

::1 localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF

  echo "=== proxmox repository (trixie, no-subscription) ==="
  apt-get update -qq
  apt-get install -y -qq --no-install-recommends wget ca-certificates gnupg ifupdown2 bridge-utils >/dev/null
  wget -q https://enterprise.proxmox.com/debian/proxmox-archive-keyring-trixie.gpg \
    -O /usr/share/keyrings/proxmox-archive-keyring.gpg
  cat > /etc/apt/sources.list.d/proxmox.sources <<'EOF'
Types: deb
URIs: http://download.proxmox.com/debian/pve
Suites: trixie
Components: pve-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF
  apt-get update -qq

  echo "=== proxmox kernel ==="
  # The cloud image leaves grub-pc without an install device, and its
  # post-installation script then fails the whole apt run.
  echo "grub-pc grub-pc/install_devices multiselect $DISK" | debconf-set-selections
  apt-get install -y -qq proxmox-default-kernel >/dev/null

  echo "=== keep the interface name the cloud image boots with ==="
  # The cloud image passes net.ifnames=0, so its NIC is eth0 — but that
  # parameter lives in the Debian grub defaults, and installing the Proxmox
  # kernel rewrites grub.cfg without it. The NIC then comes back as ens18 on
  # the next boot, /etc/network/interfaces still names eth0, and vmbr0 has no
  # port: the node boots with an address and no connectivity. Pin it.
  if ! grep -q 'net.ifnames=0' /etc/default/grub; then
    sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"$/GRUB_CMDLINE_LINUX_DEFAULT="\1 net.ifnames=0 biosdevname=0"/' /etc/default/grub
    grep GRUB_CMDLINE_LINUX_DEFAULT /etc/default/grub
    update-grub >/dev/null 2>&1
  fi

  echo "=== the bridge PVE expects, and only ifupdown2 managing it ==="
  # The Debian cloud image configures the NIC through netplan and
  # systemd-networkd. Left enabled, it keeps the address on $NIC while
  # ifupdown2 puts the same address on vmbr0, and neither works.
  rm -f /etc/netplan/*.yaml
  systemctl mask systemd-networkd systemd-networkd.socket systemd-networkd-wait-online >/dev/null 2>&1 || true
  cat > /etc/network/interfaces <<EOF
auto lo
iface lo inet loopback

iface $NIC inet manual

auto vmbr0
iface vmbr0 inet static
	address $IP/24
	gateway $GW
	bridge-ports $NIC
	bridge-stp off
	bridge-fd 0
EOF
  rm -f /etc/resolv.conf
  printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' > /etc/resolv.conf

  echo "=== rebooting into the Proxmox kernel; run this script again after ==="
  systemd-run --on-active=3 --timer-property=AccuracySec=1s /sbin/reboot >/dev/null 2>&1
  exit 0
fi

echo "=== proxmox-ve, on kernel $(uname -r) ==="
echo "postfix postfix/main_mailer_type select Local only" | debconf-set-selections
echo "postfix postfix/mailname string $(hostname -f)" | debconf-set-selections
apt-get update -qq
apt-get install -y -qq proxmox-ve postfix open-iscsi chrony >/dev/null

# proxmox-ve adds the enterprise repository, which answers 401 without a
# subscription and breaks every later apt run.
for f in /etc/apt/sources.list.d/pve-enterprise.sources /etc/apt/sources.list.d/ceph.sources; do
  [ -f "$f" ] && ! grep -q '^Enabled: no' "$f" && printf 'Enabled: no\n' >> "$f"
done
apt-get update -qq

echo "=== drop the Debian kernel ==="
apt-get remove -y -qq os-prober linux-image-amd64 'linux-image-6.12*' >/dev/null 2>&1 || true
apt-get autoremove -y -qq >/dev/null 2>&1 || true
update-grub >/dev/null 2>&1

echo "=== what nexcage calls ==="
pveversion
for t in pct pvesh pvesm pveam; do printf '%-8s %s\n' "$t" "$(command -v $t || echo MISSING)"; done
echo "PVE_INSTALLED"
