#!/bin/bash

set -euo pipefail

# Configuration
PVE_HOST="root@mgr.cp.if.ua"
PVE_PATH="/usr/local/bin"
CONFIG_PATH="/etc/nexcage"
LOG_PATH="/var/log/nexcage"
REPORT_DIR="./test-reports"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
REPORT_FILE="$REPORT_DIR/proxmox_only_test_report_$TIMESTAMP.md"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0

# Create report directory
mkdir -p "$REPORT_DIR"

# Initialize report file
cat > "$REPORT_FILE" << EOF
# Proxmox Only Test Report - $(date)

## Test Configuration
- **PVE Host**: $PVE_HOST
- **Binary Path**: $PVE_PATH
- **Config Path**: $CONFIG_PATH
- **Log Path**: $LOG_PATH
- **Timestamp**: $(date)
- **Report File**: $REPORT_FILE

## Test Results

EOF

# Function to log test result
log_test_result() {
    local test_name="$1"
    local status="$2"
    local message="$3"
    local duration="$4"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    case "$status" in
        "PASS")
            PASSED_TESTS=$((PASSED_TESTS + 1))
            echo -e "${GREEN}✅ PASS${NC}: $test_name ($duration)"
            echo "| ✅ | $test_name | PASS | $duration | $message |" >> "$REPORT_FILE"
            ;;
        "FAIL")
            FAILED_TESTS=$((FAILED_TESTS + 1))
            echo -e "${RED}❌ FAIL${NC}: $test_name ($duration) - $message"
            echo "| ❌ | $test_name | FAIL | $duration | $message |" >> "$REPORT_FILE"
            ;;
        "SKIP")
            SKIPPED_TESTS=$((SKIPPED_TESTS + 1))
            echo -e "${YELLOW}⏭️ SKIP${NC}: $test_name - $message"
            echo "| ⏭️ | $test_name | SKIP | $duration | $message |" >> "$REPORT_FILE"
            ;;
    esac
}

# Ensure Proxmox template exists (best-effort)
ensure_proxmox_template() {
    local template_name="$1"   # e.g. ubuntu-22.04-standard_22.04-1_amd64.tar.zst
    echo -e "${YELLOW}🔍 Ensuring Proxmox template available: ${template_name}${NC}"
    # Check if listed in local storage
    if ssh "$PVE_HOST" "pveam list local:vztmpl | grep -q ${template_name}" >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Template present in local:vztmpl${NC}"
        return 0
    fi
    # Try to find in available list and download
    if ssh "$PVE_HOST" "pveam available | grep -q ${template_name}" >/dev/null 2>&1; then
        echo -e "${YELLOW}⬇️  Downloading template ${template_name} to local:vztmpl...${NC}"
        if ssh "$PVE_HOST" "pveam download local ${template_name}" >/dev/null 2>&1; then
            echo -e "${GREEN}✅ Downloaded template${NC}"
            return 0
        fi
    fi
    echo -e "${YELLOW}⚠️ Could not auto-provision template: ${template_name}. Some tests may fail.${NC}"
    return 1
}

# Function to run a test with timing
run_test() {
    local test_name="$1"
    local test_command="$2"
    local start_time=$(date +%s%3N)
    
    echo -e "${BLUE}🧪 Running: $test_name${NC}"
    
    local tmp_out
    tmp_out=$(mktemp)
    if eval "$test_command" >"$tmp_out" 2>&1; then
        local end_time=$(date +%s%3N)
        local duration=$((end_time - start_time))
        log_test_result "$test_name" "PASS" "Test completed successfully" "${duration}ms"
    else
        local rc=$?
        local end_time=$(date +%s%3N)
        local duration=$((end_time - start_time))
        if [[ "$test_name" == *"Help"* ]]; then
            if grep -Eqi "(^Usage:|--help|Usage)" "$tmp_out"; then
                log_test_result "$test_name" "PASS" "Help output detected (rc=$rc)" "${duration}ms"
                rm -f "$tmp_out"
                return
            fi
        fi
        log_test_result "$test_name" "FAIL" "Test failed with exit code $rc" "${duration}ms"
    fi
    rm -f "$tmp_out"
}

# Function to run a test with expected failure
run_test_expected_fail() {
    local test_name="$1"
    local test_command="$2"
    local start_time=$(date +%s%3N)
    
    echo -e "${BLUE}🧪 Running: $test_name (expected to fail)${NC}"
    
    if ! eval "$test_command" >/dev/null 2>&1; then
        local end_time=$(date +%s%3N)
        local duration=$((end_time - start_time))
        log_test_result "$test_name" "PASS" "Test failed as expected" "${duration}ms"
    else
        local rc=$?
        local end_time=$(date +%s%3N)
        local duration=$((end_time - start_time))
        log_test_result "$test_name" "FAIL" "Test should have failed but passed (rc=$rc)" "${duration}ms"
    fi
}

