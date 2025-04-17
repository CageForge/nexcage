const std = @import("std");
const types = @import("../../types.zig");
const Client = @import("../../proxmox/client.zig").Client;
const proxmox_ops = @import("../../proxmox/lxc/operations.zig");
const fmt = std.fmt;

pub const RuntimeError = error{
    ContainerNotFound,
    ContainerAlreadyExists,
    InvalidContainerState,
    ProxmoxError,
    NetworkError,
    ConfigurationError,
    InvalidContainerId,
};

pub const RuntimeService = struct {
    client: *Client,
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, client: *Client) Self {
        return Self{
            .client = client,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    // Version returns the runtime name, runtime version, and runtime API version.
    pub fn Version(self: *Self, apiVersion: []const u8) !struct {
        version: []const u8,
        runtime_name: []const u8,
        runtime_version: []const u8,
        runtime_api_version: []const u8,
    } {
        _ = self;
        return .{
            .version = try self.allocator.dupe(u8, "0.1.0"),
            .runtime_name = try self.allocator.dupe(u8, "proxmox-lxcri"),
            .runtime_version = try self.allocator.dupe(u8, "0.1.0"),
            .runtime_api_version = try self.allocator.dupe(u8, apiVersion),
        };
    }

    // CreateContainer creates a new container.
    pub fn CreateContainer(self: *Self, pod_id: []const u8, config: types.ContainerConfig) !types.Container {
        try self.client.logger.info("Creating container for pod {s} with name {s}", .{pod_id, config.metadata.name});

        // Конвертуємо CRI конфігурацію в Proxmox LXC конфігурацію
        var lxc_config = types.LXCConfig{
            .hostname = try self.allocator.dupe(u8, config.metadata.name),
            .ostype = try self.allocator.dupe(u8, "ubuntu"), // За замовчуванням використовуємо Ubuntu
            .memory = if (config.linux.resources) |res| 
                if (res.memory_limit_bytes) |mem| 
                    @intCast(@divFloor(mem, 1024 * 1024)) // Конвертуємо байти в MB
                else 512 
            else 512,
            .swap = 0, // Вимикаємо swap за замовчуванням
            .cores = if (config.linux.resources) |res|
                if (res.cpu_shares) |cpu| 
                    @intCast(cpu)
                else 1
            else 1,
            .rootfs = try self.allocator.dupe(u8, "local:vztmpl/ubuntu-22.04-standard_22.04-1_amd64.tar.zst"),
            .net0 = .{
                .name = try self.allocator.dupe(u8, "eth0"),
                .bridge = try self.allocator.dupe(u8, "vmbr0"),
                .ip = try self.allocator.dupe(u8, "dhcp"),
                .type = try self.allocator.dupe(u8, "veth"),
            },
            .onboot = true,
            .unprivileged = if (config.linux.security_context) |ctx| 
                !ctx.privileged
            else true,
        };
        errdefer lxc_config.deinit(self.allocator);

        // Додаємо точки монтування
        if (config.mounts.len > 0) {
            for (config.mounts, 0..) |mount, i| {
                const mp = types.MountPoint{
                    .volume = try self.allocator.dupe(u8, mount.host_path),
                    .mp = try self.allocator.dupe(u8, mount.container_path),
                    .size = try self.allocator.dupe(u8, "8G"),
                    .acl = false,
                    .backup = true,
                    .quota = true,
                    .replicate = true,
                    .shared = false,
                };

                switch (i) {
                    0 => lxc_config.mp0 = mp,
                    1 => lxc_config.mp1 = mp,
                    2 => lxc_config.mp2 = mp,
                    3 => lxc_config.mp3 = mp,
                    4 => lxc_config.mp4 = mp,
                    5 => lxc_config.mp5 = mp,
                    6 => lxc_config.mp6 = mp,
                    7 => lxc_config.mp7 = mp,
                    else => {
                        try self.client.logger.warn("Ignoring mount point {s}, maximum 8 mount points supported", .{mount.container_path});
                        break;
                    },
                }
            }
        }

        // Створюємо контейнер через Proxmox API
        const lxc = try proxmox_ops.createLXC(self.client, lxc_config);
        
        // Конвертуємо Proxmox LXC в CRI Container
        return types.Container{
            .id = try fmt.allocPrint(self.allocator, "{d}", .{lxc.vmid}),
            .name = try self.allocator.dupe(u8, config.metadata.name),
            .status = .created,
            .spec = config,
        };
    }

    // StartContainer starts the container.
    pub fn StartContainer(self: *Self, container_id: []const u8) !void {
        try self.client.logger.info("Starting container {s}", .{container_id});

        // Конвертуємо container_id в VMID
        const vmid = std.fmt.parseInt(u32, container_id, 10) catch {
            try self.client.logger.err("Invalid container ID format: {s}", .{container_id});
            return error.InvalidContainerId;
        };

        // Перевіряємо поточний стан контейнера
        const status = proxmox_ops.getLXCStatus(self.client, self.client.node, vmid) catch |err| {
            try self.client.logger.err("Failed to get container status: {}", .{err});
            return error.ContainerNotFound;
        };

        // Перевіряємо чи контейнер не запущений
        if (status == .running) {
            try self.client.logger.warn("Container {s} is already running", .{container_id});
            return;
        }

        // Запускаємо контейнер
        try proxmox_ops.startLXC(self.client, self.client.node, vmid);
    }

    // StopContainer stops a running container with a grace period (i.e., timeout).
    pub fn StopContainer(self: *Self, container_id: []const u8, timeout: i64) !void {
        try self.client.logger.info("Stopping container {s} with timeout {d}", .{container_id, timeout});

        // Конвертуємо container_id в VMID
        const vmid = std.fmt.parseInt(u32, container_id, 10) catch {
            try self.client.logger.err("Invalid container ID format: {s}", .{container_id});
            return error.InvalidContainerId;
        };

        // Перевіряємо поточний стан контейнера
        const status = proxmox_ops.getLXCStatus(self.client, self.client.node, vmid) catch |err| {
            try self.client.logger.err("Failed to get container status: {}", .{err});
            return error.ContainerNotFound;
        };

        // Перевіряємо чи контейнер не зупинений
        if (status == .stopped) {
            try self.client.logger.warn("Container {s} is already stopped", .{container_id});
            return;
        }

        // Зупиняємо контейнер
        try proxmox_ops.stopLXC(self.client, self.client.node, vmid, timeout);
    }

    // RemoveContainer removes the container.
    pub fn RemoveContainer(self: *Self, container_id: []const u8) !void {
        try self.client.logger.info("Removing container {s}", .{container_id});

        // Конвертуємо container_id в VMID
        const vmid = std.fmt.parseInt(u32, container_id, 10) catch {
            try self.client.logger.err("Invalid container ID format: {s}", .{container_id});
            return error.InvalidContainerId;
        };

        // Перевіряємо поточний стан контейнера
        const status = proxmox_ops.getLXCStatus(self.client, self.client.node, vmid) catch |err| {
            try self.client.logger.err("Failed to get container status: {}", .{err});
            return error.ContainerNotFound;
        };

        // Перевіряємо чи контейнер не запущений
        if (status == .running) {
            try self.client.logger.warn("Container {s} is still running, stopping it first", .{container_id});
            try proxmox_ops.stopLXC(self.client, self.client.node, vmid, 30); // Даємо 30 секунд на зупинку
        }

        // Видаляємо контейнер
        try proxmox_ops.deleteLXC(self.client, self.client.node, vmid);
    }

    // ListContainers lists all containers by filters.
    pub fn ListContainers(self: *Self, filter: ?types.ContainerFilter) ![]types.Container {
        _ = self;
        _ = filter;
        return error.NotImplemented;
    }

    // ContainerStatus returns the status of the container.
    pub fn ContainerStatus(self: *Self, container_id: []const u8) !types.ContainerStatus {
        _ = self;
        _ = container_id;
        return error.NotImplemented;
    }

    // UpdateContainerResources updates ContainerConfig of the container.
    pub fn UpdateContainerResources(self: *Self, container_id: []const u8, resources: types.ContainerResources) !void {
        _ = self;
        _ = container_id;
        _ = resources;
        return error.NotImplemented;
    }

    // ExecSync runs a command in a container synchronously.
    pub fn ExecSync(self: *Self, container_id: []const u8, cmd: []const []const u8, timeout: i64) !struct {
        stdout: []const u8,
        stderr: []const u8,
        exit_code: i32,
    } {
        _ = self;
        _ = container_id;
        _ = cmd;
        _ = timeout;
        return error.NotImplemented;
    }
}; 