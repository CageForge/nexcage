const std = @import("std");
const core = @import("core");
const types = core.types;
const interfaces = core.interfaces;
const run = @import("run.zig");
const help = @import("help.zig");
const version = @import("version.zig");
const create = @import("create.zig");
const start = @import("start.zig");
const stop = @import("stop.zig");
const delete = @import("delete.zig");
const list = @import("list.zig");

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
        // Free all CommandInterface instances
        var iterator = self.commands.iterator();
        while (iterator.next()) |entry| {
            self.allocator.destroy(entry.value_ptr.*);
        }
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

    /// Get help for a specific command
    pub fn getHelp(self: *CommandRegistry, name: []const u8, allocator: std.mem.Allocator) ![]const u8 {
        const command = self.get(name) orelse return error.CommandNotFound;
        return command.help(allocator);
    }

    /// Execute a command
    pub fn execute(self: *CommandRegistry, name: []const u8, options: types.RuntimeOptions, allocator: std.mem.Allocator) !void {
        const command = self.get(name) orelse return error.CommandNotFound;
        try command.execute(options, allocator);
    }
};

// Global registry instance
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

// Static command instances
var run_cmd = run.RunCommand{};
var help_cmd = help.HelpCommand{};
var version_cmd = version.VersionCommand{};
var create_cmd = create.CreateCommand{};
var start_cmd = start.StartCommand{};
var stop_cmd = stop.StopCommand{};
var delete_cmd = delete.DeleteCommand{};
var list_cmd = list.ListCommand{};

/// Register all built-in commands
pub fn registerBuiltinCommands(registry: *CommandRegistry) !void {
    // Register run command
    const run_iface = try registry.allocator.create(interfaces.CommandInterface);
    run_iface.* = .{
        .name = run_cmd.name,
        .description = run_cmd.description,
        .ctx = &run_cmd,
        .execute = @ptrCast(&run.RunCommand.execute),
        .help = @ptrCast(&run.RunCommand.help),
        .validate = @ptrCast(&run.RunCommand.validate),
    };
    try registry.register(run_iface);
    
    // Register help command
    const help_iface = try registry.allocator.create(interfaces.CommandInterface);
    help_iface.* = .{
        .name = help_cmd.name,
        .description = help_cmd.description,
        .ctx = &help_cmd,
        .execute = @ptrCast(&help.HelpCommand.execute),
        .help = @ptrCast(&help.HelpCommand.help),
        .validate = @ptrCast(&help.HelpCommand.validate),
    };
    try registry.register(help_iface);
    
    // Register version command
    const version_iface = try registry.allocator.create(interfaces.CommandInterface);
    version_iface.* = .{
        .name = version_cmd.name,
        .description = version_cmd.description,
        .ctx = &version_cmd,
        .execute = @ptrCast(&version.VersionCommand.execute),
        .help = @ptrCast(&version.VersionCommand.help),
        .validate = @ptrCast(&version.VersionCommand.validate),
    };
    try registry.register(version_iface);
    
    // Register create command
    const create_iface = try registry.allocator.create(interfaces.CommandInterface);
    create_iface.* = .{
        .name = create_cmd.name,
        .description = create_cmd.description,
        .ctx = &create_cmd,
        .execute = @ptrCast(&create.CreateCommand.execute),
        .help = @ptrCast(&create.CreateCommand.help),
        .validate = @ptrCast(&create.CreateCommand.validate),
    };
    try registry.register(create_iface);
    
    // Register start command
    const start_iface = try registry.allocator.create(interfaces.CommandInterface);
    start_iface.* = .{
        .name = start_cmd.name,
        .description = start_cmd.description,
        .ctx = &start_cmd,
        .execute = @ptrCast(&start.StartCommand.execute),
        .help = @ptrCast(&start.StartCommand.help),
        .validate = @ptrCast(&start.StartCommand.validate),
    };
    try registry.register(start_iface);
    
    // Register stop command
    const stop_iface = try registry.allocator.create(interfaces.CommandInterface);
    stop_iface.* = .{
        .name = stop_cmd.name,
        .description = stop_cmd.description,
        .ctx = &stop_cmd,
        .execute = @ptrCast(&stop.StopCommand.execute),
        .help = @ptrCast(&stop.StopCommand.help),
        .validate = @ptrCast(&stop.StopCommand.validate),
    };
    try registry.register(stop_iface);
    
    // Register delete command
    const delete_iface = try registry.allocator.create(interfaces.CommandInterface);
    delete_iface.* = .{
        .name = delete_cmd.name,
        .description = delete_cmd.description,
        .ctx = &delete_cmd,
        .execute = @ptrCast(&delete.DeleteCommand.execute),
        .help = @ptrCast(&delete.DeleteCommand.help),
        .validate = @ptrCast(&delete.DeleteCommand.validate),
    };
    try registry.register(delete_iface);
    
    // Register list command
    const list_iface = try registry.allocator.create(interfaces.CommandInterface);
    list_iface.* = .{
        .name = list_cmd.name,
        .description = list_cmd.description,
        .ctx = &list_cmd,
        .execute = @ptrCast(&list.ListCommand.execute),
        .help = @ptrCast(&list.ListCommand.help),
        .validate = @ptrCast(&list.ListCommand.validate),
    };
    try registry.register(list_iface);
}
