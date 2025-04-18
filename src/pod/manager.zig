const std = @import("std");
const types = @import("../types/pod.zig");
const proxmox = @import("../proxmox/client.zig");
const network = @import("../network/manager.zig");
const image = @import("image.zig");

pub const PodManager = struct {
    const Self = @This();
    
    allocator: std.mem.Allocator,
    pods: std.StringHashMap(*Pod),
    proxmox_client: *proxmox.Client,
    network_manager: *network.NetworkManager,
    image_manager: *image.ImageManager,

    pub fn init(
        allocator: std.mem.Allocator,
        proxmox_client: *proxmox.Client,
        network_manager: *network.NetworkManager,
        storage_path: []const u8,
    ) !Self {
        const image_manager = try image.ImageManager.init(allocator, proxmox_client, storage_path);
        errdefer image_manager.deinit();

        return Self{
            .allocator = allocator,
            .pods = std.StringHashMap(*Pod).init(allocator),
            .proxmox_client = proxmox_client,
            .network_manager = network_manager,
            .image_manager = image_manager,
        };
    }

    pub fn deinit(self: *Self) void {
        var it = self.pods.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.*.deinit();
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.pods.deinit();
        self.image_manager.deinit();
    }

    pub fn createPod(self: *Self, config: types.PodConfig) !*Pod {
        if (self.pods.get(config.id)) |_| {
            return error.PodAlreadyExists;
        }

        var pod = try self.allocator.create(Pod);
        errdefer self.allocator.destroy(pod);

        // Підготовка образу для LXC
        const image_config = image.ImageConfig{
            .path = config.image.path,
            .format = if (config.storage.type == .zfs) .zfs else .raw,
            .size = config.storage.size,
            .fs_type = config.image.fs_type,
            .mount_options = config.image.mount_options,
        };

        // Завантажуємо та підготовлюємо образ
        const prepared_image = try self.image_manager.prepareImage(
            config.image.url,
            image_config,
        );
        errdefer self.allocator.free(prepared_image);

        // Створюємо директорію для монтування
        const mount_point = try std.fmt.allocPrint(
            self.allocator,
            "/var/lib/lxc/{s}/rootfs",
            .{config.id},
        );
        errdefer self.allocator.free(mount_point);

        try std.fs.makeDirAbsolute(mount_point);
        errdefer std.fs.deleteTreeAbsolute(mount_point) catch {};

        // Монтуємо образ
        try self.image_manager.mountImage(prepared_image, mount_point, image_config);

        // Створюємо LXC контейнер через Proxmox API
        try self.proxmox_client.createContainer(.{
            .vmid = config.id,
            .hostname = config.name,
            .memory = config.resources.memory.limit,
            .swap = config.resources.memory.reservation,
            .cores = config.resources.cpu.cores,
            .cpulimit = config.resources.cpu.limit,
            .rootfs = .{
                .storage = if (config.storage.type == .zfs) "zfs" else "dir",
                .path = mount_point,
                .size = config.storage.size,
            },
            .network = switch (config.network.mode) {
                .bridge => .{
                    .name = "vmbr0",
                    .bridge = true,
                    .firewall = true,
                },
                .host => .{
                    .name = "host",
                    .type = "veth",
                },
                .none => null,
            },
            .dns = .{
                .servers = config.network.dns.servers,
                .search = config.network.dns.search,
            },
        }) catch |err| {
            return switch (err) {
                error.ProxmoxError => error.PodCreationFailed,
                else => err,
            };
        };

        pod.* = try Pod.init(self.allocator, config, self.proxmox_client, self.network_manager);
        errdefer pod.deinit();

        try self.pods.put(config.id, pod);
        return pod;
    }

    pub fn deletePod(self: *Self, id: []const u8) !void {
        const pod = self.pods.get(id) orelse return error.PodNotFound;
        try pod.stop();
        try pod.cleanup();
        
        // Видаляємо LXC контейнер через Proxmox API
        try self.proxmox_client.deleteContainer(id) catch |err| {
            return switch (err) {
                error.ProxmoxError => error.PodDeletionFailed,
                else => err,
            };
        };
        
        pod.deinit();
        self.allocator.destroy(pod);
        _ = self.pods.remove(id);
    }

    pub fn getPod(self: *Self, id: []const u8) ?*Pod {
        return self.pods.get(id);
    }

    pub fn listPods(self: *Self) ![]const *Pod {
        var pods = std.ArrayList(*Pod).init(self.allocator);
        errdefer pods.deinit();

        // Отримуємо список всіх LXC контейнерів через Proxmox API
        const containers = try self.proxmox_client.listContainers() catch |err| {
            return switch (err) {
                error.ProxmoxError => error.PodListFailed,
                else => err,
            };
        };

        for (containers) |container| {
            if (self.pods.get(container.vmid)) |pod| {
                try pods.append(pod);
            }
        }

        return pods.toOwnedSlice();
    }
};

