const std = @import("std");
const Allocator = std.mem.Allocator;
const logger = std.log.scoped(.oci_delete);
const proxmox = @import("proxmox");
const errors = @import("error");

pub fn delete(container_id: []const u8, proxmox_client: *proxmox.ProxmoxClient) !void {
    logger.info("Deleting container {s}", .{container_id});

    const vmid = std.fmt.parseInt(u32, container_id, 10) catch return error.InvalidContainerId;

    // Перевіряємо статус контейнера
    const status = try proxmox_client.getContainerStatus(.lxc, vmid);
    if (status == .running) {
        // Зупиняємо контейнер перед видаленням
        try proxmox_client.stopContainer(.lxc, vmid, 30);
    }

    // Видаляємо контейнер
    try proxmox_client.deleteContainer(.lxc, vmid);

    logger.info("Container {s} deleted successfully", .{container_id});
} 