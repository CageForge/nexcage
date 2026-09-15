# Installing nexcage

nexcage runs on the Proxmox VE host (8.x or 9.x, amd64) as root. It needs
`pct`, `pvesh` and `pveversion`, which Proxmox VE provides.

## From a release

Each GitHub release carries the binary `nexcage-<version>-amd64`, the package
`nexcage-<version>-amd64.deb`, SBOMs and `checksums.txt`.

### .deb

```bash
VERSION=0.8.0
wget https://github.com/CageForge/nexcage/releases/download/v$VERSION/nexcage-$VERSION-amd64.deb
wget https://github.com/CageForge/nexcage/releases/download/v$VERSION/checksums.txt
sha256sum --ignore-missing -c checksums.txt
apt install ./nexcage-$VERSION-amd64.deb
```

The package installs `/usr/bin/nexcage`, a man page, bash completion and an
example configuration at `/usr/share/doc/nexcage/examples/config.json`.

### Binary

```bash
VERSION=0.8.0
wget https://github.com/CageForge/nexcage/releases/download/v$VERSION/nexcage-$VERSION-amd64
wget https://github.com/CageForge/nexcage/releases/download/v$VERSION/checksums.txt
sha256sum --ignore-missing -c checksums.txt
install -m 0755 nexcage-$VERSION-amd64 /usr/local/bin/nexcage
```

## From source

```bash
git clone https://github.com/CageForge/nexcage.git
cd nexcage
zig build -Doptimize=ReleaseSafe          # Zig 0.15.1
install -m 0755 zig-out/bin/nexcage /usr/local/bin/nexcage
```

To build a `.deb` yourself: `bash scripts/build_deb_local.sh` (needs
`dpkg-deb`), which writes `dist/nexcage-<version>-amd64.deb`.

## Configure

```bash
mkdir -p /etc/nexcage
cp /usr/share/doc/nexcage/examples/config.json /etc/nexcage/config.json   # .deb install
# or: cp packaging/config/config.json /etc/nexcage/config.json            # source tree
```

Set at least `proxmox.storage` to a storage that holds container volumes
(`pvesm status` lists them) and `network.bridge` to your bridge. The keys are
described in the README.

You also need a container template, for example:

```bash
pveam update
pveam available --section system
pveam download local debian-12-standard_12.7-1_amd64.tar.zst
```

## Verify

```bash
nexcage version
nexcage list
nexcage create --name smoke-1 local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst
nexcage start smoke-1 && nexcage state smoke-1
nexcage stop smoke-1 && nexcage delete smoke-1
```

## Remove

```bash
apt remove nexcage              # .deb install
rm /usr/local/bin/nexcage       # binary install
rm -rf /etc/nexcage /run/nexcage
```

Containers created with nexcage are ordinary Proxmox VE containers and are not
touched when nexcage is removed.
