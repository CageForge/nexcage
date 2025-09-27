// Proxmox VM backend plugin implementation
// This module provides the Proxmox VM backend for OCI container operations

const std = @import("std");
const Allocator = std.mem.Allocator;
const logger_mod = @import("logger");
const types = @import("types");
const plugin = @import("plugin.zig");
const proxmox = @import("proxmox");

/// Proxmox VM backend plugin implementation
pub const ProxmoxVMBackend = struct {
    const Self = @This();

    allocator: Allocator,
    logger: *logger_mod.Logger,
    proxmox_client: *proxmox.ProxmoxClient,
    node: []const u8,

    pub fn init(allocator: Allocator, logger: *logger_mod.Logger) !Self {
        // Initialize Proxmox client
        const proxmox_client = try allocator.create(proxmox.ProxmoxClient);
        proxmox_client.* = try proxmox.ProxmoxClient.init(allocator, logger);

        return Self{
            .allocator = allocator,
            .logger = logger,
            .proxmox_client = proxmox_client,
            .node = "localhost", // Default node
        };
    }

    pub fn deinit(self: *Self) void {
        self.proxmox_client.deinit();
        self.allocator.destroy(self.proxmox_client);
    }

    pub fn isAvailable(self: *const Self) bool {
        // Check if Proxmox API is available
        return self.proxmox_client.isConnected();
    }

    pub fn createContainer(self: *Self, container_id: []const u8, bundle_path: []const u8, options: ?[]const u8) !void {
        try self.logger.info("Creating Proxmox VM container: {s} in bundle: {s}", .{ container_id, bundle_path });

        // Parse options if provided
        const vm_config: ?types.VMConfig = null;
        if (options) |opts| {
            // TODO: Parse options into VMConfig
            _ = opts;
        }

        // Create VM via Proxmox API
        try self.proxmox_client.createVM(container_id, vm_config);
        try self.logger.info("Successfully created Proxmox VM container: {s}", .{container_id});
    }

    pub fn startContainer(self: *Self, container_id: []const u8) !void {
        try self.logger.info("Starting Proxmox VM container: {s}", .{container_id});

        // Start VM via Proxmox API
        try self.proxmox_client.startVM(container_id);
        try self.logger.info("Successfully started Proxmox VM container: {s}", .{container_id});
    }

    pub fn stopContainer(self: *Self, container_id: []const u8) !void {
        try self.logger.info("Stopping Proxmox VM container: {s}", .{container_id});

        // Stop VM via Proxmox API
        try self.proxmox_client.stopVM(container_id);
        try self.logger.info("Successfully stopped Proxmox VM container: {s}", .{container_id});
    }

    pub fn deleteContainer(self: *Self, container_id: []const u8) !void {
        try self.logger.info("Deleting Proxmox VM container: {s}", .{container_id});

        // Delete VM via Proxmox API
        try self.proxmox_client.deleteVM(container_id);
        try self.logger.info("Successfully deleted Proxmox VM container: {s}", .{container_id});
    }

    pub fn getContainerState(self: *const Self, container_id: []const u8) !plugin.ContainerState {
        try self.logger.info("Getting state for Proxmox VM container: {s}", .{container_id});

        // Get VM state from Proxmox API
        const state = try self.proxmox_client.getVMState(container_id);

        // Convert VM state to plugin state
        return switch (state) {
            .created => .created,
            .running => .running,
            .stopped => .stopped,
            .paused => .paused,
            .deleted => .deleted,
            .unknown => .unknown,
        };
    }

    pub fn getContainerInfo(self: *const Self, container_id: []const u8) !plugin.ContainerInfo {
        try self.logger.info("Getting info for Proxmox VM container: {s}", .{container_id});

        // Get VM state first
        const state = try self.getContainerState(container_id);

        // Get additional info from Proxmox API
        const vm_info = try self.proxmox_client.getVMInfo(container_id);

        // Create container info
        return plugin.ContainerInfo{
            .id = try self.allocator.dupe(u8, container_id),
            .name = try self.allocator.dupe(u8, vm_info.name),
            .state = state,
            .pid = vm_info.pid,
            .bundle = try self.allocator.dupe(u8, vm_info.bundle),
            .created_at = if (vm_info.created_at) |time| try self.allocator.dupe(u8, time) else null,
            .started_at = if (vm_info.started_at) |time| try self.allocator.dupe(u8, time) else null,
            .finished_at = if (vm_info.finished_at) |time| try self.allocator.dupe(u8, time) else null,
            .allocator = self.allocator,
        };
    }

    pub fn listContainers(self: *const Self) ![]plugin.ContainerInfo {
        try self.logger.info("Listing Proxmox VM containers", .{});

        // Get list of VMs from Proxmox API
        const vm_list = try self.proxmox_client.listVMs();
        defer self.allocator.free(vm_list);

        // Convert to plugin format
        var containers = try self.allocator.alloc(plugin.ContainerInfo, vm_list.len);
        for (vm_list, 0..) |vm_info, i| {
            containers[i] = plugin.ContainerInfo{
                .id = try self.allocator.dupe(u8, vm_info.id),
                .name = try self.allocator.dupe(u8, vm_info.name),
                .state = switch (vm_info.state) {
                    .created => .created,
                    .running => .running,
                    .stopped => .stopped,
                    .paused => .paused,
                    .deleted => .deleted,
                    .unknown => .unknown,
                },
                .pid = vm_info.pid,
                .bundle = try self.allocator.dupe(u8, vm_info.bundle),
                .created_at = if (vm_info.created_at) |time| try self.allocator.dupe(u8, time) else null,
                .started_at = if (vm_info.started_at) |time| try self.allocator.dupe(u8, time) else null,
                .finished_at = if (vm_info.finished_at) |time| try self.allocator.dupe(u8, time) else null,
                .allocator = self.allocator,
            };
        }

        return containers;
    }

    pub fn pauseContainer(self: *Self, container_id: []const u8) !void {
        try self.logger.info("Pausing Proxmox VM container: {s}", .{container_id});

        // Pause VM via Proxmox API
        try self.proxmox_client.pauseVM(container_id);
        try self.logger.info("Successfully paused Proxmox VM container: {s}", .{container_id});
    }

    pub fn resumeContainer(self: *Self, container_id: []const u8) !void {
        try self.logger.info("Resuming Proxmox VM container: {s}", .{container_id});

        // Resume VM via Proxmox API
        try self.proxmox_client.resumeVM(container_id);
        try self.logger.info("Successfully resumed Proxmox VM container: {s}", .{container_id});
    }

    pub fn killContainer(self: *Self, container_id: []const u8, signal: ?i32) !void {
        try self.logger.info("Killing Proxmox VM container: {s} with signal: {}", .{ container_id, signal orelse 15 });

        // Kill VM via Proxmox API
        try self.proxmox_client.killVM(container_id, signal);
        try self.logger.info("Successfully killed Proxmox VM container: {s}", .{container_id});
    }

    pub fn execContainer(self: *Self, container_id: []const u8, command: []const []const u8) !void {
        try self.logger.info("Executing command in Proxmox VM container: {s}", .{container_id});

        // Execute command in VM via Proxmox API
        try self.proxmox_client.execVM(container_id, command);
        try self.logger.info("Successfully executed command in Proxmox VM container: {s}", .{container_id});
    }

    pub fn getContainerLogs(self: *const Self, container_id: []const u8) ![]const u8 {
        try self.logger.info("Getting logs for Proxmox VM container: {s}", .{container_id});

        // Get VM logs from Proxmox API
        const logs = try self.proxmox_client.getVMLogs(container_id);
        return try self.allocator.dupe(u8, logs);
    }

    pub fn checkpointContainer(self: *Self, container_id: []const u8, checkpoint_path: []const u8) !void {
        try self.logger.info("Creating checkpoint for Proxmox VM container: {s}", .{container_id});

        // Create VM snapshot via Proxmox API
        try self.proxmox_client.createVMSnapshot(container_id, checkpoint_path);
        try self.logger.info("Successfully created checkpoint for Proxmox VM container: {s}", .{container_id});
    }

    pub fn restoreContainer(self: *Self, container_id: []const u8, checkpoint_path: []const u8) !void {
        try self.logger.info("Restoring Proxmox VM container: {s} from checkpoint: {s}", .{ container_id, checkpoint_path });

        // Restore VM from snapshot via Proxmox API
        try self.proxmox_client.restoreVMSnapshot(container_id, checkpoint_path);
        try self.logger.info("Successfully restored Proxmox VM container: {s}", .{container_id});
    }
};

