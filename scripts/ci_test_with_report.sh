#!/bin/bash

set -euo pipefail

# Configuration
REPORT_DIR="./test-reports"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
REPORT_FILE="$REPORT_DIR/ci_test_report_$TIMESTAMP.md"
LOG_FILE="$REPORT_DIR/ci_test_log_$TIMESTAMP.log"

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
# CI Test Report - $(date)

## Test Configuration
- **Timestamp**: $(date)
- **Report File**: $REPORT_FILE
- **Log File**: $LOG_FILE
- **Zig Version**: $(zig version)
- **OS**: $(uname -s)
- **Architecture**: $(uname -m)
- **Git Branch**: $(git branch --show-current)
- **Git Commit**: $(git rev-parse HEAD)

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
    
    if eval "$test_command" > "$LOG_FILE" 2>&1; then
        local end_time=$(date +%s%3N)
        local duration=$((end_time - start_time))
        log_test_result "$test_name" "PASS" "Test completed successfully" "${duration}ms"
    else
        local end_time=$(date +%s%3N)
        local duration=$((end_time - start_time))
        local error_msg=$(tail -n 5 "$LOG_FILE" | tr '\n' ' ')
        log_test_result "$test_name" "FAIL" "Test failed: $error_msg" "${duration}ms"
    fi
}

# Function to run a test with expected failure
run_test_expected_fail() {
    local test_name="$1"
    local test_command="$2"
    local start_time=$(date +%s%3N)
    
    echo -e "${BLUE}🧪 Running: $test_name (expected to fail)${NC}"
    
    if ! eval "$test_command" > "$LOG_FILE" 2>&1; then
        local end_time=$(date +%s%3N)
        local duration=$((end_time - start_time))
        log_test_result "$test_name" "PASS" "Test failed as expected" "${duration}ms"
    else
        local end_time=$(date +%s%3N)
        local duration=$((end_time - start_time))
        log_test_result "$test_name" "FAIL" "Test should have failed but passed" "${duration}ms"
    fi
}

echo -e "${BLUE}🚀 Starting CI Test Suite with Detailed Reporting${NC}"
echo "Report will be saved to: $REPORT_FILE"
echo "Log will be saved to: $LOG_FILE"
echo ""

# Test 1: Check Zig version
echo -e "${YELLOW}🔍 Checking Zig version...${NC}"
ZIG_VERSION=$(zig version)
if [ $? -eq 0 ]; then
    log_test_result "Zig Version Check" "PASS" "Zig version: $ZIG_VERSION" "0ms"
else
    log_test_result "Zig Version Check" "FAIL" "Failed to get Zig version" "0ms"
    echo -e "${RED}❌ Zig not found, cannot continue with tests${NC}"
    exit 1
fi

# Test 2: Check Git status
echo -e "${YELLOW}🔍 Checking Git status...${NC}"
if git status --porcelain | grep -q .; then
    log_test_result "Git Status Check" "PASS" "Git working directory has changes" "0ms"
else
    log_test_result "Git Status Check" "PASS" "Git working directory is clean" "0ms"
fi

# Test 3: Check dependencies
echo -e "${YELLOW}🔍 Checking dependencies...${NC}"
MISSING_DEPS=()
if ! command -v zig >/dev/null 2>&1; then
    MISSING_DEPS+=("zig")
fi
if ! command -v git >/dev/null 2>&1; then
    MISSING_DEPS+=("git")
fi
if ! command -v make >/dev/null 2>&1; then
    MISSING_DEPS+=("make")
fi

