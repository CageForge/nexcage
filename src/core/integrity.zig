const std = @import("std");
const logging = @import("logging.zig");
const config = @import("config.zig");
const state_root = @import("state_root.zig");

/// System integrity checker for monitoring critical components
pub const IntegrityChecker = struct {
    allocator: std.mem.Allocator,
    logger: ?*logging.LogContext,

    /// Initialize integrity checker
    pub fn init(allocator: std.mem.Allocator, logger: ?*logging.LogContext) IntegrityChecker {
        return IntegrityChecker{
            .allocator = allocator,
            .logger = logger,
        };
    }

    /// Check system integrity. Only checks that can both pass and fail are
    /// here. Gone: an API check that always warned; three directories --
    /// /var/lib/nexcage, /var/cache/nexcage, /tmp/nexcage -- that nothing
    /// creates, so every correct host failed; `pgrep nexcage`, which found
    /// the health check itself; and "network interfaces operational" and
    /// "system resources adequate", which said only that `ip` and `df` ran.
    pub fn checkSystemIntegrity(self: *IntegrityChecker) !IntegrityReport {
        var report = IntegrityReport.init(self.allocator);
        errdefer report.deinit();

        try self.checkProxmoxConnectivity(&report);
        try self.checkStorageIntegrity(&report);
        try self.checkConfigurationIntegrity(&report);

        return report;
    }

    /// Whether pct works. `pct list` is what nexcage itself runs, and it
    /// needs the cluster filesystem; this used to run `pct version`, which
    /// pct does not have, so the check failed on every Proxmox VE node.
    fn checkProxmoxConnectivity(self: *IntegrityChecker, report: *IntegrityReport) !void {
        if (self.logger) |log| try log.info("Checking Proxmox connectivity...", .{});

        if (self.runCommand(&[_][]const u8{ "pct", "list" })) |result| {
            defer result.deinit(self.allocator);
            if (result.exit_code == 0) {
                try report.addCheck("proxmox_pct_available", .pass, "pct list works", .{});
            } else {
                try report.addCheck("proxmox_pct_available", .fail, "pct list failed (exit {d}): {s}", .{ result.exit_code, firstLine(result.stderr) });
            }
        } else |err| {
            try report.addCheck("proxmox_pct_available", .fail, "pct cannot be run: {s}", .{@errorName(err)});
        }
    }

    /// The directories nexcage uses, and the ZFS pools.
    fn checkStorageIntegrity(self: *IntegrityChecker, report: *IntegrityReport) !void {
        if (self.logger) |log| try log.info("Checking storage integrity...", .{});

        // Where per-container state goes: /run/nexcage, or --root. The first
        // create makes it, so its absence is no fault; one nexcage cannot
        // write to is. Opened as a directory: a blocking open of a FIFO in
        // its place cannot hang the check.
        const root = state_root.get();
        if (std.fs.openDirAbsolute(root, .{})) |d| {
            var dir = d;
            dir.close();
            if (std.posix.access(root, std.posix.W_OK)) {
                try report.addCheck("state_root", .pass, "State directory: {s}", .{root});
            } else |err| {
                try report.addCheck("state_root", .fail, "State directory {s} is not writable: {s}", .{ root, @errorName(err) });
            }
        } else |err| switch (err) {
            error.FileNotFound => try report.addCheck("state_root", .warn, "State directory {s} does not exist yet; the first create makes it", .{root}),
            else => try report.addCheck("state_root", .fail, "State directory {s} cannot be opened: {s}", .{ root, @errorName(err) }),
        }

        // Proxmox VE's container configurations, there on every node
        if (std.fs.openDirAbsolute("/etc/pve/lxc", .{})) |d| {
            var dir = d;
            dir.close();
            try report.addCheck("storage_path", .pass, "Path accessible: /etc/pve/lxc", .{});
        } else |err| {
            try report.addCheck("storage_path", .fail, "Path not accessible: /etc/pve/lxc ({s})", .{@errorName(err)});
        }

        if (self.runCommand(&[_][]const u8{ "zpool", "status", "-x" })) |result| {
            defer result.deinit(self.allocator);
            const status = zpoolStatus(result);
            try report.addCheck("zfs_pool_status", status.result, "zpool status -x (exit {d}): {s}", .{ result.exit_code, status.message });
        } else |err| {
            try report.addCheck("zfs_pool_status", .warn, "zpool cannot be run: {s}", .{@errorName(err)});
        }
    }

    /// Report the configuration file the commands read. main loads it before
    /// any command runs and stops on one that does not parse, so by the time
    /// this runs the file is valid; what is left to say is which one it is.
    fn checkConfigurationIntegrity(self: *IntegrityChecker, report: *IntegrityReport) !void {
        if (self.logger) |log| try log.info("Checking configuration integrity...", .{});

        if (config.activePath()) |path| {
            try report.addCheck("config_file", .pass, "Config file in use: {s}", .{path});
        } else {
            try report.addCheck("config_file", .warn, "No config file in use; the built-in defaults apply", .{});
        }
        // Passed over without a word anywhere else
        if (config.skippedSpecPath()) |path| {
            try report.addCheck("config_file", .warn, "{s} is an OCI runtime spec, not a configuration, and was passed over", .{path});
        }
    }

    /// Run a command and return what it printed. Both pipes are read
    /// together: reading stdout to its end before stderr hung the check on
    /// a tool that filled the stderr pipe first.
    fn runCommand(self: *IntegrityChecker, args: []const []const u8) !CommandResult {
        const result = try std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = args,
            .max_output_bytes = 1024 * 1024,
        });
        return .{
            .exit_code = switch (result.term) {
                .Exited => |code| code,
                else => 1,
            },
            .stdout = result.stdout,
            .stderr = result.stderr,
        };
    }
};

