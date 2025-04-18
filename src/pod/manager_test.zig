const std = @import("std");
const testing = std.testing;
const manager = @import("manager.zig");
const types = @import("../types/pod.zig");
const proxmox = @import("../proxmox/client.zig");
const network = @import("../network/manager.zig");

// Створюємо мок для Proxmox API клієнта
const MockProxmoxClient = struct {
    const Self = @This();
    
    allocator: std.mem.Allocator,
    containers: std.StringHashMap(Container),
    
    const Container = struct {
        vmid: []const u8,
        hostname: []const u8,
        state: enum { running, stopped, created },
        memory: u64,
        cores: u32,
    };
    
    pub fn init(allocator: std.mem.Allocator) !*Self {
        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .containers = std.StringHashMap(Container).init(allocator),
        };
        return self;
    }
    
    pub fn deinit(self: *Self) void {
        var it = self.containers.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.value_ptr.*.vmid);
            self.allocator.free(entry.value_ptr.*.hostname);
        }
        self.containers.deinit();
        self.allocator.destroy(self);
    }
    
    pub fn createContainer(self: *Self, config: proxmox.ContainerConfig) !void {
        const container = Container{
            .vmid = try self.allocator.dupe(u8, config.vmid),
            .hostname = try self.allocator.dupe(u8, config.hostname),
            .state = .created,
            .memory = config.memory,
            .cores = config.cores,
        };
        try self.containers.put(config.vmid, container);
    }
    
    pub fn deleteContainer(self: *Self, vmid: []const u8) !void {
        if (self.containers.fetchRemove(vmid)) |entry| {
            self.allocator.free(entry.value.vmid);
            self.allocator.free(entry.value.hostname);
        } else {
            return error.ProxmoxError;
        }
    }
    
    pub fn startContainer(self: *Self, vmid: []const u8) !void {
        if (self.containers.getPtr(vmid)) |container| {
            container.state = .running;
        } else {
            return error.ProxmoxError;
        }
    }
    
    pub fn stopContainer(self: *Self, vmid: []const u8) !void {
        if (self.containers.getPtr(vmid)) |container| {
            container.state = .stopped;
        } else {
            return error.ProxmoxError;
        }
    }
    
    pub fn listContainers(self: *Self) ![]Container {
        var containers = std.ArrayList(Container).init(self.allocator);
        var it = self.containers.iterator();
        while (it.next()) |entry| {
            try containers.append(entry.value_ptr.*);
        }
        return containers.toOwnedSlice();
    }
    
    pub fn updateContainer(self: *Self, vmid: []const u8, config: proxmox.ContainerUpdateConfig) !void {
        if (self.containers.getPtr(vmid)) |container| {
            container.memory = config.memory;
            container.cores = config.cores;
        } else {
            return error.ProxmoxError;
        }
    }
    
    pub fn addPortForward(self: *Self, vmid: []const u8, config: proxmox.PortForwardConfig) !void {
        _ = vmid;
        _ = config;
    }
    
    pub fn removePortForward(self: *Self, vmid: []const u8, config: proxmox.PortForwardConfig) !void {
        _ = vmid;
        _ = config;
    }
};

test "PodManager - basic lifecycle" {
    const allocator = testing.allocator;

    // Створюємо мок Proxmox клієнта
    var proxmox_client = try MockProxmoxClient.init(allocator);
    defer proxmox_client.deinit();

    var network_manager = try network.NetworkManager.init(allocator);
    defer network_manager.deinit();

    // Створюємо менеджер Pod-ів
    var pod_manager = try manager.PodManager.init(
        allocator,
        proxmox_client,
        &network_manager
    );
    defer pod_manager.deinit();

    // Створюємо тестову конфігурацію Pod-а
    const pod_config = types.PodConfig{
        .id = "100",
        .name = "test-pod",
        .namespace = "default",
        .network = .{
            .mode = .bridge,
            .dns = .{
                .servers = &[_][]const u8{"8.8.8.8"},
                .search = &[_][]const u8{},
                .options = &[_][]const u8{},
            },
            .port_mappings = &[_]types.PortMapping{
                .{
                    .protocol = .tcp,
                    .container_port = 80,
                    .host_port = 8080,
                    .host_ip = null,
                },
            },
        },
        .resources = .{
            .cpu = .{
                .cores = 2,
                .limit = 100,
            },
            .memory = .{
                .limit = 256 * 1024 * 1024,
                .reservation = 128 * 1024 * 1024,
            },
            .storage = .{
                .limit = 10 * 1024 * 1024 * 1024,
                .path = "/var/lib/lxc",
            },
        },
    };

    // Тестуємо створення Pod-а
    const pod = try pod_manager.createPod(pod_config);
    try testing.expect(pod.state == .Created);
    try testing.expectEqualStrings(pod.config.id, "100");

    // Перевіряємо що LXC контейнер створено
    try testing.expect(proxmox_client.containers.contains("100"));

    // Тестуємо отримання Pod-а
    const found_pod = pod_manager.getPod("100");
    try testing.expect(found_pod != null);
    try testing.expectEqualStrings(found_pod.?.config.id, "100");

    // Тестуємо запуск Pod-а
    try pod.start();
    try testing.expect(pod.state == .Running);

    // Перевіряємо що LXC контейнер запущено
    try testing.expect(proxmox_client.containers.get("100").?.state == .running);

    // Тестуємо зупинку Pod-а
    try pod.stop();
    try testing.expect(pod.state == .Stopped);

    // Перевіряємо що LXC контейнер зупинено
    try testing.expect(proxmox_client.containers.get("100").?.state == .stopped);

    // Тестуємо видалення Pod-а
    try pod_manager.deletePod("100");
    const deleted_pod = pod_manager.getPod("100");
    try testing.expect(deleted_pod == null);

    // Перевіряємо що LXC контейнер видалено
    try testing.expect(!proxmox_client.containers.contains("100"));
}

