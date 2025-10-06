FROM ubuntu:latest

# Version arguments
ARG ZIG_VERSION=0.15.1
ARG GITLEAKS_VERSION=8.18.1

# Install dependencies
RUN apt-get update && apt-get install -y \
    curl \
    git \
    xz-utils \
    wget \
    && rm -rf /var/lib/apt/lists/*

# Install Zig
RUN curl -L https://ziglang.org/download/${ZIG_VERSION}/zig-linux-x86_64-${ZIG_VERSION}.tar.xz -o zig.tar.xz \
    && tar -xf zig.tar.xz \
    && mv zig-linux-x86_64-${ZIG_VERSION} /opt/zig \
    && rm zig.tar.xz

# Install Gitleaks
RUN wget https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz \
    && tar -xzf gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz \
    && mv gitleaks /usr/local/bin/ \
    && rm gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz

# Add Zig to PATH
ENV PATH="/opt/zig:${PATH}"

WORKDIR /app

# Copy project files
COPY . .

RUN chmod +x /opt/zig/zig
