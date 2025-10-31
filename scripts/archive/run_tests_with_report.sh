#!/bin/bash

set -euo pipefail

# Configuration
REPORT_DIR="./test-reports"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
REPORT_FILE="$REPORT_DIR/unit_test_report_$TIMESTAMP.md"
LOG_FILE="$REPORT_DIR/unit_test_log_$TIMESTAMP.log"

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
# Unit Test Report - $(date)

## Test Configuration
- **Timestamp**: $(date)
- **Report File**: $REPORT_FILE
- **Log File**: $LOG_FILE
- **Zig Version**: $(zig version)
- **OS**: $(uname -s)
- **Architecture**: $(uname -m)

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

echo -e "${BLUE}🚀 Starting Unit Test Suite with Detailed Reporting${NC}"
echo "Report will be saved to: $REPORT_FILE"
echo "Log will be saved to: $LOG_FILE"
echo ""

# Test 1: Build project
echo -e "${YELLOW}📦 Building project...${NC}"
if zig build; then
    log_test_result "Build Project" "PASS" "Project built successfully" "0ms"
else
    log_test_result "Build Project" "FAIL" "Failed to build project" "0ms"
    echo -e "${RED}❌ Build failed, cannot continue with tests${NC}"
    exit 1
fi

# Test 2: Run unit tests
run_test "Unit Tests" "zig build test"

# Test 3: Run test runner
run_test "Test Runner" "zig run tests/test_runner.zig"

# Test 4: Run comprehensive tests
run_test "Comprehensive Tests" "zig run tests/comprehensive_test.zig"

# Test 5: Run config tests
run_test "Config Tests" "zig run tests/config_test.zig"

# Test 6: Run memory tests
run_test "Memory Tests" "zig run tests/memory/memory_leak_test.zig"

# Test 7: Run performance tests
run_test "Performance Tests" "zig run tests/performance/optimized_performance_test.zig"

# Test 8: Run security tests
run_test "Security Tests" "zig run tests/security/test_security.zig"

# Test 9: Run OCI tests
run_test "OCI Tests" "zig run tests/oci/mod.zig"

# Test 10: Run integration tests
run_test "Integration Tests" "zig run tests/integration/end_to_end_test.zig"

# Test 11: Run LXC tests
run_test "LXC Tests" "zig run tests/lxc/container_test.zig"

# Test 12: Run Proxmox tests
run_test "Proxmox Tests" "zig run tests/proxmox/client_test.zig"

# Test 13: Run network tests
run_test "Network Tests" "zig run tests/test_network.zig"

# Test 14: Run container tests
run_test "Container Tests" "zig run tests/test_container.zig"

# Test 15: Run template tests
run_test "Template Tests" "zig run tests/template_operations_test.zig"

# Test 16: Run edge case tests
run_test "Edge Case Tests" "zig run tests/edge_cases_test.zig"

# Test 17: Run property-based tests
run_test "Property-Based Tests" "zig run tests/property_based_tests.zig"

# Test 18: Run pod tests
run_test "Pod Tests" "zig run tests/pod/pod_test.zig"

# Test 19: Run pause tests
run_test "Pause Tests" "zig run tests/pause/pause_test.zig"

# Test 20: Run CRI tests
run_test "CRI Tests" "zig run tests/cri/runtime/service_test.zig"

# Test 21: Run crun integration tests
run_test "Crun Integration Tests" "zig run tests/crun_integration_test.zig"

# Test 22: Run simple comprehensive tests
run_test "Simple Comprehensive Tests" "zig run tests/simple_comprehensive_test.zig"

# Test 23: Run performance simple tests
run_test "Performance Simple Tests" "zig run tests/performance_simple_test.zig"

# Test 24: Run layerfs performance tests
run_test "LayerFS Performance Tests" "zig run tests/performance/layerfs_performance_test.zig"

