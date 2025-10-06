#!/bin/bash

# Dependency Status Check Script
# Shows current versions and checks for updates
# Usage: ./scripts/check_dependencies.sh [--verbose] [--dependency DEP_NAME]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
BUILD_FILE="build.zig.zon"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Flags
VERBOSE=false
SPECIFIC_DEPENDENCY=""

# Dependency configurations
declare -A DEPENDENCIES
DEPENDENCIES["crun"]="containers/crun|https://api.github.com/repos/containers/crun/releases/latest|tag_name|Container Runtime"
DEPENDENCIES["zig-json"]="berdon/zig-json|https://api.github.com/repos/berdon/zig-json/commits/master|sha|JSON Parsing Library"

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_debug() {
    if [[ "$VERBOSE" == true ]]; then
        echo -e "${PURPLE}[DEBUG]${NC} $1"
    fi
}

show_help() {
    cat << EOF
Dependency Status Check Script

Usage: $0 [OPTIONS]

Options:
    --verbose            Enable verbose output
    --dependency NAME   Check only specific dependency (e.g., crun, zig-json)
    -h, --help          Show this help message

Examples:
    $0                           # Check all dependencies
    $0 --dependency crun        # Check only crun dependency
    $0 --verbose                # Verbose output

Available dependencies:
    - crun: Container runtime
    - zig-json: JSON parsing library

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --verbose)
            VERBOSE=true
            shift
            ;;
        --dependency)
            SPECIFIC_DEPENDENCY="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Check if we're in the project root
if [[ ! -f "$BUILD_FILE" ]]; then
    log_error "build.zig.zon not found. Please run this script from the project root."
    exit 1
fi

# Get current dependency version from build.zig.zon
get_current_version() {
    local dep_name=$1
    local current_url=""
    
    if [[ "$dep_name" == "zig-json" ]]; then
        # For zig-json, get the URL from the dependencies section
        current_url=$(grep -A 5 "\.dependencies = \." "$BUILD_FILE" | grep -A 3 "\.@\"zig-json\"" | grep '\.url' | sed 's/.*"\([^"]*\)".*/\1/')
    else
        # For other dependencies, use the standard approach
        current_url=$(grep -A 3 "\.$dep_name = \." "$BUILD_FILE" | grep '\.url' | sed 's/.*"\([^"]*\)".*/\1/')
    fi
    
    echo "$current_url"
}

# Get current hash from build.zig.zon
get_current_hash() {
    local dep_name=$1
    local current_hash=""
    
    if [[ "$dep_name" == "zig-json" ]]; then
        # For zig-json, get the hash from the dependencies section
        current_hash=$(grep -A 5 "\.dependencies = \." "$BUILD_FILE" | grep -A 3 "\.@\"zig-json\"" | grep '\.hash' | sed 's/.*"\([^"]*\)".*/\1/')
    else
        # For other dependencies, use the standard approach
        current_hash=$(grep -A 3 "\.$dep_name = \." "$BUILD_FILE" | grep '\.hash' | sed 's/.*"\([^"]*\)".*/\1/')
    fi
    
    echo "$current_hash"
}

# Get latest version from GitHub
get_latest_version() {
    local dep_name=$1
    local config="${DEPENDENCIES[$dep_name]}"
    
    if [[ -z "$config" ]]; then
        log_error "Unknown dependency: $dep_name"
        return 1
    fi
    
    IFS='|' read -r repo api_url field description <<< "$config"
    
    if [[ "$dep_name" == "crun" ]]; then
        local latest_version=$(curl -s "$api_url" | grep "\"$field\"" | sed 's/.*"tag_name": "\([^"]*\)".*/\1/')
        echo "$latest_version"
    elif [[ "$dep_name" == "zig-json" ]]; then
        local latest_sha=$(curl -s "$api_url" | grep "\"$field\"" | sed 's/.*"sha": "\([^"]*\)".*/\1/' | head -c 7)
        echo "$latest_sha"
    fi
}

# Get dependency description
get_dependency_description() {
    local dep_name=$1
    local config="${DEPENDENCIES[$dep_name]}"
    IFS='|' read -r repo api_url field description <<< "$config"
    echo "$description"
}

