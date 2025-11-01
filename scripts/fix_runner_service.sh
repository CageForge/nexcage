#!/bin/bash
# Fix GitHub Actions runner service configuration
# This script fixes common issues with runner service paths

set -euo pipefail

RUNNER_USER="${RUNNER_USER:-github-runner}"
RUNNER_HOME="${RUNNER_HOME:-/home/$RUNNER_USER}"

echo "🔧 Fixing GitHub Actions runner service..."

# 1. Find actual runner directory
echo "Searching for runner installation..."

POSSIBLE_PATHS=(
    "$RUNNER_HOME/actions-runner"
    "/opt/github-runner"
    "/opt/actions-runner"
    "$HOME/actions-runner"
)

RUNNER_DIR=""
for path in "${POSSIBLE_PATHS[@]}"; do
    if [ -f "$path/runsvc.sh" ]; then
        RUNNER_DIR="$path"
        echo "✅ Found runner at: $RUNNER_DIR"
        break
    fi
done

if [ -z "$RUNNER_DIR" ]; then
    echo "❌ Could not find runner installation"
    echo "Please specify runner directory manually:"
    echo "  export RUNNER_DIR=/path/to/actions-runner"
    echo "  $0"
    exit 1
fi

# 2. Verify files exist
if [ ! -f "$RUNNER_DIR/runsvc.sh" ]; then
    echo "❌ runsvc.sh not found at $RUNNER_DIR/runsvc.sh"
    exit 1
fi

if [ ! -f "$RUNNER_DIR/config.sh" ]; then
    echo "❌ config.sh not found at $RUNNER_DIR/config.sh"
    exit 1
fi

echo "✅ Runner files verified"

# 3. Check current service configuration
SERVICE_NAME=$(systemctl list-units --type=service | grep -i "actions.runner" | grep -i "github" | awk '{print $1}' | head -1)

if [ -z "$SERVICE_NAME" ]; then
    echo "⚠️  No GitHub Actions runner service found"
    echo "Creating new service file..."
    SERVICE_NAME="actions.runner.$(hostname).service"
else
    echo "Found service: $SERVICE_NAME"
fi

# 4. Get repository name from config
if [ -f "$RUNNER_DIR/.runner" ]; then
    REPO_URL=$(grep -oP 'repositoryUrl":\s*"\K[^"]+' "$RUNNER_DIR/.runner" || echo "")
    REPO_NAME=$(echo "$REPO_URL" | sed 's|.*github.com/||' | sed 's|\.git$||' | tr '/' '-')
    SERVICE_NAME="actions.runner.${REPO_NAME}.service"
else
    REPO_NAME="unknown"
fi

echo "Service name will be: $SERVICE_NAME"

# 5. Get runner user from directory ownership
if [ -f "$RUNNER_DIR/runsvc.sh" ]; then
    RUNNER_USER=$(stat -c '%U' "$RUNNER_DIR/runsvc.sh")
    RUNNER_GROUP=$(stat -c '%G' "$RUNNER_DIR/runsvc.sh")
    echo "Runner user: $RUNNER_USER:$RUNNER_GROUP"
else
    RUNNER_USER="${RUNNER_USER:-github-runner}"
    RUNNER_GROUP="${RUNNER_GROUP:-github-runner}"
fi

# 6. Create correct systemd service file
echo "Creating systemd service file..."
sudo tee "/etc/systemd/system/${SERVICE_NAME}" > /dev/null << SERVICE_EOF
[Unit]
Description=GitHub Actions Runner ($REPO_NAME)
After=network.target

[Service]
Type=notify
User=$RUNNER_USER
Group=$RUNNER_GROUP
WorkingDirectory=$RUNNER_DIR
ExecStart=$RUNNER_DIR/runsvc.sh

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

# Restart policy
Restart=always
RestartSec=10
TimeoutStopSec=90

# Environment
Environment="RUNNER_ALLOW_RUNASROOT=1"

[Install]
WantedBy=multi-user.target
SERVICE_EOF

# 7. Ensure correct permissions
echo "Setting permissions..."
sudo chown -R "$RUNNER_USER:$RUNNER_GROUP" "$RUNNER_DIR"
sudo chmod +x "$RUNNER_DIR/runsvc.sh"
sudo chmod +x "$RUNNER_DIR/run.sh"
sudo chmod +x "$RUNNER_DIR/config.sh"

# 8. Reload systemd and restart service
echo "Reloading systemd daemon..."
sudo systemctl daemon-reload

# Stop any existing services
echo "Stopping existing runner services..."
sudo systemctl stop "actions.runner.*" 2>/dev/null || true
sleep 2

# Start the service
echo "Starting service: $SERVICE_NAME"
sudo systemctl enable "$SERVICE_NAME"
sudo systemctl start "$SERVICE_NAME"

# 9. Check status
sleep 2
if sudo systemctl is-active --quiet "$SERVICE_NAME"; then
    echo "✅ Service started successfully!"
    echo ""
    echo "Service status:"
    sudo systemctl status "$SERVICE_NAME" --no-pager -l
else
    echo "❌ Service failed to start"
    echo ""
    echo "Service logs:"
    sudo journalctl -u "$SERVICE_NAME" --no-pager -n 50
    exit 1
fi

echo ""
echo "✅ Runner service fixed!"
echo ""
echo "📋 Service information:"
echo "  Service: $SERVICE_NAME"
echo "  Runner dir: $RUNNER_DIR"
echo "  User: $RUNNER_USER:$RUNNER_GROUP"
echo ""
echo "💡 Useful commands:"
echo "  sudo systemctl status $SERVICE_NAME"
echo "  sudo journalctl -u $SERVICE_NAME -f"
echo "  sudo systemctl restart $SERVICE_NAME"

