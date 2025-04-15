#!/bin/bash
# Development environment setup script for Proxmox LXC CRI project

set -e  # Exit on error

echo "Starting development environment setup..."

# Check OS and set variables
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    # Linux
    PKG_MANAGER="apt-get"
    DOCKER_INSTALL="curl -fsSL https://get.docker.com | sh"
elif [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    PKG_MANAGER="brew"
    DOCKER_INSTALL="brew install --cask docker"
else
    echo "Unsupported OS: $OSTYPE"
    exit 1
fi

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to print status
print_status() {
    echo -e "\n\033[1m$1\033[0m"
}

# Install Docker if not present
if ! command_exists docker; then
    print_status "Installing Docker..."
    eval "$DOCKER_INSTALL"
    
    # Start Docker service on Linux
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        sudo systemctl start docker
        sudo systemctl enable docker
    fi
else
    echo "Docker is already installed"
fi

# Install act if not present
if ! command_exists act; then
    print_status "Installing act..."
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        curl https://raw.githubusercontent.com/nektos/act/master/install.sh | sudo bash
    else
        brew install act
    fi
else
    echo "act is already installed"
fi

# Install Zig if not present
if ! command_exists zig; then
    print_status "Installing Zig..."
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Add Zig repository and install
        wget https://ziglang.org/download/0.14.0/zig-linux-x86_64-0.14.0.tar.xz
        tar xf zig-linux-x86_64-0.14.0.tar.xz
        sudo mv zig-linux-x86_64-0.14.0 /opt/zig
        echo 'export PATH=$PATH:/opt/zig' >> ~/.bashrc
        source ~/.bashrc
    else
        brew install zig
    fi
else
    echo "Zig is already installed"
fi

# Install gRPC and protobuf
print_status "Installing gRPC and protobuf..."
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    sudo $PKG_MANAGER update
    sudo $PKG_MANAGER install -y \
        libgrpc-dev \
        libprotobuf-dev \
        protobuf-compiler
else
    brew install grpc protobuf
fi

# Install development tools
print_status "Installing development tools..."
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    sudo $PKG_MANAGER install -y \
        git \
        make \
        build-essential
else
    brew install git make
fi

# Verify installations
print_status "Verifying installations..."
echo "Docker version: $(docker --version)"
echo "act version: $(act --version)"
echo "Zig version: $(zig version)"
echo "git version: $(git --version)"

print_status "Development environment setup complete!"
echo "Please restart your terminal or run 'source ~/.bashrc' to apply changes" 