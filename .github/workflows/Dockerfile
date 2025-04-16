FROM ubuntu:latest

# Встановлюємо необхідні залежності
RUN apt-get update && apt-get install -y \
    protobuf-compiler \
    libgrpc-dev \
    libgrpc++-dev \
    libgrpc++1 \
    libprotobuf-dev \
    curl \
    git \
    xz-utils \
    && rm -rf /var/lib/apt/lists/*

# Встановлюємо Zig
RUN curl -L https://ziglang.org/download/0.13.0/zig-linux-x86_64-0.13.0.tar.xz -o zig.tar.xz \
    && tar -xf zig.tar.xz \
    && mv zig-linux-x86_64-0.13.0 /opt/zig \
    && rm zig.tar.xz

# Додаємо Zig до PATH
ENV PATH="/opt/zig:${PATH}"

# Створюємо робочу директорію
WORKDIR /app

# Копіюємо файли проекту
COPY . .

# Встановлюємо права на виконання
RUN chmod +x /opt/zig/zig 