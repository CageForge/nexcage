const std = @import("std");
const Allocator = std.mem.Allocator;
const Logger = @import("logger").Logger;
const PerformanceMetrics = @import("monitor.zig").PerformanceMetrics;
const time = std.time;
const mem = std.mem;

/// Performance test type
pub const TestType = enum {
    load, // Load testing
    stress, // Stress testing
    endurance, // Endurance testing
    spike, // Spike testing
    scalability, // Scalability testing
    custom, // Custom test
};

/// Test result status
pub const TestStatus = enum {
    pending,
    running,
    completed,
    failed,
    cancelled,
};

/// Performance test configuration
pub const TestConfig = struct {
    test_type: TestType,
    duration_seconds: u64,
    target_load: u32, // requests per second
    max_concurrent_users: u32,
    ramp_up_time: u64, // seconds
    ramp_down_time: u64, // seconds
    think_time: u64, // milliseconds between requests
    timeout: u64, // milliseconds
    custom_parameters: std.StringHashMap([]const u8),

    pub fn init(test_type: TestType) TestConfig {
        return .{
            .test_type = test_type,
            .duration_seconds = 300, // 5 minutes default
            .target_load = 100,
            .max_concurrent_users = 50,
            .ramp_up_time = 60,
            .ramp_down_time = 30,
            .think_time = 1000,
            .timeout = 5000,
            .custom_parameters = std.StringHashMap([]const u8).init(std.heap.page_allocator),
        };
    }

    pub fn deinit(self: *TestConfig) void {
        self.custom_parameters.deinit();
    }

    /// Set custom parameter
    pub fn setParameter(self: *TestConfig, key: []const u8, value: []const u8) !void {
        try self.custom_parameters.put(key, value);
    }

    /// Get custom parameter
    pub fn getParameter(self: *TestConfig, key: []const u8) ?[]const u8 {
        return self.custom_parameters.get(key);
    }
};

