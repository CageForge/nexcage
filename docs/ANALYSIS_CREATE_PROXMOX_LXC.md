# Analysis: Create Command Implementation for Proxmox-LXC Backend

**Date:** 2025-11-02  
**Component:** `src/backends/proxmox-lxc/driver.zig`  
**Method:** `create()`

## Executive Summary

Analysis of the `create` command implementation reveals:

- ✅ **Mounts**: Fully implemented and working
- ⚠️ **Resources**: Partially implemented (memory & CPU only)
- ❌ **Namespaces**: Not implemented

---

## 1. Mount Configuration ✅ IMPLEMENTED

### Status: **FULLY IMPLEMENTED**

### Implementation Details:

**Location:** `src/backends/proxmox-lxc/driver.zig:917-928, 1025-1082`

#### How it works:

1. **Mount Detection** (Line 918-928):
   - After container creation, if `oci_bundle_path` exists, mounts are applied
   - Calls `applyMountsToLxcConfig(vmid, bundle_path)`

2. **Mount Parsing** (Line 1025-1082):
   - Parses OCI bundle `config.json` via `OciBundleParser`
   - Extracts mounts array from `config.mounts`
   - Reads existing `/etc/pve/lxc/<vmid>.conf` to determine next mount index
   - Appends mount entries using Proxmox format: `mp0:`, `mp1:`, etc.

3. **Mount Format** (Line 1098-1107):
   - Supports both storage references (`storage:path`) and absolute host paths
   - Format: `mp<idx>: <source>,mp=<destination>,<options>`
   - Options are parsed but not fully utilized (TODO comment on line 187)

4. **Mount Validation** (Line 978-1023):
   - `validateBundleVolumes()` checks that mount sources exist
   - Validates host paths accessibility
   - Validates Proxmox storage references via `pvesm list`

5. **Mount Verification** (Line 1085-1095):
   - `verifyMountsInConfig()` uses `pct config <vmid>` to verify mounts were added

### Code References:

```zig:917-928:src/backends/proxmox-lxc/driver.zig
// Apply mounts from bundle into /etc/pve/lxc/<vmid>.conf and verify via pct config
if (oci_bundle_path) |bundle_for_mounts| {
    if (self.debug_mode) {
        try stdout.writeAll("[DRIVER] create: Applying mounts from OCI bundle: '");
        try stdout.writeAll(bundle_for_mounts);
        try stdout.writeAll("'\n");
    }
    if (self.logger) |log| log.info("Applying mounts from OCI bundle: {s}", .{bundle_for_mounts}) catch {};
    try self.applyMountsToLxcConfig(vmid, bundle_for_mounts);
    try self.verifyMountsInConfig(vmid);
    if (self.debug_mode) try stdout.writeAll("[DRIVER] create: Mounts applied and verified\n");
}
```

```zig:1025-1082:src/backends/proxmox-lxc/driver.zig
/// Append mounts from bundle config to /etc/pve/lxc/<vmid>.conf using mpX syntax
fn applyMountsToLxcConfig(self: *Self, vmid: []const u8, bundle_path: []const u8) !void {
    // ... parsing and application logic ...
}
```

### Limitations:

1. **Mount Options Not Fully Parsed**: Line 187 in `oci_bundle.zig` has TODO: "Parse mount options"
2. **No Mount Type Validation**: Mount types (bind, tmpfs, etc.) are not validated or converted
3. **Read-only Mounts**: Read-only option parsing incomplete

---

## 2. Resource Configuration ⚠️ PARTIALLY IMPLEMENTED

### Status: **PARTIAL IMPLEMENTATION**

### What's Implemented:

#### ✅ Memory Limits
- **Location:** Lines 809-813, 838, 849
- Reads from `config.resources.memory`
- Converts bytes to MB
- Passes to `pct create --memory <MB>`

