const std = @import("std");
const Allocator = std.mem.Allocator;
const logger = std.log.scoped(.pod);
const json = std.json;
const oci = @import("../oci/spec.zig");
const net = @import("network");
const proxmox = @import("../proxmox/api.zig");
const ProxmoxContainer = @import("../proxmox/lxc/container.zig").ProxmoxContainer;

pub const PodError = error{
    CreationFailed,
    StartFailed,
    StopFailed,
    DeleteFailed,
    NetworkSetupFailed,
    ContainerError,
    InvalidSpec,
};

pub const PodHook = struct {
    path: []const u8,
    args: ?[][]const u8 = null,
    env: ?[][]const u8 = null,
    timeout: ?i64 = null,
};

pub const PodHooks = struct {
    prestart: ?[]PodHook = null,
    poststart: ?[]PodHook = null,
    poststop: ?[]PodHook = null,
};

pub const Mount = struct {
    source: []const u8,
    destination: []const u8,
    type: []const u8,
    options: ?[][]const u8 = null,
};

pub const PodResources = struct {
    memory: ?struct {
        limit: ?u64 = null,
        swap: ?u64 = null,
    } = null,
    cpu: ?struct {
        shares: ?u64 = null,
        quota: ?i64 = null,
        period: ?u64 = null,
        cpus: ?[]const u8 = null,
    } = null,
    blockio: ?struct {
        weight: ?u16 = null,
        weightDevice: ?[]struct {
            major: i64,
            minor: i64,
            weight: ?u16,
        } = null,
    } = null,
    hugepages: ?[]struct {
        pageSize: u64,
        limit: u64,
    } = null,
    network: ?struct {
        classID: ?u32 = null,
        priorities: ?[]struct {
            name: []const u8,
            priority: u32,
        } = null,
    } = null,
    pids: ?struct {
        limit: i64,
    } = null,

    pub fn fromLinuxResources(allocator: Allocator, resources: oci.LinuxResources) !PodResources {
        var pod_resources = PodResources{};

        if (resources.memory) |memory| {
            pod_resources.memory = .{
                .limit = memory.limit,
                .swap = memory.swap,
            };
        }

        if (resources.cpu) |cpu| {
            pod_resources.cpu = .{
                .shares = cpu.shares,
                .quota = cpu.quota,
                .period = cpu.period,
                .cpus = if (cpu.cpus) |cpus| try allocator.dupe(u8, cpus) else null,
            };
        }

        if (resources.blockIO) |blockio| {
            pod_resources.blockio = .{
                .weight = blockio.weight,
                .weightDevice = if (blockio.weightDevice) |devices| blk: {
                    var weight_devices = try allocator.alloc(
                        @TypeOf(pod_resources.blockio.?.weightDevice.?[0]),
                        devices.len
                    );
                    for (devices, 0..) |device, i| {
                        weight_devices[i] = .{
                            .major = device.major,
                            .minor = device.minor,
                            .weight = device.weight,
                        };
                    }
                    break :blk weight_devices;
                } else null,
            };
        }

        if (resources.hugepageLimits) |hugepages| {
            pod_resources.hugepages = try allocator.alloc(
                @TypeOf(pod_resources.hugepages.?[0]),
                hugepages.len
            );
            for (hugepages, 0..) |page, i| {
                pod_resources.hugepages.?[i] = .{
                    .pageSize = page.pageSize,
                    .limit = page.limit,
                };
            }
        }

        if (resources.network) |net_resources| {
            pod_resources.network = .{
                .classID = net_resources.classID,
                .priorities = if (net_resources.priorities) |priorities| blk: {
                    var net_priorities = try allocator.alloc(
                        @TypeOf(pod_resources.network.?.priorities.?[0]),
                        priorities.len
                    );
                    for (priorities, 0..) |priority, i| {
                        net_priorities[i] = .{
                            .name = try allocator.dupe(u8, priority.name),
                            .priority = priority.priority,
                        };
                    }
                    break :blk net_priorities;
                } else null,
            };
        }

        if (resources.pids) |pids| {
            pod_resources.pids = .{
                .limit = pids.limit,
            };
        }

        return pod_resources;
    }

    pub fn deinit(self: *PodResources, allocator: Allocator) void {
        if (self.cpu) |cpu| {
            if (cpu.cpus) |cpus| {
                allocator.free(cpus);
            }
        }

        if (self.blockio) |blockio| {
            if (blockio.weightDevice) |devices| {
                allocator.free(devices);
            }
        }

        if (self.hugepages) |hugepages| {
            allocator.free(hugepages);
        }

        if (self.network) |net_config| {
            if (net_config.priorities) |priorities| {
                for (priorities) |priority| {
                    allocator.free(priority.name);
                }
                allocator.free(priorities);
            }
        }
    }
};

