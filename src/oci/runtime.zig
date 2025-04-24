const std = @import("std");
const json = std.json;
const fs = std.fs;
const os = std.os;
const memory = std.mem;
const Allocator = memory.Allocator;
const proxmox = @import("proxmox");
const spec = @import("spec.zig");
const types = @import("types");
const errors = @import("error");
const log = @import("log");

const logger = std.log.scoped(.oci_runtime);

pub const RuntimeError = error{
    ConfigurationError,
    ContainerNotFound,
    ContainerAlreadyExists,
    ResourceAllocationFailed,
    NetworkSetupFailed,
    StorageSetupFailed,
    ProxmoxError,
    InvalidContainerName,
    InvalidContainerImage,
    InvalidContainerState,
};

pub const State = struct {
    ociVersion: []const u8,
    id: []const u8,
    status: []const u8,
    pid: i32,
    bundle: []const u8,
    annotations: std.StringHashMap([]const u8),

    pub fn init(allocator: Allocator) State {
        return State{
            .ociVersion = "1.0.0",
            .id = "",
            .status = "created",
            .pid = 0,
            .bundle = "",
            .annotations = std.StringHashMap([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *State) void {
        self.annotations.deinit();
    }
};

pub const Runtime = struct {
    allocator: Allocator,
    state: State,
    proxmox_client: *proxmox.ProxmoxClient,

    pub fn init(allocator: Allocator, proxmox_client: *proxmox.ProxmoxClient) Runtime {
        return Runtime{
            .allocator = allocator,
            .state = State.init(allocator),
            .proxmox_client = proxmox_client,
        };
    }

    pub fn deinit(self: *Runtime) void {
        self.state.deinit();
    }

    pub fn create(self: *Runtime, id: []const u8, bundle: []const u8) !void {
        // Перевіряємо чи контейнер вже існує
        const containers = try self.proxmox_client.listLXCs();
        defer self.allocator.free(containers);

        for (containers) |container| {
            if (std.mem.eql(u8, container.name, id)) {
                return RuntimeError.ContainerAlreadyExists;
            }
        }

        // Читаємо та парсимо конфігурацію OCI
        const config_path = try std.fs.path.join(self.allocator, &[_][]const u8{ bundle, "config.json" });
        defer self.allocator.free(config_path);

        const config_file = try std.fs.openFileAbsolute(config_path, .{});
        defer config_file.close();

        const config_content = try config_file.readToEndAlloc(self.allocator, 1024 * 1024);
        defer self.allocator.free(config_content);

        var parsed = try std.json.parseFromSlice(spec.Spec, self.allocator, config_content, .{
            .ignore_unknown_fields = true,
            .allocate = true,
        });
        defer parsed.deinit();

        const config = parsed.value;

        // Конвертуємо OCI spec в Proxmox LXC конфігурацію
        _ = try self.proxmox_client.createLXC(.{
            .hostname = config.hostname,
            .memory = if (config.linux.resources) |res| 
                if (res.memory) |memory_res| memory_res.limit orelse 512 * 1024 * 1024 else 512 * 1024 * 1024 
            else 512 * 1024 * 1024,
            .cores = if (config.linux.resources) |res|
                if (res.cpu) |cpu| @intCast(cpu.quota orelse 1) else 1
            else 1,
            .rootfs = .{
                .storage = try self.getStorageFromConfig(config),
                .size = 8 * 1024 * 1024 * 1024, // 8GB default
            },
            .network = .{
                .name = "vmbr50",
                .bridge = true,
                .firewall = true,
            },
        }) catch |err| {
            return switch (err) {
                errors.ProxmoxError => RuntimeError.ProxmoxError,
                else => RuntimeError.ResourceAllocationFailed,
            };
        };

        // Налаштовуємо seccomp якщо вказано
        if (config.linux.seccomp) |seccomp| {
            try self.setupSeccomp(id, seccomp) catch |err| {
                logger.err("Failed to setup seccomp: {}", .{err});
                // Видаляємо контейнер якщо не вдалося налаштувати seccomp
                _ = try self.proxmox_client.deleteContainer(id);
                return RuntimeError.ConfigurationError;
            };
        }

        // Оновлюємо стан
        self.state.id = try self.allocator.dupe(u8, id);
        self.state.bundle = try self.allocator.dupe(u8, bundle);
        self.state.status = "created";
    }

    pub fn start(self: *Runtime, id: []const u8) !void {
        if (!std.mem.eql(u8, self.state.id, id)) {
            return RuntimeError.ContainerNotFound;
        }

        try self.proxmox_client.startContainer(id) catch |err| {
            return switch (err) {
                errors.ProxmoxError => RuntimeError.ProxmoxError,
                else => RuntimeError.ResourceAllocationFailed,
            };
        };

        self.state.status = "running";
    }

    pub fn state(self: *Runtime, id: []const u8) !State {
        if (!std.mem.eql(u8, self.state.id, id)) {
            return RuntimeError.ContainerNotFound;
        }

        const status = try self.proxmox_client.getLXCStatus(id) catch |err| {
            return switch (err) {
                errors.ProxmoxError => RuntimeError.ProxmoxError,
                else => RuntimeError.ContainerNotFound,
            };
        };

        self.state.status = switch (status) {
            .running => "running",
            .stopped => "stopped",
            .paused => "paused",
            .unknown => "unknown",
        };

        return self.state;
    }

    pub fn kill(self: *Runtime, id: []const u8, signal: i32) !void {
        _ = signal; // Ігноруємо signal, оскільки Proxmox API не підтримує різні сигнали
        if (!std.mem.eql(u8, self.state.id, id)) {
            return RuntimeError.ContainerNotFound;
        }

        try self.proxmox_client.stopContainer(id) catch |err| {
            return switch (err) {
                errors.ProxmoxError => RuntimeError.ProxmoxError,
                else => RuntimeError.ResourceAllocationFailed,
            };
        };

        self.state.status = "stopped";
    }

    pub fn delete(self: *Runtime, id: []const u8) !void {
        if (!std.mem.eql(u8, self.state.id, id)) {
            return RuntimeError.ContainerNotFound;
        }

        try self.proxmox_client.deleteContainer(id) catch |err| {
            return switch (err) {
                errors.ProxmoxError => RuntimeError.ProxmoxError,
                else => RuntimeError.ResourceAllocationFailed,
            };
        };

        self.state.id = "";
        self.state.bundle = "";
        self.state.status = "stopped";
    }

    fn getStorageFromConfig(self: *Runtime, config: spec.Spec) ![]const u8 {
        // Спочатку перевіряємо анотації
        if (config.annotations.get("proxmox.storage")) |storage| {
            return try self.allocator.dupe(u8, storage);
        }

        // Перевіряємо тип монтування root
        for (config.mounts) |mount| {
            if (std.mem.eql(u8, mount.destination, "/")) {
                if (std.mem.startsWith(u8, mount.source, "zfs:")) {
                    return "zfs";
                } else if (std.mem.startsWith(u8, mount.source, "dir:")) {
                    return "local";
                }
            }
        }

        // За замовчуванням використовуємо local
        return "local";
    }

    fn setupSeccomp(self: *Runtime, container_id: []const u8, seccomp: spec.Seccomp) !void {
        logger.info("Setting up seccomp for container {s}", .{container_id});

        // Створюємо тимчасовий файл для профілю seccomp
        _ = try std.fs.openDirAbsolute("/tmp", .{});
        const profile_path = try std.fmt.allocPrint(
            self.allocator,
            "/tmp/seccomp_{s}.json",
            .{container_id}
        );
        defer self.allocator.free(profile_path);

        // Створюємо профіль
        var profile = std.ArrayList(u8).init(self.allocator);
        defer profile.deinit();

        try std.json.stringify(seccomp, .{}, profile.writer());

        // Записуємо профіль у файл
        try std.fs.cwd().writeFile(profile_path, profile.items);
        defer std.fs.deleteFileAbsolute(profile_path) catch {};

        // Застосовуємо профіль до контейнера
        try self.proxmox_client.setLXCSeccomp(container_id, profile_path);

        logger.info("Seccomp profile applied successfully", .{});
    }
};

/// OCI Runtime реалізація
pub const OciRuntime = struct {
    allocator: Allocator,
    pod_manager: *pod.PodManager,

    const Self = @This();

    pub fn init(allocator: Allocator, pod_manager: *pod.PodManager) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        self.* = .{
            .allocator = allocator,
            .pod_manager = pod_manager,
        };

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.destroy(self);
    }

    /// Створює новий контейнер
    pub fn createContainer(self: *Self, config: types.ContainerConfig) !types.Container {
        logger.info("Creating container with name: {s}", .{config.name});

        // Перевіряємо конфігурацію
        try self.validateConfig(config);

        // Створюємо контейнер через pod manager
        const container = try self.pod_manager.createContainer(config);
        
        logger.info("Container created successfully: {s}", .{container.id});
        return container;
    }

    /// Видаляє контейнер
    pub fn deleteContainer(self: *Self, container_id: []const u8) !void {
        logger.info("Deleting container: {s}", .{container_id});

        try self.pod_manager.deleteContainer(container_id);
        
        logger.info("Container deleted successfully: {s}", .{container_id});
    }

    /// Запускає контейнер
    pub fn startContainer(self: *Self, container_id: []const u8) !void {
        logger.info("Starting container: {s}", .{container_id});

        try self.pod_manager.startContainer(container_id);
        
        logger.info("Container started successfully: {s}", .{container_id});
    }

    /// Зупиняє контейнер
    pub fn stopContainer(self: *Self, container_id: []const u8, timeout: i64) !void {
        logger.info("Stopping container: {s} with timeout: {d}s", .{container_id, timeout});

        try self.pod_manager.stopContainer(container_id, timeout);
        
        logger.info("Container stopped successfully: {s}", .{container_id});
    }

    /// Перевіряє конфігурацію контейнера
    fn validateConfig(self: *Self, config: types.ContainerConfig) !void {
        _ = self;
        
        if (config.name.len == 0) {
            logger.err("Container name is empty", .{});
            return errors.InvalidContainerName;
        }

        if (config.image.len == 0) {
            logger.err("Container image is not specified", .{});
            return errors.InvalidContainerImage;
        }

        // TODO: Додати більше перевірок конфігурації OCI
    }
}; 