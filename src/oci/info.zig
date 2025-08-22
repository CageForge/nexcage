const std = @import("std");
const logger = std.log.scoped(.oci_info);
const proxmox = @import("proxmox");
const types = @import("types");

pub fn info(container_id: []const u8, proxmox_client: *proxmox.ProxmoxClient) !void {
    try proxmox_client.logger.info("Getting info for container: {s}", .{container_id});
    
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
    var found_container: ?types.LXCContainer = null;
    for (containers) |container| {
        if (std.mem.eql(u8, container.name, container_id)) {
            vmid = container.vmid;
            found_container = container;
            break;
        }
    }

    if (vmid == null or found_container == null) {
        try proxmox_client.logger.err("Container with name {s} not found", .{container_id});
        return error.ContainerNotFound;
    }

    const container = found_container.?;

    // Виводимо детальну інформацію про контейнер
    try std.io.getStdOut().writer().print("Container Information:\n", .{});
    try std.io.getStdOut().writer().print("  ID: {s}\n", .{container_id});
    try std.io.getStdOut().writer().print("  VMID: {d}\n", .{container.vmid});
    try std.io.getStdOut().writer().print("  Name: {s}\n", .{container.name});
    try std.io.getStdOut().writer().print("  Status: {s}\n", .{@tagName(container.status)});
    try std.io.getStdOut().writer().print("  Type: LXC\n", .{});
    
    // container.config не є optional, тому використовуємо його напряму
    const config = container.config;
    try std.io.getStdOut().writer().print("  Hostname: {s}\n", .{config.hostname});
    try std.io.getStdOut().writer().print("  OS Type: {s}\n", .{config.ostype});
    try std.io.getStdOut().writer().print("  Memory: {d} MB\n", .{config.memory});
    try std.io.getStdOut().writer().print("  Cores: {d}\n", .{config.cores});
    try std.io.getStdOut().writer().print("  Root FS: {s}\n", .{config.rootfs});
    try std.io.getStdOut().writer().print("  Network: {s}\n", .{config.net0.name});
    try std.io.getStdOut().writer().print("  Bridge: {s}\n", .{config.net0.bridge});
    try std.io.getStdOut().writer().print("  IP: {s}\n", .{config.net0.ip});
}
