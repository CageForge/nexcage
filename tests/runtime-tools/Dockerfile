# The runtime-spec validation suite, opencontainers/runtime-tools, against the
# -crun build (#310). Built on the image crun_build.yml has just made, so the
# binary under test is the one this CI run built.

ARG BASE=nexcage:ci

FROM golang:1.24-bookworm AS build
# runtime-tools has no releases since 2020; a commit is what can be pinned.
# 8a4db57 (2026-03-16) validates against runtime-spec v1.3.0.
ARG RUNTIME_TOOLS_COMMIT=8a4db579f5c88af5a0d036fad34bddc9c1f703f3
RUN git clone https://github.com/opencontainers/runtime-tools /runtime-tools \
    && git -C /runtime-tools checkout -q "${RUNTIME_TOOLS_COMMIT}" \
    && make -C /runtime-tools runtimetest validation-executables

FROM ${BASE}
USER root
RUN apt-get update && apt-get install -y --no-install-recommends python3 \
    && rm -rf /var/lib/apt/lists/*
COPY --from=build /runtime-tools /runtime-tools
ENTRYPOINT ["/bin/sh"]