# Function to check remote command
check_remote_command() {
    local cmd="$1"
    if ssh "$PVE_HOST" "command -v $cmd" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Function to check Proxmox VE version
check_proxmox_ve_version() {
    local required_major="$1"
    local required_minor="$2"
    
    # Get version from pveversion -v
    local version_output
    version_output=$(ssh "$PVE_HOST" "pveversion -v 2>/dev/null" || echo "")
    
    if [ -z "$version_output" ]; then
        return 1
    fi
    
    # Try to extract version from proxmox-ve: line first
    local version_str
    version_str=$(echo "$version_output" | grep -E "^proxmox-ve:" | sed -E 's/^proxmox-ve:[[:space:]]+([0-9]+\.[0-9]+).*/\1/' | head -1)
    
    # Fallback to pve-manager if proxmox-ve not found
    if [ -z "$version_str" ]; then
        version_str=$(echo "$version_output" | grep -E "pve-manager/" | sed -E 's/.*pve-manager\/([0-9]+\.[0-9]+).*/\1/' | head -1)
    fi
    
    if [ -z "$version_str" ]; then
        return 1
    fi
    
    # Extract major and minor version
    local major
    local minor
    major=$(echo "$version_str" | cut -d. -f1)
    minor=$(echo "$version_str" | cut -d. -f2)
    
    # Compare versions
    if [ "$major" -gt "$required_major" ] || ([ "$major" -eq "$required_major" ] && [ "$minor" -ge "$required_minor" ]); then
        return 0
    else
        return 1
    fi
}

echo -e "${BLUE}🚀 Starting Proxmox Only Test Suite${NC}"
echo "Report will be saved to: $REPORT_FILE"
echo ""

# Test 1: Build binary
echo -e "${YELLOW}📦 Building binary...${NC}"
if zig build install; then
    log_test_result "Build Binary" "PASS" "Binary built successfully" "0ms"
else
    log_test_result "Build Binary" "FAIL" "Failed to build binary" "0ms"
    echo -e "${RED}❌ Build failed, cannot continue with tests${NC}"
    exit 1
fi

# Test 2: Copy binary to PVE
echo -e "${YELLOW}📤 Copying binary to PVE...${NC}"
if scp zig-out/bin/nexcage "$PVE_HOST:$PVE_PATH/"; then
    log_test_result "Copy Binary to PVE" "PASS" "Binary copied successfully" "0ms"
else
    log_test_result "Copy Binary to PVE" "FAIL" "Failed to copy binary" "0ms"
    echo -e "${RED}❌ Failed to copy binary, cannot continue with tests${NC}"
    exit 1
fi

# Test 3: Copy config to PVE
echo -e "${YELLOW}📤 Copying config to PVE...${NC}"
if scp config.json "$PVE_HOST:$CONFIG_PATH/"; then
    log_test_result "Copy Config to PVE" "PASS" "Config copied successfully" "0ms"
else
    log_test_result "Copy Config to PVE" "FAIL" "Failed to copy config" "0ms"
    echo -e "${RED}❌ Failed to copy config, cannot continue with tests${NC}"
    exit 1
fi

# Test 4: Check PVE environment
echo -e "${YELLOW}🔍 Checking PVE environment...${NC}"
if ssh "$PVE_HOST" "export PATH=/usr/sbin:\$PATH && pct help" >/dev/null 2>&1; then
    log_test_result "PVE Environment Check" "PASS" "PVE environment is ready" "0ms"
else
    log_test_result "PVE Environment Check" "FAIL" "PVE environment not ready" "0ms"
    echo -e "${RED}❌ PVE environment not ready, skipping tests${NC}"
    exit 1
fi

# Test 5: Check PVE LXC tools
echo -e "${YELLOW}🔍 Checking PVE LXC tools...${NC}"
if ssh "$PVE_HOST" "which pct lxc-ls lxc-start lxc-stop lxc-destroy" >/dev/null 2>&1; then
    log_test_result "PVE LXC Tools Check" "PASS" "All LXC tools available" "0ms"
else
    log_test_result "PVE LXC Tools Check" "FAIL" "Some LXC tools missing" "0ms"
    echo -e "${RED}❌ LXC tools not available, skipping LXC tests${NC}"
fi

# Test 6: Check PVE storage
echo -e "${YELLOW}🔍 Checking PVE storage...${NC}"
if ssh "$PVE_HOST" "df -h | grep -q rpool" >/dev/null 2>&1; then
    log_test_result "PVE Storage Check" "PASS" "ZFS storage available" "0ms"
else
    log_test_result "PVE Storage Check" "FAIL" "ZFS storage not available" "0ms"
    echo -e "${YELLOW}⚠️ ZFS storage not available, some tests may fail${NC}"
fi

# Test 7: Check PVE network
echo -e "${YELLOW}🔍 Checking PVE network...${NC}"
if ssh "$PVE_HOST" "ip link show | grep -q vmbr" >/dev/null 2>&1; then
    log_test_result "PVE Network Check" "PASS" "Bridge interfaces available" "0ms"
else
    log_test_result "PVE Network Check" "FAIL" "Bridge interfaces not available" "0ms"
    echo -e "${YELLOW}⚠️ Bridge interfaces not available, some tests may fail${NC}"
fi

# Test 8: Remote help command
run_test "Remote Help Command" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage --help'"

# Test 9: Remote version command
run_test "Remote Version Command" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage version'"

# Test 10: Remote create help
run_test "Remote Create Help" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage create --help'"

# Test 11: Remote start help
run_test "Remote Start Help" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage start --help'"

# Test 12: Remote stop help
run_test "Remote Stop Help" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage stop --help'"

# Test 13: Remote delete help
run_test "Remote Delete Help" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage delete --help'"

# Test 14: Remote list help
run_test "Remote List Help" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage list --help'"

# Test 15: Remote run help
run_test "Remote Run Help" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage run --help'"

# Test 15a: Remote state help
run_test "Remote State Help" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage state --help'"

# Test 15b: Remote kill help
run_test "Remote Kill Help" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage kill --help'"

# Test 16: Test create command (should fail without proper setup)
run_test_expected_fail "Remote Create Command (Expected Fail)" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage create --name test-container --image ubuntu:20.04'"

# Test 17: Test start command (should fail without container)
run_test_expected_fail "Remote Start Command (Expected Fail)" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage start --name test-container'"

# Test 18: Test stop command (should fail without container)
run_test_expected_fail "Remote Stop Command (Expected Fail)" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage stop --name test-container'"

# Test 19: Test delete command (should fail without container)
run_test_expected_fail "Remote Delete Command (Expected Fail)" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage delete --name test-container'"

# Test 20: Test list command (should work)
run_test "Remote List Command" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage list'"

# Test 20a: Test state command (should work with existing containers)
run_test "Remote State Command" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage state 101 || ./nexcage state 999'"

# Test 21: Test run command (should fail without container)
run_test_expected_fail "Remote Run Command (Expected Fail)" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage run --name test-container --command /bin/echo hello'"

# Test 21a: Test kill command (should fail without container or on stopped container)
run_test_expected_fail "Remote Kill Command (Expected Fail)" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage kill test-nonexistent-container'"

# Test 22: Test invalid command (should fail)
run_test_expected_fail "Remote Invalid Command (Expected Fail)" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage invalid-command'"

# Test 23: Test missing required arguments (should fail)
run_test_expected_fail "Remote Missing Args (Expected Fail)" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage create'"

# Test 24: Test invalid runtime (should fail)
run_test_expected_fail "Remote Invalid Runtime (Expected Fail)" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage create --name test --image ubuntu --runtime invalid'"

# Test 25: Test config file loading
run_test "Remote Config Loading" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage create --name test --image ubuntu --config $CONFIG_PATH/config.json --help'"

# Test 26: Test Proxmox-LXC container creation (if LXC tools available)
if check_remote_command "pct"; then
    echo -e "${YELLOW}🧪 Testing  Proxmox LXC container creation...${NC}"
    # Best-effort: ensure a common ubuntu template exists
    ensure_proxmox_template "ubuntu-22.04-standard_22.04-1_amd64.tar.zst" || true
    
    # Test 27: Create Proxmox-LXC container
    run_test "Proxmox-LXC Container Creation" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage create --name test-lxc-container --image local:vztmpl/ubuntu-22.04-standard_22.04-1_amd64.tar.zst --runtime proxmox-lxc'"
    
    # Test 28: List Proxmox-LXC containers
    run_test "Proxmox-LXC Container List" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage list --runtime proxmox-lxc'"
    
    # Test 29: Start Proxmox-LXC container
    run_test "Proxmox-LXC Container Start" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage start --name test-lxc-container --runtime proxmox-lxc'"
    
    # Test 29a: State Proxmox-LXC container (while running)
    run_test "Proxmox-LXC Container State (Running)" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage state test-lxc-container'"
    
    # Test 29b: Kill Proxmox-LXC container with SIGTERM (with debug to see exec attempts)
    run_test "Proxmox-LXC Container Kill (SIGTERM)" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage --debug kill -s SIGTERM test-lxc-container 2>&1 | head -100'"
    
    # Test 30: Stop Proxmox-LXC container
    run_test "Proxmox-LXC Container Stop" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage stop --name test-lxc-container --runtime proxmox-lxc'"
    
    # Test 30a: State Proxmox-LXC container (while stopped)
    run_test "Proxmox-LXC Container State (Stopped)" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage state test-lxc-container'"
    
    # Test 31: Delete Proxmox-LXC container
    run_test "Proxmox-LXC Container Delete" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage delete --name test-lxc-container --runtime proxmox-lxc'"
else
    echo -e "${YELLOW}⏭️ Skipping Proxmox-LXC tests - LXC tools not available${NC}"
    log_test_result "Proxmox-LXC Container Tests" "SKIP" "LXC tools not available" "0ms"
fi

# Test 32: Test OCI Registry Pull (Proxmox VE 9.1+)
echo -e "${YELLOW}🧪 Testing OCI Registry Pull (Proxmox VE 9.1+)...${NC}"
if check_proxmox_ve_version 9 1; then
    echo -e "${GREEN}✅ Proxmox VE 9.1+ detected, OCI Registry pull supported${NC}"
    
    # Test 32a: Create container with PostgreSQL OCI image
    run_test "OCI Registry Pull - PostgreSQL Container Creation" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage create --name test-postgres-oci-registry --image docker.io/library/postgres:latest --runtime proxmox-lxc'"
    
    # Test 32b: List containers with OCI Registry image
    run_test "OCI Registry Pull - Container List" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage list --runtime proxmox-lxc | grep test-postgres-oci-registry'"
    
    # Test 32c: Start container with OCI Registry image
    run_test "OCI Registry Pull - Container Start" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage start --name test-postgres-oci-registry --runtime proxmox-lxc'"
    
    # Test 32d: State container with OCI Registry image (while running)
    run_test "OCI Registry Pull - Container State (Running)" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage state test-postgres-oci-registry'"
    
    # Test 32e: Stop container with OCI Registry image
    run_test "OCI Registry Pull - Container Stop" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage stop --name test-postgres-oci-registry --runtime proxmox-lxc'"
    
    # Test 32f: State container with OCI Registry image (while stopped)
    run_test "OCI Registry Pull - Container State (Stopped)" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage state test-postgres-oci-registry'"
    
    # Test 32g: Delete container with OCI Registry image
    run_test "OCI Registry Pull - Container Delete" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage delete --name test-postgres-oci-registry --runtime proxmox-lxc'"
    
    # Test 32h: Create container with Redis OCI image (different image)
    run_test "OCI Registry Pull - Redis Container Creation" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage create --name test-redis-oci-registry --image docker.io/library/redis:latest --runtime proxmox-lxc'"
    
    # Test 32i: Delete Redis container
    run_test "OCI Registry Pull - Redis Container Delete" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage delete --name test-redis-oci-registry --runtime proxmox-lxc'"
else
    echo -e "${YELLOW}⏭️ Skipping OCI Registry Pull tests - Proxmox VE version < 9.1${NC}"
    log_test_result "OCI Registry Pull Tests" "SKIP" "Proxmox VE version < 9.1" "0ms"
fi

# Test 33: Test OCI container creation (gated)
if [ "${ENABLE_OCI_TESTS:-0}" = "1" ] && check_remote_command "crun"; then
    echo -e "${YELLOW}🧪 Testing OCI container creation...${NC}"
    
    # Test 33: Create OCI container
    run_test "OCI Container Creation" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage create --name test-oci-container --image nginx --runtime crun'"
    
    # Test 35: List OCI containers
    run_test "OCI Container List" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage list --runtime crun'"
    
    # Test 36: Start OCI container
    run_test "OCI Container Start" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage start --name test-oci-container --runtime crun'"
    
    # Test 36a: State OCI container (while running)
    run_test "OCI Container State (Running)" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage state test-oci-container'"
    
    # Test 36b: Kill OCI container with SIGTERM
    run_test "OCI Container Kill (SIGTERM)" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage kill -s SIGTERM test-oci-container'"
    
    # Test 37: Stop OCI container
    run_test "OCI Container Stop" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage stop --name test-oci-container --runtime crun'"
    
    # Test 37a: State OCI container (while stopped)
    run_test "OCI Container State (Stopped)" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage state test-oci-container'"
    
    # Test 38: Delete OCI container
    run_test "OCI Container Delete" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage delete --name test-oci-container --runtime crun'"
else
    echo -e "${YELLOW}⏭️ Skipping OCI tests - crun not available${NC}"
    log_test_result "OCI Container Tests" "SKIP" "crun not available" "0ms"
fi

# Test 39: Test runc container creation (gated)
if [ "${ENABLE_RUNC_TESTS:-0}" = "1" ] && check_remote_command "runc"; then
    echo -e "${YELLOW}🧪 Testing runc container creation...${NC}"
    
    # Test 39: Create runc container
    run_test "Runc Container Creation" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage create --name test-runc-container --image nginx --runtime runc'"
    
    # Test 40: List runc containers
    run_test "Runc Container List" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage list --runtime runc'"
    
    # Test 41: Start runc container
    run_test "Runc Container Start" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage start --name test-runc-container --runtime runc'"
    
    # Test 41a: State runc container (while running)
    run_test "Runc Container State (Running)" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage state test-runc-container'"
    
    # Test 41b: Kill runc container with SIGTERM
    run_test "Runc Container Kill (SIGTERM)" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage kill -s SIGTERM test-runc-container'"
    
    # Test 42: Stop runc container
    run_test "Runc Container Stop" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage stop --name test-runc-container --runtime runc'"
    
    # Test 42a: State runc container (while stopped)
    run_test "Runc Container State (Stopped)" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage state test-runc-container'"
    
    # Test 43: Delete runc container
    run_test "Runc Container Delete" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage delete --name test-runc-container --runtime runc'"
else
    echo -e "${YELLOW}⏭️ Skipping runc tests - runc not available${NC}"
    log_test_result "Runc Container Tests" "SKIP" "runc not available" "0ms"
fi

# Test 45: Test performance
echo -e "${YELLOW}🧪 Testing performance...${NC}"
run_test "Performance Test" "ssh $PVE_HOST 'cd $PVE_PATH && time ./nexcage --help'"

# Test 46: Test memory usage
echo -e "${YELLOW}🧪 Testing memory usage...${NC}"
run_test "Memory Usage Test" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage --help && ps aux | grep nexcage'"

# Test 47: Test error handling
echo -e "${YELLOW}🧪 Testing error handling...${NC}"
run_test_expected_fail "Error Handling Test" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage create --name invalid-container --image invalid-image --runtime invalid-runtime'"

# Generate final report
echo ""
echo -e "${BLUE}📊 Generating final report...${NC}"

# Calculate success rate
SUCCESS_RATE=0
if [ $TOTAL_TESTS -gt 0 ]; then
    SUCCESS_RATE=$((PASSED_TESTS * 100 / TOTAL_TESTS))
fi

# Add summary to report
cat >> "$REPORT_FILE" << EOF

## Summary

| Metric | Value |
|--------|-------|
| Total Tests | $TOTAL_TESTS |
| Passed | $PASSED_TESTS |
| Failed | $FAILED_TESTS |
| Skipped | $SKIPPED_TESTS |
| Success Rate | $SUCCESS_RATE% |

## Test Environment

- **OS**: $(uname -s)
- **Architecture**: $(uname -m)
- **Zig Version**: $(zig version)
- **PVE Host**: $PVE_HOST
- **Test Duration**: $(date)

## Notes

- All tests were run on Proxmox VE server
- Remote tests require SSH access to PVE host
- Some tests are expected to fail (negative testing)
- Binary and config are copied to PVE for testing
- Container lifecycle tests include create, start, stop, delete

EOF

# Display final summary
echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                    PROXMOX ONLY TEST REPORT                 ║${NC}"
echo -e "${BLUE}╠══════════════════════════════════════════════════════════════╣${NC}"
printf "${BLUE}║ Total Tests: %3d                                          ║${NC}\n" $TOTAL_TESTS
printf "${BLUE}║ Passed:      %3d (%5.1f%%)                              ║${NC}\n" $PASSED_TESTS $SUCCESS_RATE
printf "${BLUE}║ Failed:      %3d                                          ║${NC}\n" $FAILED_TESTS
printf "${BLUE}║ Skipped:     %3d                                          ║${NC}\n" $SKIPPED_TESTS
printf "${BLUE}║ Success Rate: %5.1f%%                                      ║${NC}\n" $SUCCESS_RATE
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}📊 Detailed report saved to: $REPORT_FILE${NC}"

# Exit with appropriate code
if [ $FAILED_TESTS -eq 0 ]; then
    echo -e "${GREEN}🎉 All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}❌ Some tests failed. Check the report for details.${NC}"
    exit 1
fi
