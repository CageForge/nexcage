/// CLI module exports
pub const base_command = @import("base_command.zig");
pub const errors = @import("errors.zig");
pub const registry = @import("registry.zig");
pub const validation = @import("validation.zig");
pub const router = @import("router.zig");
pub const run = @import("run.zig");
pub const help = @import("help.zig");
pub const version = @import("version.zig");
pub const create = @import("create.zig");
pub const start = @import("start.zig");
pub const stop = @import("stop.zig");
pub const delete = @import("delete.zig");
pub const list = @import("list.zig");
pub const plugin_integration = @import("plugin_integration.zig");

// Re-export commonly used types
pub const BaseCommand = base_command.BaseCommand;
pub const CommandRegistry = registry.CommandRegistry;
pub const registerBuiltinCommands = registry.registerBuiltinCommands;
pub const registerBuiltinCommandsWithLogger = registry.registerBuiltinCommandsWithLogger;
pub const initGlobalRegistry = registry.initGlobalRegistry;
pub const getGlobalRegistry = registry.getGlobalRegistry;
pub const deinitGlobalRegistry = registry.deinitGlobalRegistry;

// Plugin integration exports
pub const EnhancedCommandRegistry = plugin_integration.EnhancedCommandRegistry;
pub const CommandLookupResult = plugin_integration.CommandLookupResult;
pub const CommandStats = plugin_integration.CommandStats;
pub const initGlobalEnhancedRegistry = plugin_integration.initGlobalEnhancedRegistry;
pub const getGlobalEnhancedRegistry = plugin_integration.getGlobalEnhancedRegistry;
pub const deinitGlobalEnhancedRegistry = plugin_integration.deinitGlobalEnhancedRegistry;
pub const RunCommand = run.RunCommand;
pub const HelpCommand = help.HelpCommand;
pub const VersionCommand = version.VersionCommand;
pub const CreateCommand = create.CreateCommand;
pub const StartCommand = start.StartCommand;
pub const StopCommand = stop.StopCommand;
pub const DeleteCommand = delete.DeleteCommand;
pub const ListCommand = list.ListCommand;
