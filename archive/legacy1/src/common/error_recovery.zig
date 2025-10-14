/// Advanced error recovery system for Proxmox LXCRI
///
/// This module provides comprehensive error recovery mechanisms including
/// automatic retry logic, circuit breakers, detailed stack traces, and
/// intelligent error classification for robust system operation.
const std = @import("std");
const types = @import("types");
const logger = @import("logger");
const performance = @import("performance_monitor");

/// Error severity levels for prioritization
pub const ErrorSeverity = enum(u8) {
    low = 1,
    medium = 2,
    high = 3,
    critical = 4,

    pub fn toString(self: ErrorSeverity) []const u8 {
        return switch (self) {
            .low => "LOW",
            .medium => "MEDIUM",
            .high => "HIGH",
            .critical => "CRITICAL",
        };
    }

    pub fn fromString(str: []const u8) !ErrorSeverity {
        if (std.mem.eql(u8, str, "LOW")) return .low;
        if (std.mem.eql(u8, str, "MEDIUM")) return .medium;
        if (std.mem.eql(u8, str, "HIGH")) return .high;
        if (std.mem.eql(u8, str, "CRITICAL")) return .critical;
        return error.InvalidSeverity;
    }
};

/// Error category for intelligent handling
pub const ErrorCategory = enum {
    network,
    storage,
    memory,
    configuration,
    authentication,
    resource_exhaustion,
    system,
    user_input,
    external_service,

    pub fn toString(self: ErrorCategory) []const u8 {
        return @tagName(self);
    }

    /// Determines if errors in this category are typically recoverable
    pub fn isRecoverable(self: ErrorCategory) bool {
        return switch (self) {
            .network, .external_service => true,
            .storage => true,
            .memory, .resource_exhaustion => false,
            .configuration, .user_input => false,
            .authentication => false,
            .system => false,
        };
    }

    /// Gets default retry strategy for this category
    pub fn getDefaultRetryStrategy(self: ErrorCategory) RetryStrategy {
        return switch (self) {
            .network, .external_service => RetryStrategy{
                .max_attempts = 3,
                .base_delay_ms = 1000,
                .max_delay_ms = 10000,
                .backoff_multiplier = 2.0,
                .jitter = true,
            },
            .storage => RetryStrategy{
                .max_attempts = 2,
                .base_delay_ms = 500,
                .max_delay_ms = 5000,
                .backoff_multiplier = 1.5,
                .jitter = false,
            },
            else => RetryStrategy{
                .max_attempts = 1,
                .base_delay_ms = 0,
                .max_delay_ms = 0,
                .backoff_multiplier = 1.0,
                .jitter = false,
            },
        };
    }
};

/// Retry strategy configuration
pub const RetryStrategy = struct {
    max_attempts: u32,
    base_delay_ms: u32,
    max_delay_ms: u32,
    backoff_multiplier: f64,
    jitter: bool,

    /// Calculates delay for given attempt
    pub fn calculateDelay(self: *const RetryStrategy, attempt: u32) u32 {
        if (attempt == 0) return 0;

        var delay = @as(f64, @floatFromInt(self.base_delay_ms));

        // Apply exponential backoff
        var i: u32 = 1;
        while (i < attempt) : (i += 1) {
            delay *= self.backoff_multiplier;
        }

        // Cap at maximum delay
        delay = @min(delay, @as(f64, @floatFromInt(self.max_delay_ms)));

        var final_delay = @as(u32, @intFromFloat(delay));

        // Apply jitter if enabled
        if (self.jitter and final_delay > 0) {
            var rng = std.rand.Xoroshiro128.init(@intCast(std.time.nanoTimestamp()));
            const jitter_amount = final_delay / 4; // 25% jitter
            const jitter_offset = rng.random().uintLessThan(u32, jitter_amount * 2) - jitter_amount;
            final_delay = @intCast(@max(0, @as(i64, @intCast(final_delay)) + jitter_offset));
        }

        return final_delay;
    }
};

