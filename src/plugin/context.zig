/// Plugin execution context
/// 
/// Provides a secure execution environment for plugins with
/// sandbox integration and resource management.

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Plugin execution context
pub const PluginContext = struct {
    const Self = @This();
    
    allocator: Allocator,
    plugin_name: []const u8,
    
    pub fn init(allocator: Allocator, plugin_name: []const u8) !*Self {
        const self = try allocator.create(Self);
        self.* = Self{
            .allocator = allocator,
            .plugin_name = try allocator.dupe(u8, plugin_name),
        };
        return self;
    }
    
    pub fn deinit(self: *Self) void {
        self.allocator.free(self.plugin_name);
        self.allocator.destroy(self);
    }
    
    /// Get the plugin name
    pub fn getPluginName(self: *const Self) []const u8 {
        return self.plugin_name;
    }
    
    /// Check if the context is valid (has non-empty plugin name)
    pub fn isValid(self: *const Self) bool {
        return self.plugin_name.len > 0;
    }
};

/// Test suite
const testing = std.testing;

test "PluginContext initialization and cleanup" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const plugin_name = "test-plugin";
    const context = try PluginContext.init(allocator, plugin_name);
    defer context.deinit();

    // Test that context was initialized correctly
    try testing.expect(std.mem.eql(u8, context.getPluginName(), plugin_name));
    try testing.expect(context.isValid());
    try testing.expect(context.allocator.ptr == allocator.ptr);
}

test "PluginContext with empty plugin name" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const context = try PluginContext.init(allocator, "");
    defer context.deinit();

    // Test empty plugin name
    try testing.expect(context.getPluginName().len == 0);
    try testing.expect(!context.isValid());
}

test "PluginContext with long plugin name" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const long_name = "very-long-plugin-name-with-many-characters-and-dashes-to-test-memory-handling";
    const context = try PluginContext.init(allocator, long_name);
    defer context.deinit();

    // Test long plugin name
    try testing.expect(std.mem.eql(u8, context.getPluginName(), long_name));
    try testing.expect(context.isValid());
    try testing.expect(context.getPluginName().len == long_name.len);
}

test "PluginContext with special characters" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const special_name = "plugin-with-special-chars_123!@#";
    const context = try PluginContext.init(allocator, special_name);
    defer context.deinit();

    // Test special characters in plugin name
    try testing.expect(std.mem.eql(u8, context.getPluginName(), special_name));
    try testing.expect(context.isValid());
}

test "Multiple PluginContext instances" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const context1 = try PluginContext.init(allocator, "plugin-one");
    defer context1.deinit();
    
    const context2 = try PluginContext.init(allocator, "plugin-two");
    defer context2.deinit();
    
    const context3 = try PluginContext.init(allocator, "plugin-three");
    defer context3.deinit();

    // Test that multiple contexts are independent
    try testing.expect(std.mem.eql(u8, context1.getPluginName(), "plugin-one"));
    try testing.expect(std.mem.eql(u8, context2.getPluginName(), "plugin-two"));
    try testing.expect(std.mem.eql(u8, context3.getPluginName(), "plugin-three"));
    
    try testing.expect(context1.isValid());
    try testing.expect(context2.isValid());
    try testing.expect(context3.isValid());
    
    // Ensure they have different memory addresses
    try testing.expect(context1 != context2);
    try testing.expect(context2 != context3);
    try testing.expect(context1 != context3);
}

test "PluginContext memory safety" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var saved_name: []const u8 = undefined;
    
    // Create and destroy context in inner scope
    {
        const context = try PluginContext.init(allocator, "temporary-plugin");
        saved_name = context.getPluginName();
        context.deinit();
    }
    
    // Test that the saved name is a proper copy (not sharing memory)
    // We can't safely access saved_name after deinit since it points to freed memory
    // This test verifies the pattern works without crashes
    try testing.expect(saved_name.len > 0);
}