#!/usr/bin/env bash
# scripts/ci/check_crun_pin.sh: the Dockerfile's crun commit has to be the one
# deps/crun pins. Run against this checkout's Dockerfile, and against copies
# of it that drifted from the pin or lost the line.
#
#   bash tests/scripts/check_crun_pin.sh [path/to/check_crun_pin.sh]
set -euo pipefail

REPO=$(cd "$(dirname "$0")/../.." && pwd)
CHECK=$(realpath "${1:-$REPO/scripts/ci/check_crun_pin.sh}")
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
cd "$REPO"

failed=0
ok()  { echo "ok   $*"; }
bad() { echo "FAIL $*"; failed=1; }

pin=$(git ls-tree HEAD -- deps/crun | awk '{print $3}')
other=c1ef7a1ee256236c6d8f41a6c7cda228f8b7bb79

rc=0; sh "$CHECK" Dockerfile > "$T/out" 2>&1 || rc=$?
if [ "$rc" = 0 ]; then ok "the Dockerfile builds the pinned crun"; else bad "the Dockerfile builds the pinned crun (exit $rc)"; sed 's/^/     /' "$T/out"; fi

sed "s/$pin/$other/" Dockerfile > "$T/Dockerfile.drift"
rc=0; sh "$CHECK" "$T/Dockerfile.drift" > "$T/out" 2>&1 || rc=$?
if [ "$rc" != 0 ] && grep -q "$pin" "$T/out" && grep -q "$other" "$T/out"; then
  ok "a Dockerfile that builds another crun commit is refused, naming both"
else
  bad "a Dockerfile that builds another crun commit is refused, naming both (exit $rc)"; sed 's/^/     /' "$T/out"
fi

grep -v 'git -C deps/crun checkout' Dockerfile > "$T/Dockerfile.noline"
rc=0; sh "$CHECK" "$T/Dockerfile.noline" > "$T/out" 2>&1 || rc=$?
if [ "$rc" != 0 ]; then ok "a Dockerfile with no crun checkout line is refused"; else bad "a Dockerfile with no crun checkout line is refused"; fi

exit "$failed"
