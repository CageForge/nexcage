# shellcheck shell=bash
# The fake Proxmox host that tests/sim/run.sh and tests/perf/lxc_sim.sh run
# nexcage against. Source it from bash; it checks the machine can host the
# namespace, creates the scratch directory and defines:
#
#   reset_sim      empty container db, call log, state and bundles
#   cfg <json>     write ./config.json for the next nexcage call
#   nexcage_ns ... run nexcage as uid 0 in its own user and mount namespace
#   stop_inits     kill the fake inits `pct start` left running (on EXIT too)
#
# NEXCAGE  binary to run (default zig-out/bin/nexcage)
# SIM_DIR  scratch directory (default zig-out/sim); not under /tmp

SIM_LIB_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO=$(cd "$SIM_LIB_DIR/../.." && pwd)
export BIN=$SIM_LIB_DIR/bin
export NEXCAGE=${NEXCAGE:-$REPO/zig-out/bin/nexcage}
export SIM=${SIM_DIR:-$REPO/zig-out/sim}
S=$SIM
TPL=local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst

[ -x "$NEXCAGE" ] || { echo "no nexcage binary at $NEXCAGE; run 'zig build' first" >&2; exit 2; }
NEXCAGE=$(realpath "$NEXCAGE")
mkdir -p "$SIM"
SIM=$(realpath "$SIM"); S=$SIM
for p in "$SIM" "$NEXCAGE" "$BIN"; do
  case "$p/" in /tmp/*) echo "$p is under /tmp, which the tmpfs hides from nexcage" >&2; exit 2 ;; esac
done
for tool in unshare python3 tar zstd; do
  command -v "$tool" >/dev/null || { echo "needs $tool" >&2; exit 2; }
done
if ! unshare -rm bash -c 'mount -t tmpfs tmpfs /tmp' 2>/dev/null; then
  echo "cannot mount inside an unprivileged user namespace" >&2
  echo "on Ubuntu 24.04: sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0" >&2
  exit 2
fi
mkdir -p "$SIM/run" "$SIM/work" "$SIM/bundles" "$SIM/cache" "$SIM/cgroup"

# Fake pct start leaves a fake init running per started container
stop_inits() {
  local f
  for f in "$S"/pid.*; do
    [ -e "$f" ] || continue
    kill -9 "$(cat "$f")" 2>/dev/null
    rm -f "$f"
  done
}
trap stop_inits EXIT

reset_sim() {
  stop_inits
  rm -rf "${S:?}"/run/* "$S"/work/* "$S/cache" "$S"/bundles/* "$S"/cgroup/*
  mkdir -p "$S/cache"
  : > "$S/db"; : > "$S/calls"
  rm -f "$S"/fail_* "$S/pvever" "$S"/lock.* "$S"/conf.* "$S"/tarlist.* "$S"/sig.* "$S"/snaps.*
  printf "%s\n" "$TPL" local:vztmpl/alpine-3.22-default_20250617_amd64.tar.xz local:vztmpl/debian-12.tar.zst > "$S/templates"
  # The storage's content listing is the other view of the same files, and it
  # was never reset: a pull from a later section -- or an earlier run of this
  # suite -- stayed listed, and create, which now looks there before pulling,
  # found templates that pct then refused. Sections that model other nodes
  # overwrite this file; this host starts with what pct accepts.
  { for t in "$TPL" local:vztmpl/alpine-3.22-default_20250617_amd64.tar.xz local:vztmpl/debian-12.tar.zst; do echo "$(hostname) $t"; done; } > "$S/node_templates"
}
cfg() { printf '%s\n' "$1" > "$S/work/config.json"; }
nexcage_ns() {
  # /sys/fs/cgroup is bound from $SIM, not a fresh tmpfs: `pause` writes the
  # freezer and a later `state` has to read what it wrote, and every nx call is
  # its own namespace.
  unshare -rm bash -c '
    mount --bind "$SIM/run" /run &&
    mount -t tmpfs tmpfs /tmp &&
    mkdir /tmp/nexcage-bundles && mount --bind "$SIM/bundles" /tmp/nexcage-bundles &&
    mount --bind "$SIM/cgroup" /sys/fs/cgroup &&
    cd "$SIM/work" && exec env PATH="$BIN:/usr/bin:/bin" "$NEXCAGE" "$@"' nexcage "$@"
}