```zig:809-813:src/backends/proxmox-lxc/driver.zig
const mem_mb_str = blk: {
    const mem_bytes = if (config.resources) |r| r.memory orelse (core.constants.DEFAULT_MEMORY_BYTES) else core.constants.DEFAULT_MEMORY_BYTES;
    const mb: u64 = mem_bytes / (1024 * 1024);
    break :blk try std.fmt.allocPrint(self.allocator, "{d}", .{mb});
};
```

#### ✅ CPU/Cores Limits
- **Location:** Lines 816-820, 839, 850
- Reads from `config.resources.cpu`
- Converts float CPU shares to integer cores
- Passes to `pct create --cores <count>`

```zig:816-820:src/backends/proxmox-lxc/driver.zig
const cores_str = blk: {
    const c: f64 = if (config.resources) |r| (r.cpu orelse @as(f64, core.constants.DEFAULT_CPU_CORES)) else @as(f64, core.constants.DEFAULT_CPU_CORES);
    const ci: u32 = @intFromFloat(c);
    break :blk try std.fmt.allocPrint(self.allocator, "{d}", .{ci});
};
```

### What's NOT Implemented:

#### ❌ Disk/Storage Limits
- **Location:** `ResourceLimits` struct has `disk: ?u64` field (line 66 in `types.zig`)
- **Status:** Defined but never used in `create()` method
- **OCI Bundle:** Not parsed from bundle config.json
- **Proxmox:** Could be set via `pct set <vmid> --rootfs <storage>:<size>`

#### ❌ Network Bandwidth Limits
- **Location:** `ResourceLimits` struct has `network_bandwidth: ?u64` field (line 67 in `types.zig`)
- **Status:** Defined but never used in `create()` method
- **OCI Bundle:** Not parsed from bundle config.json
- **Proxmox:** Could be set via `pct set <vmid> --net0 <spec>,rate=<mbps>`

#### ⚠️ OCI Bundle Resource Parsing
- **Location:** `src/backends/proxmox-lxc/oci_bundle.zig:200-228`
- **Status:** Parses `linux.resources.memory.limit` and `linux.resources.cpu.shares` from bundle
- **Issue:** These parsed values are stored in `OciBundleConfig` but **NOT used** during container creation
- **Current Behavior:** Only `SandboxConfig.resources` is used, bundle resources are ignored

```zig:200-228:src/backends/proxmox-lxc/oci_bundle.zig
// Parse memory limit
if (resources_obj.get("memory")) |memory_val| {
    if (memory_val == .object) {
        const memory_obj = memory_val.object;
        if (memory_obj.get("limit")) |limit_val| {
            if (limit_val == .integer) {
                bundle_config.memory_limit = @as(u64, @intCast(limit_val.integer));
            }
        }
    }
}

// Parse CPU limit
if (resources_obj.get("cpu")) |cpu_val| {
    if (cpu_val == .object) {
        const cpu_obj = cpu_val.object;
        if (cpu_obj.get("shares")) |shares_val| {
            if (shares_val == .integer) {
                bundle_config.cpu_limit = @as(f64, @floatFromInt(shares_val.integer));
            }
        }
    }
}
```

**Problem:** `bundle_config.memory_limit` and `bundle_config.cpu_limit` are parsed but never applied to `SandboxConfig.resources` or used in `pct create`.

---

## 3. Namespace Configuration ❌ NOT IMPLEMENTED

### Status: **NOT IMPLEMENTED**

### Current State:

1. **Structure Exists** (Line 489-499 in `oci_bundle.zig`):
   ```zig
   pub const NamespaceConfig = struct {
       allocator: std.mem.Allocator,
       type: []const u8,  // "pid", "network", "ipc", "uts", "mount", "user"
       path: ?[]const u8 = null,
   };
   ```

2. **OCI Bundle Config Has Field** (Line 350 in `oci_bundle.zig`):
   ```zig
   namespaces: ?[]const NamespaceConfig = null,
   ```

3. **Deinit Method Exists** (Line 404-409 in `oci_bundle.zig`):
   - Properly cleans up namespace configs

### What's Missing:

