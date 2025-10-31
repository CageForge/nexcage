const std = @import("std");
const testing = std.testing;
const core = @import("core");

// Test that comptime validation functions compile correctly
test "hasField validation" {
    const TestStruct = struct {
        field1: u32,
        field2: []const u8,
    };

    try testing.expect(core.comptime_validation.hasField(TestStruct, "field1"));
    try testing.expect(core.comptime_validation.hasField(TestStruct, "field2"));
    try testing.expect(!core.comptime_validation.hasField(TestStruct, "nonexistent"));
}

test "hasMethod validation" {
    const TestStruct = struct {
        pub fn method1() void {}
        pub fn deinit(self: *TestStruct) void {
            _ = self;
        }
    };

    try testing.expect(core.comptime_validation.hasMethod(TestStruct, "method1"));
    try testing.expect(core.comptime_validation.hasMethod(TestStruct, "deinit"));
    try testing.expect(!core.comptime_validation.hasMethod(TestStruct, "nonexistent"));
}

test "hasRequiredFields validation" {
    const TestStruct = struct {
        required1: u32,
        required2: []const u8,
        optional: ?u32,
    };

    const required = [_][]const u8{ "required1", "required2" };
    try testing.expect(core.comptime_validation.hasRequiredFields(TestStruct, &required));
    
    const missing = [_][]const u8{ "required1", "nonexistent" };
    try testing.expect(!core.comptime_validation.hasRequiredFields(TestStruct, &missing));
}

test "StringOps startsWith" {
    try testing.expect(core.comptime_validation.StringOps.startsWith("hello world", "hello"));
    try testing.expect(core.comptime_validation.StringOps.startsWith("proxmox-lxc", "proxmox"));
    try testing.expect(!core.comptime_validation.StringOps.startsWith("hello", "world"));
}

test "StringOps endsWith" {
    try testing.expect(core.comptime_validation.StringOps.endsWith("config.json", ".json"));
    try testing.expect(core.comptime_validation.StringOps.endsWith("test.zig", ".zig"));
    try testing.expect(!core.comptime_validation.StringOps.endsWith("config.json", ".txt"));
}

test "StringOps contains" {
    try testing.expect(core.comptime_validation.StringOps.contains("proxmox-lxc", "lxc"));
    try testing.expect(core.comptime_validation.StringOps.contains("test-config", "config"));
    try testing.expect(!core.comptime_validation.StringOps.contains("hello", "world"));
}

test "ConfigBuilder usage" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const default_config = core.types.SandboxConfig{
        .allocator = allocator,
        .name = try allocator.dupe(u8, "default"),
        .runtime_type = .proxmox_lxc,
        .image = null,
        .resources = null,
        .security = null,
        .network = null,
        .storage = null,
    };
    defer default_config.deinit();

    const Builder = core.comptime_validation.ConfigBuilder(core.types.SandboxConfig);
    var builder = Builder.init(allocator, default_config);
    
    // Builder should work (type-safe set operations would be tested here)
    const config = builder.build();
    
    try testing.expectEqualStrings("default", config.name);
    try testing.expect(config.runtime_type == .proxmox_lxc);
}

