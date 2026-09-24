#!/usr/bin/env bash
# Step 4: strip what belongs to this one machine, then power off so the VM can
# be converted to a template. Run inside the VM, as root.
#
# Afterwards, on the Proxmox host:
#   qm set <vmid> --delete cipassword
#   qm set <vmid> --name nexcage-pve-tpl-v0-1
#   qm template <vmid>
set -euo pipefail

echo "=== nothing from a test run left behind ==="
pct list
for id in $(pct list 2>/dev/null | awk 'NR>1 {print $1}'); do
  pct shutdown "$id" --timeout 30 --forceStop 1 >/dev/null 2>&1 || true
  pct destroy "$id" --purge 1 >/dev/null 2>&1 || true
done
rm -rf /var/lib/nexcage /run/nexcage
dpkg -r nexcage >/dev/null 2>&1 || true
rm -f /usr/bin/nexcage

echo "=== a registration belongs to one runner, not to an image ==="
RUNNER_DIR=/home/github-runner/actions-runner
if [ -e "$RUNNER_DIR/.runner" ]; then
  echo "remove the runner first: ./svc.sh stop && ./svc.sh uninstall && ./config.sh remove --token <removal token>" >&2
  exit 1
fi
rm -rf "$RUNNER_DIR/_work" "$RUNNER_DIR/_diag"

echo "=== caches, logs, cloud-init state ==="
apt-get clean
journalctl --rotate >/dev/null 2>&1 || true
journalctl --vacuum-time=1s >/dev/null 2>&1 || true
cloud-init clean --logs >/dev/null 2>&1 || true
rm -f /root/.bash_history /home/github-runner/.bash_history

echo "=== ssh host keys, so every clone gets its own ==="
# cloud-init generates them again on the first boot of a clone, which it sees
# as a new instance; this unit is the belt to that braces.
cat > /etc/systemd/system/regenerate-ssh-host-keys.service <<'EOF'
[Unit]
Description=Regenerate SSH host keys once, after this image is cloned
ConditionPathExists=!/etc/ssh/ssh_host_ed25519_key
Before=ssh.service

[Service]
Type=oneshot
ExecStart=/usr/bin/ssh-keygen -A
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
systemctl enable regenerate-ssh-host-keys.service >/dev/null 2>&1
rm -f /etc/ssh/ssh_host_*

echo "=== powering off ==="
systemd-run --on-active=2 --timer-property=AccuracySec=1s /sbin/poweroff >/dev/null 2>&1
echo "SEALED"