/// Performance test result
pub const TestResult = struct {
    test_id: []const u8,
    test_type: TestType,
    status: TestStatus,
    start_time: i64,
    end_time: ?i64,
    duration_seconds: u64,
    total_requests: u64,
    successful_requests: u64,
    failed_requests: u64,
    average_response_time: u64, // milliseconds
    min_response_time: u64, // milliseconds
    max_response_time: u64, // milliseconds
    requests_per_second: f64,
    error_rate: f64, // percentage
    cpu_usage_avg: f64,
    memory_usage_avg: u64,
    network_usage_avg: u64,
    disk_usage_avg: u64,
    container_count_avg: u32,
    error_messages: std.ArrayList([]const u8),
    performance_metrics: std.ArrayList(PerformanceMetrics),

    pub fn init(test_id: []const u8, test_type: TestType) TestResult {
        return .{
            .test_id = test_id,
            .test_type = test_type,
            .status = .pending,
            .start_time = 0,
            .end_time = null,
            .duration_seconds = 0,
            .total_requests = 0,
            .successful_requests = 0,
            .failed_requests = 0,
            .average_response_time = 0,
            .min_response_time = 0,
            .max_response_time = 0,
            .requests_per_second = 0.0,
            .error_rate = 0.0,
            .cpu_usage_avg = 0.0,
            .memory_usage_avg = 0,
            .network_usage_avg = 0,
            .disk_usage_avg = 0,
            .container_count_avg = 0,
            .error_messages = std.ArrayList([]const u8).init(std.heap.page_allocator),
            .performance_metrics = std.ArrayList(PerformanceMetrics).init(std.heap.page_allocator),
        };
    }

    pub fn deinit(self: *TestResult) void {
        self.error_messages.deinit();
        self.performance_metrics.deinit();
    }

    /// Start the test
    pub fn start(self: *TestResult) void {
        self.status = .running;
        self.start_time = time.timestamp();
    }

    /// Complete the test
    pub fn complete(self: *TestResult) void {
        self.status = .completed;
        self.end_time = time.timestamp();
        if (self.start_time > 0) {
            self.duration_seconds = @as(u64, @intCast(self.end_time.? - self.start_time));
        }
    }

    /// Fail the test
    pub fn fail(self: *TestResult, error_message: []const u8) !void {
        self.status = .failed;
        self.end_time = time.timestamp();
        try self.error_messages.append(error_message);

        if (self.start_time > 0) {
            self.duration_seconds = @as(u64, @intCast(self.end_time.? - self.start_time));
        }
    }

    /// Add performance metrics
    pub fn addMetrics(self: *TestResult, metrics: PerformanceMetrics) !void {
        try self.performance_metrics.append(metrics);
    }

    /// Calculate final statistics
    pub fn calculateStatistics(self: *TestResult) void {
        if (self.performance_metrics.items.len == 0) return;

        var total_cpu: f64 = 0.0;
        var total_memory: u64 = 0;
        var total_network: u64 = 0;
        var total_disk: u64 = 0;
        var total_containers: u32 = 0;
        var total_response_time: u64 = 0;
        var min_rt: u64 = std.math.maxInt(u64);
        var max_rt: u64 = 0;

        for (self.performance_metrics.items) |metrics| {
            total_cpu += metrics.cpu_usage;
            total_memory += metrics.memory_usage;
            total_network += metrics.network_rx + metrics.network_tx;
            total_disk += metrics.disk_read + metrics.disk_write;
            total_containers += metrics.container_count;
            total_response_time += metrics.response_time;

            if (metrics.response_time < min_rt) min_rt = metrics.response_time;
            if (metrics.response_time > max_rt) max_rt = metrics.response_time;
        }

        const count = @as(f64, @floatFromInt(self.performance_metrics.items.len));
        self.cpu_usage_avg = total_cpu / count;
        self.memory_usage_avg = @as(u64, @intFromFloat(total_memory / count));
        self.network_usage_avg = @as(u64, @intFromFloat(total_network / count));
        self.disk_usage_avg = @as(u64, @intFromFloat(total_disk / count));
        self.container_count_avg = @as(u32, @intFromFloat(total_containers / count));

        if (self.total_requests > 0) {
            self.average_response_time = @as(u64, @intFromFloat(@as(f64, @floatFromInt(total_response_time)) / count));
            self.requests_per_second = @as(f64, @floatFromInt(self.total_requests)) / @as(f64, @floatFromInt(self.duration_seconds));
            self.error_rate = @as(f64, @floatFromInt(self.failed_requests)) / @as(f64, @floatFromInt(self.total_requests)) * 100.0;
        }

        self.min_response_time = min_rt;
        self.max_response_time = max_rt;
    }

    /// Generate test report
    pub fn generateReport(self: *TestResult) ![]const u8 {
        var report = std.ArrayList(u8).init(std.heap.page_allocator);
        defer report.deinit();

        try report.writer().print(
            \\Performance Test Report
            \\======================
            \\Test ID: {s}
            \\Test Type: {s}
            \\Status: {s}
            \\Duration: {d} seconds
            \\
            \\Request Statistics:
            \\  Total Requests: {d}
            \\  Successful: {d}
            \\  Failed: {d}
            \\  Success Rate: {d:.1}%
            \\  Error Rate: {d:.1}%
            \\  Requests/Second: {d:.2}
            \\
            \\Response Time Statistics:
            \\  Average: {d}ms
            \\  Minimum: {d}ms
            \\  Maximum: {d}ms
            \\
            \\System Performance:
            \\  CPU Usage (Avg): {d:.2}%
            \\  Memory Usage (Avg): {d} bytes
            \\  Network Usage (Avg): {d} bytes
            \\  Disk Usage (Avg): {d} bytes
            \\  Container Count (Avg): {d}
            \\
        , .{
            self.test_id,
            @tagName(self.test_type),
            @tagName(self.status),
            self.duration_seconds,
            self.total_requests,
            self.successful_requests,
            self.failed_requests,
            if (self.total_requests > 0)
                @as(f64, @floatFromInt(self.successful_requests)) / @as(f64, @floatFromInt(self.total_requests)) * 100.0
            else
                0.0,
            self.error_rate,
            self.requests_per_second,
            self.average_response_time,
            self.min_response_time,
            self.max_response_time,
            self.cpu_usage_avg,
            self.memory_usage_avg,
            self.network_usage_avg,
            self.disk_usage_avg,
            self.container_count_avg,
        });

        // Add error messages if any
        if (self.error_messages.items.len > 0) {
            try report.writer().print(
                \\
                \\Error Messages ({d}):
                \\
            , .{self.error_messages.items.len});

            for (self.error_messages.items) |err_msg| {
                try report.writer().print("  • {s}\n", .{err_msg});
            }
        }

        return report.toOwnedSlice();
    }
};

