#!/bin/sh
# Isolation profiles on the crun backend (#315, ADR-005), read back from the
# kernel rather than from nexcage's log.
#
# A profile only narrows the engine's bundle: it drops capabilities, lowers
# limits, and refuses a bundle without what it requires. An engine names one by
# the program name, nexcage@<profile>, and only create reads it; later commands
# find the container without it. cgroup v2 only.
#
# Usage: profile.sh [bundle-dir]     (default /bundle, rootfs already in it)
set -eu

BUNDLE=${1:-/bundle}
NEXCAGE=${NEXCAGE:-/usr/local/bin/nexcage}
WORK=$(mktemp -d)
CFG=$WORK/config.json
ID=profile-check-$$

fail() { echo "FAIL: $*" >&2; exit 1; }

[ -x "$BUNDLE/rootfs/bin/sh" ] || [ -L "$BUNDLE/rootfs/bin/sh" ] || \
    fail "no rootfs in $BUNDLE: put one there first"
[ -f /sys/fs/cgroup/cgroup.controllers ] || fail "this checks cgroup v2 files, and the host is not on cgroup v2"

if [ -w /sys/fs/cgroup/cgroup.subtree_control ]; then
    mkdir -p /sys/fs/cgroup/init 2>/dev/null || true
    for p in $(cat /sys/fs/cgroup/cgroup.procs 2>/dev/null); do
        echo "$p" > /sys/fs/cgroup/init/cgroup.procs 2>/dev/null || true
    done
    for c in memory pids; do
        echo "+$c" > /sys/fs/cgroup/cgroup.subtree_control 2>/dev/null || true
    done
fi

cat > "$CFG" <<'JSON'
{ "profiles": {
    "hardened": { "runtime": "crun", "crun": {
        "capabilities": { "drop": ["CAP_NET_RAW", "CAP_MKNOD"] },
        "limits": { "memory": "64M", "pids": 50 } } },
    "needs-seccomp": { "runtime": "crun", "crun": { "seccomp": "require" } },
    "needs-userns": { "runtime": "crun", "crun": { "user_namespace": "require" } } } }
JSON

# What an engine would hand over: a 1 GiB limit the profile lowers, with swap
# (memory plus swap) equal to it, which is containerd's way of saying no swap,
# and the capabilities a container usually gets, NET_RAW and MKNOD among them.
# /dev is a tmpfs, as an engine mounts it: without one libcrun makes its
# device files in the shared rootfs, where a container in a user namespace
# that does not own it cannot replace them.
spec() {
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
      "bounding": [ "CAP_CHOWN", "CAP_KILL", "CAP_NET_RAW", "CAP_MKNOD" ],
      "effective": [ "CAP_CHOWN", "CAP_KILL", "CAP_NET_RAW", "CAP_MKNOD" ],
      "permitted": [ "CAP_CHOWN", "CAP_KILL", "CAP_NET_RAW", "CAP_MKNOD" ]
    }
  },
  "root": { "path": "rootfs", "readonly": false },
  "hostname": "profile-check",
  "mounts": [ { "destination": "/proc", "type": "proc", "source": "proc" },
              { "destination": "/dev", "type": "tmpfs", "source": "tmpfs", "options": [ "nosuid", "mode=755" ] } ],
  "linux": {
    "namespaces": [ { "type": "pid" }, { "type": "ipc" }, { "type": "uts" }, { "type": "mount" }${3:-} ],
    "resources": { "memory": { "limit": 1073741824, "swap": 1073741824 } }
    $1
  }
  $2
}
JSON
}

# The program name names the profile, as an engine's BinaryName does.
ln -s "$NEXCAGE" "$WORK/nexcage@hardened"
nx() { "$NEXCAGE" --config "$CFG" "$@"; }
cleanup() {
    cd /
    for id in "$ID" "$ID-s" "$ID-sa" "$ID-sf" "$ID-sb" "$ID-u" "$ID-g" "$ID-a" "$ID-z" "$ID-c" "$ID-v" "$ID-m" "$ID-o" "$ID-j0" "$ID-j1" "$ID-jp" "$ID-h0" "$ID-h1"; do
        nx delete --force "$id" >/dev/null 2>&1 || true
    done
    umount "$WORK/userns-pin" 2>/dev/null || true
    rm -rf "$WORK"
}
# The pid of a started container, from its state.
pid_of() { nx state "$1" | sed -n 's/.*"pid": *\([0-9][0-9]*\).*/\1/p'; }
trap cleanup EXIT
cd /

