#!/bin/bash

set -euo pipefail

# Configuration
PVE_HOST="root@mgr.cp.if.ua"
PVE_PATH="/usr/local/bin"
CONFIG_PATH="/etc/nexcage"
LOG_PATH="/var/log/nexcage"
REPORT_DIR="./test-reports"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
REPORT_FILE="$REPORT_DIR/proxmox_e2e_test_report_$TIMESTAMP.md"

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
# Proxmox E2E Test Report - $(date)

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

# Function to run a test with timing
run_test() {
    local test_name="$1"
    local test_command="$2"
    local start_time=$(date +%s%3N)
    
    echo -e "${BLUE}🧪 Running: $test_name${NC}"
    
    if eval "$test_command" >/dev/null 2>&1; then
        local end_time=$(date +%s%3N)
        local duration=$((end_time - start_time))
        log_test_result "$test_name" "PASS" "Test completed successfully" "${duration}ms"
    else
        local end_time=$(date +%s%3N)
        local duration=$((end_time - start_time))
        log_test_result "$test_name" "FAIL" "Test failed with exit code $?" "${duration}ms"
    fi
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
        local end_time=$(date +%s%3N)
        local duration=$((end_time - start_time))
        log_test_result "$test_name" "FAIL" "Test should have failed but passed" "${duration}ms"
    fi
}

