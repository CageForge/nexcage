# The image that runs tests/cri/pod_on_nexcage.sh and tests/cri/critest.sh:
# nexcage with the crun backend, plus a container engine's CRI and the tools
# to drive and check it.
#
# Built on nexcage:ci, which the crun CI job has already built from the repo
# Dockerfile. Nothing from the repo is copied in -- the test scripts are
# mounted, because .dockerignore excludes tests/.
ARG BASE=nexcage:ci
FROM ${BASE}
USER root

RUN apt-get update && apt-get install -y --no-install-recommends \
      containerd ca-certificates curl iptables iproute2 \
      containernetworking-plugins python3 \
    && rm -rf /var/lib/apt/lists/*

# crictl and critest, from one cri-tools release.
ARG CRI_TOOLS_VERSION=v1.37.0
RUN for t in crictl critest; do \
      curl -fsSL -o /tmp/$t.tgz \
        "https://github.com/kubernetes-sigs/cri-tools/releases/download/${CRI_TOOLS_VERSION}/$t-${CRI_TOOLS_VERSION}-linux-amd64.tar.gz" \
      && tar -C /usr/local/bin -xzf /tmp/$t.tgz && rm /tmp/$t.tgz || exit 1; \
    done \
    && crictl --version && critest --version

ENTRYPOINT ["/bin/sh"]