spec "" ""
"$WORK/nexcage@hardened" --config "$CFG" create --bundle "$BUNDLE" "$ID" 2>"$WORK/err" || fail "create under nexcage@hardened: $(tail -1 "$WORK/err")"
nx start "$ID" 2>"$WORK/err" || fail "start: $(tail -1 "$WORK/err")"
# Without the profile and without --runtime: the container is found where it is.
state=$(nx state "$ID")
pid=$(echo "$state" | sed -n 's/.*"pid": *\([0-9][0-9]*\).*/\1/p')
[ -n "$pid" ] && [ -d "/proc/$pid" ] || fail "no running process for $ID (state: $state)"
echo "$state" | grep -q '"io.cageforge.nexcage.profile": *"hardened"' || fail "state does not report the profile: $state"
echo "ok: created under nexcage@hardened; state, called without it, reports the profile"

capbnd=$(sed -n 's/^CapBnd:[[:space:]]*//p' "/proc/$pid/status")
bit() { echo $(( (0x$capbnd >> $1) & 1 )); }
[ "$(bit 13)" = 0 ] || fail "CAP_NET_RAW is still in the bounding set ($capbnd)"
[ "$(bit 27)" = 0 ] || fail "CAP_MKNOD is still in the bounding set ($capbnd)"
[ "$(bit 5)" = 1 ] || fail "CAP_KILL, which the profile does not drop, is gone ($capbnd)"
echo "ok: CapBnd $capbnd: NET_RAW and MKNOD dropped, KILL kept"

# An engine's exec carries the capabilities of the engine's own copy of the
# spec, from before the profile narrowed it: kubectl exec through containerd
# does. The process gets none the container was made without.
cat > "$WORK/process.json" <<'JSON'
{ "terminal": false, "user": { "uid": 0, "gid": 0 }, "cwd": "/",
  "env": [ "PATH=/bin:/usr/bin" ],
  "args": [ "/bin/sh", "-c", "sed -n 's/^CapBnd:[[:space:]]*//p' /proc/self/status" ],
  "capabilities": {
    "bounding": [ "CAP_CHOWN", "CAP_KILL", "CAP_NET_RAW", "CAP_MKNOD" ],
    "effective": [ "CAP_CHOWN", "CAP_KILL", "CAP_NET_RAW", "CAP_MKNOD" ],
    "permitted": [ "CAP_CHOWN", "CAP_KILL", "CAP_NET_RAW", "CAP_MKNOD" ] } }
JSON
capbnd=$(nx exec "$ID" --process "$WORK/process.json" 2>"$WORK/err") || fail "exec --process: $(tail -1 "$WORK/err")"
[ -n "$capbnd" ] || fail "exec --process printed no CapBnd"
[ "$(bit 13)" = 0 ] || fail "an exec'd process got CAP_NET_RAW back ($capbnd)"
[ "$(bit 27)" = 0 ] || fail "an exec'd process got CAP_MKNOD back ($capbnd)"
[ "$(bit 5)" = 1 ] || fail "an exec'd process lost CAP_KILL, which the container has ($capbnd)"
echo "ok: exec --process asking for NET_RAW and MKNOD gets CapBnd $capbnd"

