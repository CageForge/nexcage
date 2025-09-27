const std = @import("std");
const logger = std.log.scoped(.oci_stop);
const proxmox = @import("proxmox");
const errors = @import("error");

pub fn stop(container_id: []const u8, proxmox_client: *proxmox.ProxmoxClient) !void {
    try proxmox_client.logger.info("Stopping container: {s}", .{container_id});

    // Отримуємо список контейнерів щоб знайти VMID за іменем
    const containers = try proxmox_client.listLXCs();
    defer {
        for (containers) |*container| {
            container.deinit(proxmox_client.allocator);
        }
        proxmox_client.allocator.free(containers);
    }

    // Шукаємо контейнер за іменем
    var vmid: ?u32 = null;
    for (containers) |container| {
        if (std.mem.eql(u8, container.name, container_id)) {
            vmid = container.vmid;
            break;
        }
    }

    if (vmid == null) {
        try proxmox_client.logger.err("Container with name {s} not found", .{container_id});
        return error.ContainerNotFound;
    }

    // Отримуємо поточний статус контейнера
    const status = try proxmox_client.getContainerStatus(.lxc, vmid.?);

    if (status == .stopped) {
        try proxmox_client.logger.info("Container {s} is already stopped", .{container_id});
        return;
    }

    // Зупиняємо контейнер
    try proxmox_client.stopContainer(.lxc, vmid.?, null);
    try proxmox_client.logger.info("Container {s} stopped successfully", .{container_id});
}