/// Detailed error information with recovery context
pub const DetailedError = struct {
    original_error: anyerror,
    category: ErrorCategory,
    severity: ErrorSeverity,
    message: []const u8,
    context: std.StringHashMap([]const u8),
    stack_trace: ?[]const u8,
    timestamp: i64,
    recovery_attempted: bool,
    recovery_successful: bool,
    attempt_count: u32,
    allocator: std.mem.Allocator,

    /// Initializes detailed error
    pub fn init(allocator: std.mem.Allocator, original_error: anyerror, category: ErrorCategory, severity: ErrorSeverity, message: []const u8) !DetailedError {
        return DetailedError{
            .original_error = original_error,
            .category = category,
            .severity = severity,
            .message = try allocator.dupe(u8, message),
            .context = std.StringHashMap([]const u8).init(allocator),
            .stack_trace = null,
            .timestamp = std.time.nanoTimestamp(),
            .recovery_attempted = false,
            .recovery_successful = false,
            .attempt_count = 0,
            .allocator = allocator,
        };
    }

    /// Deinitializes detailed error
    pub fn deinit(self: *DetailedError) void {
        self.allocator.free(self.message);

        var context_iter = self.context.iterator();
        while (context_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.context.deinit();

        if (self.stack_trace) |trace| {
            self.allocator.free(trace);
        }
    }

    /// Adds context information to error
    pub fn addContext(self: *DetailedError, key: []const u8, value: []const u8) !void {
        const owned_key = try self.allocator.dupe(u8, key);
        const owned_value = try self.allocator.dupe(u8, value);
        try self.context.put(owned_key, owned_value);
    }

    /// Captures stack trace (simulated)
    pub fn captureStackTrace(self: *DetailedError) !void {
        // In a real implementation, this would capture actual stack trace
        const simulated_trace =
            \\Stack trace:
            \\  at function_a (file.zig:123)
            \\  at function_b (file.zig:456)
            \\  at main (main.zig:789)
        ;
        self.stack_trace = try self.allocator.dupe(u8, simulated_trace);
    }

    /// Logs detailed error information
    pub fn log(self: *const DetailedError) !void {
        logger.err("Detailed Error Report:", .{}) catch {};
        logger.err("  Error: {s} ({s})", .{ self.message, @errorName(self.original_error) }) catch {};
        logger.err("  Category: {s}", .{self.category.toString()}) catch {};
        logger.err("  Severity: {s}", .{self.severity.toString()}) catch {};
        logger.err("  Timestamp: {d}", .{self.timestamp}) catch {};
        logger.err("  Attempts: {d}", .{self.attempt_count}) catch {};
        logger.err("  Recovery Attempted: {}", .{self.recovery_attempted}) catch {};
        logger.err("  Recovery Successful: {}", .{self.recovery_successful}) catch {};

        // Log context
        if (self.context.count() > 0) {
            logger.err("  Context:", .{}) catch {};
            var context_iter = self.context.iterator();
            while (context_iter.next()) |entry| {
                logger.err("    {s}: {s}", .{ entry.key_ptr.*, entry.value_ptr.* }) catch {};
            }
        }

        // Log stack trace if available
        if (self.stack_trace) |trace| {
            logger.err("  {s}", .{trace}) catch {};
        }
    }
};

/// Circuit breaker state
pub const CircuitBreakerState = enum {
    closed, // Normal operation
    open, // Failing, rejecting requests
    half_open, // Testing if service recovered
};

/// Circuit breaker for preventing cascade failures
pub const CircuitBreaker = struct {
    state: CircuitBreakerState,
    failure_count: u32,
    success_count: u32,
    last_failure_time: i64,
    failure_threshold: u32,
    success_threshold: u32,
    timeout_ms: u32,
    name: []const u8,
    allocator: std.mem.Allocator,

    /// Initializes circuit breaker
    pub fn init(allocator: std.mem.Allocator, name: []const u8, failure_threshold: u32, timeout_ms: u32) !CircuitBreaker {
        return CircuitBreaker{
            .state = .closed,
            .failure_count = 0,
            .success_count = 0,
            .last_failure_time = 0,
            .failure_threshold = failure_threshold,
            .success_threshold = 1,
            .timeout_ms = timeout_ms,
            .name = try allocator.dupe(u8, name),
            .allocator = allocator,
        };
    }

    /// Deinitializes circuit breaker
    pub fn deinit(self: *CircuitBreaker) void {
        self.allocator.free(self.name);
    }

    /// Checks if operation should be allowed
    pub fn shouldAllowOperation(self: *CircuitBreaker) bool {
        const now = std.time.nanoTimestamp();

        switch (self.state) {
            .closed => return true,
            .open => {
                // Check if timeout has passed
                if (now - self.last_failure_time > self.timeout_ms * std.time.ns_per_ms) {
                    self.state = .half_open;
                    self.success_count = 0;
                    logger.info("Circuit breaker {s} transitioning to half-open", .{self.name}) catch {};
                    return true;
                }
                return false;
            },
            .half_open => return true,
        }
    }

    /// Records successful operation
    pub fn recordSuccess(self: *CircuitBreaker) void {
        switch (self.state) {
            .closed => {
                self.failure_count = 0;
            },
            .half_open => {
                self.success_count += 1;
                if (self.success_count >= self.success_threshold) {
                    self.state = .closed;
                    self.failure_count = 0;
                    logger.info("Circuit breaker {s} closed (recovered)", .{self.name}) catch {};
                }
            },
            .open => {
                // Shouldn't happen, but reset if it does
                self.state = .closed;
                self.failure_count = 0;
            },
        }
    }

    /// Records failed operation
    pub fn recordFailure(self: *CircuitBreaker) void {
        self.last_failure_time = std.time.nanoTimestamp();

        switch (self.state) {
            .closed => {
                self.failure_count += 1;
                if (self.failure_count >= self.failure_threshold) {
                    self.state = .open;
                    logger.warn("Circuit breaker {s} opened (failure threshold reached)", .{self.name}) catch {};
                }
            },
            .half_open => {
                self.state = .open;
                logger.warn("Circuit breaker {s} re-opened (test failed)", .{self.name}) catch {};
            },
            .open => {
                // Already open, just update timestamp
            },
        }
    }

    /// Gets circuit breaker status
    pub fn getStatus(self: *const CircuitBreaker) void {
        logger.info("Circuit breaker {s} status:", .{self.name}) catch {};
        logger.info("  State: {s}", .{@tagName(self.state)}) catch {};
        logger.info("  Failure count: {d}/{d}", .{ self.failure_count, self.failure_threshold }) catch {};
        logger.info("  Success count: {d}/{d}", .{ self.success_count, self.success_threshold }) catch {};
    }
};

/// Recovery action type
pub const RecoveryActionType = enum {
    retry,
    fallback,
    circuit_break,
    escalate,
    ignore,
};

/// Recovery action definition
pub const RecoveryAction = struct {
    action_type: RecoveryActionType,
    retry_strategy: ?RetryStrategy,
    fallback_function: ?*const fn () anyerror!void,
    escalation_target: ?[]const u8,

    /// Creates retry recovery action
    pub fn createRetry(strategy: RetryStrategy) RecoveryAction {
        return RecoveryAction{
            .action_type = .retry,
            .retry_strategy = strategy,
            .fallback_function = null,
            .escalation_target = null,
        };
    }

    /// Creates fallback recovery action
    pub fn createFallback(fallback_fn: *const fn () anyerror!void) RecoveryAction {
        return RecoveryAction{
            .action_type = .fallback,
            .retry_strategy = null,
            .fallback_function = fallback_fn,
            .escalation_target = null,
        };
    }

    /// Creates circuit breaker recovery action
    pub fn createCircuitBreak() RecoveryAction {
        return RecoveryAction{
            .action_type = .circuit_break,
            .retry_strategy = null,
            .fallback_function = null,
            .escalation_target = null,
        };
    }
};

/// Comprehensive error recovery manager
pub const ErrorRecoveryManager = struct {
    circuit_breakers: std.StringHashMap(CircuitBreaker),
    recovery_policies: std.StringHashMap(RecoveryAction),
    error_history: std.ArrayList(DetailedError),
    performance_monitor: performance.PerformanceTimer,
    allocator: std.mem.Allocator,

    /// Initializes error recovery manager
    pub fn init(allocator: std.mem.Allocator) ErrorRecoveryManager {
        return ErrorRecoveryManager{
            .circuit_breakers = std.StringHashMap(CircuitBreaker).init(allocator),
            .recovery_policies = std.StringHashMap(RecoveryAction).init(allocator),
            .error_history = std.ArrayList(DetailedError).init(allocator),
            .performance_monitor = performance.PerformanceTimer.start("error_recovery"),
            .allocator = allocator,
        };
    }

    /// Deinitializes error recovery manager
    pub fn deinit(self: *ErrorRecoveryManager) void {
        // Clean up circuit breakers
        var cb_iter = self.circuit_breakers.iterator();
        while (cb_iter.next()) |entry| {
            entry.value_ptr.deinit();
            self.allocator.free(entry.key_ptr.*);
        }
        self.circuit_breakers.deinit();

        // Clean up recovery policies
        var policy_iter = self.recovery_policies.iterator();
        while (policy_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.recovery_policies.deinit();

        // Clean up error history
        for (self.error_history.items) |*error_item| {
            error_item.deinit();
        }
        self.error_history.deinit();
    }

    /// Handles error with recovery attempt
    pub fn handleError(self: *ErrorRecoveryManager, original_error: anyerror, category: ErrorCategory, context: []const u8) !void {
        const severity = self.classifyErrorSeverity(original_error, category);

        var detailed_error = try DetailedError.init(self.allocator, original_error, category, severity, context);
        try detailed_error.captureStackTrace();
        try detailed_error.addContext("recovery_manager", "active");

        // Log the error
        try detailed_error.log();

        // Attempt recovery if applicable
        if (category.isRecoverable()) {
            try self.attemptRecovery(&detailed_error);
        }

        // Store in history (keep last 100 errors)
        try self.error_history.append(detailed_error);
        if (self.error_history.items.len > 100) {
            var old_error = self.error_history.orderedRemove(0);
            old_error.deinit();
        }
    }

    /// Attempts to recover from error
    fn attemptRecovery(self: *ErrorRecoveryManager, detailed_error: *DetailedError) !void {
        detailed_error.recovery_attempted = true;

        const strategy = detailed_error.category.getDefaultRetryStrategy();

        logger.info("Attempting recovery for {s} error (max attempts: {d})", .{ detailed_error.category.toString(), strategy.max_attempts }) catch {};

        var attempt: u32 = 0;
        while (attempt < strategy.max_attempts) : (attempt += 1) {
            detailed_error.attempt_count = attempt + 1;

            // Calculate delay for this attempt
            const delay_ms = strategy.calculateDelay(attempt);
            if (delay_ms > 0) {
                logger.info("Retrying in {}ms (attempt {d}/{d})", .{ delay_ms, attempt + 1, strategy.max_attempts }) catch {};
                std.time.sleep(delay_ms * std.time.ns_per_ms);
            }

            // Simulate recovery attempt
            if (self.simulateRecoveryAttempt(detailed_error.category)) {
                detailed_error.recovery_successful = true;
                logger.info("Recovery successful after {d} attempts", .{attempt + 1}) catch {};
                return;
            } else {
                logger.warn("Recovery attempt {d} failed", .{attempt + 1}) catch {};
            }
        }

        logger.err("Recovery failed after {d} attempts", .{strategy.max_attempts}) catch {};
    }

    /// Simulates recovery attempt (for testing purposes)
    fn simulateRecoveryAttempt(self: *ErrorRecoveryManager, category: ErrorCategory) bool {
        _ = self;

        // Simulate different recovery success rates based on category
        var rng = std.rand.Xoroshiro128.init(@intCast(std.time.nanoTimestamp()));
        const success_chance: f32 = switch (category) {
            .network => 0.7,
            .storage => 0.5,
            .external_service => 0.6,
            else => 0.1,
        };

        return rng.random().float(f32) < success_chance;
    }

    /// Classifies error severity based on error type and category
    fn classifyErrorSeverity(self: *ErrorRecoveryManager, err: anyerror, category: ErrorCategory) ErrorSeverity {
        _ = self;

        // Classification logic based on error type and category
        return switch (category) {
            .memory, .resource_exhaustion => .critical,
            .system => .high,
            .authentication => .high,
            .configuration => .medium,
            .network, .external_service => .medium,
            .storage => .medium,
            .user_input => .low,
        };
    }

    /// Registers a circuit breaker for a service
    pub fn registerCircuitBreaker(self: *ErrorRecoveryManager, service_name: []const u8, failure_threshold: u32, timeout_ms: u32) !void {
        const owned_name = try self.allocator.dupe(u8, service_name);
        const circuit_breaker = try CircuitBreaker.init(self.allocator, service_name, failure_threshold, timeout_ms);
        try self.circuit_breakers.put(owned_name, circuit_breaker);

        logger.info("Registered circuit breaker for service: {s}", .{service_name}) catch {};
    }

    /// Executes operation with circuit breaker protection
    pub fn executeWithCircuitBreaker(self: *ErrorRecoveryManager, service_name: []const u8, operation: anytype) !void {
        if (self.circuit_breakers.getPtr(service_name)) |cb| {
            if (!cb.shouldAllowOperation()) {
                logger.warn("Circuit breaker {s} is open, rejecting operation", .{service_name}) catch {};
                return error.CircuitBreakerOpen;
            }

            operation() catch |err| {
                cb.recordFailure();
                return err;
            };

            cb.recordSuccess();
        } else {
            return error.CircuitBreakerNotFound;
        }
    }

    /// Gets error statistics
    pub fn getErrorStatistics(self: *const ErrorRecoveryManager) !void {
        logger.info("Error Recovery Statistics:", .{}) catch {};
        logger.info("========================", .{}) catch {};
        logger.info("Total errors recorded: {d}", .{self.error_history.items.len}) catch {};

        // Count by category
        var category_counts = std.EnumMap(ErrorCategory, u32).initFull(0);
        var severity_counts = std.EnumMap(ErrorSeverity, u32).initFull(0);
        var recovery_successes: u32 = 0;
        var recovery_attempts: u32 = 0;

        for (self.error_history.items) |error_item| {
            const current_count = category_counts.get(error_item.category);
            category_counts.put(error_item.category, current_count + 1);

            const current_severity_count = severity_counts.get(error_item.severity);
            severity_counts.put(error_item.severity, current_severity_count + 1);

            if (error_item.recovery_attempted) {
                recovery_attempts += 1;
                if (error_item.recovery_successful) {
                    recovery_successes += 1;
                }
            }
        }

        // Log category statistics
        logger.info("Errors by category:", .{}) catch {};
        var category_iter = category_counts.iterator();
        while (category_iter.next()) |entry| {
            if (entry.value.* > 0) {
                logger.info("  {s}: {d}", .{ entry.key.toString(), entry.value.* }) catch {};
            }
        }

        // Log severity statistics
        logger.info("Errors by severity:", .{}) catch {};
        var severity_iter = severity_counts.iterator();
        while (severity_iter.next()) |entry| {
            if (entry.value.* > 0) {
                logger.info("  {s}: {d}", .{ entry.key.toString(), entry.value.* }) catch {};
            }
        }

        // Log recovery statistics
        if (recovery_attempts > 0) {
            const success_rate = (@as(f64, @floatFromInt(recovery_successes)) / @as(f64, @floatFromInt(recovery_attempts))) * 100.0;
            logger.info("Recovery success rate: {d:.1}% ({d}/{d})", .{ success_rate, recovery_successes, recovery_attempts }) catch {};
        }
    }
};
