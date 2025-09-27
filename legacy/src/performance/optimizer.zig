const std = @import("std");
const Allocator = std.mem.Allocator;
const Logger = @import("logger").Logger;
const PerformanceMetrics = @import("monitor.zig").PerformanceMetrics;
const PerformanceTrends = @import("dashboard.zig").PerformanceTrends;
const time = std.time;

/// Optimization recommendation priority
pub const RecommendationPriority = enum {
    low,
    medium,
    high,
    critical,
};

/// Optimization category
pub const OptimizationCategory = enum {
    cpu,
    memory,
    network,
    disk,
    container,
    system,
    security,
};

/// Optimization recommendation
pub const OptimizationRecommendation = struct {
    id: []const u8,
    title: []const u8,
    description: []const u8,
    category: OptimizationCategory,
    priority: RecommendationPriority,
    impact_score: f64, // 0.0 to 1.0
    effort_score: f64, // 0.0 to 1.0 (1.0 = high effort)
    estimated_improvement: f64, // percentage
    implementation_steps: []const []const u8,
    created_at: i64,
    applied: bool,
    applied_at: ?i64,

    pub fn init(
        id: []const u8,
        title: []const u8,
        description: []const u8,
        category: OptimizationCategory,
        priority: RecommendationPriority,
        impact_score: f64,
        effort_score: f64,
        estimated_improvement: f64,
        implementation_steps: []const []const u8,
    ) OptimizationRecommendation {
        return .{
            .id = id,
            .title = title,
            .description = description,
            .category = category,
            .priority = priority,
            .impact_score = impact_score,
            .effort_score = effort_score,
            .estimated_improvement = estimated_improvement,
            .implementation_steps = implementation_steps,
            .created_at = time.timestamp(),
            .applied = false,
            .applied_at = null,
        };
    }

    pub fn format(self: OptimizationRecommendation, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("Recommendation[{s}]: {s} ({s}, {s}) - Impact: {d:.1}%, Effort: {d:.1}%", .{
            self.id,
            self.title,
            @tagName(self.category),
            @tagName(self.priority),
            self.estimated_improvement,
            self.effort_score * 100.0,
        });
    }

    /// Mark recommendation as applied
    pub fn markApplied(self: *OptimizationRecommendation) void {
        self.applied = true;
        self.applied_at = time.timestamp();
    }

    /// Calculate ROI (Return on Investment) score
    pub fn getROIScore(self: OptimizationRecommendation) f64 {
        if (self.effort_score == 0.0) return 0.0;
        return self.impact_score / self.effort_score;
    }
};