/// What `zpool status -x` says, as a check. It prints "all pools are
/// healthy" when they are, the status of each pool that is not, and "no
/// pools available" on stderr when there is none -- exiting 0 in all three.
/// Plain `zpool status` was taken as healthy whenever it exited 0, a
/// degraded pool included.
fn zpoolStatus(result: CommandResult) struct { result: CheckResult, message: []const u8 } {
    const out = std.mem.trim(u8, result.stdout, " \t\r\n");
    if (result.exit_code != 0) {
        const why = firstLine(result.stderr);
        return .{ .result = .warn, .message = if (why.len == 0) "failed" else why };
    }
    if (std.mem.eql(u8, out, "all pools are healthy")) return .{ .result = .pass, .message = out };
    if (out.len == 0) return .{ .result = .warn, .message = "no ZFS pool" };
    return .{ .result = .warn, .message = firstLine(out) };
}

/// The first non-empty line of a tool's output, for a one-line report.
fn firstLine(text: []const u8) []const u8 {
    var lines = std.mem.tokenizeAny(u8, text, "\r\n");
    return std.mem.trim(u8, lines.next() orelse "", " \t");
}

test "a zpool check passes only when zpool says every pool is healthy" {
    const Case = struct { code: u32, out: []const u8, err: []const u8, want: CheckResult };
    const cases = [_]Case{
        .{ .code = 0, .out = "all pools are healthy\n", .err = "", .want = .pass },
        .{ .code = 0, .out = "", .err = "no pools available\n", .want = .warn },
        .{ .code = 0, .out = "  pool: tank\n state: DEGRADED\n", .err = "", .want = .warn },
        .{ .code = 1, .out = "", .err = "The ZFS modules are not loaded.\n", .want = .warn },
    };
    for (cases) |c| {
        const status = zpoolStatus(.{ .exit_code = c.code, .stdout = @constCast(c.out), .stderr = @constCast(c.err) });
        try std.testing.expectEqual(c.want, status.result);
    }
    try std.testing.expectEqualStrings("pool: tank", zpoolStatus(.{ .exit_code = 0, .stdout = @constCast(cases[2].out), .stderr = @constCast("") }).message);
}

