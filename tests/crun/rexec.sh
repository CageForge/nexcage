#!/bin/sh
# The CVE-2019-5736 protection runs where it protects something, and only
# there.
#
# libcrun re-executes its caller from a sealed copy of the binary, so that a
# process in a container cannot reach the binary on the host through
# /proc/<pid>/exe. It did that from a constructor, before main, on every run:
# `nexcage version`, `--help` and every Proxmox LXC command needed /proc and
# open_tree, a bind mount or an executable memfd, printed "Failed to re-execute
# libcrun via memory file descriptor" and exited 1 where they were missing, and
# passed _LIBCONTAINER_CLONED_BINARY=1 on to pct and pvesh. Now only create
# and exec on the crun backend do it, from the driver.
#
# Usage: rexec.sh [bundle-dir]     (default /bundle, rootfs already in it)
set -eu

BUNDLE=${1:-/bundle}
NEXCAGE=${NEXCAGE:-/usr/local/bin/nexcage}
WORK=$(mktemp -d)
ID=rexec-check-$$

fail() { echo "FAIL: $*" >&2; exit 1; }

[ -x "$BUNDLE/rootfs/bin/sh" ] || [ -L "$BUNDLE/rootfs/bin/sh" ] || \
    fail "no rootfs in $BUNDLE: put one there first"
command -v unshare >/dev/null || fail "needs unshare"

nx() { "$NEXCAGE" --runtime crun "$@"; }
cleanup() { cd /; nx delete --force "$ID" >/dev/null 2>&1 || true; rm -rf "$WORK"; }
trap cleanup EXIT
cd /

# 1. Without /proc: nothing that needs no container needs it.
for args in version --help; do
    rc=0
    out=$(unshare -m sh -c 'mount -t tmpfs none /proc && exec "$@"' sh "$NEXCAGE" $args 2>&1) || rc=$?
    [ "$rc" = 0 ] || fail "nexcage $args with /proc hidden exited $rc: $(echo "$out" | head -3 | tr '\n' ' ')"
    echo "$out" | grep -q "nexcage" || fail "nexcage $args with /proc hidden printed: $(echo "$out" | head -3 | tr '\n' ' ')"
    echo "ok: nexcage $args runs with /proc hidden"
done

# 2. A Proxmox LXC command runs no re-execution: the tools it calls see no
# _LIBCONTAINER_CLONED_BINARY in their environment.
mkdir -p "$WORK/bin"
for tool in pct pvesh pveversion pveam; do
    printf '#!/bin/sh\nenv > "%s/env.%s"\nexit 1\n' "$WORK" "$tool" > "$WORK/bin/$tool"
    chmod +x "$WORK/bin/$tool"
done
PATH="$WORK/bin:$PATH" "$NEXCAGE" list >/dev/null 2>&1 || true
ls "$WORK"/env.* >/dev/null 2>&1 || fail "nexcage list called no Proxmox tool: the check would prove nothing"
if grep -h '^_LIBCONTAINER_CLONED_BINARY=' "$WORK"/env.*; then
    fail "nexcage list re-executed itself through libcrun's protection, and its children inherited the marker"
fi
echo "ok: nexcage list (Proxmox LXC) does not re-execute: pct and pvesh see no _LIBCONTAINER_CLONED_BINARY"

# 3. The protection is still there for a container: while exec runs a
# command, nexcage's own /proc/<pid>/exe is not the binary on the host.
cat > "$BUNDLE/config.json" <<JSON
{
  "ociVersion": "1.0.0",
  "process": {
    "terminal": false,
    "user": { "uid": 0, "gid": 0 },
    "args": [ "/bin/sleep", "300" ],
    "env": [ "PATH=/bin:/usr/bin" ],
    "cwd": "/"
  },
  "root": { "path": "rootfs", "readonly": false },
  "hostname": "$ID",
  "mounts": [ { "destination": "/proc", "type": "proc", "source": "proc" } ],
  "linux": {
    "namespaces": [ { "type": "pid" }, { "type": "ipc" }, { "type": "uts" }, { "type": "mount" } ]
  }
}
JSON
nx create --bundle "$BUNDLE" "$ID" 2>"$WORK/err" || fail "create: $(tr '\n' ' ' < "$WORK/err")"
nx start "$ID" 2>"$WORK/err" || fail "start: $(tr '\n' ' ' < "$WORK/err")"
# The binary itself in the background, not the nx function: $! has to be
# nexcage's pid, not a subshell's.
"$NEXCAGE" --runtime crun exec "$ID" /bin/sleep 3 &
execpid=$!
sleep 1
exe=$(readlink "/proc/$execpid/exe" 2>/dev/null || echo "(gone)")
wait "$execpid" || fail "exec $ID /bin/sleep 3 failed"
real=$(readlink -f "$NEXCAGE")
if [ -w "$real" ]; then
    [ "$exe" != "$real" ] || fail "exec ran from $real itself, not a sealed copy: the CVE-2019-5736 protection is gone"
    echo "ok: exec runs from a sealed copy ($exe), not from $real"
else
    # libcrun counts a binary on a read-only mount as protected already.
    echo "ok: $real is on a read-only mount, which libcrun counts as protected (exec ran from $exe)"
fi

echo "PASS: the re-execution happens for containers, and nothing else needs it"
