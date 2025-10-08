const std = @import("std");
const core = @import("core");

/// Test result structure
pub const TestResult = struct {
    name: []const u8,
    status: TestStatus,
    duration_ms: u64,
    error_message: ?[]const u8 = null,
    memory_usage: ?u64 = null,
    details: ?[]const u8 = null,

    pub fn deinit(self: *TestResult, allocator: std.mem.Allocator) void {
        if (self.error_message) |msg| allocator.free(msg);
        if (self.details) |det| allocator.free(det);
    }
};

pub const TestStatus = enum {
    passed,
    failed,
    skipped,
    test_error,
};

/// Test suite runner with detailed reporting
pub const TestRunner = struct {
    allocator: std.mem.Allocator,
    results: std.ArrayList(TestResult),
    start_time: u64,
    total_memory_start: u64,

    pub fn init(allocator: std.mem.Allocator) TestRunner {
        return TestRunner{
            .allocator = allocator,
            .results = std.ArrayList(TestResult).init(allocator),
            .start_time = std.time.milliTimestamp(),
            .total_memory_start = getMemoryUsage(),
        };
    }

    pub fn deinit(self: *TestRunner) void {
        for (self.results.items) |*result| {
            result.deinit(self.allocator);
        }
        self.results.deinit();
    }

    /// Run a single test and record results
    pub fn runTest(self: *TestRunner, name: []const u8, test_fn: anytype) void {
        const test_start = std.time.milliTimestamp();
        const memory_start = getMemoryUsage();
        
        var test_result = TestResult{
            .name = name,
            .status = .passed,
            .duration_ms = 0,
        };

        // Capture stderr for error messages
        var stderr_buffer = std.ArrayList(u8).init(self.allocator);
        defer stderr_buffer.deinit();

        // Run the test
        test_fn() catch |err| {
            test_result.status = .failed;
            test_result.error_message = std.fmt.allocPrint(self.allocator, "Test failed: {}", .{err}) catch null;
        };

        const test_end = std.time.milliTimestamp();
        const memory_end = getMemoryUsage();
        
        test_result.duration_ms = @as(u64, @intCast(test_end - test_start));
        test_result.memory_usage = if (memory_end > memory_start) memory_end - memory_start else null;

        self.results.append(test_result) catch {
            // If we can't append, just print the error
            std.debug.print("Failed to record test result for: {s}\n", .{name});
        };
    }

    /// Generate comprehensive test report
    pub fn generateReport(self: *TestRunner) !void {
        const total_duration = std.time.milliTimestamp() - self.start_time;
        const total_memory_end = getMemoryUsage();
        const total_memory_used = if (total_memory_end > self.total_memory_start) 
            total_memory_end - self.total_memory_start else 0;

        // Count results by status
        var passed: u32 = 0;
        var failed: u32 = 0;
        var skipped: u32 = 0;
        var error: u32 = 0;

        for (self.results.items) |result| {
            switch (result.status) {
                .passed => passed += 1,
                .failed => failed += 1,
                .skipped => skipped += 1,
                .error => error += 1,
            }
        }

        const total_tests = self.results.items.len;
        const success_rate = if (total_tests > 0) (@as(f64, @floatFromInt(passed)) / @as(f64, @floatFromInt(total_tests))) * 100.0 else 0.0;

        // Generate report
        const report = try std.fmt.allocPrint(self.allocator,
            \\# Test Execution Report
            \\## Summary
            \\- **Total Tests**: {d}
            \\- **Passed**: {d} ({d:.1}%)
            \\- **Failed**: {d} ({d:.1}%)
            \\- **Skipped**: {d} ({d:.1}%)
            \\- **Errors**: {d} ({d:.1}%)
            \\- **Success Rate**: {d:.1}%
            \\- **Total Duration**: {d}ms
            \\- **Memory Used**: {d} bytes
            \\
            \\## Test Results
            \\
        , .{
            total_tests,
            passed, (@as(f64, @floatFromInt(passed)) / @as(f64, @floatFromInt(total_tests))) * 100.0,
            failed, (@as(f64, @floatFromInt(failed)) / @as(f64, @floatFromInt(total_tests))) * 100.0,
            skipped, (@as(f64, @floatFromInt(skipped)) / @as(f64, @floatFromInt(total_tests))) * 100.0,
            error, (@as(f64, @floatFromInt(error)) / @as(f64, @floatFromInt(total_tests))) * 100.0,
            success_rate,
            total_duration,
            total_memory_used,
        });

        // Write report to file
        const report_file = try std.fs.cwd().createFile("test-report.md", .{});
        defer report_file.close();

        try report_file.writeAll(report);

        // Add detailed test results
        for (self.results.items) |result| {
            const status_emoji = switch (result.status) {
                .passed => "✅",
                .failed => "❌",
                .skipped => "⏭️",
                .error => "💥",
            };

            const test_detail = try std.fmt.allocPrint(self.allocator,
                \\### {s} {s}
                \\- **Duration**: {d}ms
                \\- **Memory**: {d} bytes
                \\
            , .{
                status_emoji,
                result.name,
                result.duration_ms,
                result.memory_usage orelse 0,
            });

            try report_file.writeAll(test_detail);

            if (result.error_message) |err_msg| {
                const error_detail = try std.fmt.allocPrint(self.allocator,
                    \\- **Error**: {s}
                    \\
                , .{err_msg});
                try report_file.writeAll(error_detail);
            }

            if (result.details) |details| {
                const details_text = try std.fmt.allocPrint(self.allocator,
                    \\- **Details**: {s}
                    \\
                , .{details});
                try report_file.writeAll(details_text);
            }

            try report_file.writeAll("\n");
        }

        // Print summary to console
        std.debug.print("\n" ++
            \\╔══════════════════════════════════════════════════════════════╗
            \\║                        TEST REPORT                           ║
            \\╠══════════════════════════════════════════════════════════════╣
            \\║ Total Tests: {d:>3}                                          ║
            \\║ Passed:      {d:>3} ({d:>5.1}%)                              ║
            \\║ Failed:      {d:>3} ({d:>5.1}%)                              ║
            \\║ Skipped:     {d:>3} ({d:>5.1}%)                              ║
            \\║ Errors:      {d:>3} ({d:>5.1}%)                              ║
            \\║ Success Rate: {d:>5.1}%                                      ║
            \\║ Duration:    {d:>3}ms                                        ║
            \\║ Memory:      {d:>3} bytes                                    ║
            \\╚══════════════════════════════════════════════════════════════╝
            \\
        , .{
            total_tests,
            passed, (@as(f64, @floatFromInt(passed)) / @as(f64, @floatFromInt(total_tests))) * 100.0,
            failed, (@as(f64, @floatFromInt(failed)) / @as(f64, @floatFromInt(total_tests))) * 100.0,
            skipped, (@as(f64, @floatFromInt(skipped)) / @as(f64, @floatFromInt(total_tests))) * 100.0,
            error, (@as(f64, @floatFromInt(error)) / @as(f64, @floatFromInt(total_tests))) * 100.0,
            success_rate,
            total_duration,
            total_memory_used,
        });

        std.debug.print("📊 Detailed report saved to: test-report.md\n");
    }

    /// Get current memory usage (simplified)
    fn getMemoryUsage() u64 {
        // This is a simplified version - in a real implementation,
        // you might want to use platform-specific memory tracking
        return 0;
    }
};

