#!/bin/sh
# A Proxmox LXC container made under --root stays the Proxmox backend's, in a
# build that has the crun backend too.
#
# A command after create finds its backend from what is on disk, and libcrun
# keeps its containers in --root itself, one directory per id. The Proxmox
# backend used to write its state.json into <root>/<name> as well, so in a
# release binary every command after an LXC create under --root went to
# libcrun: state and start failed on a missing status file, and delete --force
# removed the directory, exited 0, and left the container in Proxmox. The
# simulator builds without crun and could not see it; this image has both.
# For the same reason the checks that one id is one backend's, both ways, are
# here: neither backend is given an id the other has, and the Proxmox backend
# keeps no record of a CT under a name libcrun has.
#
# The Proxmox tools are tests/sim's fakes, mounted at /sim/bin; their call log
# is the check.
#
# Usage: lxc_root.sh     (tests/sim/bin mounted at /sim/bin)
set -eu

NEXCAGE=${NEXCAGE:-/usr/local/bin/nexcage}
ROOT=/run/lxc-root-check
TPL=local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst

fail() { echo "FAIL: $*" >&2; exit 1; }

[ -x /sim/bin/pct ] || fail "no fake pct at /sim/bin: mount tests/sim/bin there"
SIM=$(mktemp -d)
export SIM PATH="/sim/bin:$PATH"
: > "$SIM/db"; : > "$SIM/calls"
echo "$TPL" > "$SIM/templates"
CFG=$SIM/config.json
echo '{"network":{"bridge":"vmbr0"}}' > "$CFG"
nx() { "$NEXCAGE" --config "$CFG" --root "$ROOT" "$@"; }
called() { grep -qx -- "$1" "$SIM/calls"; }

nx create --name web "$TPL" >/dev/null 2>"$SIM/err" || fail "create: $(tail -1 "$SIM/err")"
grep -q "^pct create 100 $TPL --hostname web " "$SIM/calls" || fail "create did not reach pct: $(cat "$SIM/calls")"
[ ! -e "$ROOT/web" ] || fail "the Proxmox backend wrote into $ROOT/web, which is where libcrun keeps a container called web"
echo "ok: created through pct, its state is not in libcrun's directory"

nx state web >/dev/null 2>"$SIM/err" || fail "state went elsewhere: $(tail -1 "$SIM/err")"
echo "ok: state finds it"
nx start web >/dev/null 2>"$SIM/err" || fail "start went elsewhere: $(tail -1 "$SIM/err")"
called "pct start 100" || fail "start did not reach pct"
echo "ok: start reaches pct"

# One id, one backend: libcrun is not given an id the Proxmox backend has a
# record of, or every later command would reach only one of the two. The
# bundle is one libcrun would create from -- it only looks for the program at
# create -- so a create that got through would show as $ROOT/web.
mkdir -p "$SIM/bundle/rootfs/bin" "$SIM/bundle/rootfs/dev" "$SIM/bundle/rootfs/proc" "$SIM/bundle/rootfs/sys"
printf '#!/bin/sh\n' > "$SIM/bundle/rootfs/bin/true"
chmod +x "$SIM/bundle/rootfs/bin/true"
cat > "$SIM/bundle/config.json" <<'JSON'
{"ociVersion":"1.0.0","process":{"args":["/bin/true"],"cwd":"/","user":{"uid":0,"gid":0}},"root":{"path":"rootfs"},"mounts":[{"destination":"/proc","type":"proc","source":"proc"}],"linux":{"namespaces":[{"type":"mount"},{"type":"pid"}]}}
JSON
rc=0; nx --runtime crun create --bundle "$SIM/bundle" web >/dev/null 2>"$SIM/err" || rc=$?
[ ! -e "$ROOT/web" ] || fail "libcrun made a container web beside the Proxmox one (rc=$rc): $(ls "$ROOT/web")"
[ "$rc" != 0 ] || fail "a crun create of web, which the Proxmox backend has, exited 0"
grep -q "already exists on the Proxmox LXC backend" "$SIM/err" || fail "refused, but not for that: $(tail -1 "$SIM/err")"
echo "ok: libcrun is not given an id the Proxmox backend has"
nx delete --force web >/dev/null 2>"$SIM/err" || fail "delete --force: $(tail -1 "$SIM/err")"
called "pct destroy 100" || fail "delete --force exited 0 without destroying the container"
[ ! -s "$SIM/db" ] || fail "the container is still there: $(cat "$SIM/db")"
echo "ok: delete --force destroys it"

