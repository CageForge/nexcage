#!/usr/bin/env bash
# scripts/check_runner_exposure.sh against a fake gh that answers as GitHub
# did for this repository on 2026-10-11 (two repository-level runners, four
# secrets no workflow uses), and as it will once an administrator has done
# what docs/CI_CD_SETUP.md lists.
#
#   bash tests/scripts/check_runner_exposure.sh [path/to/check_runner_exposure.sh]
set -euo pipefail

REPO=$(cd "$(dirname "$0")/../.." && pwd)
CHECK=$(realpath "${1:-$REPO/scripts/check_runner_exposure.sh}")
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

failed=0
ok()  { echo "ok   $*"; }
bad() { echo "FAIL $*"; failed=1; }

mkdir -p "$T/bin"
# The --jq results, as gh prints them; $STATE picks the answers.
cat > "$T/bin/gh" <<'FAKE'
#!/bin/sh
case "$*" in
  *fork-pr-contributor-approval*) echo all_external_contributors ;;
  "repo view"*) echo PUBLIC ;;
  *actions/runners*)
    [ "$STATE" = before ] && printf '%s\n' \
      'nexcage-e2e [self-hosted,Linux,X64,proxmox,pve9,nexcage-e2e] online' \
      'proxmox-runner [self-hosted,Linux,X64,proxmox,ubuntu] online' ;;
  *actions/secrets*)
    [ "$STATE" = before ] && printf '%s\n' GH_TOKEN PROXMOX_SSH_KEY PVE_HOST PVE_PASSWORD ;;
  *) echo "fake gh: unexpected $*" >&2; exit 1 ;;
esac
exit 0
FAKE
chmod +x "$T/bin/gh"

rc=0; PATH="$T/bin:$PATH" STATE=before bash "$CHECK" > "$T/out" 2>&1 || rc=$?
if [ "$rc" != 0 ] && grep -q 'proxmox-runner' "$T/out" && grep -q 'PROXMOX_SSH_KEY' "$T/out"; then
  ok "the settings of 2026-10-11 fail, naming the runners and the secrets"
else
  bad "the settings of 2026-10-11 fail, naming the runners and the secrets (exit $rc)"; sed 's/^/     /' "$T/out"
fi
rc=0; PATH="$T/bin:$PATH" STATE=after bash "$CHECK" > "$T/out" 2>&1 || rc=$?
if [ "$rc" = 0 ]; then ok "with the runners in a group and the secrets gone, it passes"
else bad "with the runners in a group and the secrets gone, it passes (exit $rc)"; sed 's/^/     /' "$T/out"; fi

exit "$failed"
