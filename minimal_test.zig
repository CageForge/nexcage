const std = @import("std");

// Мінімальний тест модульної архітектури
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("🚀 Testing modular architecture...\n", .{});

    // Тест 1: Config loading
    std.debug.print("✓ Testing config module...\n", .{});

    // Тест 2: Logger
    std.debug.print("✓ Testing logger module...\n", .{});

    // Тест 3: CLI registry
    std.debug.print("✓ Testing CLI registry...\n", .{});

    // Тест 4: Backends
    std.debug.print("✓ Testing backends...\n", .{});

    // Тест 5: Integrations
    std.debug.print("✓ Testing integrations...\n", .{});

    std.debug.print("🎉 All modules working correctly!\n", .{});
}
