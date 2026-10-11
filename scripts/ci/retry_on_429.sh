#!/bin/sh
# Runs a command that talks to a container registry -- docker build, pull,
# create -- and runs it again when, and only when, it failed because the
# registry answered 429 Too Many Requests: at most four times in all, waiting
# 20 s, 40 s, then 80 s. Docker Hub answers anonymous requests from the shared
# addresses GitHub's runners use that way; crun_build.yml failed on main
# resolving ubuntu:26.04 (run 37992572478). Any other failure is returned at
# once, so a build that is broken is not built four times.
#
# Usage: scripts/ci/retry_on_429.sh COMMAND [ARG...]
set -u

[ $# -gt 0 ] || { echo "usage: retry_on_429.sh COMMAND [ARG...]" >&2; exit 2; }
attempts=4
delay=${RETRY_DELAY:-20}
out=$(mktemp)
trap 'rm -f "$out" "$out.rc"' EXIT

attempt=1
while :; do
    # The command's own status, not tee's.
    { "$@" 2>&1; echo "$?" > "$out.rc"; } | tee "$out"
    rc=$(cat "$out.rc")
    [ "$rc" = 0 ] && exit 0
    if ! grep -qE '429 Too Many Requests|toomanyrequests' "$out"; then
        exit "$rc"
    fi
    if [ "$attempt" -ge "$attempts" ]; then
        echo "retry_on_429.sh: the registry still answers 429 after $attempts attempts; giving up" >&2
        exit "$rc"
    fi
    echo "::warning::the registry answered 429 Too Many Requests; trying again in ${delay}s ($((attempt + 1)) of $attempts)"
    sleep "$delay"
    attempt=$((attempt + 1))
    delay=$((delay * 2))
done