#### ❌ Namespace Parsing
- OCI bundle `config.json` contains `linux.namespaces` array
- **NOT parsed** in `parseOciConfig()` method
- The structure exists but is never populated from bundle

#### ❌ Namespace Application
- Proxmox LXC uses namespaces but configuration is via:
  - `--unprivileged` flag (affects user namespace)
  - `--features` flag (e.g., `nesting=1`, `keyctl=1`)
  - Custom namespace configuration in `/etc/pve/lxc/<vmid>.conf`
- **NO code** applies namespace configuration from OCI bundle
- Currently only `--unprivileged` is set (hardcoded from config, line 832)

### OCI Namespace Spec Example:

```json
{
  "linux": {
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
```

### Proxmox LXC Namespace Equivalents:

- **PID namespace**: Default for LXC (no config needed)
- **Network namespace**: Default for LXC (no config needed)
- **IPC namespace**: Default for LXC (no config needed)
- **UTS namespace**: Default for LXC (no config needed)
- **Mount namespace**: Default for LXC (no config needed)
- **User namespace**: Controlled by `--unprivileged` flag

**Note:** Proxmox LXC containers **always** use the standard namespaces. The OCI spec allows for shared namespaces via `path`, but Proxmox LXC doesn't support this directly.

---

## Recommendations

### Priority 1: Fix Resource Parsing from OCI Bundle

**Issue:** OCI bundle `config.json` resources are parsed but not used.

**Fix:**
```zig
// In driver.zig create() method, after parsing bundle:
if (oci_bundle_path) |bundle_path| {
    var parser = oci_bundle.OciBundleParser.init(self.allocator, self.logger);
    var bundle_cfg = try parser.parseBundle(bundle_path);
    defer bundle_cfg.deinit();
    
    // Merge bundle resources into SandboxConfig
    if (bundle_cfg.memory_limit) |mem_limit| {
        if (config.resources == null) {
            config.resources = core.types.ResourceLimits{};
        }
        config.resources.?.memory = mem_limit;
    }
    
    if (bundle_cfg.cpu_limit) |cpu_limit| {
        if (config.resources == null) {
            config.resources = core.types.ResourceLimits{};
        }
        config.resources.?.cpu = cpu_limit;
    }
}
```

### Priority 2: Implement Disk Limits

**Location:** After container creation (similar to mounts)

**Implementation:**
```zig
// After pct create succeeds
if (config.resources) |r| {
    if (r.disk) |disk_bytes| {
        const disk_mb = disk_bytes / (1024 * 1024);
        const disk_str = try std.fmt.allocPrint(self.allocator, "{d}", .{disk_mb});
        defer self.allocator.free(disk_str);
        
        // Resize rootfs if ZFS dataset exists
        if (zfs_dataset) |dataset| {
            const resize_args = [_][]const u8{ "zfs", "set", "quota={s}M", dataset };
            _ = try self.runCommand(&resize_args);
        }
    }
}
```

### Priority 3: Implement Network Bandwidth Limits

**Location:** After container creation (similar to mounts)

**Implementation:**
```zig
// After pct create succeeds
if (config.resources) |r| {
    if (r.network_bandwidth) |bandwidth_bps| {
        const bandwidth_mbps = bandwidth_bps / (1024 * 1024);
        const rate_str = try std.fmt.allocPrint(self.allocator, "{d}", .{bandwidth_mbps});
        defer self.allocator.free(rate_str);
        
        const set_args = [_][]const u8{ "pct", "set", vmid, "--net0", try std.fmt.allocPrint(
            self.allocator, "rate={s}", .{rate_str}
        ) };
        _ = try self.runCommand(&set_args);
    }
}
```

### Priority 4: Parse Namespaces from OCI Bundle (Even if Limited Application)

**Reason:** For OCI compliance, even if Proxmox LXC doesn't support all namespace configurations, we should:
1. Parse namespaces from bundle
2. Log unsupported configurations
3. Apply what we can (user namespace via `--unprivileged`)

