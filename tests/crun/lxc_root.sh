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
nx delete --force web >/dev/null 2>"$SIM/err" || fail "delete --force: $(tail -1 "$SIM/err")"
called "pct destroy 100" || fail "delete --force exited 0 without destroying the container"
[ ! -s "$SIM/db" ] || fail "the container is still there: $(cat "$SIM/db")"
echo "ok: delete --force destroys it"

rm -rf "$SIM" "$ROOT"
echo "PASS: a Proxmox LXC container under --root stays the Proxmox backend's"
