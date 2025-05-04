#!/bin/bash

set -e

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root"
    exit 1
fi

# Function to check version
check_version() {
    local current=$1
    local required=$2
    local name=$3
    
    if [[ $required == "latest" ]]; then
        return 0
    fi
    
    if [[ $required == ">="* ]]; then
        required=${required#">="}
        if [ "$(printf '%s\n' "$required" "$current" | sort -V | head -n1)" = "$required" ]; then
            return 0
        else
            echo "Error: $name version $current is less than required version $required"
            return 1
        fi
    else
        if [ "$current" = "$required" ]; then
            return 0
        else
            echo "Error: $name version $current does not match required version $required"
            return 1
        fi
    fi
}

# Check dependencies versions
if [ -f /etc/debian_version ]; then
    # Update package list
    apt-get update

    # Check cmake version
    cmake_version=$(cmake --version | head -n1 | cut -d" " -f3)
    check_version "$cmake_version" ">=3.13" "cmake"

    # Check protobuf version
    protoc_version=$(protoc --version | cut -d" " -f2)
    check_version "$protoc_version" "3.12.4" "protoc"

    # Check docker version
    docker_version=$(docker --version | cut -d" " -f3 | tr -d ",")
    check_version "$docker_version" ">=20.10" "docker"

    # Install system libraries
    apt-get install -y \
        libgrpc-dev \
        libgrpc++-dev \
        libgrpc++1 \
        libprotobuf-dev \
        libprotobuf-lite23 \
        libprotobuf23 \
        libprotoc23 \
        libssl-dev \
        zlib1g-dev \
        libcares-dev \
        libre2-dev \
        libc-ares2 \
        libatomic1

elif [ -f /etc/redhat-release ]; then
    # Similar checks for RedHat-based systems
    dnf install -y protobuf-compiler grpc-devel grpc-cpp-devel
fi

# Install development tools
if [ -f /etc/debian_version ]; then
    apt-get install -y git make curl docker.io
elif [ -f /etc/redhat-release ]; then
    dnf install -y git make curl docker
fi

# Install GitHub CLI if not present
if ! command -v gh &> /dev/null; then
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
    apt-get update
    apt-get install -y gh
fi

# Install act if not present
if ! command -v act &> /dev/null; then
    curl https://raw.githubusercontent.com/nektos/act/master/install.sh | sudo bash
fi

# Create directories
mkdir -p /etc/proxmox-lxcri
mkdir -p /var/log/proxmox-lxcri
mkdir -p /usr/local/bin

# Build Abseil
echo "Building Abseil..."
git clone https://github.com/abseil/abseil-cpp.git
cd abseil-cpp
git checkout 20230802.1
mkdir build && cd build
cmake -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
      -DCMAKE_BUILD_TYPE=Release \
      -DABSL_BUILD_TESTING=OFF \
      -DABSL_USE_GOOGLETEST_HEAD=OFF \
      -DABSL_ENABLE_INSTALL=ON \
      -DCMAKE_INSTALL_PREFIX=/usr \
      -DABSL_PROPAGATE_CXX_STD=ON \
      ..
make -j$(nproc)
make install
cd ../..
rm -rf abseil-cpp

# Set environment variables
echo 'export LD_LIBRARY_PATH="/usr/lib:/usr/local/lib:/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH}"' >> /etc/profile.d/proxmox-lxcri.sh
echo 'export LIBRARY_PATH="/usr/lib:/usr/local/lib:/usr/lib/x86_64-linux-gnu:${LIBRARY_PATH}"' >> /etc/profile.d/proxmox-lxcri.sh
echo 'export PKG_CONFIG_PATH="/usr/lib/pkgconfig:/usr/local/lib/pkgconfig:/usr/lib/x86_64-linux-gnu/pkgconfig:${PKG_CONFIG_PATH}"' >> /etc/profile.d/proxmox-lxcri.sh
source /etc/profile.d/proxmox-lxcri.sh

# Build the project
zig build -Doptimize=ReleaseSafe

# Install binary and configuration
cp zig-out/bin/proxmox-lxcri /usr/local/bin/
chmod +x /usr/local/bin/proxmox-lxcri

if [ ! -f /etc/proxmox-lxcri/config.json ]; then
    cp config.json /etc/proxmox-lxcri/
fi

# Install systemd service
cp proxmox-lxcri.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable proxmox-lxcri.service

# Set permissions
chown root:root /usr/local/bin/proxmox-lxcri
chmod 755 /usr/local/bin/proxmox-lxcri
chown -R root:root /etc/proxmox-lxcri
chmod 644 /etc/proxmox-lxcri/config.json
chown root:root /etc/systemd/system/proxmox-lxcri.service
chmod 644 /etc/systemd/system/proxmox-lxcri.service

# Update library cache
ldconfig

echo "Installation complete!"
echo "Please edit /etc/proxmox-lxcri/config.json to set your Proxmox API token"
echo "Then start the service with: systemctl start proxmox-lxcri" 