pub const PodSpec = struct {
    version: []const u8 = "1.0.0",
    metadata: struct {
        name: []const u8,
        namespace: []const u8,
        uid: []const u8,
        labels: std.StringHashMap([]const u8),
        annotations: std.StringHashMap([]const u8),
    },
    linux: struct {
        cgroups_path: ?[]const u8 = null,
        resources: ?PodResources = null,
        namespaces: []oci.LinuxNamespace,
        devices: ?[]oci.LinuxDevice = null,
        sysctl: ?std.StringHashMap([]const u8) = null,
    },
    hooks: ?PodHooks = null,
    mounts: ?[]Mount = null,
    containers: []oci.Spec,

    pub fn validateSpec(self: *const PodSpec) !void {
        // Перевіряємо версію
        if (!std.mem.eql(u8, self.version, "1.0.0")) {
            logger.err("Unsupported spec version: {s}", .{self.version});
            return PodError.InvalidSpec;
        }

        // Перевіряємо обов'язкові поля
        if (self.metadata.name.len == 0) {
            logger.err("Pod name is required", .{});
            return PodError.InvalidSpec;
        }

        if (self.containers.len == 0) {
            logger.err("At least one container is required", .{});
            return PodError.InvalidSpec;
        }

        // Перевіряємо монтування
        if (self.mounts) |mounts| {
            for (mounts) |mount| {
                if (mount.source.len == 0 or mount.destination.len == 0) {
                    logger.err("Mount source and destination are required", .{});
                    return PodError.InvalidSpec;
                }
            }
        }

        // Перевіряємо хуки
        if (self.hooks) |hooks| {
            if (hooks.prestart) |prestart| {
                for (prestart) |hook| {
                    if (hook.path.len == 0) {
                        logger.err("Hook path is required", .{});
                        return PodError.InvalidSpec;
                    }
                }
            }
        }
    }
};

