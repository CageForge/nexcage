#!/usr/bin/env bash
# What keeps a pull request's code off the self-hosted runners, and stale
# credentials out of reach, lives in GitHub's settings, not in this
# repository's files -- a pull request brings its own workflows. This reads
# those settings (read-only) and fails while any of them is not as
# docs/CI_CD_SETUP.md, "Self-hosted runners and forks", says it should be:
#
#   - every outside contributor's fork run needs approval;
#   - no runner is registered to the (public) repository itself, where no
#     runner group can restrict which workflows reach it;
#   - every runner group this repository can use, and that holds runners,
#     serves only workflows named by path at a branch (refs/heads/...);
#   - every repository secret is one a workflow uses;
#   - the workflow token is read-only unless a workflow asks for more, and
#     cannot approve pull requests.
#
# The runner groups need an organization owner's token with admin:org
# (gh auth refresh -s admin:org); without it the check fails rather than
# skip them. The secrets need a repository admin's.
#
#   bash scripts/check_runner_exposure.sh [owner/repo]
set -uo pipefail

REPO_SLUG=${1:-CageForge/nexcage}
OWNER=${REPO_SLUG%%/*}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
command -v gh >/dev/null || { echo "needs gh, logged in as an owner of $OWNER" >&2; exit 2; }

failed=0
ok()  { echo "ok   $*"; }
bad() { echo "FAIL $*"; failed=1; }

# One line per runner: its name, labels and status.
runner_line='.runners[] | "\(.name) [\([.labels[].name] | join(","))] \(.status)"'

if ! policy=$(gh api "repos/$REPO_SLUG/actions/permissions/fork-pr-contributor-approval" --jq .approval_policy); then
  bad "could not read the fork-PR approval policy"
elif [ "$policy" = all_external_contributors ]; then
  ok "fork pull requests of every outside contributor need approval"
else
  bad "fork-PR approval policy is $policy; set all_external_contributors"
fi

if ! visibility=$(gh repo view "$REPO_SLUG" --json visibility --jq .visibility) \
   || ! runners=$(gh api --paginate "repos/$REPO_SLUG/actions/runners" --jq "$runner_line"); then
  bad "could not list the repository's runners"
elif [ "$visibility" = PUBLIC ] && [ -n "$runners" ]; then
  bad "runners registered to the public repository itself; move them into a runner group (docs/CI_CD_SETUP.md):"
  printf '%s\n' "$runners" | sed 's/^/     /'
else
  ok "no runner is registered to the repository itself"
fi

# The organization's runners are in its runner groups, not in the list
# above. A group lets this repository's workflows in unless it keeps public
# repositories out or names other repositories only, and then a pull
# request's own workflow, which runs at refs/pull/<n>/merge, reaches its
# runners as easily as ours do -- unless the group is restricted to
# workflows named at a branch. Whatever a group does not say about itself
# counts as letting this repository in.
if ! groups=$(gh api --paginate "orgs/$OWNER/actions/runner-groups" \
     --jq '.runner_groups[] | [.id, .name, .visibility, .allows_public_repositories, .restricted_to_workflows, ((.selected_workflows // []) | join(" "))] | map(tostring) | @tsv'); then
  bad "could not read $OWNER's runner groups (an organization owner's token with admin:org: gh auth refresh -s admin:org)"
else
  exposed=0
  while IFS=$'\t' read -r id name gvis public restricted workflows; do
    [ -n "$id" ] || continue
    [ "$visibility" = PUBLIC ] && [ "$public" = false ] && continue
    if [ "$gvis" = selected ]; then
      if ! repos=$(gh api --paginate "orgs/$OWNER/actions/runner-groups/$id/repositories" --jq '.repositories[].full_name' < /dev/null); then
        bad "could not list the repositories of runner group $name"; exposed=1; continue
      fi
      grep -qixF "$REPO_SLUG" <<< "$repos" || continue
    fi
    if ! members=$(gh api --paginate "orgs/$OWNER/actions/runner-groups/$id/runners" --jq "$runner_line" < /dev/null); then
      bad "could not list the runners of runner group $name"; exposed=1; continue
    fi
    [ -n "$members" ] || continue
    # A pattern could match a pull request's ref; git allows none of these
    # characters in a branch name.
    loose=''
    read -r -a selected <<< "$workflows"
    for w in ${selected[@]+"${selected[@]}"}; do
      case $w in
        *[][*?]*) loose="$loose $w" ;;
        */.github/workflows/*@refs/heads/?*) ;;
        *) loose="$loose $w" ;;
      esac
    done
    [ "$restricted" = true ] && [ -z "$loose" ] && continue
    exposed=1
    if [ "$restricted" = true ]; then
      bad "runner group $name serves workflows not named at a branch (refs/heads/<branch>):$loose"
    else
      bad "runner group $name serves every workflow of $REPO_SLUG, a pull request's own among them; restrict it to workflows named at a branch, or keep $REPO_SLUG out of it:"
    fi
    printf '%s\n' "$members" | sed 's/^/     /'
  done <<< "$groups"
  [ "$exposed" = 0 ] && ok "every runner group $REPO_SLUG can use serves only workflows named at a branch, or holds no runner"
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

# Every workflow here asks for what it needs in a permissions block of its
# own, so the default reaches only a workflow without one: one pushed to a
# branch, or added later. It should get a read-only token, not write to
# contents, issues, pull requests, actions and packages.
if ! token=$(gh api "repos/$REPO_SLUG/actions/permissions/workflow" --jq '"\(.default_workflow_permissions) \(.can_approve_pull_request_reviews)"'); then
  bad "could not read the default permissions of the workflow token"
elif [ "$token" = "read false" ]; then
  ok "the workflow token is read-only by default and cannot approve pull requests"
else
  bad "the workflow token's default is ${token% *}, and approving pull requests is ${token#* }; set \"Read repository contents and packages permissions\" and untick \"Allow GitHub Actions to create and approve pull requests\""
fi

exit "$failed"
