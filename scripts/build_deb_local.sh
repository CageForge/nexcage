#!/bin/bash
# Builds dist/nexcage-<VERSION>-amd64.deb with dpkg-deb. release.yml uses it.
#
# The package is assembled directly rather than through debhelper: the old
# dh packaging described the proxmox-lxcri service and could not build. This
# script used to copy the whole tree to
# ../build-deb and then compute the repository root from there, which put the
# result in the parent directory instead of dist/.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

VERSION=$(tr -d '\n\r' < VERSION)
PACKAGE=nexcage
DEB="$REPO_ROOT/dist/${PACKAGE}-${VERSION}-amd64.deb"

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
ROOT="$STAGE/$PACKAGE"

echo "Building ${PACKAGE} ${VERSION}-1 (amd64)"
# -Dcpu=baseline: the package has to run on any x86_64 Proxmox host, not just
# on one like the machine that built it.
zig build -Doptimize=ReleaseSafe -Dcpu=baseline

install -D -m 0755 zig-out/bin/nexcage "$ROOT/usr/bin/nexcage"
install -D -m 0644 packaging/man/nexcage.1 "$ROOT/usr/share/man/man1/nexcage.1"
gzip -9n "$ROOT/usr/share/man/man1/nexcage.1"
install -D -m 0644 packaging/completion/nexcage.bash "$ROOT/usr/share/bash-completion/completions/nexcage"
install -D -m 0644 packaging/config/config.json "$ROOT/usr/share/doc/$PACKAGE/examples/config.json"
install -D -m 0644 README.md "$ROOT/usr/share/doc/$PACKAGE/README.md"
install -D -m 0644 LICENSE "$ROOT/usr/share/doc/$PACKAGE/copyright"

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
Depends: libc6
Recommends: pve-container
Homepage: https://github.com/CageForge/nexcage
Description: command-line lifecycle for Proxmox VE LXC containers
 nexcage creates, starts, stops, deletes and inspects LXC containers on a
 Proxmox VE host through pct and pvesh. Containers are created from Proxmox
 templates, OCI bundles or, on Proxmox VE 9.1 and later, OCI registry images.
 .
 It runs on the Proxmox VE host as root. An example configuration is in
 /usr/share/doc/nexcage/examples/config.json.
EOF

mkdir -p "$(dirname "$DEB")"
dpkg-deb --root-owner-group --build "$ROOT" "$DEB"
echo "Built $DEB"