/// Performance test
pub const PerformanceTest = struct {
    id: []const u8,
    name: []const u8,
    description: []const u8,
    config: TestConfig,
    result: TestResult,
    is_running: bool,
    start_time: ?i64,

    pub fn init(id: []const u8, name: []const u8, description: []const u8, config: TestConfig) PerformanceTest {
        return .{
            .id = id,
            .name = name,
            .description = description,
            .config = config,
            .result = TestResult.init(id, config.test_type),
            .is_running = false,
            .start_time = null,
        };
    }

    pub fn deinit(self: *PerformanceTest) void {
        self.result.deinit();
        self.config.deinit();
    }

    /// Start the test
    pub fn start(self: *PerformanceTest) !void {
        if (self.is_running) {
            return error.TestAlreadyRunning;
        }

        self.is_running = true;
        self.start_time = time.timestamp();
        self.result.start();

        try std.log.info("Started performance test: {s} ({s})", .{ self.name, self.id });
    }

    /// Stop the test
    pub fn stop(self: *PerformanceTest) !void {
        if (!self.is_running) {
            return error.TestNotRunning;
        }

        self.is_running = false;
        self.result.complete();
        self.result.calculateStatistics();

        try std.log.info("Completed performance test: {s} ({s})", .{ self.name, self.id });
    }

    /// Add test result data
    pub fn addResultData(self: *PerformanceTest, metrics: PerformanceMetrics, response_time: u64, success: bool) !void {
        if (!self.is_running) return;

        self.result.total_requests += 1;
        if (success) {
            self.result.successful_requests += 1;
        } else {
            self.result.failed_requests += 1;
        }

        // Update response time statistics
        if (self.result.min_response_time == 0 or response_time < self.result.min_response_time) {
            self.result.min_response_time = response_time;
        }
        if (response_time > self.result.max_response_time) {
            self.result.max_response_time = response_time;
        }

        // Add performance metrics
        try self.result.addMetrics(metrics);
    }

    /// Get test status
    pub fn getStatus(self: *PerformanceTest) TestStatus {
        return self.result.status;
    }

    /// Get test result
    pub fn getResult(self: *PerformanceTest) *TestResult {
        return &self.result;
    }
};

