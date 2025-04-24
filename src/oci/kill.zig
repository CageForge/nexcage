const std = @import("std");
const Allocator = std.mem.Allocator;
const logger = std.log.scoped(.oci_kill);
const proxmox = @import("proxmox");
const errors = @import("error");

pub fn kill(container_id: []const u8, signal: []const u8, proxmox_client: *proxmox.ProxmoxClient) !void {
    logger.info("Sending signal {s} to container {s}", .{ signal, container_id });

    const vmid = std.fmt.parseInt(u32, container_id, 10) catch return error.InvalidContainerId;

    if (std.mem.eql(u8, signal, "SIGKILL")) {
        try proxmox_client.stopContainer(.lxc, vmid, null);
    } else {
        try proxmox_client.stopContainer(.lxc, vmid, 30);
    }

    logger.info("Signal {s} sent to container {s} successfully", .{ signal, container_id });
} 