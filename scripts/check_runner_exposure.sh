#!/usr/bin/env bash
# What keeps a pull request's code off the self-hosted runners, and stale
# credentials out of reach, lives in GitHub's settings, not in this
# repository's files -- a pull request brings its own workflows. This reads
# those settings (read-only; gh logged in as a repository admin, since the
# secrets list needs it) and fails while any of them is not as
# docs/CI_CD_SETUP.md, "Self-hosted runners and forks", says it should be:
#
#   - every outside contributor's fork run needs approval;
#   - no runner is registered to the (public) repository itself, where no
#     runner group can restrict which workflows reach it;
#   - every repository secret is one a workflow uses.
#
#   bash scripts/check_runner_exposure.sh [owner/repo]
set -uo pipefail

REPO_SLUG=${1:-CageForge/nexcage}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
command -v gh >/dev/null || { echo "needs gh, logged in as an admin of $REPO_SLUG" >&2; exit 2; }

failed=0
ok()  { echo "ok   $*"; }
bad() { echo "FAIL $*"; failed=1; }

if ! policy=$(gh api "repos/$REPO_SLUG/actions/permissions/fork-pr-contributor-approval" --jq .approval_policy); then
  bad "could not read the fork-PR approval policy"
elif [ "$policy" = all_external_contributors ]; then
  ok "fork pull requests of every outside contributor need approval"
else
  bad "fork-PR approval policy is $policy; set all_external_contributors"
fi

if ! visibility=$(gh repo view "$REPO_SLUG" --json visibility --jq .visibility) \
   || ! runners=$(gh api --paginate "repos/$REPO_SLUG/actions/runners" --jq '.runners[] | "\(.name) [\([.labels[].name] | join(","))] \(.status)"'); then
  bad "could not list the repository's runners"
elif [ "$visibility" = PUBLIC ] && [ -n "$runners" ]; then
  bad "runners registered to the public repository itself; move them to a runner group restricted to selected workflows:"
  printf '%s\n' "$runners" | sed 's/^/     /'
else
  ok "no runner is registered to the repository itself"
fi

if ! secrets=$(gh api --paginate "repos/$REPO_SLUG/actions/secrets" --jq '.secrets[].name'); then
  bad "could not list the repository's secrets (it needs an admin's token)"
else
  unused=''
  for s in $secrets; do
    grep -qE "secrets\\.$s([^A-Za-z0-9_]|\$)" "$ROOT"/.github/workflows/*.yml || unused="$unused $s"
  done
  if [ -n "$unused" ]; then
    bad "repository secrets no workflow uses (delete them, then rotate what they held):$unused"
  else
    ok "every repository secret is used by a workflow"
  fi
fi

exit "$failed"
