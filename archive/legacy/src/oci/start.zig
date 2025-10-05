const std = @import("std");
const logger = std.log.scoped(.oci_start);
const proxmox = @import("proxmox");
const errors = @import("error");

pub fn start(container_id: []const u8, proxmox_client: *proxmox.ProxmoxClient) !void {
    logger.info("Starting container {s}", .{container_id});

    // Get list of containers to find VMID by name
    const containers = try proxmox_client.listLXCs();
    defer {
        for (containers) |*container| {
            container.deinit(proxmox_client.client.allocator);
        }
        proxmox_client.client.allocator.free(containers);
    }

    // Find container by name
    var vmid: ?u32 = null;
    for (containers) |container| {
        if (std.mem.eql(u8, container.name, container_id)) {
            vmid = container.vmid;
            break;
        }
    }

    if (vmid == null) {
        logger.err("Container with name {s} not found", .{container_id});
        return error.ContainerNotFound;
    }

    try proxmox_client.startContainer(.lxc, vmid.?);

    logger.info("Container {s} started successfully", .{container_id});
}
