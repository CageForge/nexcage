const std = @import("std");
const Allocator = std.mem.Allocator;
const Logger = @import("logger").Logger;
const PerformanceMonitor = @import("monitor.zig").PerformanceMonitor;
const PerformanceMetrics = @import("monitor.zig").PerformanceMetrics;
const time = std.time;
const mem = std.mem;

/// Dashboard configuration
pub const DashboardConfig = struct {
    refresh_interval: u64, // milliseconds
    max_display_items: usize,
    show_history: bool,
    show_trends: bool,
    show_alerts: bool,
    alert_thresholds: AlertThresholds,

    pub const AlertThresholds = struct {
        cpu_high: f64,      // CPU usage threshold for high alert
        memory_high: f64,   // Memory usage threshold for high alert
        error_rate_high: u32, // Error count threshold for high alert
        response_time_slow: u64, // Response time threshold for slow alert
    };

    pub fn default() DashboardConfig {
        return .{
            .refresh_interval = 2000, // 2 seconds
            .max_display_items = 20,
            .show_history = true,
            .show_trends = true,
            .show_alerts = true,
            .alert_thresholds = .{
                .cpu_high = 80.0,        // 80% CPU
                .memory_high = 85.0,     // 85% Memory
                .error_rate_high = 5,    // 5 errors
                .response_time_slow = 500, // 500ms
            },
        };
    }
};

/// Performance alert
pub const PerformanceAlert = struct {
    timestamp: i64,
    severity: AlertSeverity,
    message: []const u8,
    metrics: PerformanceMetrics,

    pub const AlertSeverity = enum {
        info,
        warning,
        critical,
    };

    pub fn init(severity: AlertSeverity, message: []const u8, metrics: PerformanceMetrics) PerformanceAlert {
        return .{
            .timestamp = time.timestamp(),
            .severity = severity,
            .message = message,
            .metrics = metrics,
        };
    }

    pub fn format(self: PerformanceAlert, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("[{s}] {s}: {s}", .{
            @tagName(self.severity),
            std.fmt.timestampToISO8601(self.timestamp),
            self.message,
        });
    }
};

