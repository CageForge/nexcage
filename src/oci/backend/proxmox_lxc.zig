// Proxmox LXC backend plugin implementation
// This module provides the Proxmox LXC backend for OCI container operations

const std = @import("std");
const Allocator = std.mem.Allocator;
const logger_mod = @import("logger");
const types = @import("types");
const plugin = @import("plugin.zig");
const proxmox = @import("proxmox");
const lxc = @import("../lxc.zig");

/// Proxmox LXC backend plugin implementation
pub const ProxmoxLXCBackend = struct {
    const Self = @This();
    
    allocator: Allocator,
    logger: *logger_mod.Logger,
    lxc_manager: lxc.LXCManager,
    proxmox_client: *proxmox.ProxmoxClient,
    node: []const u8,
    
    pub fn init(allocator: Allocator, logger: *logger_mod.Logger) !Self {
        const lxc_manager = try lxc.LXCManager.init(allocator, logger);
        
        // Initialize Proxmox client
        const proxmox_client = try allocator.create(proxmox.ProxmoxClient);
        proxmox_client.* = try proxmox.ProxmoxClient.init(allocator, logger);
        
        return Self{
            .allocator = allocator,
            .logger = logger,
            .lxc_manager = lxc_manager,
            .proxmox_client = proxmox_client,
            .node = "localhost", // Default node
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.lxc_manager.deinit();
        self.proxmox_client.deinit();
        self.allocator.destroy(self.proxmox_client);
    }
    
    pub fn isAvailable(self: *const Self) bool {
        // Check if Proxmox API is available
        return self.proxmox_client.isConnected();
    }
    
    pub fn createContainer(self: *Self, container_id: []const u8, bundle_path: []const u8, options: ?[]const u8) !void {
        try self.logger.info("Creating Proxmox LXC container: {s} in bundle: {s}", .{ container_id, bundle_path });
        
        // Parse options if provided
        const config: ?types.LXCConfig = null;
        if (options) |opts| {
            // TODO: Parse options into LXCConfig
            _ = opts;
        }
        
        // Create LXC container via Proxmox API
        try self.lxc_manager.createContainer(container_id, bundle_path, config);
        try self.logger.info("Successfully created Proxmox LXC container: {s}", .{container_id});
    }
    
    pub fn startContainer(self: *Self, container_id: []const u8) !void {
        try self.logger.info("Starting Proxmox LXC container: {s}", .{container_id});
        
        // Start LXC container via Proxmox API
        try self.lxc_manager.startContainer(container_id);
        try self.logger.info("Successfully started Proxmox LXC container: {s}", .{container_id});
    }
    
    pub fn stopContainer(self: *Self, container_id: []const u8) !void {
        try self.logger.info("Stopping Proxmox LXC container: {s}", .{container_id});
        
        // Stop LXC container via Proxmox API
        try self.lxc_manager.stopContainer(container_id);
        try self.logger.info("Successfully stopped Proxmox LXC container: {s}", .{container_id});
    }
    
    pub fn deleteContainer(self: *Self, container_id: []const u8) !void {
        try self.logger.info("Deleting Proxmox LXC container: {s}", .{container_id});
        
        // Delete LXC container via Proxmox API
        try self.lxc_manager.deleteContainer(container_id);
        try self.logger.info("Successfully deleted Proxmox LXC container: {s}", .{container_id});
    }
    
    pub fn getContainerState(self: *const Self, container_id: []const u8) !plugin.ContainerState {
        try self.logger.info("Getting state for Proxmox LXC container: {s}", .{container_id});
        
        // Get container state from Proxmox API
        const state = try self.lxc_manager.getContainerState(container_id);
        
        // Convert LXC state to plugin state
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
        try self.logger.info("Getting info for Proxmox LXC container: {s}", .{container_id});
        
        // Get container state first
        const state = try self.getContainerState(container_id);
        
        // Get additional info from Proxmox API
        const lxc_info = try self.lxc_manager.getContainerInfo(container_id);
        
        // Create container info
        return plugin.ContainerInfo{
            .id = try self.allocator.dupe(u8, container_id),
            .name = try self.allocator.dupe(u8, lxc_info.name),
            .state = state,
            .pid = lxc_info.pid,
            .bundle = try self.allocator.dupe(u8, lxc_info.bundle),
            .created_at = if (lxc_info.created_at) |time| try self.allocator.dupe(u8, time) else null,
            .started_at = if (lxc_info.started_at) |time| try self.allocator.dupe(u8, time) else null,
            .finished_at = if (lxc_info.finished_at) |time| try self.allocator.dupe(u8, time) else null,
            .allocator = self.allocator,
        };
    }
    
    pub fn listContainers(self: *const Self) ![]plugin.ContainerInfo {
        try self.logger.info("Listing Proxmox LXC containers", .{});
        
        // Get list of LXC containers from Proxmox API
        const lxc_containers = try self.lxc_manager.listContainers();
        defer self.allocator.free(lxc_containers);
        
        // Convert to plugin format
        var containers = try self.allocator.alloc(plugin.ContainerInfo, lxc_containers.len);
        for (lxc_containers, 0..) |lxc_info, i| {
            containers[i] = plugin.ContainerInfo{
                .id = try self.allocator.dupe(u8, lxc_info.id),
                .name = try self.allocator.dupe(u8, lxc_info.name),
                .state = switch (lxc_info.state) {
                    .created => .created,
                    .running => .running,
                    .stopped => .stopped,
                    .paused => .paused,
                    .deleted => .deleted,
                    .unknown => .unknown,
                },
                .pid = lxc_info.pid,
                .bundle = try self.allocator.dupe(u8, lxc_info.bundle),
                .created_at = if (lxc_info.created_at) |time| try self.allocator.dupe(u8, time) else null,
                .started_at = if (lxc_info.started_at) |time| try self.allocator.dupe(u8, time) else null,
                .finished_at = if (lxc_info.finished_at) |time| try self.allocator.dupe(u8, time) else null,
                .allocator = self.allocator,
            };
        }
        
        return containers;
    }
    
    pub fn pauseContainer(self: *Self, container_id: []const u8) !void {
        try self.logger.info("Pausing Proxmox LXC container: {s}", .{container_id});
        
        // Pause LXC container via Proxmox API
        try self.lxc_manager.pauseContainer(container_id);
        try self.logger.info("Successfully paused Proxmox LXC container: {s}", .{container_id});
    }
    
    pub fn resumeContainer(self: *Self, container_id: []const u8) !void {
        try self.logger.info("Resuming Proxmox LXC container: {s}", .{container_id});
        
        // Resume LXC container via Proxmox API
        try self.lxc_manager.resumeContainer(container_id);
        try self.logger.info("Successfully resumed Proxmox LXC container: {s}", .{container_id});
    }
    
    pub fn killContainer(self: *Self, container_id: []const u8, signal: ?i32) !void {
        try self.logger.info("Killing Proxmox LXC container: {s} with signal: {}", .{ container_id, signal orelse 15 });
        
        // Kill LXC container via Proxmox API
        try self.lxc_manager.killContainer(container_id, signal);
        try self.logger.info("Successfully killed Proxmox LXC container: {s}", .{container_id});
    }
    
    pub fn execContainer(self: *Self, container_id: []const u8, command: []const []const u8) !void {
        try self.logger.info("Executing command in Proxmox LXC container: {s}", .{container_id});
        
        // Execute command in LXC container via Proxmox API
        try self.lxc_manager.execContainer(container_id, command);
        try self.logger.info("Successfully executed command in Proxmox LXC container: {s}", .{container_id});
    }
    
    pub fn getContainerLogs(self: *const Self, container_id: []const u8) ![]const u8 {
        try self.logger.info("Getting logs for Proxmox LXC container: {s}", .{container_id});
        
        // Get container logs from Proxmox API
        const logs = try self.lxc_manager.getContainerLogs(container_id);
        return try self.allocator.dupe(u8, logs);
    }
    
    pub fn checkpointContainer(self: *Self, container_id: []const u8, checkpoint_path: []const u8) !void {
        try self.logger.info("Creating checkpoint for Proxmox LXC container: {s}", .{container_id});
        
        // Create checkpoint via Proxmox API
        try self.lxc_manager.checkpointContainer(container_id, checkpoint_path);
        try self.logger.info("Successfully created checkpoint for Proxmox LXC container: {s}", .{container_id});
    }
    
    pub fn restoreContainer(self: *Self, container_id: []const u8, checkpoint_path: []const u8) !void {
        try self.logger.info("Restoring Proxmox LXC container: {s} from checkpoint: {s}", .{ container_id, checkpoint_path });
        
        // Restore container from checkpoint via Proxmox API
        try self.lxc_manager.restoreContainer(container_id, checkpoint_path);
        try self.logger.info("Successfully restored Proxmox LXC container: {s}", .{container_id});
    }
};

/// Create a Proxmox LXC backend plugin
pub fn createProxmoxLXCPlugin(allocator: Allocator, logger: *logger_mod.Logger) !plugin.BackendPlugin {
    const backend = try allocator.create(ProxmoxLXCBackend);
    backend.* = try ProxmoxLXCBackend.init(allocator, logger);
    
    return plugin.BackendPlugin{
        .backend_type = .proxmox_lxc,
        .name = "Proxmox LXC Backend",
        .version = "1.0.0",
        .description = "Proxmox LXC backend for OCI container operations",
        .allocator = allocator,
        .logger = logger,
        .init = ProxmoxLXCBackend.init,
        .deinit = ProxmoxLXCBackend.deinit,
        .isAvailable = ProxmoxLXCBackend.isAvailable,
        .createContainer = ProxmoxLXCBackend.createContainer,
        .startContainer = ProxmoxLXCBackend.startContainer,
        .stopContainer = ProxmoxLXCBackend.stopContainer,
        .deleteContainer = ProxmoxLXCBackend.deleteContainer,
        .getContainerState = ProxmoxLXCBackend.getContainerState,
        .getContainerInfo = ProxmoxLXCBackend.getContainerInfo,
        .listContainers = ProxmoxLXCBackend.listContainers,
        .pauseContainer = ProxmoxLXCBackend.pauseContainer,
        .resumeContainer = ProxmoxLXCBackend.resumeContainer,
        .killContainer = ProxmoxLXCBackend.killContainer,
        .execContainer = ProxmoxLXCBackend.execContainer,
        .getContainerLogs = ProxmoxLXCBackend.getContainerLogs,
        .checkpointContainer = ProxmoxLXCBackend.checkpointContainer,
        .restoreContainer = ProxmoxLXCBackend.restoreContainer,
    };
}
