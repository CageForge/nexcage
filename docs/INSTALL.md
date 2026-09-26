# Installing nexcage

nexcage runs on the Proxmox VE host (8.x or 9.x, amd64) as root. It needs
`pct`, `pvesh` and `pveversion`, which Proxmox VE provides.

## From a release

Each GitHub release carries the binary `nexcage-<version>-amd64`, the package
`nexcage-<version>-amd64.deb`, SBOMs and `checksums.txt`. **From 0.11.2** there
is a second binary, `nexcage-<version>-amd64-crun`, with the OCI runtime backend
built in; for earlier versions that build has to be made from source.

**Which binary you want.** The plain one manages LXC containers on Proxmox VE
and is what most uses need. The `-crun` one adds the backend a container engine
drives: it is the binary to install when containerd, CRI-O or a kubelet is to
run containers on nexcage. Everything the plain binary does, it does too.

### .deb

```bash
VERSION=0.11.1
wget https://github.com/CageForge/nexcage/releases/download/v$VERSION/nexcage-$VERSION-amd64.deb
wget https://github.com/CageForge/nexcage/releases/download/v$VERSION/checksums.txt
sha256sum --ignore-missing -c checksums.txt
apt install ./nexcage-$VERSION-amd64.deb
```

The package installs `/usr/bin/nexcage`, a man page, bash completion and an
example configuration at `/usr/share/doc/nexcage/examples/config.json`.

### Binary

```bash
VERSION=0.11.1
wget https://github.com/CageForge/nexcage/releases/download/v$VERSION/nexcage-$VERSION-amd64
wget https://github.com/CageForge/nexcage/releases/download/v$VERSION/checksums.txt
sha256sum --ignore-missing -c checksums.txt
install -m 0755 nexcage-$VERSION-amd64 /usr/local/bin/nexcage
```

### The binary with the crun backend (0.11.2 and later)

```bash
VERSION=0.11.2
wget https://github.com/CageForge/nexcage/releases/download/v$VERSION/nexcage-$VERSION-amd64-crun
wget https://github.com/CageForge/nexcage/releases/download/v$VERSION/checksums.txt
sha256sum --ignore-missing -c checksums.txt
install -m 0755 nexcage-$VERSION-amd64-crun /usr/local/bin/nexcage
```

It links libcrun's dependencies dynamically, and a Proxmox VE host does not
have all of them:

```bash
apt install libyajl2 libseccomp2 libcap2
```

Without `libyajl2` the binary does not start at all —
`error while loading shared libraries: libyajl.so.2`. The plain binary needs
none of this.

A container engine never passes `--runtime`, so the configuration has to send
containers to that backend:

```bash
mkdir -p /etc/nexcage
cat > /etc/nexcage/config.json <<'JSON'
{ "runtime": { "routing": [ { "pattern": "*", "runtime": "crun" } ] } }
JSON
```

A routing pattern is a regular expression only when it starts with `^` or ends
with `$`; `".*"` is read as a wildcard and matches nothing. Use `"*"`.

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
