const std = @import("std");
const logger = std.log.scoped(.oci_list);
const proxmox = @import("proxmox");
const types = @import("types");

pub fn list(proxmox_client: *proxmox.ProxmoxClient) !void {
    try proxmox_client.logger.info("Listing containers", .{});

    const containers = try proxmox_client.listLXCs();
    defer {
        for (containers) |*container| {
            container.deinit(proxmox_client.allocator);
        }
        proxmox_client.allocator.free(containers);
    }

    if (containers.len == 0) {
        try std.io.getStdOut().writer().print("No containers found\n", .{});
        return;
    }

    // Виводимо заголовок таблиці
    try std.io.getStdOut().writer().print("{s:<10} {s:<20} {s:<15} {s:<10}\n", .{ "VMID", "Name", "Status", "Type" });
    try std.io.getStdOut().writer().print("{s:-<55}\n", .{""});

    // Виводимо інформацію про кожен контейнер
    for (containers) |container| {
        const status_str = switch (container.status) {
            .running => "running",
            .stopped => "stopped",
            .paused => "paused",
            else => "unknown",
        };

        try std.io.getStdOut().writer().print("{d:<10} {s:<20} {s:<15} {s:<10}\n", .{ container.vmid, container.name, status_str, "lxc" });
    }
}