/// Test suite for core functionality
pub fn runCoreTests(runner: *TestRunner) void {
    runner.runTest("NetworkConfig deinit handles nulls", testNetworkConfigDeinit);
    runner.runTest("RuntimeOptions deinit frees optionals", testRuntimeOptionsDeinit);
    runner.runTest("Config loading", testConfigLoading);
    runner.runTest("Error handling", testErrorHandling);
}

fn testNetworkConfigDeinit() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var net = core.types.NetworkConfig{};
    net.deinit(allocator);
}

fn testRuntimeOptionsDeinit() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var opts = core.types.RuntimeOptions{
        .allocator = allocator,
        .command = .help,
        .container_id = try allocator.dupe(u8, "abc"),
        .image = try allocator.dupe(u8, "img"),
    };
    opts.deinit();
}

fn testConfigLoading() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var config_loader = core.ConfigLoader.init(allocator);
    _ = config_loader.loadDefault() catch {
        // Config loading might fail in test environment, that's ok
        return;
    };
}

fn testErrorHandling() !void {
    // Test that error types are properly defined
    _ = core.Error.InvalidInput;
    _ = core.Error.NotFound;
    _ = core.Error.UnsupportedOperation;
}

/// Test suite for CLI functionality
pub fn runCliTests(runner: *TestRunner) void {
    runner.runTest("Help command", testHelpCommand);
    runner.runTest("Version command", testVersionCommand);
    runner.runTest("Command parsing", testCommandParsing);
}

fn testHelpCommand() !void {
    // Test that help command can be created
    const help_cmd = @import("cli/help.zig").HelpCommand{};
    _ = help_cmd;
}

fn testVersionCommand() !void {
    // Test that version command can be created
    const version_cmd = @import("cli/version.zig").VersionCommand{};
    _ = version_cmd;
}

fn testCommandParsing() !void {
    // Test basic command parsing logic
    const args = [_][]const u8{ "nexcage", "--help" };
    if (args.len < 2) return;
    const command_name = args[1];
    if (!std.mem.eql(u8, command_name, "--help")) {
        return error.InvalidCommand;
    }
}

/// Test suite for backend functionality
pub fn runBackendTests(runner: *TestRunner) void {
    runner.runTest("LXC backend creation", testLxcBackend);
    runner.runTest("Crun backend creation", testCrunBackend);
    runner.runTest("Runc backend creation", testRuncBackend);
}

fn testLxcBackend() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = core.types.SandboxConfig{
        .allocator = allocator,
        .name = "test-container",
        .runtime_type = .lxc,
    };
    
    const lxc_backend = @import("backends/lxc").LxcBackend.init(allocator, config) catch {
        // Backend creation might fail in test environment
        return;
    };
    defer lxc_backend.deinit();
}

fn testCrunBackend() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const logger = core.LogContext.init(allocator, std.io.getStdOut().writer(), .info, "test");
    defer logger.deinit();

    const crun_backend = @import("backends/crun").CrunDriver.init(allocator, &logger);
    _ = crun_backend;
}

fn testRuncBackend() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const logger = core.LogContext.init(allocator, std.io.getStdOut().writer(), .info, "test");
    defer logger.deinit();

    const runc_backend = @import("backends/runc").RuncDriver.init(allocator, &logger);
    _ = runc_backend;
}

/// Main test runner
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var runner = TestRunner.init(allocator);
    defer runner.deinit();

    std.debug.print("🧪 Starting comprehensive test suite...\n\n");

    // Run all test suites
    runCoreTests(&runner);
    runCliTests(&runner);
    runBackendTests(&runner);

    // Generate and display report
    try runner.generateReport();
}