# Test 25: Run concurrency tests
run_test "Concurrency Tests" "zig run tests/integration/test_concurrency.zig"

# Test 26: Run create template integration tests
run_test "Create Template Integration Tests" "zig run tests/integration/create_template_integration_test.zig"

# Test 27: Run container lifecycle tests
run_test "Container Lifecycle Tests" "zig run tests/integration/container_lifecycle_test.zig"

# Test 28: Run create with pull tests
run_test "Create With Pull Tests" "zig run tests/integration/test_create_with_pull.zig"

# Test 29: Run OCI image tests
run_test "OCI Image Tests" "zig run tests/oci/image/manager_test.zig"

# Test 30: Run OCI spec tests
run_test "OCI Spec Tests" "zig run tests/test_oci_spec.zig"

# Test 31: Run OCI bundle tests
run_test "OCI Bundle Tests" "zig run tests/oci/bundle_simple_test.zig"

# Test 32: Run OCI CLI tests
run_test "OCI CLI Tests" "zig run tests/oci/cli_simple_test.zig"

# Test 33: Run OCI container creator tests
run_test "OCI Container Creator Tests" "zig run tests/oci/container_creator_simple_test.zig"

# Test 34: Run OCI crun simple tests
run_test "OCI Crun Simple Tests" "zig run tests/oci/crun_simple_test.zig"

# Test 35: Run OCI image manager tests
run_test "OCI Image Manager Tests" "zig run tests/oci/image_manager_test.zig"

# Test 36: Run OCI runtime types tests
run_test "OCI Runtime Types Tests" "zig run tests/oci/runtime_types_test.zig"

# Test 37: Run OCI state tests
run_test "OCI State Tests" "zig run tests/oci/state_test.zig"

# Test 38: Run OCI validator tests
run_test "OCI Validator Tests" "zig run tests/oci/validator_simple_test.zig"

# Test 39: Run OCI spec tests
run_test "OCI Spec Tests" "zig run tests/oci/spec_test.zig"

# Test 40: Run OCI image config tests
run_test "OCI Image Config Tests" "zig run tests/oci/image/config_test.zig"

# Test 41: Run OCI image layer tests
run_test "OCI Image Layer Tests" "zig run tests/oci/image/layer_test.zig"

# Test 42: Run OCI image layerfs tests
run_test "OCI Image LayerFS Tests" "zig run tests/oci/image/layerfs_test.zig"

# Test 43: Run OCI image manifest tests
run_test "OCI Image Manifest Tests" "zig run tests/oci/image/manifest_test.zig"

# Test 44: Run OCI runtime types simple tests
run_test "OCI Runtime Types Simple Tests" "zig run tests/oci/runtime_types_simple_test.zig"

# Test 45: Run OCI container creator simple tests
run_test "OCI Container Creator Simple Tests" "zig run tests/oci/container_creator_simple_test.zig"

# Test 46: Run OCI CLI simple tests
run_test "OCI CLI Simple Tests" "zig run tests/oci/cli_simple_test.zig"

# Test 47: Run OCI bundle simple tests
run_test "OCI Bundle Simple Tests" "zig run tests/oci/bundle_simple_test.zig"

# Test 48: Run OCI crun simple tests
run_test "OCI Crun Simple Tests" "zig run tests/oci/crun_simple_test.zig"

# Test 49: Run OCI validator simple tests
run_test "OCI Validator Simple Tests" "zig run tests/oci/validator_simple_test.zig"

# Test 50: Run OCI runtime types simple tests
run_test "OCI Runtime Types Simple Tests" "zig run tests/oci/runtime_types_simple_test.zig"

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
- **Test Duration**: $(date)

## Notes

- All tests were run in a controlled environment
- Some tests may be skipped if dependencies are missing
- Performance tests may take longer to complete
- Memory tests check for leaks and proper cleanup

EOF

# Display final summary
echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                      UNIT TEST REPORT                       ║${NC}"
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
