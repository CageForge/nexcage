#!/bin/bash

# crun Dependency Update Script
# Automatically checks for new crun versions and updates build.zig.zon
# Usage: ./scripts/update_crun.sh [--force] [--check-only]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
CRUN_REPO="containers/crun"
BUILD_FILE="build.zig.zon"
TEMP_DIR="/tmp/crun_update"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Flags
FORCE_UPDATE=false
CHECK_ONLY=false
VERBOSE=false

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

show_help() {
    cat << EOF
crun Dependency Update Script

Usage: $0 [OPTIONS]

Options:
    --force          Force update even if compatibility issues are detected
    --check-only     Only check for new versions, don't update
    --verbose        Enable verbose output
    -h, --help      Show this help message

Examples:
    $0                    # Check and update if compatible
    $0 --check-only      # Only check for new versions
    $0 --force           # Force update (may break build)
    $0 --verbose         # Verbose output

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

# Get current crun version from build.zig.zon
get_current_version() {
    local current_url=$(grep -A 2 '\.crun = \.' "$BUILD_FILE" | grep '\.url' | sed 's/.*crun-\([0-9.]*\)\.tar\.gz.*/\1/')
    echo "$current_url"
}

# Get latest crun version from GitHub
get_latest_version() {
    local latest_version=$(curl -s "https://api.github.com/repos/$CRUN_REPO/releases/latest" | grep '"tag_name"' | sed 's/.*"tag_name": "\([^"]*\)".*/\1/')
    echo "$latest_version"
}

# Check if version is compatible with Zig
check_zig_compatibility() {
    local version=$1
    local url="https://github.com/$CRUN_REPO/releases/download/$version/crun-$version.tar.gz"
    
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
    local new_version=$1
    local new_url="https://github.com/$CRUN_REPO/releases/download/$new_version/crun-$new_version.tar.gz"
    
    log_info "Updating build.zig.zon to crun $new_version..."
    
    # Get new hash
    local temp_file="/tmp/crun_$new_version.tar.gz"
    if curl -L -o "$temp_file" "$new_url" 2>/dev/null; then
        local new_hash=$(sha256sum "$temp_file" | cut -d' ' -f1)
        rm "$temp_file"
        
        # Update the file
        sed -i "s|https://github.com/$CRUN_REPO/releases/download/[^/]*/crun-[^/]*\.tar\.gz|$new_url|g" "$BUILD_FILE"
        sed -i "s|\.hash = \"[a-f0-9]*\"|\.hash = \"$new_hash\"|g" "$BUILD_FILE"
        
        log_success "Updated build.zig.zon to crun $new_version"
        return 0
    else
        log_error "Failed to download crun $new_version for hash calculation"
        return 1
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

# Main execution
main() {
    log_info "Starting crun dependency update process..."
    
    # Get current and latest versions
    local current_version=$(get_current_version)
    local latest_version=$(get_latest_version)
    
    log_info "Current crun version: $current_version"
    log_info "Latest crun version: $latest_version"
    
    if [[ "$current_version" == "$latest_version" ]]; then
        log_success "Already using the latest crun version: $latest_version"
        exit 0
    fi
    
    if [[ "$CHECK_ONLY" == true ]]; then
        log_info "Check-only mode: Found newer version $latest_version"
        log_info "Run without --check-only to update"
        exit 0
    fi
    
    # Check compatibility
    if [[ "$FORCE_UPDATE" == false ]]; then
        if ! check_zig_compatibility "$latest_version"; then
            log_warning "crun $latest_version has compatibility issues with Zig"
            log_warning "Current version $current_version will be kept"
            log_warning "Use --force to override this check"
            exit 0
        fi
    else
        log_warning "Force update enabled - skipping compatibility check"
    fi
    
    # Create backup
    cp "$BUILD_FILE" "$BUILD_FILE.backup"
    log_info "Created backup: $BUILD_FILE.backup"
    
    # Update the file
    if update_build_file "$latest_version"; then
        # Test the build
        if test_build; then
            log_success "Successfully updated to crun $latest_version"
            log_info "Backup available at: $BUILD_FILE.backup"
        else
            log_error "Build failed after update, restoring backup..."
            cp "$BUILD_FILE.backup" "$BUILD_FILE"
            exit 1
        fi
    else
        log_error "Failed to update build.zig.zon"
        exit 1
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
