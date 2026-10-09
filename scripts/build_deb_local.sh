#!/bin/bash
# Builds dist/nexcage-<VERSION>-amd64.deb with dpkg-deb. release.yml uses it.
#
# The package carries the one nexcage binary, with both backends: Proxmox LXC
# and crun (#380). crun links vendored libcrun, which the Dockerfile builds
# from a clean clone (submodules, generated headers), so the binary comes from
# there, or from NEXCAGE_BIN when the caller has built it already: release.yml
# passes the binary it tested and publishes.
#
#   bash scripts/build_deb_local.sh                          # needs docker
#   NEXCAGE_BIN=path/to/nexcage bash scripts/build_deb_local.sh
#
# The package is assembled directly rather than through debhelper: the old
# dh packaging described the proxmox-lxcri service and could not build. This
# script used to copy the whole tree to
# ../build-deb and then compute the repository root from there, which put the
# result in the parent directory instead of dist/.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Resolved before the cd below, so a relative path means what the caller meant.
BIN=${NEXCAGE_BIN:+$(realpath "$NEXCAGE_BIN")}
cd "$REPO_ROOT"

VERSION=$(tr -d '\n\r' < VERSION)
PACKAGE=nexcage
DEB="$REPO_ROOT/dist/${PACKAGE}-${VERSION}-amd64.deb"

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
ROOT="$STAGE/$PACKAGE"

echo "Building ${PACKAGE} ${VERSION}-1 (amd64)"
command -v objdump >/dev/null || { echo "build_deb_local.sh: needs objdump (binutils)" >&2; exit 1; }
if [ -z "$BIN" ]; then
    command -v docker >/dev/null || {
        echo "build_deb_local.sh: needs docker to build the binary," >&2
        echo "or NEXCAGE_BIN=<a binary built with -Denable-backend-crun=true>" >&2
        exit 1
    }
    # -Dcpu=baseline: the package has to run on any x86_64 Proxmox host, not
    # just on one like the machine that built it.
    docker build --build-arg BUILD_FLAGS="-Denable-backend-crun=true -Dcpu=baseline" -t nexcage:deb .
    cid=$(docker create nexcage:deb)
    BIN="$STAGE/nexcage.bin"
    docker cp "$cid:/usr/local/bin/nexcage" "$BIN"
    docker rm "$cid" >/dev/null
fi
# A binary without the crun backend links none of libcrun's libraries. Packing
# one would ship a .deb whose engine configuration points at a backend it lacks.
if ! objdump -p "$BIN" | grep -q 'NEEDED *libjson-c\.so'; then
    echo "build_deb_local.sh: $BIN has no crun backend (it does not link libjson-c)" >&2
    exit 1
fi
# The newest glibc symbol version the binary uses, as dpkg-shlibdeps would put it.
GLIBC=$(objdump -T "$BIN" | grep -o 'GLIBC_[0-9.]*' | sed 's/GLIBC_//' | sort -uV | tail -1)

install -D -m 0755 "$BIN" "$ROOT/usr/bin/nexcage"
install -D -m 0644 packaging/man/nexcage.1 "$ROOT/usr/share/man/man1/nexcage.1"
gzip -9n "$ROOT/usr/share/man/man1/nexcage.1"
install -D -m 0644 packaging/completion/nexcage.bash "$ROOT/usr/share/bash-completion/completions/nexcage"
install -D -m 0644 packaging/config/config.json "$ROOT/usr/share/doc/$PACKAGE/examples/config.json"
install -D -m 0644 packaging/config/config.oci.example.json "$ROOT/usr/share/doc/$PACKAGE/examples/config.oci.example.json"
install -D -m 0644 README.md "$ROOT/usr/share/doc/$PACKAGE/README.md"
# The binary carries libcrun and libocispec, statically linked, under their
# own licenses; the package's copyright file says so.
mkdir -p "$ROOT/usr/share/doc/$PACKAGE"
{
    cat LICENSE
    cat <<'TXT'

------------------------------------------------------------------------------
The nexcage binary also contains, statically linked, code from crun
(https://github.com/containers/crun), built from the fork at
https://github.com/CageForge/crun at the commit the Dockerfile names:

 - src/libcrun: LGPL-2.1-or-later, as its file headers state;
 - libocispec's src, the OCI spec parsers (most of them generated at build
   time): see libocispec/COPYING, GPL-3.0 for the generator, with a special
   exception for the generated parser files.

crun's own command-line tool, GPL-2.0, is not built into nexcage.
TXT
} > "$ROOT/usr/share/doc/$PACKAGE/copyright"
chmod 0644 "$ROOT/usr/share/doc/$PACKAGE/copyright"

INSTALLED_SIZE=$(du -sk "$ROOT" | cut -f1)
mkdir -p "$ROOT/DEBIAN"
cat > "$ROOT/DEBIAN/control" <<EOF
Package: $PACKAGE
Version: ${VERSION}-1
Section: admin
Priority: optional
Architecture: amd64
Maintainer: CageForge Team <contact@cageforge.com>
Installed-Size: $INSTALLED_SIZE
Depends: libc6 (>= ${GLIBC}), libjson-c5, libseccomp2, libcap2, libsystemd0
Recommends: pve-container
Homepage: https://github.com/CageForge/nexcage
Description: Proxmox VE LXC command line and OCI runtime
 nexcage creates, starts, stops, deletes and inspects LXC containers on a
 Proxmox VE cluster through pct and pvesh, from Proxmox templates or, on
 Proxmox VE 9.1 and later, OCI registry images.
 .
 It is also an OCI runtime that containerd, CRI-O and podman drive: its crun
 backend, built on libcrun, runs their containers, and an isolation profile
 narrows what a Kubernetes pod gets.
 .
 It runs on a Proxmox VE host as root. Example configurations are in
 /usr/share/doc/nexcage/examples: config.json for the command line, and
 config.oci.example.json for a container engine.
EOF

mkdir -p "$(dirname "$DEB")"
dpkg-deb --root-owner-group --build "$ROOT" "$DEB"
echo "Built $DEB"
