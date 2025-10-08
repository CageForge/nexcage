#!/bin/bash

set -euo pipefail

# Configuration
PVE_HOST="mgr.cp.if.ua"
PVE_USER="root"
RUNNER_USER="github-runner"
GITHUB_REPO="kubebsd/nexcage"
RUNNER_NAME="proxmox-runner"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to display usage
usage() {
    echo "Usage: $0 {start|stop|restart|status|logs|remove|update}"
    echo ""
    echo "Commands:"
    echo "  start    - Start the GitHub Actions runner service"
    echo "  stop     - Stop the GitHub Actions runner service"
    echo "  restart  - Restart the GitHub Actions runner service"
    echo "  status   - Check the status of the runner service"
    echo "  logs     - Show the runner service logs"
    echo "  remove   - Remove the runner from GitHub and stop service"
    echo "  update   - Update the runner to latest version"
    echo ""
    echo "Examples:"
    echo "  $0 start"
    echo "  $0 status"
    echo "  $0 logs"
}

# Function to start runner
start_runner() {
    echo -e "${BLUE}🚀 Starting GitHub Actions runner...${NC}"
    ssh "$PVE_USER@$PVE_HOST" "systemctl start github-runner"
    if ssh "$PVE_USER@$PVE_HOST" "systemctl is-active --quiet github-runner"; then
        echo -e "${GREEN}✅ Runner started successfully${NC}"
    else
        echo -e "${RED}❌ Failed to start runner${NC}"
        exit 1
    fi
}

# Function to stop runner
stop_runner() {
    echo -e "${BLUE}🛑 Stopping GitHub Actions runner...${NC}"
    ssh "$PVE_USER@$PVE_HOST" "systemctl stop github-runner"
    echo -e "${GREEN}✅ Runner stopped${NC}"
}

# Function to restart runner
restart_runner() {
    echo -e "${BLUE}🔄 Restarting GitHub Actions runner...${NC}"
    ssh "$PVE_USER@$PVE_HOST" "systemctl restart github-runner"
    sleep 3
    if ssh "$PVE_USER@$PVE_HOST" "systemctl is-active --quiet github-runner"; then
        echo -e "${GREEN}✅ Runner restarted successfully${NC}"
    else
        echo -e "${RED}❌ Failed to restart runner${NC}"
        exit 1
    fi
}

# Function to check status
check_status() {
    echo -e "${BLUE}🔍 Checking runner status...${NC}"
    echo ""
    
    # Check service status
    echo -e "${YELLOW}Service Status:${NC}"
    ssh "$PVE_USER@$PVE_HOST" "systemctl status github-runner --no-pager"
    echo ""
    
    # Check runner registration
    echo -e "${YELLOW}GitHub Registration:${NC}"
    if command -v gh &> /dev/null; then
        if gh api repos/$GITHUB_REPO/actions/runners --jq '.runners[] | select(.name=="'$RUNNER_NAME'")' | grep -q "$RUNNER_NAME"; then
            echo -e "${GREEN}✅ Runner is registered with GitHub${NC}"
            gh api repos/$GITHUB_REPO/actions/runners --jq '.runners[] | select(.name=="'$RUNNER_NAME'") | {name, status, labels, busy}'
        else
            echo -e "${RED}❌ Runner is not registered with GitHub${NC}"
        fi
    else
        echo -e "${YELLOW}⚠️ GitHub CLI not available, cannot check registration${NC}"
    fi
    echo ""
    
    # Check runner logs
    echo -e "${YELLOW}Recent Logs:${NC}"
    ssh "$PVE_USER@$PVE_HOST" "journalctl -u github-runner --no-pager -n 10"
}

# Function to show logs
show_logs() {
    echo -e "${BLUE}📋 Showing runner logs...${NC}"
    ssh "$PVE_USER@$PVE_HOST" "journalctl -u github-runner --no-pager -f"
}

