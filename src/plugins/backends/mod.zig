/// Backend Plugins Module
/// 
/// This module provides registration and management for backend plugins,
/// allowing the plugin system to discover and load container runtime backends.

const std = @import("std");
const plugin = @import("../../plugin/mod.zig");

/// Backend plugin registration entry
pub const BackendPluginEntry = struct {
    name: []const u8,
    description: []const u8,
    plugin_path: []const u8,
    capabilities: []const plugin.Capability,
    priority: u8 = 100, // Lower numbers = higher priority
    enabled: bool = true,
};

/// Registry of available backend plugins
pub const BackendPluginRegistry = struct {
    const Self = @This();
    
    allocator: std.mem.Allocator,
    plugins: std.ArrayList(BackendPluginEntry),
    
    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .plugins = std.ArrayList(BackendPluginEntry).empty,
        };
    }
    
    pub fn deinit(self: *Self) void {
        for (self.plugins.items) |entry| {
            self.allocator.free(entry.name);
            self.allocator.free(entry.description);
            self.allocator.free(entry.plugin_path);
            self.allocator.free(entry.capabilities);
        }
        self.plugins.deinit(self.allocator);
    }
    
    /// Register a backend plugin
    pub fn registerPlugin(
        self: *Self,
        name: []const u8,
        description: []const u8,
        plugin_path: []const u8,
        capabilities: []const plugin.Capability,
        priority: u8
    ) !void {
        const entry = BackendPluginEntry{
            .name = try self.allocator.dupe(u8, name),
            .description = try self.allocator.dupe(u8, description),
            .plugin_path = try self.allocator.dupe(u8, plugin_path),
            .capabilities = try self.allocator.dupe(plugin.Capability, capabilities),
            .priority = priority,
            .enabled = true,
        };
        
        try self.plugins.append(self.allocator, entry);
        
        // Sort by priority (lower numbers first)
        std.sort.pdq(BackendPluginEntry, self.plugins.items, {}, comparePriority);
    }
    
    /// Get list of enabled backend plugins
    pub fn getEnabledPlugins(self: *Self, allocator: std.mem.Allocator) ![]BackendPluginEntry {
        var enabled = std.ArrayList(BackendPluginEntry).empty;
        defer enabled.deinit(allocator);
        
        for (self.plugins.items) |entry| {
            if (entry.enabled) {
                try enabled.append(allocator, entry);
            }
        }
        
        return enabled.toOwnedSlice(allocator);
    }
    
    /// Find plugin by name
    pub fn findPlugin(self: *Self, name: []const u8) ?*BackendPluginEntry {
        for (self.plugins.items) |*entry| {
            if (std.mem.eql(u8, entry.name, name)) {
                return entry;
            }
        }
        return null;
    }
    
    /// Enable/disable a plugin
    pub fn setPluginEnabled(self: *Self, name: []const u8, enabled: bool) bool {
        if (self.findPlugin(name)) |entry| {
            entry.enabled = enabled;
            return true;
        }
        return false;
    }
    
    fn comparePriority(context: void, a: BackendPluginEntry, b: BackendPluginEntry) bool {
        _ = context;
        return a.priority < b.priority;
    }
};

/// Initialize default backend plugins
pub fn initializeDefaultBackendPlugins(registry: *BackendPluginRegistry) !void {
    // Register crun backend plugin
    try registry.registerPlugin(
        "crun-backend",
        "Crun OCI container runtime backend",
        "src/plugins/backends/crun-plugin",
        &[_]plugin.Capability{
            .container_create, .container_start, .container_stop,
            .container_delete, .container_exec, .container_list,
            .container_info, .host_command, .filesystem_read,
            .filesystem_write, .logging,
        },
        10
    );
    
    // Register runc backend plugin
    try registry.registerPlugin(
        "runc-backend", 
        "Runc OCI container runtime backend",
        "src/plugins/backends/runc-plugin",
        &[_]plugin.Capability{
            .container_create, .container_start, .container_stop,
            .container_delete, .container_exec, .container_list,
            .container_info, .host_command, .filesystem_read,
            .filesystem_write, .logging,
        },
        20
    );
    
    // Register Proxmox LXC backend plugin
    try registry.registerPlugin(
        "proxmox-lxc-backend",
        "Proxmox LXC container backend",
        "src/plugins/backends/proxmox-lxc-plugin",
        &[_]plugin.Capability{
            .container_create, .container_start, .container_stop,
            .container_delete, .container_exec, .container_list,
            .container_info, .host_command, .filesystem_read,
            .filesystem_write, .network_client, .network_server,
            .system_info, .logging,
        },
        30
    );
    
    // Register Proxmox VM backend plugin
    try registry.registerPlugin(
        "proxmox-vm-backend",
        "Proxmox VM container backend",
        "src/plugins/backends/proxmox-vm-plugin",
        &[_]plugin.Capability{
            .container_create, .container_start, .container_stop,
            .container_delete, .container_exec, .container_list,
            .container_info, .host_command, .filesystem_read,
            .filesystem_write, .network_client, .network_server,
            .system_info, .system_metrics, .logging,
        },
        40
    );
}

