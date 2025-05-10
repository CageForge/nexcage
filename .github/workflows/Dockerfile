FROM ubuntu:latest

# Dependency
RUN apt-get update && apt-get install -y \
    curl \
    git \
    xz-utils \
    wget \
    && rm -rf /var/lib/apt/lists/*

# Install Zig
RUN curl -L https://ziglang.org/download/0.13.0/zig-linux-x86_64-0.13.0.tar.xz -o zig.tar.xz \
    && tar -xf zig.tar.xz \
    && mv zig-linux-x86_64-0.13.0 /opt/zig \
    && rm zig.tar.xz

# Install Gitleaks
RUN wget https://github.com/gitleaks/gitleaks/releases/download/v8.18.1/gitleaks_8.18.1_linux_x64.tar.gz \
    && tar -xzf gitleaks_8.18.1_linux_x64.tar.gz \
    && mv gitleaks /usr/local/bin/ \
    && rm gitleaks_8.18.1_linux_x64.tar.gz

# Add Zig до PATH
ENV PATH="/opt/zig:${PATH}"

WORKDIR /app

# Copy project files
COPY . .

RUN chmod +x /opt/zig/zig
