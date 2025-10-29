/// Backend Plugins Integration
/// 
/// This module integrates backend plugins into the main NexCage system,
/// providing a bridge between the existing backend implementations and
/// the new plugin architecture.

const std = @import("std");
const plugin = @import("plugin/mod.zig");
const backends = @import("backends/mod.zig");
const core = @import("core/mod.zig");

/// Backend plugin wrapper that implements the plugin interface
pub const BackendPluginWrapper = struct {
    const Self = @This();
    
    plugin_instance: *plugin.Plugin,
    backend_type: BackendType,
    allocator: std.mem.Allocator,
    
    pub const BackendType = enum {
        crun,
        runc,
        proxmox_lxc,
        proxmox_vm,
    };
    
    pub fn init(allocator: std.mem.Allocator, backend_type: BackendType) !*Self {
        const self = try allocator.create(Self);
        
        // Create plugin metadata based on backend type
        const metadata = switch (backend_type) {
            .crun => createCrunMetadata(allocator),
            .runc => createRuncMetadata(allocator),
            .proxmox_lxc => createProxmoxLxcMetadata(allocator),
            .proxmox_vm => createProxmoxVmMetadata(allocator),
        };
        
        const plugin_instance = try plugin.Plugin.init(allocator, metadata);
        
        self.* = Self{
            .plugin_instance = plugin_instance,
            .backend_type = backend_type,
            .allocator = allocator,
        };
        
        return self;
    }
    
    pub fn deinit(self: *Self) void {
        self.plugin_instance.deinit(self.allocator);
        self.allocator.destroy(self);
    }
    
    /// Execute container operation using the wrapped backend
    pub fn executeOperation(
        self: *Self,
        operation: ContainerOperation,
        container_id: []const u8,
        allocator: std.mem.Allocator
    ) !plugin.CommandResult {
        switch (self.backend_type) {
            .crun => {
                var driver = backends.crun.CrunDriver.init(allocator, null);
                defer driver.deinit();
                return try self.executeCrunOperation(&driver, operation, container_id, allocator);
            },
            .runc => {
                var driver = backends.runc.RuncDriver.init(allocator, null);
                defer driver.deinit();
                return try self.executeRuncOperation(&driver, operation, container_id, allocator);
            },
            .proxmox_lxc => {
                // TODO: Implement Proxmox LXC operations
                return error.NotImplemented;
            },
            .proxmox_vm => {
                // TODO: Implement Proxmox VM operations  
                return error.NotImplemented;
            },
        }
    }
    
    fn executeCrunOperation(
        self: *Self,
        driver: *backends.crun.CrunDriver,
        operation: ContainerOperation,
        container_id: []const u8,
        allocator: std.mem.Allocator
    ) !plugin.CommandResult {
        _ = self;
        const start_time = std.time.milliTimestamp();
        
        switch (operation) {
            .create => {
                const config = core.types.SandboxConfig{
                    .name = container_id,
                    .image = null,
                    .command = null,
                    .working_dir = null,
                    .environment = null,
                    .ports = null,
                    .volumes = null,
                    .resources = null,
                    .network = null,
                    .security = null,
                };
                try driver.create(config);
            },
            .start => try driver.start(container_id),
            .stop => try driver.stop(container_id),
            .delete => try driver.delete(container_id),
            .list, .info => {
                // These operations would need output parsing
                // For now, return empty JSON
            },
        }
        
        const end_time = std.time.milliTimestamp();
        
        return plugin.CommandResult{
            .exit_code = 0,
            .stdout = try allocator.dupe(u8, ""),
            .stderr = try allocator.dupe(u8, ""),
            .duration_ms = @intCast(end_time - start_time),
        };
    }
    
    fn executeRuncOperation(
        self: *Self,
        driver: *backends.runc.RuncDriver,
        operation: ContainerOperation,
        container_id: []const u8,
        allocator: std.mem.Allocator
    ) !plugin.CommandResult {
        _ = self;
        const start_time = std.time.milliTimestamp();
        
        switch (operation) {
            .create => {
                const config = core.types.SandboxConfig{
                    .name = container_id,
                    .image = null,
                    .command = null,
                    .working_dir = null,
                    .environment = null,
                    .ports = null,
                    .volumes = null,
                    .resources = null,
                    .network = null,
                    .security = null,
                };
                try driver.create(config);
            },
            .start => try driver.start(container_id),
            .stop => try driver.stop(container_id),
            .delete => try driver.delete(container_id),
            .list, .info => {
                // These operations would need output parsing
                // For now, return empty JSON
            },
        }
        
        const end_time = std.time.milliTimestamp();
        
        return plugin.CommandResult{
            .exit_code = 0,
            .stdout = try allocator.dupe(u8, ""),
            .stderr = try allocator.dupe(u8, ""),
            .duration_ms = @intCast(end_time - start_time),
        };
    }
};

