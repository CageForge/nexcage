FROM ubuntu:24.04

# Set Timezone
ENV TZ=UTC
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# Dependency
RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    git \
    curl \
    wget \
    pkg-config \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

# Path to libs
ENV LD_LIBRARY_PATH="/usr/lib:/usr/local/lib:/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH}"
ENV LIBRARY_PATH="/usr/lib:/usr/local/lib:/usr/lib/x86_64-linux-gnu:${LIBRARY_PATH}"
ENV PKG_CONFIG_PATH="/usr/lib/pkgconfig:/usr/local/lib/pkgconfig:/usr/lib/x86_64-linux-gnu/pkgconfig:${PKG_CONFIG_PATH}"

# Install Zig
RUN wget https://ziglang.org/download/0.15.1/zig-linux-x86_64-0.15.1.tar.xz \
    && tar xf zig-linux-x86_64-0.15.1.tar.xz \
    && mv zig-linux-x86_64-0.15.1 /usr/local/zig \
    && rm zig-linux-x86_64-0.15.1.tar.xz

# Add Zig до PATH
ENV PATH="/usr/local/zig:${PATH}"

WORKDIR /app

# Copy project files
COPY . .

# Build project
CMD ["zig", "build", "run"] 