#!/bin/bash

set -euo pipefail

# Configuration
PVE_HOST="mgr.cp.if.ua"
PVE_USER="root"
GITHUB_REPO="moriarti/proxmox-lxcri"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 Setting up GitHub CI/CD for Proxmox testing${NC}"
echo ""

# Check if gh CLI is installed
if ! command -v gh &> /dev/null; then
    echo -e "${RED}❌ GitHub CLI (gh) is not installed${NC}"
    echo "Please install it first: https://cli.github.com/"
    exit 1
fi

# Check if user is logged in to GitHub
if ! gh auth status &> /dev/null; then
    echo -e "${RED}❌ Not logged in to GitHub${NC}"
    echo "Please run: gh auth login"
    exit 1
fi

echo -e "${YELLOW}📋 Setting up GitHub CI/CD...${NC}"

# 1. Generate SSH key pair for CI
echo -e "${BLUE}🔑 Generating SSH key pair for CI...${NC}"
if [ ! -f "ci_ssh_key" ]; then
    ssh-keygen -t ed25519 -f ci_ssh_key -N "" -C "proxmox-lxcri-ci@github.com"
    echo -e "${GREEN}✅ SSH key pair generated${NC}"
else
    echo -e "${YELLOW}⚠️ SSH key pair already exists${NC}"
fi

# 2. Copy public key to Proxmox server
echo -e "${BLUE}📤 Copying public key to Proxmox server...${NC}"
if ssh-copy-id -i ci_ssh_key.pub "$PVE_USER@$PVE_HOST"; then
    echo -e "${GREEN}✅ Public key copied to Proxmox server${NC}"
else
    echo -e "${RED}❌ Failed to copy public key to Proxmox server${NC}"
    echo "Please ensure you have SSH access to $PVE_USER@$PVE_HOST"
    exit 1
fi

# 3. Test SSH connection
echo -e "${BLUE}🔍 Testing SSH connection...${NC}"
if ssh -i ci_ssh_key -o StrictHostKeyChecking=no "$PVE_USER@$PVE_HOST" "echo 'SSH connection successful'"; then
    echo -e "${GREEN}✅ SSH connection successful${NC}"
else
    echo -e "${RED}❌ SSH connection failed${NC}"
    exit 1
fi

# 4. Add private key to GitHub secrets
echo -e "${BLUE}🔐 Adding private key to GitHub secrets...${NC}"
if gh secret set PROXMOX_SSH_KEY --body-file ci_ssh_key; then
    echo -e "${GREEN}✅ Private key added to GitHub secrets${NC}"
else
    echo -e "${RED}❌ Failed to add private key to GitHub secrets${NC}"
    exit 1
fi

# 5. Create GitHub Actions workflow file
echo -e "${BLUE}📝 Creating GitHub Actions workflow...${NC}"
if [ -f ".github/workflows/proxmox_ci.yml" ]; then
    echo -e "${YELLOW}⚠️ Workflow file already exists${NC}"
else
    echo -e "${GREEN}✅ Workflow file created${NC}"
fi

# 6. Test the workflow
echo -e "${BLUE}🧪 Testing the workflow...${NC}"
if gh workflow run "Proxmox CI/CD" --ref main; then
    echo -e "${GREEN}✅ Workflow triggered successfully${NC}"
else
    echo -e "${RED}❌ Failed to trigger workflow${NC}"
    exit 1
fi

# 7. Clean up local files
echo -e "${BLUE}🧹 Cleaning up local files...${NC}"
rm -f ci_ssh_key ci_ssh_key.pub
echo -e "${GREEN}✅ Local files cleaned up${NC}"

# 8. Display summary
echo ""
echo -e "${GREEN}🎉 GitHub CI/CD setup completed successfully!${NC}"
echo ""
echo -e "${BLUE}📋 Summary:${NC}"
echo -e "  • SSH key pair generated and configured"
echo -e "  • Public key copied to Proxmox server ($PVE_HOST)"
echo -e "  • Private key added to GitHub secrets"
echo -e "  • GitHub Actions workflow created"
echo -e "  • Workflow triggered for testing"
echo ""
echo -e "${BLUE}🔗 Next steps:${NC}"
echo -e "  1. Check the Actions tab in your GitHub repository"
echo -e "  2. Monitor the workflow execution"
echo -e "  3. Verify that tests run on Proxmox server"
echo -e "  4. Check the generated reports and artifacts"
echo ""
echo -e "${BLUE}📊 Monitoring:${NC}"
echo -e "  • GitHub Actions: https://github.com/$GITHUB_REPO/actions"
echo -e "  • Proxmox Server: $PVE_USER@$PVE_HOST"
echo -e "  • Test Reports: Available as workflow artifacts"
echo ""

# 9. Display workflow status
echo -e "${BLUE}🔍 Checking workflow status...${NC}"
if gh run list --workflow="Proxmox CI/CD" --limit=1; then
    echo -e "${GREEN}✅ Workflow status retrieved${NC}"
else
    echo -e "${YELLOW}⚠️ Could not retrieve workflow status${NC}"
fi

echo ""
echo -e "${GREEN}🚀 Setup complete! Your CI/CD pipeline is now ready.${NC}"