/// Performance dashboard
pub const PerformanceDashboard = struct {
    allocator: Allocator,
    logger: *Logger,
    monitor: *PerformanceMonitor,
    config: DashboardConfig,
    alerts: std.ArrayList(PerformanceAlert),
    last_refresh: i64,
    is_active: bool,

    const Self = @This();

    pub fn init(allocator: Allocator, logger: *Logger, monitor: *PerformanceMonitor) !*Self {
        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .logger = logger,
            .monitor = monitor,
            .config = DashboardConfig.default(),
            .alerts = std.ArrayList(PerformanceAlert).init(allocator),
            .last_refresh = time.timestamp(),
            .is_active = false,
        };
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.alerts.deinit();
        self.allocator.destroy(self);
    }

    /// Configure dashboard settings
    pub fn configure(self: *Self, config: DashboardConfig) void {
        self.config = config;
        try self.logger.info("Dashboard configured: refresh={d}ms, alerts={s}", .{
            config.refresh_interval,
            if (config.show_alerts) "enabled" else "disabled",
        });
    }

    /// Start dashboard
    pub fn start(self: *Self) !void {
        if (self.is_active) {
            try self.logger.warn("Dashboard is already active", .{});
            return;
        }

        self.is_active = true;
        try self.logger.info("Performance dashboard started", .{});
        
        // Initial refresh
        try self.refresh();
    }

    /// Stop dashboard
    pub fn stop(self: *Self) void {
        if (!self.is_active) {
            try self.logger.warn("Dashboard is not active", .{});
            return;
        }

        self.is_active = false;
        try self.logger.info("Performance dashboard stopped", .{});
    }

    /// Refresh dashboard data
    pub fn refresh(self: *Self) !void {
        if (!self.is_active) return;

        const now = time.timestamp();
        if (now - self.last_refresh < @as(i64, @intCast(self.config.refresh_interval / 1000))) {
            return; // Too soon to refresh
        }

        try self.logger.debug("Refreshing dashboard data", .{});

        // Collect new metrics
        const metrics = try self.monitor.collectMetrics();
        
        // Check for alerts
        if (self.config.show_alerts) {
            try self.checkAlerts(metrics);
        }

        // Update last refresh time
        self.last_refresh = now;
    }

    /// Check metrics for alerts
    fn checkAlerts(self: *Self, metrics: PerformanceMetrics) !void {
        var alert_message: ?[]const u8 = null;
        var severity: PerformanceAlert.AlertSeverity = .info;

        // Check CPU usage
        if (metrics.cpu_usage > self.config.alert_thresholds.cpu_high) {
            alert_message = try mem.dupe(self.allocator, u8, 
                "High CPU usage detected");
            severity = if (metrics.cpu_usage > 95.0) .critical else .warning;
        }

        // Check memory usage
        const memory_percent = @as(f64, @floatFromInt(metrics.memory_usage)) / 
                              @as(f64, @floatFromInt(metrics.memory_limit)) * 100.0;
        if (memory_percent > self.config.alert_thresholds.memory_high) {
            alert_message = try mem.dupe(self.allocator, u8, 
                "High memory usage detected");
            severity = if (memory_percent > 95.0) .critical else .warning;
        }

        // Check error rate
        if (metrics.error_count > self.config.alert_thresholds.error_rate_high) {
            alert_message = try mem.dupe(self.allocator, u8, 
                "High error rate detected");
            severity = .warning;
        }

        // Check response time
        if (metrics.response_time > self.config.alert_thresholds.response_time_slow) {
            alert_message = try mem.dupe(self.allocator, u8, 
                "Slow response time detected");
            severity = .warning;
        }

        // Create alert if needed
        if (alert_message) |message| {
            const alert = PerformanceAlert.init(severity, message, metrics);
            try self.alerts.append(alert);
            
            try self.logger.warn("Performance alert: {s}", .{message});
            
            // Limit alert history
            if (self.alerts.items.len > 100) {
                _ = self.alerts.orderedRemove(0);
            }
        }
    }

    /// Get current dashboard view
    pub fn getDashboardView(self: *Self) !DashboardView {
        const latest_metrics = self.monitor.getLatestMetrics();
        if (latest_metrics == null) {
            return DashboardView{
                .current_metrics = PerformanceMetrics.init(),
                .alerts = &[_]PerformanceAlert{},
                .history = &[_]PerformanceMetrics{},
                .trends = null,
            };
        }

        const metrics = latest_metrics.?;
        const now = time.timestamp();
        const one_hour_ago = now - 3600;
        
        // Get recent history
        const history = try self.monitor.getMetricsInRange(one_hour_ago, now);
        
        // Calculate trends
        const trends = if (self.config.show_trends) 
            try self.calculateTrends(history) else null;

        return DashboardView{
            .current_metrics = metrics,
            .alerts = self.alerts.items,
            .history = history,
            .trends = trends,
        };
    }

    /// Calculate performance trends
    fn calculateTrends(_: *Self, _: []const PerformanceMetrics) !PerformanceTrends {
        // TODO: Implement actual trend calculation based on historical data
        // For now, return default trends
        return PerformanceTrends.init();
    }

    /// Generate dashboard report
    pub fn generateDashboardReport(self: *Self) ![]const u8 {
        const view = try self.getDashboardView();
        defer if (view.history.len > 0) self.allocator.free(view.history);
        // Note: trends is already handled by the function

        var report = std.ArrayList(u8).init(self.allocator);
        defer report.deinit();

        try report.writer().print(
            \\Performance Dashboard Report
            \\==========================
            \\Generated: {s}
            \\Status: {s}
            \\
            \\Current Metrics:
            \\  CPU Usage: {d:.2}% {s}
            \\  Memory Usage: {d:.1}% {s}
            \\  Active Containers: {d}/{d} {s}
            \\  Error Count: {d}
            \\  Response Time: {d}ms
            \\
        , .{
            std.fmt.timestampToISO8601(time.timestamp()),
            if (self.is_active) "ACTIVE" else "INACTIVE",
            view.current_metrics.cpu_usage,
            if (view.trends) |t| @tagName(t.cpu_trend) else "",
            @as(f64, @floatFromInt(view.current_metrics.memory_usage)) / 
            @as(f64, @floatFromInt(view.current_metrics.memory_limit)) * 100.0,
            if (view.trends) |t| @tagName(t.memory_trend) else "",
            view.current_metrics.active_containers,
            view.current_metrics.container_count,
            if (view.trends) |t| @tagName(t.container_trend) else "",
            view.current_metrics.error_count,
            view.current_metrics.response_time,
        });

        // Add trends if available
        if (view.trends) |trends| {
            try report.writer().print(
                \\
                \\Trends (Last Hour):
                \\  CPU Change: {d:.2}% {s}
                \\  Memory Change: {d:.1}% {s}
                \\  Container Change: {d:.0} {s}
                \\
            , .{
                trends.cpu_change,
                @tagName(trends.cpu_trend),
                trends.memory_change,
                @tagName(trends.memory_trend),
                trends.container_change,
                @tagName(trends.container_trend),
            });
        }

        // Add recent alerts
        if (view.alerts.len > 0) {
            try report.writer().print(
                \\
                \\Recent Alerts ({d}):
                \\
            , .{view.alerts.len});

            const start_idx = if (view.alerts.len > 5) view.alerts.len - 5 else 0;
            for (view.alerts[start_idx..]) |alert| {
                try report.writer().print("  [{s}] {s}\n", .{
                    @tagName(alert.severity),
                    alert.message,
                });
            }
        }

        return report.toOwnedSlice();
    }

    /// Get alerts
    pub fn getAlerts(self: *Self) []const PerformanceAlert {
        return self.alerts.items;
    }

    /// Clear old alerts
    pub fn clearOldAlerts(self: *Self, older_than_hours: u32) void {
        const cutoff_time = time.timestamp() - @as(i64, @intCast(older_than_hours * 3600));
        
        var i: usize = 0;
        while (i < self.alerts.items.len) {
            if (self.alerts.items[i].timestamp < cutoff_time) {
                _ = self.alerts.orderedRemove(i);
            } else {
                i += 1;
            }
        }
        
        try self.logger.info("Cleared {d} old alerts", .{self.alerts.items.len});
    }
};

/// Dashboard view data
pub const DashboardView = struct {
    current_metrics: PerformanceMetrics,
    alerts: []const PerformanceAlert,
    history: []const PerformanceMetrics,
    trends: ?PerformanceTrends,
};

/// Performance trends
pub const PerformanceTrends = struct {
    cpu_trend: TrendDirection,
    cpu_change: f64,
    memory_trend: TrendDirection,
    memory_change: f64,
    container_trend: TrendDirection,
    container_change: f64,

    pub const TrendDirection = enum {
        increasing,
        decreasing,
        stable,
    };

    pub fn init() PerformanceTrends {
        return .{
            .cpu_trend = .stable,
            .cpu_change = 0.0,
            .memory_trend = .stable,
            .memory_change = 0.0,
            .container_trend = .stable,
            .container_change = 0.0,
        };
    }
};
