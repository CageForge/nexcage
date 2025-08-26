#!/bin/bash

# Universal Dependency Update Script
# Automatically checks and updates all dependencies in build.zig.zon
# Usage: ./scripts/update_dependencies.sh [--force] [--check-only] [--dependency DEP_NAME]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Configuration
BUILD_FILE="build.zig.zon"
TEMP_DIR="/tmp/deps_update"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Flags
FORCE_UPDATE=false
CHECK_ONLY=false
VERBOSE=false
SPECIFIC_DEPENDENCY=""

# Dependency configurations
declare -A DEPENDENCIES
DEPENDENCIES["crun"]="containers/crun|https://api.github.com/repos/containers/crun/releases/latest|tag_name"
DEPENDENCIES["zig-json"]="berdon/zig-json|https://api.github.com/repos/berdon/zig-json/commits/master|sha"

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
Universal Dependency Update Script

Usage: $0 [OPTIONS]

Options:
    --force              Force update even if compatibility issues are detected
    --check-only         Only check for new versions, don't update
    --verbose            Enable verbose output
    --dependency NAME    Update only specific dependency (e.g., crun, zig-json)
    -h, --help          Show this help message

Examples:
    $0                           # Check and update all dependencies
    $0 --check-only             # Only check for new versions
    $0 --dependency crun        # Update only crun dependency
    $0 --force                  # Force update (may break build)
    $0 --verbose                # Verbose output

Available dependencies:
    - crun: Container runtime
    - zig-json: JSON parsing library

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE_UPDATE=true
            shift
            ;;
        --check-only)
            CHECK_ONLY=true
            shift
            ;;
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

# Get latest version from GitHub
get_latest_version() {
    local dep_name=$1
    local config="${DEPENDENCIES[$dep_name]}"
    
    if [[ -z "$config" ]]; then
        log_error "Unknown dependency: $dep_name"
        return 1
    fi
    
    IFS='|' read -r repo api_url field <<< "$config"
    
    if [[ "$dep_name" == "crun" ]]; then
        local latest_version=$(curl -s "$api_url" | grep "\"$field\"" | sed 's/.*"tag_name": "\([^"]*\)".*/\1/')
        echo "$latest_version"
    elif [[ "$dep_name" == "zig-json" ]]; then
        local latest_sha=$(curl -s "$api_url" | grep "\"$field\"" | sed 's/.*"sha": "\([^"]*\)".*/\1/' | head -c 7)
        echo "$latest_sha"
    fi
}

# Check if crun version is compatible with Zig
check_crun_compatibility() {
    local version=$1
    local url="https://github.com/containers/crun/releases/download/$version/crun-$version.tar.gz"
    
    log_info "Checking Zig compatibility for crun $version..."
    
    # Create temp directory
    mkdir -p "$TEMP_DIR"
    cd "$TEMP_DIR"
    
    # Download and test
    if curl -L -o "crun-$version.tar.gz" "$url" 2>/dev/null; then
        # Try to extract with Zig
        if zig fetch "$url" 2>&1 | grep -q "unable to unpack tarball"; then
            log_warning "crun $version has Zig compatibility issues"
            return 1
        else
            log_success "crun $version is compatible with Zig"
            return 0
        fi
    else
        log_error "Failed to download crun $version"
        return 1
    fi
}

# Update build.zig.zon with new version
update_build_file() {
    local dep_name=$1
    local new_version=$2
    
    log_info "Updating build.zig.zon for $dep_name to $new_version..."
    
    if [[ "$dep_name" == "crun" ]]; then
        local new_url="https://github.com/containers/crun/releases/download/$new_version/crun-$new_version.tar.gz"
        
        # Get new hash
        local temp_file="/tmp/crun_$new_version.tar.gz"
        if curl -L -o "$temp_file" "$new_url" 2>/dev/null; then
            local new_hash=$(sha256sum "$temp_file" | cut -d' ' -f1)
            rm "$temp_file"
            
            # Update the file
            sed -i "s|https://github.com/containers/crun/releases/download/[^/]*/crun-[^/]*\.tar\.gz|$new_url|g" "$BUILD_FILE"
            sed -i "s|\.hash = \"[a-f0-9]*\"|\.hash = \"$new_hash\"|g" "$BUILD_FILE"
            
            log_success "Updated build.zig.zon for crun to $new_version"
            return 0
        else
            log_error "Failed to download crun $new_version for hash calculation"
            return 1
        fi
    elif [[ "$dep_name" == "zig-json" ]]; then
        local new_url="https://github.com/berdon/zig-json/archive/refs/heads/master.tar.gz"
        
        # Get new hash
        local temp_file="/tmp/zig-json_master.tar.gz"
        if curl -L -o "$temp_file" "$new_url" 2>/dev/null; then
            local new_hash=$(sha256sum "$temp_file" | cut -d' ' -f1)
            rm "$temp_file"
            
            # Update the file
            sed -i "s|\.hash = \"[a-f0-9]*\"|\.hash = \"$new_hash\"|g" "$BUILD_FILE"
            
            log_success "Updated build.zig.zon for zig-json to $new_version"
            return 0
        else
            log_error "Failed to download zig-json for hash calculation"
            return 1
        fi
    fi
}

