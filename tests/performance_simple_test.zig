const std = @import("std");
const testing = std.testing;
const performance = @import("performance");

test "Performance module import test" {
    try testing.expect(@hasDecl(performance, "monitor"));
    try testing.expect(@hasDecl(performance, "dashboard"));
    try testing.expect(@hasDecl(performance, "optimizer"));
    try testing.expect(@hasDecl(performance, "tester"));
}

test "PerformanceMonitor struct test" {
    try testing.expect(@hasDecl(performance.monitor.PerformanceMonitor, "init"));
    try testing.expect(@hasDecl(performance.monitor.PerformanceMonitor, "deinit"));
    try testing.expect(@hasDecl(performance.monitor.PerformanceMonitor, "collectMetrics"));
}

test "PerformanceDashboard struct test" {
    try testing.expect(@hasDecl(performance.dashboard.PerformanceDashboard, "init"));
    try testing.expect(@hasDecl(performance.dashboard.PerformanceDashboard, "deinit"));
    try testing.expect(@hasDecl(performance.dashboard.PerformanceDashboard, "start"));
    try testing.expect(@hasDecl(performance.dashboard.PerformanceDashboard, "stop"));
}

test "PerformanceOptimizer struct test" {
    try testing.expect(@hasDecl(performance.optimizer.PerformanceOptimizer, "init"));
    try testing.expect(@hasDecl(performance.optimizer.PerformanceOptimizer, "deinit"));
    try testing.expect(@hasDecl(performance.optimizer.PerformanceOptimizer, "analyzePerformance"));
}

test "PerformanceTester struct test" {
    try testing.expect(@hasDecl(performance.tester.PerformanceTester, "init"));
    try testing.expect(@hasDecl(performance.tester.PerformanceTester, "init"));
    try testing.expect(@hasDecl(performance.tester.PerformanceTester, "createTest"));
    try testing.expect(@hasDecl(performance.tester.PerformanceTester, "startTest"));
}

test "PerformanceMetrics basic test" {
    // Simple test that just checks the module can create a PerformanceMetrics
    const metrics = performance.monitor.PerformanceMetrics.init();
    try testing.expect(metrics.cpu_usage == 0.0);
}

test "DashboardConfig basic test" {
    // Simple test that just checks the module can create a DashboardConfig
    const config = performance.dashboard.DashboardConfig.default();
    try testing.expect(config.refresh_interval > 0);
}

test "TestConfig basic test" {
    // Simple test that just checks the module can create a TestConfig
    const config = performance.TestConfig.init(.load);
    try testing.expect(config.duration_seconds > 0);
}

test "TestResult basic test" {
    // Simple test that just checks the module can create a TestResult
    const result = performance.TestResult.init("test123", .load);
    try testing.expect(result.total_requests == 0);
}

test "Performance module types test" {
    try testing.expect(@hasDecl(performance.optimizer, "RecommendationPriority"));
    try testing.expect(@hasDecl(performance.optimizer, "OptimizationCategory"));
    try testing.expect(@hasDecl(performance.tester, "TestType"));
    try testing.expect(@hasDecl(performance.tester, "TestStatus"));
}