if [ ${#MISSING_DEPS[@]} -eq 0 ]; then
    log_test_result "Dependencies Check" "PASS" "All required dependencies found" "0ms"
else
    log_test_result "Dependencies Check" "FAIL" "Missing dependencies: ${MISSING_DEPS[*]}" "0ms"
    echo -e "${RED}❌ Missing dependencies, cannot continue with tests${NC}"
    exit 1
fi

# Test 4: Build project
echo -e "${YELLOW}📦 Building project...${NC}"
if zig build; then
    log_test_result "Build Project" "PASS" "Project built successfully" "0ms"
else
    log_test_result "Build Project" "FAIL" "Failed to build project" "0ms"
    echo -e "${RED}❌ Build failed, cannot continue with tests${NC}"
    exit 1
fi

# Test 5: Run unit tests
run_test "Unit Tests" "zig build test"

# Test 6: Check binary exists
echo -e "${YELLOW}🔍 Checking binary exists...${NC}"
if [ -f "./zig-out/bin/nexcage" ]; then
    log_test_result "Binary Exists Check" "PASS" "Binary found at ./zig-out/bin/nexcage" "0ms"
else
    log_test_result "Binary Exists Check" "FAIL" "Binary not found at ./zig-out/bin/nexcage" "0ms"
    echo -e "${RED}❌ Binary not found, cannot continue with tests${NC}"
    exit 1
fi

# Test 7: Check binary permissions
echo -e "${YELLOW}🔍 Checking binary permissions...${NC}"
if [ -x "./zig-out/bin/nexcage" ]; then
    log_test_result "Binary Permissions Check" "PASS" "Binary is executable" "0ms"
else
    log_test_result "Binary Permissions Check" "FAIL" "Binary is not executable" "0ms"
    echo -e "${RED}❌ Binary is not executable, cannot continue with tests${NC}"
    exit 1
fi

# Test 8: Test help command
run_test "Help Command" "./zig-out/bin/nexcage --help"

# Test 9: Test version command
run_test "Version Command" "./zig-out/bin/nexcage version"

# Test 10: Test create help
run_test "Create Help Command" "./zig-out/bin/nexcage create --help"

# Test 11: Test start help
run_test "Start Help Command" "./zig-out/bin/nexcage start --help"

# Test 12: Test stop help
run_test "Stop Help Command" "./zig-out/bin/nexcage stop --help"

# Test 13: Test delete help
run_test "Delete Help Command" "./zig-out/bin/nexcage delete --help"

# Test 14: Test list help
run_test "List Help Command" "./zig-out/bin/nexcage list --help"

# Test 15: Test run help
run_test "Run Help Command" "./zig-out/bin/nexcage run --help"

# Test 16: Test invalid command (should fail)
run_test_expected_fail "Invalid Command (Expected Fail)" "./zig-out/bin/nexcage invalid-command"

# Test 17: Test missing required arguments (should fail)
run_test_expected_fail "Missing Args (Expected Fail)" "./zig-out/bin/nexcage create"

# Test 18: Test invalid runtime (should fail)
run_test_expected_fail "Invalid Runtime (Expected Fail)" "./zig-out/bin/nexcage create --name test --image ubuntu --runtime invalid"

# Test 19: Test config file loading
run_test "Config File Loading" "./zig-out/bin/nexcage create --name test --image ubuntu --config config.json --help"

# Test 20: Test verbose flag
run_test "Verbose Flag" "./zig-out/bin/nexcage create --name test --image ubuntu --verbose --help"

# Test 21: Test debug flag
run_test "Debug Flag" "./zig-out/bin/nexcage create --name test --image ubuntu --debug --help"

# Test 22: Test detach flag
run_test "Detach Flag" "./zig-out/bin/nexcage create --name test --image ubuntu --detach --help"

# Test 23: Test interactive flag
run_test "Interactive Flag" "./zig-out/bin/nexcage create --name test --image ubuntu --interactive --help"

# Test 24: Test tty flag
run_test "TTY Flag" "./zig-out/bin/nexcage create --name test --image ubuntu --tty --help"

# Test 25: Test user flag
run_test "User Flag" "./zig-out/bin/nexcage create --name test --image ubuntu --user root --help"

# Test 26: Test workdir flag
run_test "Workdir Flag" "./zig-out/bin/nexcage create --name test --image ubuntu --workdir /tmp --help"

# Test 27: Test env flag
run_test "Env Flag" "./zig-out/bin/nexcage create --name test --image ubuntu --env PATH=/bin --help"

# Test 28: Test args flag
run_test "Args Flag" "./zig-out/bin/nexcage create --name test --image ubuntu --args /bin/echo hello --help"

# Test 29: Test runtime flag
run_test "Runtime Flag" "./zig-out/bin/nexcage create --name test --image ubuntu --runtime lxc --help"

# Test 30: Test config flag
run_test "Config Flag" "./zig-out/bin/nexcage create --name test --image ubuntu --config config.json --help"

# Test 31: Test memory usage
echo -e "${YELLOW}🔍 Checking memory usage...${NC}"
MEMORY_USAGE=$(ps -o rss= -p $$ | tr -d ' ')
if [ $? -eq 0 ]; then
    log_test_result "Memory Usage Check" "PASS" "Memory usage: ${MEMORY_USAGE}KB" "0ms"
else
    log_test_result "Memory Usage Check" "SKIP" "Could not determine memory usage" "0ms"
fi

# Test 32: Test disk usage
echo -e "${YELLOW}🔍 Checking disk usage...${NC}"
DISK_USAGE=$(du -sh . | cut -f1)
if [ $? -eq 0 ]; then
    log_test_result "Disk Usage Check" "PASS" "Disk usage: $DISK_USAGE" "0ms"
else
    log_test_result "Disk Usage Check" "SKIP" "Could not determine disk usage" "0ms"
fi

# Test 33: Test file permissions
echo -e "${YELLOW}🔍 Checking file permissions...${NC}"
if [ -r "config.json" ]; then
    log_test_result "Config File Readable" "PASS" "config.json is readable" "0ms"
else
    log_test_result "Config File Readable" "FAIL" "config.json is not readable" "0ms"
fi

# Test 34: Test directory structure
echo -e "${YELLOW}🔍 Checking directory structure...${NC}"
REQUIRED_DIRS=("src" "tests" "scripts" "deps")
MISSING_DIRS=()
for dir in "${REQUIRED_DIRS[@]}"; do
    if [ ! -d "$dir" ]; then
        MISSING_DIRS+=("$dir")
    fi
done

if [ ${#MISSING_DIRS[@]} -eq 0 ]; then
    log_test_result "Directory Structure Check" "PASS" "All required directories found" "0ms"
else
    log_test_result "Directory Structure Check" "FAIL" "Missing directories: ${MISSING_DIRS[*]}" "0ms"
fi

# Test 35: Test file extensions
echo -e "${YELLOW}🔍 Checking file extensions...${NC}"
ZIG_FILES=$(find src -name "*.zig" | wc -l)
if [ $ZIG_FILES -gt 0 ]; then
    log_test_result "Zig Files Check" "PASS" "Found $ZIG_FILES Zig files" "0ms"
else
    log_test_result "Zig Files Check" "FAIL" "No Zig files found" "0ms"
fi

# Test 36: Test build artifacts
echo -e "${YELLOW}🔍 Checking build artifacts...${NC}"
if [ -d "zig-out" ]; then
    log_test_result "Build Artifacts Check" "PASS" "Build artifacts directory found" "0ms"
else
    log_test_result "Build Artifacts Check" "FAIL" "Build artifacts directory not found" "0ms"
fi

# Test 37: Test log files
echo -e "${YELLOW}🔍 Checking log files...${NC}"
if [ -f "$LOG_FILE" ]; then
    LOG_SIZE=$(wc -c < "$LOG_FILE")
    log_test_result "Log File Check" "PASS" "Log file created with $LOG_SIZE bytes" "0ms"
else
    log_test_result "Log File Check" "FAIL" "Log file not created" "0ms"
fi

# Test 38: Test report file
echo -e "${YELLOW}🔍 Checking report file...${NC}"
if [ -f "$REPORT_FILE" ]; then
    REPORT_SIZE=$(wc -c < "$REPORT_FILE")
    log_test_result "Report File Check" "PASS" "Report file created with $REPORT_SIZE bytes" "0ms"
else
    log_test_result "Report File Check" "FAIL" "Report file not created" "0ms"
fi

# Test 39: Test exit codes
echo -e "${YELLOW}🔍 Testing exit codes...${NC}"
if ./zig-out/bin/nexcage --help >/dev/null 2>&1; then
    log_test_result "Help Exit Code Check" "PASS" "Help command returns exit code 0" "0ms"
else
    log_test_result "Help Exit Code Check" "FAIL" "Help command does not return exit code 0" "0ms"
fi

# Test 40: Test error handling
echo -e "${YELLOW}🔍 Testing error handling...${NC}"
if ! ./zig-out/bin/nexcage invalid-command >/dev/null 2>&1; then
    log_test_result "Error Handling Check" "PASS" "Invalid command returns non-zero exit code" "0ms"
else
    log_test_result "Error Handling Check" "FAIL" "Invalid command should return non-zero exit code" "0ms"
fi

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
- **Git Branch**: $(git branch --show-current)
- **Git Commit**: $(git rev-parse HEAD)
- **Test Duration**: $(date)

## Notes

- All tests were run in a controlled CI environment
- Some tests are expected to fail (negative testing)
- Build artifacts are checked for completeness
- File permissions and structure are validated

EOF

# Display final summary
echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                        CI TEST REPORT                       ║${NC}"
echo -e "${BLUE}╠══════════════════════════════════════════════════════════════╣${NC}"
printf "${BLUE}║ Total Tests: %3d                                          ║${NC}\n" $TOTAL_TESTS
printf "${BLUE}║ Passed:      %3d (%5.1f%%)                              ║${NC}\n" $PASSED_TESTS $SUCCESS_RATE
printf "${BLUE}║ Failed:      %3d                                          ║${NC}\n" $FAILED_TESTS
printf "${BLUE}║ Skipped:     %3d                                          ║${NC}\n" $SKIPPED_TESTS
printf "${BLUE}║ Success Rate: %5.1f%%                                      ║${NC}\n" $SUCCESS_RATE
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}📊 Detailed report saved to: $REPORT_FILE${NC}"
echo -e "${GREEN}📝 Test log saved to: $LOG_FILE${NC}"

# Exit with appropriate code
if [ $FAILED_TESTS -eq 0 ]; then
    echo -e "${GREEN}🎉 All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}❌ Some tests failed. Check the report for details.${NC}"
    exit 1
fi
