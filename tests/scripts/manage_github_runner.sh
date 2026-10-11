#!/usr/bin/env bash
# scripts/manage_github_runner.sh remove: retires the runner on the Proxmox
# VE host, which must leave it deregistered from the repository and its
# service gone, not stopped until the next boot.
#
# ssh and gh are fakes that log their arguments. The fake ssh answers as the
# host does: the script connects as root, and the actions runner's config.sh
# refuses to run as root ("Must not run with sudo") unless the runner service
# sets RUNNER_ALLOW_RUNASROOT, which a login over ssh does not.
#
#   bash tests/scripts/manage_github_runner.sh [path/to/manage_github_runner.sh]
set -euo pipefail

REPO=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT=$(realpath "${1:-$REPO/scripts/manage_github_runner.sh}")
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

failed=0
ok()  { echo "ok   $*"; }
bad() { echo "FAIL $*"; failed=1; }

mkdir -p "$T/bin"
cat > "$T/bin/ssh" <<'FAKE'
#!/bin/sh
printf '%s\n' "$*" >> "$LOG_DIR/ssh.log"
case "$*" in
  *config.sh\ remove*) echo "Must not run with sudo" >&2; exit 1 ;;
esac
exit 0
FAKE
cat > "$T/bin/gh" <<'FAKE'
#!/bin/sh
printf '%s\n' "$*" >> "$LOG_DIR/gh.log"
case "$*" in
  *DELETE*) exit 0 ;;
  *actions/runners/registration-token*|*actions/runners/remove-token*) echo AAAAFAKETOKEN ;;
  *actions/runners*) echo 2 ;;
esac
exit 0
FAKE
chmod +x "$T/bin/ssh" "$T/bin/gh"

rc=0
PATH="$T/bin:$PATH" LOG_DIR=$T bash "$SCRIPT" remove > "$T/out.log" 2>&1 || rc=$?
touch "$T/ssh.log" "$T/gh.log"

if [ "$rc" = 0 ]; then ok "remove exits 0"; else bad "remove exits 0 (exit $rc)"; sed 's/^/     /' "$T/out.log"; fi
if grep -qx 'api -X DELETE repos/CageForge/nexcage/actions/runners/2' "$T/gh.log"; then
  ok "the runner is deregistered through the API, from this machine"
else
  bad "the runner is deregistered through the API, from this machine"; sed 's/^/     gh: /' "$T/gh.log"
fi
if grep -q 'systemctl disable' "$T/ssh.log"; then
  ok "the runner service is disabled, not only stopped"
else
  bad "the runner service is disabled, not only stopped"; sed 's/^/     ssh: /' "$T/ssh.log"
fi
# shellcheck disable=SC2016  # the literal text the host would have expanded
if grep -qF '$(gh' "$T/ssh.log" || grep -q 'config.sh remove' "$T/ssh.log"; then
  bad "nothing is left for the host to fetch or run as root"; sed 's/^/     ssh: /' "$T/ssh.log"
else
  ok "nothing is left for the host to fetch or run as root"
fi

exit "$failed"