# The other way round: the Proxmox backend is not given an id libcrun has.
# Only a build with crun can show it; in the simulator's, a status file under
# /run/crun is another runtime's and holds nothing up.
nx --runtime crun create --bundle "$SIM/bundle" ctr >/dev/null 2>"$SIM/err" || fail "crun create of ctr: $(tail -1 "$SIM/err")"
[ -e "$ROOT/ctr/status" ] || fail "libcrun did not record ctr in $ROOT"
rc=0; nx create --name ctr "$TPL" >/dev/null 2>"$SIM/err" || rc=$?
! grep -q -- "--hostname ctr " "$SIM/calls" || fail "pct was asked to create ctr, which libcrun has (rc=$rc)"
[ "$rc" != 0 ] || fail "a Proxmox LXC create of ctr, which libcrun has, exited 0"
grep -q "already exists on the crun backend" "$SIM/err" || fail "refused, but not for that: $(tail -1 "$SIM/err")"
echo "ok: the Proxmox backend is not given an id libcrun has"

# Nor is a record of a CT kept under a name libcrun has. CT 101, which
# nexcage did not create, has the hostname ctr and is started by its VMID with
# --runtime lxc. A record of it under ctr would send ctr to the Proxmox
# backend once libcrun's container was gone, and an engine's second delete
# --force of ctr would destroy the CT.
echo "101 stopped ctr" >> "$SIM/db"
nx --runtime lxc start 101 >/dev/null 2>"$SIM/err" || fail "--runtime lxc start 101: $(tail -1 "$SIM/err")"
called "pct start 101" || fail "--runtime lxc start 101 did not reach pct"
[ ! -e "$ROOT/.proxmox-lxc/ctr" ] || fail "CT 101 was recorded under ctr, an id libcrun has"
# The warning says how the CT is reached now, and that has to work: by its
# name, --runtime lxc is refused, since libcrun has the name. A snapshot,
# because the fake init does not run here, so the CT does not stay up.
grep -q "reach the CT by its VMID: nexcage --runtime lxc <command> 101" "$SIM/err" \
    || fail "the warning does not say the CT is reached by its VMID: $(grep WARN "$SIM/err" | tail -1)"
rc=0; nx --runtime lxc snapshot ctr s1 >/dev/null 2>"$SIM/err" || rc=$?
[ "$rc" = 2 ] || fail "--runtime lxc snapshot ctr s1, by a name libcrun has, exited $rc, not 2"
! called "pct snapshot 101 s1" || fail "--runtime lxc snapshot ctr s1 reached CT 101 by a name libcrun has"
nx --runtime lxc snapshot 101 s1 >/dev/null 2>"$SIM/err" || fail "--runtime lxc snapshot 101 s1, as the warning says: $(tail -1 "$SIM/err")"
called "pct snapshot 101 s1" || fail "--runtime lxc snapshot 101 s1 did not reach pct"
echo "ok: the CT is reached by its VMID, as the warning says, and not by the name libcrun has"
nx delete --force ctr >/dev/null 2>"$SIM/err" || fail "delete --force ctr: $(tail -1 "$SIM/err")"
[ ! -e "$ROOT/ctr" ] || fail "libcrun's ctr is still there after delete --force"
nx delete --force ctr >/dev/null 2>"$SIM/err" || fail "a second delete --force ctr: $(tail -1 "$SIM/err")"
! grep -q "^pct destroy 101$" "$SIM/calls" || fail "an engine's second delete --force of ctr destroyed CT 101"
grep -q "^101 " "$SIM/db" || fail "CT 101 is gone: $(cat "$SIM/db")"
echo "ok: no record of a CT is kept under an id libcrun has"

rm -rf "$SIM" "$ROOT"
echo "PASS: a Proxmox LXC container under --root stays the Proxmox backend's"