pub const ContainerOperation = enum {
    create,
    start,
    stop,
    delete,
    list,
    info,
};

/// Backend Plugin Registry
pub const BackendPluginRegistry = struct {
    const Self = @This();
    
    allocator: std.mem.Allocator,
    plugins: std.StringHashMap(*BackendPluginWrapper),
    
    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .plugins = std.StringHashMap(*BackendPluginWrapper).init(allocator),
        };
    }
    
    pub fn deinit(self: *Self) void {
        var iterator = self.plugins.iterator();
        while (iterator.next()) |entry| {
            entry.value_ptr.*.deinit();
            self.allocator.free(entry.key_ptr.*);
        }
        self.plugins.deinit();
    }
    
    /// Register a backend plugin
    pub fn registerBackend(self: *Self, name: []const u8, backend_type: BackendPluginWrapper.BackendType) !void {
        const wrapper = try BackendPluginWrapper.init(self.allocator, backend_type);
        errdefer wrapper.deinit();
        
        const name_copy = try self.allocator.dupe(u8, name);
        try self.plugins.put(name_copy, wrapper);
    }
    
    /// Get backend plugin by name
    pub fn getBackend(self: *Self, name: []const u8) ?*BackendPluginWrapper {
        return self.plugins.get(name);
    }
    
    /// List all registered backends
    pub fn listBackends(self: *Self, allocator: std.mem.Allocator) ![][]const u8 {
        var list = std.ArrayList([]const u8).empty;
        defer list.deinit(allocator);
        
        var iterator = self.plugins.iterator();
        while (iterator.next()) |entry| {
            try list.append(allocator, try allocator.dupe(u8, entry.key_ptr.*));
        }
        
        return list.toOwnedSlice(allocator);
    }
};

/// Initialize default backend plugins
pub fn initializeDefaultBackends(registry: *BackendPluginRegistry) !void {
    try registry.registerBackend("crun-backend", .crun);
    try registry.registerBackend("runc-backend", .runc);
    try registry.registerBackend("proxmox-lxc-backend", .proxmox_lxc);
    try registry.registerBackend("proxmox-vm-backend", .proxmox_vm);
}

// Helper functions to create plugin metadata

fn createCrunMetadata(allocator: std.mem.Allocator) plugin.PluginMetadata {
    _ = allocator;
    return plugin.PluginMetadata{
        .name = "crun-backend",
        .version = plugin.SemanticVersion{ .major = 1, .minor = 0, .patch = 0 },
        .description = "Crun OCI container runtime backend",
        .api_version = 1,
        .nexcage_version = plugin.SemanticVersion{ .major = 0, .minor = 7, .patch = 0 },
        .dependencies = &[_][]const u8{},
        .capabilities = &[_]plugin.Capability{
            .container_create, .container_start, .container_stop,
            .container_delete, .host_command, .logging,
        },
        .resource_requirements = plugin.ResourceRequirements{
            .max_memory_mb = 128,
            .max_cpu_percent = 10,
        },
        .provides_backend = true,
    };
}

fn createRuncMetadata(allocator: std.mem.Allocator) plugin.PluginMetadata {
    _ = allocator;
    return plugin.PluginMetadata{
        .name = "runc-backend",
        .version = plugin.SemanticVersion{ .major = 1, .minor = 0, .patch = 0 },
        .description = "Runc OCI container runtime backend",
        .api_version = 1,
        .nexcage_version = plugin.SemanticVersion{ .major = 0, .minor = 7, .patch = 0 },
        .dependencies = &[_][]const u8{},
        .capabilities = &[_]plugin.Capability{
            .container_create, .container_start, .container_stop,
            .container_delete, .host_command, .logging,
        },
        .resource_requirements = plugin.ResourceRequirements{
            .max_memory_mb = 128,
            .max_cpu_percent = 10,
        },
        .provides_backend = true,
    };
}

