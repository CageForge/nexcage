/// CLI Constants
/// This file contains all magic numbers and default values used across CLI modules

// Memory constants (in bytes)
pub const DEFAULT_MEMORY_MB: u32 = 512;
pub const DEFAULT_MEMORY_BYTES: u64 = DEFAULT_MEMORY_MB * 1024 * 1024;

// CPU constants
pub const DEFAULT_CPU_CORES: f32 = 1.0;

// Network constants
// vmbr0 is the bridge a Proxmox VE install creates. This used to be vmbr50,
// which exists only on the CI runner; set "network.bridge" in the config file
// for anything else.
pub const DEFAULT_BRIDGE_NAME: []const u8 = "vmbr0";

// Storage constants
// Root filesystem size used when "proxmox.storage" is set without
// "proxmox.rootfs_size_gb"; matches the Proxmox VE web UI default.
pub const DEFAULT_ROOTFS_SIZE_GB: u32 = 8;

// VM constants
pub const DEFAULT_VM_ID: u32 = 100;
pub const DEFAULT_VM_MEMORY_GB: u32 = 1;
pub const DEFAULT_VM_MEMORY_BYTES: u64 = DEFAULT_VM_MEMORY_GB * 1024 * 1024 * 1024;

// Container runtime defaults
pub const DEFAULT_RUNTIME_TYPE = .lxc;

// Tests
const std = @import("std");

test "memory constants" {
    try std.testing.expect(DEFAULT_MEMORY_MB == 512);
    try std.testing.expect(DEFAULT_MEMORY_BYTES == 512 * 1024 * 1024);
    try std.testing.expect(DEFAULT_MEMORY_BYTES == 536870912);
}

test "CPU constants" {
    try std.testing.expect(DEFAULT_CPU_CORES == 1.0);
}

test "network constants" {
    try std.testing.expectEqualStrings(DEFAULT_BRIDGE_NAME, "vmbr0");
}

test "storage constants" {
    try std.testing.expect(DEFAULT_ROOTFS_SIZE_GB == 8);
}

test "VM constants" {
    try std.testing.expect(DEFAULT_VM_ID == 100);
    try std.testing.expect(DEFAULT_VM_MEMORY_GB == 1);
    try std.testing.expect(DEFAULT_VM_MEMORY_BYTES == 1024 * 1024 * 1024);
    try std.testing.expect(DEFAULT_VM_MEMORY_BYTES == 1073741824);
}

test "runtime constants" {
    try std.testing.expect(DEFAULT_RUNTIME_TYPE == .lxc);
}
