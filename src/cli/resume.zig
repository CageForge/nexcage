const std = @import("std");
const core = @import("core");
const types = core.types;
const base_command = @import("base_command.zig");
const router = @import("router.zig");
const validation = @import("validation.zig");

/// `resume`: the cgroup freezer, as the runtime-spec means it.
///
/// Thaw every process in the container. They stay in memory exactly where they
/// were -- this is not a checkpoint, and nothing is written to disk.
///
/// On the Proxmox LXC backend this is **not** `pct suspend`: that runs
/// `lxc-checkpoint -s`, which dumps the container through CRIU and takes it
/// down. The freezer is a different thing, and it is the one the spec describes.
pub const ResumeCommand = struct {
    const Self = @This();

    name: []const u8 = "resume",
    description: []const u8 = "Thaw every process in a container (the cgroup freezer)",
    base: base_command.BaseCommand = .{},

    pub fn setLogger(self: *Self, logger: *core.LogContext) void {
        self.base.setLogger(logger);
    }

    pub fn logCommandStart(self: *const Self, command_name: []const u8) !void {
        try self.base.logCommandStart(command_name);
    }

    pub fn logCommandComplete(self: *const Self, command_name: []const u8) !void {
        try self.base.logCommandComplete(command_name);
    }

    pub fn execute(self: *Self, options: types.RuntimeOptions, allocator: std.mem.Allocator) !void {
        if (options.help) {
            const help_text = try self.help(allocator);
            defer allocator.free(help_text);
            try std.fs.File.stdout().writeAll(help_text);
            return;
        }

        const container_id = try validation.ValidationUtils.requireContainerId(options, self.base.logger, "resume");

        var backend_router = router.BackendRouter.init(allocator, self.base.logger);
        try backend_router.routeAndExecute(.resume_, container_id, options.runtime_type, null);
    }

    pub fn help(self: *Self, allocator: std.mem.Allocator) ![]const u8 {
        _ = self;
        return allocator.dupe(u8, "Usage: nexcage resume <container-name>\n\n" ++
            "Thaw every process in the container, through the cgroup freezer.\n" ++
            "They stay in memory where they were; nothing is written to disk.\n\n" ++
            "On the Proxmox LXC backend, note that 'pct status' keeps saying\n" ++
            "'running' for a frozen container -- Proxmox has no notion of the\n" ++
            "state. 'nexcage state' reads the freezer itself and says 'paused'.\n\n" ++
            "This is not 'pct suspend', which runs lxc-checkpoint and dumps the\n" ++
            "container to disk. Freezing is done on the host the container is on.\n\n" ++
            "Options:\n" ++
            "  -h, --help    Show this help message\n\n" ++
            "Examples:\n" ++
            "  nexcage resume web-1\n");
    }

    pub fn validate(self: *Self, args: []const []const u8) !void {
        _ = self;
        try validation.ValidationUtils.requireNonEmptyArgs(args);
    }
};