# Function to remove runner
remove_runner() {
    echo -e "${BLUE}🗑️ Removing GitHub Actions runner...${NC}"
    
    # Stop service
    ssh "$PVE_USER@$PVE_HOST" "systemctl stop github-runner"
    
    # Unregister from GitHub
    if command -v gh &> /dev/null; then
        echo -e "${YELLOW}Unregistering from GitHub...${NC}"
        ssh "$PVE_USER@$PVE_HOST" "cd /opt/github-runner && ./config.sh remove --token \$(gh api repos/$GITHUB_REPO/actions/runners/registration-token --method POST --jq '.token')"
    else
        echo -e "${YELLOW}⚠️ GitHub CLI not available, please unregister manually${NC}"
    fi
    
    # Remove service
    ssh "$PVE_USER@$PVE_HOST" "systemctl disable github-runner && rm -f /etc/systemd/system/github-runner.service && systemctl daemon-reload"
    
    # Remove runner directory
    ssh "$PVE_USER@$PVE_HOST" "rm -rf /opt/github-runner"
    
    echo -e "${GREEN}✅ Runner removed successfully${NC}"
}

# Function to update runner
update_runner() {
    echo -e "${BLUE}🔄 Updating GitHub Actions runner...${NC}"
    
    # Get latest version
    LATEST_VERSION=$(curl -s https://api.github.com/repos/actions/runner/releases/latest | grep -o '"tag_name": "[^"]*' | grep -o '[^"]*$')
    echo -e "${YELLOW}Latest version: $LATEST_VERSION${NC}"
    
    # Stop service
    ssh "$PVE_USER@$PVE_HOST" "systemctl stop github-runner"
    
    # Download latest version
    ssh "$PVE_USER@$PVE_HOST" "cd /opt/github-runner && curl -o actions-runner-linux-x64-$LATEST_VERSION.tar.gz -L https://github.com/actions/runner/releases/download/$LATEST_VERSION/actions-runner-linux-x64-$LATEST_VERSION.tar.gz"
    
    # Extract new version
    ssh "$PVE_USER@$PVE_HOST" "cd /opt/github-runner && tar xzf actions-runner-linux-x64-$LATEST_VERSION.tar.gz"
    
    # Start service
    ssh "$PVE_USER@$PVE_HOST" "systemctl start github-runner"
    
    echo -e "${GREEN}✅ Runner updated to version $LATEST_VERSION${NC}"
}

# Function to show runner info
show_info() {
    echo -e "${BLUE}📊 GitHub Actions Runner Information${NC}"
    echo ""
    echo -e "${YELLOW}Configuration:${NC}"
    echo -e "  • Host: $PVE_HOST"
    echo -e "  • User: $PVE_USER"
    echo -e "  • Repository: $GITHUB_REPO"
    echo -e "  • Runner Name: $RUNNER_NAME"
    echo -e "  • Runner Directory: /opt/github-runner"
    echo -e "  • Service Name: github-runner"
    echo ""
    echo -e "${YELLOW}Useful Commands:${NC}"
    echo -e "  • Check status: $0 status"
    echo -e "  • View logs: $0 logs"
    echo -e "  • Restart: $0 restart"
    echo -e "  • Stop: $0 stop"
    echo -e "  • Start: $0 start"
    echo ""
    echo -e "${YELLOW}GitHub Actions:${NC}"
    echo -e "  • Repository: https://github.com/$GITHUB_REPO"
    echo -e "  • Actions: https://github.com/$GITHUB_REPO/actions"
    echo -e "  • Runners: https://github.com/$GITHUB_REPO/settings/actions/runners"
}

# Main script logic
case "${1:-}" in
    start)
        start_runner
        ;;
    stop)
        stop_runner
        ;;
    restart)
        restart_runner
        ;;
    status)
        check_status
        ;;
    logs)
        show_logs
        ;;
    remove)
        remove_runner
        ;;
    update)
        update_runner
        ;;
    info)
        show_info
        ;;
    *)
        usage
        exit 1
        ;;
esac
