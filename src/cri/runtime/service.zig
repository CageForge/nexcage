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
        try self.client.logger.info("Listing containers with filter: {?}", .{filter});

        // Get all LXC containers from Proxmox
        var containers = std.ArrayList(types.Container).init(self.allocator);
        defer containers.deinit();

        // Get list of all containers
        const lxc_list = try proxmox_ops.listLXC(self.client, self.client.node);

        for (lxc_list) |lxc| {
            // Get container status
            const status = try proxmox_ops.getLXCStatus(self.client, self.client.node, lxc.vmid);
            
            // Convert Proxmox status to CRI status
            const cri_status = switch (status) {
                .running => types.ContainerStatus.running,
                .stopped => types.ContainerStatus.exited,
                .suspended => types.ContainerStatus.paused,
                else => types.ContainerStatus.unknown,
            };

            // Get container config
            const config = try proxmox_ops.getLXCConfig(self.client, self.client.node, lxc.vmid);

            // Create CRI container
            const container = types.Container{
                .id = try std.fmt.allocPrint(self.allocator, "{d}", .{lxc.vmid}),
                .name = try self.allocator.dupe(u8, config.hostname orelse "unknown"),
                .status = cri_status,
                .created_at = lxc.created_time,
                .started_at = if (cri_status == .running) lxc.uptime else null,
                .labels = try self.extractLabels(config),
                .annotations = try self.extractAnnotations(config),
                .image_ref = try self.allocator.dupe(u8, config.rootfs),
            };

            // Apply filters if any
            if (filter) |f| {
                if (!self.matchesFilter(container, f)) {
                    continue;
                }
            }

            try containers.append(container);
        }

        return containers.toOwnedSlice();
    }

    fn extractLabels(self: *Self, config: types.LXCConfig) !std.StringHashMap([]const u8) {
        var labels = std.StringHashMap([]const u8).init(self.allocator);

        // Extract labels from container description if it contains JSON
        if (config.description) |desc| {
            if (std.json.parseFromSlice(std.json.Value, self.allocator, desc, .{})) |json| {
                if (json.object.get("labels")) |label_obj| {
                    var it = label_obj.object.iterator();
                    while (it.next()) |entry| {
                        try labels.put(
                            try self.allocator.dupe(u8, entry.key_ptr.*),
                            try self.allocator.dupe(u8, entry.value_ptr.*.string)
                        );
                    }
                }
            } else |_| {
                // If not JSON, use description as a single label
                try labels.put("description", try self.allocator.dupe(u8, desc));
            }
        }

        return labels;
    }

    fn extractAnnotations(self: *Self, config: types.LXCConfig) !std.StringHashMap([]const u8) {
        var annotations = std.StringHashMap([]const u8).init(self.allocator);

        // Add basic container info as annotations
        try annotations.put("architecture", try self.allocator.dupe(u8, config.arch orelse "amd64"));
        try annotations.put("os", try self.allocator.dupe(u8, config.ostype));
        if (config.memory) |mem| {
            try annotations.put("memory_limit_mb", try std.fmt.allocPrint(self.allocator, "{d}", .{mem}));
        }
        if (config.cores) |cores| {
            try annotations.put("cpu_cores", try std.fmt.allocPrint(self.allocator, "{d}", .{cores}));
        }

        return annotations;
    }

    fn matchesFilter(self: *Self, container: types.Container, filter: types.ContainerFilter) bool {
        _ = self;
        
        // Check ID prefix match
        if (filter.id) |id| {
            if (!std.mem.startsWith(u8, container.id, id)) {
                return false;
            }
        }

        // Check state match
        if (filter.state) |state| {
            if (container.status != state) {
                return false;
            }
        }

        // Check label matches
        if (filter.label_selector) |selector| {
            var it = selector.iterator();
            while (it.next()) |entry| {
                if (container.labels.get(entry.key_ptr.*)) |value| {
                    if (!std.mem.eql(u8, value, entry.value_ptr.*)) {
                        return false;
                    }
                } else {
                    return false;
                }
            }
        }

        return true;
    }

    // ContainerStatus returns the status of the container.
    pub fn ContainerStatus(self: *Self, container_id: []const u8) !types.ContainerStatus {
        try self.client.logger.info("Getting status for container {s}", .{container_id});

        // Convert container_id to VMID
        const vmid = std.fmt.parseInt(u32, container_id, 10) catch {
            try self.client.logger.err("Invalid container ID format: {s}", .{container_id});
            return error.InvalidContainerId;
        };

        // Get container status and config from Proxmox
        const status = try proxmox_ops.getLXCStatus(self.client, self.client.node, vmid);
        const config = try proxmox_ops.getLXCConfig(self.client, self.client.node, vmid);
        const stats = try proxmox_ops.getLXCStats(self.client, self.client.node, vmid);

        // Convert Proxmox status to CRI status
        const cri_status = switch (status) {
            .running => types.ContainerStatus.running,
            .stopped => types.ContainerStatus.exited,
            .suspended => types.ContainerStatus.paused,
            else => types.ContainerStatus.unknown,
        };

        // Get network info
        var network_info = types.NetworkInfo{
            .ip_addresses = std.ArrayList([]const u8).init(self.allocator),
            .interfaces = std.ArrayList(types.NetworkInterface).init(self.allocator),
        };
        defer network_info.ip_addresses.deinit();
        defer network_info.interfaces.deinit();

        // Add network interfaces
        if (config.net0) |net| {
            try network_info.interfaces.append(.{
                .name = try self.allocator.dupe(u8, net.name),
                .mac_address = try self.allocator.dupe(u8, net.hwaddr orelse ""),
                .network = try self.allocator.dupe(u8, net.bridge),
            });

            // Add IP addresses if available
            if (net.ip) |ip| {
                if (!std.mem.eql(u8, ip, "dhcp")) {
                    try network_info.ip_addresses.append(try self.allocator.dupe(u8, ip));
                }
            }
        }

        // Create container status
        return types.ContainerStatus{
            .id = try self.allocator.dupe(u8, container_id),
            .status = cri_status,
            .created_at = stats.created_time,
            .started_at = if (cri_status == .running) stats.uptime else null,
            .finished_at = if (cri_status == .exited) stats.downtime else null,
            .exit_code = if (cri_status == .exited) @as(i32, 0) else null,
            .image = .{
                .image = try self.allocator.dupe(u8, config.rootfs),
            },
            .labels = try self.extractLabels(config),
            .annotations = try self.extractAnnotations(config),
            .mounts = try self.extractMounts(config),
            .network = network_info,
        };
    }

    fn extractMounts(self: *Self, config: types.LXCConfig) ![]types.Mount {
        var mounts = std.ArrayList(types.Mount).init(self.allocator);
        defer mounts.deinit();

        // Helper function to process mount points
        const processMountPoint = struct {
            fn process(mp: ?types.MountPoint, alloc: std.mem.Allocator, mounts_list: *std.ArrayList(types.Mount)) !void {
                if (mp) |point| {
                    try mounts_list.append(.{
                        .container_path = try alloc.dupe(u8, point.mp),
                        .host_path = try alloc.dupe(u8, point.volume),
                        .readonly = false,
                        .selinux_relabel = false,
                        .propagation = .private,
                    });
                }
            }
        }.process;

        // Process all mount points
        try processMountPoint(config.mp0, self.allocator, &mounts);
        try processMountPoint(config.mp1, self.allocator, &mounts);
        try processMountPoint(config.mp2, self.allocator, &mounts);
        try processMountPoint(config.mp3, self.allocator, &mounts);
        try processMountPoint(config.mp4, self.allocator, &mounts);
        try processMountPoint(config.mp5, self.allocator, &mounts);
        try processMountPoint(config.mp6, self.allocator, &mounts);
        try processMountPoint(config.mp7, self.allocator, &mounts);

        return mounts.toOwnedSlice();
    }

    // UpdateContainerResources updates ContainerConfig of the container.
    pub fn UpdateContainerResources(self: *Self, container_id: []const u8, resources: types.ContainerResources) !void {
        try self.client.logger.info("Updating resources for container {s}", .{container_id});

        // Convert container_id to VMID
        const vmid = std.fmt.parseInt(u32, container_id, 10) catch {
            try self.client.logger.err("Invalid container ID format: {s}", .{container_id});
            return error.InvalidContainerId;
        };

        // Get current container config
        const current_config = try proxmox_ops.getLXCConfig(self.client, self.client.node, vmid);

        // Prepare update config
        var update_config = types.LXCConfigUpdate{
            .memory = if (resources.memory_limit_bytes) |mem|
                @intCast(@divFloor(mem, 1024 * 1024)) // Convert bytes to MB
            else
                current_config.memory orelse 512,
            
            .swap = if (resources.memory_swap_limit_bytes) |swap|
                @intCast(@divFloor(swap, 1024 * 1024)) // Convert bytes to MB
            else
                current_config.swap orelse 0,
            
            .cores = if (resources.cpu_shares) |cpu|
                @intCast(cpu)
            else
                current_config.cores orelse 1,
            
            .cpulimit = if (resources.cpu_quota) |quota|
                @floatFromInt(quota)
            else
                null,
            
            .cpuunits = if (resources.cpu_period) |period|
                @intCast(period)
            else
                null,
        };

        // Check if container is running
        const status = try proxmox_ops.getLXCStatus(self.client, self.client.node, vmid);
        if (status == .running) {
            // For running containers, we need to apply changes immediately
            try proxmox_ops.updateLXCConfig(self.client, self.client.node, vmid, update_config);
            try proxmox_ops.reloadLXC(self.client, self.client.node, vmid);
        } else {
            // For stopped containers, just update the config
            try proxmox_ops.updateLXCConfig(self.client, self.client.node, vmid, update_config);
        }

        try self.client.logger.info("Successfully updated resources for container {s}", .{container_id});
    }

    // ExecSync runs a command in a container synchronously.
    pub fn ExecSync(self: *Self, container_id: []const u8, cmd: []const []const u8, timeout: i64) !struct {
        stdout: []const u8,
        stderr: []const u8,
        exit_code: i32,
    } {
        try self.client.logger.info("Executing command in container {s} with timeout {d}s", .{container_id, timeout});

        // Convert container_id to VMID
        const vmid = std.fmt.parseInt(u32, container_id, 10) catch {
            try self.client.logger.err("Invalid container ID format: {s}", .{container_id});
            return error.InvalidContainerId;
        };

        // Check if container is running
        const status = try proxmox_ops.getLXCStatus(self.client, self.client.node, vmid);
        if (status != .running) {
            try self.client.logger.err("Container {s} is not running", .{container_id});
            return error.InvalidContainerState;
        }

        // Prepare command string
        var command_buf = std.ArrayList(u8).init(self.allocator);
        defer command_buf.deinit();

        // Join command arguments with proper escaping
        for (cmd, 0..) |arg, i| {
            if (i > 0) {
                try command_buf.append(' ');
            }
            try std.json.encodeJsonString(arg, .{}, command_buf.writer());
        }

        // Create execution options
        const exec_options = types.ExecOptions{
            .command = try command_buf.toOwnedSlice(),
            .timeout = timeout,
            .stdout_capture = true,
            .stderr_capture = true,
        };

        // Execute command in container
        const result = try proxmox_ops.execLXC(
            self.client,
            self.client.node,
            vmid,
            exec_options,
        );
        defer {
            if (result.stdout) |stdout| {
                self.allocator.free(stdout);
            }
            if (result.stderr) |stderr| {
                self.allocator.free(stderr);
            }
        }

        // Check if command timed out
        if (result.timed_out) {
            try self.client.logger.err("Command execution timed out after {d}s", .{timeout});
            return error.CommandTimeout;
        }

        return .{
            .stdout = result.stdout orelse "",
            .stderr = result.stderr orelse "",
            .exit_code = result.exit_code,
        };
    }
}; 