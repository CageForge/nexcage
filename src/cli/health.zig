const std = @import("std");
const core = @import("../core/mod.zig");
const base_command = @import("base_command.zig");

/// Health check command for system integrity
pub const HealthCommand = struct {
    base: base_command.BaseCommand,
    
    pub fn init(allocator: std.mem.Allocator, logger: ?*core.logging.Logger) HealthCommand {
        return HealthCommand{
            .base = base_command.BaseCommand.init(allocator, logger, "health"),
        };
    }
    
    pub fn deinit(self: *HealthCommand) void {
        self.base.deinit();
    }
    
    pub fn execute(self: *HealthCommand, options: core.RuntimeOptions, allocator: std.mem.Allocator) !void {
        if (self.base.logger) |log| {
            try log.info("Starting system integrity check...");
        }
        
        // Initialize integrity checker
        var checker = core.IntegrityChecker.init(allocator, self.base.logger);
        
        // Run integrity checks
        var report = try checker.checkSystemIntegrity();
        defer report.deinit();
        
        // Print report
        report.printReport(self.base.logger);
        
        // Determine exit code based on results
        const summary = report.getSummary();
        if (summary.failed > 0) {
            if (self.base.logger) |log| {
                try log.err("System integrity check failed: {d} failures detected", .{summary.failed});
            }
            return core.Error.OperationFailed;
        } else if (summary.warnings > 0) {
            if (self.base.logger) |log| {
                try log.warn("System integrity check completed with {d} warnings", .{summary.warnings});
            }
        } else {
            if (self.base.logger) |log| {
                try log.info("System integrity check passed: all {d} checks successful", .{summary.total});
            }
        }
    }
    
    pub fn getHelp(self: *HealthCommand) []const u8 {
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
};
