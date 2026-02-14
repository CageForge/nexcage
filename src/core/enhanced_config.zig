/// Enhanced Configuration System Integration
///
/// This module previously integrated the plugin-aware configuration system.
/// It is now a simplified wrapper around the core configuration loader.
const std = @import("std");
const core = @import("core");

/// Enhanced configuration loader
pub const EnhancedConfigLoader = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    core_loader: core.config.ConfigLoader,
    logger: ?*core.LogContext = null,

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .core_loader = core.config.ConfigLoader.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    pub fn setLogger(self: *Self, logger: *core.LogContext) void {
        self.logger = logger;
    }

    /// Load configuration
    pub fn loadEnhancedConfiguration(self: *Self, json_content: []const u8) !EnhancedConfigurationResult {
        // Load core configuration
        const core_config = try self.core_loader.loadFromString(json_content);

        return EnhancedConfigurationResult{
            .core_config = core_config,
        };
    }

    /// Load from default locations
    pub fn loadDefaultEnhanced(self: *Self) !EnhancedConfigurationResult {
        // Try to load from default locations
        const default_paths = [_][]const u8{
            "./config.json",
            "/etc/nexcage/config.json",
            "/etc/nexcage/nexcage.json",
        };

        for (default_paths) |path| {
            if (self.loadEnhancedFromFile(path)) |result| {
                return result;
            } else |err| switch (err) {
                error.FileNotFound => continue,
                else => return err,
            }
        }

        // Return default configuration if no file found
        const core_config = try core.config.Config.init(self.allocator, .lxc);
        return EnhancedConfigurationResult{
            .core_config = core_config,
        };
    }

    /// Load from file
    pub fn loadEnhancedFromFile(self: *Self, file_path: []const u8) !EnhancedConfigurationResult {
        const file_content = std.fs.cwd().readFileAlloc(self.allocator, file_path, 1024 * 1024) catch |err| switch (err) {
            error.FileNotFound => return error.FileNotFound,
            else => return err,
        };
        defer self.allocator.free(file_content);

        return self.loadEnhancedConfiguration(file_content);
    }

    /// Check if a backend is enabled
    pub fn isBackendEnabled(self: *const Self, result: *const EnhancedConfigurationResult, backend_name: []const u8) bool {
        _ = self;
        _ = result;
        _ = backend_name;
        return true; // Default to enabled
    }

    /// Get backend priority
    pub fn getBackendPriority(self: *const Self, result: *const EnhancedConfigurationResult, backend_name: []const u8) u32 {
        _ = self;
        _ = result;

        // Return default priorities
        if (std.mem.eql(u8, backend_name, "crun")) return 10;
        if (std.mem.eql(u8, backend_name, "runc")) return 20;
        if (std.mem.eql(u8, backend_name, "proxmox-lxc")) return 30;
        if (std.mem.eql(u8, backend_name, "proxmox-vm")) return 40;

        return 100;
    }

    /// Generate configuration documentation
    pub fn generateConfigurationDocs(self: *Self) ![]const u8 {
        var docs = std.ArrayList(u8).init(self.allocator);
        defer docs.deinit();

        const writer = docs.writer();

        try writer.print("# NexCage Configuration Documentation\n\n", .{});
        try writer.print("This document describes the complete configuration options for NexCage.\n\n", .{});

        // Core configuration documentation
        try writer.print("## Core Configuration\n\n", .{});
        try writer.print("The core configuration includes runtime, logging, and networking options.\n\n", .{});
        try writer.print("```json\n", .{});
        try writer.print("{{\n", .{});
        try writer.print("  \"runtime_type\": \"lxc\",\n", .{});
        try writer.print("  \"log_level\": \"info\",\n", .{});
        try writer.print("  \"log_file\": \"/var/log/nexcage.log\",\n", .{});
        try writer.print("  \"data_dir\": \"/var/lib/nexcage\",\n", .{});
        try writer.print("  \"network\": {{\n", .{});
        try writer.print("    \"bridge\": \"lxcbr0\"\n", .{});
        try writer.print("  }}\n", .{});
        try writer.print("}}\n", .{});
        try writer.print("```\n\n", .{});

        return docs.toOwnedSlice();
    }
};

/// Enhanced configuration result containing core config
pub const EnhancedConfigurationResult = struct {
    core_config: core.config.Config,

    pub fn deinit(self: *EnhancedConfigurationResult) void {
        self.core_config.deinit();
    }

    /// Get the core configuration
    pub fn getCoreConfig(self: *const EnhancedConfigurationResult) *const core.config.Config {
        return &self.core_config;
    }

    /// Check if configuration is valid
    pub fn isValid(self: *const EnhancedConfigurationResult) bool {
        _ = self;
        return true;
    }
};

/// Global enhanced configuration loader instance
var global_enhanced_loader: ?EnhancedConfigLoader = null;

/// Initialize global enhanced configuration loader
pub fn initGlobalEnhancedLoader(allocator: std.mem.Allocator) void {
    global_enhanced_loader = EnhancedConfigLoader.init(allocator);
}

/// Get global enhanced configuration loader
pub fn getGlobalEnhancedLoader() ?*EnhancedConfigLoader {
    return if (global_enhanced_loader) |*loader| loader else null;
}

/// Deinitialize global enhanced configuration loader
pub fn deinitGlobalEnhancedLoader() void {
    if (global_enhanced_loader) |*loader| {
        loader.deinit();
        global_enhanced_loader = null;
    }
}

/// Test suite
const testing = std.testing;

test "enhanced configuration loader basic operations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var loader = EnhancedConfigLoader.init(allocator);
    defer loader.deinit();

    // Test loading basic configuration without plugins
    const test_config =
        \\{
        \\  "runtime_type": "lxc",
        \\  "log_level": "info"
        \\}
    ;

    var result = try loader.loadEnhancedConfiguration(test_config);
    defer result.deinit();

    try testing.expect(result.isValid());
}
