/// Proxmox API integration module
///
/// This module provides integration with Proxmox VE API for managing
/// LXC containers, VMs, templates, and other Proxmox resources.
pub const types = @import("types.zig");
pub const client = @import("client.zig");
pub const operations = @import("operations.zig");
