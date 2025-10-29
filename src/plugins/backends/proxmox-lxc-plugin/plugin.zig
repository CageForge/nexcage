/// Proxmox LXC Backend Plugin for NexCage
/// 
/// This plugin wraps the existing Proxmox LXC backend implementation as a plugin,
/// providing LXC container management through Proxmox VE API and pct CLI.

const std = @import("std");
const plugin = @import("../../../plugin/mod.zig");
const proxmox_lxc_backend = @import("../../../backends/proxmox-lxc/mod.zig");
const core = @import("../../../core/mod.zig");

/// Plugin metadata
export const metadata = plugin.PluginMetadata{
    .name = "proxmox-lxc-backend",
    .version = plugin.SemanticVersion{ .major = 1, .minor = 0, .patch = 0 },
    .description = "Proxmox LXC container backend plugin for NexCage",
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
        .network_client,
        .network_server,
        .system_info,
        .logging,
    },
    .resource_requirements = plugin.ResourceRequirements{
        .max_memory_mb = 256,
        .max_cpu_percent = 15,
        .max_file_descriptors = 300,
        .max_threads = 8,
        .timeout_seconds = 120,
        .max_network_connections = 50,
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
    .name = "proxmox-lxc",
    .description = "Proxmox LXC container backend",
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
var proxmox_lxc_driver: ?*proxmox_lxc_backend.driver.ProxmoxLxcDriver = null;
var plugin_allocator: ?std.mem.Allocator = null;
var plugin_config: ?core.types.ProxmoxLxcBackendConfig = null;

/// Plugin initialization
fn pluginInit(context: *plugin.PluginContext) !void {
    plugin_allocator = context.allocator;
    
    // TODO: Load configuration from plugin config or environment
    // For now, use default configuration
    const config = core.types.ProxmoxLxcBackendConfig{
        .proxmox_host = "localhost",
        .proxmox_port = 8006,
        .proxmox_node = "pve",
        .proxmox_token = "",
        .template_storage = "local",
        .container_storage = "local-lvm",
        .verify_ssl = false,
        .timeout = 30,
        .default_template = "ubuntu-20.04-standard",
        .network_bridge = "vmbr0",
        .container_cores = 1,
        .container_memory = 512,
        .container_disk = 8,
        .auto_start = false,
        .unprivileged = true,
    };
    
    plugin_config = config;
    
    // Initialize the Proxmox LXC driver
    proxmox_lxc_driver = try proxmox_lxc_backend.driver.ProxmoxLxcDriver.init(context.allocator, config);
    
    std.log.info("Proxmox LXC backend plugin '{}' initialized", .{context.getPluginName()});
}

/// Plugin cleanup
fn pluginDeinit(context: *plugin.PluginContext) void {
    if (proxmox_lxc_driver) |driver| {
        driver.deinit();
    }
    proxmox_lxc_driver = null;
    plugin_allocator = null;
    plugin_config = null;
    
    std.log.info("Proxmox LXC backend plugin '{}' deinitialized", .{context.getPluginName()});
}

/// Plugin health check
fn pluginHealthCheck(context: *plugin.PluginContext) !plugin.HealthStatus {
    _ = context;
    
    // Check if Proxmox LXC tools are available
    const allocator = plugin_allocator orelse return .unhealthy;
    
    // Check for pct command availability
    const pct_result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "pct", "--version" },
        .max_output_bytes = 1024,
    }) catch return .unhealthy;
    
    defer allocator.free(pct_result.stdout);
    defer allocator.free(pct_result.stderr);
    
    if (pct_result.term != .Exited or pct_result.term.Exited != 0) {
        return .degraded;
    }
    
    // Check Proxmox API connectivity (basic check)
    if (plugin_config) |config| {
        if (config.proxmox_host.len == 0 or config.proxmox_token.len == 0) {
            return .degraded;
        }
    }
    
    return .healthy;
}

