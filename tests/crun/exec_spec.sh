#!/bin/sh
# exec's process spec is written where only root can make entries.
#
# libcrun takes the process an `exec` runs as a file. nexcage writes that file
# for a command typed on the command line, and for an engine's `--process`
# into a container made under an isolation profile (the spec is cut to the
# container's bounding set first). It used to be /tmp/nexcage-exec-<pid>.json:
# a local user who made directories under the next few thousand of those names
# -- one mkdir, the pids come in order -- made every exec that drew one abort
# the root process with "panic: invalid error code", exit 134. kubectl exec
# and exec probes into profiled pods went with it.
#
# The planting is done the way the attack does it, as nobody, ahead of the
# pids the execs will get; then the execs have to work, and leave nothing.
#
# Usage: exec_spec.sh [bundle-dir]     (default /bundle, rootfs already in it)
set -eu

BUNDLE=${1:-/bundle}
NEXCAGE=${NEXCAGE:-/usr/local/bin/nexcage}
WORK=$(mktemp -d)
CFG=$WORK/config.json
ID=exec-spec-$$

fail() { echo "FAIL: $*" >&2; exit 1; }

[ -x "$BUNDLE/rootfs/bin/sh" ] || [ -L "$BUNDLE/rootfs/bin/sh" ] || \
    fail "no rootfs in $BUNDLE: put one there first"
command -v setpriv >/dev/null || fail "needs setpriv, to plant as an unprivileged user"

if [ -w /sys/fs/cgroup/cgroup.subtree_control ]; then
    mkdir -p /sys/fs/cgroup/init 2>/dev/null || true
    for p in $(cat /sys/fs/cgroup/cgroup.procs 2>/dev/null); do
        echo "$p" > /sys/fs/cgroup/init/cgroup.procs 2>/dev/null || true
    done
fi

cat > "$CFG" <<'JSON'
{ "profiles": { "hardened": { "runtime": "crun", "crun": { "capabilities": { "drop": ["CAP_NET_RAW"] } } } } }
JSON

cat > "$BUNDLE/config.json" <<JSON
{
  "ociVersion": "1.0.0",
  "process": {
    "terminal": false,
    "user": { "uid": 0, "gid": 0 },
    "args": [ "/bin/sleep", "300" ],
    "env": [ "PATH=/bin:/usr/bin" ],
    "cwd": "/",
    "capabilities": {
      "bounding": [ "CAP_CHOWN", "CAP_KILL", "CAP_NET_RAW" ],
      "effective": [ "CAP_CHOWN", "CAP_KILL", "CAP_NET_RAW" ],
      "permitted": [ "CAP_CHOWN", "CAP_KILL", "CAP_NET_RAW" ]
    }
  },
  "root": { "path": "rootfs", "readonly": false },
  "hostname": "$ID",
  "mounts": [ { "destination": "/proc", "type": "proc", "source": "proc" } ],
  "linux": {
    "namespaces": [ { "type": "pid" }, { "type": "ipc" }, { "type": "uts" }, { "type": "mount" } ]
  }
}
JSON

# What containerd sends for kubectl exec: the capabilities of its own copy of
# the spec, so the profile has something to cut and nexcage writes a file.
cat > "$WORK/process.json" <<'JSON'
{ "terminal": false, "user": { "uid": 0, "gid": 0 }, "cwd": "/",
  "env": [ "PATH=/bin:/usr/bin" ], "args": [ "/bin/true" ],
  "capabilities": { "bounding": [ "CAP_CHOWN", "CAP_NET_RAW" ], "effective": [ "CAP_NET_RAW" ], "permitted": [ "CAP_NET_RAW" ] } }
JSON

ln -s "$NEXCAGE" "$WORK/nexcage@hardened"
nx() { "$NEXCAGE" --config "$CFG" "$@"; }
cleanup() {
    cd /
    nx delete --force "$ID" >/dev/null 2>&1 || true
    find /tmp -maxdepth 1 -name 'nexcage-exec-*.json' -user nobody -exec rmdir {} + 2>/dev/null || true
    rm -rf "$WORK"
}
trap cleanup EXIT
cd /

"$WORK/nexcage@hardened" --config "$CFG" create --bundle "$BUNDLE" "$ID" 2>"$WORK/err" || fail "create under nexcage@hardened: $(tail -1 "$WORK/err")"
nx start "$ID" 2>"$WORK/err" || fail "start: $(tail -1 "$WORK/err")"
nx exec "$ID" --process "$WORK/process.json" 2>"$WORK/err" || fail "exec --process before anything was planted: $(tail -1 "$WORK/err")"
echo "ok: $ID runs under a profile, and exec works"

# One mkdir for the lot, run as nobody: a shell loop would use up the very
# pids it is trying to get ahead of.
last=$(cat /proc/sys/kernel/ns_last_pid)
setpriv --reuid=65534 --regid=65534 --clear-groups \
    mkdir $(seq -f '/tmp/nexcage-exec-%.0f.json' $((last + 1)) $((last + 3000)))
planted=$(find /tmp -maxdepth 1 -name 'nexcage-exec-*.json' -type d -user nobody | wc -l)
[ "$planted" -ge 3000 ] || fail "only $planted directories were planted"
echo "ok: nobody planted $planted directories ahead of the next pids"

for round in 1 2 3; do
    rc=0; nx exec "$ID" --process "$WORK/process.json" >/dev/null 2>"$WORK/err" || rc=$?
    [ "$rc" = 0 ] || fail "round $round: exec --process into a profiled container exited $rc with directories planted in /tmp: $(head -c 300 "$WORK/err" | tr '\n' ' ')"
    rc=0; nx exec "$ID" /bin/true 2>"$WORK/err" || rc=$?
    [ "$rc" = 0 ] || fail "round $round: exec <id> /bin/true exited $rc with directories planted in /tmp: $(head -c 300 "$WORK/err" | tr '\n' ' ')"
done
echo "ok: exec --process and a command-line exec work regardless (3 rounds each)"

# Nothing of nexcage's in /tmp, nothing left in the container's state.
left=$(find /tmp -maxdepth 1 -name 'nexcage-exec-*' ! -user nobody | wc -l)
[ "$left" = 0 ] || fail "nexcage left $left entries in /tmp"
state=/run/crun/$ID
[ -d "$state" ] || fail "no state directory at $state to look in"
spec=$(find "$state" -name 'nexcage-exec-*' | wc -l)
[ "$spec" = 0 ] || fail "$spec process spec file(s) left in $state"
[ "$(stat -c %a "$state")" = 700 ] || fail "the state directory $state is $(stat -c %a "$state"), not 700"
echo "ok: no file in /tmp, none left in $state (mode 700)"

echo "PASS: exec's process spec cannot be planted against"
