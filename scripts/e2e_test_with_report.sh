#!/bin/bash

set -euo pipefail

# Configuration
PVE_HOST="root@mgr.cp.if.ua"
PVE_PATH="/usr/local/bin"
CONFIG_PATH="/etc/proxmox-lxcri"
LOG_PATH="/var/log/proxmox-lxcri"
REPORT_DIR="./test-reports"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
REPORT_FILE="$REPORT_DIR/e2e_test_report_$TIMESTAMP.md"

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
# E2E Test Report - $(date)

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

echo -e "${BLUE}🚀 Starting E2E Test Suite with Detailed Reporting${NC}"
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

# Test 2: Check local help command
run_test "Local Help Command" "./zig-out/bin/proxmox-lxcri --help"

# Test 3: Check local version command
run_test "Local Version Command" "./zig-out/bin/proxmox-lxcri version"

# Test 4: Check local create help
run_test "Local Create Help" "./zig-out/bin/proxmox-lxcri create --help"

# Test 5: Check local start help
run_test "Local Start Help" "./zig-out/bin/proxmox-lxcri start --help"

# Test 6: Check local stop help
run_test "Local Stop Help" "./zig-out/bin/proxmox-lxcri stop --help"

# Test 7: Check local delete help
run_test "Local Delete Help" "./zig-out/bin/proxmox-lxcri delete --help"

# Test 8: Check local list help
run_test "Local List Help" "./zig-out/bin/proxmox-lxcri list --help"

# Test 9: Check local run help
run_test "Local Run Help" "./zig-out/bin/proxmox-lxcri run --help"

# Test 10: Copy binary to PVE
echo -e "${YELLOW}📤 Copying binary to PVE...${NC}"
if scp zig-out/bin/proxmox-lxcri "$PVE_HOST:$PVE_PATH/"; then
    log_test_result "Copy Binary to PVE" "PASS" "Binary copied successfully" "0ms"
else
    log_test_result "Copy Binary to PVE" "FAIL" "Failed to copy binary" "0ms"
    echo -e "${RED}❌ Failed to copy binary, cannot continue with remote tests${NC}"
    exit 1
fi

# Test 11: Copy config to PVE
echo -e "${YELLOW}📤 Copying config to PVE...${NC}"
if scp config.json "$PVE_HOST:$CONFIG_PATH/"; then
    log_test_result "Copy Config to PVE" "PASS" "Config copied successfully" "0ms"
else
    log_test_result "Copy Config to PVE" "FAIL" "Failed to copy config" "0ms"
    echo -e "${RED}❌ Failed to copy config, cannot continue with remote tests${NC}"
    exit 1
fi

# Test 12: Check PVE environment
echo -e "${YELLOW}🔍 Checking PVE environment...${NC}"
if ssh "$PVE_HOST" "export PATH=/usr/sbin:\$PATH && pct help" >/dev/null 2>&1; then
    log_test_result "PVE Environment Check" "PASS" "PVE environment is ready" "0ms"
else
    log_test_result "PVE Environment Check" "FAIL" "PVE environment not ready" "0ms"
    echo -e "${RED}❌ PVE environment not ready, skipping remote tests${NC}"
    exit 1
fi

# Test 13: Remote help command
run_test "Remote Help Command" "ssh $PVE_HOST 'cd $PVE_PATH && ./proxmox-lxcri --help'"

# Test 14: Remote version command
run_test "Remote Version Command" "ssh $PVE_HOST 'cd $PVE_PATH && ./proxmox-lxcri version'"

# Test 15: Remote create help
run_test "Remote Create Help" "ssh $PVE_HOST 'cd $PVE_PATH && ./proxmox-lxcri create --help'"

# Test 16: Remote start help
run_test "Remote Start Help" "ssh $PVE_HOST 'cd $PVE_PATH && ./proxmox-lxcri start --help'"

# Test 17: Remote stop help
run_test "Remote Stop Help" "ssh $PVE_HOST 'cd $PVE_PATH && ./proxmox-lxcri stop --help'"

# Test 18: Remote delete help
run_test "Remote Delete Help" "ssh $PVE_HOST 'cd $PVE_PATH && ./proxmox-lxcri delete --help'"

# Test 19: Remote list help
run_test "Remote List Help" "ssh $PVE_HOST 'cd $PVE_PATH && ./proxmox-lxcri list --help'"

# Test 20: Remote run help
run_test "Remote Run Help" "ssh $PVE_HOST 'cd $PVE_PATH && ./proxmox-lxcri run --help'"

# Test 21: Test create command (should fail without proper setup)
run_test_expected_fail "Remote Create Command (Expected Fail)" "ssh $PVE_HOST 'cd $PVE_PATH && ./proxmox-lxcri create --name test-container --image ubuntu:20.04'"

# Test 22: Test start command (should fail without container)
run_test_expected_fail "Remote Start Command (Expected Fail)" "ssh $PVE_HOST 'cd $PVE_PATH && ./proxmox-lxcri start --name test-container'"

# Test 23: Test stop command (should fail without container)
run_test_expected_fail "Remote Stop Command (Expected Fail)" "ssh $PVE_HOST 'cd $PVE_PATH && ./proxmox-lxcri stop --name test-container'"

# Test 24: Test delete command (should fail without container)
run_test_expected_fail "Remote Delete Command (Expected Fail)" "ssh $PVE_HOST 'cd $PVE_PATH && ./proxmox-lxcri delete --name test-container'"

# Test 25: Test list command (should work)
run_test "Remote List Command" "ssh $PVE_HOST 'cd $PVE_PATH && ./proxmox-lxcri list'"

# Test 26: Test run command (should fail without container)
run_test_expected_fail "Remote Run Command (Expected Fail)" "ssh $PVE_HOST 'cd $PVE_PATH && ./proxmox-lxcri run --name test-container --command /bin/echo hello'"

# Test 27: Test invalid command (should fail)
run_test_expected_fail "Remote Invalid Command (Expected Fail)" "ssh $PVE_HOST 'cd $PVE_PATH && ./proxmox-lxcri invalid-command'"

# Test 28: Test missing required arguments (should fail)
run_test_expected_fail "Remote Missing Args (Expected Fail)" "ssh $PVE_HOST 'cd $PVE_PATH && ./proxmox-lxcri create'"

# Test 29: Test invalid runtime (should fail)
run_test_expected_fail "Remote Invalid Runtime (Expected Fail)" "ssh $PVE_HOST 'cd $PVE_PATH && ./proxmox-lxcri create --name test --image ubuntu --runtime invalid'"

# Test 30: Test config file loading
run_test "Remote Config Loading" "ssh $PVE_HOST 'cd $PVE_PATH && ./proxmox-lxcri create --name test --image ubuntu --config $CONFIG_PATH/config.json --help'"

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

- All tests were run in a controlled environment
- Remote tests require SSH access to PVE host
- Some tests are expected to fail (negative testing)
- Binary and config are copied to PVE for testing

EOF

# Display final summary
echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                        E2E TEST REPORT                      ║${NC}"
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