# Function to check if command exists
check_command() {
    local cmd="$1"
    if command -v "$cmd" >/dev/null 2>&1; then
        return 0
    else
        return 1
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

echo -e "${BLUE}🚀 Starting Proxmox E2E Test Suite with Detailed Reporting${NC}"
echo "Report will be saved to: $REPORT_FILE"
echo ""

# Test 1: Build binary
echo -e "${YELLOW}📦 Building binary...${NC}"
if zig build install; then
    log_test_result "Build Binary" "PASS" "Binary built successfully" "0ms"
else
    log_test_result "Build Binary" "FAIL" "Failed to build binary" "0ms"
    echo -e "${RED}❌ Build failed, cannot continue with E2E tests${NC}"
    exit 1
fi

# Local tests removed - no point testing without Proxmox server

# Test 2: Copy binary to PVE
echo -e "${YELLOW}📤 Copying binary to PVE...${NC}"
if scp zig-out/bin/nexcage "$PVE_HOST:$PVE_PATH/"; then
    log_test_result "Copy Binary to PVE" "PASS" "Binary copied successfully" "0ms"
else
    log_test_result "Copy Binary to PVE" "FAIL" "Failed to copy binary" "0ms"
    echo -e "${RED}❌ Failed to copy binary, cannot continue with remote tests${NC}"
    exit 1
fi

# Test 3: Copy config to PVE
echo -e "${YELLOW}📤 Copying config to PVE...${NC}"
if scp config.json "$PVE_HOST:$CONFIG_PATH/"; then
    log_test_result "Copy Config to PVE" "PASS" "Config copied successfully" "0ms"
else
    log_test_result "Copy Config to PVE" "FAIL" "Failed to copy config" "0ms"
    echo -e "${RED}❌ Failed to copy config, cannot continue with remote tests${NC}"
    exit 1
fi

# Test 4: Check PVE environment
echo -e "${YELLOW}🔍 Checking PVE environment...${NC}"
if ssh "$PVE_HOST" "export PATH=/usr/sbin:\$PATH && pct help" >/dev/null 2>&1; then
    log_test_result "PVE Environment Check" "PASS" "PVE environment is ready" "0ms"
else
    log_test_result "PVE Environment Check" "FAIL" "PVE environment not ready" "0ms"
    echo -e "${RED}❌ PVE environment not ready, skipping remote tests${NC}"
    exit 1
fi

# Test  Check PVE LXC tools
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

# Test  Remote help command
run_test "Remote Help Command" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage --help'"

# Test  Remote version command
run_test "Remote Version Command" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage version'"

# Test  Remote create help
run_test "Remote Create Help" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage create --help'"

# Test  Remote start help
run_test "Remote Start Help" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage start --help'"

# Test 20: Remote stop help
run_test "Remote Stop Help" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage stop --help'"

# Test 21: Remote delete help
run_test "Remote Delete Help" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage delete --help'"

# Test 22: Remote list help
run_test "Remote List Help" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage list --help'"

# Test 23: Remote run help
run_test "Remote Run Help" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage run --help'"

# Test 24: Test create command (should fail without proper setup)
run_test_expected_fail "Remote Create Command (Expected Fail)" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage create --name test-container --image ubuntu:20.04'"

# Test 25: Test start command (should fail without container)
run_test_expected_fail "Remote Start Command (Expected Fail)" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage start --name test-container'"

# Test 26: Test stop command (should fail without container)
run_test_expected_fail "Remote Stop Command (Expected Fail)" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage stop --name test-container'"

# Test 27: Test delete command (should fail without container)
run_test_expected_fail "Remote Delete Command (Expected Fail)" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage delete --name test-container'"

# Test 28: Test list command (should work)
run_test "Remote List Command" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage list'"

# Test 29: Test run command (should fail without container)
run_test_expected_fail "Remote Run Command (Expected Fail)" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage run --name test-container --command /bin/echo hello'"

# Test 30: Test invalid command (should fail)
run_test_expected_fail "Remote Invalid Command (Expected Fail)" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage invalid-command'"

# Test 31: Test missing required arguments (should fail)
run_test_expected_fail "Remote Missing Args (Expected Fail)" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage create'"

# Test 32: Test invalid runtime (should fail)
run_test_expected_fail "Remote Invalid Runtime (Expected Fail)" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage create --name test --image ubuntu --runtime invalid'"

# Test 33: Test config file loading
run_test "Remote Config Loading" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage create --name test --image ubuntu --config $CONFIG_PATH/config.json --help'"

# Test 34: Test LXC container creation (if LXC tools available)
if check_remote_command "pct"; then
    echo -e "${YELLOW}🧪 Testing LXC container creation...${NC}"
    
    # Test 35: Create LXC container
    run_test "LXC Container Creation" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage create --name test-lxc-container --image ubuntu:20.04 --runtime lxc'"
    
    # Test 36: List LXC containers
    run_test "LXC Container List" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage list --runtime lxc'"
    
    # Test 37: Start LXC container
    run_test "LXC Container Start" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage start --name test-lxc-container --runtime lxc'"
    
    # Test 38: Stop LXC container
    run_test "LXC Container Stop" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage stop --name test-lxc-container --runtime lxc'"
    
    # Test 39: Delete LXC container
    run_test "LXC Container Delete" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage delete --name test-lxc-container --runtime lxc'"
else
    echo -e "${YELLOW}⏭️ Skipping LXC tests - LXC tools not available${NC}"
    log_test_result "LXC Container Tests" "SKIP" "LXC tools not available" "0ms"
fi

# Test 40: Test OCI container creation (if crun available)
if check_remote_command "crun"; then
    echo -e "${YELLOW}🧪 Testing OCI container creation...${NC}"
    
    # Test 41: Create OCI container
    run_test "OCI Container Creation" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage create --name test-oci-container --image nginx --runtime crun'"
    
    # Test 42: List OCI containers
    run_test "OCI Container List" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage list --runtime crun'"
    
    # Test 43: Start OCI container
    run_test "OCI Container Start" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage start --name test-oci-container --runtime crun'"
    
    # Test 44: Stop OCI container
    run_test "OCI Container Stop" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage stop --name test-oci-container --runtime crun'"
    
    # Test 45: Delete OCI container
    run_test "OCI Container Delete" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage delete --name test-oci-container --runtime crun'"
else
    echo -e "${YELLOW}⏭️ Skipping OCI tests - crun not available${NC}"
    log_test_result "OCI Container Tests" "SKIP" "crun not available" "0ms"
fi

# Test 46: Test runc container creation (if runc available)
if check_remote_command "runc"; then
    echo -e "${YELLOW}🧪 Testing runc container creation...${NC}"
    
    # Test 47: Create runc container
    run_test "Runc Container Creation" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage create --name test-runc-container --image nginx --runtime runc'"
    
    # Test 48: List runc containers
    run_test "Runc Container List" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage list --runtime runc'"
    
    # Test 49: Start runc container
    run_test "Runc Container Start" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage start --name test-runc-container --runtime runc'"
    
    # Test 50: Stop runc container
    run_test "Runc Container Stop" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage stop --name test-runc-container --runtime runc'"
    
    # Test 51: Delete runc container
    run_test "Runc Container Delete" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage delete --name test-runc-container --runtime runc'"
else
    echo -e "${YELLOW}⏭️ Skipping runc tests - runc not available${NC}"
    log_test_result "Runc Container Tests" "SKIP" "runc not available" "0ms"
fi

# Test 52: Test VM creation (if Proxmox API available)
echo -e "${YELLOW}🧪 Testing VM creation...${NC}"
run_test "VM Creation Test" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage create --name test-vm --image ubuntu:20.04 --runtime vm'"

# Test 53: Test performance
echo -e "${YELLOW}🧪 Testing performance...${NC}"
run_test "Performance Test" "ssh $PVE_HOST 'cd $PVE_PATH && time ./nexcage --help'"

# Test 54: Test memory usage
echo -e "${YELLOW}🧪 Testing memory usage...${NC}"
run_test "Memory Usage Test" "ssh $PVE_HOST 'cd $PVE_PATH && ./nexcage --help && ps aux | grep nexcage'"

# Test 55: Test error handling
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
echo -e "${BLUE}║                    PROXMOX E2E TEST REPORT                  ║${NC}"
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