pub const Pod = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    config: types.PodConfig,
    proxmox_client: *proxmox.Client,
    network_manager: *network.NetworkManager,
    state: PodState,

    pub fn init(allocator: std.mem.Allocator, config: types.PodConfig, proxmox_client: *proxmox.Client, network_manager: *network.NetworkManager) !Self {
        return Self{
            .allocator = allocator,
            .config = config,
            .proxmox_client = proxmox_client,
            .network_manager = network_manager,
            .state = .Created,
        };
    }

    pub fn deinit(self: *Self) void {
        // Звільняємо ресурси конфігурації
        for (self.config.network.dns.servers) |server| {
            self.allocator.free(server);
        }
        for (self.config.network.dns.search) |domain| {
            self.allocator.free(domain);
        }
    }

    pub fn start(self: *Self) !void {
        if (self.state != .Created and self.state != .Stopped) {
            return error.InvalidState;
        }

        // Запускаємо LXC контейнер через Proxmox API
        try self.proxmox_client.startContainer(self.config.id) catch |err| {
            return switch (err) {
                error.ProxmoxError => error.PodStartFailed,
                else => err,
            };
        };

        // Налаштовуємо мережу якщо потрібно
        if (self.config.network.mode != .none) {
            for (self.config.network.port_mappings) |mapping| {
                try self.proxmox_client.addPortForward(self.config.id, .{
                    .proto = mapping.protocol,
                    .dport = mapping.host_port,
                    .dip = mapping.host_ip orelse "0.0.0.0",
                    .sport = mapping.container_port,
                }) catch |err| {
                    return switch (err) {
                        error.ProxmoxError => error.NetworkSetupFailed,
                        else => err,
                    };
                };
            }
        }

        self.state = .Running;
    }

    pub fn stop(self: *Self) !void {
        if (self.state != .Running) {
            return error.InvalidState;
        }

        // Зупиняємо LXC контейнер через Proxmox API
        try self.proxmox_client.stopContainer(self.config.id) catch |err| {
            return switch (err) {
                error.ProxmoxError => error.PodStopFailed,
                else => err,
            };
        };

        self.state = .Stopped;
    }

    pub fn cleanup(self: *Self) !void {
        if (self.state == .Running) {
            return error.PodStillRunning;
        }

        // Видаляємо налаштування мережі
        if (self.config.network.mode != .none) {
            for (self.config.network.port_mappings) |mapping| {
                try self.proxmox_client.removePortForward(self.config.id, .{
                    .proto = mapping.protocol,
                    .dport = mapping.host_port,
                }) catch |err| {
                    return switch (err) {
                        error.ProxmoxError => error.NetworkCleanupFailed,
                        else => err,
                    };
                };
            }
        }

        self.state = .Deleted;
    }

    pub fn updateResources(self: *Self, resources: types.ResourceConfig) !void {
        // Оновлюємо ресурси LXC контейнера через Proxmox API
        try self.proxmox_client.updateContainer(self.config.id, .{
            .memory = resources.memory.limit,
            .swap = resources.memory.reservation,
            .cores = resources.cpu.cores,
            .cpulimit = resources.cpu.limit,
        }) catch |err| {
            return switch (err) {
                error.ProxmoxError => error.ResourceUpdateFailed,
                else => err,
            };
        };

        self.config.resources = resources;
    }
};

pub const PodState = enum {
    Created,
    Running,
    Stopped,
    Deleted,
};

pub const PodError = error{
    PodCreationFailed,
    PodDeletionFailed,
    PodStartFailed,
    PodStopFailed,
    PodListFailed,
    NetworkSetupFailed,
    NetworkCleanupFailed,
    ResourceUpdateFailed,
    PodAlreadyExists,
    PodNotFound,
    PodStillRunning,
    InvalidState,
}; 