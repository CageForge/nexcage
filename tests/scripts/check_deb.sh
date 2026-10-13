#!/usr/bin/env bash
# scripts/ci/check_deb.sh is the release's last word on a .deb: it packs the
# files it should, its man page names its version, its binary is a PIE, and
# that binary has the crun backend -- `features` is answered by libcrun, so a
# binary without it fails there.
# A check that cannot fail proves nothing, so this runs it on packages that
# should be refused as well as on one that should pass.
#
# The packages are built here with dpkg-deb. docker is a fake that runs the
# script check_deb.sh hands the Debian 13 container on this machine instead,
# with /dist and /tmp pointed into a scratch directory, apt-get a no-op and
# nexcage a fake: "crun" answers features as a binary with the backend does,
# "lxc" fails it as one without the backend does.
#
#   bash tests/scripts/check_deb.sh [path/to/check_deb.sh]
set -euo pipefail

REPO=$(cd "$(dirname "$0")/../.." && pwd)
CHECK=$(realpath "${1:-$REPO/scripts/ci/check_deb.sh}")
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
for tool in dpkg-deb readelf; do
  command -v "$tool" >/dev/null || { echo "needs $tool" >&2; exit 2; }
done

failed=0
ok()  { echo "ok   $*"; }
bad() { echo "FAIL $*"; failed=1; }

# mk_deb NAME ELF [MANVERSION]: a package with everything check_deb.sh looks
# for, whose usr/bin/nexcage is a copy of ELF and whose man page's header
# names MANVERSION, by default the package's own, 0.0.0.
mk_deb() {
  local root=$T/pkg-$1
  install -D -m 0755 "$2" "$root/usr/bin/nexcage"
  mkdir -p "$root/usr/share/man/man1"
  printf '.TH NEXCAGE 1 "October 2026" "nexcage %s" "User Commands"\n.SH NAME\nnexcage\n' "${3:-0.0.0}" \
    | gzip -9n > "$root/usr/share/man/man1/nexcage.1.gz"
  install -D -m 0644 /dev/null "$root/usr/share/bash-completion/completions/nexcage"
  for f in config.json config.oci.example.json; do
    mkdir -p "$root/usr/share/doc/nexcage/examples"; echo '{}' > "$root/usr/share/doc/nexcage/examples/$f"
  done
  mkdir -p "$root/DEBIAN"
  printf 'Package: nexcage\nVersion: 0.0.0-1\nArchitecture: amd64\nMaintainer: test <test@example.invalid>\nDescription: test\n' > "$root/DEBIAN/control"
  mkdir -p "$T/dist-$1"
  dpkg-deb --root-owner-group --build "$root" "$T/dist-$1/nexcage-0.0.0-amd64.deb" > /dev/null
}

# A PIE and a non-PIE executable from this machine: the binary's ELF type is
# all the PIE check reads; what runs is the fake nexcage.
pie=$(type -P true)
case "$(readelf -h "$pie" | sed -n 's/^ *Type: *//p')" in
  DYN*) ;; *) echo "$pie is not a PIE; cannot build the fixture" >&2; exit 2 ;;
esac
nopie=''
for c in /usr/lib/klibc/bin/sh.shared /usr/bin/busybox /bin/busybox; do
  [ -x "$c" ] && case "$(readelf -h "$c" 2>/dev/null | sed -n 's/^ *Type: *//p')" in EXEC*) nopie=$c; break ;; esac
done
if [ -z "$nopie" ]; then
  # An ELF header patched to ET_EXEC is enough for readelf.
  cp "$pie" "$T/nopie"; printf '\002' | dd of="$T/nopie" bs=1 seek=16 conv=notrunc status=none; nopie=$T/nopie
fi

mkdir -p "$T/fake-crun" "$T/fake-lxc" "$T/docker"
printf '#!/bin/sh\necho "fake apt-get $*"\n' | tee "$T/fake-crun/apt-get" > "$T/fake-lxc/apt-get"
cat > "$T/fake-crun/nexcage" <<'FAKE'
#!/bin/sh
case "$*" in
  *features*) printf '{\n  "ociVersionMin": "1.0.0",\n  "annotations": {\n    "io.cageforge.nexcage.backend": "crun"\n  }\n}\n' ;;
  *) echo "nexcage version 0.0.0" ;;
esac
FAKE
cat > "$T/fake-lxc/nexcage" <<'FAKE'
#!/bin/sh
case "$*" in
  *features*) echo "ERROR nexcage: The crun backend is not built into this binary; rebuild with -Denable-backend-crun=true" >&2; exit 1 ;;
  *) echo "nexcage version 0.0.0" ;;
esac
FAKE
chmod +x "$T"/fake-*/*
# docker pull IMAGE, and docker run --rm -v DIR:/dist:ro debian:trixie sh -euxc SCRIPT
cat > "$T/docker/docker" <<'FAKE'
#!/bin/sh
[ "$1" = pull ] && exit 0
[ "$1 $2 $3" = "run --rm -v" ] || { echo "fake docker: unexpected $*" >&2; exit 2; }
dist=${4%%:*}
[ "$6 $7" = "sh -euxc" ] || { echo "fake docker: unexpected $*" >&2; exit 2; }
mkdir -p "$SCRATCH/tmp"
script=$(printf '%s' "$8" | sed -e "s#/tmp/#$SCRATCH/tmp/#g" -e "s#/dist/#$dist/#g")
PATH="$FAKES:$PATH" exec sh -euxc "$script"
FAKE
chmod +x "$T/docker/docker"

# run NAME FAKES: check_deb.sh on dist-NAME's package; sets rc.
run() {
  rc=0
  PATH="$T/docker:$PATH" FAKES="$T/$2" SCRATCH="$T/scratch-$1-$2" \
    sh "$CHECK" "$T/dist-$1/nexcage-0.0.0-amd64.deb" > "$T/out-$1-$2" 2>&1 || rc=$?
}

mk_deb pie "$pie"
mk_deb nopie "$nopie"
mk_deb oldman "$pie" 0.13.0

run pie fake-crun
if [ "$rc" = 0 ]; then ok "a package whose PIE binary has the crun backend passes"
else bad "a package whose PIE binary has the crun backend passes (exit $rc)"; sed 's/^/     /' "$T/out-pie-fake-crun"; fi

run pie fake-lxc
if [ "$rc" != 0 ]; then ok "a binary whose features fails, built without the crun backend, is refused"
else bad "a binary whose features fails, built without the crun backend, is refused (exit 0)"; fi

run nopie fake-crun
if [ "$rc" != 0 ] && grep -q 'not position-independent' "$T/out-nopie-fake-crun"; then ok "a binary that is not a PIE is refused"
else bad "a binary that is not a PIE is refused (exit $rc)"; fi

run oldman fake-crun
if [ "$rc" != 0 ] && grep -q 'does not name version 0.0.0' "$T/out-oldman-fake-crun"; then ok "a man page that names another version than the package's is refused"
else bad "a man page that names another version than the package's is refused (exit $rc)"; fi

exit "$failed"
