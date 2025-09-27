const std = @import("std");
const core = @import("../src/core/mod.zig");
const cli = @import("../src/cli/mod.zig");

/// CLI example demonstrating command registry and execution
/// This example shows how to use the modular CLI system
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("🚀 Proxmox LXCRI CLI Example\n", .{});
    std.debug.print("============================\n", .{});

    // Initialize logger
    var logger = core.LogContext.init(allocator, std.io.getStdErr().writer(), core.LogLevel.info, "cli-example");
    defer logger.deinit();

    try logger.info("Starting CLI example", .{});

    // Initialize command registry
    var registry = cli.CommandRegistry.init(allocator);
    defer registry.deinit();

    try logger.info("Command registry initialized", .{});

    // Register built-in commands
    try cli.registerBuiltinCommands(&registry);
    try logger.info("Built-in commands registered", .{});

    // Register custom command
    try registerCustomCommands(&registry, &logger);
    try logger.info("Custom commands registered", .{});

    // List all available commands
    try listAvailableCommands(&registry, allocator);

    // Demonstrate command execution
    try demonstrateCommandExecution(&registry, allocator, &logger);

    try logger.info("CLI example completed successfully", .{});
    std.debug.print("\n✅ CLI example completed successfully!\n", .{});
}

fn registerCustomCommands(registry: *cli.CommandRegistry, logger: *core.LogContext) !void {
    // Create custom command
    const custom_cmd = try registry.allocator.alloc(CustomCommand, 1);
    custom_cmd[0] = CustomCommand{};
    custom_cmd[0].setLogger(logger);

    // Register custom command
    try registry.register(@ptrCast(&custom_cmd[0]));
    
    std.debug.print("  ✅ Custom command 'custom' registered\n", .{});
}

fn listAvailableCommands(registry: *cli.CommandRegistry, allocator: std.mem.Allocator) !void {
    std.debug.print("\n📋 Available Commands:\n", .{});
    std.debug.print("======================\n", .{});

    const commands = try registry.list(allocator);
    defer allocator.free(commands);

    for (commands, 0..) |cmd_name, i| {
        const command = registry.get(cmd_name);
        if (command) |cmd| {
            std.debug.print("  {d}. {s} - {s}\n", .{ i + 1, cmd.name, cmd.description });
        }
    }
}

fn demonstrateCommandExecution(registry: *cli.CommandRegistry, allocator: std.mem.Allocator, logger: *core.LogContext) !void {
    std.debug.print("\n🎯 Command Execution Demo:\n", .{});
    std.debug.print("==========================\n", .{});

    // Create runtime options
    const options = core.types.RuntimeOptions{
        .allocator = allocator,
        .command = .help,
        .container_id = try allocator.dupe(u8, "demo-container"),
        .image = try allocator.dupe(u8, "ubuntu:20.04"),
        .verbose = true,
    };

    // Test help command
    std.debug.print("  Testing 'help' command...\n", .{});
    registry.execute("help", options, allocator) catch |err| {
        std.debug.print("    ⚠️  Help command failed: {}\n", .{err});
        // This is expected as we don't have full implementation
    };

    // Test version command
    std.debug.print("  Testing 'version' command...\n", .{});
    registry.execute("version", options, allocator) catch |err| {
        std.debug.print("    ⚠️  Version command failed: {}\n", .{err});
        // This is expected as we don't have full implementation
    };

    // Test custom command
    std.debug.print("  Testing 'custom' command...\n", .{});
    registry.execute("custom", options, allocator) catch |err| {
        std.debug.print("    ⚠️  Custom command failed: {}\n", .{err});
        // This is expected as we don't have full implementation
    };

    std.debug.print("  ✅ Command execution demo completed\n", .{});
}

/// Custom command implementation
const CustomCommand = struct {
    const Self = @This();
    
    name: []const u8 = "custom",
    description: []const u8 = "Custom command example",
    logger: ?*core.LogContext = null,

    pub fn setLogger(self: *Self, logger: *core.LogContext) void {
        self.logger = logger;
    }

    pub fn execute(self: *Self, options: core.types.RuntimeOptions, allocator: std.mem.Allocator) !void {
        _ = allocator;

        if (self.logger) |log| {
            try log.info("Executing custom command", .{});
        }

        std.debug.print("    🔧 Custom command executed!\n", .{});
        std.debug.print("      - Container ID: {s}\n", .{options.container_id orelse "none"});
        std.debug.print("      - Image: {s}\n", .{options.image orelse "none"});
        std.debug.print("      - Verbose: {}\n", .{options.verbose});

        if (self.logger) |log| {
            try log.info("Custom command completed successfully", .{});
        }
    }
};

/// Custom command that demonstrates advanced features
const AdvancedCustomCommand = struct {
    const Self = @This();
    
    name: []const u8 = "advanced",
    description: []const u8 = "Advanced custom command with backend integration",
    logger: ?*core.LogContext = null,

    pub fn setLogger(self: *Self, logger: *core.LogContext) void {
        self.logger = logger;
    }

    pub fn execute(self: *Self, options: core.types.RuntimeOptions, allocator: std.mem.Allocator) !void {
        if (self.logger) |log| {
            try log.info("Executing advanced custom command", .{});
        }

        std.debug.print("    🚀 Advanced custom command executed!\n", .{});
        std.debug.print("      - Runtime type: {}\n", .{options.runtime_type orelse .unknown});
        std.debug.print("      - Debug mode: {}\n", .{options.debug});
        std.debug.print("      - Interactive: {}\n", .{options.interactive});

        // Demonstrate backend selection based on runtime type
        switch (options.runtime_type orelse .lxc) {
            .lxc => {
                std.debug.print("      - Selected LXC backend\n", .{});
            },
            .proxmox_lxc => {
                std.debug.print("      - Selected Proxmox LXC backend\n", .{});
            },
            .proxmox_vm => {
                std.debug.print("      - Selected Proxmox VM backend\n", .{});
            },
            .crun => {
                std.debug.print("      - Selected Crun backend\n", .{});
            },
            else => {
                std.debug.print("      - Unknown runtime type\n", .{});
            },
        }

        if (self.logger) |log| {
            try log.info("Advanced custom command completed successfully", .{});
        }
    }
};
