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

        // Parse signal from args: default SIGTERM
        var signal: []const u8 = "SIGTERM";
        if (options.args) |args| {
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

        // Minimal validation of signal token (letters, numbers, SIG prefix or number)
        try validateSignal(signal);

        var backend_router = router.BackendRouter.init(allocator, self.base.logger);
        const op = router.Operation{ .kill = router.KillConfig{ .signal = signal } };
        try backend_router.routeAndExecute(op, container_id, null);
    }

    pub fn help(self: *Self, allocator: std.mem.Allocator) ![]const u8 {
        _ = self;
        return allocator.dupe(u8,
            "Usage: nexcage kill [--signal|-s SIGNAL] <container-id>\n\n" ++
            "Send a signal to a running container (OCI). Default is SIGTERM.\n\n" ++
            "Options:\n" ++
            "  -s, --signal STRING   Signal name (e.g. SIGTERM, SIGKILL) or number\n" ++
            "  -h, --help            Show this help\n"
        );
    }

    pub fn validate(self: *Self, args: []const []const u8) !void {
        _ = self;
        try validation.ValidationUtils.requireNonEmptyArgs(args);
    }
};

fn validateSignal(sig: []const u8) !void {
    // Accept alnum and underscore, and digits for numeric signals
    if (sig.len == 0 or sig.len > 32) return types.Error.InvalidInput;
    for (sig) |c| {
        const ok = (c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z') or (c >= '0' and c <= '9') or (c == '_');
        if (!ok) return types.Error.InvalidInput;
    }
}