/// Backend implementation - Create container
fn backendCreate(context: *plugin.PluginContext, container_id: []const u8) !void {
    const driver = proxmox_lxc_driver orelse return error.DriverNotInitialized;
    
    // Convert container_id to SandboxConfig for Proxmox LXC
    const config = core.types.SandboxConfig{
        .name = container_id,
        .image = null, // Will use default template from plugin config
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
    
    std.log.info("Proxmox LXC container '{}' created via plugin from context '{}'", 
        .{ container_id, context.getPluginName() });
}

/// Backend implementation - Start container
fn backendStart(context: *plugin.PluginContext, container_id: []const u8) !void {
    const driver = proxmox_lxc_driver orelse return error.DriverNotInitialized;
    
    try driver.start(container_id);
    
    std.log.info("Proxmox LXC container '{}' started via plugin from context '{}'", 
        .{ container_id, context.getPluginName() });
}

/// Backend implementation - Stop container
fn backendStop(context: *plugin.PluginContext, container_id: []const u8) !void {
    const driver = proxmox_lxc_driver orelse return error.DriverNotInitialized;
    
    try driver.stop(container_id);
    
    std.log.info("Proxmox LXC container '{}' stopped via plugin from context '{}'", 
        .{ container_id, context.getPluginName() });
}

/// Backend implementation - Delete container
fn backendDelete(context: *plugin.PluginContext, container_id: []const u8) !void {
    const driver = proxmox_lxc_driver orelse return error.DriverNotInitialized;
    
    try driver.delete(container_id);
    
    std.log.info("Proxmox LXC container '{}' deleted via plugin from context '{}'", 
        .{ container_id, context.getPluginName() });
}

/// Backend implementation - List containers
fn backendList(context: *plugin.PluginContext, allocator: std.mem.Allocator) ![]const u8 {
    _ = context;
    const driver = proxmox_lxc_driver orelse return error.DriverNotInitialized;
    
    // Call driver's list method and format as JSON
    const containers = try driver.list(allocator);
    defer {
        for (containers) |*container| {
            container.deinit();
        }
        allocator.free(containers);
    }
    
    // Convert to JSON format
    var json_list = std.ArrayList(u8).empty;
    defer json_list.deinit(allocator);
    
    try json_list.append(allocator, '[');
    
    for (containers, 0..) |container, i| {
        if (i > 0) try json_list.appendSlice(allocator, ",");
        
        const container_json = try std.fmt.allocPrint(allocator,
            \\{{"id":"{s}","name":"{s}","status":"{s}","backend":"proxmox-lxc"}}
        , .{ container.id, container.name, container.status });
        defer allocator.free(container_json);
        
        try json_list.appendSlice(allocator, container_json);
    }
    
    try json_list.append(allocator, ']');
    
    return json_list.toOwnedSlice(allocator);
}

/// Backend implementation - Get container info
fn backendInfo(context: *plugin.PluginContext, container_id: []const u8, allocator: std.mem.Allocator) ![]const u8 {
    _ = context;
    const driver = proxmox_lxc_driver orelse return error.DriverNotInitialized;
    
    // Get container info from driver
    const container_info = try driver.info(container_id, allocator);
    defer container_info.deinit();
    
    // Format as JSON
    const result = try std.fmt.allocPrint(allocator,
        \\{{"id":"{s}","name":"{s}","status":"{s}","backend":"proxmox-lxc","runtime":"proxmox-lxc"}}
    , .{ container_info.id, container_info.name, container_info.status });
    
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
    const driver = proxmox_lxc_driver orelse return error.DriverNotInitialized;
    
    const start_time = std.time.milliTimestamp();
    
    // Execute command using driver
    try driver.exec(container_id, command, allocator);
    
    const end_time = std.time.milliTimestamp();
    
    // For now, return success - in real implementation, capture actual output
    return plugin.CommandResult{
        .exit_code = 0,
        .stdout = try allocator.dupe(u8, ""),
        .stderr = try allocator.dupe(u8, ""),
        .duration_ms = @intCast(end_time - start_time),
    };
}

/// Test suite for the plugin
const testing = std.testing;

test "proxmox lxc plugin metadata validation" {
    try testing.expect(metadata.validate());
    try testing.expect(std.mem.eql(u8, metadata.name, "proxmox-lxc-backend"));
    try testing.expect(metadata.provides_backend);
}

test "proxmox lxc plugin capabilities" {
    try testing.expect(metadata.hasCapability(.container_create));
    try testing.expect(metadata.hasCapability(.container_start));
    try testing.expect(metadata.hasCapability(.network_client));
    try testing.expect(metadata.hasCapability(.system_info));
    try testing.expect(!metadata.hasCapability(.process_spawn));
}

test "proxmox lxc plugin resource requirements" {
    const reqs = metadata.resource_requirements;
    try testing.expect(reqs.validate());
    try testing.expect(reqs.max_memory_mb == 256);
    try testing.expect(reqs.max_cpu_percent == 15);
    try testing.expect(reqs.max_network_connections == 50);
}