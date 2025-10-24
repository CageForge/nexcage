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
        
    pub fn validate(_: *Self, _: core.RuntimeOptions) !void {
        // No validation needed for health check
    }
    
    pub fn help() []const u8 {
        return 
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
            \\  0  - All checks passed
            \\  1  - Warnings detected
            \\  2  - Failures detected
            \\
        ;
    }
    
    pub fn execute(self: *HealthCommand, _: core.RuntimeOptions, allocator: std.mem.Allocator) !void {
        _ = self;
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
