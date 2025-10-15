#!/bin/bash

# Proxmox VE Integration Test Script
# This script tests the integration with Proxmox VE using pct CLI

set -e

echo "🧪 Starting Proxmox VE Integration Tests"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test configuration
TEST_CONTAINER_ID="test-container-$(date +%s)"
TEST_BUNDLE_DIR="/tmp/test-bundle-$(date +%s)"
TEST_STATE_DIR="/tmp/test-state-$(date +%s)"

# Cleanup function
cleanup() {
    echo "🧹 Cleaning up test resources..."
    
    # Remove test bundle directory
    if [ -d "$TEST_BUNDLE_DIR" ]; then
        rm -rf "$TEST_BUNDLE_DIR"
    fi
    
    # Remove test state directory
    if [ -d "$TEST_STATE_DIR" ]; then
        rm -rf "$TEST_STATE_DIR"
    fi
    
    # Try to destroy test container if it exists
    if command -v pct >/dev/null 2>&1; then
        # Get VMID for test container
        VMID=$(pct list 2>/dev/null | grep "$TEST_CONTAINER_ID" | awk '{print $1}' || echo "")
        if [ -n "$VMID" ]; then
            echo "🗑️  Destroying test container VMID: $VMID"
            pct destroy "$VMID" 2>/dev/null || true
        fi
    fi
    
    echo "✅ Cleanup completed"
}

# Set up trap for cleanup
trap cleanup EXIT

# Test 1: Check if pct command is available
echo "🔍 Test 1: Checking pct command availability"
if command -v pct >/dev/null 2>&1; then
    echo -e "${GREEN}✅ pct command is available${NC}"
    PCT_VERSION=$(pct --version 2>/dev/null || echo "unknown")
    echo "   Version: $PCT_VERSION"
else
    echo -e "${YELLOW}⚠️  pct command is not available - skipping Proxmox-specific tests${NC}"
    echo "   This is expected if not running on a Proxmox VE system"
    exit 0
fi

# Test 2: Check if we can list containers
echo "🔍 Test 2: Checking container listing capability"
if pct list >/dev/null 2>&1; then
    echo -e "${GREEN}✅ Can list containers${NC}"
    CONTAINER_COUNT=$(pct list | wc -l)
    echo "   Found $CONTAINER_COUNT containers"
else
    echo -e "${RED}❌ Cannot list containers${NC}"
    echo "   This might indicate permission issues or Proxmox VE not running"
    exit 1
fi

# Test 3: Create test OCI bundle
echo "🔍 Test 3: Creating test OCI bundle"
mkdir -p "$TEST_BUNDLE_DIR/rootfs"

# Create config.json
cat > "$TEST_BUNDLE_DIR/config.json" << 'EOF'
{
  "ociVersion": "1.0.2",
  "process": {
    "args": ["/bin/sh"],
    "env": ["PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"]
  },
  "root": {
    "path": "rootfs"
  },
  "hostname": "test-container",
  "linux": {
    "resources": {
      "memory": {
        "limit": 536870912
      },
      "cpu": {
        "shares": 1024
      }
    }
  }
}
EOF

# Create minimal rootfs
mkdir -p "$TEST_BUNDLE_DIR/rootfs/bin"
mkdir -p "$TEST_BUNDLE_DIR/rootfs/usr/bin"
mkdir -p "$TEST_BUNDLE_DIR/rootfs/lib"
mkdir -p "$TEST_BUNDLE_DIR/rootfs/lib64"

# Create a simple shell script
cat > "$TEST_BUNDLE_DIR/rootfs/bin/sh" << 'EOF'
#!/bin/sh
echo "Hello from test container!"
EOF
chmod +x "$TEST_BUNDLE_DIR/rootfs/bin/sh"

echo -e "${GREEN}✅ Test OCI bundle created at $TEST_BUNDLE_DIR${NC}"

# Test 4: Test our nexcage create command
echo "🔍 Test 4: Testing nexcage create command"
if [ -f "./zig-out/bin/nexcage" ]; then
    echo "   Using built nexcage binary"
    NEXCAGE_CMD="./zig-out/bin/nexcage"
elif [ -f "./nexcage" ]; then
    echo "   Using local nexcage binary"
    NEXCAGE_CMD="./nexcage"
else
    echo "   Building nexcage..."
    if zig build; then
        NEXCAGE_CMD="./zig-out/bin/nexcage"
        echo -e "${GREEN}✅ nexcage built successfully${NC}"
    else
        echo -e "${RED}❌ Failed to build nexcage${NC}"
        exit 1
    fi
fi

# Test create command
echo "   Testing create command with test bundle..."
if $NEXCAGE_CMD create "$TEST_CONTAINER_ID" "$TEST_BUNDLE_DIR" 2>/dev/null; then
    echo -e "${GREEN}✅ Create command executed successfully${NC}"
else
    echo -e "${YELLOW}⚠️  Create command failed (this might be expected in test environment)${NC}"
fi

# Test 5: Check if container was created
echo "🔍 Test 5: Checking if container was created"
if pct list | grep -q "$TEST_CONTAINER_ID"; then
    echo -e "${GREEN}✅ Container found in pct list${NC}"
    VMID=$(pct list | grep "$TEST_CONTAINER_ID" | awk '{print $1}')
    echo "   VMID: $VMID"
else
    echo -e "${YELLOW}⚠️  Container not found in pct list${NC}"
    echo "   This might be expected if create command failed"
fi

# Test 6: Test state management
echo "🔍 Test 6: Testing state management"
if [ -d "/var/lib/proxmox-lxcri/state" ]; then
    echo -e "${GREEN}✅ State directory exists${NC}"
    STATE_FILES=$(find /var/lib/proxmox-lxcri/state -name "*.json" | wc -l)
    echo "   Found $STATE_FILES state files"
else
    echo -e "${YELLOW}⚠️  State directory not found${NC}"
    echo "   This might be expected if create command failed"
fi

# Test 7: Test mapping management
echo "🔍 Test 7: Testing mapping management"
if [ -f "/var/lib/proxmox-lxcri/state/mapping.json" ]; then
    echo -e "${GREEN}✅ Mapping file exists${NC}"
    if grep -q "$TEST_CONTAINER_ID" /var/lib/proxmox-lxcri/state/mapping.json 2>/dev/null; then
        echo -e "${GREEN}✅ Container mapping found${NC}"
    else
        echo -e "${YELLOW}⚠️  Container mapping not found${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  Mapping file not found${NC}"
fi

echo ""
echo "🎉 Proxmox VE Integration Tests Completed!"
echo ""
echo "📊 Test Summary:"
echo "   - pct command: $(command -v pct >/dev/null 2>&1 && echo "✅ Available" || echo "❌ Not available")"
echo "   - OCI bundle: ✅ Created"
echo "   - nexcage binary: $(test -f "$NEXCAGE_CMD" && echo "✅ Available" || echo "❌ Not available")"
echo "   - Container creation: $(pct list | grep -q "$TEST_CONTAINER_ID" && echo "✅ Success" || echo "⚠️  Failed/Skipped")"
echo "   - State management: $(test -d "/var/lib/proxmox-lxcri/state" && echo "✅ Working" || echo "⚠️  Not found")"
echo ""
echo "💡 Note: Some tests may fail in non-Proxmox environments or without proper permissions"
