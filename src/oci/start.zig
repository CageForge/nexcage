const std = @import("std");
const logger = std.log.scoped(.oci_start);
const proxmox = @import("proxmox");
const errors = @import("error");

pub fn start(container_id: []const u8, proxmox_client: *proxmox.ProxmoxClient) !void {
    logger.info("Starting container {s}", .{container_id});

    const vmid = try std.fmt.parseInt(u32, container_id, 10);
    try proxmox_client.startContainer(.lxc, vmid);

    logger.info("Container {s} started successfully", .{container_id});
} 