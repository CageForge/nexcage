const std = @import("std");
const Allocator = std.mem.Allocator;
const logger = std.log.scoped(.oci_kill);
const proxmox = @import("proxmox");
const errors = @import("error");

pub fn kill(container_id: []const u8, signal: []const u8, proxmox_client: *proxmox.ProxmoxClient) !void {
    logger.info("Sending signal {s} to container {s}", .{ signal, container_id });

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
        logger.err("Container with name {s} not found", .{container_id});
        return error.ContainerNotFound;
    }

    // Відповідно до специфікації OCI, runtime ПОВИНЕН підтримувати TERM і KILL
    // з семантикою POSIX. Оскільки Proxmox API не підтримує різні сигнали,
    // ми просто зупиняємо контейнер
    if (std.mem.eql(u8, signal, "SIGKILL") or
        std.mem.eql(u8, signal, "SIGTERM") or
        std.mem.eql(u8, signal, "TERM"))
    {
        try proxmox_client.stopContainer(.lxc, vmid.?, null);
    } else {
        // Інші сигнали наразі не підтримуються
        logger.warn("Signal {s} is not supported, using default stop", .{signal});
        try proxmox_client.stopContainer(.lxc, vmid.?, null);
    }

    logger.info("Signal {s} sent to container {s} successfully", .{ signal, container_id });
}
