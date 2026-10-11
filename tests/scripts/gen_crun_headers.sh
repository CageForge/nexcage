#!/usr/bin/env bash
# scripts/gen_crun_headers_local.sh downloads crun's release tarball, unpacks
# it and runs its ./configure -- as root, in the release build -- and copies
# the config.h that comes out into deps/crun, where it decides what libcrun is
# compiled with. These checks run a copy of the script in a scratch
# repository against fixture tarballs that a fake curl serves; nothing is
# downloaded.
#
#   bash tests/scripts/gen_crun_headers.sh [path/to/gen_crun_headers_local.sh]
set -euo pipefail

REPO=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT=$(realpath "${1:-$REPO/scripts/gen_crun_headers_local.sh}")
T=$(mktemp -d)
planted=''
feeder=''
cleanup() {
  if [ -n "$feeder" ]; then pkill -P "$feeder" 2>/dev/null || true; kill "$feeder" 2>/dev/null || true; fi
  [ -z "$planted" ] || rm -rf "$planted"
  rm -rf "$T"
}
trap cleanup EXIT

failed=0
ok()  { echo "ok   $*"; }
bad() { echo "FAIL $*"; failed=1; }

# A release tarball whose configure writes a config.h naming the fixture, and
# leaves a mark that it ran.
mk_tarball() { # name
  local d=$T/src-$1/crun-1.30.1
  mkdir -p "$d"
  printf '#!/bin/sh\necho "#define FIXTURE_%s 1" > config.h\ntouch "%s/ran-%s"\n' "$1" "$T" "$1" > "$d/configure"
  chmod +x "$d/configure"
  tar -C "$T/src-$1" -czf "$T/$1.tar.gz" crun-1.30.1
}
mk_tarball legit
mk_tarball evil

# A scratch repository around a copy of the script, deps/crun marked as the
# fork marks it. With pin=legit the copy's pinned sha256 for 1.30.1 is the
# legit fixture's, so a run can get as far as configure.
mk_repo() { # dir [pin]
  mkdir -p "$1/scripts" "$1/deps/crun" "$1/tmp"
  cp "$SCRIPT" "$1/scripts/gen_crun_headers_local.sh"
  echo 1.30.1 > "$1/deps/crun/.upstream_tag"
  if [ "${2:-}" = legit ]; then
    local sum; sum=$(sha256sum "$T/legit.tar.gz" | cut -d' ' -f1)
    sed -i "s/^\( *1\.30\.1) echo \)[0-9a-f]\{64\}/\1$sum/" "$1/scripts/gen_crun_headers_local.sh"
  fi
}

# curl as the script uses it: the GitHub API's answer for the latest release,
# or the tarball, which is whatever $SERVE names. Every call is logged.
mkdir -p "$T/bin"
cat > "$T/bin/curl" <<'EOF'
#!/bin/sh
echo "curl $*" >> "$CURL_LOG"
out='' url=''
while [ $# -gt 0 ]; do
  case $1 in -o) out=$2; shift 2 ;; -*) shift ;; *) url=$1; shift ;; esac
done
case $url in
  https://api.github.com/repos/containers/crun/releases/latest)
    printf '{\n  "tag_name": "9.9.9",\n  "name": "9.9.9"\n}\n' ;;
  https://github.com/containers/crun/releases/download/*/crun-*.tar.gz)
    if [ -n "$out" ]; then cat "$SERVE" > "$out"; else cat "$SERVE"; fi ;;
  *) echo "curl: (22) The requested URL returned error: 404" >&2; exit 22 ;;
esac
EOF
chmod +x "$T/bin/curl"

# run_script REPO SERVE: runs the copy with the fake curl; sets rc.
run_script() {
  rc=0
  PATH="$T/bin:$PATH" SERVE="$T/$2.tar.gz" CURL_LOG="$1/curl.log" TMPDIR="$1/tmp" \
    bash "$1/scripts/gen_crun_headers_local.sh" > "$1/out.log" 2>&1 || rc=$?
}

# --- a directory planted where the script makes its own is not used --------
# The script used /tmp/crun_headers.<its pid> and `mkdir -p`, which accepts a
# directory someone else made first. That person then owns every entry in it:
# here a FIFO in place of crun.tar.gz takes the downloaded tarball and hands
# tar another one, with no race to win.
r=$T/planted
mk_repo "$r" legit
mkfifo "$T/go"
PATH="$T/bin:$PATH" SERVE="$T/legit.tar.gz" CURL_LOG="$r/curl.log" TMPDIR="$r/tmp" \
  sh -c 'echo $$ > "$1/pid"; read -r _ < "$1/go"; exec bash "$2"' sh "$T" "$r/scripts/gen_crun_headers_local.sh" \
  > "$r/out.log" 2>&1 &
victim=$!
for _ in $(seq 1 50); do [ -s "$T/pid" ] && break; sleep 0.1; done
pid=$(cat "$T/pid")
planted=/tmp/crun_headers.$pid
mkdir -m 0777 "$planted"
mkfifo "$planted/crun.tar.gz"
( cat "$planted/crun.tar.gz" > /dev/null; cat "$T/evil.tar.gz" > "$planted/crun.tar.gz" ) &
feeder=$!
disown "$feeder"
echo go > "$T/go"
for _ in $(seq 1 100); do kill -0 "$victim" 2>/dev/null || break; sleep 0.1; done
if kill -0 "$victim" 2>/dev/null; then kill "$victim"; fi
rc=0; wait "$victim" || rc=$?
if [ "$rc" = 0 ] && grep -qx '#define FIXTURE_legit 1' "$r/deps/crun/config.h" 2>/dev/null \
   && [ ! -e "$T/ran-evil" ]; then
  ok "a directory planted at /tmp/crun_headers.<pid> is not used"
else
  bad "a directory planted at /tmp/crun_headers.<pid> is not used (exit $rc; config.h: $(cat "$r/deps/crun/config.h" 2>/dev/null || echo none); planted configure ran: $([ -e "$T/ran-evil" ] && echo yes || echo no))"
  sed 's/^/     /' "$r/out.log"
fi

exit "$failed"
