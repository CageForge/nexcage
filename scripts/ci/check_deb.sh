#!/bin/sh
# Installs a nexcage .deb into a clean Debian 13 container, as a Proxmox VE 9
# node is, and runs it there (#380). That proves the Depends line brings in
# everything the binary links, and that the crun backend is in the binary:
# `features` is answered by libcrun itself.
#
# What the package carries is read from the package, not from the installed
# tree: a minimized image skips /usr/share/doc and man pages on install.
#
# Usage: scripts/ci/check_deb.sh dist/nexcage-<version>-amd64.deb
set -eu

DEB=${1:?usage: check_deb.sh <path to .deb>}
[ -f "$DEB" ] || { echo "check_deb.sh: no $DEB" >&2; exit 1; }
DIR=$(cd "$(dirname "$DEB")" && pwd)
NAME=$(basename "$DEB")

dpkg-deb --info "$DEB"
payload=$(dpkg-deb -c "$DEB" | awk '{print $6}')
for f in ./usr/bin/nexcage \
         ./usr/share/man/man1/nexcage.1.gz \
         ./usr/share/bash-completion/completions/nexcage \
         ./usr/share/doc/nexcage/examples/config.json \
         ./usr/share/doc/nexcage/examples/config.oci.example.json; do
    echo "$payload" | grep -qx "$f" || { echo "check_deb.sh: $f missing from $NAME" >&2; exit 1; }
done

docker run --rm -v "$DIR:/dist:ro" debian:trixie sh -euxc "
  apt-get update -qq
  apt-get install -y -qq /dist/$NAME
  nexcage version
  nexcage --help > /dev/null
  nexcage --runtime crun features | head -3
  for c in config.json config.oci.example.json; do
    dpkg-deb --fsys-tarfile /dist/$NAME | tar -xO ./usr/share/doc/nexcage/examples/\$c > /tmp/\$c
    nexcage --config /tmp/\$c version
  done
"
echo "ok: $NAME installs on Debian 13 and runs, with the crun backend"
