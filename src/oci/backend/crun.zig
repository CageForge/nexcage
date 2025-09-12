// Crun backend plugin implementation
// This module provides the crun backend for OCI container operations

const std = @import("std");
const Allocator = std.mem.Allocator;
const logger_mod = @import("logger");
const types = @import("types");
const plugin = @import("plugin.zig");
const crun = @import("crun.zig");

/// Crun backend plugin implementation
pub const CrunBackend = struct {
    const Self = @This();
    
    allocator: Allocator,
    logger: *logger_mod.Logger,
    crun_manager: crun.CrunManager,
    crun_path: []const u8,
    
    pub fn init(allocator: Allocator, logger: *logger_mod.Logger) !Self {
        const crun_manager = try crun.CrunManager.init(allocator, logger);
        
        return Self{
            .allocator = allocator,
            .logger = logger,
            .crun_manager = crun_manager,
            .crun_path = "/usr/bin/crun",
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.crun_manager.deinit();
    }
    
    pub fn isAvailable(self: *const Self) bool {
        // Check if crun is available
        const file = std.fs.openFileAbsolute(self.crun_path, .{}) catch return false;
        defer file.close();
        return true;
    }
    
    pub fn createContainer(self: *Self, container_id: []const u8, bundle_path: []const u8, options: ?[]const u8) !void {
        try self.logger.info("Creating crun container: {s} in bundle: {s}", .{ container_id, bundle_path });
        try self.crun_manager.createContainer(container_id, bundle_path, options);
        try self.logger.info("Successfully created crun container: {s}", .{container_id});
    }
    
    pub fn startContainer(self: *Self, container_id: []const u8) !void {
        try self.logger.info("Starting crun container: {s}", .{container_id});
        try self.crun_manager.startContainer(container_id);
        try self.logger.info("Successfully started crun container: {s}", .{container_id});
    }
    
    pub fn stopContainer(self: *Self, container_id: []const u8) !void {
        try self.logger.info("Stopping crun container: {s}", .{container_id});
        try self.crun_manager.stopContainer(container_id);
        try self.logger.info("Successfully stopped crun container: {s}", .{container_id});
    }
    
    pub fn deleteContainer(self: *Self, container_id: []const u8) !void {
        try self.logger.info("Deleting crun container: {s}", .{container_id});
        try self.crun_manager.deleteContainer(container_id);
        try self.logger.info("Successfully deleted crun container: {s}", .{container_id});
    }
    
    pub fn getContainerState(self: *const Self, container_id: []const u8) !plugin.ContainerState {
        try self.logger.info("Getting state for crun container: {s}", .{container_id});
        
        // Use crun manager to get container state
        const state = try self.crun_manager.getContainerState(container_id);
        
        // Convert crun state to plugin state
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
        try self.logger.info("Getting info for crun container: {s}", .{container_id});
        
        // Get container state first
        const state = try self.getContainerState(container_id);
        
        // Create container info
        return plugin.ContainerInfo{
            .id = try self.allocator.dupe(u8, container_id),
            .name = try self.allocator.dupe(u8, container_id),
            .state = state,
            .pid = null, // TODO: Get actual PID from crun
            .bundle = "", // TODO: Get bundle path from crun
            .created_at = null,
            .started_at = null,
            .finished_at = null,
            .allocator = self.allocator,
        };
    }
    
    pub fn listContainers(self: *const Self) ![]plugin.ContainerInfo {
        try self.logger.info("Listing crun containers", .{});
        
        // TODO: Implement container listing for crun
        // For now, return empty list
        return try self.allocator.alloc(plugin.ContainerInfo, 0);
    }
    
    pub fn pauseContainer(self: *Self, container_id: []const u8) !void {
        try self.logger.info("Pausing crun container: {s}", .{container_id});
        try self.crun_manager.pauseContainer(container_id);
        try self.logger.info("Successfully paused crun container: {s}", .{container_id});
    }
    
    pub fn resumeContainer(self: *Self, container_id: []const u8) !void {
        try self.logger.info("Resuming crun container: {s}", .{container_id});
        try self.crun_manager.resumeContainer(container_id);
        try self.logger.info("Successfully resumed crun container: {s}", .{container_id});
    }
    
    pub fn killContainer(self: *Self, container_id: []const u8, signal: ?i32) !void {
        try self.logger.info("Killing crun container: {s} with signal: {}", .{ container_id, signal orelse 15 });
        try self.crun_manager.killContainer(container_id, signal);
        try self.logger.info("Successfully killed crun container: {s}", .{container_id});
    }
    
    pub fn execContainer(self: *Self, container_id: []const u8, command: []const []const u8) !void {
        try self.logger.info("Executing command in crun container: {s}", .{container_id});
        try self.crun_manager.execContainer(container_id, command);
        try self.logger.info("Successfully executed command in crun container: {s}", .{container_id});
    }
    
    pub fn getContainerLogs(self: *const Self, container_id: []const u8) ![]const u8 {
        try self.logger.info("Getting logs for crun container: {s}", .{container_id});
        
        // TODO: Implement log retrieval for crun
        // For now, return empty string
        return try self.allocator.dupe(u8, "");
    }
    
    pub fn checkpointContainer(self: *Self, container_id: []const u8, checkpoint_path: []const u8) !void {
        try self.logger.info("Creating checkpoint for crun container: {s}", .{container_id});
        try self.crun_manager.checkpointContainer(container_id, checkpoint_path);
        try self.logger.info("Successfully created checkpoint for crun container: {s}", .{container_id});
    }
    
    pub fn restoreContainer(self: *Self, container_id: []const u8, checkpoint_path: []const u8) !void {
        try self.logger.info("Restoring crun container: {s} from checkpoint: {s}", .{ container_id, checkpoint_path });
        try self.crun_manager.restoreContainer(container_id, checkpoint_path);
        try self.logger.info("Successfully restored crun container: {s}", .{container_id});
    }
};

/// Create a crun backend plugin
pub fn createCrunPlugin(allocator: Allocator, logger: *logger_mod.Logger) !plugin.BackendPlugin {
    const backend = try allocator.create(CrunBackend);
    backend.* = try CrunBackend.init(allocator, logger);
    
    return plugin.BackendPlugin{
        .backend_type = .crun,
        .name = "Crun Backend",
        .version = "1.0.0",
        .description = "Crun backend for OCI container operations",
        .allocator = allocator,
        .logger = logger,
        .init = CrunBackend.init,
        .deinit = CrunBackend.deinit,
        .isAvailable = CrunBackend.isAvailable,
        .createContainer = CrunBackend.createContainer,
        .startContainer = CrunBackend.startContainer,
        .stopContainer = CrunBackend.stopContainer,
        .deleteContainer = CrunBackend.deleteContainer,
        .getContainerState = CrunBackend.getContainerState,
        .getContainerInfo = CrunBackend.getContainerInfo,
        .listContainers = CrunBackend.listContainers,
        .pauseContainer = CrunBackend.pauseContainer,
        .resumeContainer = CrunBackend.resumeContainer,
        .killContainer = CrunBackend.killContainer,
        .execContainer = CrunBackend.execContainer,
        .getContainerLogs = CrunBackend.getContainerLogs,
        .checkpointContainer = CrunBackend.checkpointContainer,
        .restoreContainer = CrunBackend.restoreContainer,
    };
}
