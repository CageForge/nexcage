#!/usr/bin/env bash
# Runs every nexcage command against the fake Proxmox tools in tests/sim/bin
# and checks what nexcage asks of them, what it prints and how it exits.
#
#   zig build && tests/sim/run.sh        # or: make sim
#
# nexcage runs as uid 0 in its own user and mount namespace. /run and
# /tmp/nexcage-bundles are bound to a scratch directory and a tmpfs covers
# /tmp, so nexcage writes /run/nexcage without root and without touching the
# host. Any allocator leak report, panic or invalid free fails the run.
#
# NEXCAGE  binary to test (default zig-out/bin/nexcage, a Debug build)
# SIM_DIR  scratch directory (default zig-out/sim); not under /tmp
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)
export BIN=$HERE/bin
export NEXCAGE=${NEXCAGE:-$REPO/zig-out/bin/nexcage}
export SIM=${SIM_DIR:-$REPO/zig-out/sim}
S=$SIM
PASS=0; FAIL=0; LEAKS=0
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
  rm -f "$S"/fail_* "$S/pvever" "$S"/lock.* "$S"/conf.* "$S"/tarlist.* "$S"/sig.*
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
nx() {
  local before; before=$(wc -l < "$S/calls")
  nexcage_ns "$@" > "$S/out" 2> "$S/err"; RC=$?
  tail -n +"$((before + 1))" "$S/calls" > "$S/calls.last"
  LAST="nexcage $*"
  if grep -qE "error\(gpa\)|leaked|panic|Segmentation fault|Invalid free|reached unreachable" "$S/err"; then
    LEAKS=$((LEAKS + 1)); echo "!!    runtime error/leak in: $LAST"; sed 's/^/        /' "$S/err" | head -20
  fi
}
check() {
  local name=$1; shift
  if "$@"; then echo "PASS  $name"; PASS=$((PASS + 1))
  else
    echo "FAIL  $name"; FAIL=$((FAIL + 1))
    echo "        last: $LAST  (rc=$RC)"
    echo "        stdout: $(head -c 300 "$S/out" | tr '\n' '|')"
    echo "        stderr: $(head -c 400 "$S/err" | tr '\n' '|')"
    echo "        calls:  $(tr '\n' '|' < "$S/calls.last")"
  fi
}
# Conditions for check; `all` takes several as strings
rc()        { [ "$RC" = "$1" ]; }
out_has()   { grep -qF -- "$1" "$S/out"; }
err_has()   { grep -qiF -- "$1" "$S/err"; }
called()    { grep -qxF -- "$1" "$S/calls.last"; }
called_re() { grep -qE -e "$1" "$S/calls.last"; }
not_called_re() { ! grep -qE -e "$1" "$S/calls.last"; }
all() { local c; for c in "$@"; do eval "$c" || return 1; done; }
json_ok()   { python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$1" 2>/dev/null; }
# Every line a JSON object, and at least one of them an error: what a container
# engine opens this file to find.
json_lines_have_error() {
  python3 - "$1" <<'PYEOF' 2>/dev/null
import json, sys
lines = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
sys.exit(0 if any(o.get("level") == "error" for o in lines) else 1)
PYEOF
}
json_get()  { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$1" "$2" 2>/dev/null; }
# NAMES is the last column, after NODE was added for the cluster.
listed()    { awk -F'\t' -v n="$1" 'NR>1 && $8==n {f=1} END {exit !f}' "$S/out"; }
status_is() { nx state "$1"; [ "$RC" = 0 ] && [ "$(json_get "$S/out" status)" = "$2" ]; }
init_pid()  { cat "$S/pid.$1" 2>/dev/null; }
# Signal handlers and process exit are asynchronous: allow them 3 seconds
got_signal() { local i; for i in $(seq 1 30); do grep -qx "$2" "$S/sig.$1" 2>/dev/null && return 0; sleep 0.1; done; return 1; }
eventually() { local i; for i in $(seq 1 30); do eval "$1" && return 0; sleep 0.1; done; return 1; }

echo "=== global ==="
reset_sim
nx;            check "no args prints usage, exit 0"      all 'rc 0' 'out_has "Commands:"'
nx --help;     check "--help prints usage"               all 'rc 0' 'out_has "Commands:"'
nx -h;         check "-h prints usage"                   all 'rc 0' 'out_has "Commands:"'
nx version;    check "version prints a version"          all 'rc 0' 'out_has "nexcage version "'
nx help;       check "help lists commands"               all 'rc 0' 'out_has "create"'
nx bogus;      check "unknown command -> exit 2"         all 'rc 2' 'err_has "unknown command"'
for c in create start stop delete list state kill run version help health; do
  nx "$c" --help; check "$c --help exits 0 without touching pct" all 'rc 0' '[ -s "$S/out" ]' 'not_called_re "^pct"'
done
nx version --help; check "version --help prints help, not the version" all 'rc 0' 'out_has "Usage: nexcage version"'
nx health --help;  check "health --help prints help, runs no checks"   all 'rc 0' 'out_has "Usage: nexcage health"' '[ ! -s "$S/calls.last" ]'
nx --debug list; check "--debug before command still runs list" all 'rc 0' 'out_has "NAMES"'

echo "=== create ==="
reset_sim
cfg '{"network":{"bridge":"vmbr50"},"proxmox":{"storage":"local-lvm","rootfs_size_gb":2}}'
nx create --name web-1 "$TPL"
check "create from template exits 0" rc 0
check "create checks the name across the cluster first, then asks for a VMID" \
  all 'called "pvesh get /cluster/resources --type vm --output-format json"' \
      'called "pvesh get /cluster/nextid"'
check "pct create argv: vmid, template, hostname, bridge, rootfs from config" \
  called_re "^pct create 100 $TPL --hostname web-1 --memory [0-9]+ --cores [0-9]+ --net0 name=eth0,bridge=vmbr50,ip=dhcp --unprivileged 1 --rootfs local-lvm:2$"
check "no --ostype unless configured" not_called_re "--ostype"
check "state.json written, valid, status created" \
  all 'json_ok "$S/run/nexcage/web-1/state.json"' '[ "$(json_get "$S/run/nexcage/web-1/state.json" status)" = created ]'
check "runtime-metadata.json valid, vmid 100" \
  all 'json_ok "$S/run/nexcage/web-1/runtime-metadata.json"' '[ "$(json_get "$S/run/nexcage/web-1/runtime-metadata.json" vmid)" = 100 ]'

nx create --name web-1 "$TPL"
check "duplicate name -> exit 1, no second pct create" all 'rc 1' 'err_has "already exists"' 'not_called_re "^pct create"'
nx create --name bad_name "$TPL";  check "invalid hostname (underscore) -> exit 2" all 'rc 2' 'not_called_re "^pct create"'
nx create --name -lead "$TPL";     check "invalid hostname (leading dash) -> refused" all '[ "$RC" != 0 ]' 'not_called_re "^pct create"'
nx create "$TPL";                  check "missing --name -> exit 2" all 'rc 2' 'not_called_re "^pct"'
nx create --name web-x;            check "missing image -> exit 2" all 'rc 2' 'not_called_re "^pct"'

nx create --name web-2 --image "$TPL"
check "--image form shown in 'create --help' works" all 'rc 0' "called_re '^pct create 101 $TPL --hostname web-2 '"
nx create --name web-3 debian-12.tar.zst
check "bare .tar.zst name -> local:vztmpl/<name>" all 'rc 0' 'called_re "^pct create 102 local:vztmpl/debian-12.tar.zst --hostname web-3 "'
nx create --name web-4 local:vztmpl/alpine-3.22-default_20250617_amd64.tar.xz
check ".tar.xz template passes through unchanged" all 'rc 0' 'called_re "^pct create 103 local:vztmpl/alpine-3.22-default_20250617_amd64.tar.xz "'

echo "unable to create CT 104 - some pct failure" > "$S/fail_create"
nx create --name web-5 "$TPL"
check "pct create failing -> exit 1, no state dir left" all 'rc 1' '[ ! -e "$S/run/nexcage/web-5" ]'
rm -f "$S/fail_create"

nx create --name nginx-1 docker.io/library/nginx:latest
check "registry image on PVE 8.4 -> exit 1 with a version message, nothing pulled" \
  all 'rc 1' 'err_has "9.1"' 'not_called_re "^pvesh create"' 'not_called_re "^pct create"'
echo 9.1.0 > "$S/pvever"
nx create --name nginx-1 docker.io/library/nginx:latest
check "registry image on PVE 9.1 -> pvesh oci-registry-pull, then an unprivileged pct create with the .tar" \
  all 'rc 0' "called 'pvesh create /nodes/$(hostname)/storage/local/oci-registry-pull --reference docker.io/library/nginx:latest'" \
      'called_re "^pct create [0-9]+ local:vztmpl/nginx_latest.tar --hostname nginx-1 .*--unprivileged 1( |$)"' 'not_called_re "--ostype"'
cfg '{"network":{"bridge":"vmbr50"},"proxmox":{"storage":"local-lvm","rootfs_size_gb":2,"unprivileged":false}}'
nx create --name redis-1 docker.io/library/redis:7
check "registry image with unprivileged=false: no --unprivileged 0, which pct rejects, and a warning" \
  all 'rc 0' 'called_re "^pct create [0-9]+ local:vztmpl/redis_7.tar --hostname redis-1 "' 'not_called_re "--unprivileged"' 'err_has "always run unprivileged"'
cfg '{"network":{"bridge":"vmbr50"},"proxmox":{"storage":"local-lvm","rootfs_size_gb":2}}'
touch "$S/fail_pull"
nx create --name nginx-2 docker.io/library/nginx:1.27
check "registry pull failing -> exit 1, no pct create" all 'rc 1' 'not_called_re "^pct create"'
rm -f "$S/fail_pull"
# Reuse before pull: nginx:latest went onto the storage a few checks ago, so a
# second create from the same reference must take it from there. It used to
# call the endpoint every time and then guess the volid from the reference.
nx create --name nginx-3 docker.io/library/nginx:latest
check "a registry image already on the storage is reused, not pulled again" \
  all 'rc 0' 'not_called_re "oci-registry-pull"' 'called_re "^pct create [0-9]+ local:vztmpl/nginx_latest\.tar "'
# --storage names where the pull lands, as it does for `pull`, and what pct is
# given is what that storage holds afterwards.
nx create --name nginx-4 --storage shared-rdma docker.io/library/nginx:1.26
check "create --storage pulls into that storage and creates from what it holds" \
  all 'rc 0' 'called_re "^pvesh create /nodes/[^/]+/storage/shared-rdma/oci-registry-pull --reference docker.io/library/nginx:1.26"' \
      'called_re "^pct create [0-9]+ shared-rdma:vztmpl/nginx_1\.26\.tar "'
rm -f "$S/fail_pull" "$S/pvever"

cfg '{"network":{"bridge":"vmbr50"},"proxmox":{"storage":"local-lvm","ostype":"debian","unprivileged":true}}'
nx create --name web-6 "$TPL"
check "ostype/unprivileged from config reach pct" all 'rc 0' 'called_re "--ostype debian --unprivileged 1 --rootfs local-lvm:[0-9]+$"'
cfg '{"network":{"bridge":"vmbr50"},"proxmox":{"storage":"local-lvm","unprivileged":false}}'
nx create --name web-6b "$TPL"
check "unprivileged=false in config -> --unprivileged 0" all 'rc 0' 'called_re "--hostname web-6b .*--unprivileged 0 --rootfs local-lvm:[0-9]+$"'
rm -f "$S/work/config.json"
nx create --name web-7 "$TPL"
check "no config file -> default bridge, unprivileged, no --rootfs" all 'rc 0' 'called_re "bridge=vmbr0,ip=dhcp --unprivileged 1$"'

echo "pct list: Permission denied" > "$S/fail_all"
nx create --name web-8 "$TPL"
check "the host unable to answer -> create refuses (not read as 'name free')" all 'rc 1' 'err_has "permission denied"' 'not_called_re "^pct create"'
rm -f "$S/fail_all"

echo "=== state ==="
nx state web-1
check "state of created container: exit 0, stdout is pure JSON" all 'rc 0' 'json_ok "$S/out"'
check "state of a container never started: id, status created, pid 0, ociVersion" \
  all '[ "$(json_get "$S/out" id)" = web-1 ]' '[ "$(json_get "$S/out" status)" = created ]' '[ "$(json_get "$S/out" pid)" = 0 ]' '[ "$(json_get "$S/out" ociVersion)" = 1.0.0 ]'
nx state 100;  check "state by VMID works" all 'rc 0' '[ "$(json_get "$S/out" status)" = created ]'
nx state nope; check "state of missing container -> exit 1, not found" all 'rc 1' 'err_has "not found"'
nx state;      check "state without name -> exit 2" rc 2
echo "backup" > "$S/lock.100"
nx state web-1; check "locked container still resolves by name" all 'rc 0' '[ "$(json_get "$S/out" id)" = web-1 ]'
rm -f "$S/lock.100"
echo "Permission denied" > "$S/fail_all"
nx state web-1; check "state with the host failing -> exit 1, the tool's message logged" all 'rc 1' 'err_has "permission denied"' 'err_has "pct command failed"'
rm -f "$S/fail_all"

echo "=== list ==="
nx list
check "list: header + row with the name in the last column" all 'rc 0' 'out_has "NAMES"' 'listed web-1'
check "list row fields: vmid/status/backend/node" awk -F'\t' '$8=="web-1" && $1=="100" && $5=="stopped" && $6=="proxmox-lxc" && $7!="" {f=1} END {exit !f}' "$S/out"
echo "backup" > "$S/lock.101"
nx list; check "list with a locked container keeps the right name" all 'listed web-2' '! listed backup'
rm -f "$S/lock.101"
echo "Permission denied" > "$S/fail_all"
nx list; check "list with the host failing -> exit 1 with the reason, not an empty list" all 'rc 1' 'err_has "permission denied"' '! out_has "NAMES"'
rm -f "$S/fail_all"

echo "=== start ==="
nx start web-1
check "start exits 0, runs pct start 100" all 'rc 0' 'called "pct start 100"'
check "state.json -> running, with the init's host PID" \
  all '[ "$(json_get "$S/run/nexcage/web-1/state.json" status)" = running ]' '[ "$(json_get "$S/run/nexcage/web-1/state.json" pid)" = "$(init_pid 100)" ]'
status_is web-1 running
check "state reports running with the init's host PID from pct status --verbose" \
  all 'rc 0' '[ "$(json_get "$S/out" status)" = running ]' '[ "$(json_get "$S/out" pid)" = "$(init_pid 100)" ]' 'called "pct status 100 --verbose"'
nx start web-1;  check "start an already running container -> exit 1" rc 1
nx start nope;   check "start missing -> exit 1, not found" all 'rc 1' 'err_has "not found"'
nx start;        check "start without name -> exit 2" rc 2
nx start --name web-2; check "start --name <id> (form in 'start --help')" all 'rc 0' 'called "pct start 101"'

echo "=== kill ==="
# The fake init records every signal it catches, so these check delivery
nx kill web-1;                 check "kill: default SIGTERM reaches the init, PID from pct status --verbose" \
                                 all 'rc 0' 'got_signal 100 SIGTERM' 'called "pct status 100 --verbose"'
nx kill -s hup web-1;          check "kill -s hup <name> (any case, SIG prefix optional)" all 'rc 0' 'got_signal 100 SIGHUP'
nx kill --signal SIGINT web-1; check "kill --signal SIGINT <name>"    all 'rc 0' 'got_signal 100 SIGINT'
nx kill web-1 10;              check "kill <name> 10 (runc form, a number)" all 'rc 0' 'got_signal 100 SIGUSR1'
nx kill web-1 --signal USR2;   check "kill <name> --signal USR2"      all 'rc 0' 'got_signal 100 SIGUSR2'
check "kill never runs pct exec" all '! grep -q "^pct exec" "$S/calls"'
check "the init survives the signals it handles" status_is web-1 running
nx kill web-1 'TERM;id';       check "kill: bad signal -> exit 2, nothing sent" all 'rc 2' 'err_has "unknown signal"' 'not_called_re "^pct"'
nx kill web-1 0;               check "kill: signal 0 -> exit 2"       all 'rc 2' 'not_called_re "^pct"'
nx kill web-1 65;              check "kill: signal 65 -> exit 2"      all 'rc 2' 'not_called_re "^pct"'
nx kill nope;                  check "kill missing -> exit 1"         rc 1
nx kill;                       check "kill without name -> exit 2"    rc 2
nx kill web-3;                 check "kill a stopped container -> exit 1, says it is not running" all 'rc 1' 'err_has "not running"'
nx run --name kill-1 "$TPL"
nx kill kill-1 KILL
check "kill KILL: the init dies and the container stops" all 'rc 0' "eventually 'status_is kill-1 stopped'"

echo "=== exec ==="
nx exec web-1 echo hello;      check "exec runs the command and its output reaches stdout" \
                                 all 'rc 0' 'out_has hello' 'called "pct exec 100 -- echo hello"'
nx exec web-1 sh -c 'exit 7';  check "exec exits with the status of the command, as runc does" rc 7
nx exec web-1 -- echo dashed;  check "exec <name> -- <cmd>: the separator is not passed to pct" \
                                 all 'rc 0' 'out_has dashed' 'called "pct exec 100 -- echo dashed"'
nx exec web-1 -- sh -c 'echo x 1>&2; exit 3'
                               check "exec: stderr passes through and a non-zero status survives it" all 'rc 3' 'err_has x'
nx exec nope echo hi;          check "exec on a missing container -> exit 1, nothing run" \
                                 all 'rc 1' 'not_called_re "^pct exec"'

# A container engine writes a flag either way, and the choice is not ours:
# containerd sends `--root <dir>`, CRI-O sends `--root=<dir>`. CRI-O's first
# call came back as `unknown command '--root=/run/nexcage-crio'`.
nx --root=/tmp/sim-root-eq state web-1
check "--flag=value is a flag, not a command name" all 'rc 0' 'out_has "\"id\": \"web-1\""'
nx --version
check "--version, which is how CRI-O asks" all 'rc 0' 'out_has "nexcage version"'
# ...and the splitting stops at `--`: what follows belongs to the command run
# inside the container, where FOO=bar is an argument and not a flag.
nx exec web-1 -- env FOO=bar
check "an = after -- survives untouched" \
  all 'rc 0' 'called "pct exec 100 -- env FOO=bar"'

# `exec --process <file>` hands over an OCI process spec: an identity to become,
# an environment, a terminal. `pct exec` takes a command and returns when it
# ends, so the spec cannot be honoured and ignoring it would run the command as
# somebody else. Refusing is the same rule as --console-socket on this backend.
printf '{"args":["/bin/true"],"cwd":"/"}' > /tmp/sim-process.json
nx exec web-1 --process /tmp/sim-process.json
check "exec --process is refused on the LXC backend, not ignored" \
  all 'rc 1' 'err_has "--runtime crun"' 'not_called_re "^pct exec"'
nx exec web-1 -d echo hi
check "exec --detach is refused on the LXC backend" \
  all 'rc 1' 'err_has "--detach"' 'not_called_re "^pct exec"'
nx exec web-1 --process /tmp/sim-process.json ls
# 2, not 1: giving both is a usage error, and nexcage keeps that distinction.
check "exec takes a command or --process, not both" all 'rc 2' 'err_has "not both"'

# Kubernetes asks for `ps --format json`, which was answered with `unknown
# command 'ps'` -- containerd says nothing about that in its journal and the pod
# runs anyway, so only the runtime's own command lines showed it.
nx ps web-1
check "ps is refused on the LXC backend, where it would answer another question" \
  all 'rc 1' 'err_has "--runtime crun"' 'not_called_re "^pct"'
# With --log the explanation goes to that file rather than to stderr, which is
# what --log is for; only the terse summary line stays on stderr. Checking
# stderr for it, as this did at first, fails on correct behaviour.
# The log goes under /run, which is bind-mounted from $S: the sandbox mounts a
# fresh tmpfs on /tmp, so a file written there disappears with the namespace and
# the check cannot see it.
rm -f "$S/run/nexcage-ps.log"
nx --root /run/x --log /run/nexcage-ps.log --log-format json ps --format json web-1
check "the shape containerd sends is read as ps, not as a command name" \
  all 'rc 1' '! err_has "unknown command"' 'grep -q "runtime crun" "$S/run/nexcage-ps.log"'
nx --runtime crun ps --format yaml web-1
check "ps --format takes json or table" all 'rc 2' 'err_has "json or table"'
nx ps --help
check "ps --help says whose PIDs these are" all 'rc 0' 'out_has "host PIDs"'
nx exec web-3 echo hi;         check "exec on a stopped container -> exit 1, says it is not running" \
                                 all 'rc 1' 'err_has "not running"' 'not_called_re "^pct exec"'
nx exec web-1;                 check "exec without a command -> exit 2" all 'rc 2' 'not_called_re "^pct exec"'
nx exec;                       check "exec without a name -> exit 2"    rc 2

echo "=== stop ==="
nx stop web-1
check "stop: pct shutdown 100 --timeout 60 --forceStop 1" all 'rc 0' 'called "pct shutdown 100 --timeout 60 --forceStop 1"'
check "state.json -> stopped, fake init gone" all '[ "$(json_get "$S/run/nexcage/web-1/state.json" status)" = stopped ]' '[ ! -e "$S/pid.100" ]'
check "state reports stopped, pid 0" all 'status_is web-1 stopped' '[ "$(json_get "$S/out" pid)" = 0 ]'
nx stop web-1;  check "stop an already stopped container -> exit 1" rc 1
nx stop nope;   check "stop missing -> exit 1" rc 1
nx stop;        check "stop without name -> exit 2" rc 2

echo "=== delete ==="
nx delete web-2
check "delete a running container -> exit 1, still listed" all 'rc 1' 'grep -q " web-2$" "$S/db"'
nx delete web-1
check "delete: pct destroy 100, exit 0" all 'rc 0' 'called "pct destroy 100"'
check "delete removes /run/nexcage/web-1" all '[ ! -e "$S/run/nexcage/web-1" ]'
nx state web-1;  check "state after delete -> exit 1" rc 1
nx list;         check "list after delete has no row" all 'rc 0' '! listed web-1'
nx start web-1;  check "start after delete -> exit 1" rc 1
nx delete nope;  check "delete missing -> exit 1" rc 1
nx delete;       check "delete without name -> exit 2" rc 2

echo "=== run ==="
cfg '{"network":{"bridge":"vmbr50"},"proxmox":{"storage":"local-lvm","rootfs_size_gb":2}}'
nx run --name app-1 "$TPL"
check "run: create then start the same VMID" all 'rc 0' 'called_re "^pct create ([0-9]+) .*--hostname app-1 "' \
  "grep -q \"^pct start \$(awk '\$3==\"app-1\" {print \$1}' \$S/db)\$\" \"\$S/calls.last\""
check "run: rootfs/bridge from config" called_re "bridge=vmbr50,ip=dhcp .*--rootfs local-lvm:2$"
check "run: state reports running" status_is app-1 running
nx run --name app-1 "$TPL"; check "run duplicate -> exit 1, no start" all 'rc 1' 'not_called_re "^pct start"'
nx run --name app-2;        check "run without image -> exit 2" rc 2

echo "=== option parsing ==="
nx start --log-level debug web-3
check "start --log-level debug <name> starts <name>" all 'rc 0' 'called "pct start 102"'
nx stop web-3 --log-file /dev/null
check "stop <name> --log-file <path>" all 'rc 0' 'called_re "^pct shutdown 102 "'
nx state --log-level info web-3
check "state --log-level info <name>" all 'rc 0' '[ "$(json_get "$S/out" id)" = web-3 ]'

echo "=== --runtime ==="
nx create --runtime lxc --name rt-0 "$TPL"
check "--runtime lxc creates through pct" all 'rc 0' 'called_re "^pct create [0-9]+ .*--hostname rt-0 "'
nx create --runtime crun --name rt-1 "$TPL"
check "--runtime crun on a build without crun -> exit 1, nothing created" all 'rc 1' 'err_has "not built"' 'not_called_re "^pct create"'
nx start --runtime vm rt-0
check "--runtime vm -> exit 1 (not implemented), not a silent success" all 'rc 1' 'err_has "not implemented"' 'not_called_re "^pct start"'
nx create --name rt-2 --runtime bogus "$TPL"
check "unknown --runtime -> exit 2, nothing run" all 'rc 2' 'err_has "unknown runtime"' 'not_called_re "^pct"'
nx state --runtime crun rt-0
check "state --runtime crun -> exit 1, no made-up state" all 'rc 1' '[ ! -s "$S/out" ]'

echo "=== --config ==="
printf '%s\n' '{"network":{"bridge":"vmbr77"},"proxmox":{"storage":"alt-store","rootfs_size_gb":3}}' > "$S/work/alt.json"
nx create --config alt.json --name cf-1 "$TPL"
check "--config <file> after the command wins over ./config.json" \
  all 'rc 0' 'called_re "^pct create [0-9]+ .*--hostname cf-1 .*bridge=vmbr77,ip=dhcp .*--rootfs alt-store:3$"'
nx --config "$S/work/alt.json" create --name cf-2 "$TPL"
check "--config before the command, absolute path" all 'rc 0' 'called_re "--hostname cf-2 .*bridge=vmbr77,ip=dhcp"'
nx --config missing.json list
check "--config with a missing file -> exit 1, names the file, runs nothing" all 'rc 1' 'err_has "missing.json"' 'not_called_re "^pct"'
printf '{"network":' > "$S/work/bad.json"
nx list --config bad.json
check "--config with invalid JSON -> exit 1" all 'rc 1' 'err_has "invalid configuration"' 'not_called_re "^pct"'
nx list --config
check "--config without a path -> exit 2" all 'rc 2' 'err_has "--config needs a path"'

echo "=== create from an OCI bundle ==="
mkdir -p "$S/bundles/b1/rootfs/bin" "$S/bundles/nocfg/rootfs"
printf '#!/bin/sh\n' > "$S/bundles/b1/rootfs/bin/busybox"; chmod 755 "$S/bundles/b1/rootfs/bin/busybox"
ln -s busybox "$S/bundles/b1/rootfs/bin/sh"
cat > "$S/bundles/b1/config.json" <<'JSON'
{"ociVersion":"1.0.2","hostname":"b1","process":{"args":["/bin/sh"],"cwd":"/"},"root":{"path":"rootfs"},
 "linux":{"namespaces":[{"type":"pid"},{"type":"user"}]}}
JSON
nx create --name bundle-0 ./relative-bundle
check "a relative bundle path -> exit 2: the engine's working directory is not ours" \
  all 'rc 2' 'err_has "absolute"' 'not_called_re "^pct create"'
nx create --name bundle-e /run/engine-bundles/b1
check "a bundle outside nexcage's own directories is accepted and then fails on its contents" \
  all 'rc 2' '! err_has "must be an absolute path"' 'not_called_re "^pct create"'
nx create --name bundle-x /tmp/nexcage-bundles/nocfg
check "bundle without config.json -> exit 2, no crash" all 'rc 2' 'err_has "config.json"' 'not_called_re "^pct create"'
nx create --name bundle-1 /tmp/nexcage-bundles/b1
check "bundle: rootfs packed on storage local, pct create uses that volume" \
  all 'rc 0' 'called_re "^pvesm path local:vztmpl/nexcage-bundle-1-[0-9]+\.tar\.zst$"' \
      'called_re "^pct create [0-9]+ local:vztmpl/nexcage-bundle-1-[0-9]+\.tar\.zst --hostname bundle-1 "' \
      '! err_has "No mp entries"'
check "bundle: archive keeps the executable bit and symlinks" \
  all 'grep -qE "^-rwxr-xr-x .* \./bin/busybox$" "$S"/tarlist.*' 'grep -qE "^lrwxrwxrwx .* \./bin/sh -> busybox$" "$S"/tarlist.*'
check "bundle: archive removed after pct create" all '[ -z "$(ls -A "$S/cache")" ]'
check "bundle: user namespace -> pct set --features nesting=1,keyctl=1" called_re "^pct set [0-9]+ --features nesting=1,keyctl=1$"

echo "=== runtime-spec command line ==="
# What a container engine sends: the id positionally, the bundle behind
# --bundle, its own state directory behind --root.
nx create spec-1 --bundle /tmp/nexcage-bundles/b1
check "create <id> --bundle <dir>: the positional word is the id, not the image" \
  all 'rc 0' 'called_re "^pct create [0-9]+ local:vztmpl/nexcage-spec-1-[0-9]+\.tar\.zst --hostname spec-1 "'
nx state spec-1
check "state reports the bundle the container was created from" \
  all 'rc 0' '[ "$(json_get "$S/out" bundle)" = /tmp/nexcage-bundles/b1 ]'
nx start spec-1; nx state spec-1
check "start keeps the bundle in state" all 'rc 0' '[ "$(json_get "$S/out" bundle)" = /tmp/nexcage-bundles/b1 ]'
nx create tpl-1 --bundle /tmp/nexcage-bundles/b1 >/dev/null 2>&1 || true
nx create --name from-tpl "$TPL"; nx state from-tpl
check "a container created from a template reports bundle null" \
  all 'rc 0' 'grep -q "\"bundle\": null" "$S/out"'

nx --root /run/alt list
check "--root before the command is not read as the command" all 'rc 0' '! err_has "unknown command"'
nx create --root /run/alt --name rooted-1 "$TPL"
check "--root: state goes under the given directory, not /run/nexcage" \
  all 'rc 0' '[ -f "$S/run/alt/rooted-1/state.json" ]' '[ ! -e "$S/run/nexcage/rooted-1" ]'
nx --root relative list
check "--root with a relative path -> exit 2" all 'rc 2' 'err_has "absolute"'
nx --root
check "--root without a value -> exit 2" rc 2

nx --runtime lxc state from-tpl
check "--runtime before the command routes, instead of being dropped" all 'rc 0' '! err_has "unknown command"'
nx --runtime bogus state from-tpl
check "--runtime bogus before the command -> exit 2, no leak" rc 2

# What containerd puts before the command. --log used to be taken for the
# command name, so the engine's very first call answered "unknown command".
# A container engine runs the runtime from the bundle directory, and a bundle
# holds a config.json that is an OCI spec. It used to be read as nexcage's own
# configuration, silently replacing it — routing rules included.
printf '{"ociVersion":"1.0.0","process":{"args":["/bin/sh"]},"root":{"path":"rootfs"}}' > "$S/work/config.json"
nx list
check "an OCI spec in the search path is not read as nexcage's config" \
  all 'rc 0' '! err_has "SyntaxError"' '! err_has "invalid configuration"'
nx --config "$S/work/config.json" list
check "an OCI spec named with --config is refused, not silently ignored" \
  all 'rc 1' 'err_has "invalid configuration"'
rm -f "$S/work/config.json"

# Routing by name (ADR-001). A glob under runtime.routing is the matcher
# crun_name_patterns used to be, so the proof is both directions of one rule:
# a matching name reaches the crun backend and a non-matching one reaches pct.
cfg '{"runtime":{"routing":[{"pattern":"kube-ovn-*","runtime":"crun"}]}}'
nx state kube-ovn-1
check "a glob under runtime.routing sends a matching name to crun" \
  all 'rc 1' 'err_has "not built into this binary"' 'not_called_re "^pct"'
nx state from-tpl
check "and a name it does not match goes to Proxmox LXC" \
  all 'rc 0' 'called_re "^pct"'
# The removed key is ignored -- and says so, because a container it used to
# send to crun now lands on the default backend.
cfg '{"container_config":{"crun_name_patterns":["kube-ovn-*"]}}'
nx state kube-ovn-1
check "crun_name_patterns no longer routes, and the warning names runtime.routing" \
  all 'rc 1' 'called_re "^pct"' 'err_has "crun_name_patterns is ignored"' 'err_has "runtime.routing"'
rm -f "$S/work/config.json"

# No runc backend since 0.13.0. A rule that still names it describes an OCI
# container, so it goes to crun -- and is said, since the file should change.
cfg '{"runtime":{"routing":[{"pattern":"*","runtime":"runc"}]}}'
nx state from-tpl
check "a routing rule naming runc goes to crun, with a warning that says so" \
  all 'rc 1' 'err_has "not built into this binary"' 'err_has "runc is not a backend"' 'not_called_re "^pct"'
rm -f "$S/work/config.json"
nx --runtime runc state from-tpl
check "--runtime runc is refused with the replacement named, not a shorter list" \
  all 'rc 2' 'err_has "use --runtime crun"' 'not_called_re "^pct"'

nx --root /run/alt --log "$S/run/ct.json" --log-format json --systemd-cgroup list
check "the options containerd sends are accepted, not read as a command" \
  all 'rc 0' '! err_has "unknown command"'
# a command that fails, so there is a line for the engine to read back
nx --log "$S/run/ct.json" --log-format json state no-such-container
check "--log --log-format json: the error lands in the file containerd reads" \
  all 'rc 1' '[ -s "$S/run/ct.json" ]' 'json_lines_have_error "$S/run/ct.json"'
nx --log "$S/run/ct2.json" state no-such-container
check "--log without a format writes text, not JSON" \
  all '[ -s "$S/run/ct2.json" ]' '! grep -q "level" "$S/run/ct2.json"'

nx --runtime crun state some-id
check "state on a crun binary that lacks the backend -> exit 1, says how to build it" \
  all 'rc 1' 'err_has "not built into this binary"' 'not_called_re "^pct"'

nx create sock-1 --bundle /tmp/nexcage-bundles/b1 --console-socket /run/x.sock
check "--console-socket on the LXC backend -> exit 1, says why and what to use" \
  all 'rc 1' 'err_has "pct create starts no process"' 'err_has "--runtime crun"' 'not_called_re "^pct create"'
nx create pidf-1 --bundle /tmp/nexcage-bundles/b1 --pid-file /run/x.pid
check "--pid-file on the LXC backend -> exit 1, refused rather than ignored" \
  all 'rc 1' 'err_has "--pid-file"' 'not_called_re "^pct create"'
nx create plain-1 --bundle /tmp/nexcage-bundles/b1
check "without either flag the bundle path is unaffected" all 'rc 0' 'called_re "^pct create [0-9]+ "'

nx delete spec-1
check "delete refuses a running container without --force" rc 1
nx delete spec-1 --force
check "delete --force stops it first, then destroys it" \
  all 'rc 0' 'called_re "^pct shutdown [0-9]+ "' 'called_re "^pct destroy [0-9]+$"'
nx start from-tpl; nx kill from-tpl --all TERM
check "kill --all is accepted and says what it does on this backend" all 'rc 0' 'err_has "--all"'

# containerd's CRI asks for `features` once at startup. On this backend there
# is nothing honest to answer with: `pct` creates the container, so the hooks,
# seccomp and capabilities a features document promises are not nexcage's to
# report. Refusing and saying where the answer lives beats inventing one.
nx features
check "features refuses on the LXC backend and points at crun" \
  all 'rc 1' 'err_has "--runtime crun"' 'not_called_re "^pct"'
nx --runtime crun features
check "features on a build without the crun backend says so" \
  all 'rc 1' 'err_has "-Denable-backend-crun=true"'
nx features --help
check "features --help explains where the values come from" all 'rc 0' 'out_has "crun features"'

echo "--- the cluster listing lags ---"
# /cluster/resources is a cached view that pvestatd refreshes every few seconds.
# A container created a moment ago is not in it yet, while `pct list` sees it at
# once, so a miss there has to mean "keep looking" rather than "no such
# container". Getting this wrong made create-then-start fail on a real host.
reset_sim
cfg '{"network":{"bridge":"vmbr0"}}'
nx create --name lag-1 "$TPL" >/dev/null 2>&1
echo lag-1 > "$S/stale_cluster"
nx start lag-1
check "a container the cluster listing has not caught up with still starts" \
  all 'rc 0' 'called_re "^pct start"'
nx state lag-1
check "and state finds it too" all 'rc 0' '[ "$(json_get "$S/out" id)" = lag-1 ]'
nx start no-such-container-anywhere
check "while a container that exists nowhere is still not found" \
  all 'rc 1' 'err_has "not found"'
: > "$S/stale_cluster"

# The cache can also be *wrong* rather than empty: for a few seconds after a
# start it still says stopped. For a container on this host `pct list` is the
# current answer, so it has to win -- state said "stopped" right after a
# successful start until it did.
echo "lag-1 stopped" > "$S/stale_status"
nx state lag-1
check "this host's status wins over the cluster's stale copy" \
  all 'rc 0' '[ "$(json_get "$S/out" status)" = running ]'
nx list
check "and the listing shows the current status, not the cached one" \
  awk -F'\t' '$8=="lag-1" && $5=="running" {f=1} END {exit !f}' "$S/out"
: > "$S/stale_status"

echo "=== pause and resume ==="
reset_sim
cfg '{"network":{"bridge":"vmbr0"}}'
nx create --name fz-1 "$TPL" >/dev/null 2>&1
nx start fz-1 >/dev/null 2>&1

nx pause fz-1
check "pause writes the cgroup freezer" \
  all 'rc 0' '[ "$(cat "$S/cgroup/lxc/100/cgroup.freeze" 2>/dev/null)" = 1 ]' \
      'not_called_re "^pct suspend"'
# `pct status` says running for a frozen container, so state has to read the
# freezer -- that is the whole reason it does.
nx state fz-1
check "state calls a frozen container paused, where pct says running" \
  all 'rc 0' '[ "$(json_get "$S/out" status)" = paused ]'

# And `list` has to say the same. It read pct's answer only, so the same binary
# called one container running and paused depending on which command was asked.
nx list
check "list calls it paused too, rather than disagreeing with state" \
  awk -F'\t' '$8=="fz-1" && $5=="paused" {f=1} END {exit !f}' "$S/out"

nx resume fz-1
check "resume thaws it" \
  all 'rc 0' '[ "$(cat "$S/cgroup/lxc/100/cgroup.freeze" 2>/dev/null)" = 0 ]'
nx state fz-1
check "and state says running again" all 'rc 0' '[ "$(json_get "$S/out" status)" = running ]'
nx list
check "and so does list" \
  awk -F'\t' '$8=="fz-1" && $5=="running" {f=1} END {exit !f}' "$S/out"

# A container that is not running has no cgroup to freeze.
nx stop fz-1 >/dev/null 2>&1
nx pause fz-1
check "pause on a stopped container is an error naming why" \
  all 'rc 1' 'err_has "not running"'

nx pause no-such-fz-$$
check "pause on a container that does not exist is an error" all 'rc 1'
nx resume no-such-fz-$$
check "and so is resume" all 'rc 1'

# pct suspend is lxc-checkpoint, which is a different thing; nexcage must never
# reach for it.
check "nothing in this suite ever ran pct suspend" \
  all '! grep -q "^pct suspend" "$S/calls"'

echo "=== the cluster ==="
# A container on another node. `pct` cannot see it -- that is what the fourth
# field means in the fake's db, and what makes these checks worth anything:
# before this, every one of them answered "not found".
reset_sim
echo "200 running remote-1 titan" >> "$S/db"

nx list
check "list shows a container on another node, with the node" \
  all 'rc 0' 'listed remote-1' 'awk -F"\t" '"'"'$8=="remote-1" && $7=="titan" {f=1} END {exit !f}'"'"' "$S/out"'
check "and it is the cluster that was asked, not this host" \
  called "pvesh get /cluster/resources --type vm --output-format json"
# --type vm covers virtual machines too, and the fake has one. A container
# listing must not show it: the entry's own "type" field is what separates them,
# and asking for "lxc" is rejected by the real API outright.
check "a virtual machine is not listed as a container" \
  all '! out_has a-virtual-machine' '! grep -q 9999 "$S/out"'

nx start remote-1
check "start on another node goes through that node's API, not pct" \
  all 'rc 0' 'called "pvesh create /nodes/titan/lxc/200/status/start"' 'not_called_re "^pct start"'

nx state remote-1
check "state names the node it is on" \
  all 'rc 0' 'out_has "\"io.cageforge.nexcage.node\": \"titan\""'
check "and reports no PID, because a PID there is not a PID here" \
  out_has '"pid": 0'

nx exec remote-1 echo hi
check "exec on another node is refused, and says where to run it" \
  all 'rc 1' 'err_has "runs on titan"' 'not_called_re "^pct exec"'
nx kill remote-1
check "kill on another node is refused: a signal comes from the host" \
  all 'rc 1' 'err_has "runs on titan"'
nx pause remote-1
check "pause on another node is refused: the freezer is that host's filesystem" \
  all 'rc 1' 'err_has "runs on titan"'

nx create --name remote-1 "$TPL"
check "a name taken on another node is not free" \
  all 'rc 1' 'err_has "already exists on node titan"' 'not_called_re "^pct create"'

nx stop remote-1
check "stop on another node goes through that node's API" \
  all 'rc 0' 'called_re "^pvesh create /nodes/titan/lxc/200/status/shutdown"'
nx delete remote-1
check "delete on another node goes through that node's API" \
  all 'rc 0' 'called "pvesh delete /nodes/titan/lxc/200"'
nx state remote-1
check "and afterwards it is gone from the cluster" rc 1

echo "--- create --node ---"
reset_sim
: > "$S/node_templates"
echo "titan $TPL" >> "$S/node_templates"
cfg '{"network":{"bridge":"vmbr0"}}'

nx create --name there-1 --node titan "$TPL"
check "create --node makes the container through that node's API" \
  all 'rc 0' 'called_re "^pvesh create /nodes/titan/lxc --vmid [0-9]+ --ostemplate .* --hostname there-1"' \
      'not_called_re "^pct create"'
# calls.last holds only the last invocation, so this is asserted on the create
# itself rather than after the list that follows it.
check "the template was checked on that node, and before the VMID was taken" \
  all 'called_re "^pvesh get /nodes/titan/storage/local/content --content vztmpl"' \
      'awk "/storage\\/local\\/content/{t=NR} /cluster\\/nextid/{n=NR} END{exit !(t && n && t<n)}" "$S/calls.last"'
nx list
check "and it is listed on that node" \
  all 'rc 0' 'awk -F"\t" '"'"'$8=="there-1" && $7=="titan" {f=1} END {exit !f}'"'"' "$S/out"'

# The template check is the point: a node that cannot see it is told so, and
# nothing is created.
nx create --name there-2 --node otherhost "$TPL"
check "a node without the template is refused, with the node named" \
  all 'rc 1' 'err_has "does not have the template"' 'not_called_re "^pvesh create /nodes/otherhost/lxc"'

# An OCI bundle is packed into a template on *this* host, so it cannot travel.
nx create --name there-3 --node titan --bundle /tmp/nexcage-bundles/b1
check "--node with a bundle is refused, not half-done" \
  all 'rc 1' 'err_has "packed into a template on this host"'

nx --runtime crun create --node titan --bundle /tmp/nexcage-bundles/b1 there-4
check "--node on the crun backend says it has nowhere to put it" \
  all 'rc 1' 'err_has "nowhere else to put it"'

# Naming this host is not "another node": it is the ordinary local path.
nx create --name here-2 --node "$(hostname)" "$TPL"
check "--node naming this host goes through pct, as it should" \
  all 'rc 0' 'called_re "^pct create"' 'not_called_re "^pvesh create /nodes/"'

# A container here still goes through pct: the API is for what is elsewhere.
reset_sim
cfg '{"network":{"bridge":"vmbr0"}}'
nx create --name here-1 "$TPL" >/dev/null 2>&1
nx start here-1
check "a container on this host still goes through pct" \
  all 'rc 0' 'called_re "^pct start"' 'not_called_re "^pvesh create /nodes/"'

echo "=== images and pull ==="
reset_sim
: > "$S/node_templates"; : > "$S/nodes"; : > "$S/node_storages"
HOST=$(hostname)
printf '%s\n' "$HOST" titan > "$S/nodes"
# `shared-rdma` is shared: both nodes report it, and it must be listed once.
{ echo "$HOST local 0"; echo "$HOST shared-rdma 1"; echo "titan local 0"; echo "titan shared-rdma 1"; } > "$S/node_storages"
{ echo "$HOST local:vztmpl/debian-13.tar.zst"
  echo "$HOST shared-rdma:vztmpl/redis_7.tar"
  echo "titan shared-rdma:vztmpl/redis_7.tar"
  echo "titan local:vztmpl/alpine-3.22.tar.zst"; } > "$S/node_templates"

nx images
check "images lists a template with its node and storage" \
  all 'rc 0' 'out_has "NODE	STORAGE	SHARED	SIZE	TEMPLATE"' \
      'grep -q "local:vztmpl/debian-13.tar.zst" "$S/out"'
check "images sees the other node's own template too" \
  out_has "local:vztmpl/alpine-3.22.tar.zst"
# The subtlety worth testing: a shared storage carries the same file on every
# node, so listing per node would show it twice and a count would mean nothing.
check "a template on a shared storage is listed once, not once per node" \
  [ "$(grep -c 'shared-rdma:vztmpl/redis_7.tar' "$S/out")" = 1 ]
check "and the shared storage is marked as shared" \
  awk -F'\t' '$5 ~ /shared-rdma/ && $3=="yes" {f=1} END {exit !f}' "$S/out"

nx images --node titan
check "images --node narrows it to that node" \
  all 'rc 0' 'out_has "local:vztmpl/alpine-3.22.tar.zst"' '! out_has "debian-13"'

nx images --node no-such-node
check "images on a node the cluster does not have is an error, not an empty list" \
  all 'rc 1' 'err_has "no node called"' 'err_has "titan"'

nx --runtime crun images
check "images on the crun backend says templates are not its business" \
  all 'rc 1' 'err_has "already there"'

# Pulling needs PVE 9.1+, which is where oci-registry-pull arrived.
echo 9.1.0 > "$S/pvever"
nx pull docker.io/library/nginx:1.27
check "pull answers with the volid the storage ended up holding" \
  all 'rc 0' 'called_re "^pvesh create /nodes/.*/storage/local/oci-registry-pull --reference docker.io/library/nginx:1.27"' \
      'grep -q "^local:vztmpl/nginx_1.27.tar$" "$S/out"'
nx pull docker.io/library/nginx:1.27 --node titan --storage shared-rdma
check "pull --node --storage puts it where create --node can read it" \
  all 'rc 0' 'called_re "^pvesh create /nodes/titan/storage/shared-rdma/oci-registry-pull"' \
      'grep -q "^shared-rdma:vztmpl/nginx_1.27.tar$" "$S/out"'

# An older Proxmox has no such endpoint, and the version is why -- not an
# obscure API failure.
echo 8.4.1 > "$S/pvever"
nx pull docker.io/library/nginx:1.27
check "pull on a Proxmox older than 9.1 says which version it needs" \
  all 'rc 1' 'err_has "9.1 or later"' 'not_called_re "oci-registry-pull"'
echo 9.1.0 > "$S/pvever"

echo "--- rmi ---"
nx rmi "local:vztmpl/debian-13.tar.zst"
check "rmi removes the template from this node's storage" \
  all 'rc 0' 'called_re "^pvesh delete /nodes/.*/storage/local/content/local:vztmpl/debian-13.tar.zst"' \
      'out_has "removed from"'
nx images
check "and it is gone from the listing" all 'rc 0' '! out_has "debian-13.tar.zst"'

# A mistyped volid must not look like a successful removal.
nx rmi "local:vztmpl/there-was-never-such-a-thing.tar"
check "rmi on a template that is not there is an error, not a no-op" \
  all 'rc 1' 'err_has "does not have the template"' 'not_called_re "^pvesh delete"'
nx rmi "no-such-storage:vztmpl/x.tar"
check "rmi names the storage the node does not have" \
  all 'rc 1' 'err_has "no storage called"'
nx rmi not-a-volid
# 2, not 1: a malformed name is a usage error, and nexcage keeps that apart
# from "the thing is not there", which is 1.
check "rmi wants <storage>:vztmpl/<file>" all 'rc 2' 'err_has "vztmpl"'

# On a shared storage the file goes for every node, and that is said.
nx rmi "shared-rdma:vztmpl/redis_7.tar" --node titan
check "rmi on a shared storage says it is gone from every node" \
  all 'rc 0' 'out_has "gone from every node"'
nx images
check "and the shared template is gone from the listing" all 'rc 0' '! out_has "redis_7.tar"'

nx --runtime crun rmi "local:vztmpl/x.tar"
check "rmi on the crun backend says templates are not its business" \
  all 'rc 1' 'err_has "already there"'

echo "=== health ==="
# Its checks look at the host, so only the absence of leaks is checked here
nx health

echo
check "no leaks, panics or invalid frees in any run" all '[ "$LEAKS" = 0 ]'
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
