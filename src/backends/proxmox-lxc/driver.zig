const std = @import("std");
const core = @import("core");
const types = @import("types.zig");
const proxmox_api = @import("integrations/proxmox-api");

/// Proxmox LXC backend driver
/// Proxmox LXC backend driver
pub const ProxmoxLxcDriver = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    config: types.ProxmoxLxcBackendConfig,
    api_client: *proxmox_api.client.ProxmoxApiClient,
    operations: proxmox_api.operations.ProxmoxApiOperations,
    logger: ?*core.LogContext = null,

    pub fn init(allocator: std.mem.Allocator, config: types.ProxmoxLxcBackendConfig) !*Self {
        const api_config = proxmox_api.types.ProxmoxApiConfig{
            .allocator = allocator,
            .host = try allocator.dupe(u8, config.proxmox_host),
            .port = config.proxmox_port,
            .token = try allocator.dupe(u8, config.proxmox_token),
            .node = try allocator.dupe(u8, config.proxmox_node),
            .verify_ssl = config.verify_ssl,
            .timeout = config.timeout,
        };

        const api_client = try proxmox_api.client.ProxmoxApiClient.init(allocator, api_config);
        const operations = proxmox_api.operations.ProxmoxApiOperations.init(allocator, api_client);

        const driver = try allocator.alloc(Self, 1);
        driver[0] = Self{
            .allocator = allocator,
            .config = config,
            .api_client = api_client,
            .operations = operations,
        };

        return &driver[0];
    }

    pub fn deinit(self: *Self) void {
        self.api_client.deinit();
        self.allocator.free(self);
    }

    /// Set logger
    pub fn setLogger(self: *Self, logger: *core.LogContext) void {
        self.logger = logger;
        self.api_client.setLogger(logger);
    }

    /// Create LXC container
    pub fn createContainer(self: *Self, config: types.ProxmoxLxcConfig) !void {
        if (self.logger) |log| {
            try log.info("Creating LXC container {d} with hostname '{s}'", .{ config.vmid, config.hostname });
        }

        const api_config = proxmox_api.types.ProxmoxLxcConfig{
            .allocator = self.allocator,
            .vmid = config.vmid,
            .hostname = try self.allocator.dupe(u8, config.hostname),
            .memory = config.memory,
            .cores = config.cores,
            .rootfs = try self.allocator.dupe(u8, config.rootfs),
            .net0 = if (config.net0) |net| try self.allocator.dupe(u8, net) else null,
            .ostemplate = if (config.ostemplate) |ost| try self.allocator.dupe(u8, ost) else null,
            .password = if (config.password) |pass| try self.allocator.dupe(u8, pass) else null,
            .ssh_public_keys = if (config.ssh_public_keys) |keys| try self.allocator.dupe(u8, keys) else null,
            .unprivileged = config.unprivileged,
            .onboot = config.onboot,
            .start = config.start,
        };
        defer api_config.deinit();

        try self.operations.createLxcContainer(api_config);

        if (self.logger) |log| {
            try log.info("Successfully created LXC container {d}", .{config.vmid});
        }
    }

    /// Start LXC container
    pub fn startContainer(self: *Self, vmid: u32) !void {
        if (self.logger) |log| {
            try log.info("Starting LXC container {d}", .{vmid});
        }

        try self.operations.start(vmid, true);

        if (self.logger) |log| {
            try log.info("Successfully started LXC container {d}", .{vmid});
        }
    }

    /// Stop LXC container
    pub fn stopContainer(self: *Self, vmid: u32) !void {
        if (self.logger) |log| {
            try log.info("Stopping LXC container {d}", .{vmid});
        }

        try self.operations.stop(vmid, true);

        if (self.logger) |log| {
            try log.info("Successfully stopped LXC container {d}", .{vmid});
        }
    }

    /// Delete LXC container
    pub fn deleteContainer(self: *Self, vmid: u32) !void {
        if (self.logger) |log| {
            try log.info("Deleting LXC container {d}", .{vmid});
        }

        try self.operations.delete(vmid, true);

        if (self.logger) |log| {
            try log.info("Successfully deleted LXC container {d}", .{vmid});
        }
    }

    /// List LXC containers
    pub fn listContainers(self: *Self) ![]types.LxcInfo {
        if (self.logger) |log| {
            try log.info("Listing LXC containers");
        }

        const api_containers = try self.operations.listContainers();
        defer {
            for (api_containers) |container| {
                container.deinit();
            }
            self.allocator.free(api_containers);
        }

        var result = try self.allocator.alloc(types.LxcInfo, api_containers.len);

        for (api_containers, 0..) |api_container, i| {
            result[i] = types.LxcInfo{
                .allocator = self.allocator,
                .vmid = api_container.vmid,
                .hostname = try self.allocator.dupe(u8, api_container.hostname),
                .status = if (api_container.start) .running else .stopped,
                .memory = api_container.memory,
                .cores = api_container.cores,
                .rootfs = try self.allocator.dupe(u8, api_container.rootfs),
                .ip_address = null, // TODO: Get IP from container config
                .uptime = null, // TODO: Get uptime from container status
            };
        }

        if (self.logger) |log| {
            try log.info("Found {d} LXC containers", .{result.len});
        }

        return result;
    }

    /// Get container information
    pub fn getContainerInfo(self: *Self, vmid: u32) !?types.LxcInfo {
        const containers = try self.listContainers();
        defer {
            for (containers) |container| {
                container.deinit();
            }
            self.allocator.free(containers);
        }

        for (containers) |container| {
            if (container.vmid == vmid) {
                return container;
            }
        }

        return null;
    }

    /// Check if container exists
    pub fn containerExists(self: *Self, vmid: u32) !bool {
        const info = try self.getContainerInfo(vmid);
        if (info) |container_info| {
            container_info.deinit();
            return true;
        }
        return false;
    }

    /// Get available templates
    pub fn getTemplates(self: *Self) ![]proxmox_api.types.ProxmoxTemplate {
        if (self.logger) |log| {
            try log.info("Getting available LXC templates");
        }

        const templates = try self.operations.listTemplates();

        if (self.logger) |log| {
            try log.info("Found {d} LXC templates", .{templates.len});
        }

        return templates;
    }
};