# libcrun's parser ends a key at a NUL, and of two keys that are then the
# same it keeps the last. "capabilities\u0000" is what it applies, and the
# process spec had no "capabilities" for nexcage to cut.
cat > "$WORK/process-nul.json" <<'JSON'
{ "terminal": false, "user": { "uid": 0, "gid": 0 }, "cwd": "/",
  "env": [ "PATH=/bin:/usr/bin" ],
  "args": [ "/bin/sh", "-c", "sed -n 's/^CapBnd:[[:space:]]*//p' /proc/self/status" ],
  "capabilities\u0000": {
    "bounding": [ "CAP_CHOWN", "CAP_KILL", "CAP_NET_RAW", "CAP_MKNOD" ],
    "effective": [ "CAP_CHOWN", "CAP_KILL", "CAP_NET_RAW", "CAP_MKNOD" ],
    "permitted": [ "CAP_CHOWN", "CAP_KILL", "CAP_NET_RAW", "CAP_MKNOD" ] } }
JSON
rc=0; capbnd=$(nx exec "$ID" --process "$WORK/process-nul.json" 2>"$WORK/err") || rc=$?
if [ "$rc" = 0 ]; then
    [ "$(bit 13)" = 0 ] || fail "an exec'd process got CAP_NET_RAW back through \"capabilities\\u0000\" (CapBnd $capbnd)"
    fail "exec --process with a NUL in a key ran (CapBnd $capbnd)"
fi
grep -q 'the process spec has a NUL in the key at capabilities\\u0000' "$WORK/err" || fail "the NUL refusal does not say where: $(tail -1 "$WORK/err")"
echo "ok: exec --process with \"capabilities\\u0000\" is refused"

cg=/sys/fs/cgroup$(sed -n 's/^0:://p' "/proc/$pid/cgroup")
[ "$(cat "$cg/memory.max")" = 67108864 ] || fail "memory.max is $(cat "$cg/memory.max"), not the profile's 64M"
[ "$(cat "$cg/pids.max")" = 50 ] || fail "pids.max is $(cat "$cg/pids.max"), not the profile's 50"
echo "ok: memory.max 67108864 (the bundle asked 1G), pids.max 50 (the bundle set none)"
# Lowering the limit alone would have made the other 960M swap.
if [ -f "$cg/memory.swap.max" ]; then
    [ "$(cat "$cg/memory.swap.max")" = 0 ] || fail "memory.swap.max is $(cat "$cg/memory.swap.max"), and the bundle allowed no swap"
    echo "ok: memory.swap.max 0: no swap, as the bundle asked"
else
    echo "skipped: no memory.swap.max here (no swap accounting), so swap is not checked"
fi

# libcrun writes linux.resources.unified last, and it wins: "max" there undid
# the profile's limits after they were written.
spec "" ""
sed -i 's/"swap": 1073741824 } }/"swap": 1073741824 }, "unified": { "memory.max": "max", "memory.high": "max", "pids.max": "max" } }/' "$BUNDLE/config.json"
grep -q '"unified"' "$BUNDLE/config.json" || fail "the bundle did not get its unified section"
"$WORK/nexcage@hardened" --config "$CFG" create --bundle "$BUNDLE" "$ID-v" 2>"$WORK/err" || fail "create with unified: $(tail -1 "$WORK/err")"
nx start "$ID-v" 2>"$WORK/err" || fail "start with unified: $(tail -1 "$WORK/err")"
cgv=/sys/fs/cgroup$(sed -n 's/^0:://p' "/proc/$(pid_of "$ID-v")/cgroup")
[ "$(cat "$cgv/memory.max")" = 67108864 ] || fail "unified's memory.max undid the profile's limit: memory.max is $(cat "$cgv/memory.max")"
[ "$(cat "$cgv/pids.max")" = 50 ] || fail "unified's pids.max undid the profile's limit: pids.max is $(cat "$cgv/pids.max")"
[ "$(cat "$cgv/memory.high")" = 67108864 ] || fail "unified's memory.high is $(cat "$cgv/memory.high"), above the profile's limit"
echo "ok: unified asking \"max\" leaves memory.max 67108864, memory.high 67108864, pids.max 50"