/// Performance optimizer that analyzes metrics and provides recommendations
pub const PerformanceOptimizer = struct {
    allocator: Allocator,
    logger: *Logger,
    recommendations: std.ArrayList(OptimizationRecommendation),
    max_recommendations: usize,
    analysis_enabled: bool,

    const Self = @This();

    pub fn init(allocator: Allocator, logger: *Logger) !*Self {
        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .logger = logger,
            .recommendations = std.ArrayList(OptimizationRecommendation).init(allocator),
            .max_recommendations = 50,
            .analysis_enabled = true,
        };
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.recommendations.deinit();
        self.allocator.destroy(self);
    }

    /// Enable or disable optimization analysis
    pub fn setAnalysisEnabled(self: *Self, enabled: bool) void {
        self.analysis_enabled = enabled;
        try self.logger.info("Performance optimization analysis {s}", .{if (enabled) "enabled" else "disabled"});
    }

    /// Analyze performance metrics and generate recommendations
    pub fn analyzePerformance(self: *Self, metrics: PerformanceMetrics, trends: ?PerformanceTrends) ![]const OptimizationRecommendation {
        if (!self.analysis_enabled) {
            return &[_]OptimizationRecommendation{};
        }

        try self.logger.info("Analyzing performance metrics for optimization opportunities", .{});

        // Clear old recommendations
        self.recommendations.clearRetainingCapacity();

        // Analyze CPU usage
        try self.analyzeCPUUsage(metrics, trends);

        // Analyze memory usage
        try self.analyzeMemoryUsage(metrics, trends);

        // Analyze container performance
        try self.analyzeContainerPerformance(metrics, trends);

        // Analyze error rates
        try self.analyzeErrorRates(metrics, trends);

        // Analyze response times
        try self.analyzeResponseTimes(metrics, trends);

        // Sort recommendations by ROI score
        std.sort.insertion(OptimizationRecommendation, self.recommendations.items, {}, sortByROI);

        try self.logger.info("Generated {d} optimization recommendations", .{self.recommendations.items.len});

        return self.recommendations.items;
    }

    /// Analyze CPU usage patterns
    fn analyzeCPUUsage(self: *Self, metrics: PerformanceMetrics, trends: ?PerformanceTrends) !void {
        // High CPU usage recommendation
        if (metrics.cpu_usage > 80.0) {
            const priority = if (metrics.cpu_usage > 95.0) .critical else .high;
            const improvement = if (metrics.cpu_usage > 95.0) 25.0 else 15.0;

            const rec = OptimizationRecommendation.init(
                "cpu-high-usage",
                "Optimize High CPU Usage",
                "CPU usage is consistently high, indicating potential performance bottlenecks",
                .cpu,
                priority,
                0.8,
                0.6,
                improvement,
                &[_][]const u8{
                    "Review container resource limits",
                    "Implement CPU quotas and cgroups",
                    "Optimize application code",
                    "Consider horizontal scaling",
                },
            );
            try self.recommendations.append(rec);
        }

        // CPU trend analysis
        if (trends) |t| {
            if (t.cpu_trend == .increasing and t.cpu_change > 10.0) {
                const rec = OptimizationRecommendation.init(
                    "cpu-increasing-trend",
                    "Address Increasing CPU Trend",
                    "CPU usage is trending upward, indicating growing resource pressure",
                    .cpu,
                    .medium,
                    0.6,
                    0.4,
                    10.0,
                    &[_][]const u8{
                        "Monitor CPU usage patterns",
                        "Identify resource-intensive containers",
                        "Implement resource scheduling",
                        "Plan capacity expansion",
                    },
                );
                try self.recommendations.append(rec);
            }
        }
    }

    /// Analyze memory usage patterns
    fn analyzeMemoryUsage(self: *Self, metrics: PerformanceMetrics, trends: ?PerformanceTrends) !void {
        const memory_percent = @as(f64, @floatFromInt(metrics.memory_usage)) /
            @as(f64, @floatFromInt(metrics.memory_limit)) * 100.0;

        // High memory usage recommendation
        if (memory_percent > 85.0) {
            const priority = if (memory_percent > 95.0) .critical else .high;
            const improvement = if (memory_percent > 95.0) 30.0 else 20.0;

            const rec = OptimizationRecommendation.init(
                "memory-high-usage",
                "Optimize High Memory Usage",
                "Memory usage is approaching limits, risking system stability",
                .memory,
                priority,
                0.9,
                0.7,
                improvement,
                &[_][]const u8{
                    "Review memory limits for containers",
                    "Implement memory quotas",
                    "Optimize application memory usage",
                    "Consider memory expansion",
                },
            );
            try self.recommendations.append(rec);
        }

        // Memory trend analysis
        if (trends) |t| {
            if (t.memory_trend == .increasing and t.memory_change > 15.0) {
                const rec = OptimizationRecommendation.init(
                    "memory-increasing-trend",
                    "Address Memory Growth Trend",
                    "Memory usage is growing rapidly, indicating potential memory leaks",
                    .memory,
                    .high,
                    0.8,
                    0.5,
                    20.0,
                    &[_][]const u8{
                        "Investigate memory leaks",
                        "Implement memory monitoring",
                        "Set memory growth alerts",
                        "Plan memory expansion",
                    },
                );
                try self.recommendations.append(rec);
            }
        }
    }

    /// Analyze container performance
    fn analyzeContainerPerformance(self: *Self, metrics: PerformanceMetrics, trends: ?PerformanceTrends) !void {
        // Container efficiency analysis
        if (metrics.container_count > 0) {
            const efficiency = @as(f64, @floatFromInt(metrics.active_containers)) /
                @as(f64, @floatFromInt(metrics.container_count)) * 100.0;

            if (efficiency < 50.0) {
                const rec = OptimizationRecommendation.init(
                    "container-efficiency",
                    "Improve Container Efficiency",
                    "Low container utilization indicates resource waste",
                    .container,
                    .medium,
                    0.5,
                    0.3,
                    15.0,
                    &[_][]const u8{
                        "Review container lifecycle management",
                        "Implement auto-scaling policies",
                        "Optimize resource allocation",
                        "Remove unused containers",
                    },
                );
                try self.recommendations.append(rec);
            }
        }

        // Container trend analysis
        if (trends) |t| {
            if (t.container_trend == .increasing and t.container_change > 5) {
                const rec = OptimizationRecommendation.init(
                    "container-scaling",
                    "Optimize Container Scaling",
                    "Rapid container growth indicates need for better scaling policies",
                    .container,
                    .medium,
                    0.6,
                    0.4,
                    12.0,
                    &[_][]const u8{
                        "Implement auto-scaling rules",
                        "Set scaling thresholds",
                        "Monitor scaling patterns",
                        "Optimize scaling algorithms",
                    },
                );
                try self.recommendations.append(rec);
            }
        }
    }

    /// Analyze error rates
    fn analyzeErrorRates(self: *Self, metrics: PerformanceMetrics, _: ?PerformanceTrends) !void {
        if (metrics.error_count > 5) {
            const priority = if (metrics.error_count > 10) .critical else .high;
            const improvement = if (metrics.error_count > 10) 40.0 else 25.0;

            const rec = OptimizationRecommendation.init(
                "error-rate-reduction",
                "Reduce Error Rate",
                "High error count indicates system instability or configuration issues",
                .system,
                priority,
                0.9,
                0.8,
                improvement,
                &[_][]const u8{
                    "Investigate error sources",
                    "Review system logs",
                    "Fix configuration issues",
                    "Implement error handling",
                },
            );
            try self.recommendations.append(rec);
        }
    }

    /// Analyze response times
    fn analyzeResponseTimes(self: *Self, metrics: PerformanceMetrics, _: ?PerformanceTrends) !void {
        if (metrics.response_time > 500) {
            const priority = if (metrics.response_time > 1000) .high else .medium;
            const improvement = if (metrics.response_time > 1000) 35.0 else 20.0;

            const rec = OptimizationRecommendation.init(
                "response-time-optimization",
                "Optimize Response Times",
                "Slow response times indicate performance bottlenecks",
                .system,
                priority,
                0.7,
                0.6,
                improvement,
                &[_][]const u8{
                    "Profile application performance",
                    "Optimize database queries",
                    "Implement caching",
                    "Review network configuration",
                },
            );
            try self.recommendations.append(rec);
        }
    }

    /// Get recommendations by category
    pub fn getRecommendationsByCategory(self: *Self, category: OptimizationCategory) []const OptimizationRecommendation {
        var result = std.ArrayList(OptimizationRecommendation).init(self.allocator);
        defer result.deinit();

        for (self.recommendations.items) |rec| {
            if (rec.category == category) {
                result.append(rec) catch continue;
            }
        }

        return result.toOwnedSlice();
    }

    /// Get recommendations by priority
    pub fn getRecommendationsByPriority(self: *Self, priority: RecommendationPriority) []const OptimizationRecommendation {
        var result = std.ArrayList(OptimizationRecommendation).init(self.allocator);
        defer result.deinit();

        for (self.recommendations.items) |rec| {
            if (rec.priority == priority) {
                result.append(rec) catch continue;
            }
        }

        return result.toOwnedSlice();
    }

    /// Get top recommendations by ROI
    pub fn getTopRecommendations(self: *Self, count: usize) []const OptimizationRecommendation {
        const limit = @min(count, self.recommendations.items.len);
        return self.recommendations.items[0..limit];
    }

    /// Apply a recommendation
    pub fn applyRecommendation(self: *Self, recommendation_id: []const u8) !bool {
        for (self.recommendations.items) |*rec| {
            if (std.mem.eql(u8, rec.id, recommendation_id)) {
                rec.markApplied();
                try self.logger.info("Applied optimization recommendation: {s}", .{rec.title});
                return true;
            }
        }
        return false;
    }

    /// Generate optimization report
    pub fn generateOptimizationReport(self: *Self) ![]const u8 {
        var report = std.ArrayList(u8).init(self.allocator);
        defer report.deinit();

        try report.writer().print(
            \\Performance Optimization Report
            \\=============================
            \\Generated: {s}
            \\Total Recommendations: {d}
            \\
        , .{
            std.fmt.timestampToISO8601(time.timestamp()),
            self.recommendations.items.len,
        });

        // Group by priority
        const critical = self.getRecommendationsByPriority(.critical);
        const high = self.getRecommendationsByPriority(.high);
        const medium = self.getRecommendationsByPriority(.medium);
        const low = self.getRecommendationsByPriority(.low);

        defer if (critical.len > 0) self.allocator.free(critical);
        defer if (high.len > 0) self.allocator.free(high);
        defer if (medium.len > 0) self.allocator.free(medium);
        defer if (low.len > 0) self.allocator.free(low);

        if (critical.len > 0) {
            try report.writer().print(
                \\
                \\🔴 Critical Priority ({d}):
                \\
            , .{critical.len});
            for (critical) |rec| {
                try report.writer().print("  • {s} (Impact: {d:.1}%)\n", .{ rec.title, rec.estimated_improvement });
            }
        }

        if (high.len > 0) {
            try report.writer().print(
                \\
                \\🟠 High Priority ({d}):
                \\
            , .{high.len});
            for (high) |rec| {
                try report.writer().print("  • {s} (Impact: {d:.1}%)\n", .{ rec.title, rec.estimated_improvement });
            }
        }

        if (medium.len > 0) {
            try report.writer().print(
                \\
                \\🟡 Medium Priority ({d}):
                \\
            , .{medium.len});
            for (medium) |rec| {
                try report.writer().print("  • {s} (Impact: {d:.1}%)\n", .{ rec.title, rec.estimated_improvement });
            }
        }

        if (low.len > 0) {
            try report.writer().print(
                \\
                \\🟢 Low Priority ({d}):
                \\
            , .{low.len});
            for (low) |rec| {
                try report.writer().print("  • {s} (Impact: {d:.1}%)\n", .{ rec.title, rec.estimated_improvement });
            }
        }

        // Summary
        const total_improvement = self.calculateTotalPotentialImprovement();
        try report.writer().print(
            \\
            \\Summary:
            \\  Total Potential Improvement: {d:.1}%
            \\  Critical Issues: {d}
            \\  High Priority: {d}
            \\  Medium Priority: {d}
            \\  Low Priority: {d}
            \\
        , .{
            total_improvement,
            critical.len,
            high.len,
            medium.len,
            low.len,
        });

        return report.toOwnedSlice();
    }

    /// Calculate total potential improvement
    fn calculateTotalPotentialImprovement(self: *Self) f64 {
        var total: f64 = 0.0;
        for (self.recommendations.items) |rec| {
            total += rec.estimated_improvement;
        }
        return total;
    }
};

/// Sort recommendations by ROI score (descending)
fn sortByROI(context: void, a: OptimizationRecommendation, b: OptimizationRecommendation) bool {
    _ = context;
    return a.getROIScore() > b.getROIScore();
}