/// Command execution result
const CommandResult = struct {
    exit_code: u32,
    stdout: []u8,
    stderr: []u8,

    pub fn deinit(self: CommandResult, allocator: std.mem.Allocator) void {
        allocator.free(self.stdout);
        allocator.free(self.stderr);
    }
};

/// Integrity check result
pub const CheckResult = enum {
    pass,
    warn,
    fail,
};

/// Individual integrity check
pub const IntegrityCheck = struct {
    name: []const u8,
    result: CheckResult,
    message: []const u8,

    pub fn deinit(self: *IntegrityCheck, allocator: std.mem.Allocator) void {
        allocator.free(self.message);
    }
};

/// System integrity report
pub const IntegrityReport = struct {
    allocator: std.mem.Allocator,
    checks: std.ArrayList(IntegrityCheck),
    timestamp: i64,

    pub fn init(allocator: std.mem.Allocator) IntegrityReport {
        return IntegrityReport{
            .allocator = allocator,
            .checks = std.ArrayList(IntegrityCheck){ .items = &[_]IntegrityCheck{}, .capacity = 0 },
            .timestamp = std.time.timestamp(),
        };
    }

    pub fn deinit(self: *IntegrityReport) void {
        for (self.checks.items) |*check| {
            check.deinit(self.allocator);
        }
        self.checks.deinit(self.allocator);
    }

    pub fn addCheck(self: *IntegrityReport, name: []const u8, result: CheckResult, comptime fmt: []const u8, args: anytype) !void {
        const message = try std.fmt.allocPrint(self.allocator, fmt, args);
        try self.checks.append(self.allocator, IntegrityCheck{
            .name = name,
            .result = result,
            .message = message,
        });
    }

    pub fn getSummary(self: *IntegrityReport) IntegritySummary {
        var summary = IntegritySummary{
            .total = self.checks.items.len,
            .passed = 0,
            .warnings = 0,
            .failed = 0,
        };

        for (self.checks.items) |check| {
            switch (check.result) {
                .pass => summary.passed += 1,
                .warn => summary.warnings += 1,
                .fail => summary.failed += 1,
            }
        }

        return summary;
    }

    pub fn printReport(self: *IntegrityReport, logger: ?*logging.LogContext) !void {
        if (logger) |log| {
            try log.info("=== System Integrity Report ===", .{});
            try log.info("Timestamp: {d}", .{self.timestamp});

            const summary = self.getSummary();
            try log.info("Summary: {d} total, {d} passed, {d} warnings, {d} failed", .{ summary.total, summary.passed, summary.warnings, summary.failed });

            for (self.checks.items) |check| {
                const status = switch (check.result) {
                    .pass => "✅ PASS",
                    .warn => "⚠️  WARN",
                    .fail => "❌ FAIL",
                };
                try log.info("{s} {s}: {s}", .{ status, check.name, check.message });
            }
        } else {
            std.debug.print("=== System Integrity Report ===\n", .{});
            std.debug.print("Timestamp: {d}\n", .{self.timestamp});

            const summary = self.getSummary();
            std.debug.print("Summary: {d} total, {d} passed, {d} warnings, {d} failed\n", .{ summary.total, summary.passed, summary.warnings, summary.failed });

            for (self.checks.items) |check| {
                const status = switch (check.result) {
                    .pass => "✅ PASS",
                    .warn => "⚠️  WARN",
                    .fail => "❌ FAIL",
                };
                std.debug.print("{s} {s}: {s}\n", .{ status, check.name, check.message });
            }
        }
    }
};

/// Integrity report summary
pub const IntegritySummary = struct {
    total: usize,
    passed: usize,
    warnings: usize,
    failed: usize,
};