/// Performance tester that manages and executes performance tests
pub const PerformanceTester = struct {
    allocator: Allocator,
    logger: *Logger,
    tests: std.ArrayList(*PerformanceTest),
    active_tests: std.ArrayList(*PerformanceTest),
    max_concurrent_tests: usize,
    test_timeout: u64, // seconds

    const Self = @This();

    pub fn init(allocator: Allocator, logger: *Logger) !*Self {
        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .logger = logger,
            .tests = std.ArrayList(*PerformanceTest).init(allocator),
            .active_tests = std.ArrayList(*PerformanceTest).init(allocator),
            .max_concurrent_tests = 5,
            .test_timeout = 3600, // 1 hour default
        };
        return self;
    }

    pub fn deinit(self: *Self) void {
        // Stop all active tests
        for (self.active_tests.items) |active_test| {
            if (active_test.is_running) {
                active_test.stop() catch {};
            }
        }

        // Deinit all tests
        for (self.tests.items) |test_item| {
            test_item.deinit();
            self.allocator.destroy(test_item);
        }

        self.tests.deinit();
        self.active_tests.deinit();
        self.allocator.destroy(self);
    }

    /// Create a new performance test
    pub fn createTest(self: *Self, name: []const u8, description: []const u8, config: TestConfig) !*PerformanceTest {
        const test_id = try self.generateTestId();
        const test_item = try self.allocator.create(PerformanceTest);
        test_item.* = PerformanceTest.init(test_id, name, description, config);

        try self.tests.append(test_item);
        try self.logger.info("Created performance test: {s} ({s})", .{ name, test_id });

        return test_item;
    }

    /// Start a performance test
    pub fn startTest(self: *Self, test_item: *PerformanceTest) !void {
        if (self.active_tests.items.len >= self.max_concurrent_tests) {
            return error.MaxConcurrentTestsReached;
        }

        try test_item.start();
        try self.active_tests.append(test_item);

        try self.logger.info("Started performance test: {s}", .{test_item.name});
    }

    /// Stop a performance test
    pub fn stopTest(self: *Self, test_item: *PerformanceTest) !void {
        try test_item.stop();

        // Remove from active tests
        for (self.active_tests.items, 0..) |active_test, i| {
            if (active_test.id == test_item.id) {
                _ = self.active_tests.orderedRemove(i);
                break;
            }
        }

        try self.logger.info("Stopped performance test: {s}", .{test_item.name});
    }

    /// Get all tests
    pub fn getAllTests(self: *Self) []const *PerformanceTest {
        return self.tests.items;
    }

    /// Get active tests
    pub fn getActiveTests(self: *Self) []const *PerformanceTest {
        return self.active_tests.items;
    }

    /// Get test by ID
    pub fn getTestById(self: *Self, test_id: []const u8) ?*PerformanceTest {
        for (self.tests.items) |test_item| {
            if (std.mem.eql(u8, test_item.id, test_id)) {
                return test_item;
            }
        }
        return null;
    }

    /// Get test results
    pub fn getTestResults(self: *Self) ![]const TestResult {
        var results = std.ArrayList(TestResult).init(self.allocator);
        defer results.deinit();

        for (self.tests.items) |test_item| {
            try results.append(test_item.result);
        }

        return results.toOwnedSlice();
    }

    /// Generate unique test ID
    fn generateTestId(self: *Self) ![]const u8 {
        const timestamp = time.timestamp();
        const random = @as(u32, @intCast(@mod(timestamp, 1000000)));
        return try std.fmt.allocPrint(self.allocator, "test_{d}_{d}", .{ timestamp, random });
    }

    /// Monitor active tests and handle timeouts
    pub fn monitorTests(self: *Self) !void {
        const now = time.timestamp();

        var i: usize = 0;
        while (i < self.active_tests.items.len) {
            const active_test = self.active_tests.items[i];

            if (active_test.start_time) |start_time| {
                if (now - start_time > @as(i64, @intCast(self.test_timeout))) {
                    try self.logger.warn("Test timeout reached for: {s}", .{active_test.name});
                    try active_test.fail("Test timeout reached");
                    try self.stopTest(active_test);
                    continue; // Don't increment i since we removed an item
                }
            }

            i += 1;
        }
    }

    /// Generate testing summary report
    pub fn generateSummaryReport(self: *Self) ![]const u8 {
        var report = std.ArrayList(u8).init(self.allocator);
        defer report.deinit();

        const total_tests = self.tests.items.len;
        const active_tests = self.active_tests.items.len;
        const completed_tests = total_tests - active_tests;

        try report.writer().print(
            \\Performance Testing Summary Report
            \\==================================
            \\Generated: {s}
            \\
            \\Test Statistics:
            \\  Total Tests: {d}
            \\  Active Tests: {d}
            \\  Completed Tests: {d}
            \\  Max Concurrent Tests: {d}
            \\
        , .{
            std.fmt.timestampToISO8601(time.timestamp()),
            total_tests,
            active_tests,
            completed_tests,
            self.max_concurrent_tests,
        });

        // Test type breakdown
        var test_types = std.AutoHashMap(TestType, u32).init(self.allocator);
        defer test_types.deinit();

        for (self.tests.items) |test_item| {
            const count = test_types.get(test_item.config.test_type) orelse 0;
            try test_types.put(test_item.config.test_type, count + 1);
        }

        try report.writer().print(
            \\
            \\Test Type Breakdown:
            \\
        );

        var iterator = test_types.iterator();
        while (iterator.next()) |entry| {
            try report.writer().print("  {s}: {d}\n", .{ @tagName(entry.key), entry.value });
        }

        // Recent test results
        if (completed_tests > 0) {
            try report.writer().print(
                \\
                \\Recent Test Results:
                \\
            );

            const recent_tests = if (completed_tests > 5)
                self.tests.items[completed_tests - 5 ..]
            else
                self.tests.items;

            for (recent_tests) |test_item| {
                if (test_item.result.status == .completed) {
                    try report.writer().print("  • {s}: {d} req/s, {d}ms avg, {d:.1}% success\n", .{
                        test_item.name,
                        @as(u32, @intFromFloat(test_item.result.requests_per_second)),
                        test_item.result.average_response_time,
                        100.0 - test_item.result.error_rate,
                    });
                }
            }
        }

        return report.toOwnedSlice();
    }
};
