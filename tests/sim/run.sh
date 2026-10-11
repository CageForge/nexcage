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

# The fake host: $SIM, $NEXCAGE, $TPL, reset_sim, cfg, nexcage_ns
source "$(dirname "$0")/lib.sh"
PASS=0; FAIL=0; LEAKS=0
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
# Some line of a JSON log is an error whose msg starts with $2 and ends with $3,
# and every line is JSON.
json_error_msg_is() {
  python3 - "$@" <<'PYEOF' 2>/dev/null
import json, sys
lines = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
sys.exit(0 if any(o.get("level") == "error" and o["msg"].startswith(sys.argv[2]) and o["msg"].endswith(sys.argv[3]) for o in lines) else 1)
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
for c in create start stop delete list state kill run version help health snapshot snapshots rollback delsnapshot; do
  nx "$c" --help; check "$c --help exits 0 without touching pct" all 'rc 0' '[ -s "$S/out" ]' 'not_called_re "^pct"'
done
nx version --help; check "version --help prints help, not the version" all 'rc 0' 'out_has "Usage: nexcage version"'
nx health --help;  check "health --help prints help, runs no checks"   all 'rc 0' 'out_has "Usage: nexcage health"' '[ ! -s "$S/calls.last" ]'
nx --debug list; check "--debug before command still runs list" all 'rc 0' 'out_has "NAMES"'
# A command can fail with an error from outside nexcage's own set, as version
# does writing to a full disk. That was a panic, "invalid error code" and exit
# 134; it is an error exit naming the error.
RC=0; nexcage_ns version > /dev/full 2> "$S/err" || RC=$?; LAST="nexcage version > /dev/full"; : > "$S/calls.last"
check "an error from outside nexcage's set exits 1 naming it, not a panic" \
  all 'rc 1' 'err_has "version: NoSpaceLeft"' '! err_has "panic"'

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
# A long failure -- tar's warning for every device node, then the task error --
# still reaches the file an engine reads: cut and marked, where a message over
# the JSON line's limit used to be written as "msg":"".
for i in $(seq 1 40); do echo "tar: ./dev/tty$i: Cannot mknod: Operation not permitted"; done > "$S/fail_create"
echo "TASK ERROR: unable to create CT 104 - command failed: exit code 2" >> "$S/fail_create"
nx --log /run/create-fail.json --log-format json create --name web-5 "$TPL"
check "a long pct error keeps its message in the JSON log, cut and marked" \
  all 'rc 1' 'json_error_msg_is "$S/run/create-fail.json" "pct command failed: tar: ./dev/tty1: " "..."'
# What pct prints is not nexcage's to lay out: a newline in it made a line of
# the log that nobody wrote, and an escape sequence reached the terminal. CSI
# and NEL as UTF-8 (C2 9B, C2 85) are the same escape and the same new line
# to xterm and VTE terminals.
printf 'unable to create CT\n[1790000000] ERROR nexcage: forged\033]0;t\007\302\2332J\302\205[1790000000] ERROR nexcage: nel\n' > "$S/fail_create"
nx create --name web-5 "$TPL"
check "a text log line cannot be forged from what pct prints" \
  all 'rc 1' '! grep -q "^\[1790000000\] ERROR nexcage: forged" "$S/err"' '! grep -q "$(printf "\033")" "$S/err"' \
      '! grep -qF "$(printf "\302\233")" "$S/err"' '! grep -qF "$(printf "\302\205")" "$S/err"' \
      'err_has "unable to create CT\n[1790000000] ERROR nexcage: forged\x1b]0;t\x07\xc2\x9b2J\xc2\x85[1790000000] ERROR nexcage: nel"'
rm -f "$S/fail_create"

# Nor does a create carry on once its caller is gone. nexcage installs no
# signal handlers, and a wrapper that kills it -- a timeout in Python or Go, a
# unit with KillMode=process -- kills it alone: pct used to finish the
# container by itself, with no state, under a name a retry was then refused.
# Its children get SIGTERM when it dies now; fake pct models what real pct
# does with that, and with a KILL, which would not stop the create. The work
# is held until the check has looked, so a create that carries on is still
# there to be seen however slowly anything runs. It used to be given two
# seconds, and a loaded machine let it finish before the signal came.
echo 0 > "$S/slow_create"; touch "$S/hold_create"
before=$(wc -l < "$S/calls")
nexcage_ns create --name slow-1 "$TPL" > "$S/out" 2> "$S/err" &
bg=$!
for _ in $(seq 1 100); do [ -s "$S/create_caller" ] && break; sleep 0.1; done
worker=$(cat "$S/create_worker" 2>/dev/null)
kill -KILL "$(cat "$S/create_caller")"
RC=0; wait "$bg" || RC=$?
tail -n +"$((before + 1))" "$S/calls" > "$S/calls.last"; LAST="nexcage create --name slow-1 $TPL, killed during pct create"
check "nexcage killed during pct create: the create does not carry on without it" \
  all 'rc 137' 'called_re "^pct create [0-9]+ .*--hostname slow-1 "' '[ -n "$worker" ]' 'eventually "! kill -0 $worker 2>/dev/null"'
# A create that carries on is stopped here, rather than let into the db
[ -n "$worker" ] && kill -KILL -- "-$worker" 2>/dev/null
rm -f "$S/hold_create" "$S/slow_create" "$S/create_caller" "$S/create_worker"

nx create --name nginx-1 docker.io/library/nginx:latest
check "registry image on PVE 8.4 -> exit 1 with a version message, nothing pulled" \
  all 'rc 1' 'err_has "9.1"' 'not_called_re "^pvesh create"' 'not_called_re "^pct create"'
echo 9.1.0 > "$S/pvever"
# nexcage names a pulled file for the whole reference. The name is derived here
# as well, apart from nexcage's code (pve.zig, pulledTemplateName): `pulled` is
# the name pvesh is given, `pulled_re` the template's file as a regex. Past 110
# characters the reference is cut, and the digest is still of all of it.
pulled()    { printf '%s-%s' "$(printf '%s' "${1:0:110}" | tr -c 'A-Za-z0-9_.-' _)" "$(printf '%s' "$1" | sha256sum | cut -c1-16)"; }
pulled_re() { printf '%s\\.tar' "$(pulled "$1" | sed 's/\./\\./g')"; }
nx create --name nginx-1 docker.io/library/nginx:latest
check "registry image on PVE 9.1 -> pvesh oci-registry-pull, then an unprivileged pct create with the .tar" \
  all 'rc 0' "called 'pvesh create /nodes/$(hostname)/storage/local/oci-registry-pull --reference docker.io/library/nginx:latest --filename $(pulled docker.io/library/nginx:latest)'" \
      'called_re "^pct create [0-9]+ local:vztmpl/$(pulled_re docker.io/library/nginx:latest) --hostname nginx-1 .*--unprivileged 1( |$)"' 'not_called_re "--ostype"'
cfg '{"network":{"bridge":"vmbr50"},"proxmox":{"storage":"local-lvm","rootfs_size_gb":2,"unprivileged":false}}'
nx create --name redis-1 docker.io/library/redis:7
check "registry image with unprivileged=false: no --unprivileged 0, which pct rejects, and a warning" \
  all 'rc 0' 'called_re "^pct create [0-9]+ local:vztmpl/$(pulled_re docker.io/library/redis:7) --hostname redis-1 "' 'not_called_re "--unprivileged"' 'err_has "always run unprivileged"'
# Reuse is of that exact file and nothing else. Any template whose name held
# the image's last path component and its tag used to do: Proxmox's own system
# template, a file someone uploaded, the same name from another registry -- and
# with unprivileged=false a .tar.zst among them ran privileged.
nx create --name deb-1 docker.io/library/debian:12
check "a registry image is pulled, not taken from a system template whose name contains it" \
  all 'rc 0' 'called_re "oci-registry-pull --reference docker.io/library/debian:12 --filename "' \
      'called_re "^pct create [0-9]+ local:vztmpl/$(pulled_re docker.io/library/debian:12) "' 'not_called_re "^pct create [0-9]+ local:vztmpl/debian-12"'
echo "$(hostname) local:vztmpl/postgres-16-custom.tar.zst" >> "$S/node_templates"
echo "local:vztmpl/postgres-16-custom.tar.zst" >> "$S/templates"
nx create --name pg-1 docker.io/library/postgres:16
check "nor from an uploaded file whose name contains it, which would run privileged" \
  all 'rc 0' 'called_re "^pct create [0-9]+ local:vztmpl/$(pulled_re docker.io/library/postgres:16) "' \
      'not_called_re "postgres-16-custom"' 'not_called_re "--unprivileged 0"'
nx pull ghcr.io/someone/valkey:8 >/dev/null 2>&1
nx create --name vk-1 docker.io/library/valkey:8
check "nor from the same name pulled from another registry" \
  all 'rc 0' 'called_re "oci-registry-pull --reference docker.io/library/valkey:8 "' \
      'called_re "^pct create [0-9]+ local:vztmpl/$(pulled_re docker.io/library/valkey:8) "'
# The pulled file is the one nexcage named, never whatever appeared on the
# storage meanwhile -- here another create's bundle archive -- and a listing
# that fails is an error, not an empty storage: read as empty, the listing
# before the pull made every template already there look new.
echo "local:vztmpl/nexcage-tenant-b-1791664000.tar.zst" > "$S/also_lands"
nx create --name mc-1 docker.io/library/memcached:1.6
check "a file another writer adds during the pull is not taken for the image" \
  all 'rc 0' 'called_re "^pct create [0-9]+ local:vztmpl/$(pulled_re docker.io/library/memcached:1.6) "' 'not_called_re "nexcage-tenant-b"'
echo 2 > "$S/fail_list_in"
nx create --name hp-1 docker.io/library/haproxy:3
check "a storage listing that fails during create is an error, and nothing is created" \
  all 'rc 1' 'err_has "could not be listed"' 'not_called_re "^pct create"'
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
  all 'rc 0' 'not_called_re "oci-registry-pull"' 'called_re "^pct create [0-9]+ local:vztmpl/$(pulled_re docker.io/library/nginx:latest) "'
# --storage names where the pull lands, as it does for `pull`, and what pct is
# given is what that storage holds afterwards.
nx create --name nginx-4 --storage shared-rdma docker.io/library/nginx:1.26
check "create --storage pulls into that storage and creates from what it holds" \
  all 'rc 0' 'called_re "^pvesh create /nodes/[^/]+/storage/shared-rdma/oci-registry-pull --reference docker.io/library/nginx:1.26"' \
      'called_re "^pct create [0-9]+ shared-rdma:vztmpl/$(pulled_re docker.io/library/nginx:1.26) "'
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
# A config.json in the directory nexcage runs from is not its configuration:
# podman runs the runtime in its caller's directory, and one that another
# user left in /tmp made root create privileged containers on their bridge
# and append its log to a file of their choosing.
printf '%s\n' '{"log_file":"/run/planted.log","network":{"bridge":"vmbr666"},"proxmox":{"unprivileged":false}}' > "$S/work/config.json"
SIM_NO_CONFIG=1 nx create --name web-7b "$TPL"
check "a config.json in the working directory is not read" \
  all 'rc 0' 'called_re "--hostname web-7b .*bridge=vmbr0,ip=dhcp --unprivileged 1$"' 'not_called_re "vmbr666"' '[ ! -e "$S/run/planted.log" ]'
rm -f "$S/work/config.json"

# What pct create is usually given (#308): update's limits under update's
# names and in pct's terms, pct's own names for the rest, net0 in its syntax.
cfg '{"network":{"bridge":"vmbr50"},"proxmox":{"storage":"local-lvm","rootfs_size_gb":2}}'
nx create --name opt-1 --memory 1G --memory-swap 1536M --cores 3 --cpu-quota 150000 --cpu-share 512 \
  --ip 192.0.2.10/24 --gw 192.0.2.1 --vlan 20 --firewall --onboot --tags 'web;prod' \
  --mp 'local-lvm:1,mp=/data' --mp '/srv/x,mp=/mnt/x,ro=1' "$TPL"
check "create takes update's limits, said to pct as update says them" \
  all 'rc 0' 'called_re "^pct create .* --memory 1024 "' 'called_re " --swap 512 "' \
      'called_re " --cpulimit 1\.5 "' 'called_re " --cpuunits 20 "'
check "--memory and --cores replace the defaults rather than doubling them" \
  all 'called_re " --cores 3 "' '[ "$(grep -o -- " --memory " "$S/calls.last" | wc -l)" = 1 ]' \
      '[ "$(grep -o -- " --cores " "$S/calls.last" | wc -l)" = 1 ]'
check "--ip, --gw, --vlan and --firewall are net0's ip=, gw=, tag= and firewall=1" \
  called_re " --net0 name=eth0,bridge=vmbr50,ip=192\.0\.2\.10/24,gw=192\.0\.2\.1,tag=20,firewall=1 "
check "--onboot, --tags and each --mp reach pct as pct takes them" \
  all 'called_re " --onboot 1 "' 'called_re " --tags web;prod "' \
      'called_re " --mp0 local-lvm:1,mp=/data --mp1 /srv/x,mp=/mnt/x,ro=1$"'
nx create --name opt-2 --memory-swap 256M "$TPL"
check "--memory-swap is memory plus swap: below the default memory it is refused, before pct" \
  all 'rc 2' 'err_has "memory plus swap"' 'not_called_re "^pct create"'
nx create --name opt-2 --pids-limit 100 "$TPL"
check "a limit Proxmox has no setting for is refused by name, as update refuses it" \
  all 'rc 1' 'err_has "pids.limit has no Proxmox setting"' 'not_called_re "^pct create"'
nx create --name opt-3 --memory 9223372036854775807 "$TPL"
check "a memory limit past what Proxmox holds is a usage error naming it, not a trap" \
  all 'rc 2' 'err_has "memory.limit"' 'not_called_re "^pct create"'
nx create --name opt-4 --cpu-quota 50 "$TPL"
check "a quota pct would say as cpulimit 0, no limit, is refused, as update refuses it" \
  all 'rc 2' 'err_has "cpu.quota"' 'not_called_re "^pct create"'
nx create --name opt-5 --memory 0 "$TPL"
check "and memory 0 is not made 16 MiB" all 'rc 2' 'err_has "memory.limit"' 'not_called_re "^pct create"'
nx create --name opt-2 --vlan 5000 "$TPL"
check "--vlan outside 1-4094 is a usage error" all 'rc 2' 'err_has "VLAN tag"' 'not_called_re "^pct create"'
nx create --name opt-2 --ip 10.0.0.5/24,hwaddr=02:00:00:00:00:01 "$TPL"
check "an address with ',' or '=' would add a net0 key: refused" all 'rc 2' 'err_has "without"' 'not_called_re "^pct create"'
nx create --name opt-2 --cores 0 "$TPL"
check "--cores 0 is a usage error" all 'rc 2' 'err_has "--cores"' 'not_called_re "^pct create"'

echo "pct list: Permission denied" > "$S/fail_all"
nx create --name web-8 "$TPL"
check "the host unable to answer -> create refuses (not read as 'name free')" all 'rc 1' 'err_has "permission denied"' 'not_called_re "^pct create"'
rm -f "$S/fail_all"

echo "=== state ==="
nx state web-1
check "state of created container: exit 0, stdout is pure JSON" all 'rc 0' 'json_ok "$S/out"'
check "state of a container never started: id, status created, pid 0, ociVersion" \
  all '[ "$(json_get "$S/out" id)" = web-1 ]' '[ "$(json_get "$S/out" status)" = created ]' '[ "$(json_get "$S/out" pid)" = 0 ]' '[ "$(json_get "$S/out" ociVersion)" = 1.3.0 ]'
# A VMID is not a name nexcage has a record of, so it reaches the Proxmox
# backend only when asked to: an id nothing has a record of does not exist.
nx --runtime lxc state 100;  check "state by VMID works, with --runtime lxc" all 'rc 0' '[ "$(json_get "$S/out" status)" = created ]'
nx state 100;  check "a bare VMID without --runtime lxc does not exist, and nothing is asked" \
  all 'rc 1' 'err_has "does not exist"' 'err_has "--runtime lxc"' 'not_called_re "^(pct|pvesh)"'
nx state nope; check "state of missing container -> exit 1, does not exist" all 'rc 1' 'err_has "does not exist"'
nx state;      check "state without name -> exit 2" rc 2
echo "backup" > "$S/lock.100"
nx state web-1; check "locked container still resolves by name" all 'rc 0' '[ "$(json_get "$S/out" id)" = web-1 ]'
rm -f "$S/lock.100"
echo "Permission denied" > "$S/fail_all"
nx state web-1; check "state with the host failing -> exit 1, the tool's message logged" all 'rc 1' 'err_has "permission denied"' 'err_has "/cluster/resources) failed"'
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
nx start nope;   check "start missing -> exit 1, does not exist" all 'rc 1' 'err_has "does not exist"'
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
# The PID comes from `pct status`, another process, a moment before the
# signal: the init can exit in between and its PID go to an unrelated process,
# which kill(2) as root used to hit, reporting success. The signal goes through
# a pidfd now, and only to a process in the container's cgroup. A stand-in for
# the unrelated process records what it is sent.
python3 "$(dirname "$0")/fake_init.py" "$S/sig.stranger" </dev/null >/dev/null 2>&1 &
stranger=$!
eventually 'grep -qx READY "$S/sig.stranger" 2>/dev/null'
echo "$stranger" > "$S/reused_pid.100"
nx kill web-1 TERM
check "kill: a PID that is not the container's any more is not signalled; the container is not running" \
  all 'rc 1' 'err_has "not running"' '! got_signal stranger SIGTERM'
nx kill web-1 KILL; sleep 0.3
check "kill KILL: the unrelated process holding the PID lives on" \
  all 'rc 1' 'st=$(awk "{print \$3}" "/proc/$stranger/stat" 2>/dev/null); [ -n "$st" ] && [ "$st" != Z ]'
rm -f "$S/reused_pid.100" "$S/sig.stranger"; kill -9 "$stranger" 2>/dev/null; wait "$stranger" 2>/dev/null
nx kill web-1 CONT
check "and the container's own init is signalled as before" all 'rc 0' 'got_signal 100 SIGCONT'
# The tree under lxc/<vmid>/ns is the container's: its root makes cgroups
# there, and one that cannot be read -- a threaded cgroup's cgroup.procs
# fails with EOPNOTSUPP, one systemd removes mid-walk with ENODEV -- made kill
# fail on a live container, so an engine's TERM-then-KILL never landed. Here
# the cgroup's list is longer than kill reads. It has to be met before the
# init's, and the walk goes in directory order, which is not the same on any
# two filesystems: names that happened to come first on one did not on ext4's
# hash order. So two cgroups sit side by side. The one `ls -f` lists first
# cannot be read, the init moves into the other -- leaving ns/ itself with an
# empty list, as cgroup v2 has it -- and the walk is through the first before
# it reaches the second.
cg_ns=$S/cgroup/lxc/100/ns
mkdir "$cg_ns/a" "$cg_ns/b"
unread=$(ls -f "$cg_ns" | grep -Ex '[ab]' | head -1)
init_cg=a; [ "$unread" = a ] && init_cg=b
truncate -s 17M "$cg_ns/$unread/cgroup.procs"
mv "$cg_ns/cgroup.procs" "$cg_ns/$init_cg/cgroup.procs" && : > "$cg_ns/cgroup.procs"
: > "$S/sig.100"
nx kill web-1 USR1
check "kill: a cgroup in the container that cannot be read is passed over; the init is signalled" \
  all '[ "$(stat -c %s "$cg_ns/$unread/cgroup.procs")" -gt 16777216 ]' '[ ! -s "$cg_ns/cgroup.procs" ]' \
      'grep -qx "$(init_pid 100)" "$cg_ns/$init_cg/cgroup.procs"' 'rc 0' 'got_signal 100 SIGUSR1'
mv "$cg_ns/$init_cg/cgroup.procs" "$cg_ns/cgroup.procs" && rm -rf "${cg_ns:?}/a" "${cg_ns:?}/b"
nx kill web-1 'TERM;id';      check "kill: bad signal -> exit 2, nothing sent" all 'rc 2' 'err_has "unknown signal"' 'not_called_re "^pct"'
nx kill web-1 0;               check "kill: signal 0 -> exit 2"       all 'rc 2' 'not_called_re "^pct"'
nx kill web-1 65;              check "kill: signal 65 -> exit 2"      all 'rc 2' 'not_called_re "^pct"'
# Digits only: "1_5" read as 15 here and as 1 by libcrun's strtol on crun
nx kill web-1 1_5;             check "kill: 1_5 is not a number -> exit 2, nothing sent" all 'rc 2' 'err_has "unknown signal"' 'not_called_re "^pct"'
nx kill nope;                  check "kill missing -> exit 1"         rc 1
nx kill;                       check "kill without name -> exit 2"    rc 2
nx kill web-3;                 check "kill a stopped container -> exit 1, says it is not running" all 'rc 1' 'err_has "not running"'
nx run --name kill-1 "$TPL"
nx kill kill-1 KILL
check "kill KILL: the init dies and the container stops" all 'rc 0' "eventually 'status_is kill-1 stopped'"

echo "=== exec ==="
nx exec web-1 echo hello;      check "exec runs the command and its output reaches stdout" \
                                 all 'rc 0' 'out_has hello' 'called "pct exec 100 --keep-env 0 -- echo hello"'
nx exec web-1 sh -c 'exit 7';  check "exec exits with the status of the command, as runc does" rc 7
# The command gets LXC's clean environment, not the caller's: pct exec keeps
# the environment unless told not to, and handed every variable of the shell
# or job that ran nexcage -- API tokens, cloud keys -- to a binary from the
# image. Fake pct records what the command starts with.
SIM_EXEC_SECRET=from-the-callers-shell nx exec web-1 -- sh -c 'echo "env:[${SIM_EXEC_SECRET-}] path:[$PATH]"'
check "exec: the caller's environment does not reach the command in the container" \
  all 'rc 0' 'out_has "env:[] path:[/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin]"' \
      'called_re "^pct exec 100 --keep-env 0 -- "' '! grep -q SIM_EXEC_SECRET "$S/exec_env.100"' \
      'grep -qx container=lxc "$S/exec_env.100"'
nx exec web-1 -- echo dashed;  check "exec <name> -- <cmd>: the separator is not passed to pct" \
                                 all 'rc 0' 'out_has dashed' 'called "pct exec 100 --keep-env 0 -- echo dashed"'
nx exec web-1 -- sh -c 'echo x 1>&2; exit 3'
                               check "exec: stderr passes through and a non-zero status survives it" all 'rc 3' 'err_has x'
nx exec nope echo hi;          check "exec on a missing container -> exit 1, nothing run" \
                                 all 'rc 1' 'not_called_re "^pct exec"'

# A container engine writes a flag either way, and the choice is not ours:
# containerd sends `--root <dir>`, CRI-O sends `--root=<dir>`. CRI-O's first
# call came back as `unknown command '--root=/run/nexcage-crio'`.
# web-1's record is under the default root, so --runtime lxc names its backend
nx --root=/tmp/sim-root-eq --runtime lxc state web-1
check "--flag=value is a flag, not a command name" all 'rc 0' 'out_has "\"id\": \"web-1\""'
nx --version
check "--version, which is how CRI-O asks" all 'rc 0' 'out_has "nexcage version"'
# ...and the splitting stops at `--`: what follows belongs to the command run
# inside the container, where FOO=bar is an argument and not a flag.
nx exec web-1 -- env FOO=bar
check "an = after -- survives untouched" \
  all 'rc 0' 'called "pct exec 100 --keep-env 0 -- env FOO=bar"'

# Nor does nexcage read its own flags there: --config used to make it load
# the command's argument as its configuration.
nx exec web-1 -- echo --config /nonexistent --runtime bogus --profile nope --root /x
check "nexcage's flags after -- belong to the command, not to nexcage" \
  all 'rc 0' 'called "pct exec 100 --keep-env 0 -- echo --config /nonexistent --runtime bogus --profile nope --root /x"'
# Its logging flags neither: root created the file the command named and wrote
# nexcage's own log into it.
nx exec web-1 -- echo --log /run/exec-x.log --log-file /run/exec-y.log --debug
check "nexcage's logging flags after -- belong to the command too" \
  all 'rc 0' '[ ! -e "$S/run/exec-x.log" ]' '[ ! -e "$S/run/exec-y.log" ]' '! err_has "DEBUG"' \
      'called "pct exec 100 --keep-env 0 -- echo --log /run/exec-x.log --log-file /run/exec-y.log --debug"'
# Nor without --, the form `exec --help` shows: the command starts at the word
# after the container id, and every word of it is the command's, `=` and all.
# Each of these failed the call, made root write its log into the file named,
# or turned --color=auto into two words. nexcage_ns gives a call that names
# --config no file of its own, and cannot tell this one from such a call, so an
# empty /etc/nexcage stands in for the host's.
mkdir -p "$S/etc/nexcage"
nx exec web-1 echo --config /nonexistent --root rel --runtime bogus --profile nope --log /run/exec-z.log --debug --color=auto
check "the command's words are its own without -- too" \
  all 'rc 0' '[ ! -e "$S/run/exec-z.log" ]' '! err_has "DEBUG"' \
      'called "pct exec 100 --keep-env 0 -- echo --config /nonexistent --root rel --runtime bogus --profile nope --log /run/exec-z.log --debug --color=auto"'
rm -r "${S:?}/etc"
# nexcage's own options before the command are still nexcage's, in either
# spelling
nx exec web-1 --log /run/exec-own.log echo hi
check "and nexcage's options before the command are still read" \
  all 'rc 0' '[ -e "$S/run/exec-own.log" ]' 'called "pct exec 100 --keep-env 0 -- echo hi"'
nx exec web-1 --log=/run/exec-eq.log echo hi
check "an option's value after = is the option's, not the command" \
  all 'rc 0' '[ -e "$S/run/exec-eq.log" ]' 'called "pct exec 100 --keep-env 0 -- echo hi"'
rm -f "$S/run/exec-own.log" "$S/run/exec-eq.log"
# The command's words are the container's, and the line --log-file and
# --debug write when a command starts named every one of them: the variables
# a caller is told to give the command that way, tokens included, went into
# root's log file. That line has nexcage's own words now, and a count.
nx --log-file /run/exec-lf.log exec web-1 env TOKEN=s3cr3t true
check "--log-file has exec's own words, and only how many the container's command has" \
  all 'rc 0' 'called "pct exec 100 --keep-env 0 -- env TOKEN=s3cr3t true"' \
      'grep -q "Starting command: exec with args: web-1, and a command of 3 word(s) for the container, not logged" "$S/run/exec-lf.log"' \
      '! grep -q s3cr3t "$S/run/exec-lf.log"' '! err_has s3cr3t'
nx --debug exec web-1 -- env TOKEN=s3cr3t true
check "nor does --debug write them to stderr" all 'rc 0' 'err_has "a command of 3 word(s)"' '! err_has s3cr3t'
rm -f "$S/run/exec-lf.log"
# An option exec does not have, or one that takes no value, given a value
# after =: what was meant cannot be told -- the `true` of --tty=true was run as
# the command -- so it is a usage error. Each crashed nexcage once the command
# was looked for.
nx exec web-1 --foo=bar ls
check "an option exec does not have, written with =, is a usage error" \
  all 'rc 2' 'err_has "--foo"' 'not_called_re "^pct exec"'
nx exec web-1 --tty=false echo hi
check "and so is a value for one that takes none, not a command" \
  all 'rc 2' "err_has \"'--tty=false': exec has no option '--tty' that takes a value\"" 'not_called_re "^pct exec"'

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
# pct exec runs the command as root, where nexcage does not choose, and hands
# back no pty or pid: these used to be dropped, so `--user 1000` ran as root.
for flag in "--user 1000" "--cwd /srv" "--console-socket /tmp/sim-console.sock" "--pid-file /tmp/sim-exec.pid"; do
  # shellcheck disable=SC2086 # the flag and its value are two words
  nx exec $flag web-1 id
  check "exec ${flag%% *} is refused on the LXC backend, not ignored" \
    all 'rc 1' "err_has '${flag%% *}'" 'not_called_re "^pct exec"'
done
# lxc-attach, which pct exec runs, gives the command a terminal when one of the
# caller's standard descriptors is one. With none, --tty cannot be honoured.
nx exec -t web-1 echo hi < /dev/null
check "exec --tty with no terminal is refused on the LXC backend" \
  all 'rc 1' 'err_has "--tty"' 'not_called_re "^pct exec"'
nx exec web-1 --process /tmp/sim-process.json ls
# 2, not 1: giving both is a usage error, and nexcage keeps that distinction.
check "exec takes a command or --process, not both" all 'rc 2' 'err_has "not both"'

# Kubernetes asks for `ps --format json`, which was answered with `unknown
# command 'ps'` -- containerd says nothing about that in its journal and the pod
# runs anyway, so only the runtime's own command lines showed it.
nx ps web-1
check "ps is refused on the LXC backend, where it would answer another question" \
  all 'rc 1' 'err_has "--runtime crun"' 'not_called_re "^pct"'
# With --log the explanation goes to that file, and an error to stderr as
# well, as runc and crun print theirs: containerd's shim reads the command's
# output to tell one failure from another, and found only "operation failed"
# there (#361).
# The log goes under /run, which is bind-mounted from $S: the sandbox mounts a
# fresh tmpfs on /tmp, so a file written there disappears with the namespace and
# the check cannot see it.
# Under /run/x no backend has a record of web-1, which is the reason given.
rm -f "$S/run/nexcage-ps.log"
nx --root /run/x --log /run/nexcage-ps.log --log-format json ps --format json web-1
check "the shape containerd sends is read as ps, not as a command name" \
  all 'rc 1' '! err_has "unknown command"' 'grep -q "does not exist" "$S/run/nexcage-ps.log"'
check "and the reason is on stderr as well, where the engine reads it" \
  all 'err_has "does not exist"' '! err_has "\"level\""'
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
# An id no backend has a record of does not exist, and delete --force of it
# succeeds, as it does with crun and runc: an engine cleans up that way once a
# reboot has emptied /run. Such an id used to go to the Proxmox backend, which
# matched it against every CT in the cluster by name or VMID -- a second
# delete --force of a crun container named like a VMID destroyed that CT.
echo "905 stopped tenant-b-db" >> "$S/db"
nx delete --force 905
check "delete --force of an id nexcage has no record of exits 0 and touches no CT" \
  all 'rc 0' 'not_called_re "^(pct|pvesh)"' 'grep -q "^905 stopped tenant-b-db$" "$S/db"'
nx delete --force tenant-b-db
check "nor does it touch a CT nexcage did not create, named by its hostname, and it says so" \
  all 'rc 0' 'not_called_re "^(pct|pvesh)"' 'grep -q "^905 stopped tenant-b-db$" "$S/db"' 'err_has "--runtime lxc"'
nx delete --force 0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
check "an engine's id that libcrun no longer has: delete --force exits 0" \
  all 'rc 0' 'not_called_re "^(pct|pvesh)"'
nx delete 905
check "delete of it without --force says it does not exist, as crun does" \
  all 'rc 1' 'err_has "does not exist"' 'not_called_re "^(pct|pvesh)"'
nx --runtime lxc delete --force tenant-b-db
check "--runtime lxc reaches a CT nexcage did not create" \
  all 'rc 0' 'called "pct destroy 905"' '! grep -q "tenant-b-db" "$S/db"'
nx delete;       check "delete without name -> exit 2" rc 2

echo "=== run ==="
cfg '{"network":{"bridge":"vmbr50"},"proxmox":{"storage":"local-lvm","rootfs_size_gb":2}}'
nx run --name app-1 "$TPL"
check "run: create then start the same VMID" all 'rc 0' 'called_re "^pct create ([0-9]+) .*--hostname app-1 "' \
  "grep -q \"^pct start \$(awk '\$3==\"app-1\" {print \$1}' \$S/db)\$\" \"\$S/calls.last\""
check "run: rootfs/bridge from config" called_re "bridge=vmbr50,ip=dhcp .*--rootfs local-lvm:2$"
check "run: state reports running" status_is app-1 running
nx run --name app-1 "$TPL"; check "run duplicate -> exit 1, no start, and the existing one is not destroyed" \
  all 'rc 1' 'not_called_re "^pct start"' 'not_called_re "^pct destroy"' 'grep -q " app-1$" "$S/db"'
# A start that fails takes the container run made with it, as `runc run` does;
# it used to stay behind, created, and the next run of the name was refused.
echo "startup for container failed" > "$S/fail_start"
nx run --name app-f "$TPL"
app_f=$(sed -n 's/^pct create \([0-9]*\) .*/\1/p' "$S/calls.last")
check "run whose start fails -> exit 1, and the container it made is destroyed" \
  all 'rc 1' '[ -n "$app_f" ]' 'called "pct start $app_f"' 'called "pct destroy $app_f"' \
      '! grep -q " app-f$" "$S/db"' '[ ! -e "$S/run/nexcage/app-f" ]'
rm -f "$S/fail_start"
nx run --name app-f "$TPL"; check "and a run of the same name then succeeds" all 'rc 0' 'status_is app-f running'
# The undo goes by the VMID run made, not by the name again. Another caller's
# container of the same name, made while pct create ran and listed first, used
# to be the one run started -- "already running" -- then stopped and
# destroyed, while run's own stayed behind. hold_create keeps pct create's
# work waiting while that one appears, started as pct starts one and in a
# namespace as nexcage's, so that its cgroup lands in $S/cgroup. Its calls are
# not run's, and are left out of calls.last.
pct_ns() { unshare -rm bash -c 'mount --bind "$SIM/cgroup" /sys/fs/cgroup && exec "$BIN/pct" "$@"' pct "$@" > /dev/null 2>&1; }
echo 0 > "$S/slow_create"; touch "$S/hold_create"
before=$(wc -l < "$S/calls")
nexcage_ns run --name dup "$TPL" > "$S/out" 2> "$S/err" &
bg=$!
for _ in $(seq 1 100); do [ -s "$S/create_caller" ] && break; sleep 0.1; done
mid=$(wc -l < "$S/calls")
echo "90 stopped dup" >> "$S/db"
pct_ns start 90
echo "startup for container failed" > "$S/fail_start"
held=$(wc -l < "$S/calls")
rm -f "$S/hold_create"
RC=0; wait "$bg" || RC=$?
{ sed -n "$((before + 1)),${mid}p" "$S/calls"; tail -n +"$((held + 1))" "$S/calls"; } > "$S/calls.last"
LAST="nexcage run --name dup $TPL, while another dup is made and started"
dup=$(sed -n 's/^pct create \([0-9]*\) .*/\1/p' "$S/calls.last")
check "run whose start fails destroys the VMID it made, not a container of the same name made meanwhile" \
  all 'rc 1' '[ -n "$dup" ]' '[ "$dup" != 90 ]' 'called "pct start $dup"' 'called "pct destroy $dup"' \
      '! grep -q "^$dup " "$S/db"' '[ ! -e "$S/run/nexcage/dup" ]' \
      'not_called_re "^pct [a-z]+ 90( |$)"' 'grep -qx "90 running dup" "$S/db"' 'kill -0 "$(init_pid 90)"'
rm -f "$S/fail_start" "$S/slow_create" "$S/create_caller" "$S/create_worker"
pct_ns shutdown 90; pct_ns destroy 90
# A start can also fail once the init is up, and pct destroy refuses a
# running container: run stops it first, by the VMID it made.
echo "startup for container failed" > "$S/fail_after_start"
nx run --name app-g "$TPL"
app_g=$(sed -n 's/^pct create \([0-9]*\) .*/\1/p' "$S/calls.last")
check "run whose start fails with the init up stops, then destroys, the container it made" \
  all 'rc 1' '[ -n "$app_g" ]' 'called "pct start $app_g"' 'called_re "^pct shutdown $app_g "' 'called "pct destroy $app_g"' \
      '! grep -q "^$app_g " "$S/db"' '[ ! -e "$S/run/nexcage/app-g" ]' '! kill -0 "$(init_pid "$app_g")" 2>/dev/null'
# The undo checks that the VMID is still the container run made, as stop and
# delete check one they found: while pct start ran, the CT can have been
# destroyed through its record and its VMID taken by the next container made,
# which is neither stopped nor destroyed in its place.
cat > "$S/meanwhile.start" <<'SH'
# app-h is destroyed elsewhere and other-h takes its VMID
awk '$3=="app-h" {$3="other-h"} {print}' "$SIM/db" > "$SIM/db.tmp" && mv "$SIM/db.tmp" "$SIM/db"
SH
nx run --name app-h "$TPL"
app_h=$(sed -n 's/^pct create \([0-9]*\) .*/\1/p' "$S/calls.last")
check "run whose start fails leaves alone a VMID that changed hands during the start" \
  all 'rc 1' '[ -n "$app_h" ]' 'called "pct start $app_h"' 'err_has "no longer"' 'not_called_re "^pct (shutdown|destroy) "' \
      'grep -qx "$app_h running other-h" "$S/db"' 'kill -0 "$(init_pid "$app_h")"'
rm -f "$S/fail_after_start" "$S/meanwhile.start"
pct_ns shutdown "$app_h"; pct_ns destroy "$app_h"; rm -rf "${S:?}/run/nexcage/app-h"
nx run --name app-2;        check "run without image -> exit 2" rc 2
# run used to accept these and drop them: --node made the container on this
# host, and a caller passing --console-socket waited for a pty that never came.
for flag in "--node titan" "--console-socket /tmp/sim-console.sock" "--pid-file /tmp/sim-run.pid"; do
  # shellcheck disable=SC2086 # the flag and its value are two words
  nx run --name app-3 $flag "$TPL"
  check "run ${flag%% *} is refused, nothing created" \
    all 'rc 1' "err_has '${flag%% *}'" 'not_called_re "^pct create"' 'not_called_re "^pvesh create"'
done

echo "=== option parsing ==="
# An option no command takes is refused by name (#355). It used to be skipped,
# and its value taken for the next positional word.
nx create --name typo-1 --memroy 2G "$TPL"
check "a misspelt option is refused by name, not read as the image" \
  all 'rc 2' "err_has \"unknown option '--memroy' for 'create'\"" '! err_has "OCI bundle"' 'not_called_re "^pct create"'
nx kill --al web-1
check "an unknown flag without a value is refused, not dropped" \
  all 'rc 2' "err_has \"unknown option '--al'\"" 'not_called_re "^(pct|pvesh|kill)"'
nx run --name r-9 --memory 1G "$TPL"
check "an option of another command is unknown here: run does not take --memory" \
  all 'rc 2' "err_has \"unknown option '--memory' for 'run'\"" 'not_called_re "^pct create"'
nx state --name
check "a value flag with nothing after it says so" all 'rc 2' 'err_has "needs a value"'
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
check "--runtime vm after the command -> exit 2, the backend was removed in 0.14.0" all 'rc 2' 'err_has "removed in 0.14.0"' 'not_called_re "^pct start"'
nx create --name rt-2 --runtime bogus "$TPL"
check "unknown --runtime -> exit 2, nothing run" all 'rc 2' 'err_has "unknown runtime"' 'not_called_re "^pct"'
nx state --runtime crun rt-0
check "state --runtime crun -> exit 1, no made-up state" all 'rc 1' '[ ! -s "$S/out" ]'

echo "=== --config ==="
printf '%s\n' '{"network":{"bridge":"vmbr77"},"proxmox":{"storage":"alt-store","rootfs_size_gb":3}}' > "$S/work/alt.json"
nx create --config alt.json --name cf-1 "$TPL"
check "--config <file> after the command is the file read" \
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
# The file decides whether containers are privileged and where root appends
# its log, so only root (or the user running nexcage) may be able to write it.
cfg '{"network":{"bridge":"vmbr666"},"proxmox":{"unprivileged":false}}'
chmod 666 "$S/work/config.json"
nx create --name ww-1 "$TPL"
check "a config file others can write is refused, saying why" \
  all 'rc 1' 'err_has "group or others can write it (mode 0666)"' 'not_called_re "^pct create"'
chmod 644 "$S/work/config.json"; chmod 777 "$S/work"
nx create --name ww-2 "$TPL"
check "and so is one in a directory others can write" \
  all 'rc 1' 'err_has "can write its directory (mode 0777)"' 'not_called_re "^pct create"'
chmod 1777 "$S/work"
nx create --name ww-3 "$TPL"
check "a sticky directory, as /tmp is, lets nobody else replace it" \
  all 'rc 0' 'called_re "--hostname ww-3 .*bridge=vmbr666"'
chmod 755 "$S/work"; rm -f "$S/work/config.json"
# A symlink is followed, and the directory holding the file it leads to is
# checked as the symlink's own is: a link into a directory anyone can write
# let whoever writes there choose root's configuration.
mkdir "$S/work/open"; chmod 777 "$S/work/open"
printf '%s\n' '{"network":{"bridge":"vmbr666"},"proxmox":{"unprivileged":false}}' > "$S/work/open/cfg.json"
ln -s open/cfg.json "$S/work/link.json"
nx --config link.json create --name sl-1 "$TPL"
check "a symlink into a directory others can write is refused, naming the file it leads to" \
  all 'rc 1' "err_has \"link.json: it leads to $S/work/open/cfg.json, in a directory group or others can write (mode 0777)\"" 'not_called_re "^pct create"'
chmod 755 "$S/work/open"
nx --config link.json create --name sl-2 "$TPL"
check "and followed when only its owner can write that directory" all 'rc 0' 'called_re "--hostname sl-2 .*bridge=vmbr666"'
rm -r "${S:?}/work/open" "$S/work/link.json"
# Opening a FIFO waits for a writer. One in the file's place opens at once and,
# with nothing writing to it, reads as an empty pipe does.
mkfifo "$S/work/fifo.json"
printf '#!/bin/sh\nexec timeout 10 %s "$@"\n' "$NEXCAGE" > "$S/timed-nexcage"; chmod +x "$S/timed-nexcage"
NEXCAGE=$S/timed-nexcage nx --config fifo.json list
check "a FIFO named as the config file is not waited on" \
  all 'rc 1' 'err_has "fifo.json: it is not valid JSON (UnexpectedEndOfInput)"'
rm -f "$S/work/fifo.json" "$S/timed-nexcage"
# A pipe is read as 0.17.0 read it -- `--config <(...)`, or /dev/stdin fed by
# one -- and once, since what a pipe held is gone once read: the spec check is
# made on what was read. (Not /dev/stdin here: /dev is host root's, which is
# nobody in this namespace, and a directory nobody owns is refused.)
nx --config <(printf '%s\n' '{"log_level":"debug"}') list
check "--config <(...) is read" all 'rc 0' 'err_has "DEBUG nexcage:"'
nx --config <(printf '%s\n' '{"ociVersion":"1.0.0","root":{"path":"rootfs"}}') list
check "an OCI spec in a pipe is refused as one" \
  all 'rc 1' 'err_has ": it is an OCI runtime spec, not a nexcage configuration"' 'not_called_re "^(pct|pvesh)"'
# A file owned by neither root nor the user running nexcage, as nexcage's
# namespace sees it. That namespace maps the caller's uid alone, so anyone but
# root finds one in /etc/passwd: host root's files are nobody's there, as they
# are in rootless podman's. Root -- act runs the CI jobs as root -- finds only
# files root owns in the namespace too, so it makes one, of a uid the
# namespace does not map.
foreign=/etc/passwd
if [ "$(id -u)" = 0 ]; then
  foreign=$S/work/foreign.json
  printf '%s\n' '{"network":{"bridge":"vmbr666"},"proxmox":{"unprivileged":false}}' > "$foreign"
  chown 4242 "$foreign" || echo "        cannot give $foreign to uid 4242: the next check cannot pass"
fi
owner=$(unshare -r stat -c %u "$foreign")
# The kernel shows an owner it cannot map as its overflow uid, 65534, and the
# message says that is what the number can mean.
says="it is owned by uid $owner, not by root"
[ "$owner" != "$(cat /proc/sys/kernel/overflowuid)" ] ||
  says="it is owned by uid $owner (how the kernel shows an owner outside nexcage's user namespace, as host root is under rootless podman), not by root"
nx --config "$foreign" create --name fo-1 "$TPL"
check "a config file owned by somebody else is refused, naming the owner" \
  all '[ -n "$owner" ] && [ "$owner" != 0 ]' 'rc 1' 'err_has "$says"' 'not_called_re "^(pct|pvesh)"'
rm -f "$S/work/foreign.json"
# /etc/nexcage, without --config. The simulator puts $S/etc/nexcage there for
# nexcage alone, whoever runs it and whatever /etc is on.
mkdir -p "$S/etc/nexcage"
echo "the simulator's own" > "$S/etc/nexcage/probe"
printf '#!/bin/sh\nexec cat /etc/nexcage/probe\n' > "$S/probe-nexcage"; chmod +x "$S/probe-nexcage"
NEXCAGE=$S/probe-nexcage nx
check "nexcage's /etc/nexcage is the simulator's" all 'rc 0' "out_has \"the simulator's own\""
rm -f "$S/etc/nexcage/probe" "$S/probe-nexcage"
# An OCI spec there is passed over whatever its size -- one over the 1 MiB a
# configuration may hold failed every command with FileTooBig -- and an error
# or `health` names the file actually read, not the first one that exists.
python3 -I -c 'import json,sys; json.dump({"ociVersion":"1.0.0","process":{"args":["/bin/sh"],"env":["V%d=%s"%(i,"x"*1000) for i in range(1100)]},"root":{"path":"rootfs"}}, open(sys.argv[1],"w"))' "$S/etc/nexcage/config.json"
nx list
check "an OCI spec over 1 MiB in /etc/nexcage is passed over, not a FileTooBig" \
  all 'rc 0' '! err_has "FileTooBig"' '! err_has "invalid configuration"'
printf '{"ociVersion":"1.0.0","process":{"args":["/bin/sh"]},"root":{"path":"rootfs"}}\n' > "$S/etc/nexcage/config.json"
printf '{"routnig":[]}\n' > "$S/etc/nexcage/nexcage.json"
nx list
check "an error behind a spec names the file that has it" \
  all 'rc 1' 'err_has "invalid configuration file /etc/nexcage/nexcage.json"' 'not_called_re "^(pct|pvesh)"'
printf '{"network":{"bridge":"vmbr1"}}\n' > "$S/etc/nexcage/nexcage.json"
nx health
check "health names the file read, and the spec passed over" \
  all 'err_has "Config file in use: /etc/nexcage/nexcage.json"' 'err_has "/etc/nexcage/config.json is an OCI runtime spec"'
rm -r "${S:?}/etc"

echo "=== create from an OCI bundle ==="
# A bundle's rootfs is packed into a private directory under $TMPDIR, which
# lib.sh points at $S/vartmp rather than the host's /var/tmp.
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
# A mount that is not an object left the parser's slot undefined, and freeing
# it crashed nexcage (root) after pct create had already run.
mkdir -p "$S/bundles/badmp/rootfs"
printf '{"ociVersion":"1.0.2","root":{"path":"rootfs"},"mounts":[1,"/srv:/data"]}' > "$S/bundles/badmp/config.json"
nx create --name bundle-bad /tmp/nexcage-bundles/badmp
check "bundle whose mounts hold a non-object -> exit 2 before pct create, no crash" \
  all 'rc 2' 'err_has "not a usable OCI bundle"' '! err_has "General protection"' 'not_called_re "^pct create"'
# A "mounts" that is not a list was skipped with what it held, and the
# container created without the mounts the bundle asked for.
mkdir -p "$S/bundles/objmp/rootfs"
printf '{"ociVersion":"1.0.2","root":{"path":"rootfs"},"mounts":{"destination":"/data","type":"bind","source":"/srv/data"}}' > "$S/bundles/objmp/config.json"
nx create --name bundle-objmp /tmp/nexcage-bundles/objmp
check "bundle whose mounts is an object, not a list -> exit 2 before anything is packed" \
  all 'rc 2' 'err_has "not a usable OCI bundle"' '! err_has "Packing"' 'not_called_re "nextid|^pct create"'
rm -f "$S"/tplmode.*
nx create --name bundle-1 /tmp/nexcage-bundles/b1
# The archive was written to storage local as nexcage-<name>-<time>.tar.zst
# with tar's umask, 0644: every local user could read the image's 0600 files
# while pct create ran, and for good if nexcage was interrupted, and it was a
# template other Proxmox users could use. pct create takes a file from root.
check "bundle: rootfs packed in a private directory, not the template store; pct create reads that file" \
  all 'rc 0' 'not_called_re "^pvesm path"' \
      'called_re "^pct create [0-9]+ /[^ ]+/vartmp/nexcage-bundle-bundle-1-[0-9a-f]{16}/rootfs\.tar\.zst --hostname bundle-1 "' \
      '! err_has "No mp entries"' '! err_has "not applied on the Proxmox LXC backend"'
check "bundle: the archive is 0600, in a 0700 directory, while pct create reads it" all '[ "$(cat "$S"/tplmode.*)" = "600 700" ]'
check "bundle: archive keeps the executable bit and symlinks" \
  all 'grep -qE "^-rwxr-xr-x .* \./bin/busybox$" "$S"/tarlist.*' 'grep -qE "^lrwxrwxrwx .* \./bin/sh -> busybox$" "$S"/tarlist.*'
check "bundle: archive and its directory removed after pct create" all '[ -z "$(ls -A "$S/vartmp")" ]' '[ -z "$(ls -A "$S/cache")" ]'
# A user namespace in the bundle turned on nesting=1,keyctl=1, and any other
# namespace list keyctl=1: Proxmox's AppArmor profile loosened and its keyctl
# filter lifted because a bundle asked for its own namespaces.
check "bundle: a user namespace turns on no Proxmox features" not_called_re "--features"
echo "unable to create CT - no space left" > "$S/fail_create"
nx create --name bundle-f /tmp/nexcage-bundles/b1
rm -f "$S/fail_create"
check "bundle: a failed pct create removes the archive too" all '! rc 0' 'called_re "^pct create "' '[ -z "$(ls -A "$S/vartmp")" ]' '[ -z "$(ls -A "$S/cache")" ]'
# So does a failed pack -- zstd out of space under tar, say -- which ends
# create before a VMID is taken.
: > "$S/fail_zstd"
nx create --name bundle-z /tmp/nexcage-bundles/b1
rm -f "$S/fail_zstd"
check "bundle: packing that fails removes the archive and its directory, before pct create" \
  all '! rc 0' 'err_has "Packing /tmp/nexcage-bundles/b1/rootfs failed"' 'not_called_re "nextid|^pct create"' '[ -z "$(ls -A "$S/vartmp")" ]'
# Root writes the archive by path, so the directory it is made in must be one
# where no one else can swap a symlink in: not writable by others unless
# sticky, as /var/tmp is.
mkdir -p "$S/opentmp"; chmod 777 "$S/opentmp"
TMPDIR="$S/opentmp" nx create --name bundle-open /tmp/nexcage-bundles/b1
check "bundle: a TMPDIR anyone can write to, not sticky -> refused before packing" \
  all '! rc 0' 'err_has "not a safe place"' '! err_has "Packing"' 'not_called_re "^pct create"' '[ -z "$(ls -A "$S/opentmp")" ]'
chmod 1777 "$S/opentmp"
TMPDIR="$S/opentmp" nx create --name bundle-sticky /tmp/nexcage-bundles/b1
check "bundle: a sticky TMPDIR, as /var/tmp is -> used, and left empty" \
  all 'rc 0' 'called_re "^pct create [0-9]+ /[^ ]+/opentmp/nexcage-bundle-bundle-sticky-"' '[ -z "$(ls -A "$S/opentmp")" ]'
rm -rf "$S/opentmp"
# Nor one another user owns, as a TMPDIR kept through pam_tmpdir or `sudo -E`
# can be: its owner could rename the private directory and put another
# archive where pct create reads as root. Only its owner is wrong here:
# neither its group nor others can write to it. The namespace maps only the
# uid the suite runs as, so for a user the host's /usr belongs to the
# overflow uid. For root -- act runs the suite as root -- /usr is its own,
# and a directory given to nobody stands in.
othertmp=/usr
if [ "$(id -u)" = 0 ]; then othertmp=$S/othertmp; mkdir -p -m 755 "$othertmp"; chown 65534:65534 "$othertmp"; fi
TMPDIR=$othertmp nx create --name bundle-owner /tmp/nexcage-bundles/b1
check "bundle: a TMPDIR another user owns -> refused before packing" \
  all '! rc 0' 'err_has "not a safe place"' '! err_has "Packing"' 'not_called_re "^pct create"'
rm -rf "$S/othertmp"
# A symlinked TMPDIR is resolved once, and the directory it leads to is the
# one checked and used: checked through the link, it could be pointed
# elsewhere before nexcage made its directory there.
ln -sfn vartmp "$S/linktmp"
TMPDIR="$S/linktmp" nx create --name bundle-link /tmp/nexcage-bundles/b1
check "bundle: a symlinked TMPDIR -> the directory it resolves to is checked and used" \
  all 'rc 0' 'called_re "^pct create [0-9]+ /[^ ]+/vartmp/nexcage-bundle-bundle-link-[0-9a-f]{16}/rootfs\.tar\.zst "' 'not_called_re "linktmp"' \
      '[ -z "$(ls -A "$S/vartmp")" ]'
rm -f "$S/linktmp"
# pct create takes a template path of at most 255 characters (ostemplate's
# maxLength in pve-container) and refused a longer one, after the rootfs had
# been packed. The archive's path is its directory, the name and 48 more.
name_of_len() {  # a hostname of exactly $1 characters, in labels of at most 63
  python3 -c 'import sys; s = ("a" * 62 + ".") * 5; s = s[:int(sys.argv[1])]; print(s[:-1] + "b" if s.endswith(".") else s)' "$1"
}
archive_base=$S/vartmp; fit=$((255 - ${#archive_base} - 48))
nx create --name "$(name_of_len "$((fit + 1))")" /tmp/nexcage-bundles/b1
check "bundle: a name that makes the archive's path longer than pct create takes -> refused before packing" \
  all 'rc 2' 'err_has "pct create takes a template path of at most 255"' '! err_has "Packing"' 'not_called_re "nextid|^pct create"' \
      '[ -z "$(ls -A "$S/vartmp")" ]'
nx create --name "$(name_of_len "$fit")" /tmp/nexcage-bundles/b1
check "bundle: a name that makes the archive's path 255 characters -> used" \
  all 'rc 0' 'called_re "^pct create [0-9]+ /[^ ]{254} --hostname "' '[ -z "$(ls -A "$S/vartmp")" ]'
# A signal ends nexcage without running its defers. SIGTERM goes to nexcage
# itself -- the fake pct's parent -- while pct create stands still.
echo 30 > "$S/fail_hang"; rm -f "$S/fail_hang.pid"
nexcage_ns create --name bundle-sig /tmp/nexcage-bundles/b1 > "$S/out" 2> "$S/err" & bg=$!
nexcage_pid=""; pct_pid=""
if eventually '[ -s "$S/fail_hang.pid" ]'; then read -r nexcage_pid pct_pid < "$S/fail_hang.pid"; fi
[ -n "$nexcage_pid" ] && kill -TERM "$nexcage_pid"
RC=0; wait "$bg" || RC=$?
[ -n "$pct_pid" ] && kill "$pct_pid" 2>/dev/null
rm -f "$S/fail_hang" "$S/fail_hang.pid"; LAST="nexcage create --name bundle-sig (SIGTERM during pct create)"
check "bundle: SIGTERM during pct create removes the archive, and nexcage still dies of it" \
  all 'rc 143' '[ -z "$(ls -A "$S/vartmp")" ]'
mkdir -p "$S/bundles/ns-pid"; cp -a "$S/bundles/b1/rootfs" "$S/bundles/ns-pid/"
printf '{"ociVersion":"1.0.2","root":{"path":"rootfs"},"linux":{"namespaces":[{"type":"pid"},{"type":"mount"}]}}' > "$S/bundles/ns-pid/config.json"
nx create --name ns-pid /tmp/nexcage-bundles/ns-pid
check "bundle: namespaces without a user one turn on no keyctl either" all 'rc 0' 'not_called_re "--features"'
# Proxmox confines every container its own way, and pct cannot take a
# bundle's seccomp, capabilities and the rest. They were dropped without a
# word; the container is still created (runc spec puts some in every bundle),
# with one warning that names them.
mkdir -p "$S/bundles/conf-sec"; cp -a "$S/bundles/b1/rootfs" "$S/bundles/conf-sec/"
cat > "$S/bundles/conf-sec/config.json" <<'JSON'
{"ociVersion":"1.0.2","root":{"path":"rootfs","readonly":true},
 "process":{"args":["/bin/sh"],"capabilities":{"bounding":["CAP_KILL"]},"noNewPrivileges":true},
 "linux":{"seccomp":{"defaultAction":"SCMP_ACT_ERRNO"},"maskedPaths":["/proc/kcore"],"readonlyPaths":["/proc/sys"],
          "devices":[{"path":"/dev/fuse","type":"c","major":10,"minor":229}]}}
JSON
nx create --name conf-sec /tmp/nexcage-bundles/conf-sec
check "bundle confinement the backend cannot apply: created, with one warning naming each field" \
  all 'rc 0' 'called_re "^pct create "' '[ "$(grep -c "not applied on the Proxmox LXC backend" "$S/err")" = 1 ]' \
      'err_has "process.capabilities, process.noNewPrivileges, root.readonly, linux.seccomp, linux.maskedPaths, linux.readonlyPaths, linux.devices in"' \
      'err_has "--runtime crun"'
# With --log the log is a file, and only errors were echoed to stderr: the
# warning reached the file alone, and whoever ran create never saw it.
nx --log "$S/run/conf-sec.log" create --name conf-sec-log /tmp/nexcage-bundles/conf-sec
check "bundle confinement warning with --log: in that file once, and on stderr once" \
  all 'rc 0' '[ "$(grep -c "not applied on the Proxmox LXC backend" "$S/run/conf-sec.log")" = 1 ]' \
      '[ "$(grep -c "not applied on the Proxmox LXC backend" "$S/err")" = 1 ]' \
      'grep -qE "^nexcage: warning: process\.capabilities, .* --runtime crun applies a bundle.s own$" "$S/err"'
# That stderr line is written beside the logger, and it carries the bundle's
# path, which is the caller's text: it is escaped as an echoed error is, so a
# newline in the path cannot add a line of nexcage's own.
inj=$'conf-inj\nnexcage: forged'
mkdir -p "$S/bundles/$inj"; cp -a "$S/bundles/conf-sec/rootfs" "$S/bundles/conf-sec/config.json" "$S/bundles/$inj/"
nx --log "$S/run/conf-inj.log" create --name conf-inj "/tmp/nexcage-bundles/$inj"
check "bundle confinement warning on stderr: a newline in the bundle's path is written escaped, adding no line" \
  all 'rc 0' '! grep -q "^nexcage: forged" "$S/err"' \
      'grep -qF "nexcage: warning: process.capabilities, process.noNewPrivileges, root.readonly, linux.seccomp, linux.maskedPaths, linux.readonlyPaths, linux.devices in /tmp/nexcage-bundles/conf-inj\\nnexcage: forged/config.json: not applied" "$S/err"'
rm -rf "${S:?}/bundles/$inj"
nx --log "$S/run/conf-sec-quiet.log" --log-level error create --name conf-sec-quiet /tmp/nexcage-bundles/conf-sec
check "bundle confinement warning with --log-level error: not written" all 'rc 0' '! err_has "not applied"' '! grep -qs "not applied" "$S/run/conf-sec-quiet.log"'
# The kernel filesystems at /proc, /sys and /dev are LXC's and the init's to
# mount, so a bundle's options for them are not applied either: its noexec
# on /dev/shm was dropped at debug level. A bind mount's options are applied.
mkdir -p "$S/bundles/conf-mnt"; cp -a "$S/bundles/b1/rootfs" "$S/bundles/conf-mnt/"
cat > "$S/bundles/conf-mnt/config.json" <<'JSON'
{"ociVersion":"1.0.2","root":{"path":"rootfs"},
 "mounts":[{"destination":"/proc","type":"proc","source":"proc"},
           {"destination":"/dev/shm","type":"tmpfs","source":"shm","options":["nosuid","noexec","nodev","mode=1777"]},
           {"destination":"/data","type":"bind","source":"/srv/data","options":["ro"]}]}
JSON
nx create --name conf-mnt /tmp/nexcage-bundles/conf-mnt
check "bundle mount options LXC's own /dev/shm replaces: created, and named in the one warning" \
  all 'rc 0' 'called_re "^pct set [0-9]+ --mp0 /srv/data,mp=/data,ro=1$"' \
      '[ "$(grep -c "not applied on the Proxmox LXC backend" "$S/err")" = 1 ]' \
      'err_has "nexcage: mounts[1] (/dev/shm) options in /tmp/nexcage-bundles/conf-mnt/config.json: not applied"' \
      '! err_has "mounts[0]"' '! err_has "mounts[2]"'
nx create --name bundle-mp --mp 'local-lvm:1,mp=/data' /tmp/nexcage-bundles/b1
check "--mp with a bundle is refused: the bundle's mounts take the mp entries" \
  all 'rc 2' 'err_has "--mp with an OCI bundle"' 'not_called_re "^pct create"'
# The bundle's mounts become mp entries through `pct set`, which checks them as
# Proxmox's API does. They were appended to /etc/pve/lxc/<vmid>.conf as raw
# lines, so a newline in a destination added any config line the bundle liked,
# and a comma added mp properties. The kernel filesystems a runtime-spec
# bundle mounts at their usual places are the container's own and left out.
mp_bundle() {  # <name> <the mounts array>
  mkdir -p "$S/bundles/$1"; cp -a "$S/bundles/b1/rootfs" "$S/bundles/$1/"
  printf '{"ociVersion":"1.0.2","root":{"path":"rootfs"},"mounts":%s}' "$2" > "$S/bundles/$1/config.json"
}
mp_bundle mp-ok '[{"destination":"/proc","type":"proc","source":"proc"},{"destination":"/dev","type":"tmpfs","source":"tmpfs","options":["nosuid","mode=755"]},
  {"destination":"/data","type":"bind","source":"/srv/data"}]'
nx create --name mp-ok /tmp/nexcage-bundles/mp-ok
check "bundle bind mount -> pct set --mp0 after the create; proc and /dev are the container's own" \
  all 'rc 0' 'called_re "^pct set [0-9]+ --mp0 /srv/data,mp=/data$"' 'not_called_re "--mp1|mp=/proc|mp=/dev"' \
      'grep -qx "mp0: /srv/data,mp=/data" "$S"/conf.*'
# Options were dropped, so a mount asked to be read-only and nosuid came out
# writable and setuid. "rbind" among the options makes a bind mount whatever
# the type; private propagation is what LXC gives a container's mounts.
mp_bundle mp-ro '[{"destination":"/ro","type":"bind","source":"/srv/ro","options":["rbind","ro","nosuid","nodev","noexec"]}]'
nx create --name mp-ro /tmp/nexcage-bundles/mp-ro
check "bundle mount options ro, nosuid, nodev, noexec reach the mount point, as pct takes them" \
  all 'rc 0' 'called_re "^pct set [0-9]+ --mp0 /srv/ro,mp=/ro,ro=1,mountoptions=nosuid;nodev;noexec$"' \
      'grep -qx "mp0: /srv/ro,mp=/ro,ro=1,mountoptions=nosuid;nodev;noexec" "$S"/conf.*'
mp_bundle mp-rbind '[{"destination":"/rw","type":"none","source":"/srv/rw","options":["rbind","rprivate"]}]'
nx create --name mp-rbind /tmp/nexcage-bundles/mp-rbind
check "bundle mount with rbind among its options is a bind mount" \
  all 'rc 0' 'called_re "^pct set [0-9]+ --mp0 /srv/rw,mp=/rw$"'
# A create can fail after pct create has made the CT: a bundle's bind mounts
# are a `pct set` of their own ($SIM/fail_set). The CT stayed behind, with
# perhaps half its mount points, and a retry under the same name was refused
# with "already exists". create now destroys it, with nexcage's record of it
# and the packed rootfs, before it exits 1. The refusal is pct's own for a
# bind mount asked for by someone other than root@pam, and not a lock, which
# would refuse the undo's pct destroy as well.
mp_bundle rb-1 '[{"destination":"/data","type":"bind","source":"/srv/data"}]'
echo "Permission check failed (mount point type bind is only allowed for root@pam)" > "$S/fail_set"
nx create --name rb-1 /tmp/nexcage-bundles/rb-1
rb_vmid=$(sed -n 's/^pct create \([0-9]*\) .*/\1/p' "$S/calls.last")
check "a failure after pct create destroys the container it made, its record and the packed rootfs" \
  all 'rc 1' '[ -n "$rb_vmid" ]' 'called_re "^pct set [0-9]+ --mp0 /srv/data,mp=/data$"' 'called "pct destroy $rb_vmid"' \
      '! grep -q " rb-1$" "$S/db"' '[ ! -e "$S/run/nexcage/rb-1" ]' '[ -z "$(ls -A "$S/vartmp")" ]'
rm -f "$S/fail_set"
nx create --name rb-1 /tmp/nexcage-bundles/rb-1
check "and the same name can be created again" all 'rc 0' 'grep -q " rb-1$" "$S/db"'
# A lock pct set cannot take refuses the undo's pct destroy too
# ($SIM/fail_destroy). Then nexcage's record of the CT, written as soon as
# pct create made it, is kept: an engine cleans up a failed create with
# delete --force, and with the record written last, or removed with the
# CT still there, delete --force said there was nothing to delete and the
# engine's next create of the name was refused.
mp_bundle half-1 '[{"destination":"/data","type":"bind","source":"/srv/data"}]'
echo "can't lock file '/run/lock/lxc/pve-config-0.lock' - got timeout" > "$S/fail_set"
cp "$S/fail_set" "$S/fail_destroy"
nx create --name half-1 /tmp/nexcage-bundles/half-1
check "a create whose undo cannot destroy the CT exits 1, keeps its record and says how to remove it" \
  all 'rc 1' 'called_re "^pct create [0-9]+ .*--hostname half-1 "' 'called_re "^pct set [0-9]+ --mp0 /srv/data,mp=/data$"' \
      'called_re "^pct destroy [0-9]+$"' 'grep -q " half-1$" "$S/db"' '[ -e "$S/run/nexcage/half-1/state.json" ]' \
      'err_has "delete --force half-1"' '[ -z "$(ls -A "$S/vartmp")" ]'
rm -f "$S/fail_set" "$S/fail_destroy"
half=$(awk '$3=="half-1" {print $1}' "$S/db")
nx delete --force half-1
check "and delete --force, as an engine cleans up, destroys that CT" \
  all 'rc 0' "called 'pct destroy ${half:-none}'" '! grep -q " half-1$" "$S/db"' '[ ! -e "$S/run/nexcage/half-1" ]'
nx create --name half-1 /tmp/nexcage-bundles/half-1
check "so the name can be created again" all 'rc 0' 'called_re "^pct create [0-9]+ .*--hostname half-1 "'
# The refusal quotes a path with Zig's escapes, \n or \xc2, and stderr writes
# each backslash in a message as \\: the reasons below are as stderr has them.
for bad in 'mp-nl|{"destination":"/x\nlxc.apparmor.profile: unconfined","type":"bind","source":"/srv/a"}|destination "/x\\nlxc.apparmor.profile: unconfined" contains a control character' \
           'mp-nel|{"destination":"/x\u0085lxc.apparmor.profile: unconfined","type":"bind","source":"/srv/a"}|destination "/x\\xc2\\x85lxc.apparmor.profile: unconfined" contains a control character' \
           'mp-lsep|{"destination":"/x","type":"bind","source":"/srv/a\u2028b"}|source "/srv/a\\xe2\\x80\\xa8b" contains a line or paragraph separator' \
           'mp-comma|{"destination":"/x","type":"bind","source":"/srv/a,"}|source "/srv/a," contains '"','"' or '"'='"'' \
           'mp-equals|{"destination":"/x=y","type":"bind","source":"/srv/a"}|destination "/x=y" contains '"','"' or '"'='"'' \
           'mp-rel|{"destination":"/x","type":"bind","source":"srv/a"}|source "srv/a" is not an absolute path' \
           'mp-dots|{"destination":"/data/../etc","type":"bind","source":"/srv/a"}|is not a normalised path' \
           'mp-root|{"destination":"/","type":"bind","source":"/srv/a"}|cover the container'"'"'s root' \
           'mp-dev|{"destination":"/disk","type":"bind","source":"/dev/sda1"}|as a device'"'"'s filesystem' \
           'mp-tmpfs|{"destination":"/data","type":"tmpfs","source":"tmpfs"}|can only bind-mount a host directory' \
           'mp-nodest|{"type":"bind","source":"/srv/a"}|has no destination' \
           'mp-shared|{"destination":"/x","type":"bind","source":"/srv/a","options":["rbind","rshared"]}|asks for "rshared", which a Proxmox bind mount cannot do'; do
  IFS='|' read -r name mount why <<< "$bad"
  mp_bundle "$name" "[$mount]"
  nx create --name "$name" "/tmp/nexcage-bundles/$name"
  check "bundle mount refused before anything is packed: $why" \
    all 'rc 2' 'err_has "$why"' '! err_has "Packing"' 'not_called_re "nextid|^pct (create|set)"'
done
# A container has mount points mp0 to mp255. A 257th bind mount passed
# nexcage and failed in `pct set`, after the container had been created.
many_mounts() { python3 -c 'import json,sys; print(json.dumps([{"destination":"/m%d" % i,"type":"bind","source":"/srv/m%d" % i} for i in range(int(sys.argv[1]))]))' "$1"; }
mp_bundle mp-256 "$(many_mounts 256)"
nx create --name mp-256 /tmp/nexcage-bundles/mp-256
check "bundle with 256 bind mounts -> mp0 to mp255 in one pct set" \
  all 'rc 0' 'called_re "^pct set [0-9]+ --mp0 /srv/m0,mp=/m0 .* --mp255 /srv/m255,mp=/m255$"' 'grep -qx "mp255: /srv/m255,mp=/m255" "$S"/conf.*'
mp_bundle mp-257 "$(many_mounts 257)"
nx create --name mp-257 /tmp/nexcage-bundles/mp-257
check "bundle with 257 bind mounts, more than a container has mount points -> refused before anything is packed" \
  all 'rc 2' 'err_has "the bundle has 257 bind mounts"' '! err_has "Packing"' 'not_called_re "nextid|^pct (create|set)"'
# The bundle's linux.resources. memory.limit -1 is the runtime-spec's "no
# limit", and Proxmox has none, so --memory is left out and pct's default
# applies. Both values used to be cast unchecked: -1, or shares worth more
# cores than a u32, aborted nexcage with a panic.
res_bundle() {  # <name> <the resources object>
  mkdir -p "$S/bundles/$1"; cp -a "$S/bundles/b1/rootfs" "$S/bundles/$1/"
  printf '{"ociVersion":"1.0.2","root":{"path":"rootfs"},"linux":{"resources":%s}}' "$2" > "$S/bundles/$1/config.json"
}
res_bundle res-unl '{"memory":{"limit":-1}}'
nx create --name res-unl /tmp/nexcage-bundles/res-unl
check "bundle memory.limit -1 (no limit) -> created without --memory, so pct's default" \
  all 'rc 0' 'called_re "^pct create [0-9]+ [^ ]+ --hostname res-unl --cores 1 "'
res_bundle res-neg '{"memory":{"limit":-5}}'
nx create --name res-neg /tmp/nexcage-bundles/res-neg
check "bundle memory.limit -5 -> exit 2 naming it, before anything is packed or a VMID taken" \
  all 'rc 2' 'err_has "memory.limit -5"' '! err_has "Packing"' 'not_called_re "nextid|^pct create"'
# Proxmox gives a container 16 MiB at least: a smaller limit became
# --memory 0 and was refused by pct create, after the rootfs was packed.
res_bundle res-small '{"memory":{"limit":1048576}}'
nx create --name res-small /tmp/nexcage-bundles/res-small
check "bundle memory.limit 1 MiB, below Proxmox's 16 -> exit 2 naming it, before anything is packed" \
  all 'rc 2' 'err_has "memory.limit 1048576"' '! err_has "Packing"' 'not_called_re "nextid|^pct create"'
res_bundle res-min '{"memory":{"limit":16777216}}'
nx create --name res-min /tmp/nexcage-bundles/res-min
check "bundle memory.limit 16 MiB, Proxmox's minimum -> --memory 16" \
  all 'rc 0' 'called_re "^pct create [0-9]+ [^ ]+ --hostname res-min --memory 16 "'
res_bundle res-cpu '{"cpu":{"shares":5000000000000}}'
nx create --name res-cpu /tmp/nexcage-bundles/res-cpu
check "bundle cpu.shares past the kernel's maximum -> exit 2 naming it, before anything is packed" \
  all 'rc 2' 'err_has "cpu.shares 5000000000000"' '! err_has "Packing"' 'not_called_re "nextid|^pct create"'
res_bundle res-max '{"cpu":{"shares":262144}}'
nx create --name res-max /tmp/nexcage-bundles/res-max
check "bundle cpu.shares 262144, the kernel's maximum -> --cores 256" \
  all 'rc 0' 'called_re "^pct create [0-9]+ [^ ]+ --hostname res-max --memory 512 --cores 256 "'
nx --runtime crun create --memory 1G --bundle /tmp/nexcage-bundles/b1 crun-opt
check "create's Proxmox options on the crun backend: refused, naming the bundle's config.json" \
  all 'rc 1' 'err_has "is for the Proxmox LXC backend"' 'err_has "config.json"'

echo "=== runtime-spec command line ==="
# What a container engine sends: the id positionally, the bundle behind
# --bundle, its own state directory behind --root.
nx create spec-1 --bundle /tmp/nexcage-bundles/b1
check "create <id> --bundle <dir>: the positional word is the id, not the image" \
  all 'rc 0' 'called_re "^pct create [0-9]+ /[^ ]+/nexcage-bundle-spec-1-[0-9a-f]{16}/rootfs\.tar\.zst --hostname spec-1 "'
nx state spec-1
check "state reports the bundle the container was created from" \
  all 'rc 0' '[ "$(json_get "$S/out" bundle)" = /tmp/nexcage-bundles/b1 ]'
nx start spec-1; nx state spec-1
check "start keeps the bundle in state" all 'rc 0' '[ "$(json_get "$S/out" bundle)" = /tmp/nexcage-bundles/b1 ]'
# state.json is replaced, never rewritten in place: a write that fails part
# way -- /run full, an I/O error -- leaves the record as it was. It used to be
# truncated first, so one failed start lost the bundle path for good, and a
# `state` reading in between found an empty file. A file size limit of 0 on
# nexcage alone stands in for the full /run; the fake tools lift it again.
W=$S/wrapbin; rm -rf "$W"; mkdir -p "$W"
for t in "$BIN"/*; do
  printf '#!/bin/bash\nulimit -S -f unlimited\nexec %q "$@"\n' "$t" > "$W/${t##*/}"; chmod +x "$W/${t##*/}"
done
printf '#!/bin/bash\ntrap "" XFSZ\nulimit -S -f 0\nexec %q "$@"\n' "$NEXCAGE" > "$W/nexcage"; chmod +x "$W/nexcage"
nx create spec-w --bundle /tmp/nexcage-bundles/b1
NEXCAGE=$W/nexcage BIN=$W nx start spec-w
check "start with /run full: pct start runs, and start does not fail on the bookkeeping" all 'rc 0' 'called_re "^pct start [0-9]+$"'
nx state spec-w
check "a state write that fails keeps the record it was to replace: the bundle survives" \
  all 'rc 0' '[ "$(json_get "$S/out" bundle)" = /tmp/nexcage-bundles/b1 ]' \
      '[ "$(ls -A "$S/run/nexcage/spec-w" | tr "\n" " ")" = "runtime-metadata.json state.json " ]'
rm -rf "$W"
nx create tpl-1 --bundle /tmp/nexcage-bundles/b1 >/dev/null 2>&1 || true
nx create --name from-tpl "$TPL"; nx state from-tpl
check "a container created from a template reports bundle null" \
  all 'rc 0' 'grep -q "\"bundle\": null" "$S/out"'

nx --root /run/alt list
check "--root before the command is not read as the command" all 'rc 0' '! err_has "unknown command"'
nx create --root /run/alt --name rooted-1 "$TPL"
check "--root: state goes under the given directory, not /run/nexcage" \
  all 'rc 0' '[ -f "$S/run/alt/.proxmox-lxc/rooted-1/state.json" ]' '[ ! -e "$S/run/nexcage/rooted-1" ]'
# libcrun keeps its containers in --root itself, one directory per id. The
# Proxmox backend's state.json used to go there too, and in a build with crun
# every later command took the container for libcrun's: delete removed the
# directory, said it had succeeded, and left the CT in Proxmox.
check "--root: the Proxmox backend's state is not where libcrun keeps its containers" \
  all '[ ! -e "$S/run/alt/rooted-1" ]'
# --root is normalised before it is compared with the default: /run/nexcage/
# is the default root, where from-tpl has its record, and not a caller's root
# with the records under .proxmox-lxc.
nx --root /run/nexcage/ start from-tpl
check "--root naming the default with a trailing slash is the default" all 'rc 0' 'called_re "^pct start [0-9]+$"'
nx stop from-tpl >/dev/null 2>&1   # stopped, as the checks further down expect it
nx --root /run/alt delete --force rooted-1
check "--root: delete --force reaches Proxmox and removes the state" \
  all 'rc 0' 'called_re "^pct destroy [0-9]+$"' '[ ! -e "$S/run/alt/.proxmox-lxc/rooted-1" ]'
# One id, one backend: with a record on each side, every later command would
# reach only one of the two containers. This build has no crun backend, so a
# status file under /run/crun is another runtime's container, which nexcage
# never reaches, and it holds no create up. tests/crun/lxc_root.sh checks the
# refusal in a build that has crun.
mkdir -p "$S/run/crun/both-1" && : > "$S/run/crun/both-1/status"
nx create --name both-1 "$TPL"
check "without the crun backend, another runtime's crun container does not hold up a create" \
  all 'rc 0' 'called_re "^pct create [0-9]+ .*--hostname both-1 "'
rm -rf "$S/run/crun"
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
# configuration, silently replacing it — routing rules included. Nothing in
# the working directory is read now.
printf '{"ociVersion":"1.0.0","process":{"args":["/bin/sh"]},"root":{"path":"rootfs"}}' > "$S/work/config.json"
SIM_NO_CONFIG=1 nx list
check "an OCI spec in the working directory is not read as nexcage's config" \
  all 'rc 0' '! err_has "SyntaxError"' '! err_has "invalid configuration"'
nx --config "$S/work/config.json" list
check "an OCI spec named with --config is refused, not silently ignored" \
  all 'rc 1' 'err_has "invalid configuration"'
rm -f "$S/work/config.json"

# Routing by name (ADR-001). A glob under runtime.routing is the matcher
# crun_name_patterns used to be, so the proof is both directions of one rule:
# a matching name reaches the crun backend and a non-matching one reaches pct.
# Routing picks the backend of a new container; every other command goes to
# the container itself (#372), so the proof is create.
cfg '{"runtime":{"routing":[{"pattern":"kube-ovn-*","runtime":"crun"}]}}'
nx create --name kube-ovn-1 "$TPL"
check "a glob under runtime.routing sends a matching name to crun" \
  all 'rc 1' 'err_has "not built into this binary"' 'not_called_re "^pct"'
nx create --name rt-lxc-1 "$TPL"
check "and a name it does not match goes to Proxmox LXC" \
  all 'rc 0' 'called_re "^pct create"'
# A container created under one rule is still found after the rule changes
# (#372). Every command used to route again, so the rule below sent state and
# delete to a backend that does not have the container.
cfg '{"runtime":{"routing":[{"pattern":"*","runtime":"crun"}]}}'
nx state rt-lxc-1
check "after create, the rules no longer decide: state still reaches the container" \
  all 'rc 0' 'called_re "^pct"' '! err_has "not built into this binary"'
nx delete rt-lxc-1
check "and so does delete" all 'rc 0' 'called_re "^pct destroy"'
# The removed key is refused, naming its replacement: a container it used to
# send to crun would otherwise land on the default backend.
cfg '{"container_config":{"crun_name_patterns":["kube-ovn-*"]}}'
nx state kube-ovn-1
check "crun_name_patterns refuses the file, and the message names runtime.routing" \
  all 'rc 1' 'not_called_re "^(pct|pvesh)"' 'err_has "crun_name_patterns"' 'err_has "is not read since 0.13.0"' 'err_has "runtime.routing"'
rm -f "$S/work/config.json"

# The file fails closed (#371). A misspelt runtime routed to LXC, a section
# of the wrong type panicked, and a key nexcage does not read did nothing --
# security.seccomp included. Each now refuses the file, naming the key and
# the file, before anything runs.
cfg '{"runtime":{"routing":[{"pattern":"*","runtime":"crn"}]}}'
nx state kube-ovn-1
check "a misspelt runtime refuses the file instead of routing to LXC" \
  all 'rc 1' 'err_has "runtime.routing[0].runtime"' 'err_has "which is not a runtime"' 'err_has "config.json"' 'not_called_re "^(pct|pvesh)"'
cfg '{"runtime": 5}'
nx list
check "a section of the wrong type is refused, not a panic" \
  all 'rc 1' "err_has \"'runtime' must be an object\"" '! err_has "panic"'
cfg '{"network":{"bridge":"vmbr0"},"routnig":[]}'
nx list
check "a misspelt key refuses the file, naming it" \
  all 'rc 1' "err_has \"'routnig' is not a key nexcage reads\"" 'not_called_re "^(pct|pvesh)"'
cfg '{"security":{"seccomp":true}}'
nx list
check "a key that was parsed and never used is refused too" \
  all 'rc 1' "err_has \"'security' is not a key nexcage reads\""
rm -f "$S/work/config.json"

# What the project ships, and what INSTALL.md tells an administrator to
# install, still loads. Copied as `cp` puts it in /etc/nexcage: the checkout's
# modes follow whoever cloned it, and nexcage refuses a file others can write.
for f in packaging/config/config.json packaging/config/config.oci.example.json config.json.example; do
  install -m 644 "$REPO/$f" "$S/work/shipped.json"
  nx --config "$S/work/shipped.json" version
  check "$f loads" all 'rc 0' '! err_has "invalid configuration"'
done
rm -f "$S/work/shipped.json"

# No runc backend since 0.13.0. A rule that still names it describes an OCI
# container, so it goes to crun -- and is said, since the file should change.
cfg '{"runtime":{"routing":[{"pattern":"*","runtime":"runc"}]}}'
nx create --name runc-rule-1 "$TPL"
check "a routing rule naming runc goes to crun, with a warning that says so" \
  all 'rc 1' 'err_has "not built into this binary"' 'err_has "runc is not a backend"' 'not_called_re "^pct"'
rm -f "$S/work/config.json"
nx --runtime runc state from-tpl
check "--runtime runc is refused with the replacement named, not a shorter list" \
  all 'rc 2' 'err_has "use --runtime crun"' 'not_called_re "^pct"'

# No Proxmox VM backend since 0.14.0, and nothing that could stand in for it:
# the default backend would make a container where a VM was asked for. A file
# naming it is refused before anything runs, and --runtime vm says why.
cfg '{"runtime":{"routing":[{"pattern":"vm-*","runtime":"vm"},{"pattern":"*","runtime":"lxc"}]}}'
nx list
check "a routing rule naming vm refuses the file, even for a command it does not route" \
  all 'rc 1' 'err_has "Proxmox VM backend was removed"' 'err_has "name lxc or crun"' 'not_called_re "^(pct|pvesh)"'
cfg '{"container_config":{"routing":[{"pattern":"*","runtime":"proxmox"}]}}'
nx create --name vm-1 "$TPL"
check "\"proxmox\", which named the VM backend, is refused too rather than read as lxc" \
  all 'rc 1' "err_has \"names 'proxmox'\"" 'not_called_re "^(pct|pvesh)"'
rm -f "$S/work/config.json"
nx --runtime vm state from-tpl
check "--runtime vm is refused, saying the backend was removed and what runs instead" \
  all 'rc 2' 'err_has "removed in 0.14.0"' 'err_has "use --runtime lxc or crun"' 'not_called_re "^pct"'
nx --runtime qemu state from-tpl
check "--runtime qemu likewise" all 'rc 2' 'err_has "removed in 0.14.0"'

# Isolation profiles (ADR-005). What a profile does to a container is checked
# against the kernel in tests/crun/profile.sh; here, how one is named and
# what happens when the name is wrong. An engine names one by the program
# name, so the checks run nexcage through a symlink, as BinaryName would.
cfg '{"profiles":{"hardened":{"runtime":"crun","crun":{"limits":{"pids":50}}}}}'
for p in hardened nope ""; do ln -sfn "$NEXCAGE" "$S/nexcage@$p"; done
NEXCAGE=$S/nexcage@hardened nx create --name prof-1 "$TPL"
check "nexcage@hardened creates on the profile's backend, ahead of routing" \
  all 'rc 1' 'err_has "not built into this binary"' 'not_called_re "^pct"'
nx --profile hardened create --name prof-1 "$TPL"
check "--profile names it the same way" \
  all 'rc 1' 'err_has "not built into this binary"' 'not_called_re "^pct"'
NEXCAGE=$S/nexcage@hardened nx state from-tpl
check "only create reads the profile: state under nexcage@hardened reaches an LXC container" \
  all 'rc 0' 'called_re "^pct"'
NEXCAGE=$S/nexcage@nope nx create --name prof-2 "$TPL"
check "a profile the file does not define -> exit 2, naming the ones it does, nothing created" \
  all 'rc 2' "err_has \"profile 'nope' is not defined\"" 'err_has "hardened"' 'not_called_re "^(pct|pvesh)"'
NEXCAGE=$S/nexcage@ nx create --name prof-3 "$TPL"
check "nexcage@ with no profile after it -> exit 2" all 'rc 2' "err_has \"no profile after it\"" 'not_called_re "^(pct|pvesh)"'
NEXCAGE=$S/nexcage@hardened nx --profile nope create --name prof-4 "$TPL"
check "--profile and the program name disagreeing -> exit 2" all 'rc 2' 'err_has "name different profiles"' 'not_called_re "^(pct|pvesh)"'
nx --profile hardened --runtime lxc create --name prof-5 "$TPL"
check "--runtime that disagrees with the profile -> exit 2, not a quiet override" all 'rc 2' 'not_called_re "^(pct|pvesh)"'
nx --profile hardened run --name prof-6 "$TPL"
check "run refuses a profile instead of running without it" \
  all 'rc 2' 'err_has "run takes no profile"' 'not_called_re "^(pct|pvesh)"'
cfg '{"profiles":{"lxc-hardened":{"runtime":"lxc"}}}'
nx list
check "a profile on the LXC backend refuses the file: not there yet" \
  all 'rc 1' 'err_has "profiles.lxc-hardened.runtime"' 'err_has "#316"'
cfg '{"profiles":{"x":{"runtime":"crun","crun":{"capabilities":{"drop":["NET_RAW"]}}}}}'
nx list
check "a capability not spelt as the spec spells it refuses the file" \
  all 'rc 1' 'err_has "profiles.x.crun.capabilities.drop"' 'err_has "such as \"CAP_NET_RAW\""'
cfg '{"profiles":{"x":{"runtime":"crun","crun":{"capabilities":{"drop":["CAP_NET_RAW","CAP_SYSADMIN"]}}}}}'
nx list
check "a capability the kernel does not have refuses the file, naming it: the typo would drop nothing" \
  all 'rc 1' 'err_has "profiles.x.crun.capabilities.drop"' "err_has 'names \"CAP_SYSADMIN\"'"
rm -f "$S/work/config.json" "$S"/nexcage@*

# What engines put before the command, in both their orders: go-runc's, which
# containerd's shim runs (with --rootless=<bool> when its caller sets one), and
# conmon's, for CRI-O and podman. On this backend they can only be accepted:
# Proxmox places a container's cgroup itself. tests/crun/systemd_cgroup.sh
# checks that --systemd-cgroup reaches libcrun.
nx --root /run/alt --log "$S/run/ct.json" --log-format json --systemd-cgroup --rootless=false list
check "go-runc's global options are accepted, not read as a command" \
  all 'rc 0' '! err_has "unknown"'
nx --systemd-cgroup --root=/run/alt --rootless true list
check "conmon's order, and --rootless in its two-word form, likewise" all 'rc 0' '! err_has "unknown"'
nx --root /run/alt list --systemd-cgroup --rootless=true
check "after the command, as every global option is" all 'rc 0' '! err_has "unknown"'
# a command that fails, so there is a line for the engine to read back
nx --log "$S/run/ct.json" --log-format json state no-such-container
check "--log --log-format json: the error lands in the file containerd reads" \
  all 'rc 1' '[ -s "$S/run/ct.json" ]' 'json_lines_have_error "$S/run/ct.json"'
nx --log "$S/run/ct2.json" state no-such-container
check "--log without a format writes text, not JSON" \
  all '[ -s "$S/run/ct2.json" ]' '! grep -q "level" "$S/run/ct2.json"'
nx --log "$S/run/ct2.json" state no-such-container-2
check "a second call appends to the --log file" \
  all "grep -q \"'no-such-container'\" \"\$S/run/ct2.json\"" 'grep -q "no-such-container-2" "$S/run/ct2.json"'
# An engine names a file in a directory of its own, which the runtime creates:
# a symlink in its place is not followed, and the log goes to stderr instead.
ln -sfn /run/ct-target.log "$S/run/ct-link.json"
nx --log /run/ct-link.json --log-format json state no-such-container
check "--log does not follow a symlink, and says where the log went" \
  all 'rc 1' '[ ! -e "$S/run/ct-target.log" ]' 'err_has "cannot open --log file"' 'err_has "not found"'
rm -f "$S/run/ct-link.json"
# --log-file, NEXCAGE_LOG_FILE and the configuration's log_file are opened in
# another place, the same way.
ln -sfn /run/lf-target.log "$S/run/lf-link.log"
nx --log-file /run/lf-link.log list
check "--log-file does not follow a symlink either" \
  all 'rc 0' '[ ! -e "$S/run/lf-target.log" ]' "err_has \"cannot open log file '/run/lf-link.log' (SymLinkLoop)\""
rm -f "$S/run/lf-link.log" "$S/run/lf-target.log"
# Opening a FIFO to write waits for a reader; one that nothing reads is refused
# at once, for --log and --log-file alike, and the command still runs.
mkfifo "$S/run/lf.fifo"
printf '#!/bin/sh\nexec timeout 10 %s "$@"\n' "$NEXCAGE" > "$S/timed-nexcage"; chmod +x "$S/timed-nexcage"
NEXCAGE=$S/timed-nexcage nx --log /run/lf.fifo --log-file /run/lf.fifo list
check "a FIFO named as a log file is not waited on" \
  all 'rc 0' "err_has \"cannot open --log file '/run/lf.fifo' (NoDevice)\"" "err_has \"cannot open log file '/run/lf.fifo' (NoDevice)\""
rm -f "$S/run/lf.fifo" "$S/timed-nexcage"

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
  all 'rc 1' 'err_has "does not exist"'
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

echo "=== update ==="
reset_sim
cfg '{"network":{"bridge":"vmbr0"}}'
nx create --name up-1 "$TPL" >/dev/null 2>&1
nx start up-1 >/dev/null 2>&1

# runc's words into pct's: bytes into MiB, quota over period into cores,
# shares into a cgroup v2 weight. Each is a `pct set`, and the arguments are
# the proof that the arithmetic happened.
nx update --memory 1G up-1
check "update --memory: bytes become the MiB pct takes" \
  all 'rc 0' 'called "pct set 100 --memory 1024"'
nx update --memory 1G --memory-swap 3G up-1
check "--memory-swap is memory plus swap, as runc means it; pct gets the difference" \
  all 'rc 0' 'called "pct set 100 --memory 1024 --swap 2048"'
nx update --memory-swap 1G up-1
check "--memory-swap alone reads the memory limit from the config (512 MiB) for the difference" \
  all 'rc 0' 'called "pct set 100 --swap 512"' 'called "pct config 100"'
nx update --cpu-quota 150000 --cpu-period 100000 up-1
check "quota over period is pct's cpulimit, in cores" \
  all 'rc 0' 'called "pct set 100 --cpulimit 1.5"'
nx update --cpu-quota -1 up-1
check "quota -1 lifts the limit: cpulimit 0" \
  all 'rc 0' 'called "pct set 100 --cpulimit 0"'
nx update --cpu-share 1024 up-1
check "shares become the cgroup v2 weight runc would set" \
  all 'rc 0' 'called "pct set 100 --cpuunits 39"'
# A value pct cannot say faithfully is refused, not made a different limit:
# cpulimit 0 is no limit at all, and 16 MiB is pct's least memory.
nx update --cpu-quota 50 up-1
check "a quota below a hundredth of a core is refused, not made cpulimit 0 (no limit)" \
  all 'rc 2' 'err_has "cpu.quota"' 'not_called_re "^pct set"'
nx update --cpu-quota 0 up-1
check "so is a quota of 0" all 'rc 2' 'err_has "cpu.quota"' 'not_called_re "^pct set"'
nx update --cpu-quota 1000 up-1
check "the kernel's 1 ms in pct's 100 ms period is still a limit: cpulimit 0.01" \
  all 'rc 0' 'called "pct set 100 --cpulimit 0.01"'
nx update --memory 0 up-1
check "memory 0 is refused, not made a 16 MiB limit" \
  all 'rc 2' 'err_has "memory.limit"' 'not_called_re "^pct set"'
nx update --memory 4M up-1
check "so is a memory limit below pct's 16 MiB" \
  all 'rc 2' 'err_has "16 MiB"' 'not_called_re "^pct set"'
nx update --memory 16M up-1
check "16 MiB itself is pct's least, and taken" all 'rc 0' 'called "pct set 100 --memory 16"'
nx update --cpu-share 0 up-1
check "shares 0 is refused, not made the lowest weight" \
  all 'rc 2' 'err_has "cpu.shares"' 'not_called_re "^pct set"'
nx update --pids-limit 100 up-1
check "a limit Proxmox cannot express is refused by name, not dropped" \
  all 'rc 1' 'err_has "pids.limit has no Proxmox setting"' 'not_called_re "^pct set"'
nx update --memory lots up-1
check "a size that is not one is a usage error before any backend" \
  all 'rc 2' 'err_has "not a size"' 'not_called_re "^pct set"'
nx update up-1
check "update with nothing to change is a usage error" all 'rc 2'

# Values at the top of i64 overflowed the arithmetic into pct's terms, and
# the root process died on the trap (exit 134). Each is now converted
# exactly or refused, naming the setting, before pct is asked.
nx update --memory 9223372036854775807 up-1
check "a memory limit whose MiB Proxmox cannot turn back into bytes is a usage error" \
  all 'rc 2' 'err_has "memory.limit"' 'not_called_re "^pct set"'
nx update --cpu-quota 9223372036854776 up-1
check "a quota whose cores overflow is a usage error" \
  all 'rc 2' 'err_has "cpu.quota"' 'not_called_re "^pct set"'
nx update --cpu-share 1000000000000000 up-1
check "shares past the kernel's most are its most: weight 10000, as before" \
  all 'rc 0' 'called "pct set 100 --cpuunits 10000"'
# pct keeps memory in MiB and the swap is worked out from it in bytes; a
# config Proxmox holds can have more MiB than 64 bits of bytes.
echo "memory: 8796093022208" >> "$S/conf.100"
nx update --memory-swap 1G up-1
check "a config's memory past 64 bits of bytes is an error, not a trap" \
  all 'rc 1' 'err_has "8796093022208 MiB"' 'not_called_re "^pct set"'
sed -i '/^memory: /d' "$S/conf.100"

# The shape an engine sends: a linux.resources document. Applied through
# the same arithmetic, and `-` is stdin, which is how containerd sends a
# resize (`update --resources=- <id>`).
printf '{"memory":{"limit":536870912},"cpu":{"quota":50000,"period":100000}}' > "$S/run/res.json"
nx update --resources /run/res.json up-1
check "--resources: the linux.resources document an engine sends, applied through pct" \
  all 'rc 0' 'called "pct set 100 --memory 512 --cpulimit 0.5"'
# A document on stdin through a redirect: `printf | nx` runs nx in a subshell,
# and the RC a check reads is then the previous command's.
resize() { printf '%s' "$1" > "$S/run/doc.json"; nx update --resources=- up-1 < "$S/run/doc.json"; }
resize '{"memory":{"limit":268435456}}'
check "--resources=- reads the document from stdin, as containerd sends it" \
  all 'rc 0' 'called "pct set 100 --memory 256"'
nx update --memory 1G --resources /run/res.json up-1
check "--resources together with value flags is a usage error" \
  all 'rc 2' 'not_called_re "^pct set"'
# A number in a document is a whole one in 64 bits, as libcrun reads it too.
# A float was cast: 1.5 became a limit of 1 byte, and 1e300 a trap.
resize '{"memory":{"limit":1e300}}'
check "a number in a document past i64 is refused by name, not cast" \
  all 'rc 2' 'err_has "memory.limit"' 'not_called_re "^pct set"'
resize '{"memory":{"limit":1.5}}'
check "and a fraction is not cut off into a limit" \
  all 'rc 2' 'err_has "memory.limit"' 'not_called_re "^pct set"'
resize '{"cpu":{"quota":9223372036854775807}}'
check "a document's quota whose cores overflow is refused by name" \
  all 'rc 2' 'err_has "cpu.quota"' 'not_called_re "^pct set"'
resize '{"cpu":{"quota":500,"period":1000000}}'
check "a document's quota below a hundredth of a core is refused, not made no limit" \
  all 'rc 2' 'err_has "cpu.quota"' 'not_called_re "^pct set"'
resize '{"memory":{"limit":0}}'
check "and its memory 0 is not made a 16 MiB limit" \
  all 'rc 2' 'err_has "memory.limit"' 'not_called_re "^pct set"'
# What the values leave out of a document was dropped: the rest was applied
# and the update reported success. Now it is refused by name, as pids.limit
# is, and nothing is half-applied.
resize '{"memory":{"swappiness":0}}'
check "a document's setting Proxmox has no option for is refused by name, not dropped" \
  all 'rc 1' 'err_has "memory.swappiness has no Proxmox setting"' 'not_called_re "^pct set"'
resize '{"memory":{"limit":536870912},"unified":{"memory.high":"536870912"}}'
check "beside one it applies too, so nothing is half-applied" \
  all 'rc 1' 'err_has "unified.memory.high has no Proxmox setting"' 'not_called_re "^pct set"'
resize '{"memory":{"limit":536870912,"swappiness":null},"devices":[],"unified":{}}'
check "a setting that is null or empty sets nothing, and the rest applies" \
  all 'rc 0' 'called "pct set 100 --memory 512"'
nx update --memory 1G no-such-up-$$
check "update on a container that does not exist is an error" all 'rc 1' 'not_called_re "^pct set"'

echo "=== snapshots ==="
# Proxmox takes the snapshot; nexcage names the container. The fake pct keeps
# a snapshot list per container, and the fake pvesh answers the node's
# /snapshot path from the same list, which is what `snapshots` reads.
reset_sim
cfg '{"network":{"bridge":"vmbr0"}}'
nx create --name sn-1 "$TPL" >/dev/null 2>&1

nx snapshot sn-1 before --description "before the upgrade"
check "snapshot takes one through pct, with the description" \
  all 'rc 0' 'called "pct snapshot 100 before --description before the upgrade"'
nx snapshot --description "flag first" sn-1 early
check "the description may come before the container too" \
  all 'rc 0' 'called "pct snapshot 100 early --description flag first"'
nx snapshots sn-1
check "snapshots lists them from the node's API, oldest first, without 'current'" \
  all 'rc 0' 'called_re "^pvesh get /nodes/[^/]+/lxc/100/snapshot --output-format json$"' \
      'out_has "before the upgrade"' '[ "$(awk -F"\t" "NR==2 {print \$1}" "$S/out")" = before ]' '! out_has current'
nx snapshots --format json sn-1
check "snapshots --format json is a JSON array with the names and a UTC time" \
  all 'rc 0' 'json_ok "$S/out"' \
      "[ \"\$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[1][\"name\"])' \"$S/out\")\" = early ]" \
      'grep -qE "\"created\": \"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\"" "$S/out"'
nx snapshots --format xml sn-1
check "snapshots --format takes json or table only" all 'rc 2' 'not_called_re "^pvesh"'

nx snapshot sn-1 before
check "a name already used is pct's refusal, passed on" all 'rc 1' 'err_has "already used"'
nx snapshot sn-1 current
check "'current' is Proxmox's reserved name: refused before pct" all 'rc 2' 'err_has reserved' 'not_called_re "^pct snapshot"'
# Proxmox's rule for the name (pve-configid), checked by nexcage before any pct
# or pvesh call: for a container on another node the name goes into a pvesh
# path, and that path reaches the node's shell.
nx snapshot sn-1 'a/b'
check "a snapshot name outside Proxmox's rule is a usage error, before pct" \
  all 'rc 2' 'err_has "not a snapshot name"' 'not_called_re "^pct snapshot"'
nx snapshot sn-1
check "snapshot without a name is a usage error, before any pct" all 'rc 2' 'not_called_re "^pct snapshot"'
nx snapshot sn-1 two words
check "a second word after the name is a usage error, not a name silently dropped" \
  all 'rc 2' 'not_called_re "^pct snapshot"'
# What pct says for a raw volume on a directory storage: the format cannot be
# snapshotted. nexcage adds which storages can.
echo "unable to create snapshot: can't snapshot this image format" > "$S/fail_snapshot"
nx snapshot sn-1 nope
check "a storage that cannot snapshot: pct's refusal, plus which storages can" \
  all 'rc 1' 'err_has "cannot take snapshots"' 'err_has "lvm-thin"'
rm -f "$S/fail_snapshot"

# Proxmox stops a running container itself before rolling it back, and
# nexcage's own record has to say so afterwards, as it does after stop.
nx start sn-1 >/dev/null 2>&1
nx rollback sn-1 before
check "rollback of a running container: Proxmox stops it first, through pct, exit 0" \
  all 'rc 0' 'called "pct rollback 100 before"' '[ "$(awk "\$1==100 {print \$2}" "$S/db")" = stopped ]' \
      'grep -q "^rollback: before$" "$S/conf.100"'
check "and nexcage's state record says stopped, with no pid" \
  all '[ "$(json_get "$S/run/nexcage/sn-1/state.json" status)" = stopped ]' '[ "$(json_get "$S/run/nexcage/sn-1/state.json" pid)" = 0 ]'
nx rollback sn-1 before
check "rollback of a stopped container goes through pct, and it stays stopped" \
  all 'rc 0' 'called "pct rollback 100 before"' '[ "$(awk "\$1==100 {print \$2}" "$S/db")" = stopped ]'
nx rollback sn-1 before --start
check "rollback --start asks pct to start it afterwards, and it runs" \
  all 'rc 0' 'called "pct rollback 100 before --start 1"' '[ "$(awk "\$1==100 {print \$2}" "$S/db")" = running ]'
nx state sn-1
check "state agrees it is running after rollback --start" \
  all 'rc 0' '[ "$(json_get "$S/out" status)" = running ]' '[ "$(json_get "$S/out" pid)" != 0 ]'
# A container nexcage has no record of is reached with --runtime lxc, and a
# command that changes it writes the record, so that the next one needs no
# --runtime: a rollback too, which leaves it stopped. Without --start it
# wrote none.
echo "120 stopped other-rb" >> "$S/db"
echo "snap1 0" > "$S/snaps.120"
nx --runtime lxc rollback other-rb snap1
check "rollback through --runtime lxc of a container with no record writes one, stopped" \
  all 'rc 0' 'called "pct rollback 120 snap1"' '[ "$(json_get "$S/run/nexcage/other-rb/state.json" status)" = stopped ]'
nx state other-rb
check "so the next command finds it without --runtime" all 'rc 0' '[ "$(json_get "$S/out" status)" = stopped ]'
nx stop sn-1 >/dev/null 2>&1
nx rollback sn-1 ghost
check "rollback to a snapshot that does not exist is an error" all 'rc 1' 'err_has "does not exist"'

nx create --name sn-2 "$TPL" >/dev/null 2>&1
nx snapshot sn-2 fresh >/dev/null 2>&1
nx rollback sn-2 fresh
check "a never-started container is still 'created' after a rollback" \
  all 'rc 0' '[ "$(json_get "$S/run/nexcage/sn-2/state.json" status)" = created ]'
nx state sn-2
check "and state says so" all 'rc 0' '[ "$(json_get "$S/out" status)" = created ]'

nx delsnapshot sn-1 before
check "delsnapshot removes it through pct" all 'rc 0' 'called "pct delsnapshot 100 before"'
nx snapshots sn-1
check "and the list no longer has it, while the other stays" \
  all 'rc 0' '! out_has before' 'out_has early'
nx delsnapshot sn-1 before
check "deleting it twice is an error" all 'rc 1' 'err_has "does not exist"'

nx --runtime crun snapshot sn-1 xx
check "snapshot on the crun backend is refused as a Proxmox operation, before any pct" \
  all 'rc 1' 'err_has "Proxmox VE operation"' 'not_called_re "^pct"'
nx --runtime crun snapshots sn-1
check "so is the listing" all 'rc 1' 'err_has "Proxmox VE operation"' 'not_called_re "^pvesh"'
nx snapshot no-such-sn-$$ xx
check "snapshot of a container that does not exist is an error naming it" \
  all 'rc 1' 'err_has "does not exist"' 'not_called_re "^pct snapshot"'

echo "=== the cluster ==="
# A container on another node. `pct` cannot see it -- that is what the fourth
# field means in the fake's db, and what makes these checks worth anything:
# before this, every one of them answered "not found".
reset_sim
echo "200 running remote-1 titan" >> "$S/db"
# nexcage did not create remote-1, so it has no record of it: every command
# but create names the backend with --runtime lxc.
nx start remote-1
check "a container nexcage has no record of is not looked up without --runtime lxc" \
  all 'rc 1' 'err_has "does not exist"' 'not_called_re "^(pct|pvesh)"'

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

nx --runtime lxc start remote-1
check "start on another node goes through that node's API, not pct" \
  all 'rc 0' 'called "pvesh create /nodes/titan/lxc/200/status/start"' 'not_called_re "^pct start"'

nx --runtime lxc state remote-1
check "state names the node it is on" \
  all 'rc 0' 'out_has "\"io.cageforge.nexcage.node\": \"titan\""'
check "and reports no PID, because a PID there is not a PID here" \
  out_has '"pid": 0'

nx --runtime lxc exec remote-1 echo hi
check "exec on another node is refused, and says where to run it" \
  all 'rc 1' 'err_has "runs on titan"' 'not_called_re "^pct exec"'
nx --runtime lxc kill remote-1
check "kill on another node is refused: a signal comes from the host" \
  all 'rc 1' 'err_has "runs on titan"'
nx --runtime lxc pause remote-1
check "pause on another node is refused: the freezer is that host's filesystem" \
  all 'rc 1' 'err_has "runs on titan"'
# `update` is the one thing on this list the API does have: a container's
# options are a `set` on its node's config.
nx --runtime lxc update --memory 1G remote-1
check "update on another node goes through that node's API, not pct" \
  all 'rc 0' 'called_re "^pvesh set /nodes/[^/]+/lxc/[0-9]+/config --memory 1024$"' 'not_called_re "^pct set"'

# Snapshots are the API's as well: /nodes/<node>/lxc/<vmid>/snapshot.
nx --runtime lxc snapshot remote-1 s1 --description there
check "snapshot on another node goes through that node's API, not pct" \
  all 'rc 0' 'called "pvesh create /nodes/titan/lxc/200/snapshot --snapname s1 --description there"' 'not_called_re "^pct snapshot"'
nx --runtime lxc snapshots remote-1
check "snapshots on another node reads that node's list" \
  all 'rc 0' 'called "pvesh get /nodes/titan/lxc/200/snapshot --output-format json"' 'out_has s1'
nx --runtime lxc stop remote-1 >/dev/null 2>&1
nx --runtime lxc rollback remote-1 s1 --start
check "rollback on another node goes through that node's API, with --start" \
  all 'rc 0' 'called "pvesh create /nodes/titan/lxc/200/snapshot/s1/rollback --start 1"' 'not_called_re "^pct rollback"'
nx --runtime lxc delsnapshot remote-1 s1
check "delsnapshot on another node goes through that node's API" \
  all 'rc 0' 'called "pvesh delete /nodes/titan/lxc/200/snapshot/s1"' 'not_called_re "^pct delsnapshot"'
# pvesh hands the path of a call for another node to that node's shell over
# ssh, unquoted: a snapshot name there was a command run as root on titan. One
# without '/', since a '/' splits the path and pvesh then finds no handler to
# pass it to.
nx --runtime lxc rollback remote-1 'x;touch${IFS}pwn;'
check "a snapshot name that is a shell command never reaches another node's pvesh path" \
  all 'rc 2' 'err_has "not a snapshot name"' 'not_called_re "^pvesh create /nodes/.*/snapshot/"'
nx --runtime lxc delsnapshot remote-1 '../../201/snapshot/s'
check "nor does one that climbs out of the container's snapshots" \
  all 'rc 2' 'not_called_re "^pvesh delete"'

nx create --name remote-1 "$TPL"
check "a name taken on another node is not free" \
  all 'rc 1' 'err_has "already exists on node titan"' 'not_called_re "^pct create"'

nx --runtime lxc stop remote-1
check "stop on another node goes through that node's API" \
  all 'rc 0' 'called_re "^pvesh create /nodes/titan/lxc/200/status/shutdown"'
nx --runtime lxc delete remote-1
check "delete on another node goes through that node's API" \
  all 'rc 0' 'called "pvesh delete /nodes/titan/lxc/200"'
nx --runtime lxc state remote-1
check "and afterwards it is gone from the cluster" rc 1

echo "--- the cluster's listing, large or failing ---"
# /cluster/resources has an entry for every guest on every node. A few
# thousand of them are more than the 1 MiB nexcage read from a tool, and what
# did not fit was taken for "the cluster cannot be asked": lookups fell back
# to this host's `pct list`, so a container on another node was "not found",
# list was silently short, and create's cluster-wide check passed a name
# another node had.
reset_sim
cfg '{"network":{"bridge":"vmbr0"}}'
echo "200 running remote-1 titan" >> "$S/db"
awk 'BEGIN { for (i = 1000; i < 3500; i++) printf "%d running filler-%d-%0440d titan\n", i, i, 0 }' >> "$S/db"
nx list
check "list on a cluster whose listing is over 1 MiB still shows the other node's container" \
  all 'rc 0' 'listed remote-1'
nx --runtime lxc stop remote-1
check "and a container on another node is still found" \
  all 'rc 0' 'called_re "^pvesh create /nodes/titan/lxc/200/status/shutdown"'
nx create --name remote-1 "$TPL"
check "and a name another node has is still taken" \
  all 'rc 1' 'err_has "already exists on node titan"' 'not_called_re "^pct create"'

# A cluster that cannot answer at all is an error that says so. It was the
# same quiet fallback to this host.
reset_sim
cfg '{"network":{"bridge":"vmbr0"}}'
nx create --name here-9 "$TPL" >/dev/null 2>&1
echo "200 stopped remote-9 titan" >> "$S/db"
echo "ipcc_send_rec[1] failed: Connection refused" > "$S/fail_resources"
nx list
check "a cluster listing that fails is an error naming it, not this host's list in its place" \
  all 'rc 1' 'err_has "/cluster/resources"' 'err_has "connection refused"' '! out_has "here-9"'
nx start here-9
check "and so is a lookup, even of a container on this host" \
  all 'rc 1' 'err_has "/cluster/resources"' 'not_called_re "^pct start"'
nx create --name remote-9 "$TPL"
check "create refuses a name it cannot check across the cluster" \
  all 'rc 1' 'err_has "/cluster/resources"' 'not_called_re "^pct create"'
# Whatever words the failure has. A tool's "not found" or "No such file or
# directory" is read as a missing container, which is right for a call about
# one container; for a listing it made create take the name for free.
echo "ipcc_send_rec[1] failed: No such file or directory" > "$S/fail_resources"
nx create --name remote-9 "$TPL"
check "a failing cluster listing that reads like a miss is still no answer to create" \
  all 'rc 1' 'err_has "/cluster/resources"' 'not_called_re "^pct create"'
rm -f "$S/fail_resources"
echo "No such file or directory" > "$S/fail_list"
nx create --name remote-9 "$TPL"
check "nor is a failing pct list" all 'rc 1' 'err_has "pct list"' 'not_called_re "^pct create"'
rm -f "$S/fail_list"

echo "--- which container a command acts on ---"
# A name before a VMID. One pass took the first row matching either, and the
# fake now lists rows as Proxmox does, VMIDs sorted as strings: the container
# with VMID 1000 comes before the one named 1000 at VMID 150.
reset_sim
cfg '{"network":{"bridge":"vmbr0"}}'
echo "149 stopped filler" > "$S/db"
nx create --name 1000 "$TPL" >/dev/null 2>&1
awk '$3!="filler"' "$S/db" > "$S/db.tmp" && mv "$S/db.tmp" "$S/db"; echo "999 stopped filler" >> "$S/db"
nx create --name db-prod "$TPL" >/dev/null 2>&1
awk '$3!="filler"' "$S/db" > "$S/db.tmp" && mv "$S/db.tmp" "$S/db"
check "(two containers: one named 1000, and one with VMID 1000)" \
  all 'grep -qx "150 stopped 1000" "$S/db"' 'grep -qx "1000 stopped db-prod" "$S/db"'
nx delete 1000
check "delete <name> destroys the container of that name, not the one with that VMID" \
  all 'rc 0' 'called "pct destroy 150"' 'grep -qx "1000 stopped db-prod" "$S/db"' \
      '[ ! -e "$S/run/nexcage/1000" ]' '[ -f "$S/run/nexcage/db-prod/state.json" ]'
nx --runtime lxc delete 1000
check "and the state removed is the destroyed container's, not the typed word's" \
  all 'rc 0' 'called "pct destroy 1000"' '[ ! -e "$S/run/nexcage/db-prod" ]'

# A name two containers have is refused, naming both. The first in the
# listing used to win, and that was another node's as readily as this one's.
reset_sim
cfg '{"network":{"bridge":"vmbr0"}}'
echo "149 stopped filler" > "$S/db"
nx create --name web-1 "$TPL" >/dev/null 2>&1
awk '$3!="filler"' "$S/db" > "$S/db.tmp" && mv "$S/db.tmp" "$S/db"
echo "1000 running web-1 titan" >> "$S/db"
nx delete --force web-1
check "a name two containers have is refused, naming both, and neither is touched" \
  all 'rc 1' 'err_has "VMID 1000 on titan"' 'err_has "VMID 150"' \
      'not_called_re "^(pct (shutdown|destroy)|pvesh (create|delete) /nodes/)"'
nx state web-1
check "state refuses it the same way" all 'rc 1' 'err_has "names more than one container"'
nx --runtime lxc delete 150
check "while a VMID still addresses one of them" all 'rc 0' 'called "pct destroy 150"' 'grep -q "^1000 running web-1 titan$" "$S/db"'

# A VMID can change hands between finding a container and acting on it, and
# Proxmox gives a freed VMID to the next container created. The cluster's
# listing keeps the old name for a few seconds after that ($SIM/stale_name).
reset_sim
cfg '{"network":{"bridge":"vmbr0"}}'
echo "200 running web-new titan" >> "$S/db"
echo "200 web-old" > "$S/stale_name"
nx --runtime lxc stop web-old
check "a container whose VMID has gone to another one is not stopped in its place" \
  all 'rc 1' 'err_has "no longer '"'"'web-old'"'"'"' 'not_called_re "^pvesh create /nodes/titan/lxc/200/status/"' \
      'grep -q "^200 running web-new titan$" "$S/db"'
nx --runtime lxc delete --force web-old
check "nor destroyed in its place" \
  all 'rc 1' 'not_called_re "^pvesh (create|delete) /nodes/titan/lxc/200"' 'grep -q "^200 running web-new titan$" "$S/db"'
echo "s1 0" > "$S/snaps.200"
nx --runtime lxc rollback web-old s1
check "nor rolled back in its place" \
  all 'rc 1' 'err_has "no longer"' 'not_called_re "^pvesh create /nodes/titan/lxc/200/snapshot/"' \
      'grep -q "^200 running web-new titan$" "$S/db"'
rm -f "$S/stale_name"
# On this host `pct list` is current, and its name wins over the cache's.
reset_sim
cfg '{"network":{"bridge":"vmbr0"}}'
nx create --name web-new "$TPL" >/dev/null 2>&1
echo "100 web-old" > "$S/stale_name"
nx --runtime lxc start web-old
check "a name the cluster's cache still gives a reused VMID here does not find the new container" \
  all 'rc 1' 'not_called_re "^pct start"'
nx start web-new
check "(which its own name does)" all 'rc 0' 'called "pct start 100"'
rm -f "$S/stale_name"
# kill reaches for the init from the host. A VMID that changes hands after
# the listing ($SIM/meanwhile.list runs once, right after `pct list`) is the
# same race as stop's, and SIGKILL is as final as a destroy.
reset_sim
cfg '{"network":{"bridge":"vmbr0"}}'
nx create --name web-old "$TPL" >/dev/null 2>&1
nx start web-old >/dev/null 2>&1
cat > "$S/meanwhile.list" <<'SH'
# web-old is destroyed elsewhere and web-new takes VMID 100
awk '$1==100 {$3="web-new"} {print}' "$SIM/db" > "$SIM/db.tmp" && mv "$SIM/db.tmp" "$SIM/db"
SH
nx kill web-old TERM
check "a container whose VMID changed hands after it was found is not sent the signal" \
  all 'rc 1' 'err_has "no longer"' 'not_called_re "^pct status"' '! grep -qx SIGTERM "$S/sig.100"'
rm -f "$S/meanwhile.list"
# The window that matters most: a forced delete waits for the shutdown, and
# the VMID is free once something else has destroyed the container.
reset_sim
cfg '{"network":{"bridge":"vmbr0"}}'
nx create --name web-old "$TPL" >/dev/null 2>&1
nx start web-old >/dev/null 2>&1
cat > "$S/meanwhile" <<'SH'
# web-old is destroyed elsewhere and web-new takes VMID 100
awk '$1==100 {$3="web-new"} {print}' "$SIM/db" > "$SIM/db.tmp" && mv "$SIM/db.tmp" "$SIM/db"
SH
nx delete --force web-old
check "a VMID that changed hands during delete --force's shutdown is not destroyed" \
  all 'rc 1' 'called_re "^pct shutdown 100 "' 'not_called_re "^pct destroy"' \
      'grep -q "^100 stopped web-new$" "$S/db"' 'err_has "no longer"'
rm -f "$S/meanwhile"

# A container named after its own VMID: on a fresh host `create --name 100`
# gets VMID 100, the next free one. A name equal to the VMID was taken for no
# name at all, so the container counted as found by VMID: its record was not
# written by start or stop, nor removed by delete, and nothing confirmed it
# was still the same container before it was destroyed.
reset_sim
cfg '{"network":{"bridge":"vmbr0"}}'
nx create --name 100 "$TPL" >/dev/null 2>&1
check "(a container named 100, at VMID 100)" grep -qx "100 stopped 100" "$S/db"
nx start 100 >/dev/null 2>&1; nx stop 100 >/dev/null 2>&1
check "a container named after its VMID: state after stop says stopped" status_is 100 stopped
nx delete 100
check "and delete removes its record with it" all 'rc 0' 'called "pct destroy 100"' '[ ! -e "$S/run/nexcage/100" ]'
nx create --name 100 "$TPL" >/dev/null 2>&1
nx start 100 >/dev/null 2>&1
cat > "$S/meanwhile" <<'SH'
# the container named 100 is destroyed elsewhere and web-new takes VMID 100
awk '$1==100 {$3="web-new"} {print}' "$SIM/db" > "$SIM/db.tmp" && mv "$SIM/db.tmp" "$SIM/db"
SH
nx delete --force 100
check "and a VMID that changed hands during its delete --force's shutdown is not destroyed" \
  all 'rc 1' 'called_re "^pct shutdown 100 "' 'not_called_re "^pct destroy"' \
      'grep -q "^100 stopped web-new$" "$S/db"' 'err_has "no longer"'
rm -f "$S/meanwhile"

# nexcage's record proves it made a container with that name, and says
# nothing about a VMID. A record whose container has gone -- destroyed from
# the GUI or with pct, or renamed -- still unlocked a lookup by VMID, and a
# CT nexcage never made, holding that number now, was the one destroyed.
reset_sim
cfg '{"network":{"bridge":"vmbr0"}}'
nx create --name 250 "$TPL" >/dev/null 2>&1
check "(a container named 250, at VMID 100)" grep -qx "100 stopped 250" "$S/db"
# destroyed outside nexcage, and VMID 250 is a CT nexcage did not create
echo "250 stopped tenant-b-db" > "$S/db"
nx state 250
check "through its record a numeric id is a name, not the CT with that VMID: state" \
  all 'rc 1' '[ ! -s "$S/out" ]' 'err_has "not found"'
nx delete 250
check "nor delete" all 'rc 1' 'not_called_re "^pct destroy"' 'grep -qx "250 stopped tenant-b-db" "$S/db"'
echo "250 stopped tenant-b-db" > "$S/db"   # each check on its own, whatever the last one did
nx delete --force 250
check "nor delete --force, which touches neither the CT nor anything else" \
  all 'not_called_re "^(pct (shutdown|destroy)|pvesh (create|delete) /nodes/)"' 'grep -qx "250 stopped tenant-b-db" "$S/db"'
# What is left of a container that is gone is its record, and delete --force
# is how an engine forgets one. It failed, and the record stayed until a
# reboot, keeping the id from the crun backend as well.
check "and exits 0, forgetting the record of the container that is gone" \
  all 'rc 0' '[ ! -e "$S/run/nexcage/250" ]' 'err_has "no container is named"'
echo "250 stopped tenant-b-db" > "$S/db"
nx --runtime lxc delete 250
check "while --runtime lxc still reaches the CT by its VMID" all 'rc 0' 'called "pct destroy 250"'
# Only a container no node has is forgotten that way. A listing that fails
# says nothing about it, whatever words the failure has.
nx create --name web-9 "$TPL" >/dev/null 2>&1
echo "ipcc_send_rec[1] failed: No such file or directory" > "$S/fail_resources"
nx delete --force web-9
check "a record is not forgotten when the cluster could not be asked" \
  all 'rc 1' 'err_has "/cluster/resources"' '[ -f "$S/run/nexcage/web-9/state.json" ]'
rm -f "$S/fail_resources"
# Nor while the cluster lists a container without a name ($SIM/noname): one
# its node made seconds ago, or any of a node down for five minutes. It may be
# the one, and forgetting the record left it running with nexcage told it was
# gone.
reset_sim
cfg '{"network":{"bridge":"vmbr0"}}'
echo "titan $TPL" >> "$S/node_templates"
nx create --name rem-1 --node titan "$TPL" >/dev/null 2>&1
nx start rem-1 >/dev/null 2>&1
rem=$(awk '$3=="rem-1" {print $1}' "$S/db")
check "(rem-1, made through nexcage and running on titan)" grep -qx "${rem:-none} running rem-1 titan" "$S/db"
echo "$rem" > "$S/noname"
nx delete --force rem-1
check "a record is not forgotten while the cluster lists a container without a name" \
  all 'rc 1' "err_has 'CT ${rem:-none} on titan has no name'" 'err_has "try again"' \
      '[ -f "$S/run/nexcage/rem-1/state.json" ]' 'not_called_re "^pvesh (create|delete) /nodes/titan/lxc/"'
nx create --name rem-2 "$TPL"
check "while a create is not held up by it, or a node that is down would stop every create" \
  all 'rc 0' 'called_re "^pct create [0-9]+ .*--hostname rem-2 "'
# An empty id, an unset shell variable, matched the container without a name
nx --runtime lxc delete --force ''
check "and an empty id is not taken for that container: nothing is stopped or destroyed" \
  all 'rc 1' 'not_called_re "^pvesh (create|delete) /nodes/titan/lxc/"' "grep -qx '${rem:-none} running rem-1 titan' \"\$S/db\""
rm -f "$S/noname"
nx delete --force rem-1
check "and once the cluster names it, delete --force destroys it" \
  all 'rc 0' "called 'pvesh delete /nodes/titan/lxc/${rem:-none}'" '[ ! -e "$S/run/nexcage/rem-1" ]'

echo "--- create --node ---"
reset_sim
: > "$S/node_templates"
echo "titan $TPL" >> "$S/node_templates"
cfg '{"network":{"bridge":"vmbr0"}}'

# The fake host has the zfs tools, as every stock Proxmox VE host does: --node
# used to be refused wherever `zfs version` worked.
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

# The volid's storage goes into a pvesh path on that node, and that path
# reaches the node's shell: only a <storage>:vztmpl/<file> in Proxmox's
# characters gets that far.
nx create --name there-x --node titan 'x;id;:vztmpl/a.tar'
check "create --node refuses a template volid that is not one, before that node is asked" \
  all 'rc 2' 'err_has "vztmpl"' 'not_called_re "^pvesh get /nodes/titan/storage/"'

# The template check is the point: a node that cannot see it is told so, and
# nothing is created.
nx create --name there-2 --node otherhost "$TPL"
check "a node without the template is refused, with the node named" \
  all 'rc 1' 'err_has "does not have the template"' 'not_called_re "^pvesh create /nodes/otherhost/lxc"'

# A rootfs on a ZFS storage is Proxmox's to make, on the node that owns the
# container: the stock-host setup #327 refused.
cfg '{"network":{"bridge":"vmbr0"},"proxmox":{"storage":"local-zfs","rootfs_size_gb":4}}'
nx create --name there-zs --node titan "$TPL"
check "create --node with a ZFS storage hands the rootfs to that node" \
  all 'rc 0' 'called_re "^pvesh create /nodes/titan/lxc --vmid [0-9]+ .*--hostname there-zs .*--rootfs local-zfs:4$"'
nx create --name there-o --node titan --memory 1G --vlan 7 --onboot "$TPL"
check "create --node says the same options to that node's API" \
  all 'rc 0' 'called_re "^pvesh create /nodes/titan/lxc .*--net0 name=eth0,bridge=vmbr0,ip=dhcp,tag=7 .*--memory 1024 --onboot 1"'
cfg '{"network":{"bridge":"vmbr0"}}'

# An OCI bundle is packed into a private file on *this* host, so it cannot
# travel.
nx create --name there-3 --node titan --bundle /tmp/nexcage-bundles/b1
check "--node with a bundle is refused, not half-done" \
  all 'rc 1' 'err_has "packed into a private file on this host, which titan cannot read"' '! err_has "Packing"' \
      'not_called_re "nextid|^pct create|^pvesh create"'

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

# A node that does not answer fails the listing and is named: a listing
# without its templates would read as "it has none". It was a bare
# "operation failed".
echo "500 Can't connect to 192.0.2.7:8006 (No route to host)" > "$S/fail_storage.titan"
nx images
check "images with a node that does not answer is an error naming the node" \
  all 'rc 1' 'err_has "node titan"' 'err_has "No route to host"'
nx images --node "$HOST"
check "and --node lists a node that does" all 'rc 0' 'out_has "local:vztmpl/debian-13.tar.zst"'
nx images --node titan
check "images --node on the node that does not answer names it too" \
  all 'rc 1' 'err_has "node titan"'
rm -f "$S/fail_storage.titan"

nx --runtime crun images
check "images on the crun backend says templates are not its business" \
  all 'rc 1' 'err_has "already there"'

# Pulling needs PVE 9.1+, which is where oci-registry-pull arrived.
echo 9.1.0 > "$S/pvever"
nx pull docker.io/library/nginx:1.27
check "pull names the file for the whole reference and answers with exactly that volid" \
  all 'rc 0' "called 'pvesh create /nodes/$HOST/storage/local/oci-registry-pull --reference docker.io/library/nginx:1.27 --filename $(pulled docker.io/library/nginx:1.27)'" \
      'grep -qxE "local:vztmpl/$(pulled_re docker.io/library/nginx:1.27)" "$S/out"'
nx pull docker.io/library/nginx:1.27 --node titan --storage shared-rdma
check "pull --node --storage puts it where create --node can read it" \
  all 'rc 0' 'called_re "^pvesh create /nodes/titan/storage/shared-rdma/oci-registry-pull"' \
      'grep -qxE "shared-rdma:vztmpl/$(pulled_re docker.io/library/nginx:1.27)" "$S/out"'
# Proxmox will not write over a file: a reference pulled before is that file.
nx pull docker.io/library/nginx:1.27
check "pulling a reference already there answers with its file" \
  all 'rc 0' 'grep -qxE "local:vztmpl/$(pulled_re docker.io/library/nginx:1.27)" "$S/out"'
# A name the caller chose says nothing about what the file holds: one that is
# there already is an error. It used to be answered with any template whose
# name held the image and the tag.
nx pull docker.io/library/redis:7 --filename mine >/dev/null 2>&1
nx pull docker.io/library/nginx:1.27 --filename mine
check "pull --filename onto a file that is there is an error, not some other template" \
  all 'rc 1' 'err_has "already on local"' '[ ! -s "$S/out" ]'
nx pull docker.io/library/nginx:1.27 --filename "a b"
check "pull --filename that Proxmox would rewrite is refused before pvesh" \
  all 'rc 2' 'not_called_re "^pvesh create"'
# Proxmox adds ".tar" to the name, so one ending in '.' was pulled as
# <name>..tar and printed, and then rmi and create --node refused that volid
# for its "..".
nx pull docker.io/library/redis:7 --node titan --storage shared-rdma --filename myredis.
check "pull --filename ending in '.' is refused before pvesh, since rmi could not take its file" \
  all 'rc 2' "err_has \"not ending in '.'\"" 'not_called_re "^pvesh create"' '[ ! -s "$S/out" ]'
# The tight limit on the name is the pull's task: Proxmox names the task's log
# for a UPID holding the node and the file, one file name of 255 bytes at most.
# A long reference written out whole made that UPID too long, and the pull
# failed where Proxmox's own short name had worked. The name has to leave room
# for any node's name, and a hostname may have 64 characters.
long_ref=europe-west3-docker.pkg.dev/my-gcp-project-123456/my-artifact-repo/platform-team/payments/service-name:2026.10.11-main-0123456789abcdef0123456789abcdef01234567
long_node=pve-$(printf 'n%.0s' {1..60})
nx pull "$long_ref"
check "pull of a long reference leaves room for its task's log, and answers with its file" \
  all 'rc 0' 'grep -qxE "local:vztmpl/$(pulled_re "$long_ref")" "$S/out"'
nx pull "$long_ref" --node "$long_node"
check "and so on a node whose name is as long as a hostname can be" \
  all 'rc 0' 'grep -qxE "local:vztmpl/$(pulled_re "$long_ref")" "$S/out"'
nx pull docker.io/library/nginx:1.27 --filename "$(printf 'x%.0s' {1..128})"
check "pull --filename too long for a task's log on every node is refused before pvesh" \
  all 'rc 2' 'err_has "at most 127"' 'not_called_re "^pvesh create"'
# `create` takes the file under a reference's derived name for that reference,
# so a pull of another one must not be written there by name.
nx pull ghcr.io/someone/redis:7 --filename "$(pulled docker.io/library/redis:7)"
check "pull --filename with the name of another reference's pull is refused before pvesh" \
  all 'rc 2' 'err_has "16 hex digits"' 'not_called_re "^pvesh create"'
nx create --name redis-2 docker.io/library/redis:7
check "and create of that reference pulls it, not ghcr.io's image" \
  all 'rc 0' 'called_re "^pvesh create .*oci-registry-pull --reference docker.io/library/redis:7 --filename "'
# Another pull's file landing meanwhile is not this one, and a listing that
# fails is an error: the listing before the pull failing once used to make the
# first template on the storage the answer.
echo "local:vztmpl/alpine_3.20.tar" > "$S/also_lands"
nx pull docker.io/library/nginx:1.24
check "pull: another file landing during the pull is not reported as this one" \
  all 'rc 0' 'grep -qxE "local:vztmpl/$(pulled_re docker.io/library/nginx:1.24)" "$S/out"'
echo 1 > "$S/fail_list_in"
nx pull docker.io/library/nginx:1.23
check "pull: a storage listing that fails is an error, not some template's volid" \
  all 'rc 1' 'err_has "could not be listed"' '[ ! -s "$S/out" ]'
nx pull docker.io/library/nginx:1.27 --node titan --storage 'x;id;'
check "pull refuses a storage that is not a Proxmox storage ID, before pvesh" \
  all 'rc 2' 'err_has "storage name"' 'not_called_re "^pvesh"'
# Proxmox takes a reference with a tag and nothing else. The fake pvesh pulled
# any, and so the sim said an empty reference or one pinned by a digest gave a
# template, which on Proxmox they never do.
nx pull ''
check "pull of an empty reference is Proxmox's error, and no template" \
  all 'rc 1' 'err_has "reference: value does not match"' '[ ! -s "$S/out" ]'
nx pull "docker.io/library/redis@sha256:$(printf 'ab%.0s' {1..32})"
check "nor is one pinned by a digest, which Proxmox's pattern does not take" \
  all 'rc 1' 'err_has "reference: value does not match"' '[ ! -s "$S/out" ]'
# The first listing is this host's local: it is left out and named, and the
# other storages are still shown.
echo 1 > "$S/fail_list_in"
nx images
check "images leaves out a storage it cannot list, and says which" \
  all 'rc 0' "err_has 'storage local on $HOST could not be listed'" '! out_has "debian-13.tar.zst"' \
      'out_has "local:vztmpl/alpine-3.22.tar.zst"' 'out_has "shared-rdma:vztmpl/redis_7.tar"'

# Proxmox's pvesh exits 0 when its pull task fails, with skopeo's reason on
# stdout (#309). A refused login is reported with that reason, and with where
# the login goes: root's auth file on the node that pulls.
touch "$S/pull_refused"
nx pull ghcr.io/acme/private:1
check "a refused login gives skopeo's reason and the skopeo login line" \
  all 'rc 1' 'err_has "incorrect username or password"' \
      'err_has "skopeo login --authfile /root/.config/containers/auth.json ghcr.io"'
nx pull docker.io/acme/private:1 --node titan
check "with --node, the login goes on that node" \
  all 'rc 1' 'err_has "run as root on titan"'
rm -f "$S/pull_refused"

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
nx rmi "local:vztmpl/../../x.tar"
check "rmi refuses a volid that climbs out of vztmpl/, before any pvesh" all 'rc 2' 'not_called_re "^pvesh"'
# A tag may hold "..": the name a pull is written under does not keep it, so
# what pull prints, rmi takes.
nx pull docker.io/library/nginx:1..2
nx rmi "$(cat "$S/out")"
check "rmi takes the volid pull printed, for a tag with '..' in it too" \
  all 'rc 0' 'out_has "removed from"' 'called_re "^pvesh delete /nodes/[^/]+/storage/local/content/local:vztmpl/docker\.io_library_nginx_1\._2-[0-9a-f]{16}\.tar$"'
# A file named by hand on a storage is listed as it is, and its volid went
# into the delete's path: for another node, into that node's shell.
echo "titan local:vztmpl/evil;id>pwn.tar.zst" >> "$S/node_templates"
nx rmi "local:vztmpl/evil;id>pwn.tar.zst" --node titan
check "rmi refuses a volid outside Proxmox's file name characters, before any pvesh" \
  all 'rc 2' 'not_called_re "^pvesh"'

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
# Most of its checks look at the host, so only what does not depend on the host
# is checked here: which configuration it reports, and that it asks no outside
# host. It used to look at /etc/nexcage/config.json, then ./config.json,
# whatever the commands read, and to run `nslookup google.com`.
cfg '{"proxmox":{"storage":"local-lvm"}}'
nx health
check "health reports the config file the commands read" err_has "Config file in use: $S/work/config.json"
check "health resolves no outside name" all '! grep -qiE "dns|google" "$S/err"'
# Only checks that can both pass and fail. Three directories nothing creates
# failed every correct host, `pct version`, which pct does not have, failed
# every node, and `pgrep nexcage` found health itself.
check "health checks only what nexcage uses, with a command pct has" \
  all 'err_has "PASS proxmox_pct_available: pct list works"' 'called "pct list"' 'not_called_re "^pct version"' \
      '! err_has "/var/lib/nexcage"' '! err_has "/var/cache/nexcage"' '! err_has "/tmp/nexcage"' '! err_has "nexcage_process"'
# It opened /tmp/nexcage as root with a blocking open, in a directory anyone can
# write: a FIFO there hung it. And it read a tool's stdout to the end before
# its stderr, so a tool that filled the stderr pipe first hung it too.
mkdir -p "$S/noisy"
printf '#!/bin/sh\nmkfifo /tmp/nexcage && exec timeout 10 %s "$@"\n' "$NEXCAGE" > "$S/noisy/fifo-nexcage"
printf '#!/bin/sh\nhead -c 100000 /dev/zero | tr "\\000" x >&2\necho "all pools are healthy"\n' > "$S/noisy/zpool"
printf '#!/bin/sh\nPATH=%s:$PATH exec timeout 10 %s "$@"\n' "$S/noisy" "$NEXCAGE" > "$S/noisy/noisy-nexcage"
chmod +x "$S"/noisy/*
NEXCAGE=$S/noisy/fifo-nexcage nx health
check "a FIFO at /tmp/nexcage does not hang health" all '[ "$RC" != 124 ]' 'err_has "config_file"'
NEXCAGE=$S/noisy/noisy-nexcage nx health
check "a tool that fills its stderr pipe does not hang health" \
  all '[ "$RC" != 124 ]' 'err_has "PASS zfs_pool_status: zpool status -x (exit 0): all pools are healthy"'
# Under --root, create writes in the root, where libcrun keeps its containers,
# and makes <root>/.proxmox-lxc for the Proxmox LXC records. health looked only
# at the second, so a root nexcage cannot write to was "not made yet", and the
# next create failed on it. Read-only by a mount, not by its mode, so that it
# is read-only to root too, as nexcage is when act runs this as root.
printf '#!/bin/sh\nmkdir /tmp/ro-root && mount --bind /tmp/ro-root /tmp/ro-root && mount -o remount,bind,ro /tmp/ro-root && exec %s "$@"\n' "$NEXCAGE" > "$S/noisy/ro-nexcage"
chmod +x "$S/noisy/ro-nexcage"
NEXCAGE=$S/noisy/ro-nexcage nx --root /tmp/ro-root health
check "health under a read-only --root fails on the root and on the directory create would make in it" \
  all 'rc 1' 'err_has "FAIL state_root: State directory /tmp/ro-root is not writable: "' \
      'err_has "FAIL state_root: State directory /tmp/ro-root/.proxmox-lxc cannot be made: /tmp/ro-root is not writable: "' \
      '! err_has "does not exist yet"'
nx --root /run/fresh health
check "and under a --root not made yet, where it can be, both are warnings" \
  all 'err_has "WARN state_root: State directory /run/fresh does not exist yet"' \
      'err_has "WARN state_root: State directory /run/fresh/.proxmox-lxc does not exist yet"' '! err_has "FAIL state_root"'
rm -rf "$S/noisy"
printf '{}\n' > "$S/work/alt.json"
nx --config alt.json health
check "health reports the file --config names" err_has "Config file in use: alt.json"

echo
check "no leaks, panics or invalid frees in any run" all '[ "$LEAKS" = 0 ]'
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
