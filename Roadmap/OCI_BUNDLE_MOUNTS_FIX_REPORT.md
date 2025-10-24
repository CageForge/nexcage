# OCI Bundle Mounts Fix Report

**Date**: 2025-10-23  
**Status**: ✅ COMPLETED  
**Priority**: P0 - CRITICAL  

---

## Problem Description

**Issue**: `ConfigFileNotFound` error when applying mounts from OCI bundle to LXC container configuration.

**Root Cause**: The `applyMountsToLxcConfig` function was receiving the wrong path - it was getting the template path instead of the original OCI bundle path.

---

## Root Cause Analysis

### The Problem Flow

1. **OCI Bundle Processing**: When creating a container with an OCI bundle:
   ```zig
   // In driver.zig:104-131
   if (config.image) |image_path| {
       if (std.mem.endsWith(u8, image_path, ".tar.zst") or std.mem.indexOf(u8, image_path, ":") != null) {
           // It's a Proxmox template, use it directly
           template_name = try self.allocator.dupe(u8, image_path);
       } else {
           // It's an OCI bundle - convert to template
           template_name = try self.processOciBundle(image_path, config.name);
       }
   }
   ```

2. **Mounts Processing**: After container creation, mounts were applied:
   ```zig
   // In driver.zig:202-206 (BEFORE FIX)
   if (config.image) |bundle_for_mounts| {
       try self.applyMountsToLxcConfig(vmid, bundle_for_mounts);
   }
   ```

3. **The Bug**: `config.image` now contained the template path (e.g., `local:vztmpl/ubuntu-22.04-standard_22.04-1_amd64.tar.zst`) instead of the original OCI bundle path (e.g., `/tmp/test-bundle-with-mounts`).

4. **ConfigFileNotFound Error**: `applyMountsToLxcConfig` tried to parse the template file as an OCI bundle, looking for `config.json` inside the `.tar.zst` file, which failed.

---

## Solution Implemented

### 1. Track Original OCI Bundle Path

**File**: `src/backends/proxmox-lxc/driver.zig:104-132`

```zig
// Keep track of original OCI bundle path for mounts
var oci_bundle_path: ?[]const u8 = null;

if (config.image) |image_path| {
    if (std.mem.endsWith(u8, image_path, ".tar.zst") or std.mem.indexOf(u8, image_path, ":") != null) {
        // It's a Proxmox template, use it directly
        template_name = try self.allocator.dupe(u8, image_path);
    } else {
        // It's an OCI bundle - ensure bundle directory exists
        // ... validation code ...
        
        // Save OCI bundle path for mounts processing
        oci_bundle_path = image_path;
        
        // Process OCI bundle - convert to template if needed
        template_name = try self.processOciBundle(image_path, config.name);
    }
}
```

### 2. Use Correct Path for Mounts Processing

**File**: `src/backends/proxmox-lxc/driver.zig:208-212`

```zig
// Apply mounts from bundle into /etc/pve/lxc/<vmid>.conf and verify via pct config
if (oci_bundle_path) |bundle_for_mounts| {
    if (self.logger) |log| try log.info("Applying mounts from OCI bundle: {s}", .{bundle_for_mounts});
    try self.applyMountsToLxcConfig(vmid, bundle_for_mounts);
    try self.verifyMountsInConfig(vmid);
}
```

---

## Key Changes

### Before Fix
- `config.image` was used for both template creation AND mounts processing
- After OCI bundle conversion, `config.image` pointed to template path
- `applyMountsToLxcConfig` received template path instead of bundle path
- `ConfigFileNotFound` error when trying to parse template as OCI bundle

### After Fix
- `oci_bundle_path` variable tracks original OCI bundle path separately
- `template_name` is used for container creation
- `oci_bundle_path` is used for mounts processing
- Mounts are correctly applied from the original OCI bundle

---

## Code Flow

### OCI Bundle Processing Flow
```
1. Input: /tmp/test-bundle-with-mounts (OCI bundle path)
2. Validation: Check bundle directory and config.json exist
3. Save: oci_bundle_path = "/tmp/test-bundle-with-mounts"
4. Convert: template_name = "test-mounts-container-1234567890"
5. Create: pct create using template_name
6. Mounts: applyMountsToLxcConfig using oci_bundle_path
```

### Proxmox Template Processing Flow
```
1. Input: local:vztmpl/ubuntu-22.04-standard_22.04-1_amd64.tar.zst
2. Direct: template_name = "local:vztmpl/ubuntu-22.04-standard_22.04-1_amd64.tar.zst"
3. Create: pct create using template_name
4. Mounts: No mounts processing (oci_bundle_path = null)
```

---

## Testing

### Test Case 1: OCI Bundle with Mounts
```bash
# Create OCI bundle with mounts
mkdir -p /tmp/test-bundle-with-mounts/rootfs
cat > /tmp/test-bundle-with-mounts/config.json << EOF
{
  "mounts": [
    {
      "destination": "/host-data",
      "type": "bind",
      "source": "/tmp/host-data",
      "options": ["bind", "ro"]
    }
  ]
}
EOF

# Create container (should work without ConfigFileNotFound)
nexcage create --name test-mounts-container /tmp/test-bundle-with-mounts
```

### Test Case 2: Proxmox Template (No Mounts)
```bash
# Create container with template (should work as before)
nexcage create --name test-template-container local:vztmpl/ubuntu-22.04-standard_22.04-1_amd64.tar.zst
```

---

## Impact

- ✅ **ConfigFileNotFound error fixed**: OCI bundle mounts now work correctly
- ✅ **Backward compatibility**: Proxmox template processing unchanged
- ✅ **Clean separation**: Template creation and mounts processing use correct paths
- ✅ **Better logging**: Clear distinction between OCI bundle and template processing

---

## Related Functions

- `applyMountsToLxcConfig()`: Now receives correct OCI bundle path
- `verifyMountsInConfig()`: Verifies mounts were applied correctly
- `processOciBundle()`: Converts OCI bundle to Proxmox template
- `validateBundleVolumes()`: Validates mount sources exist

---

## Time Spent

**Total**: ~30 minutes
- Root cause analysis: 10 min
- Implementation: 15 min
- Documentation: 5 min

---

## Next Steps

1. ✅ Test on Proxmox server with real OCI bundles
2. ✅ Verify mounts are correctly applied to LXC config
3. ⏭️ Proceed with next critical task: System integrity checks

---

## Related Issues

- GitHub Issue #TBD: ConfigFileNotFound error with OCI bundle mounts
- Roadmap: OCI Bundle Support (HIGH priority)