# A second "process" behind a NUL: the profile checked the first, and
# libcrun, which reads "process\u0000" as "process" and keeps the last, would
# apply this one, NET_RAW and MKNOD included.
spec "" ', "process\u0000": { "terminal": false, "user": { "uid": 0, "gid": 0 },
    "args": [ "/bin/sleep", "300" ], "env": [ "PATH=/bin:/usr/bin" ], "cwd": "/",
    "capabilities": { "bounding": [ "CAP_KILL", "CAP_NET_RAW", "CAP_MKNOD" ],
      "effective": [ "CAP_KILL", "CAP_NET_RAW", "CAP_MKNOD" ],
      "permitted": [ "CAP_KILL", "CAP_NET_RAW", "CAP_MKNOD" ] } }'
rc=0; "$WORK/nexcage@hardened" --config "$CFG" create --bundle "$BUNDLE" "$ID-z" 2>"$WORK/err" || rc=$?
if [ "$rc" = 0 ]; then
    nx start "$ID-z" 2>"$WORK/err" || fail "a bundle with a NUL in a key was created, and start failed: $(tail -1 "$WORK/err")"
    capbnd=$(sed -n 's/^CapBnd:[[:space:]]*//p' "/proc/$(pid_of "$ID-z")/status")
    [ "$(bit 13)" = 0 ] && [ "$(bit 27)" = 0 ] || fail "the second \"process\" behind a NUL was applied: CapBnd $capbnd holds NET_RAW or MKNOD, which the profile drops"
    fail "a bundle with a NUL in a key was created (CapBnd $capbnd)"
fi
grep -q 'has a NUL in the key at process\\u0000' "$WORK/err" || fail "the NUL refusal does not say where: $(tail -1 "$WORK/err")"
[ ! -e "/run/crun/$ID-z" ] || fail "a refused create left state behind"
echo "ok: a second \"process\" behind a NUL is refused, and nothing is created"

# libcrun reads capability names with libcap, which takes "cap_net_raw" and
# "27" for CAP_NET_RAW and CAP_MKNOD; the profile compares names.
spec "" ""
sed -i 's/"CAP_NET_RAW"/"cap_net_raw"/g; s/"CAP_MKNOD"/"27"/g' "$BUNDLE/config.json"
rc=0; "$WORK/nexcage@hardened" --config "$CFG" create --bundle "$BUNDLE" "$ID-c" 2>"$WORK/err" || rc=$?
if [ "$rc" = 0 ]; then
    nx start "$ID-c" 2>"$WORK/err" || fail "a bundle spelling capabilities as libcap does was created, and start failed: $(tail -1 "$WORK/err")"
    capbnd=$(sed -n 's/^CapBnd:[[:space:]]*//p' "/proc/$(pid_of "$ID-c")/status")
    [ "$(bit 13)" = 0 ] && [ "$(bit 27)" = 0 ] || fail "cap_net_raw and 27 got past the drop: CapBnd $capbnd holds NET_RAW or MKNOD"
    fail "a bundle spelling capabilities as libcap does was created (CapBnd $capbnd)"
fi
grep -q 'lists "cap_net_raw", which is not a capability name as the kernel spells it' "$WORK/err" || fail "the refusal does not name the spelling: $(tail -1 "$WORK/err")"
echo "ok: \"cap_net_raw\" and \"27\" are refused, not let past the drop"
spec "" ""

# A requirement refuses a bundle without it, and leaves nothing behind.
nx --profile needs-seccomp create --bundle "$BUNDLE" "$ID-s" 2>"$WORK/err" && fail "a bundle without seccomp passed a profile that requires it"
grep -q "seccompProfile.type: RuntimeDefault" "$WORK/err" || fail "the seccomp refusal does not say how to fix it: $(tail -1 "$WORK/err")"
[ ! -e "/run/crun/$ID-s" ] || fail "a refused create left state behind"
echo "ok: a profile requiring seccomp refuses a bundle without it"
# A filter that lets every call through is a filter only to /proc, where it
# shows as Seccomp: 2 like any other.
spec ', "seccomp": { "defaultAction": "SCMP_ACT_ALLOW" }' ""
rc=0; nx --profile needs-seccomp create --bundle "$BUNDLE" "$ID-sa" 2>"$WORK/err" || rc=$?
[ "$rc" != 0 ] || fail "a seccomp filter that refuses no call passed a profile that requires one"
grep -q "refuses no system call" "$WORK/err" || fail "the refusal does not say why: $(tail -1 "$WORK/err")"
[ ! -e "/run/crun/$ID-sa" ] || fail "a refused create left state behind"
echo "ok: a profile requiring seccomp refuses a filter that refuses no call"

