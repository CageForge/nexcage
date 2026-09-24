#!/usr/bin/env bash
# Registers the GitHub Actions runner on the Proxmox VE E2E node that kubemox
# created from nexcage-pve-tpl-v0-1. The template carries the runner software
# but no registration, so this runs once per node.
#
#   gh api -X POST repos/CageForge/nexcage/actions/runners/registration-token \
#     --jq .token | ssh -J root@<pve-host> root@<node> \
#     'read -r RUNNER_TOKEN; export RUNNER_TOKEN; bash -s' \
#     < scripts/register_e2e_runner.sh
#
# The token is read from stdin rather than passed as an argument so it does not
# appear in the node's process list.
set -euo pipefail

REPO_URL=${REPO_URL:-https://github.com/CageForge/nexcage}
RUNNER_USER=${RUNNER_USER:-github-runner}
RUNNER_DIR=${RUNNER_DIR:-/home/$RUNNER_USER/actions-runner}
NAME=${NAME:-$(hostname)}
# proxmox: what proxmox_e2e.yml has always asked for. pve9: this node is
# Proxmox VE 9.x, so the OCI registry path works here and the workflow can
# target it on purpose rather than by luck.
LABELS=${LABELS:-proxmox,pve9,nexcage-e2e}
: "${RUNNER_TOKEN:?RUNNER_TOKEN must be set (read from stdin by the caller)}"

[ -x "$RUNNER_DIR/config.sh" ] || { echo "no runner software in $RUNNER_DIR" >&2; exit 1; }

if [ -e "$RUNNER_DIR/.runner" ]; then
  echo "already registered:"
  python3 -c "import json;d=json.load(open('$RUNNER_DIR/.runner',encoding='utf-8-sig'));print(d['agentName'],d['gitHubUrl'])"
  exit 0
fi

# runuser passes the token through the environment, so it is not an argument
# in the node's process list until config.sh itself is exec'd.
runuser -u "$RUNNER_USER" -- env RUNNER_TOKEN="$RUNNER_TOKEN" bash -c '
  cd "$1" || exit 1
  ./config.sh --unattended --replace \
    --url "$2" --token "$RUNNER_TOKEN" \
    --name "$3" --labels "$4" --work _work
' _ "$RUNNER_DIR" "$REPO_URL" "$NAME" "$LABELS" >/dev/null

cd "$RUNNER_DIR"
./svc.sh install "$RUNNER_USER"
./svc.sh start
sleep 4
systemctl is-enabled "actions.runner.$(python3 -c "
import json;d=json.load(open('$RUNNER_DIR/.runner',encoding='utf-8-sig'))
print(d['gitHubUrl'].rstrip('/').split('/')[-2]+'-'+d['gitHubUrl'].rstrip('/').split('/')[-1]+'.'+d['agentName'])").service"
echo "RUNNER_REGISTERED"
