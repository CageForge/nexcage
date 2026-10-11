const std = @import("std");
const core = @import("core");

pub const CommandResult = struct {
    stdout: []u8,
    stderr: []u8,
    exit_code: u8,
};

pub fn runCommand(allocator: std.mem.Allocator, logger: ?*core.LogContext, args: []const []const u8) !CommandResult {
    return runCommandMax(allocator, logger, args, 1024 * 1024);
}

/// What nexcage reads from a listing of the whole cluster. /cluster/resources
/// has an entry of a few hundred bytes for every guest on every node, so a
/// cluster of a few thousand outgrew the 1 MiB every other call is read with
/// -- and what did not fit was taken for "the cluster cannot be asked".
pub const cluster_max_output = 64 * 1024 * 1024;

/// runCommand with a cap of the caller's on each of stdout and stderr.
/// Output past it is an error that says so, never a short answer.
pub fn runCommandMax(allocator: std.mem.Allocator, logger: ?*core.LogContext, args: []const []const u8, max_output_bytes: usize) !CommandResult {
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = args,
        .max_output_bytes = max_output_bytes,
    }) catch |err| {
        // A missing pct/pvesh means this is not a Proxmox host; say so rather
        // than "Failed to run command: error.FileNotFound".
        if (err == error.FileNotFound) {
            if (logger) |log| log.err("'{s}' not found in PATH; nexcage must run on a Proxmox VE host", .{args[0]}) catch {};
            return core.Error.UnsupportedOperation;
        }
        if (err == error.StdoutStreamTooLong or err == error.StderrStreamTooLong) {
            if (logger) |log| log.err("'{s}' printed more than the {d} bytes nexcage reads from it", .{ args[0], max_output_bytes }) catch {};
            return core.Error.OperationFailed;
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

test "the cluster's listing is read whole: 2 MiB is within its cap" {
    const a = std.testing.allocator;
    const res = try runCommandMax(a, null, &.{ "head", "-c", "2097152", "/dev/zero" }, cluster_max_output);
    defer {
        a.free(res.stdout);
        a.free(res.stderr);
    }
    try std.testing.expectEqual(@as(u8, 0), res.exit_code);
    try std.testing.expectEqual(@as(usize, 2 * 1024 * 1024), res.stdout.len);
}

test "output past the cap is an error, not a short answer" {
    try std.testing.expectError(core.Error.OperationFailed, runCommandMax(std.testing.allocator, null, &.{ "head", "-c", "2048", "/dev/zero" }, 1024));
}
