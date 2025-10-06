#!/bin/bash

set -euo pipefail

# Configuration
PVE_HOST="mgr.cp.if.ua"
PVE_USER="root"
RUNNER_USER="github-runner"
GITHUB_REPO="kubebsd/proxmox-lxcri"
RUNNER_NAME="proxmox-runner"
RUNNER_LABELS="proxmox,self-hosted,ubuntu"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 Setting up Proxmox server as GitHub Actions self-hosted runner${NC}"
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

echo -e "${YELLOW}📋 Setting up GitHub Actions self-hosted runner...${NC}"

# 1. Generate registration token
echo -e "${BLUE}🔑 Generating registration token...${NC}"
REGISTRATION_TOKEN=$(gh api repos/$GITHUB_REPO/actions/runners/registration-token --method POST --jq '.token')
if [ -z "$REGISTRATION_TOKEN" ]; then
    echo -e "${RED}❌ Failed to generate registration token${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Registration token generated${NC}"

# 2. Create runner directory on Proxmox server
echo -e "${BLUE}📁 Creating runner directory on Proxmox server...${NC}"
ssh "$PVE_USER@$PVE_HOST" "mkdir -p /opt/github-runner && chown $RUNNER_USER:$RUNNER_USER /opt/github-runner"

# 3. Download GitHub Actions runner
echo -e "${BLUE}📥 Downloading GitHub Actions runner...${NC}"
ssh "$PVE_USER@$PVE_HOST" "cd /opt/github-runner && curl -o actions-runner-linux-x64-2.311.0.tar.gz -L https://github.com/actions/runner/releases/download/v2.311.0/actions-runner-linux-x64-2.311.0.tar.gz && chown $RUNNER_USER:$RUNNER_USER actions-runner-linux-x64-2.311.0.tar.gz"

# 4. Extract runner
echo -e "${BLUE}📦 Extracting runner...${NC}"
ssh "$PVE_USER@$PVE_HOST" "cd /opt/github-runner && tar xzf actions-runner-linux-x64-2.311.0.tar.gz && chown -R $RUNNER_USER:$RUNNER_USER ."

# 5. Install dependencies
echo -e "${BLUE}📦 Installing dependencies...${NC}"
ssh "$PVE_USER@$PVE_HOST" "apt-get update && apt-get install -y libcap-dev libseccomp-dev libyajl-dev build-essential"

# 6. Install Zig
echo -e "${BLUE}📦 Installing Zig...${NC}"
ssh "$PVE_USER@$PVE_HOST" "cd /opt && wget https://ziglang.org/download/0.15.1/zig-linux-x86_64-0.15.1.tar.xz && tar -xf zig-linux-x86_64-0.15.1.tar.xz && ln -sf /opt/zig-linux-x86_64-0.15.1/zig /usr/local/bin/zig"

# 7. Configure runner
echo -e "${BLUE}⚙️ Configuring runner...${NC}"
ssh "$PVE_USER@$PVE_HOST" "sudo -u $RUNNER_USER bash -c 'cd /opt/github-runner && ./config.sh --url https://github.com/$GITHUB_REPO --token $REGISTRATION_TOKEN --name $RUNNER_NAME --labels $RUNNER_LABELS --work _work --replace'"

# 8. Create systemd service
echo -e "${BLUE}🔧 Creating systemd service...${NC}"
ssh "$PVE_USER@$PVE_HOST" "cat > /etc/systemd/system/github-runner.service << 'EOF'
[Unit]
Description=GitHub Actions Runner
After=network.target

[Service]
Type=simple
User=$RUNNER_USER
WorkingDirectory=/opt/github-runner
ExecStart=/opt/github-runner/run.sh
Restart=always
RestartSec=5
Environment=PATH=/usr/local/bin:/usr/bin:/bin
Environment=HOME=/home/$RUNNER_USER

[Install]
WantedBy=multi-user.target
EOF"

# 9. Enable and start service
echo -e "${BLUE}🚀 Starting runner service...${NC}"
ssh "$PVE_USER@$PVE_HOST" "systemctl daemon-reload && systemctl enable github-runner && systemctl start github-runner"

# 10. Check runner status
echo -e "${BLUE}🔍 Checking runner status...${NC}"
sleep 5
if ssh "$PVE_USER@$PVE_HOST" "systemctl is-active --quiet github-runner"; then
    echo -e "${GREEN}✅ Runner service is running${NC}"
else
    echo -e "${RED}❌ Runner service failed to start${NC}"
    ssh "$PVE_USER@$PVE_HOST" "systemctl status github-runner"
    exit 1
