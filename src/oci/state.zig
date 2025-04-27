const std = @import("std");
const Allocator = std.mem.Allocator;
const logger = @import("logger");
const proxmox = @import("proxmox");
const errors = @import("error");
const types = @import("types");

fn lxcStatusToContainerStatus(lxc_status: types.LXCStatus) types.ContainerStatus {
    return switch (lxc_status) {
        .running => .running,
        .stopped => .stopped,
        // LXC не має стану paused, тому всі інші стани вважаємо unknown
        else => .unknown,
    };
}

fn containerStatusToString(status: types.ContainerStatus) []const u8 {
    return switch (status) {
        .running => "running",
        .stopped => "stopped",
        .paused => "paused",
        .unknown => "unknown",
    };
}

pub fn getState(proxmox_client: *proxmox.ProxmoxClient, oci_container_id: []const u8) !types.ContainerState {
    try proxmox_client.logger.info("Getting state for container {s}", .{oci_container_id});

    const vmid = try proxmox_client.getProxmoxVMID(oci_container_id);
    const containers = try proxmox_client.listContainers();
    defer proxmox_client.allocator.free(containers);

    for (containers) |container| {
        if (container.vmid == vmid) {
            const bundle = try std.fmt.allocPrint(proxmox_client.allocator, "/var/lib/lxc/{s}", .{oci_container_id});
            const status = try proxmox_client.allocator.dupe(u8, containerStatusToString(lxcStatusToContainerStatus(container.status)));
            const version = try proxmox_client.allocator.dupe(u8, "1.0.2");
            const id = try proxmox_client.allocator.dupe(u8, oci_container_id);

            return types.ContainerState{
                .ociVersion = version,
                .id = id,
                .status = status,
                .pid = 0, // TODO: отримати реальний PID
                .bundle = bundle,
                .annotations = null,
            };
        }
    }

    try proxmox_client.logger.err("Container with VMID {d} not found", .{vmid});
    return error.ContainerNotFound;
} 