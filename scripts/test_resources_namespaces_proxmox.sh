#!/bin/bash
# Test script for OCI bundle resources and namespaces on Proxmox VE
# Server: mgr.cp.if.ua

set -e

PROXMOX_HOST="${PROXMOX_HOST:-mgr.cp.if.ua}"
BUNDLE_PATH="${BUNDLE_PATH:-/tmp/test-oci-bundle/resources-namespaces}"
CONTAINER_ID="${CONTAINER_ID:-test-resources-ns-$(date +%s)}"

echo "=== Testing Resources and Namespaces on Proxmox VE ==="
echo "Host: $PROXMOX_HOST"
echo "Bundle: $BUNDLE_PATH"
echo "Container ID: $CONTAINER_ID"
echo ""

# Check if bundle exists
if [ ! -d "$BUNDLE_PATH" ]; then
    echo "ERROR: Bundle directory not found: $BUNDLE_PATH"
    echo "Creating test bundle..."
    mkdir -p "$BUNDLE_PATH/rootfs/bin"
    cat > "$BUNDLE_PATH/config.json" << 'EOF'
{
  "ociVersion": "1.0.2",
  "process": {
    "terminal": false,
    "user": {"uid": 0, "gid": 0},
    "args": ["/bin/sh"],
    "env": ["PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"],
    "cwd": "/"
  },
  "root": {"path": "rootfs", "readonly": false},
  "hostname": "test-resources-namespaces",
  "linux": {
    "resources": {
      "memory": {"limit": 268435456},
      "cpu": {"shares": 512}
    },
    "namespaces": [
      {"type": "pid"},
      {"type": "network"},
      {"type": "ipc"},
      {"type": "uts"},
      {"type": "mount"},
      {"type": "user"}
    ]
  }
}
EOF
    echo "#!/bin/sh" > "$BUNDLE_PATH/rootfs/bin/sh"
    chmod +x "$BUNDLE_PATH/rootfs/bin/sh"
    echo "✓ Test bundle created"
fi

# Check if nexcage is available
if ! command -v nexcage &> /dev/null; then
    echo "ERROR: nexcage not found in PATH"
    echo "Please install or add to PATH"
    exit 1
fi

echo "✓ nexcage found: $(which nexcage)"
echo ""

# Step 1: Create container
echo "Step 1: Creating container with resources and namespaces..."
echo "Command: nexcage create $CONTAINER_ID $BUNDLE_PATH"
echo ""

if nexcage create "$CONTAINER_ID" "$BUNDLE_PATH" 2>&1; then
    echo "✓ Container created successfully"
else
    echo "✗ Container creation failed"
    exit 1
fi

# Get VMID (might need to parse from output or state file)
echo ""
echo "Step 2: Finding VMID..."
STATE_FILE="/var/lib/nexcage/state/${CONTAINER_ID}.json"
if [ -f "$STATE_FILE" ]; then
    VMID=$(python3 -c "import json; print(json.load(open('$STATE_FILE'))['vmid'])" 2>/dev/null || jq -r '.vmid' "$STATE_FILE" 2>/dev/null || grep -o '"vmid"[[:space:]]*:[[:space:]]*[0-9]*' "$STATE_FILE" | grep -o '[0-9]*' | head -1)
    echo "VMID: $VMID"
else
    echo "WARNING: State file not found, trying to find VMID from pct list..."
    VMID=$(pct list | grep "$CONTAINER_ID" | awk '{print $1}' | head -1 || echo "")
fi

if [ -z "$VMID" ]; then
    echo "ERROR: Could not determine VMID"
    exit 1
fi

echo "✓ VMID found: $VMID"
echo ""

# Step 3: Verify resources
echo "Step 3: Verifying resource limits..."
echo "Checking memory and CPU configuration..."
echo ""

pct config "$VMID" | grep -E "memory|cores|swap" || echo "No resource limits found in config"

MEMORY_CONFIG=$(pct config "$VMID" | grep "^memory:" | awk '{print $2}' || echo "")
CORES_CONFIG=$(pct config "$VMID" | grep "^cores:" | awk '{print $2}' || echo "")

echo ""
if [ ! -z "$MEMORY_CONFIG" ]; then
    echo "Memory limit: ${MEMORY_CONFIG} MB (expected: 256 MB)"
    if [ "$MEMORY_CONFIG" = "256" ]; then
        echo "✓ Memory limit matches bundle config"
    else
        echo "⚠ Memory limit differs from bundle config"
    fi
else
    echo "⚠ Memory limit not found in config"
fi

if [ ! -z "$CORES_CONFIG" ]; then
    echo "CPU cores: ${CORES_CONFIG} (expected: 1, from 512 shares / 1024)"
    if [ "$CORES_CONFIG" = "1" ]; then
        echo "✓ CPU cores match expected value"
    else
        echo "⚠ CPU cores differ from expected value"
    fi
else
    echo "⚠ CPU cores not found in config"
fi

echo ""

# Step 4: Verify namespaces/features
echo "Step 4: Verifying namespaces (LXC features)..."
echo "Checking features configuration..."
echo ""

FEATURES_CONFIG=$(pct config "$VMID" | grep "^features:" | cut -d: -f2- | xargs || echo "")

if [ ! -z "$FEATURES_CONFIG" ]; then
    echo "Features: $FEATURES_CONFIG"
    echo "Expected: nesting=1,keyctl=1 (due to user namespace)"
    echo ""
    
    if echo "$FEATURES_CONFIG" | grep -q "nesting=1"; then
        echo "✓ nesting=1 feature found"
    else
        echo "⚠ nesting=1 feature NOT found"
    fi
    
    if echo "$FEATURES_CONFIG" | grep -q "keyctl=1"; then
        echo "✓ keyctl=1 feature found"
    else
        echo "⚠ keyctl=1 feature NOT found"
    fi
else
    echo "⚠ Features not found in config (may use defaults)"
fi

echo ""

# Step 5: Show full config
echo "Step 5: Full container configuration:"
echo "---"
pct config "$VMID" | head -20
echo "---"
echo ""

# Step 6: Summary
echo "=== Test Summary ==="
echo "Container ID: $CONTAINER_ID"
echo "VMID: $VMID"
echo "Memory: ${MEMORY_CONFIG:-not set} MB"
echo "CPU Cores: ${CORES_CONFIG:-not set}"
echo "Features: ${FEATURES_CONFIG:-defaults}"
echo ""
echo "To inspect container: pct config $VMID"
echo "To destroy container: nexcage delete $CONTAINER_ID"
echo ""

