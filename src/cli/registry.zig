const std = @import("std");
const core = @import("core");
const types = core.types;
const interfaces = core.interfaces;
const errors = @import("errors.zig");
const run = @import("run.zig");
const help = @import("help.zig");
const version = @import("version.zig");
const create = @import("create.zig");
const start = @import("start.zig");
const stop = @import("stop.zig");
const delete = @import("delete.zig");
const list = @import("list.zig");
const health = @import("health_check.zig");
// const template = @import("template.zig");

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
        var names = std.array_list.Managed([]const u8).init(allocator);
        var iterator = self.commands.iterator();

        while (iterator.next()) |entry| {
            try names.append(entry.key_ptr.*);
        }

        return names.toOwnedSlice();
    }

    /// Get help for a specific command
    pub fn getHelp(self: *CommandRegistry, name: []const u8, allocator: std.mem.Allocator) ![]const u8 {
        const command = self.get(name) orelse return errors.CliError.CommandNotFound;
        return command.help(allocator);
    }

    /// Execute a command
    pub fn execute(self: *CommandRegistry, name: []const u8, options: types.RuntimeOptions, allocator: std.mem.Allocator) !void {
        const command = self.get(name) orelse return errors.CliError.CommandNotFound;
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
var health_cmd = health.HealthCommand{};
// var template_cmd = template.TemplateCommand{};

/// Generic command registration helper
fn registerCommand(
    registry: *CommandRegistry,
    cmd: anytype,
    comptime CommandType: type,
) !void {
    const iface = try registry.allocator.create(interfaces.CommandInterface);
    iface.* = .{
        .name = cmd.name,
        .description = cmd.description,
        .ctx = cmd,
        .execute = @ptrCast(&CommandType.execute),
        .help = @ptrCast(&CommandType.help),
        .validate = @ptrCast(&CommandType.validate),
    };
    try registry.register(iface);
}

fn registerCommandWithLogger(
    registry: *CommandRegistry,
    cmd: anytype,
    comptime CommandType: type,
    logger: *const core.LogContext,
) !void {
    const iface = try registry.allocator.create(interfaces.CommandInterface);
    iface.* = .{
        .name = cmd.name,
        .description = cmd.description,
        .ctx = cmd,
        .execute = @ptrCast(&CommandType.execute),
        .help = @ptrCast(&CommandType.help),
        .validate = @ptrCast(&CommandType.validate),
    };
    
    // Set logger for the command
    if (@hasDecl(CommandType, "setLogger")) {
        cmd.setLogger(@constCast(logger));
    }
    
    try registry.register(iface);
}

/// Register all built-in commands
pub fn registerBuiltinCommands(registry: *CommandRegistry) !void {
    try registerCommand(registry, &run_cmd, run.RunCommand);
    try registerCommand(registry, &help_cmd, help.HelpCommand);
    try registerCommand(registry, &version_cmd, version.VersionCommand);
    try registerCommand(registry, &create_cmd, create.CreateCommand);
    try registerCommand(registry, &start_cmd, start.StartCommand);
    try registerCommand(registry, &stop_cmd, stop.StopCommand);
    try registerCommand(registry, &delete_cmd, delete.DeleteCommand);
    try registerCommand(registry, &list_cmd, list.ListCommand);
    try registerCommand(registry, &health_cmd, health.HealthCommand);
    // try registerCommand(registry, &template_cmd, template.TemplateCommand);
}

/// Register all built-in commands with logger
pub fn registerBuiltinCommandsWithLogger(registry: *CommandRegistry, logger: *const core.LogContext) !void {
    try registerCommandWithLogger(registry, &run_cmd, run.RunCommand, logger);
    try registerCommandWithLogger(registry, &help_cmd, help.HelpCommand, logger);
    try registerCommandWithLogger(registry, &version_cmd, version.VersionCommand, logger);
    try registerCommandWithLogger(registry, &create_cmd, create.CreateCommand, logger);
    try registerCommandWithLogger(registry, &start_cmd, start.StartCommand, logger);
    try registerCommandWithLogger(registry, &stop_cmd, stop.StopCommand, logger);
    try registerCommandWithLogger(registry, &delete_cmd, delete.DeleteCommand, logger);
    try registerCommandWithLogger(registry, &list_cmd, list.ListCommand, logger);
    try registerCommandWithLogger(registry, &health_cmd, health.HealthCommand, logger);
    // try registerCommandWithLogger(registry, &template_cmd, template.TemplateCommand, logger);
}
