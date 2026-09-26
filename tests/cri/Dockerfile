# The image that runs tests/cri/pod_on_nexcage.sh: nexcage with the crun
# backend, plus a container engine's CRI and the tools to drive it.
#
# Built on nexcage:ci, which the crun CI job has already built from the repo
# Dockerfile. Nothing from the repo is copied in -- the test script is mounted,
# because .dockerignore excludes tests/.
ARG BASE=nexcage:ci
FROM ${BASE}
USER root

RUN apt-get update && apt-get install -y --no-install-recommends \
      containerd ca-certificates curl iptables iproute2 \
      containernetworking-plugins \
    && rm -rf /var/lib/apt/lists/*

ARG CRICTL_VERSION=v1.37.0
RUN curl -fsSL -o /tmp/crictl.tgz \
      "https://github.com/kubernetes-sigs/cri-tools/releases/download/${CRICTL_VERSION}/crictl-${CRICTL_VERSION}-linux-amd64.tar.gz" \
    && tar -C /usr/local/bin -xzf /tmp/crictl.tgz \
    && rm /tmp/crictl.tgz \
    && crictl --version

ENTRYPOINT ["/bin/sh"]
