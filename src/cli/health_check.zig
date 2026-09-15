const std = @import("std");
const core = @import("core");
const base_command = @import("base_command.zig");

/// Health check command for system integrity
pub const HealthCommand = struct {
    const Self = @This();

    name: []const u8 = "health",
    description: []const u8 = "Check system integrity and health",
    base: base_command.BaseCommand = .{},

    pub fn setLogger(self: *Self, logger: *core.LogContext) void {
        self.base.setLogger(logger);
    }

    pub fn validate(_: *Self, _: []const []const u8) !void {
        // No validation needed for health check
    }

    pub fn help(self: *Self, allocator: std.mem.Allocator) ![]const u8 {
        _ = self;
        // Allocated like the other commands' help, so callers can free it
        return allocator.dupe(u8,
            \\Health Check Command
            \\
            \\Usage: nexcage health [options]
            \\
            \\Description:
            \\  Performs system integrity checks to verify that all critical components
            \\  are functioning correctly.
            \\
            \\Options:
            \\  --help     Show this help message
            \\
            \\Examples:
            \\  nexcage health                    # Run full system integrity check
            \\
            \\The health check verifies:
            \\  - Proxmox connectivity (pct command, API)
            \\  - Storage integrity (directories, ZFS pools)
            \\  - Network integrity (interfaces, DNS)
            \\  - Configuration integrity (config files, JSON validity)
            \\  - Process integrity (nexcage process, system resources)
            \\
            \\Exit codes:
            \\  0  - No check failed (warnings are reported but do not fail)
            \\  1  - At least one check failed
            \\
        );
    }

    pub fn execute(self: *HealthCommand, options: core.RuntimeOptions, allocator: std.mem.Allocator) !void {
        // --help used to run the whole check
        if (options.help) {
            const help_text = try self.help(allocator);
            defer allocator.free(help_text);
            try std.fs.File.stdout().writeAll(help_text);
            return;
        }

        std.debug.print("Starting system integrity check...\n", .{});

        // Initialize integrity checker
        var checker = core.IntegrityChecker.init(allocator, null);

        // Run integrity checks
        var report = try checker.checkSystemIntegrity();
        defer report.deinit();

        // Print report
        try report.printReport(null);

        // Determine exit code based on results
        const summary = report.getSummary();
        if (summary.failed > 0) {
            std.debug.print("System integrity check failed: {d} failures detected\n", .{summary.failed});
            return core.Error.OperationFailed;
        } else if (summary.warnings > 0) {
            std.debug.print("System integrity check completed with {d} warnings\n", .{summary.warnings});
        } else {
            std.debug.print("System integrity check passed: all {d} checks successful\n", .{summary.total});
        }
    }
};