test "PodManager - error handling" {
    const allocator = testing.allocator;

    var proxmox_client = try MockProxmoxClient.init(allocator);
    defer proxmox_client.deinit();

    var network_manager = try network.NetworkManager.init(allocator);
    defer network_manager.deinit();

    var pod_manager = try manager.PodManager.init(
        allocator,
        proxmox_client,
        &network_manager
    );
    defer pod_manager.deinit();

    // Тестуємо помилку при створенні дубліката Pod-а
    const pod_config = types.PodConfig{
        .id = "101",
        .name = "duplicate-pod",
        .namespace = "default",
        .network = .{
            .mode = .none,
            .dns = .{
                .servers = &[_][]const u8{},
                .search = &[_][]const u8{},
                .options = &[_][]const u8{},
            },
            .port_mappings = &[_]types.PortMapping{},
        },
        .resources = .{
            .cpu = .{
                .cores = 1,
                .limit = 100,
            },
            .memory = .{
                .limit = 256 * 1024 * 1024,
                .reservation = 128 * 1024 * 1024,
            },
            .storage = .{
                .limit = 5 * 1024 * 1024 * 1024,
                .path = "/var/lib/lxc",
            },
        },
    };

    _ = try pod_manager.createPod(pod_config);
    try testing.expectError(error.PodAlreadyExists, pod_manager.createPod(pod_config));

    // Тестуємо помилку при видаленні неіснуючого Pod-а
    try testing.expectError(error.PodNotFound, pod_manager.deletePod("non-existent-pod"));

    // Тестуємо помилку при спробі очистити запущений Pod
    const pod = pod_manager.getPod("101").?;
    try pod.start();
    try testing.expectError(error.PodStillRunning, pod.cleanup());
}

test "PodManager - resource update" {
    const allocator = testing.allocator;

    var proxmox_client = try MockProxmoxClient.init(allocator);
    defer proxmox_client.deinit();

    var network_manager = try network.NetworkManager.init(allocator);
    defer network_manager.deinit();

    var pod_manager = try manager.PodManager.init(
        allocator,
        proxmox_client,
        &network_manager
    );
    defer pod_manager.deinit();

    // Створюємо Pod
    const pod_config = types.PodConfig{
        .id = "102",
        .name = "resource-test-pod",
        .namespace = "default",
        .network = .{
            .mode = .none,
            .dns = .{
                .servers = &[_][]const u8{},
                .search = &[_][]const u8{},
                .options = &[_][]const u8{},
            },
            .port_mappings = &[_]types.PortMapping{},
        },
        .resources = .{
            .cpu = .{
                .cores = 1,
                .limit = 100,
            },
            .memory = .{
                .limit = 256 * 1024 * 1024,
                .reservation = 128 * 1024 * 1024,
            },
            .storage = .{
                .limit = 5 * 1024 * 1024 * 1024,
                .path = "/var/lib/lxc",
            },
        },
    };

    const pod = try pod_manager.createPod(pod_config);

    // Оновлюємо ресурси
    const new_resources = types.ResourceConfig{
        .cpu = .{
            .cores = 2,
            .limit = 200,
        },
        .memory = .{
            .limit = 512 * 1024 * 1024,
            .reservation = 256 * 1024 * 1024,
        },
        .storage = .{
            .limit = 10 * 1024 * 1024 * 1024,
            .path = "/var/lib/lxc",
        },
    };

    try pod.updateResources(new_resources);

    // Перевіряємо що ресурси оновлено
    const container = proxmox_client.containers.get("102").?;
    try testing.expectEqual(container.cores, 2);
    try testing.expectEqual(container.memory, 512 * 1024 * 1024);
} 