#!/bin/bash
# Setup secure GitHub Actions self-hosted runner
# Usage: ./setup_secure_runner.sh <repo-url> <registration-token>

set -euo pipefail

if [ $# -ne 2 ]; then
    echo "Usage: $0 <repo-url> <registration-token>"
    echo "Example: $0 https://github.com/CageForge/nexcage <token>"
    exit 1
fi

REPO_URL="$1"
REGISTRATION_TOKEN="$2"
RUNNER_USER="github-runner"
RUNNER_DIR="/opt/github-runner"
RUNNER_NAME="${RUNNER_NAME:-proxmox-runner}"

echo "🔒 Setting up secure GitHub Actions runner..."

# 1. Create dedicated user
if ! id "$RUNNER_USER" &>/dev/null; then
    echo "Creating user: $RUNNER_USER"
    sudo useradd -r -m -s /bin/bash -d "$RUNNER_DIR" "$RUNNER_USER"
else
    echo "User $RUNNER_USER already exists"
fi

# 2. Create runner directory with proper permissions
echo "Creating runner directory: $RUNNER_DIR"
sudo mkdir -p "$RUNNER_DIR"/_work
sudo chown -R "$RUNNER_USER:$RUNNER_USER" "$RUNNER_DIR"
sudo chmod 750 "$RUNNER_DIR"
sudo chmod 700 "$RUNNER_DIR/_work"

# 3. Download and install runner
echo "Downloading GitHub Actions runner..."
cd "$RUNNER_DIR"
RUNNER_VERSION="2.311.0"
RUNNER_TAR="actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz"
RUNNER_URL="https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/${RUNNER_TAR}"

if [ ! -f "$RUNNER_TAR" ]; then
    sudo -u "$RUNNER_USER" curl -L -o "$RUNNER_TAR" "$RUNNER_URL"
fi

if [ ! -d "bin" ]; then
    echo "Extracting runner..."
    sudo -u "$RUNNER_USER" tar xzf "$RUNNER_TAR"
fi

# 4. Configure runner
if [ ! -f ".runner" ]; then
    echo "Configuring runner..."
    sudo -u "$RUNNER_USER" ./config.sh \
        --url "$REPO_URL" \
        --token "$REGISTRATION_TOKEN" \
        --name "$RUNNER_NAME" \
        --work _work \
        --unattended \
        --replace
else
    echo "Runner already configured"
fi

# 5. Create systemd service with security hardening
echo "Creating systemd service..."
sudo tee /etc/systemd/system/github-runner.service > /dev/null << SERVICE_EOF
[Unit]
Description=GitHub Actions Runner
After=network.target

[Service]
Type=simple
User=$RUNNER_USER
Group=$RUNNER_USER
WorkingDirectory=$RUNNER_DIR
ExecStart=$RUNNER_DIR/run.sh

# Security hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$RUNNER_DIR/_work
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictNamespaces=true
RestrictRealtime=true
LockPersonality=true
MemoryDenyWriteExecute=true
RestrictAddressFamilies=AF_INET AF_INET6
SystemCallFilter=@system-service
SystemCallErrorNumber=EPERM

# Resource limits
MemoryLimit=4G
CPUQuota=200%
TasksMax=100
LimitNOFILE=4096
LimitNPROC=512

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=github-runner

Restart=always
RestartSec=10
TimeoutStopSec=90

[Install]
WantedBy=multi-user.target
SERVICE_EOF

# 6. Enable and start service
echo "Enabling and starting service..."
sudo systemctl daemon-reload
sudo systemctl enable github-runner
sudo systemctl start github-runner

# 7. Verify installation
echo "Verifying installation..."
sleep 2
if sudo systemctl is-active --quiet github-runner; then
    echo "✅ Runner service is running"
else
    echo "❌ Runner service failed to start"
    sudo systemctl status github-runner
    exit 1
fi

# 8. Display status
echo ""
echo "=== Runner Status ==="
sudo systemctl status github-runner --no-pager -l

echo ""
echo "✅ Secure GitHub Actions runner setup complete!"
echo ""
echo "📋 Next steps:"
echo "  1. Configure workflows to block fork PRs"
echo "  2. Set up firewall rules"
echo "  3. Enable audit logging"
echo "  4. Review workflow permissions"
echo ""
echo "📚 See docs/SECURITY_SELF_HOSTED_RUNNER.md for details"

