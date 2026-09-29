# The image act runs this repository's ubuntu jobs in; see
# docs/LOCAL_DEVELOPMENT.md. GitHub's hosted runners ship the GitHub CLI
# and dependency_check.yml uses it; the medium act image has everything else
# those jobs need but not gh.
#
#   podman build --format docker -t localhost/nexcage-act:latest .github/act
FROM ghcr.io/catthehacker/ubuntu:act-latest
RUN apt-get update \
 && apt-get install -y --no-install-recommends gh \
 && rm -rf /var/lib/apt/lists/*
