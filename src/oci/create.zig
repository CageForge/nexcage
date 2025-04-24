const std = @import("std");
const Allocator = std.mem.Allocator;
const json = std.json;
const fs = std.fs;
const spec = @import("../oci/spec.zig");
const logger = std.log.scoped(.oci_create);
const errors = @import("error");
const types = @import("types");
const proxmox = @import("proxmox");

pub const CreateOpts = struct {
    bundle_path: []const u8,
    container_id: []const u8,
    pid_file: ?[]const u8 = null,
};

pub fn create(
    allocator: Allocator,
    opts: CreateOpts,
    proxmox_client: *proxmox.ProxmoxClient,
) !void {
    logger.info("Creating container {s} with bundle {s}", .{ opts.container_id, opts.bundle_path });

    // Перевіряємо наявність bundle директорії
    try fs.cwd().access(opts.bundle_path, .{});

    // Читаємо та парсимо config.json
    const config_path = try std.fs.path.join(allocator, &[_][]const u8{ opts.bundle_path, "config.json" });
    defer allocator.free(config_path);

    const config_file = try std.fs.openFileAbsolute(config_path, .{});
    defer config_file.close();

    const config_content = try config_file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(config_content);

    var parsed = try std.json.parseFromSlice(spec.Spec, allocator, config_content, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    });
    defer parsed.deinit();

    const config = parsed.value;

    const default_memory: u32 = 512 * 1024 * 1024;
    const memory_limit: u32 = if (config.linux.resources) |res| 
        if (res.memory) |memory_res| 
            if (memory_res.limit) |limit| 
                @intCast(@min(limit, std.math.maxInt(u32)))
            else default_memory
        else default_memory
    else default_memory;

    const storage = try getStorageFromConfig(allocator, config);
    defer allocator.free(storage);

    const rootfs = try std.fmt.allocPrint(allocator, "{s}:8", .{storage});
    defer allocator.free(rootfs);

    // Створюємо LXC контейнер через Proxmox API
    var container_config = types.LXCConfig{
        .hostname = try allocator.dupe(u8, config.hostname),
        .ostype = try allocator.dupe(u8, "ubuntu"),
        .memory = memory_limit,
        .swap = 0,
        .cores = if (config.linux.resources) |res|
            if (res.cpu) |cpu| @intCast(cpu.quota orelse 1) else 1
        else 1,
        .rootfs = rootfs,
        .net0 = .{
            .name = try allocator.dupe(u8, "vmbr50"),
            .bridge = try allocator.dupe(u8, "vmbr50"),
            .ip = try allocator.dupe(u8, "dhcp"),
            .type = try allocator.dupe(u8, "veth"),
        },
        .onboot = false,
        .protection = false,
        .start = true,
        .template = false,
        .unprivileged = true,
        .features = .{},
    };
    defer container_config.deinit(allocator);

    const container = try proxmox_client.createLXC(container_config);

    // Якщо вказано pid_file, записуємо PID
    if (opts.pid_file) |pid_file| {
        const pid_str = try std.fmt.allocPrint(allocator, "{d}\n", .{container.vmid});
        defer allocator.free(pid_str);
        
        try fs.cwd().writeFile(.{
            .sub_path = pid_file,
            .data = pid_str,
            .flags = .{},
        });
        //try fs.cwd().chmod(pid_file, 0o644);
    }

    logger.info("Container {s} created successfully", .{opts.container_id});
}

fn getStorageFromConfig(allocator: Allocator, config: spec.Spec) ![]const u8 {
    // Спочатку перевіряємо анотації
    if (config.annotations) |annotations| {
        if (annotations.get("proxmox.storage")) |storage| {
            return try allocator.dupe(u8, storage);
        }
    }

    // Перевіряємо тип монтування root
    for (config.mounts) |mount| {
        if (std.mem.eql(u8, mount.destination, "/")) {
            if (std.mem.startsWith(u8, mount.source, "zfs:")) {
                return try allocator.dupe(u8, "zfs");
            } else if (std.mem.startsWith(u8, mount.source, "dir:")) {
                return try allocator.dupe(u8, "local");
            }
        }
    }

    // За замовчуванням використовуємо local
    return try allocator.dupe(u8, "local");
} 