# The filter the profile judges must be the one the kernel enforces. libcrun
# installs run.oci.seccomp_bpf_data, a program compiled elsewhere, in its
# place, for the container and every exec into it; this one loads the arch
# and the call number and lets the call through. First, that the bundle's
# own filter refuses mkdir here, or the second check would prove nothing.
refuses_mkdir=', "seccomp": { "defaultAction": "SCMP_ACT_ALLOW", "syscalls": [ { "names": [ "mkdir", "mkdirat" ], "action": "SCMP_ACT_ERRNO" } ] }'
cat > "$WORK/mkdir.json" <<'JSON'
{ "terminal": false, "user": { "uid": 0, "gid": 0 }, "cwd": "/",
  "env": [ "PATH=/bin:/usr/bin" ],
  "args": [ "/bin/sh", "-c", "mkdir /dev/seccomp-probe 2>/dev/null && echo made || echo refused" ] }
JSON
spec "$refuses_mkdir" ""
nx --profile needs-seccomp create --bundle "$BUNDLE" "$ID-sf" 2>"$WORK/err" && nx start "$ID-sf" 2>>"$WORK/err" || fail "a filter refusing mkdir: $(tail -1 "$WORK/err")"
got=$(nx exec "$ID-sf" --process "$WORK/mkdir.json" 2>&1) || true
[ "$got" = refused ] || fail "the bundle's own filter does not refuse mkdir here, so the precompiled program could not be told apart: exec printed $got"
spec "$refuses_mkdir" ', "annotations": { "run.oci.seccomp_bpf_data": "IAAAAAQAAAAgAAAAAAAAAAYAAAAAAP9/" }'
rc=0; nx --profile needs-seccomp create --bundle "$BUNDLE" "$ID-sb" 2>"$WORK/err" || rc=$?
if [ "$rc" = 0 ]; then
    nx start "$ID-sb" 2>"$WORK/err" || fail "a bundle with run.oci.seccomp_bpf_data was created, and start failed: $(tail -1 "$WORK/err")"
    got=$(nx exec "$ID-sb" --process "$WORK/mkdir.json" 2>&1) || true
    [ "$got" = refused ] || fail "run.oci.seccomp_bpf_data replaced the filter the profile judged: an exec'd mkdir, which that filter refuses, printed $got"
    fail "a bundle with run.oci.seccomp_bpf_data was created under a profile requiring seccomp"
fi
grep -q 'annotation run.oci.seccomp_bpf_data has libcrun install a precompiled program' "$WORK/err" || fail "the refusal does not name the annotation: $(tail -1 "$WORK/err")"
[ ! -e "/run/crun/$ID-sb" ] || fail "a refused create left state behind"
echo "ok: run.oci.seccomp_bpf_data is refused under a profile requiring seccomp; the bundle's own filter refuses mkdir"
spec "" ""
nx --profile needs-userns create --bundle "$BUNDLE" "$ID-u" 2>"$WORK/err" && fail "a bundle without a user namespace passed a profile that requires one"
grep -q "hostUsers: false" "$WORK/err" || fail "the user namespace refusal does not say how to fix it: $(tail -1 "$WORK/err")"
echo "ok: a profile requiring a user namespace refuses a bundle without one"

# A user namespace that leaves the container's root the host's does not
# count: mappings that include host uid 0, or a namespace joined by path that
# is nexcage's own or maps host uid 0. One joined by path that maps neither
# passes, as a pod's containers join the sandbox's: by /proc/<pid>/ns/user
# (containerd) or by a bind mount that pins it (CRI-O). uid_map is read from
# the kernel, in this namespace's terms, where root is 0.
mappings() { echo ", \"uidMappings\": [ { \"containerID\": 0, \"hostID\": $1, \"size\": $2 } ], \"gidMappings\": [ { \"containerID\": 0, \"hostID\": $1, \"size\": $2 } ]"; }
maps_root() { awk '$2 == 0 { found = 1 } END { exit !found }' "/proc/$1/uid_map"; }
uid_map() { tr -s ' \n' ' ' < "/proc/$1/uid_map"; }

