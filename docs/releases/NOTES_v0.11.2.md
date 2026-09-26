# nexcage 0.11.2

**A release now carries the binary a container engine drives.**

```bash
VERSION=0.11.2
wget https://github.com/CageForge/nexcage/releases/download/v$VERSION/nexcage-$VERSION-amd64-crun
wget https://github.com/CageForge/nexcage/releases/download/v$VERSION/checksums.txt
sha256sum --ignore-missing -c checksums.txt
install -m 0755 nexcage-$VERSION-amd64-crun /usr/local/bin/nexcage

apt install libyajl2 libseccomp2 libcap2
```

Until now the runtime backend that podman, containerd, CRI-O and a kubelet drive
had to be built from source, through the Dockerfile, because vendored libcrun
needs the submodules and two generated header sets. That build is published.

## Which binary you want

| | |
|---|---|
| `nexcage-<version>-amd64` | Manages LXC containers on Proxmox VE. No extra libraries. What most uses need |
| `nexcage-<version>-amd64-crun` | Everything the first one does, **plus** the backend a container engine drives. Needs `libyajl2`, `libseccomp2` and `libcap2` |

**`libyajl2` is not on a Proxmox VE host by default.** Without it the `-crun`
binary does not start at all:

```
error while loading shared libraries: libyajl.so.2
```

A container engine never passes `--runtime`, so the configuration has to send
containers to that backend:

```json
{ "runtime": { "routing": [ { "pattern": "*", "runtime": "crun" } ] } }
```

A routing pattern is a regular expression only when it starts with `^` or ends
with `$`. `".*"` is read as a wildcard — a literal dot followed by anything —
and matches nothing. Use `"*"`.

Both binaries are built with `-Dcpu=baseline` and checked on a Xeon E5-2697 v2
without AVX2 before the release is announced.

## The README stopped being wrong

It had been saying **"Status as of version 0.9.0"**, with containerd/CRI
integration and containers on other cluster nodes listed under "Not yet" —
months after both were done. A project's own front page is the worst place for a
claim like that.

It now says what nexcage is: a command line for LXC containers on a Proxmox VE
cluster, and an OCI runtime that podman, `ctr`, containerd's CRI, CRI-O and a
kubelet drive. With a status table that names what is **not** there, install
instructions for both binaries, and the sections an open-source project carries.

`docs/index.md`, the site description and `docs/architecture/OVERVIEW.md` carried
the same stale framing — the last described nexcage as turning CLI commands into
`pct` calls, when it is called from two directions — and now match.

## Nothing else changed

No runtime behaviour, no command line. Upgrading from 0.11.1 is replacing the
binary, and the plain one behaves exactly as it did.
