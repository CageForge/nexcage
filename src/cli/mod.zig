/// CLI module exports
pub const registry = @import("registry.zig");
pub const run = @import("run.zig");
pub const help = @import("help.zig");
pub const version = @import("version.zig");
pub const create = @import("create.zig");
pub const start = @import("start.zig");
pub const stop = @import("stop.zig");
pub const delete = @import("delete.zig");
pub const list = @import("list.zig");

// Re-export commonly used types
pub const CommandRegistry = registry.CommandRegistry;
pub const registerBuiltinCommands = registry.registerBuiltinCommands;
pub const RunCommand = run.RunCommand;
pub const HelpCommand = help.HelpCommand;
pub const VersionCommand = version.VersionCommand;
pub const CreateCommand = create.CreateCommand;
pub const StartCommand = start.StartCommand;
pub const StopCommand = stop.StopCommand;
pub const DeleteCommand = delete.DeleteCommand;
pub const ListCommand = list.ListCommand;