# Check if version is up to date
is_up_to_date() {
    local current=$1
    local latest=$2
    local dep_name=$3
    
    if [[ "$dep_name" == "crun" ]]; then
        [[ "$current" == "$latest" ]]
    elif [[ "$dep_name" == "zig-json" ]]; then
        # For zig-json, check if current hash starts with latest sha
        [[ "$current" == *"$latest"* ]]
    fi
}

# Check dependency status
check_dependency_status() {
    local dep_name=$1
    
    log_info "=== Checking $dep_name ==="
    
    # Get current and latest versions
    local current_version=$(get_current_version "$dep_name")
    local current_hash=$(get_current_hash "$dep_name")
    local latest_version=$(get_latest_version "$dep_name")
    local description=$(get_dependency_description "$dep_name")
    
    if [[ -z "$current_version" || -z "$latest_version" ]]; then
        log_error "Failed to get version information for $dep_name"
        return 1
    fi
    
    # Display information
    echo -e "${CYAN}Description:${NC} $description"
    echo -e "${CYAN}Current URL:${NC} $current_version"
    echo -e "${CYAN}Current Hash:${NC} $current_hash"
    echo -e "${CYAN}Latest Version:${NC} $latest_version"
    
    # Check if up to date
    if is_up_to_date "$current_version" "$latest_version" "$dep_name"; then
        echo -e "${GREEN}Status: UP TO DATE${NC}"
        log_success "$dep_name is using the latest version"
    else
        echo -e "${YELLOW}Status: UPDATE AVAILABLE${NC}"
        log_warning "$dep_name has a newer version available"
        
        if [[ "$VERBOSE" == true ]]; then
            echo -e "${CYAN}Update Command:${NC} ./scripts/update_dependencies.sh --dependency $dep_name"
        fi
    fi
    
    echo
}

# Check build file syntax
check_build_file() {
    log_info "Checking build.zig.zon syntax..."
    
    # Try to find Zig in common locations
    local zig_path=""
    if command -v zig > /dev/null 2>&1; then
        zig_path="zig"
    elif [[ -f "./zig-linux-x86_64-0.15.1/zig" ]]; then
        zig_path="./zig-linux-x86_64-0.15.1/zig"
    else
        log_error "Zig not found. Please ensure Zig is installed or in the project directory."
        return 1
    fi
    
    if $zig_path build --help > /dev/null 2>&1; then
        log_success "Zig is accessible and build.zig.zon syntax is valid"
    else
        log_error "Zig is not accessible or build.zig.zon has syntax errors"
        return 1
    fi
}

# Check if dependencies are accessible
check_dependency_accessibility() {
    log_info "Checking dependency accessibility..."
    
    for dep in "${!DEPENDENCIES[@]}"; do
        local config="${DEPENDENCIES[$dep]}"
        IFS='|' read -r repo api_url field description <<< "$config"
        
        if curl -s "$api_url" > /dev/null 2>&1; then
            log_debug "$dep API endpoint is accessible"
        else
            log_warning "$dep API endpoint is not accessible"
        fi
    done
}

# Main execution
main() {
    log_info "Starting dependency status check..."
    
    # Check build file syntax
    check_build_file
    echo
    
    # Check dependency accessibility
    check_dependency_accessibility
    echo
    
    if [[ -n "$SPECIFIC_DEPENDENCY" ]]; then
        # Check specific dependency
        if [[ -n "${DEPENDENCIES[$SPECIFIC_DEPENDENCY]}" ]]; then
            check_dependency_status "$SPECIFIC_DEPENDENCY"
        else
            log_error "Unknown dependency: $SPECIFIC_DEPENDENCY"
            log_info "Available dependencies: ${!DEPENDENCIES[*]}"
            exit 1
        fi
    else
        # Check all dependencies
        for dep in "${!DEPENDENCIES[@]}"; do
            check_dependency_status "$dep"
        done
    fi
    
    log_success "Dependency status check completed"
    
    # Summary
    echo -e "${CYAN}=== Summary ===${NC}"
    echo -e "To update dependencies, use: ${GREEN}./scripts/update_dependencies.sh${NC}"
    echo -e "To check specific dependency: ${GREEN}./scripts/check_dependencies.sh --dependency DEP_NAME${NC}"
    echo -e "For verbose output: ${GREEN}./scripts/check_dependencies.sh --verbose${NC}"
}

# Run main function
main "$@"
