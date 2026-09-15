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
mkdir -p "$SIM/run" "$SIM/work" "$SIM/bundles" "$SIM/cache"

reset_sim() {
  rm -rf "${S:?}"/run/* "$S"/work/* "$S/cache" "$S"/bundles/*
  mkdir -p "$S/cache"
  : > "$S/db"; : > "$S/calls"
  rm -f "$S"/fail_* "$S/no_kill" "$S/pvever" "$S"/lock.* "$S"/conf.* "$S"/tarlist.*
  printf "%s\n" "$TPL" local:vztmpl/alpine-3.22-default_20250617_amd64.tar.xz local:vztmpl/debian-12.tar.zst > "$S/templates"
}
cfg() { printf '%s\n' "$1" > "$S/work/config.json"; }
nexcage_ns() {
  unshare -rm bash -c '
    mount --bind "$SIM/run" /run &&
    mount -t tmpfs tmpfs /tmp &&
    mkdir /tmp/nexcage-bundles && mount --bind "$SIM/bundles" /tmp/nexcage-bundles &&
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
json_get()  { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$1" "$2" 2>/dev/null; }
listed()    { awk -F'\t' -v n="$1" 'NR>1 && $7==n {f=1} END {exit !f}' "$S/out"; }
status_is() { nx state "$1"; [ "$RC" = 0 ] && [ "$(json_get "$S/out" status)" = "$2" ]; }

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
check "create checks the name first (pct list), then asks pvesh for a VMID" \
  all 'called "pct list"' 'called "pvesh get /cluster/nextid"'
check "pct create argv: vmid, template, hostname, bridge, rootfs from config" \
  called_re "^pct create 100 $TPL --hostname web-1 --memory [0-9]+ --cores [0-9]+ --net0 name=eth0,bridge=vmbr50,ip=dhcp --unprivileged 0 --rootfs local-lvm:2$"
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
check "registry image on PVE 9.1 -> pvesh oci-registry-pull, then pct create with the .tar" \
  all 'rc 0' "called 'pvesh create /nodes/$(hostname)/storage/local/oci-registry-pull --reference docker.io/library/nginx:latest'" \
      'called_re "^pct create [0-9]+ local:vztmpl/nginx_latest.tar --hostname nginx-1 "' 'not_called_re "--ostype|--unprivileged"'
touch "$S/fail_pull"
nx create --name nginx-2 docker.io/library/nginx:1.27
check "registry pull failing -> exit 1, no pct create" all 'rc 1' 'not_called_re "^pct create"'
rm -f "$S/fail_pull" "$S/pvever"

cfg '{"network":{"bridge":"vmbr50"},"proxmox":{"storage":"local-lvm","ostype":"debian","unprivileged":true}}'
nx create --name web-6 "$TPL"
check "ostype/unprivileged from config reach pct" all 'rc 0' 'called_re "--ostype debian --unprivileged 1 --rootfs local-lvm:[0-9]+$"'
rm -f "$S/work/config.json"
nx create --name web-7 "$TPL"
check "no config file -> default bridge, no --rootfs" all 'rc 0' 'called_re "bridge=vmbr0,ip=dhcp --unprivileged 0$"'

echo "pct list: Permission denied" > "$S/fail_all"
nx create --name web-8 "$TPL"
check "pct list failing -> create refuses (not read as 'name free')" all 'rc 1' 'err_has "permission denied"' 'not_called_re "^pct create"'
rm -f "$S/fail_all"

echo "=== state ==="
nx state web-1
check "state of created container: exit 0, stdout is pure JSON" all 'rc 0' 'json_ok "$S/out"'
check "state id/status/ociVersion" all '[ "$(json_get "$S/out" id)" = web-1 ]' '[ "$(json_get "$S/out" status)" = stopped ]' '[ "$(json_get "$S/out" ociVersion)" = 1.0.0 ]'
nx state 100;  check "state by VMID works" all 'rc 0' '[ "$(json_get "$S/out" status)" = stopped ]'
nx state nope; check "state of missing container -> exit 1, not found" all 'rc 1' 'err_has "not found"'
nx state;      check "state without name -> exit 2" rc 2
echo "backup" > "$S/lock.100"
nx state web-1; check "locked container still resolves by name" all 'rc 0' '[ "$(json_get "$S/out" id)" = web-1 ]'
rm -f "$S/lock.100"
echo "Permission denied" > "$S/fail_all"
nx state web-1; check "state with pct failing -> exit 1, pct's message logged" all 'rc 1' 'err_has "permission denied"' 'err_has "pct command failed"'
rm -f "$S/fail_all"

echo "=== list ==="
nx list
check "list: header + row with name in column 7" all 'rc 0' 'out_has "NAMES"' 'listed web-1'
check "list row fields: vmid/status/backend" awk -F'\t' '$7=="web-1" && $1=="100" && $5=="stopped" && $6=="proxmox-lxc" {f=1} END {exit !f}' "$S/out"
echo "backup" > "$S/lock.101"
nx list; check "list with a locked container keeps the right name" all 'listed web-2' '! listed backup'
rm -f "$S/lock.101"
echo "Permission denied" > "$S/fail_all"
nx list; check "list with pct failing -> exit 1 with the reason, not an empty list" all 'rc 1' 'err_has "permission denied"' '! out_has "NAMES"'
rm -f "$S/fail_all"

echo "=== start ==="
nx start web-1
check "start exits 0, runs pct start 100" all 'rc 0' 'called "pct start 100"'
check "state.json -> running" all '[ "$(json_get "$S/run/nexcage/web-1/state.json" status)" = running ]'
status_is web-1 running; check "state reports running" true
nx start web-1;  check "start an already running container -> exit 1" rc 1
nx start nope;   check "start missing -> exit 1, not found" all 'rc 1' 'err_has "not found"'
nx start;        check "start without name -> exit 2" rc 2
nx start --name web-2; check "start --name <id> (form in 'start --help')" all 'rc 0' 'called "pct start 101"'

echo "=== kill ==="
nx kill web-1;                 check "kill default SIGTERM"          all 'rc 0' 'called "pct exec 100 -- kill -s SIGTERM 1"'
nx kill -s SIGKILL web-1;      check "kill -s SIGKILL <name>"         all 'rc 0' 'called "pct exec 100 -- kill -s SIGKILL 1"'
nx kill --signal HUP web-1;    check "kill --signal HUP <name>"       all 'rc 0' 'called "pct exec 100 -- kill -s HUP 1"'
nx kill web-1 9;               check "kill <name> 9 (runc form)"      all 'rc 0' 'called "pct exec 100 -- kill -s 9 1"'
nx kill web-1 --signal USR1;   check "kill <name> --signal USR1"      all 'rc 0' 'called "pct exec 100 -- kill -s USR1 1"'
nx kill web-1 'TERM;id';       check "kill rejects a bad signal -> exit 2, no exec" all 'rc 2' 'not_called_re "^pct exec"'
touch "$S/no_kill"
nx kill web-1;                 check "kill falls back to /bin/kill"   all 'rc 0' 'called "pct exec 100 -- /bin/kill -s SIGTERM 1"'
rm -f "$S/no_kill"
nx kill nope;                  check "kill missing -> exit 1"         rc 1
nx kill;                       check "kill without name -> exit 2"    rc 2
nx kill web-3;                 check "kill a stopped container -> exit 1, pct's reason logged" all 'rc 1' 'err_has "CT 102 not running"'

echo "=== stop ==="
nx stop web-1
check "stop: pct shutdown 100 --timeout 60 --forceStop 1" all 'rc 0' 'called "pct shutdown 100 --timeout 60 --forceStop 1"'
check "state.json -> stopped" all '[ "$(json_get "$S/run/nexcage/web-1/state.json" status)" = stopped ]'
status_is web-1 stopped; check "state reports stopped" true
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
status_is app-1 running; check "run: state reports running" true
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

echo "=== create from an OCI bundle ==="
mkdir -p "$S/bundles/b1/rootfs/bin" "$S/bundles/nocfg/rootfs"
printf '#!/bin/sh\n' > "$S/bundles/b1/rootfs/bin/busybox"; chmod 755 "$S/bundles/b1/rootfs/bin/busybox"
ln -s busybox "$S/bundles/b1/rootfs/bin/sh"
cat > "$S/bundles/b1/config.json" <<'JSON'
{"ociVersion":"1.0.2","hostname":"b1","process":{"args":["/bin/sh"],"cwd":"/"},"root":{"path":"rootfs"},
 "linux":{"namespaces":[{"type":"pid"},{"type":"user"}]}}
JSON
nx create --name bundle-0 "$S/bundles/b1"
check "bundle outside the allowed prefixes -> exit 2, says where bundles go" all 'rc 2' 'err_has "/tmp/nexcage-bundles/"' 'not_called_re "^pct create"'
nx create --name bundle-x /tmp/nexcage-bundles/nocfg
check "bundle without config.json -> exit 2, no crash" all 'rc 2' 'err_has "config.json"' 'not_called_re "^pct create"'
nx create --name bundle-1 /tmp/nexcage-bundles/b1
check "bundle: rootfs packed on storage local, pct create uses that volume" \
  all 'rc 0' 'called_re "^pvesm path local:vztmpl/nexcage-bundle-1-[0-9]+\.tar\.zst$"' \
      'called_re "^pct create [0-9]+ local:vztmpl/nexcage-bundle-1-[0-9]+\.tar\.zst --hostname bundle-1 "'
check "bundle: archive keeps the executable bit and symlinks" \
  all 'grep -qE "^-rwxr-xr-x .* \./bin/busybox$" "$S"/tarlist.*' 'grep -qE "^lrwxrwxrwx .* \./bin/sh -> busybox$" "$S"/tarlist.*'
check "bundle: archive removed after pct create" all '[ -z "$(ls -A "$S/cache")" ]'
check "bundle: user namespace -> pct set --features nesting=1,keyctl=1" called_re "^pct set [0-9]+ --features nesting=1,keyctl=1$"

echo "=== health ==="
# Its checks look at the host, so only the absence of leaks is checked here
nx health

echo
check "no leaks, panics or invalid frees in any run" all '[ "$LEAKS" = 0 ]'
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