spec "$(mappings 0 1)" "" ', { "type": "user" }'
rc=0; nx --profile needs-userns create --bundle "$BUNDLE" "$ID-m" 2>"$WORK/err" || rc=$?
if [ "$rc" = 0 ]; then
    nx start "$ID-m" 2>"$WORK/err" || fail "mappings of host uid 0 passed the profile, and start failed: $(tail -1 "$WORK/err")"
    p=$(pid_of "$ID-m")
    maps_root "$p" && fail "mappings of host uid 0 passed the profile: the container's uid_map is $(uid_map "$p")"
    fail "mappings of host uid 0 passed the profile"
fi
grep -q 'does not map host uid 0, and linux.uidMappings\[0\] maps it' "$WORK/err" || fail "the refusal does not name the mapping: $(tail -1 "$WORK/err")"
echo "ok: a user namespace whose mappings include host uid 0 is refused"

# run.oci.keep_original_groups has libcrun skip setgroups, so the container
# keeps nexcage's own supplementary groups: host gids, which no gid_map
# limits. nexcage gets gid 0 among them here, as it has from a root shell.
command -v setpriv >/dev/null || fail "setpriv (util-linux) is needed to give nexcage a supplementary group"
spec "$(mappings 1 65536)" ', "annotations": { "run.oci.keep_original_groups": "1" }' ', { "type": "user" }'
rc=0; setpriv --groups 0 "$NEXCAGE" --config "$CFG" --profile needs-userns create --bundle "$BUNDLE" "$ID-g" 2>"$WORK/err" || rc=$?
if [ "$rc" = 0 ]; then
    nx start "$ID-g" 2>"$WORK/err" || fail "a bundle keeping nexcage's groups passed the profile, and start failed: $(tail -1 "$WORK/err")"
    groups=$(sed -n 's/^Groups:[[:space:]]*//p' "/proc/$(pid_of "$ID-g")/status")
    case " $groups " in
        *" 0 "*) fail "run.oci.keep_original_groups passed the profile: the container holds host gid 0 (Groups: $groups), which its gid_map leaves out" ;;
    esac
    fail "a bundle keeping nexcage's groups passed the profile (Groups: $groups)"
fi
grep -q 'annotation run.oci.keep_original_groups keeps nexcage' "$WORK/err" || fail "the refusal does not name the annotation: $(tail -1 "$WORK/err")"
[ ! -e "/run/crun/$ID-g" ] || fail "a refused create left state behind"
echo "ok: run.oci.keep_original_groups is refused under a required user namespace"

# Two sandboxes made without a profile: one mapping host uid 0, one not.
spec "$(mappings 0 1)" "" ', { "type": "user" }'
nx --runtime crun create --bundle "$BUNDLE" "$ID-h0" 2>"$WORK/err" && nx start "$ID-h0" 2>>"$WORK/err" || fail "a sandbox mapping host uid 0: $(tail -1 "$WORK/err")"
spec "$(mappings 1 65536)" "" ', { "type": "user" }'
nx --runtime crun create --bundle "$BUNDLE" "$ID-h1" 2>"$WORK/err" && nx start "$ID-h1" 2>>"$WORK/err" || fail "a sandbox with a user namespace of its own: $(tail -1 "$WORK/err")"
h0=$(pid_of "$ID-h0"); h1=$(pid_of "$ID-h1")
maps_root "$h0" || fail "the sandbox meant to map host uid 0 does not: $(uid_map "$h0")"
! maps_root "$h1" || fail "the sandbox meant to leave host uid 0 out maps it: $(uid_map "$h1")"
joining() { spec "$(mappings 1 65536)" "" ", { \"type\": \"user\", \"path\": \"$1\" }"; }