# Test build after update
test_build() {
    log_info "Testing build after update..."
    
    if zig build --summary all > /dev/null 2>&1; then
        log_success "Build successful after update"
        return 0
    else
        log_error "Build failed after update"
        return 1
    fi
}

# Update specific dependency
update_dependency() {
    local dep_name=$1
    
    log_info "Processing dependency: $dep_name"
    
    # Get current and latest versions
    local current_version=$(get_current_version "$dep_name")
    local latest_version=$(get_latest_version "$dep_name")
    
    if [[ -z "$current_version" || -z "$latest_version" ]]; then
        log_error "Failed to get version information for $dep_name"
        return 1
    fi
    
    log_info "Current $dep_name version: $current_version"
    log_info "Latest $dep_name version: $latest_version"
    
    if [[ "$current_version" == "$latest_version" ]]; then
        log_success "Already using the latest $dep_name version: $latest_version"
        return 0
    fi
    
    if [[ "$CHECK_ONLY" == true ]]; then
        log_info "Check-only mode: Found newer $dep_name version $latest_version"
        return 0
    fi
    
    # Check compatibility for crun
    if [[ "$dep_name" == "crun" && "$FORCE_UPDATE" == false ]]; then
        if ! check_crun_compatibility "$latest_version"; then
            log_warning "$dep_name $latest_version has compatibility issues with Zig"
            log_warning "Current version $current_version will be kept"
            log_warning "Use --force to override this check"
            return 0
        fi
    fi
    
    # Create backup if not exists
    if [[ ! -f "$BUILD_FILE.backup" ]]; then
        cp "$BUILD_FILE" "$BUILD_FILE.backup"
        log_info "Created backup: $BUILD_FILE.backup"
    fi
    
    # Update the file
    if update_build_file "$dep_name" "$latest_version"; then
        # Test the build
        if test_build; then
            log_success "Successfully updated $dep_name to $latest_version"
        else
            log_error "Build failed after update, restoring backup..."
            cp "$BUILD_FILE.backup" "$BUILD_FILE"
            return 1
        fi
    else
        log_error "Failed to update build.zig.zon for $dep_name"
        return 1
    fi
}

# Main execution
main() {
    log_info "Starting dependency update process..."
    
    # Create temp directory
    mkdir -p "$TEMP_DIR"
    
    if [[ -n "$SPECIFIC_DEPENDENCY" ]]; then
        # Update specific dependency
        if [[ -n "${DEPENDENCIES[$SPECIFIC_DEPENDENCY]}" ]]; then
            update_dependency "$SPECIFIC_DEPENDENCY"
        else
            log_error "Unknown dependency: $SPECIFIC_DEPENDENCY"
            log_info "Available dependencies: ${!DEPENDENCIES[*]}"
            exit 1
        fi
    else
        # Update all dependencies
        for dep in "${!DEPENDENCIES[@]}"; do
            log_info "=== Processing $dep ==="
            update_dependency "$dep"
            echo
        done
    fi
    
    log_success "Dependency update process completed"
    
    if [[ -f "$BUILD_FILE.backup" ]]; then
        log_info "Backup available at: $BUILD_FILE.backup"
    fi
}

# Cleanup function
cleanup() {
    if [[ -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
    fi
}

# Set trap for cleanup
trap cleanup EXIT

# Run main function
main "$@"