/// Create a Proxmox VM backend plugin
pub fn createProxmoxVMPlugin(allocator: Allocator, logger: *logger_mod.Logger) !plugin.BackendPlugin {
    const backend = try allocator.create(ProxmoxVMBackend);
    backend.* = try ProxmoxVMBackend.init(allocator, logger);

    return plugin.BackendPlugin{
        .backend_type = .proxmox_vm,
        .name = "Proxmox VM Backend",
        .version = "1.0.0",
        .description = "Proxmox VM backend for OCI container operations",
        .allocator = allocator,
        .logger = logger,
        .init = ProxmoxVMBackend.init,
        .deinit = ProxmoxVMBackend.deinit,
        .isAvailable = ProxmoxVMBackend.isAvailable,
        .createContainer = ProxmoxVMBackend.createContainer,
        .startContainer = ProxmoxVMBackend.startContainer,
        .stopContainer = ProxmoxVMBackend.stopContainer,
        .deleteContainer = ProxmoxVMBackend.deleteContainer,
        .getContainerState = ProxmoxVMBackend.getContainerState,
        .getContainerInfo = ProxmoxVMBackend.getContainerInfo,
        .listContainers = ProxmoxVMBackend.listContainers,
        .pauseContainer = ProxmoxVMBackend.pauseContainer,
        .resumeContainer = ProxmoxVMBackend.resumeContainer,
        .killContainer = ProxmoxVMBackend.killContainer,
        .execContainer = ProxmoxVMBackend.execContainer,
        .getContainerLogs = ProxmoxVMBackend.getContainerLogs,
        .checkpointContainer = ProxmoxVMBackend.checkpointContainer,
        .restoreContainer = ProxmoxVMBackend.restoreContainer,
    };
}
