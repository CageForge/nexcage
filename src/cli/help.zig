const std = @import("std");
const core = @import("core");
const types = core.types;
const interfaces = core.interfaces;
const registry = @import("registry.zig");

/// Help command implementation
pub const HelpCommand = struct {
    const Self = @This();

    name: []const u8 = "help",
    description: []const u8 = "Show help information",
    ctx: ?*anyopaque = null,

    pub fn execute(self: *Self, options: types.RuntimeOptions, allocator: std.mem.Allocator) !void {
        const global_registry = registry.getGlobalRegistry() orelse return types.Error.OperationFailed;

        if (options.args) |args| {
            if (args.len > 0) {
                // Show help for specific command
                const command_name = args[0];
                const help_text = try global_registry.getHelp(command_name, allocator);
                defer allocator.free(help_text);
                std.debug.print("{s}\n", .{help_text});
            } else {
                // Show general help
                const help_text = try self.help(allocator);
                defer allocator.free(help_text);
                std.debug.print("{s}\n", .{help_text});
            }
        } else {
            // Show general help
            const help_text = try self.help(allocator);
            defer allocator.free(help_text);
            std.debug.print("{s}\n", .{help_text});
        }
    }

    pub fn help(self: *Self, allocator: std.mem.Allocator) ![]const u8 {
        _ = self;

        const global_registry = registry.getGlobalRegistry() orelse {
            return allocator.dupe(u8, "Error: Command registry not initialized");
        };

        const command_names = try global_registry.list(allocator);
        defer allocator.free(command_names);

        var help_text = std.array_list.Managed(u8).init(allocator);
        defer help_text.deinit();

        try help_text.appendSlice("proxmox-lxcri - Proxmox LXC Runtime Interface\n\n");
        try help_text.appendSlice("Usage: proxmox-lxcri [COMMAND] [OPTIONS]\n\n");
        try help_text.appendSlice("Commands:\n");

        for (command_names) |name| {
            const command = global_registry.get(name) orelse continue;
            try help_text.writer().print("  {s:<12} {s}\n", .{ name, command.description });
        }

        try help_text.appendSlice("\nUse 'proxmox-lxcri help <command>' for more information about a command.\n");

        return help_text.toOwnedSlice();
    }

    pub fn validate(self: *Self, args: []const []const u8) !void {
        _ = self;
        _ = args;
        // Help command accepts any arguments
    }
};

/// Create a help command instance
pub fn createHelpCommand() HelpCommand {
    return HelpCommand{};
}