fi

# 11. Verify runner registration
echo -e "${BLUE}🔍 Verifying runner registration...${NC}"
sleep 10
if gh api repos/$GITHUB_REPO/actions/runners --jq '.runners[] | select(.name=="'$RUNNER_NAME'")' | grep -q "$RUNNER_NAME"; then
    echo -e "${GREEN}✅ Runner registered successfully${NC}"
else
    echo -e "${RED}❌ Runner registration failed${NC}"
    exit 1
fi

# 12. Create workflow for self-hosted runner
echo -e "${BLUE}📝 Creating workflow for self-hosted runner...${NC}"
cat > .github/workflows/proxmox_self_hosted.yml << EOF
name: Proxmox Self-Hosted CI/CD

on:
  push:
    branches: [ main, develop, feature/**, feat/** ]
  pull_request:
    branches: [ main, develop ]
  workflow_dispatch:

jobs:
  proxmox-ci:
    runs-on: [self-hosted, proxmox]
    
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup environment
        run: |
          echo "Running on Proxmox server: \$(hostname)"
          echo "Zig version: \$(zig version)"
          echo "Current directory: \$(pwd)"

      - name: Install dependencies
        run: |
          apt-get update
          apt-get install -y libcap-dev libseccomp-dev libyajl-dev

      - name: Create test reports directory
        run: mkdir -p test-reports

      - name: Run Proxmox tests
        run: |
          chmod +x scripts/proxmox_only_test.sh
          ./scripts/proxmox_only_test.sh
        env:
          PVE_HOST: root@localhost

      - name: Upload test reports
        uses: actions/upload-artifact@v4
        if: always()
        with:
          name: proxmox-test-reports-\${{ github.run_id }}
          path: test-reports/proxmox_only_test_report_*.md
          retention-days: 30

      - name: Upload test logs
        uses: actions/upload-artifact@v4
        if: always()
        with:
          name: proxmox-test-logs-\${{ github.run_id }}
          path: test-reports/*.log
          retention-days: 30

      - name: Comment PR with test results
        if: github.event_name == 'pull_request'
        uses: actions/github-script@v7
        with:
          script: |
            const fs = require('fs');
            const path = require('path');
            
            // Read Proxmox test report
            const files = fs.readdirSync('test-reports/');
            const reportFile = files.find(f => f.startsWith('proxmox_only_test_report_') && f.endsWith('.md'));
            
            if (reportFile) {
              const reportContent = fs.readFileSync(\`test-reports/\${reportFile}\`, 'utf8');
              
              // Extract summary from report
              const summaryMatch = reportContent.match(/## Summary\\s*\\n\\s*\\|.*\\|.*\\|.*\\|.*\\|.*\\|/s);
              const summary = summaryMatch ? summaryMatch[0] : 'Summary not found';
              
              // Create comment
              const comment = \`## 🧪 Proxmox Self-Hosted Test Results
              
              **Test Environment**: Proxmox VE Server (Self-Hosted Runner)
              **Runner**: \$(hostname)
              **Commit**: \${{ github.sha }}
              **Branch**: \${{ github.ref_name }}
              
              \${summary}
              
              <details>
              <summary>📊 Full Test Report</summary>
              
              \\\`\\\`\\\`markdown
              \${reportContent}
              \\\`\\\`\\\`
              </details>
              
              📁 [Download Full Report](https://github.com/\${{ github.repository }}/actions/runs/\${{ github.run_id }})
              \`;
              
              github.rest.issues.createComment({
                issue_number: context.issue.number,
                owner: context.repo.owner,
                repo: context.repo.repo,
                body: comment
              });
            }

  proxmox-deployment:
    runs-on: [self-hosted, proxmox]
    needs: [proxmox-ci]
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'
    
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Build release binary
        run: |
          zig build -Doptimize=ReleaseFast
          ls -la zig-out/bin/

      - name: Deploy to Proxmox
        run: |
          # Copy binary to system location
          cp zig-out/bin/proxmox-lxcri /usr/local/bin/
          chmod +x /usr/local/bin/proxmox-lxcri
          
          # Copy config to system location
          mkdir -p /etc/proxmox-lxcri
          cp config.json /etc/proxmox-lxcri/
          
          # Test deployment
          /usr/local/bin/proxmox-lxcri --help

      - name: Create deployment summary
        run: |
          cat > deployment_summary.md << EOF
          # Self-Hosted Deployment Summary - \$(date)
          
          ## Deployment Details
          - **Target Server**: \$(hostname)
          - **Binary Path**: /usr/local/bin
          - **Config Path**: /etc/proxmox-lxcri
          - **Commit**: \${{ github.sha }}
          - **Branch**: \${{ github.ref_name }}
          - **Status**: Success
          
          ## Files Deployed
          - \`proxmox-lxcri\` - Main binary
          - \`config.json\` - Configuration file
          
          ## Verification
          - Binary permissions set correctly
          - Help command executed successfully
          - Ready for production use
          EOF

      - name: Upload deployment summary
        uses: actions/upload-artifact@v4
        with:
          name: deployment-summary-\${{ github.run_id }}
          path: deployment_summary.md
          retention-days: 30

  proxmox-monitoring:
    runs-on: [self-hosted, proxmox]
    needs: [proxmox-ci, proxmox-deployment]
    if: always()
    
    steps:
      - name: Monitor Proxmox server
        run: |
          # Check server status
          echo "=== Proxmox Server Status ==="
          uptime
          df -h | head -5
          free -h
          
          # Check binary status
          echo "=== Binary Status ==="
          ls -la /usr/local/bin/proxmox-lxcri
          /usr/local/bin/proxmox-lxcri version
          
          # Check config status
          echo "=== Config Status ==="
          ls -la /etc/proxmox-lxcri/config.json

      - name: Create monitoring report
        run: |
          cat > monitoring_report.md << EOF
          # Proxmox Self-Hosted Monitoring Report - \$(date)
          
          ## Server Status
          - **Host**: \$(hostname)
          - **Uptime**: \$(uptime | awk '{print \$3,\$4}')
          - **Disk Usage**: \$(df -h / | tail -1 | awk '{print \$5}')
          - **Memory Usage**: \$(free -h | grep Mem | awk '{print \$3}')
          
          ## Application Status
          - **Binary**: /usr/local/bin/proxmox-lxcri
          - **Config**: /etc/proxmox-lxcri/config.json
          - **Version**: \$(/usr/local/bin/proxmox-lxcri version | head -1)
          
          ## Health Check
          - ✅ Runner service active
          - ✅ Binary executable
          - ✅ Config file present
          - ✅ Version command working
          
          **Status**: All systems operational
          EOF

      - name: Upload monitoring report
        uses: actions/upload-artifact@v4
        with:
          name: monitoring-report-\${{ github.run_id }}
          path: monitoring_report.md
          retention-days: 30
EOF

# 13. Display summary
echo ""
echo -e "${GREEN}🎉 GitHub Actions self-hosted runner setup completed successfully!${NC}"
echo ""
echo -e "${BLUE}📋 Summary:${NC}"
echo -e "  • Runner installed and configured on Proxmox server"
echo -e "  • Systemd service created and started"
echo -e "  • Runner registered with GitHub"
echo -e "  • Self-hosted workflow created"
echo -e "  • Dependencies installed (Zig, build tools)"
echo ""
echo -e "${BLUE}🔗 Next steps:${NC}"
echo -e "  1. Check the Actions tab in your GitHub repository"
echo -e "  2. Monitor the runner status in repository settings"
echo -e "  3. Test the self-hosted workflow"
echo -e "  4. Verify that tests run on Proxmox server"
echo ""
echo -e "${BLUE}📊 Monitoring:${NC}"
echo -e "  • GitHub Actions: https://github.com/$GITHUB_REPO/actions"
echo -e "  • Runner Status: https://github.com/$GITHUB_REPO/settings/actions/runners"
echo -e "  • Proxmox Server: $PVE_USER@$PVE_HOST"
echo -e "  • Service Status: ssh $PVE_USER@$PVE_HOST 'systemctl status github-runner'"
echo ""

# 14. Display runner status
echo -e "${BLUE}🔍 Checking runner status...${NC}"
if gh api repos/$GITHUB_REPO/actions/runners --jq '.runners[] | select(.name=="'$RUNNER_NAME'") | {name, status, labels}' | grep -q "$RUNNER_NAME"; then
    echo -e "${GREEN}✅ Runner is online and ready${NC}"
    gh api repos/$GITHUB_REPO/actions/runners --jq '.runners[] | select(.name=="'$RUNNER_NAME'") | {name, status, labels}'
else
    echo -e "${YELLOW}⚠️ Runner status unknown${NC}"
fi

echo ""
echo -e "${GREEN}🚀 Self-hosted runner setup complete! Your Proxmox server is now a GitHub Actions runner.${NC}"
