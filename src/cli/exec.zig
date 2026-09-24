const std = @import("std");
const core = @import("core");
const types = core.types;
const base_command = @import("base_command.zig");
const router = @import("router.zig");

pub const ExecCommand = struct {
    const Self = @This();

    name: []const u8 = "exec",
    description: []const u8 = "Run a command inside a running container",
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

        const container_id = options.container_id orelse {
            if (self.base.logger) |log| log.err("exec needs a container name", .{}) catch {};
            return types.Error.InvalidInput;
        };

        // Everything after the name is the command. "--" separates it from
        // nexcage's own options where the command starts with a dash:
        //   nexcage exec web-1 -- ls -la
        var argv = options.args orelse &[_][]const u8{};
        if (argv.len > 0 and std.mem.eql(u8, argv[0], "--")) argv = argv[1..];
        if (argv.len == 0) {
            if (self.base.logger) |log| log.err("exec needs a command to run in '{s}'", .{container_id}) catch {};
            return types.Error.InvalidInput;
        }

        var backend_router = router.BackendRouter.init(allocator, self.base.logger);
        const op = router.Operation{ .exec = router.ExecConfig{ .argv = argv } };
        try backend_router.routeAndExecute(op, container_id, options.runtime_type, null);
    }

    pub fn help(self: *Self, allocator: std.mem.Allocator) ![]const u8 {
        _ = self;
        return allocator.dupe(u8,
            \\Run a command inside a running container
            \\
            \\Usage:
            \\  nexcage exec <name> <command> [args...]
            \\  nexcage exec <name> -- <command> [args...]
            \\
            \\Use "--" when the command starts with a dash, so nexcage does not
            \\read it as one of its own options.
            \\
            \\Exit status:
            \\  nexcage exits with the status of the command it ran, as an OCI
            \\  runtime does: 'nexcage exec web-1 false' exits 1. The usual
            \\  meanings of 1 and 2 do not apply to this command; a container
            \\  that is not running or does not exist is reported on stderr.
            \\
            \\Notes:
            \\  - The container must be running.
            \\  - On the Proxmox LXC backend this runs 'pct exec', so the
            \\    command has to exist in the container's image.
            \\  - stdin, stdout and stderr are connected to the container's
            \\    process; output is not buffered by nexcage.
            \\
            \\Examples:
            \\  nexcage exec web-1 ps aux
            \\  nexcage exec web-1 -- sh -c 'echo $HOSTNAME'
            \\
        );
    }

    pub fn validate(self: *Self, args: []const []const u8) !void {
        _ = self;
        _ = args;
    }
};
