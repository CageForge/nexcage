// Performance monitoring and optimization module
// This module provides comprehensive performance monitoring, metrics collection,
// alerting, and optimization recommendations for the proxmox-lxcri system.

pub const monitor = @import("monitor.zig");
pub const dashboard = @import("dashboard.zig");
pub const optimizer = @import("optimizer.zig");
pub const tester = @import("tester.zig");

// Re-export main types for convenience
pub const PerformanceMonitor = monitor.PerformanceMonitor;
pub const PerformanceMetrics = monitor.PerformanceMetrics;
pub const PerformanceDashboard = dashboard.PerformanceDashboard;
pub const DashboardConfig = dashboard.DashboardConfig;
pub const PerformanceAlert = dashboard.PerformanceAlert;
pub const DashboardView = dashboard.DashboardView;
pub const PerformanceTrends = dashboard.PerformanceTrends;

// Performance optimization recommendations
pub const PerformanceOptimizer = optimizer.PerformanceOptimizer;
pub const OptimizationRecommendation = optimizer.OptimizationRecommendation;

// Performance testing framework
pub const PerformanceTester = tester.PerformanceTester;
pub const PerformanceTest = tester.PerformanceTest;
pub const TestConfig = tester.TestConfig;
pub const TestResult = tester.TestResult;

// Export all performance-related functionality
pub const performance = struct {
    pub const Monitor = PerformanceMonitor;
    pub const Dashboard = PerformanceDashboard;
    pub const Optimizer = PerformanceOptimizer;
    pub const Tester = PerformanceTester;
    
    pub const Metrics = PerformanceMetrics;
    pub const Alert = PerformanceAlert;
    pub const View = DashboardView;
    pub const Trends = PerformanceTrends;
    pub const Config = DashboardConfig;
    pub const Recommendation = OptimizationRecommendation;
    pub const Test = PerformanceTest;
    pub const Result = TestResult;
};