pub const Pod = struct {
    spec: PodSpec,
    containers: std.ArrayList(*ProxmoxContainer),
    network_manager: *net.NetworkManager,
    proxmox_api: *proxmox.ProxmoxApi,
    allocator: Allocator,

    const Self = @This();

    pub fn init(allocator: Allocator, spec: PodSpec, proxmox_config: proxmox.ProxmoxConfig) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        // Створюємо API клієнт
        var api = try allocator.create(proxmox.ProxmoxApi);
        api.* = proxmox.ProxmoxApi.init(allocator, proxmox_config);
        errdefer api.deinit();

        // Створюємо мережевий менеджер
        var net_manager = try allocator.create(net.NetworkManager);
        net_manager.* = net.NetworkManager.init(allocator);
        errdefer net_manager.deinit();

        self.* = .{
            .spec = spec,
            .containers = std.ArrayList(*ProxmoxContainer).init(allocator),
            .network_manager = net_manager,
            .proxmox_api = api,
            .allocator = allocator,
        };

        return self;
    }

    pub fn deinit(self: *Self) void {
        // Очищуємо контейнери
        for (self.containers.items) |container| {
            container.deinit();
        }
        self.containers.deinit();

        // Очищуємо мережу
        self.network_manager.deinit();
        self.allocator.destroy(self.network_manager);

        // Очищуємо Proxmox API
        self.proxmox_api.deinit();
        self.allocator.destroy(self.proxmox_api);

        // Очищуємо метадані
        self.spec.metadata.labels.deinit();
        self.spec.metadata.annotations.deinit();

        self.allocator.destroy(self);
    }

    pub fn create(self: *Self) !void {
        logger.info("Creating pod {s} in namespace {s}", .{ self.spec.metadata.name, self.spec.metadata.namespace });

        // Валідуємо специфікацію
        try self.spec.validateSpec();

        // Виконуємо prestart хуки
        if (self.spec.hooks) |hooks| {
            if (hooks.prestart) |prestart| {
                try self.executeHooks(prestart);
            }
        }

        // Налаштовуємо мережу для поду
        const network_config = try self.network_manager.createNetwork(self.spec.metadata.name);
        errdefer network_config.deinit();

        // Створюємо контейнери
        var vmid: u32 = 100; // Початковий VMID
        for (self.spec.containers) |container_spec| {
            const container = try ProxmoxContainer.create(
                self.allocator,
                container_spec.hostname orelse self.spec.metadata.name,
                self.proxmox_api,
                "pve", // Ім'я ноди Proxmox
                vmid
            );
            errdefer container.deinit();

            // Налаштовуємо монтування
            if (self.spec.mounts) |mounts| {
                try self.setupMounts(container, mounts);
            }

            try container.configure(&container_spec);
            try self.containers.append(container);
            vmid += 1;
        }

        // Виконуємо poststart хуки
        if (self.spec.hooks) |hooks| {
            if (hooks.poststart) |poststart| {
                try self.executeHooks(poststart);
            }
        }

        logger.info("Pod created successfully", .{});
    }

    fn executeHooks(self: *Self, hooks: []PodHook) !void {
        for (hooks) |hook| {
            logger.info("Executing hook: {s}", .{hook.path});

            var child = std.ChildProcess.init(
                &[_][]const u8{hook.path},
                self.allocator,
            );

            if (hook.args) |args| {
                child.argv = args;
            }

            if (hook.env) |env| {
                child.env = env;
            }

            // Встановлюємо таймаут, якщо вказано
            if (hook.timeout) |timeout| {
                child.timeout_ns = @intCast(timeout * std.time.ns_per_s);
            }

            const result = try child.spawnAndWait();
            if (result.term != .Exited or result.term.Exited != 0) {
                logger.err("Hook execution failed: {s}", .{hook.path});
                return PodError.CreationFailed;
            }
        }
    }

    fn setupMounts(self: *Self, container: *ProxmoxContainer, mounts: []Mount) !void {
        for (mounts) |mount| {
            logger.info("Setting up mount {s} -> {s}", .{ mount.source, mount.destination });

            // Перевіряємо чи існує джерело монтування
            const source_path = try std.fs.path.resolve(self.allocator, &[_][]const u8{mount.source});
            defer self.allocator.free(source_path);

            const stat = try std.fs.cwd().statFile(source_path);
            if (stat.kind == .Directory) {
                // Створюємо директорію призначення в контейнері
                try container.createDirectory(mount.destination);
            }

            // Налаштовуємо монтування в контейнері
            try container.addMount(mount.source, mount.destination, mount.type, mount.options);
        }
    }

    pub fn start(self: *Self) !void {
        logger.info("Starting pod {s}", .{self.spec.metadata.name});

        // Запускаємо всі контейнери
        for (self.containers.items) |container| {
            container.start() catch |err| {
                logger.err("Failed to start container: {}", .{err});
                return PodError.StartFailed;
            };
        }

        logger.info("Pod started successfully", .{});
    }

    pub fn stop(self: *Self) !void {
        logger.info("Stopping pod {s}", .{self.spec.metadata.name});

        // Виконуємо poststop хуки
        if (self.spec.hooks) |hooks| {
            if (hooks.poststop) |poststop| {
                try self.executeHooks(poststop);
            }
        }

        // Зупиняємо всі контейнери
        for (self.containers.items) |container| {
            container.stop() catch |err| {
                logger.err("Failed to stop container: {}", .{err});
                return PodError.StopFailed;
            };
        }

        logger.info("Pod stopped successfully", .{});
    }

    pub fn delete(self: *Self) !void {
        logger.info("Deleting pod {s}", .{self.spec.metadata.name});

        // Видаляємо всі контейнери
        for (self.containers.items) |container| {
            container.destroy() catch |err| {
                logger.err("Failed to delete container: {}", .{err});
                return PodError.DeleteFailed;
            };
        }

        // Видаляємо мережу поду
        self.network_manager.deleteNetwork(self.spec.metadata.name);

        logger.info("Pod deleted successfully", .{});
    }

    pub fn applyResources(self: *Self) !void {
        if (self.spec.linux.resources) |resources| {
            logger.info("Applying resource limits to pod {s}", .{self.spec.metadata.name});

            // Застосовуємо ліміти ресурсів до всіх контейнерів
            for (self.containers.items) |container| {
                // Оновлюємо конфігурацію контейнера через Proxmox API
                var config = try container.getConfig();
                if (resources.memory) |memory| {
                    if (memory.limit) |limit| {
                        config.memory = limit;
                    }
                    if (memory.swap) |swap| {
                        config.swap = swap;
                    }
                }
                if (resources.cpu) |cpu| {
                    if (cpu.shares) |shares| {
                        config.cpu_shares = shares;
                    }
                    if (cpu.quota) |quota| {
                        config.cpu_quota = quota;
                    }
                }
                try container.updateConfig(config);
            }
        }
    }

    pub fn shareNamespace(self: *Self, namespace_type: []const u8) !void {
        logger.info("Sharing {s} namespace in pod {s}", .{ namespace_type, self.spec.metadata.name });

        if (self.containers.items.len < 2) {
            return;
        }

        // Використовуємо перший контейнер як основний для спільного namespace
        const main_container = self.containers.items[0];
        const main_pid = try main_container.getPid();

        // Приєднуємо інші контейнери до namespace основного
        for (self.containers.items[1..]) |container| {
            try container.joinNamespace(namespace_type, main_pid);
        }
    }
}; 