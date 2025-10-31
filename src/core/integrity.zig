const std = @import("std");
const logging = @import("logging.zig");

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
    
    /// Check system integrity
    pub fn checkSystemIntegrity(self: *IntegrityChecker) !IntegrityReport {
        var report = IntegrityReport.init(self.allocator);
        errdefer report.deinit();
        
        // Check critical system components
        try self.checkProxmoxConnectivity(&report);
        try self.checkStorageIntegrity(&report);
        try self.checkNetworkIntegrity(&report);
        try self.checkConfigurationIntegrity(&report);
        try self.checkProcessIntegrity(&report);
        
        return report;
    }
    
    /// Check Proxmox connectivity
    fn checkProxmoxConnectivity(self: *IntegrityChecker, report: *IntegrityReport) !void {
        if (self.logger) |log| try log.info("Checking Proxmox connectivity...", .{});
        
        // Check if pct command is available
        const pct_check = self.runCommand(&[_][]const u8{"pct", "version"});
        if (pct_check) |result| {
            if (result.exit_code == 0) {
                try report.addCheck("proxmox_pct_available", .pass, "pct command available", .{});
            } else {
                try report.addCheck("proxmox_pct_available", .fail, "pct command failed", .{});
            }
        } else |err| {
            try report.addCheck("proxmox_pct_available", .fail, "pct command not found: {}", .{err});
        }
        
        // Check Proxmox API connectivity (if configured)
        const api_check = self.checkProxmoxApi();
        if (api_check) {
            try report.addCheck("proxmox_api_connectivity", .pass, "Proxmox API accessible", .{});
        } else {
            try report.addCheck("proxmox_api_connectivity", .warn, "Proxmox API not accessible", .{});
        }
    }
    
    /// Check storage integrity
    fn checkStorageIntegrity(self: *IntegrityChecker, report: *IntegrityReport) !void {
        if (self.logger) |log| try log.info("Checking storage integrity...", .{});
        
        // Check if storage directories exist and are writable
        const storage_paths = [_][]const u8{
            "/var/lib/nexcage",
            "/var/cache/nexcage", 
            "/tmp/nexcage",
            "/etc/pve/lxc",
        };
        
        for (storage_paths) |path| {
            const path_check = self.checkPathAccess(path);
            if (path_check) {
                try report.addCheck("storage_path", .pass, "Path accessible: {s}", .{path});
            } else |err| {
                try report.addCheck("storage_path", .fail, "Path not accessible: {s} ({})", .{ path, err });
            }
        }
        
        // Check ZFS pool status (if available)
        const zfs_check = self.checkZfsPool();
        if (zfs_check) |pool_status| {
            defer self.allocator.free(pool_status);
            try report.addCheck("zfs_pool_status", .pass, "ZFS pool healthy: {s}", .{pool_status});
        } else |err| {
            try report.addCheck("zfs_pool_status", .warn, "ZFS pool check failed: {}", .{err});
        }
    }
    
    /// Check network integrity
    fn checkNetworkIntegrity(self: *IntegrityChecker, report: *IntegrityReport) !void {
        if (self.logger) |log| try log.info("Checking network integrity...", .{});
        
        // Check if network interfaces are up
        const network_check = self.checkNetworkInterfaces();
        if (network_check) {
            try report.addCheck("network_interfaces", .pass, "Network interfaces operational", .{});
        } else {
            try report.addCheck("network_interfaces", .warn, "Network interface issues detected", .{});
        }
        
        // Check DNS resolution
        const dns_check = self.checkDnsResolution();
        if (dns_check) {
            try report.addCheck("dns_resolution", .pass, "DNS resolution working", .{});
        } else {
            try report.addCheck("dns_resolution", .warn, "DNS resolution issues", .{});
        }
    }
    
    /// Check configuration integrity
    fn checkConfigurationIntegrity(self: *IntegrityChecker, report: *IntegrityReport) !void {
        if (self.logger) |log| try log.info("Checking configuration integrity...", .{});
        
        // Check if config file exists and is readable
        const config_paths = [_][]const u8{
            "/etc/nexcage/config.json",
            "config.json",
        };
        
        var config_found = false;
        for (config_paths) |path| {
            if (self.checkPathAccess(path)) {
                try report.addCheck("config_file", .pass, "Config file found: {s}", .{path});
                config_found = true;
                break;
            } else |_| {
                // Path not accessible, continue to next
            }
        }
        
        if (!config_found) {
            try report.addCheck("config_file", .warn, "No config file found in standard locations", .{});
        }
        
        // Check if config is valid JSON
        if (config_found) {
            const json_check = self.validateConfigJson();
            if (json_check) {
                try report.addCheck("config_json_valid", .pass, "Config file contains valid JSON", .{});
            } else {
                try report.addCheck("config_json_valid", .fail, "Config file contains invalid JSON", .{});
            }
        }
    }
    
    /// Check process integrity
    fn checkProcessIntegrity(self: *IntegrityChecker, report: *IntegrityReport) !void {
        if (self.logger) |log| try log.info("Checking process integrity...", .{});
        
        // Check if nexcage process is running
        const process_check = self.checkNexcageProcess();
        if (process_check) {
            try report.addCheck("nexcage_process", .pass, "nexcage process running", .{});
        } else {
            try report.addCheck("nexcage_process", .warn, "nexcage process not detected", .{});
        }
        
        // Check system resources
        const resources_check = self.checkSystemResources();
        if (resources_check) {
            try report.addCheck("system_resources", .pass, "System resources adequate", .{});
        } else {
            try report.addCheck("system_resources", .warn, "System resource constraints detected", .{});
        }
    }
    
    /// Run a command and return result
    fn runCommand(self: *IntegrityChecker, args: []const []const u8) !CommandResult {
        var result = CommandResult{
            .exit_code = 0,
            .stdout = &[_]u8{},
            .stderr = &[_]u8{},
        };
        
        var child = std.process.Child.init(args, self.allocator);
        
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Pipe;
        
        try child.spawn();
        
        const stdout = try child.stdout.?.readToEndAlloc(self.allocator, 1024 * 1024);
        defer self.allocator.free(stdout);
        
        const stderr = try child.stderr.?.readToEndAlloc(self.allocator, 1024 * 1024);
        defer self.allocator.free(stderr);
        
        const term = try child.wait();
        result.exit_code = switch (term) {
            .Exited => |code| code,
            else => 1,
        };
        result.stdout = try self.allocator.dupe(u8, stdout);
        result.stderr = try self.allocator.dupe(u8, stderr);
        
        return result;
    }
    
    /// Check if Proxmox API is accessible
    /// Note: Currently not implemented as we use pct CLI instead of direct API
    fn checkProxmoxApi(_: *IntegrityChecker) bool {
        // Proxmox API check not implemented - using pct CLI for operations
        // To implement: add HTTP client to query /api2/json/access/ticket
        return false;
    }
    
    /// Check if path is accessible
    fn checkPathAccess(_: *IntegrityChecker, path: []const u8) !void {
        // Check if path is absolute
        if (std.fs.path.isAbsolute(path)) {
            const file = std.fs.openFileAbsolute(path, .{}) catch return error.FileNotFound;
            file.close();
        } else {
            // Try relative path
            const rel_file = std.fs.cwd().openFile(path, .{}) catch return error.FileNotFound;
            rel_file.close();
        }
    }
    
    /// Check ZFS pool status
    fn checkZfsPool(self: *IntegrityChecker) ![]const u8 {
        const result = try self.runCommand(&[_][]const u8{"zpool", "status"});
        defer {
            self.allocator.free(result.stdout);
            self.allocator.free(result.stderr);
        }
        
        if (result.exit_code == 0) {
            return try self.allocator.dupe(u8, result.stdout);
        } else {
            return error.ZfsCheckFailed;
        }
    }
    
    /// Check network interfaces
    fn checkNetworkInterfaces(self: *IntegrityChecker) bool {
        const result = self.runCommand(&[_][]const u8{"ip", "link", "show"}) catch return false;
        defer {
            self.allocator.free(result.stdout);
            self.allocator.free(result.stderr);
        }
        
        return result.exit_code == 0;
    }
    
    /// Check DNS resolution
    fn checkDnsResolution(self: *IntegrityChecker) bool {
        const result = self.runCommand(&[_][]const u8{"nslookup", "google.com"}) catch return false;
        defer {
            self.allocator.free(result.stdout);
            self.allocator.free(result.stderr);
        }
        
        return result.exit_code == 0;
    }
    
    /// Validate config JSON
    fn validateConfigJson(self: *IntegrityChecker) bool {
        const config_paths = [_][]const u8{
            "/etc/nexcage/config.json",
            "config.json",
        };
        
        for (config_paths) |path| {
            // Check if path is absolute
            const file = if (std.fs.path.isAbsolute(path))
                std.fs.openFileAbsolute(path, .{}) catch continue
            else
                std.fs.cwd().openFile(path, .{}) catch continue;
            
            defer file.close();
            
            const content = file.readToEndAlloc(self.allocator, 1024 * 1024) catch continue;
            defer self.allocator.free(content);
            
            var parsed = std.json.parseFromSlice(std.json.Value, self.allocator, content, .{}) catch continue;
            defer parsed.deinit();
            
            return true;
        }
        
        return false;
    }
    
    /// Check if nexcage process is running
    fn checkNexcageProcess(self: *IntegrityChecker) bool {
        const result = self.runCommand(&[_][]const u8{"pgrep", "nexcage"}) catch return false;
        defer {
            self.allocator.free(result.stdout);
            self.allocator.free(result.stderr);
        }
        
        return result.exit_code == 0 and result.stdout.len > 0;
    }
    
    /// Check system resources
    fn checkSystemResources(self: *IntegrityChecker) bool {
        const result = self.runCommand(&[_][]const u8{"df", "-h", "/"}) catch return false;
        defer {
            self.allocator.free(result.stdout);
            self.allocator.free(result.stderr);
        }
        
        return result.exit_code == 0;
    }
};

/// Command execution result
const CommandResult = struct {
    exit_code: u32,
    stdout: []u8,
    stderr: []u8,
    
    pub fn deinit(self: *CommandResult, allocator: std.mem.Allocator) void {
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
            try log.info("Summary: {d} total, {d} passed, {d} warnings, {d} failed", .{ 
                summary.total, summary.passed, summary.warnings, summary.failed 
            });
            
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
            std.debug.print("Summary: {d} total, {d} passed, {d} warnings, {d} failed\n", .{ 
                summary.total, summary.passed, summary.warnings, summary.failed 
            });
            
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