joining "/proc/$h0/ns/user"
rc=0; nx --profile needs-userns create --bundle "$BUNDLE" "$ID-j0" 2>"$WORK/err" || rc=$?
if [ "$rc" = 0 ]; then
    nx start "$ID-j0" 2>"$WORK/err" || fail "joining a namespace that maps host uid 0 passed the profile, and start failed: $(tail -1 "$WORK/err")"
    p=$(pid_of "$ID-j0")
    maps_root "$p" && fail "joining a namespace that maps host uid 0 passed the profile: the container's uid_map is $(uid_map "$p")"
    fail "joining a namespace that maps host uid 0 passed the profile"
fi
grep -q "the one the bundle joins, /proc/$h0/ns/user, maps it" "$WORK/err" || fail "the refusal does not say why: $(tail -1 "$WORK/err")"
echo "ok: joining a user namespace that maps host uid 0 is refused"

# pid 1 here shares nexcage's user namespace, as init does on a host.
joining "/proc/1/ns/user"
nx --profile needs-userns create --bundle "$BUNDLE" "$ID-o" 2>"$WORK/err" && fail "joining nexcage's own user namespace passed the profile"
grep -q "which is nexcage's" "$WORK/err" || fail "the refusal does not say why: $(tail -1 "$WORK/err")"
echo "ok: joining nexcage's own user namespace is refused"

joined() {
    nx --profile needs-userns create --bundle "$BUNDLE" "$1" 2>"$WORK/err" || fail "a container joining a sandbox's user namespace by $2 was refused: $(tail -1 "$WORK/err")"
    nx start "$1" 2>"$WORK/err" || fail "start, joining by $2: $(tail -1 "$WORK/err")"
    p=$(pid_of "$1")
    [ "$(readlink "/proc/$p/ns/user")" = "$(readlink "/proc/$h1/ns/user")" ] || fail "the container joined by $2 is not in the sandbox's user namespace"
    ! maps_root "$p" || fail "the container joined by $2 maps host uid 0: $(uid_map "$p")"
    echo "ok: joining a sandbox's user namespace by $2 passes, uid_map $(uid_map "$p")"
}
joining "/proc/$h1/ns/user"
joined "$ID-j1" "/proc/<pid>/ns/user"
touch "$WORK/userns-pin"
if mount --bind "/proc/$h1/ns/user" "$WORK/userns-pin" 2>/dev/null; then
    joining "$WORK/userns-pin"
    joined "$ID-jp" "a bind mount that pins it"
else
    echo "skipped: this container cannot bind-mount a namespace, so CRI-O's pinned form is not checked"
fi
spec "" ""

# A profile that is not defined is an error, not the plain handler.
rc=0; nx --profile nope create --bundle "$BUNDLE" "$ID-n" 2>"$WORK/err" || rc=$?
[ "$rc" = 2 ] || fail "an undefined profile exited $rc, not 2"
grep -q "profile 'nope' is not defined" "$WORK/err" || fail "the undefined profile is not named: $(tail -1 "$WORK/err")"
echo "ok: an undefined profile exits 2"

# The bundle cannot claim a profile for itself, under one or under none:
# `state` would report a profile nothing applied.
spec "" ', "annotations": { "io.cageforge.nexcage.profile": "hardened" }'
nx --profile hardened create --bundle "$BUNDLE" "$ID-a" 2>"$WORK/err" && fail "a bundle carrying the profile annotation was accepted"
grep -q "which nexcage writes itself" "$WORK/err" || fail "the annotation refusal does not say why: $(tail -1 "$WORK/err")"
nx --runtime crun create --bundle "$BUNDLE" "$ID-a" 2>"$WORK/err" && fail "a bundle claiming a profile was accepted without one"
grep -q "which nexcage writes itself" "$WORK/err" || fail "the annotation refusal without a profile does not say why: $(tail -1 "$WORK/err")"
echo "ok: a bundle carrying io.cageforge.nexcage.profile is refused, with a profile or without"

echo "PASS: a profile narrows the bundle, and the kernel shows it"
