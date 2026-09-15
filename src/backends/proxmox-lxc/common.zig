const std = @import("std");
const core = @import("core");

pub const CommandResult = struct {
    stdout: []u8,
    stderr: []u8,
    exit_code: u8,
};

pub fn runCommand(allocator: std.mem.Allocator, logger: ?*core.LogContext, args: []const []const u8) !CommandResult {
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = args,
        .max_output_bytes = 1024 * 1024, // 1MB
    }) catch |err| {
        // A missing pct/pvesh means this is not a Proxmox host; say so rather
        // than "Failed to run command: error.FileNotFound".
        if (err == error.FileNotFound) {
            if (logger) |log| log.err("'{s}' not found in PATH; nexcage must run on a Proxmox VE host", .{args[0]}) catch {};
            return core.Error.UnsupportedOperation;
        }
        if (logger) |log| log.err("Failed to run '{s}': {s}", .{ args[0], @errorName(err) }) catch {};
        return core.Error.OperationFailed;
    };

    const exit_code = switch (result.term) {
        .Exited => |code| @as(u8, @intCast(@abs(code))),
        else => 1,
    };

    return CommandResult{
        .stdout = result.stdout,
        .stderr = result.stderr,
        .exit_code = exit_code,
    };
}

pub const NetDeviceRuntimeInfo = struct {
    alias: []const u8,
    bridge: []const u8,
    host_name: ?[]const u8 = null,
};
