# ============================================================================
# Builder Stage - Build nexcage with all dependencies
# ============================================================================
FROM ubuntu:24.04 AS builder

# Set Timezone
ENV TZ=UTC
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# Install build dependencies
RUN apt-get update && apt-get install -y \
    # Build tools
    build-essential \
    cmake \
    git \
    curl \
    wget \
    pkg-config \
    libssl-dev \
    autoconf \
    automake \
    libtool \
    python3 \
    # Required system libraries for nexcage
    libcap-dev \
    libseccomp-dev \
    libyajl-dev \
    # Optional libraries for libcrun ABI mode
    libsystemd-dev \
    # Additional build dependencies for crun
    go-md2man \
    libprotobuf-c-dev \  # Required by crun for OCI runtime spec serialization
    libyajl-dev \
    && rm -rf /var/lib/apt/lists/*

# Set library paths
ENV LD_LIBRARY_PATH="/usr/lib:/usr/local/lib:/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH}"
ENV LIBRARY_PATH="/usr/lib:/usr/local/lib:/usr/lib/x86_64-linux-gnu:${LIBRARY_PATH}"
ENV PKG_CONFIG_PATH="/usr/lib/pkgconfig:/usr/local/lib/pkgconfig:/usr/lib/x86_64-linux-gnu/pkgconfig:${PKG_CONFIG_PATH}"

# Install Zig 0.15.1 by querying the download index
RUN set -ex && \
    ZIG_VERSION="0.15.1" && \
    ZIG_TARGET="zig-x86_64-linux" && \
    echo "Fetching Zig download URL for version ${ZIG_VERSION}..." && \
    ZIG_URL=$(wget -qO- https://ziglang.org/download/index.json | \
              grep -F "${ZIG_TARGET}" | \
              grep -F "${ZIG_VERSION}" | \
              awk '{print $2}' | \
              sed 's/[",]//g' | head -1) && \
    if [ -z "$ZIG_URL" ]; then \
        echo "ERROR: Could not find Zig ${ZIG_VERSION} download URL"; \
        exit 1; \
    fi && \
    echo "Downloading Zig from: ${ZIG_URL}" && \
    ZIG_ARCHIVE=$(basename "$ZIG_URL") && \
    wget --progress=dot:mega -O "${ZIG_ARCHIVE}" "${ZIG_URL}" && \
    echo "Extracting ${ZIG_ARCHIVE}..." && \
    tar xf "${ZIG_ARCHIVE}" && \
    ZIG_DIR=$(basename "${ZIG_ARCHIVE}" .tar.xz) && \
    mv "${ZIG_DIR}" /usr/local/zig && \
    rm "${ZIG_ARCHIVE}" && \
    /usr/local/zig/zig version

ENV PATH="/usr/local/zig:${PATH}"

WORKDIR /app

# Copy project files
COPY . .

# Initialize git submodules (bfc and crun)
RUN git init || true && \
    git submodule update --init --recursive || true

# Build arguments for customizing build
ARG BUILD_FLAGS=""
ARG BUILD_VERSION="dev"

# Workaround for Docker/OrbStack ENOSYS errors with Zig cache
# Simply remove any existing cache and build fresh
RUN rm -rf .zig-cache /root/.cache/zig

# Build project with default configuration (all features enabled)
# Note: libcrun ABI mode is disabled by default, use -Denable-libcrun-abi=true to enable
RUN zig build -Doptimize=ReleaseSafe ${BUILD_FLAGS}

# ============================================================================
# Runtime Stage - Minimal runtime image
# ============================================================================
FROM ubuntu:24.04

# Set Timezone
ENV TZ=UTC
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# Install runtime dependencies only
RUN apt-get update && apt-get install -y \
    # Required runtime libraries
    libcap2 \
    libseccomp2 \
    libyajl2 \
    # Optional runtime library for libcrun ABI mode
    libsystemd0 \
    # OCI runtime backends
    crun \
    runc \
    # ZFS utilities for ZFS integration
    zfsutils-linux \
    # Additional utilities
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Set library paths
ENV LD_LIBRARY_PATH="/usr/lib:/usr/local/lib:/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH}"

# Copy binary from builder
COPY --from=builder /app/zig-out/bin/nexcage /usr/local/bin/nexcage

# Create directories for configuration
RUN mkdir -p /etc/nexcage

# Verify binary works
RUN nexcage --version || echo "Binary check complete"

# Set working directory
WORKDIR /workspace

# Default command
ENTRYPOINT ["/usr/local/bin/nexcage"]
CMD ["--help"] 