#!/bin/bash
# Prepare test bundle and nexcage for Proxmox server testing

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TARGET_DIR="/tmp/nexcage-test-package"

echo "=== Preparing Test Package for Proxmox Server ==="
echo ""

# Create target directory
mkdir -p "$TARGET_DIR"
cd "$TARGET_DIR"

# 1. Copy or create test bundle
echo "1. Preparing test bundle..."
BUNDLE_SRC="$PROJECT_ROOT/tmp/test-oci-bundle/resources-namespaces"
BUNDLE_DEST="$TARGET_DIR/test-bundle"

if [ -d "$BUNDLE_SRC" ]; then
    cp -r "$BUNDLE_SRC" "$BUNDLE_DEST"
    echo "✓ Test bundle copied"
else
    mkdir -p "$BUNDLE_DEST/rootfs/bin"
    cat > "$BUNDLE_DEST/config.json" << 'EOF'
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
    echo "#!/bin/sh" > "$BUNDLE_DEST/rootfs/bin/sh"
    chmod +x "$BUNDLE_DEST/rootfs/bin/sh"
    echo "✓ Test bundle created"
fi

# 2. Copy nexcage binary if available
echo ""
echo "2. Checking nexcage binary..."
BINARY_SRC="$PROJECT_ROOT/zig-out/bin/nexcage"

if [ -f "$BINARY_SRC" ]; then
    cp "$BINARY_SRC" "$TARGET_DIR/nexcage"
    chmod +x "$TARGET_DIR/nexcage"
    echo "✓ nexcage binary copied"
else
    echo "⚠ nexcage binary not found. Build it with: cd $PROJECT_ROOT && zig build"
    echo "   Then copy zig-out/bin/nexcage to $TARGET_DIR/"
fi

# 3. Copy test script
echo ""
echo "3. Preparing test script..."
cat > "$TARGET_DIR/test-on-server.sh" << 'SCRIPT_EOF'
#!/bin/bash
# Test script to run on Proxmox server

set -e

BUNDLE_PATH="${1:-./test-bundle}"
CONTAINER_ID="${2:-test-resources-ns-$(date +%s)}"

echo "=== Testing on Proxmox Server ==="
echo "Bundle: $BUNDLE_PATH"
echo "Container ID: $CONTAINER_ID"
echo ""

# Check if nexcage is available
if [ -f "./nexcage" ]; then
    NEXCAGE="./nexcage"
elif command -v nexcage &> /dev/null; then
    NEXCAGE="nexcage"
else
    echo "ERROR: nexcage not found"
    exit 1
fi

echo "Using: $NEXCAGE"
$NEXCAGE --version || echo "Version check failed"
echo ""

# Create container
echo "Creating container..."
if $NEXCAGE create "$CONTAINER_ID" "$BUNDLE_PATH"; then
    echo "✓ Container created"
else
    echo "✗ Container creation failed"
    exit 1
fi

# Find VMID
echo ""
echo "Finding VMID..."
STATE_FILE="/var/lib/nexcage/state/${CONTAINER_ID}.json"
if [ -f "$STATE_FILE" ]; then
    VMID=$(grep -o '"vmid"[[:space:]]*:[[:space:]]*[0-9]*' "$STATE_FILE" | grep -o '[0-9]*' | head -1)
    echo "VMID: $VMID"
    
    # Verify resources
    echo ""
    echo "Verifying resources..."
    pct config "$VMID" | grep -E "memory|cores" || echo "Resources not found"
    
    # Verify features
    echo ""
    echo "Verifying features..."
    pct config "$VMID" | grep features || echo "Features not found"
    
    echo ""
    echo "Full config:"
    pct config "$VMID" | head -15
else
    echo "⚠ State file not found"
fi

echo ""
echo "=== Test Complete ==="
echo "Container ID: $CONTAINER_ID"
echo "To delete: $NEXCAGE delete $CONTAINER_ID"
SCRIPT_EOF

chmod +x "$TARGET_DIR/test-on-server.sh"
echo "✓ Test script created"

# 4. Create README
echo ""
echo "4. Creating README..."
cat > "$TARGET_DIR/README.md" << 'README_EOF'
# NexCage Test Package for Proxmox Server

## Contents

- `nexcage` - NexCage binary (if available)
- `test-bundle/` - OCI test bundle with resources and namespaces
- `test-on-server.sh` - Test script to run on Proxmox server

## Setup on Proxmox Server

1. Copy this directory to Proxmox server:
   ```bash
   scp -r /tmp/nexcage-test-package user@mgr.cp.if.ua:/tmp/
   ```

2. SSH to server:
   ```bash
   ssh user@mgr.cp.if.ua
   ```

3. Run test:
   ```bash
   cd /tmp/nexcage-test-package
   ./test-on-server.sh
   ```

## Test Bundle Configuration

- **Memory limit:** 256 MB (268435456 bytes)
- **CPU shares:** 512 (~0.5 cores)
- **Namespaces:** pid, network, ipc, uts, mount, user

## Expected Results

- Container created with VMID
- Memory: 256 MB
- CPU Cores: 1 (rounded from 512 shares)
- Features: nesting=1,keyctl=1 (from user namespace)
README_EOF

echo "✓ README created"

# Summary
echo ""
echo "=== Package Ready ==="
echo "Location: $TARGET_DIR"
echo ""
echo "Contents:"
ls -lh "$TARGET_DIR"
echo ""
echo "To transfer to server:"
echo "  scp -r $TARGET_DIR user@mgr.cp.if.ua:/tmp/"
echo ""
echo "Then on server:"
echo "  cd /tmp/nexcage-test-package"
echo "  ./test-on-server.sh"

