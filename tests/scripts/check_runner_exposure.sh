#!/usr/bin/env bash
# scripts/check_runner_exposure.sh against a fake gh that serves GitHub's REST
# answers from fixtures, shaped as the API documents them, and puts them
# through the script's own --jq filters as gh does. The fixtures: the settings
# of 2026-10-11 (two repository-level runners, four secrets no workflow uses,
# the organization's Default group as the review of this check found it --
# buildagent-node in it, public repositories let in, no workflow
# restriction -- and the workflow token's default as the audit read it,
# write and allowed to approve pull requests); the settings once an
# administrator has done what docs/CI_CD_SETUP.md lists; and each of those
# undone again, one at a time.
#
#   bash tests/scripts/check_runner_exposure.sh [path/to/check_runner_exposure.sh]
set -euo pipefail

REPO=$(cd "$(dirname "$0")/../.." && pwd)
CHECK=$(realpath "${1:-$REPO/scripts/check_runner_exposure.sh}")
command -v jq > /dev/null || { echo "FAIL this test needs jq for its fake gh"; exit 1; }
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

failed=0
ok()  { echo "ok   $*"; }
bad() { echo "FAIL $*"; failed=1; }

mkdir -p "$T/bin"
# gh api [--paginate] <endpoint> [--jq <filter>], and gh repo view <slug>
# --json <fields> --jq <filter>: the endpoint's JSON from $FIX, through the
# filter with jq -r (gh prints a string result raw). An endpoint without a
# fixture is a 404. With $DENY_ORG set, every orgs/ endpoint gives the 403
# gh got on 2026-10-11 with a token that lacks admin:org.
cat > "$T/bin/gh" <<'FAKE'
#!/bin/sh
ep='' filter='.'
if [ "$1" = repo ] && [ "$2" = view ]; then ep=repo-view; shift 3
elif [ "$1" = api ]; then shift
else echo "fake gh: unexpected $*" >&2; exit 1; fi
while [ $# -gt 0 ]; do
  case $1 in
    --paginate) ;;
    --jq|--json) [ "$1" = --jq ] && filter=$2; shift ;;
    -*) echo "fake gh: unexpected option $1" >&2; exit 1 ;;
    *) [ -z "$ep" ] || { echo "fake gh: a second endpoint $1" >&2; exit 1; }; ep=$1 ;;
  esac
  shift
