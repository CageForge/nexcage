const std = @import("std");
const proxmox = @import("proxmox");
const logger = @import("logger");
const oci = @import("oci");

pub fn createLXC(client: *proxmox.ProxmoxClient, oci_container_id: []const u8, spec: *const oci.Spec) !void {
    const vmid = try client.getProxmoxVMID(oci_container_id);
    
    const api_path = try std.fmt.allocPrint(client.allocator, "/nodes/{s}/lxc", .{client.node});
    defer client.allocator.free(api_path);

    // Створюємо конфігурацію для Proxmox LXC
    var config = std.StringHashMap([]const u8).init(client.allocator);
    defer {
        var iter = config.iterator();
        while (iter.next()) |entry| {
            client.allocator.free(entry.value_ptr.*);
        }
        config.deinit();
    }

    // Базові налаштування
    try config.put("vmid", try std.fmt.allocPrint(client.allocator, "{d}", .{vmid}));
    try config.put("hostname", try client.allocator.dupe(u8, spec.hostname));
    try config.put("ostype", try client.allocator.dupe(u8, "ubuntu")); // За замовчуванням використовуємо Ubuntu

    // Налаштування мережі (за замовчуванням)
    try config.put("net0", try client.allocator.dupe(u8, "name=eth0,bridge=vmbr0,ip=dhcp"));

    // Налаштування ресурсів
    if (spec.linux) |linux| {
        if (linux.resources) |resources| {
            if (resources.memory) |memory| {
                if (memory.limit) |limit| {
                    try config.put("memory", try std.fmt.allocPrint(client.allocator, "{d}", .{limit / (1024 * 1024)})); // Конвертуємо в MB
                }
            }
            if (resources.cpu) |cpu| {
                if (cpu.shares) |shares| {
                    try config.put("cpuunits", try std.fmt.allocPrint(client.allocator, "{d}", .{shares}));
                }
            }
        }
    }

    // Налаштування root filesystem
    if (spec.root) |root| {
        if (root.path) |root_path| {
            try config.put("rootfs", try client.allocator.dupe(u8, root_path));
        }
    }

    // Перетворюємо конфігурацію в JSON
    const body = try std.json.stringifyAlloc(client.allocator, config, .{});
    defer client.allocator.free(body);

    // Відправляємо запит на створення контейнера
    const response = try client.makeRequest(.POST, api_path, body);
    defer client.allocator.free(response);

    // Перевіряємо відповідь
    var parsed = try std.json.parseFromSlice(std.json.Value, client.allocator, response, .{});
    defer parsed.deinit();

    // Логуємо успішне створення
    try logger.info("Created LXC container with VMID: {d}", .{vmid});
} 