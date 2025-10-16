const std = @import("std");
const core = @import("core");
const types = core.types;
const interfaces = core.interfaces;
const registry = @import("registry.zig");
const errors = @import("errors.zig");
const base_command = @import("base_command.zig");

/// Help command implementation
pub const HelpCommand = struct {
    const Self = @This();

    name: []const u8 = "help",
    description: []const u8 = "Show help information",
    ctx: ?*anyopaque = null,
    base: base_command.BaseCommand = .{},

    pub fn setLogger(self: *Self, logger: *core.LogContext) void {
        self.base.setLogger(logger);
    }

    pub fn execute(self: *Self, options: types.RuntimeOptions, allocator: std.mem.Allocator) !void {
        // Use stdout instead of debug.print for proper output
        const stdout = std.fs.File.stdout();
        
        if (options.args) |args| {
            if (args.len > 0) {
                // Show help for specific command
                const command_name = args[0];
                const help_text = try self.getCommandHelp(command_name, allocator);
                defer allocator.free(help_text);
                try stdout.writeAll(help_text);
                try stdout.writeAll("\n");
            } else {
                // Show general help
                const help_text = try self.help(allocator);
                defer allocator.free(help_text);
                try stdout.writeAll(help_text);
            }
        } else {
            // Show general help
            const help_text = try self.help(allocator);
            defer allocator.free(help_text);
            try stdout.writeAll(help_text);
        }
    }

    fn getCommandHelp(self: *Self, command_name: []const u8, allocator: std.mem.Allocator) ![]const u8 {
        _ = self;
        // For now, return a simple help message
        return std.fmt.allocPrint(allocator, "Help for command '{s}' - use 'nexcage {s} --help' for detailed help", .{command_name, command_name});
    }

    pub fn help(self: *Self, allocator: std.mem.Allocator) ![]const u8 {
        _ = self;

        var help_text = std.array_list.Managed(u8).init(allocator);
        defer help_text.deinit();

        try help_text.appendSlice("nexcage - Proxmox LXC Runtime Interface\n\n");
        try help_text.appendSlice("Usage: nexcage [COMMAND] [OPTIONS]\n\n");
        try help_text.appendSlice("Commands:\n");
        try help_text.appendSlice("  create     Create a new container\n");
        try help_text.appendSlice("  start      Start a container\n");
        try help_text.appendSlice("  stop       Stop a container\n");
        try help_text.appendSlice("  delete     Delete a container\n");
        try help_text.appendSlice("  list       List containers\n");
        try help_text.appendSlice("  run        Run a command in a container\n");
        try help_text.appendSlice("  help       Show this help message\n");
        try help_text.appendSlice("  version    Show version information\n");
        try help_text.appendSlice("\nUse 'nexcage <command> --help' for command-specific help\n");

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
