const std = @import("std");
const Allocator = std.mem.Allocator;
const logger = std.log.scoped(.oci_state);
const proxmox = @import("proxmox");
const errors = @import("error");
const types = @import("types");

pub fn state(
    allocator: Allocator,
    container_id: []const u8,
    bundle_path: []const u8,
    proxmox_client: *proxmox.ProxmoxClient,
) !types.ContainerState {
    logger.info("Getting state for container {s}", .{container_id});

    const status = try proxmox_client.getContainerStatus(.lxc, std.fmt.parseInt(u32, container_id, 10) catch return error.InvalidContainerId);

    const container_state = types.ContainerState{
        .ociVersion = try allocator.dupe(u8, "1.0.0"),
        .id = try allocator.dupe(u8, container_id),
        .status = try allocator.dupe(u8, @tagName(status)),
        .pid = 0, // TODO: Отримати реальний PID
        .bundle = try allocator.dupe(u8, bundle_path),
        .annotations = null,
    };

    logger.info("Container {s} state retrieved successfully", .{container_id});
    return container_state;
} 