done
case $ep in
  orgs/*) if [ -n "${DENY_ORG:-}" ]; then
      echo 'gh: You must be an org admin or have the runners and runner groups fine-grained permission. (HTTP 403)' >&2
      echo 'gh: This API operation needs the "admin:org" scope. To request it, run:  gh auth refresh -h github.com -s admin:org' >&2
      exit 1
    fi ;;
esac
[ -f "$FIX/$ep.json" ] || { echo "gh: Not Found (HTTP 404)" >&2; exit 1; }
exec jq -r "$filter" "$FIX/$ep.json"
FAKE
chmod +x "$T/bin/gh"

# put <fixture dir> <endpoint> <json>
put() { mkdir -p "$(dirname "$1/$2")"; printf '%s\n' "$3" > "$1/$2.json"; }
runner() { # id name status label...
  local id=$1 name=$2 status=$3; shift 3
  jq -cn --argjson id "$id" --arg name "$name" --arg status "$status" --args \
    '{id: $id, name: $name, os: "Linux", status: $status, busy: false, ephemeral: false,
      labels: [$ARGS.positional | to_entries[] | {id: (.key + 1), name: .value, type: "read-only"}]}' "$@"
}
group() { # id name visibility allows_public restricted workflow...
  local id=$1 name=$2 vis=$3 pub=$4 res=$5; shift 5
  jq -cn --argjson id "$id" --arg name "$name" --arg vis "$vis" --argjson pub "$pub" --argjson res "$res" --args \
    '{id: $id, name: $name, visibility: $vis, default: ($id == 1),
      runners_url: "https://api.github.com/orgs/CageForge/actions/runner_groups/\($id)/runners",
      inherited: false, allows_public_repositories: $pub, restricted_to_workflows: $res,
      selected_workflows: $ARGS.positional, workflow_restrictions_read_only: false}' "$@"
}
list() { local key=$1; shift; jq -cn --arg key "$key" '{total_count: ($ARGS.positional | length)} + {($key): $ARGS.positional}' --jsonargs "$@"; }
e2e=$(runner 7 nexcage-e2e online self-hosted Linux X64 proxmox pve9 nexcage-e2e)
old=$(runner 2 proxmox-runner online self-hosted Linux X64 proxmox ubuntu)
agent=$(runner 11 buildagent-node online self-hosted Linux X64)
other=$(runner 12 other-node online self-hosted Linux X64)
wf=CageForge/nexcage/.github/workflows

# 2026-10-11.
F="$T/today"
put "$F" repos/CageForge/nexcage/actions/permissions/fork-pr-contributor-approval '{"approval_policy":"all_external_contributors"}'
put "$F" repo-view '{"visibility":"PUBLIC"}'
put "$F" repos/CageForge/nexcage/actions/runners "$(list runners "$e2e" "$old")"
put "$F" repos/CageForge/nexcage/actions/secrets "$(list secrets '{"name":"GH_TOKEN"}' '{"name":"PROXMOX_SSH_KEY"}' '{"name":"PVE_HOST"}' '{"name":"PVE_PASSWORD"}')"
put "$F" orgs/CageForge/actions/runner-groups "$(list runner_groups "$(group 1 Default all true false)")"
put "$F" orgs/CageForge/actions/runner-groups/1/runners "$(list runners "$agent")"
put "$F" repos/CageForge/nexcage/actions/permissions/workflow '{"default_workflow_permissions":"write","can_approve_pull_request_reviews":true}'

# Done: nothing registered to the repository, the stale secrets gone, the
# Default group closed to public repositories, a group of another
# repository's that this one cannot use, and the E2E runner in a group
# restricted to two workflows at main.
D="$T/done"
put "$D" repos/CageForge/nexcage/actions/permissions/fork-pr-contributor-approval '{"approval_policy":"all_external_contributors"}'
put "$D" repo-view '{"visibility":"PUBLIC"}'
put "$D" repos/CageForge/nexcage/actions/runners "$(list runners)"
put "$D" repos/CageForge/nexcage/actions/secrets "$(list secrets)"
put "$D" orgs/CageForge/actions/runner-groups "$(list runner_groups \
  "$(group 1 Default all false false)" \
  "$(group 2 other-projects selected true false)" \
  "$(group 3 nexcage-e2e selected true true "$wf/proxmox_e2e.yml@refs/heads/main" "$wf/k8s_e2e.yml@refs/heads/main")")"
put "$D" orgs/CageForge/actions/runner-groups/1/runners "$(list runners "$agent")"
put "$D" orgs/CageForge/actions/runner-groups/2/repositories "$(list repositories '{"id":1,"name":"orcaaas","full_name":"CageForge/orcaaas","private":false}')"
put "$D" orgs/CageForge/actions/runner-groups/2/runners "$(list runners "$other")"
put "$D" orgs/CageForge/actions/runner-groups/3/repositories "$(list repositories '{"id":2,"name":"nexcage","full_name":"CageForge/nexcage","private":false}')"
put "$D" orgs/CageForge/actions/runner-groups/3/runners "$(list runners "$e2e")"
put "$D" repos/CageForge/nexcage/actions/permissions/workflow '{"default_workflow_permissions":"read","can_approve_pull_request_reviews":false}'

# variant <name>: a copy of the done fixtures to change, in $V.
variant() { V="$T/$1"; cp -r "$D" "$V"; }
run() { # fixture dir, then environment assignments
  local fix=$1; shift
  rc=0; env PATH="$T/bin:$PATH" FIX="$fix" "$@" bash "$CHECK" > "$T/out" 2>&1 || rc=$?
}
show() { sed 's/^/     /' "$T/out"; }

run "$F"
if [ "$rc" != 0 ] && grep -q 'proxmox-runner' "$T/out" && grep -q 'PROXMOX_SSH_KEY' "$T/out" \
   && grep -q '^FAIL runner group Default serves every workflow' "$T/out" && grep -q '^ *buildagent-node ' "$T/out" \
   && grep -q "^FAIL the workflow token's default is write, and approving pull requests is true" "$T/out"; then
  ok "the settings of 2026-10-11 fail, naming the runners, the secrets, the Default group and the token's default"
else
  bad "the settings of 2026-10-11 fail, naming the runners, the secrets, the Default group and the token's default (exit $rc)"; show
fi

run "$D"
if [ "$rc" = 0 ]; then ok "with all docs/CI_CD_SETUP.md lists done, it passes"
else bad "with all docs/CI_CD_SETUP.md lists done, it passes (exit $rc)"; show; fi

# The policy is the one barrier while a runner can be reached: with
# everything else in order, it alone has to fail the check.
variant policy
put "$V" repos/CageForge/nexcage/actions/permissions/fork-pr-contributor-approval '{"approval_policy":"first_time_contributors"}'
run "$V"
if [ "$rc" != 0 ] && grep -q '^FAIL fork-PR approval policy is first_time_contributors' "$T/out"; then
  ok "approval for first-time contributors only (2026-10-08) fails, naming the policy"
else
  bad "approval for first-time contributors only (2026-10-08) fails, naming the policy (exit $rc)"; show
fi

# Out of the repository's registration and into the organization's Default
# group as it is: every workflow of every repository, public ones included,
# can select the runner, so a pull request's own workflow can.
variant default-group
put "$V" orgs/CageForge/actions/runner-groups "$(list runner_groups "$(group 1 Default all true false)")"
put "$V" orgs/CageForge/actions/runner-groups/1/runners "$(list runners "$e2e" "$agent")"
run "$V"
if [ "$rc" != 0 ] && grep -q '^FAIL runner group Default serves every workflow' "$T/out" && grep -q '^ *nexcage-e2e .*pve9' "$T/out"; then
  ok "nexcage-e2e in an unrestricted Default group open to public repositories fails, naming it"
else
  bad "nexcage-e2e in an unrestricted Default group open to public repositories fails, naming it (exit $rc)"; show
fi

# Restricted, but to a tag pattern, a branch pattern or a workflow named
# without a branch: none is a branch a pull request cannot run at.
variant loose
put "$V" orgs/CageForge/actions/runner-groups "$(list runner_groups \
  "$(group 1 Default all false false)" \
  "$(group 3 nexcage-e2e selected true true "$wf/proxmox_e2e.yml@refs/heads/main" \
      "$wf/k8s_e2e.yml@refs/tags/v*" "$wf/k8s_e2e.yml@refs/heads/*" "$wf/proxmox_e2e.yml")")"
run "$V"
if [ "$rc" != 0 ] && grep -q '^FAIL runner group nexcage-e2e serves workflows not named at a branch' "$T/out" \
   && grep -qF " $wf/k8s_e2e.yml@refs/tags/v*" "$T/out" && grep -qF " $wf/k8s_e2e.yml@refs/heads/*" "$T/out" \
   && grep -qE " $wf/proxmox_e2e\.yml( |\$)" "$T/out" && ! grep -qF "proxmox_e2e.yml@refs/heads/main" "$T/out"; then
  ok "a group restricted to a tag or branch pattern, or an unpinned workflow, fails, naming those three"
else
  bad "a group restricted to a tag or branch pattern, or an unpinned workflow, fails, naming those three (exit $rc)"; show
fi

# The two halves of the token's default, each on its own.
for t in 'write false' 'read true'; do
  variant "token-${t% *}"
  put "$V" repos/CageForge/nexcage/actions/permissions/workflow \
    "{\"default_workflow_permissions\":\"${t% *}\",\"can_approve_pull_request_reviews\":${t#* }}"
  run "$V"
  if [ "$rc" != 0 ] && grep -q "^FAIL the workflow token's default is ${t% *}, and approving pull requests is ${t#* }" "$T/out"; then
    ok "a workflow token default of ${t% *}, approving pull requests ${t#* }, fails"
  else
    bad "a workflow token default of ${t% *}, approving pull requests ${t#* }, fails (exit $rc)"; show
  fi
done

# A default that cannot be read is not a pass either.
variant token-unread
rm "$V/repos/CageForge/nexcage/actions/permissions/workflow.json"
run "$V"
if [ "$rc" != 0 ] && grep -q '^FAIL could not read the default permissions of the workflow token' "$T/out"; then
  ok "a workflow token default that cannot be read fails"
else
  bad "a workflow token default that cannot be read fails (exit $rc)"; show
fi

# A token without admin:org cannot see the groups; that is not a pass.
run "$D" DENY_ORG=1
if [ "$rc" != 0 ] && grep -q "^FAIL could not read CageForge's runner groups .*admin:org" "$T/out"; then
  ok "runner groups that cannot be read (no admin:org) fail"
else
  bad "runner groups that cannot be read (no admin:org) fail (exit $rc)"; show
fi

exit "$failed"
