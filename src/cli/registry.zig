const std = @import("std");
const core = @import("core");
const types = core.types;
const interfaces = core.interfaces;
const run = @import("run.zig");
const help = @import("help.zig");
const version = @import("version.zig");

/// CLI command registry using StaticStringMap
/// Command registry
pub const CommandRegistry = struct {
    allocator: std.mem.Allocator,
    commands: std.StringHashMap(*interfaces.CommandInterface),

    pub fn init(allocator: std.mem.Allocator) CommandRegistry {
        return CommandRegistry{
            .allocator = allocator,
            .commands = std.StringHashMap(*interfaces.CommandInterface).init(allocator),
        };
    }

    pub fn deinit(self: *CommandRegistry) void {
        self.commands.deinit();
    }

    /// Register a command
    pub fn register(self: *CommandRegistry, command: *interfaces.CommandInterface) !void {
        try self.commands.put(command.name, command);
    }

    /// Get a command by name
    pub fn get(self: *CommandRegistry, name: []const u8) ?*interfaces.CommandInterface {
        return self.commands.get(name);
    }

    /// List all registered commands
    pub fn list(self: *CommandRegistry, allocator: std.mem.Allocator) ![]const []const u8 {
        var names = std.ArrayList([]const u8).init(allocator);
        var iterator = self.commands.iterator();

        while (iterator.next()) |entry| {
            try names.append(entry.key_ptr.*);
        }

        return names.toOwnedSlice();
    }

    /// Execute a command
    pub fn execute(self: *CommandRegistry, name: []const u8, options: types.RuntimeOptions, allocator: std.mem.Allocator) !void {
        const command = self.get(name) orelse return types.Error.NotFound;
        try command.execute(command, options, allocator);
    }

    /// Get command help
    pub fn getHelp(self: *CommandRegistry, name: []const u8, allocator: std.mem.Allocator) ![]const u8 {
        const command = self.get(name) orelse return types.Error.NotFound;
        return command.help(allocator);
    }

    /// Validate command arguments
    pub fn validate(self: *CommandRegistry, name: []const u8, args: []const []const u8) !void {
        const command = self.get(name) orelse return types.Error.NotFound;
        try command.validate(args);
    }
};

/// Global command registry instance
var global_registry: ?CommandRegistry = null;

/// Initialize the global command registry
pub fn initGlobalRegistry(allocator: std.mem.Allocator) !void {
    global_registry = CommandRegistry.init(allocator);
}

/// Get the global command registry
pub fn getGlobalRegistry() ?*CommandRegistry {
    return if (global_registry) |*registry| registry else null;
}

/// Deinitialize the global command registry
pub fn deinitGlobalRegistry() void {
    if (global_registry) |*registry| {
        registry.deinit();
        global_registry = null;
    }
}

/// Register all built-in commands
pub fn registerBuiltinCommands(registry: *CommandRegistry) !void {
    // Register run command
    const run_cmd = try registry.allocator.alloc(run.RunCommand, 1);
    run_cmd[0] = run.RunCommand{};
    try registry.register(@ptrCast(&run_cmd[0]));
    
    // Register help command
    const help_cmd = try registry.allocator.alloc(help.HelpCommand, 1);
    help_cmd[0] = help.HelpCommand{};
    try registry.register(@ptrCast(&help_cmd[0]));
    
    // Register version command
    const version_cmd = try registry.allocator.alloc(version.VersionCommand, 1);
    version_cmd[0] = version.VersionCommand{};
    try registry.register(@ptrCast(&version_cmd[0]));
}
