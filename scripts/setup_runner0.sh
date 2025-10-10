#!/bin/bash
# Quick setup script for github-runner0
# Run this on github-runner0.cp.if.ua

set -euo pipefail

RUNNER_VERSION="2.328.0"
RUNNER_TOKEN="ADKGWFVIZG5GUM6RMDTAI7DI5DW6S"
REPO_URL="https://github.com/cageforge/nexcage"

echo "=== GitHub Runner0 Setup ==="
echo "Server: github-runner0.cp.if.ua"
echo "Label: [self-hosted, runner0]"
echo

# Check if running as correct user
if [[ $EUID -eq 0 ]]; then
   echo "ERROR: Do not run this script as root"
   echo "Run as: bash $0"
   exit 1
fi

# Create runner directory
RUNNER_DIR="$HOME/actions-runner"
mkdir -p "$RUNNER_DIR"
cd "$RUNNER_DIR"

echo "=== Step 1: Download GitHub Actions Runner ==="
if [[ ! -f "actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz" ]]; then
    echo "Downloading runner version ${RUNNER_VERSION}..."
    curl -o "actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz" -L \
        "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz"
else
    echo "Runner archive already downloaded"
fi

echo "=== Step 2: Extract Runner ==="
if [[ ! -f "config.sh" ]]; then
    echo "Extracting runner..."
    tar xzf "actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz"
else
    echo "Runner already extracted"
fi

echo "=== Step 3: Configure Runner ==="
if [[ -f ".runner" ]]; then
    echo "Runner already configured. Removing old configuration..."
    ./config.sh remove --token "$RUNNER_TOKEN" || true
fi

echo "Configuring runner with label 'runner0'..."
./config.sh \
    --url "$REPO_URL" \
    --token "$RUNNER_TOKEN" \
    --name github-runner0 \
    --labels self-hosted,runner0 \
    --work _work \
    --unattended

echo "=== Step 4: Install as Service ==="
sudo ./svc.sh install
sudo ./svc.sh start

echo
echo "=== Step 5: Verify Installation ==="
sudo ./svc.sh status

echo
echo "=== Step 6: Install Dependencies ==="
echo "Checking required dependencies..."

# Check Zig
if command -v zig >/dev/null 2>&1; then
    ZIG_VERSION=$(zig version)
    echo "✓ Zig installed: $ZIG_VERSION"
    if [[ "$ZIG_VERSION" != "0.15.1" ]]; then
        echo "⚠ Warning: Expected Zig 0.15.1, found $ZIG_VERSION"
    fi
else
    echo "✗ Zig not found"
    echo "Installing Zig 0.15.1..."
    cd /tmp
    curl -L https://ziglang.org/download/0.15.1/zig-linux-x86_64-0.15.1.tar.xz -o zig.tar.xz
    tar -xf zig.tar.xz
    sudo mv zig-linux-x86_64-0.15.1 /usr/local/zig-0.15.1
    sudo ln -sf /usr/local/zig-0.15.1/zig /usr/local/bin/zig
    echo "✓ Zig 0.15.1 installed"
    cd "$RUNNER_DIR"
fi

# Check build dependencies
echo "Checking build dependencies..."
MISSING_DEPS=()

for lib in libcap-dev libseccomp-dev libyajl-dev build-essential git curl wget; do
    if ! dpkg -l | grep -q "^ii  $lib"; then
        MISSING_DEPS+=("$lib")
    fi
done

if [[ ${#MISSING_DEPS[@]} -gt 0 ]]; then
    echo "Installing missing dependencies: ${MISSING_DEPS[*]}"
    sudo apt-get update
    sudo apt-get install -y "${MISSING_DEPS[@]}"
    echo "✓ Dependencies installed"
else
    echo "✓ All dependencies already installed"
fi

echo
echo "=== Setup Complete ==="
echo "✓ Runner configured with label: [self-hosted, runner0]"
echo "✓ Service installed and started"
echo "✓ Dependencies verified"
echo
echo "Verify runner at: https://github.com/cageforge/nexcage/settings/actions/runners"
echo
echo "Monitor logs with: journalctl -u actions.runner.* -f"
echo

