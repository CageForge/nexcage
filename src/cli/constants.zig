/// CLI Constants
/// This file contains all magic numbers and default values used across CLI modules

// Memory constants (in bytes)
pub const DEFAULT_MEMORY_MB: u32 = 512;
pub const DEFAULT_MEMORY_BYTES: u64 = DEFAULT_MEMORY_MB * 1024 * 1024;

// CPU constants
pub const DEFAULT_CPU_CORES: f32 = 1.0;

// Network constants
pub const DEFAULT_BRIDGE_NAME: []const u8 = "lxcbr0";

// VM constants
pub const DEFAULT_VM_ID: u32 = 100;
pub const DEFAULT_VM_MEMORY_GB: u32 = 1;
pub const DEFAULT_VM_MEMORY_BYTES: u64 = DEFAULT_VM_MEMORY_GB * 1024 * 1024 * 1024;

// Container runtime defaults
pub const DEFAULT_RUNTIME_TYPE = .lxc;
