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

# crictl and critest, from one cri-tools release, each checked against the
# sha256 GitHub records for its release asset before it is unpacked and run.
# Another release needs its two sums here as well.
ARG CRI_TOOLS_VERSION=v1.37.0
RUN set -eu; \
    for t in crictl:67c983ee8a6bbce73d39a186e633c5fe4f8a70e62171ac3bd92a9c1b2c601670 \
             critest:e39780b83deac72e3d70599a6641f4db7661b63ebe15aa6d9f6d46dde06a4c05; do \
      archive="${t%%:*}-${CRI_TOOLS_VERSION}-linux-amd64.tar.gz"; \
      curl -fsSL -o "/tmp/${archive}" \
        "https://github.com/kubernetes-sigs/cri-tools/releases/download/${CRI_TOOLS_VERSION}/${archive}"; \
      echo "${t#*:}  /tmp/${archive}" | sha256sum -c -; \
      tar -C /usr/local/bin -xzf "/tmp/${archive}"; \
      rm "/tmp/${archive}"; \
    done; \
    crictl --version && critest --version

ENTRYPOINT ["/bin/sh"]
