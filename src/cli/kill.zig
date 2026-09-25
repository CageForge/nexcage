const std = @import("std");
const core = @import("core");
const types = core.types;
const base_command = @import("base_command.zig");
const router = @import("router.zig");
const validation = @import("validation.zig");

pub const KillCommand = struct {
    const Self = @This();

    name: []const u8 = "kill",
    description: []const u8 = "Send a signal to a container (OCI-compatible)",
    base: base_command.BaseCommand = .{},

    pub fn setLogger(self: *Self, logger: *core.LogContext) void {
        self.base.setLogger(logger);
    }

    pub fn execute(self: *Self, options: types.RuntimeOptions, allocator: std.mem.Allocator) !void {
        const stdout = std.fs.File.stdout();

        if (options.help) {
            const help_text = try self.help(allocator);
            defer allocator.free(help_text);
            try stdout.writeAll(help_text);
            return;
        }

        const container_id = options.container_id orelse return types.Error.InvalidInput;

        // Signal: "-s/--signal SIGNAL", or positional as runc takes it
        // ("kill <id> SIGNAL"). Default SIGTERM.
        var signal: []const u8 = "SIGTERM";
        if (options.args) |args| {
            if (args.len > 0 and !std.mem.startsWith(u8, args[0], "-")) {
                signal = args[0];
            } else {
                var i: usize = 0;
                while (i < args.len) : (i += 1) {
                    const arg = args[i];
                    if (std.mem.eql(u8, arg, "--signal") or std.mem.eql(u8, arg, "-s")) {
                        if (i + 1 >= args.len) return types.Error.InvalidInput;
                        signal = args[i + 1];
                        break;
                    }
                }
            }
        }

        // A usage error before any backend is touched
        if (core.signals.parse(signal) == null) {
            if (self.base.logger) |log| log.err("unknown signal '{s}'; use a name such as TERM or SIGKILL, or a number from 1 to {d}", .{ signal, core.signals.max }) catch {};
            return types.Error.InvalidInput;
        }

        // runc takes --all to mean every process in the container's cgroup.
        // nexcage signals the init from the host, and the kernel delivers to
        // the whole namespace only for SIGKILL, so saying nothing here would
        // let a caller believe more happened than did.
        if (options.all) {
            if (self.base.logger) |log| log.warn("--all: nexcage signals the container's init; only SIGKILL reaches every process in it", .{}) catch {};
        }

        var backend_router = router.BackendRouter.init(allocator, self.base.logger);
        const op = router.Operation{ .kill = router.KillConfig{ .signal = signal } };
        try backend_router.routeAndExecute(op, container_id, options.runtime_type, null);
    }

    pub fn help(self: *Self, allocator: std.mem.Allocator) ![]const u8 {
        _ = self;
        return allocator.dupe(u8, "Usage: nexcage kill [--signal|-s SIGNAL] <name>\n" ++
            "       nexcage kill <name> [SIGNAL]\n\n" ++
            "Send a signal to the container's init process from the host. Default is SIGTERM.\n" ++
            "The kernel delivers it only if init handles that signal, except SIGKILL and\n" ++
            "SIGSTOP; SIGKILL always stops the container. Use 'stop' for a clean shutdown.\n\n" ++
            "Options:\n" ++
            "  -s, --signal STRING   Name in any case, with or without SIG (TERM, SIGKILL),\n" ++
            "                        or a number from 1 to 64\n" ++
            "  -h, --help            Show this help\n");
    }

    pub fn validate(self: *Self, args: []const []const u8) !void {
        _ = self;
        try validation.ValidationUtils.requireNonEmptyArgs(args);
    }
};