fn createProxmoxLxcMetadata(allocator: std.mem.Allocator) plugin.PluginMetadata {
    _ = allocator;
    return plugin.PluginMetadata{
        .name = "proxmox-lxc-backend",
        .version = plugin.SemanticVersion{ .major = 1, .minor = 0, .patch = 0 },
        .description = "Proxmox LXC container backend",
        .api_version = 1,
        .nexcage_version = plugin.SemanticVersion{ .major = 0, .minor = 7, .patch = 0 },
        .dependencies = &[_][]const u8{},
        .capabilities = &[_]plugin.Capability{
            .container_create, .container_start, .container_stop,
            .container_delete, .network_client, .logging,
        },
        .resource_requirements = plugin.ResourceRequirements{
            .max_memory_mb = 256,
            .max_cpu_percent = 15,
        },
        .provides_backend = true,
    };
}

fn createProxmoxVmMetadata(allocator: std.mem.Allocator) plugin.PluginMetadata {
    _ = allocator;
    return plugin.PluginMetadata{
        .name = "proxmox-vm-backend",
        .version = plugin.SemanticVersion{ .major = 1, .minor = 0, .patch = 0 },
        .description = "Proxmox VM container backend",
        .api_version = 1,
        .nexcage_version = plugin.SemanticVersion{ .major = 0, .minor = 7, .patch = 0 },
        .dependencies = &[_][]const u8{},
        .capabilities = &[_]plugin.Capability{
            .container_create, .container_start, .container_stop,
            .container_delete, .network_client, .logging,
        },
        .resource_requirements = plugin.ResourceRequirements{
            .max_memory_mb = 512,
            .max_cpu_percent = 25,
        },
        .provides_backend = true,
    };
}

/// Test suite
const testing = std.testing;

test "backend plugin wrapper creation and execution" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Test crun wrapper
    const crun_wrapper = try BackendPluginWrapper.init(allocator, .crun);
    defer crun_wrapper.deinit();
    
    try testing.expect(crun_wrapper.backend_type == .crun);
    try testing.expect(crun_wrapper.plugin_instance.status == .unloaded);
    
    // Test runc wrapper  
    const runc_wrapper = try BackendPluginWrapper.init(allocator, .runc);
    defer runc_wrapper.deinit();
    
    try testing.expect(runc_wrapper.backend_type == .runc);
    try testing.expect(runc_wrapper.plugin_instance.status == .unloaded);
}

test "backend plugin registry operations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var registry = BackendPluginRegistry.init(allocator);
    defer registry.deinit();
    
    // Test registration
    try registry.registerBackend("test-crun", .crun);
    try registry.registerBackend("test-runc", .runc);
    
    // Test retrieval
    const crun_backend = registry.getBackend("test-crun");
    try testing.expect(crun_backend != null);
    try testing.expect(crun_backend.?.backend_type == .crun);
    
    const runc_backend = registry.getBackend("test-runc");
    try testing.expect(runc_backend != null);
    try testing.expect(runc_backend.?.backend_type == .runc);
    
    // Test non-existent backend
    const missing = registry.getBackend("non-existent");
    try testing.expect(missing == null);
    
    // Test listing backends
    const backend_list = try registry.listBackends(allocator);
    defer {
        for (backend_list) |name| {
            allocator.free(name);
        }
        allocator.free(backend_list);
    }
    
    try testing.expect(backend_list.len == 2);
}

test "default backends initialization" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var registry = BackendPluginRegistry.init(allocator);
    defer registry.deinit();
    
    // Initialize default backends
    try initializeDefaultBackends(&registry);
    
    // Test that all default backends are registered
    try testing.expect(registry.getBackend("crun-backend") != null);
    try testing.expect(registry.getBackend("runc-backend") != null);
    try testing.expect(registry.getBackend("proxmox-lxc-backend") != null);
    try testing.expect(registry.getBackend("proxmox-vm-backend") != null);
    
    // Test listing all backends
    const all_backends = try registry.listBackends(allocator);
    defer {
        for (all_backends) |name| {
            allocator.free(name);
        }
        allocator.free(all_backends);
    }
    
    try testing.expect(all_backends.len == 4);
}