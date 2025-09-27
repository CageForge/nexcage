/// CLI module exports
pub const registry = @import("registry.zig");
pub const run = @import("run.zig");
pub const help = @import("help.zig");
pub const version = @import("version.zig");

// Re-export commonly used types
pub const CommandRegistry = registry.CommandRegistry;
pub const registerBuiltinCommands = registry.registerBuiltinCommands;
pub const RunCommand = run.RunCommand;
pub const HelpCommand = help.HelpCommand;
pub const VersionCommand = version.VersionCommand;
