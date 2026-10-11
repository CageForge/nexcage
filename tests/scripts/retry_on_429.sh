#!/usr/bin/env bash
# scripts/ci/retry_on_429.sh: retries a registry command on 429 Too Many
# Requests, and only on that. The commands here are fakes that fail as
# docker does, a given number of times.
#
#   bash tests/scripts/retry_on_429.sh [path/to/retry_on_429.sh]
set -euo pipefail

REPO=$(cd "$(dirname "$0")/../.." && pwd)
RETRY=$(realpath "${1:-$REPO/scripts/ci/retry_on_429.sh}")
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

failed=0
ok()  { echo "ok   $*"; }
bad() { echo "FAIL $*"; failed=1; }

# fake N MESSAGE RC: fails with MESSAGE and RC on its first N runs, then
# succeeds. Counts its runs in $T/runs.
cat > "$T/fake" <<'FAKE'
#!/bin/sh
n=$(cat "$T/runs" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" > "$T/runs"
if [ "$n" -le "$1" ]; then echo "$2" >&2; exit "$3"; fi
echo "done"
FAKE
chmod +x "$T/fake"
export T
hub='ERROR: failed to build: failed to solve: ubuntu:26.04: failed to resolve source metadata for docker.io/library/ubuntu:26.04: unexpected status from HEAD request to https://registry-1.docker.io/v2/library/ubuntu/manifests/26.04: 429 Too Many Requests'

run() { rm -f "$T/runs"; rc=0; RETRY_DELAY=0 sh "$RETRY" "$T/fake" "$@" > "$T/out" 2>&1 || rc=$?; runs=$(cat "$T/runs" 2>/dev/null || echo 0); }

run 2 "$hub" 1
if [ "$rc" = 0 ] && [ "$runs" = 3 ]; then ok "two 429s, then success: exit 0 after three runs"
else bad "two 429s, then success: exit 0 after three runs (exit $rc, $runs runs)"; sed 's/^/     /' "$T/out"; fi

run 9 "$hub" 1
if [ "$rc" = 1 ] && [ "$runs" = 4 ]; then ok "429 every time: it gives up after four runs with the command's status"
else bad "429 every time: it gives up after four runs with the command's status (exit $rc, $runs runs)"; fi

run 1 "error: compiling nexcage failed" 3
if [ "$rc" = 3 ] && [ "$runs" = 1 ]; then ok "any other failure is returned at once, status kept"
else bad "any other failure is returned at once, status kept (exit $rc, $runs runs)"; fi

run 0 "" 0
if [ "$rc" = 0 ] && [ "$runs" = 1 ] && grep -qx 'done' "$T/out"; then ok "a success runs once, its output shown"
else bad "a success runs once, its output shown (exit $rc, $runs runs)"; fi

exit "$failed"
