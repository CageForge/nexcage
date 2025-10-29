/// Runc Backend Plugin for NexCage
/// 
/// This plugin wraps the existing runc backend implementation as a plugin,
/// providing OCI container runtime functionality through the plugin system.

const std = @import("std");
const plugin = @import("../../../plugin/mod.zig");
const runc_backend = @import("../../../backends/runc/mod.zig");
const core = @import("../../../core/mod.zig");

/// Plugin metadata
export const metadata = plugin.PluginMetadata{
    .name = "runc-backend",
    .version = plugin.SemanticVersion{ .major = 1, .minor = 0, .patch = 0 },
    .description = "Runc OCI container runtime backend plugin",
    .author = "NexCage Team",
    .api_version = 1,
    .nexcage_version = plugin.SemanticVersion{ .major = 0, .minor = 7, .patch = 0 },
    .dependencies = &[_][]const u8{},
    .capabilities = &[_]plugin.Capability{
        .container_create,
        .container_start,
        .container_stop,
        .container_delete,
        .container_exec,
        .container_list,
        .container_info,
        .host_command,
        .filesystem_read,
        .filesystem_write,
        .logging,
    },
    .resource_requirements = plugin.ResourceRequirements{
        .max_memory_mb = 128,
        .max_cpu_percent = 10,
        .max_file_descriptors = 200,
        .max_threads = 5,
        .timeout_seconds = 60,
    },
    .provides_backend = true,
};

/// Plugin lifecycle hooks
export const hooks = plugin.PluginHooks{
    .init = pluginInit,
    .deinit = pluginDeinit,
    .health_check = pluginHealthCheck,
};

/// Plugin extensions - backend implementation
export const extensions = plugin.PluginExtensions{
    .backend = &backend_extension,
};

/// Backend extension implementation
const backend_extension = plugin.BackendExtension{
    .name = "runc",
    .description = "Runc OCI container runtime",
    .version = plugin.SemanticVersion{ .major = 1, .minor = 0, .patch = 0 },
    .create = backendCreate,
    .start = backendStart,
    .stop = backendStop,
    .delete = backendDelete,
    .list = backendList,
    .info = backendInfo,
    .exec = backendExec,
};

/// Plugin state
var runc_driver: ?runc_backend.RuncDriver = null;
var plugin_allocator: ?std.mem.Allocator = null;

/// Plugin initialization
fn pluginInit(context: *plugin.PluginContext) !void {
    plugin_allocator = context.allocator;
    
    // Initialize the runc driver
    runc_driver = runc_backend.RuncDriver.init(context.allocator, null);
    
    std.log.info("Runc backend plugin '{}' initialized", .{context.getPluginName()});
}

/// Plugin cleanup
fn pluginDeinit(context: *plugin.PluginContext) void {
    if (runc_driver) |*driver| {
        driver.deinit();
    }
    runc_driver = null;
    plugin_allocator = null;
    
    std.log.info("Runc backend plugin '{}' deinitialized", .{context.getPluginName()});
}

/// Plugin health check
fn pluginHealthCheck(context: *plugin.PluginContext) !plugin.HealthStatus {
    _ = context;
    
    // Check if runc binary is available
    const allocator = plugin_allocator orelse return .unhealthy;
    
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "runc", "--version" },
        .max_output_bytes = 1024,
    }) catch return .unhealthy;
    
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    
    return if (result.term == .Exited and result.term.Exited == 0) .healthy else .degraded;
}

/// Backend implementation - Create container
fn backendCreate(context: *plugin.PluginContext, container_id: []const u8) !void {
    const driver = runc_driver orelse return error.DriverNotInitialized;
    
    // Convert container_id to SandboxConfig
    const config = core.types.SandboxConfig{
        .name = container_id,
        .image = null,
        .command = null,
        .working_dir = null,
        .environment = null,
        .ports = null,
        .volumes = null,
        .resources = null,
        .network = null,
        .security = null,
    };
    
    try driver.create(config);
    
    std.log.info("Container '{}' created via runc plugin from context '{}'", 
        .{ container_id, context.getPluginName() });
}