/// Plugin loader for backend plugins
pub const BackendPluginLoader = struct {
    const Self = @This();
    
    allocator: std.mem.Allocator,
    plugin_manager: *plugin.PluginManager,
    registry: *BackendPluginRegistry,
    
    pub fn init(
        allocator: std.mem.Allocator,
        plugin_manager: *plugin.PluginManager,
        registry: *BackendPluginRegistry
    ) Self {
        return Self{
            .allocator = allocator,
            .plugin_manager = plugin_manager,
            .registry = registry,
        };
    }
    
    /// Load all registered backend plugins
    pub fn loadBackendPlugins(self: *Self) !void {
        const enabled_plugins = try self.registry.getEnabledPlugins(self.allocator);
        defer self.allocator.free(enabled_plugins);
        
        for (enabled_plugins) |entry| {
            self.loadBackendPlugin(entry) catch |err| {
                std.log.err("Failed to load backend plugin {s}: {}", .{ entry.name, err });
                continue;
            };
        }
    }
    
    /// Load a specific backend plugin
    fn loadBackendPlugin(self: *Self, entry: BackendPluginEntry) !void {
        std.log.info("Loading backend plugin: {s}", .{entry.name});
        
        // In a real implementation, this would:
        // 1. Load the plugin dynamic library
        // 2. Validate plugin metadata
        // 3. Register plugin with plugin manager
        // 4. Initialize plugin
        
        // For now, we'll use the plugin manager's loadPlugin method
        try self.plugin_manager.loadPlugin(entry.name);
        
        std.log.info("Successfully loaded backend plugin: {s}", .{entry.name});
    }
    
    /// Get available backend types
    pub fn getAvailableBackends(self: *Self, allocator: std.mem.Allocator) ![][]const u8 {
        const enabled_plugins = try self.registry.getEnabledPlugins(self.allocator);
        defer self.allocator.free(enabled_plugins);
        
        var backends = std.ArrayList([]const u8).empty;
        defer backends.deinit(allocator);
        
        for (enabled_plugins) |entry| {
            try backends.append(allocator, try allocator.dupe(u8, entry.name));
        }
        
        return backends.toOwnedSlice(allocator);
    }
};

/// Test suite
const testing = std.testing;

test "backend plugin registry basic operations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var registry = BackendPluginRegistry.init(allocator);
    defer registry.deinit();
    
    // Test plugin registration
    try registry.registerPlugin(
        "test-backend",
        "Test backend plugin",
        "/path/to/test-plugin",
        &[_]plugin.Capability{ .container_create, .logging },
        50
    );
    
    // Test finding plugin
    const found = registry.findPlugin("test-backend");
    try testing.expect(found != null);
    try testing.expect(std.mem.eql(u8, found.?.name, "test-backend"));
    
    // Test enabling/disabling
    try testing.expect(registry.setPluginEnabled("test-backend", false));
    try testing.expect(!found.?.enabled);
    
    try testing.expect(registry.setPluginEnabled("test-backend", true));
    try testing.expect(found.?.enabled);
    
    // Test non-existent plugin
    try testing.expect(!registry.setPluginEnabled("non-existent", false));
}

test "backend plugin priority ordering" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var registry = BackendPluginRegistry.init(allocator);
    defer registry.deinit();
    
    // Register plugins with different priorities
    try registry.registerPlugin("high-priority", "High priority plugin", "/path/1",
        &[_]plugin.Capability{.logging}, 10);
    try registry.registerPlugin("medium-priority", "Medium priority plugin", "/path/2", 
        &[_]plugin.Capability{.logging}, 50);
    try registry.registerPlugin("low-priority", "Low priority plugin", "/path/3",
        &[_]plugin.Capability{.logging}, 90);
    
    // Check that plugins are sorted by priority
    try testing.expect(registry.plugins.items.len == 3);
    try testing.expect(std.mem.eql(u8, registry.plugins.items[0].name, "high-priority"));
    try testing.expect(std.mem.eql(u8, registry.plugins.items[1].name, "medium-priority"));
    try testing.expect(std.mem.eql(u8, registry.plugins.items[2].name, "low-priority"));
}