**Implementation:**
```zig
// In oci_bundle.zig parseOciConfig():
if (linux_obj.get("namespaces")) |namespaces_val| {
    if (namespaces_val == .array) {
        const ns_array = namespaces_val.array;
        var namespaces = try self.allocator.alloc(NamespaceConfig, ns_array.items.len);
        for (ns_array.items, 0..) |ns_val, i| {
            if (ns_val == .object) {
                const ns_obj = ns_val.object;
                namespaces[i] = NamespaceConfig{
                    .allocator = self.allocator,
                    .type = if (ns_obj.get("type")) |t|
                        if (t == .string) try self.allocator.dupe(u8, t.string) else "pid"
                    else "pid",
                    .path = if (ns_obj.get("path")) |p|
                        if (p == .string) try self.allocator.dupe(u8, p.string) else null
                    else null,
                };
            }
        }
        bundle_config.namespaces = namespaces;
    }
}
```

---

## Summary Table

| Feature | Status | Implementation Location | Notes |
|---------|--------|-------------------------|-------|
| **Mounts** | ✅ Complete | `driver.zig:917-928, 1025-1082` | Works for OCI bundles, validates paths |
| **Memory Limits** | ✅ Complete | `driver.zig:809-813, 838, 849` | From SandboxConfig, not from bundle |
| **CPU Limits** | ✅ Complete | `driver.zig:816-820, 839, 850` | From SandboxConfig, not from bundle |
| **Disk Limits** | ❌ Missing | N/A | Defined in ResourceLimits but unused |
| **Network Bandwidth** | ❌ Missing | N/A | Defined in ResourceLimits but unused |
| **Bundle Resources** | ⚠️ Partial | `oci_bundle.zig:200-228` | Parsed but not applied |
| **Namespaces** | ❌ Missing | N/A | Structure exists but never populated/used |

---

## Code Quality Observations

1. **Debug Logging:** Excessive debug logging using stderr/stdout directly (should use logger)
2. **Error Handling:** Good use of `try` and error propagation
3. **Memory Management:** Proper use of `defer` for cleanup
4. **Code Organization:** Large `create()` method (975 lines) - could be refactored

---

## Next Steps

1. ✅ **Immediate:** Fix bundle resource parsing to actually use parsed values - **COMPLETED**
2. ✅ **High Priority:** Implement disk and network bandwidth limits
3. ✅ **Medium Priority:** Parse namespaces from bundle (even if limited application) - **COMPLETED**
4. ✅ **Low Priority:** Refactor large `create()` method into smaller functions

## Recent Implementation (2025-11-02)

### Resource Limits from OCI Bundle

**Implementation:**
- ✅ Bundle config parsing now extracts `memory_limit` and `cpu_limit` from `linux.resources.memory.limit` and `linux.resources.cpu.shares`
- ✅ Resources from OCI bundle take priority over SandboxConfig resources
- ✅ Memory limit converted from bytes to MB for `pct create --memory`
- ✅ CPU shares converted to cores approximation (shares/1024) for `pct create --cores`

**Priority Order:**
1. `bundle_config.memory_limit` / `bundle_config.cpu_limit` (OCI bundle)
2. `config.resources.memory` / `config.resources.cpu` (SandboxConfig)
3. Default values (`DEFAULT_MEMORY_BYTES`, `DEFAULT_CPU_CORES`)

### OCI Namespaces Support

**Implementation:**
- ✅ Parsing of `linux.namespaces` array from OCI config.json
- ✅ Namespace types supported: `user`, `pid`, `network`, `ipc`, `uts`, `mount`, `cgroup`
- ✅ Application of LXC features based on namespace types via `pct set --features`

**Namespace Mapping:**
- `user` namespace → enables `nesting=1` and `keyctl=1` features (required for nested containers)
- Other namespaces (pid, network, ipc, uts, mount, cgroup) are default in LXC and don't require special configuration
- Features are applied after container creation using `pct set <vmid> --features <features>`

**LXC Features Applied:**
- `nesting=1` - Allows nested containers (when user namespace present)
- `keyctl=1` - Kernel key management (useful with user namespaces)

