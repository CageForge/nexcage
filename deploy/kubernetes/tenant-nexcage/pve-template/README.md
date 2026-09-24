# The Proxmox VE template the E2E node is cloned from

Four scripts that turn the Debian 13 cloud image into `nexcage-pve-tpl-v0-1`,
a Proxmox VE 9 guest that `../vm-e2e-node.yaml` clones through kubemox. Proxmox
VE 9 is Debian 13, so the cloud image is the right base and no installer ISO is
involved.

Run step 1 on the Proxmox host; steps 2 to 4 inside the VM, as root.

| Step | Where | What |
|---|---|---|
| `01-create-vm.sh` | Proxmox host | VM from the cloud image, 4 cores, 8 GB, 60 GB, serial console, cloud-init |
| `02-install-pve.sh` | in the VM | Proxmox repository, Proxmox kernel, `vmbr0`, then `proxmox-ve`. Reboots once — run it again after |
| `03-prepare-runner-host.sh` | in the VM | What `proxmox_e2e.yml` needs: its packages, the `vmbr50` bridge, an LXC template, the runner user, and the runner software **unregistered** |
| `04-seal-template.sh` | in the VM | Removes everything belonging to this one machine, then powers off |

Then, on the host:

```bash
qm set 119 --delete cipassword
qm set 119 --name nexcage-pve-tpl-v0-1
qm template 119
```

## Why it is built this way

**The hostname is fixed.** A Proxmox node keeps its configuration under
`/etc/pve/nodes/<hostname>`, so a clone cannot be renamed afterwards. The image
sets `nexcage-e2e` and turns off cloud-init's hostname module, and the address
lives in `/etc/network/interfaces` because PVE owns that file. One node per
template, therefore; a second concurrent node needs its own.

**The interface name is pinned.** The cloud image boots with `net.ifnames=0`,
so its NIC is `eth0` — but that parameter is in the Debian grub defaults, and
installing the Proxmox kernel rewrites `grub.cfg` without it. Left alone, the
NIC comes back as `ens18` on the next boot while `/etc/network/interfaces`
still says `eth0`; `vmbr0` then holds the address with no port, and the node
boots with no connectivity and no ssh. Step 2 puts `net.ifnames=0` back into
`/etc/default/grub`.

**Only ifupdown2 manages the network.** The cloud image configures the NIC
through netplan and systemd-networkd. Left enabled, it keeps the address on the
NIC while ifupdown2 puts the same address on `vmbr0`, and neither works. Step 2
removes the netplan configuration and masks systemd-networkd.

**grub-pc needs an install device.** The cloud image leaves it unset, and its
post-installation script then fails the whole `apt` run when the Proxmox kernel
is installed. Step 2 answers it with `debconf-set-selections`.

**The enterprise repository is disabled.** `proxmox-ve` adds it, and it answers
401 without a subscription, which breaks every later `apt` run.

**The runner is not in the image.** A registration belongs to one machine.
Register it on the node kubemox created, with
[`scripts/register_e2e_runner.sh`](../../../../scripts/register_e2e_runner.sh).

## Known gap in the current template

`nexcage-pve-tpl-v0-1` was sealed before the `net.ifnames` pin above was added
to step 2, so a node cloned from it comes up with the address on `vmbr0` and
`ens18` unattached. Fix it once on the new node, over the serial console
(`socat - UNIX-CONNECT:/var/run/qemu-server/<vmid>.serial0` on the host):

```bash
NIC=$(ip -o link show | awk -F': ' '{print $2}' | grep -vE '^(lo|vmbr|veth|fw|bond|dummy)' | head -1)
sed -i "s/\beth0\b/$NIC/g" /etc/network/interfaces && ifreload -a
```

Rebuilding the template with the current scripts removes the need for it.