/// Backend implementation - Start container
fn backendStart(context: *plugin.PluginContext, container_id: []const u8) !void {
    const driver = runc_driver orelse return error.DriverNotInitialized;
    
    try driver.start(container_id);
    
    std.log.info("Container '{}' started via runc plugin from context '{}'", 
        .{ container_id, context.getPluginName() });
}

/// Backend implementation - Stop container
fn backendStop(context: *plugin.PluginContext, container_id: []const u8) !void {
    const driver = runc_driver orelse return error.DriverNotInitialized;
    
    try driver.stop(container_id);
    
    std.log.info("Container '{}' stopped via runc plugin from context '{}'", 
        .{ container_id, context.getPluginName() });
}

/// Backend implementation - Delete container
fn backendDelete(context: *plugin.PluginContext, container_id: []const u8) !void {
    const driver = runc_driver orelse return error.DriverNotInitialized;
    
    try driver.delete(container_id);
    
    std.log.info("Container '{}' deleted via runc plugin from context '{}'", 
        .{ container_id, context.getPluginName() });
}

/// Backend implementation - List containers
fn backendList(context: *plugin.PluginContext, allocator: std.mem.Allocator) ![]const u8 {
    _ = context;
    _ = runc_driver orelse return error.DriverNotInitialized;
    
    // For now, return a basic JSON list
    // In real implementation, this would call runc list and parse the output
    const result = try allocator.dupe(u8, "[]");
    return result;
}

/// Backend implementation - Get container info
fn backendInfo(context: *plugin.PluginContext, container_id: []const u8, allocator: std.mem.Allocator) ![]const u8 {
    _ = context;
    _ = runc_driver orelse return error.DriverNotInitialized;
    
    // For now, return basic container info as JSON
    // In real implementation, this would call runc state and parse the output
    const result = try std.fmt.allocPrint(allocator,
        \\{{"id": "{s}", "status": "unknown", "runtime": "runc"}}
    , .{container_id});
    
    return result;
}

/// Backend implementation - Execute command in container
fn backendExec(
    context: *plugin.PluginContext, 
    container_id: []const u8, 
    command: []const []const u8,
    allocator: std.mem.Allocator
) !plugin.CommandResult {
    _ = context;
    _ = runc_driver orelse return error.DriverNotInitialized;
    
    // Build runc exec command
    var args = std.ArrayList([]const u8).init(allocator);
    defer args.deinit();
    
    try args.append("runc");
    try args.append("exec");
    try args.append(container_id);
    
    for (command) |arg| {
        try args.append(arg);
    }
    
    const start_time = std.time.milliTimestamp();
    
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = args.items,
        .max_output_bytes = 1024 * 1024,
    });
    
    const end_time = std.time.milliTimestamp();
    const exit_code: i32 = switch (result.term) {
        .Exited => |code| @intCast(code),
        .Signal => |sig| @intCast(128 + sig),
        else => 1,
    };
    
    return plugin.CommandResult{
        .exit_code = exit_code,
        .stdout = result.stdout,
        .stderr = result.stderr,
        .duration_ms = @intCast(end_time - start_time),
    };
}

/// Test suite for the plugin
const testing = std.testing;

test "runc plugin metadata validation" {
    try testing.expect(metadata.validate());
    try testing.expect(std.mem.eql(u8, metadata.name, "runc-backend"));
    try testing.expect(metadata.provides_backend);
}

test "runc plugin capabilities" {
    try testing.expect(metadata.hasCapability(.container_create));
    try testing.expect(metadata.hasCapability(.container_start));
    try testing.expect(metadata.hasCapability(.host_command));
    try testing.expect(!metadata.hasCapability(.network_server));
}

test "runc plugin resource requirements" {
    const reqs = metadata.resource_requirements;
    try testing.expect(reqs.validate());
    try testing.expect(reqs.max_memory_mb == 128);
    try testing.expect(reqs.max_cpu_percent == 10);
}