/// Proxmox VM Backend Plugin for NexCage
/// 
/// This plugin wraps the existing Proxmox VM backend implementation as a plugin,
/// providing VM-based container management through Proxmox VE API.

const std = @import("std");
const plugin = @import("../../../plugin/mod.zig");
const proxmox_vm_backend = @import("../../../backends/proxmox-vm/mod.zig");
const core = @import("../../../core/mod.zig");

/// Plugin metadata
export const metadata = plugin.PluginMetadata{
    .name = "proxmox-vm-backend",
    .version = plugin.SemanticVersion{ .major = 1, .minor = 0, .patch = 0 },
    .description = "Proxmox VM container backend plugin for NexCage",
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
        .system_metrics,
        .logging,
    },
    .resource_requirements = plugin.ResourceRequirements{
        .max_memory_mb = 512,
        .max_cpu_percent = 25,
        .max_file_descriptors = 400,
        .max_threads = 10,
        .timeout_seconds = 180,
        .max_network_connections = 100,
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
    .name = "proxmox-vm",
    .description = "Proxmox VM container backend",
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
var proxmox_vm_driver: ?*proxmox_vm_backend.driver.ProxmoxVmDriver = null;
var plugin_allocator: ?std.mem.Allocator = null;
var plugin_config: ?proxmox_vm_backend.types.ProxmoxVmBackendConfig = null;

/// Plugin initialization
fn pluginInit(context: *plugin.PluginContext) !void {
    plugin_allocator = context.allocator;
    
    // TODO: Load configuration from plugin config or environment
    // For now, use default configuration
    const config = proxmox_vm_backend.types.ProxmoxVmBackendConfig{
        .proxmox_host = "localhost",
        .proxmox_port = 8006,
        .proxmox_node = "pve",
        .proxmox_token = "",
        .verify_ssl = false,
        .timeout = 30,
        .vm_cores = 2,
        .vm_memory = 2048,
        .vm_disk = 20,
        .vm_os_type = "l26",
        .vm_network_model = "virtio",
        .vm_storage = "local-lvm",
        .iso_storage = "local",
        .auto_start = false,
    };
    
    plugin_config = config;
    
    // Initialize the Proxmox VM driver
    proxmox_vm_driver = try proxmox_vm_backend.driver.ProxmoxVmDriver.init(context.allocator, config);
    
    std.log.info("Proxmox VM backend plugin '{}' initialized", .{context.getPluginName()});
}

/// Plugin cleanup
fn pluginDeinit(context: *plugin.PluginContext) void {
    if (proxmox_vm_driver) |driver| {
        driver.deinit();
    }
    proxmox_vm_driver = null;
    plugin_allocator = null;
    plugin_config = null;
    
    std.log.info("Proxmox VM backend plugin '{}' deinitialized", .{context.getPluginName()});
}

/// Plugin health check
fn pluginHealthCheck(context: *plugin.PluginContext) !plugin.HealthStatus {
    _ = context;
    
    // Check if Proxmox VM tools are available
    const allocator = plugin_allocator orelse return .unhealthy;
    
    // Check for qm command availability
    const qm_result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "qm", "help" },
        .max_output_bytes = 1024,
    }) catch return .unhealthy;
    
    defer allocator.free(qm_result.stdout);
    defer allocator.free(qm_result.stderr);
    
    if (qm_result.term != .Exited or qm_result.term.Exited != 0) {
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

/// Backend implementation - Create container (VM)
fn backendCreate(context: *plugin.PluginContext, container_id: []const u8) !void {
    const driver = proxmox_vm_driver orelse return error.DriverNotInitialized;
    
    // Convert container_id to SandboxConfig for Proxmox VM
    const config = core.types.SandboxConfig{
        .name = container_id,
        .image = null, // Will use default VM template/ISO
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
    
    std.log.info("Proxmox VM container '{}' created via plugin from context '{}'", 
        .{ container_id, context.getPluginName() });
}

/// Backend implementation - Start container (VM)
fn backendStart(context: *plugin.PluginContext, container_id: []const u8) !void {
    const driver = proxmox_vm_driver orelse return error.DriverNotInitialized;
    
    try driver.start(container_id);
    
    std.log.info("Proxmox VM container '{}' started via plugin from context '{}'", 
        .{ container_id, context.getPluginName() });
}

/// Backend implementation - Stop container (VM)
fn backendStop(context: *plugin.PluginContext, container_id: []const u8) !void {
    const driver = proxmox_vm_driver orelse return error.DriverNotInitialized;
    
    try driver.stop(container_id);
    
    std.log.info("Proxmox VM container '{}' stopped via plugin from context '{}'", 
        .{ container_id, context.getPluginName() });
}

/// Backend implementation - Delete container (VM)
fn backendDelete(context: *plugin.PluginContext, container_id: []const u8) !void {
    const driver = proxmox_vm_driver orelse return error.DriverNotInitialized;
    
    try driver.delete(container_id);
    
    std.log.info("Proxmox VM container '{}' deleted via plugin from context '{}'", 
        .{ container_id, context.getPluginName() });
}

/// Backend implementation - List containers (VMs)
fn backendList(context: *plugin.PluginContext, allocator: std.mem.Allocator) ![]const u8 {
    _ = context;
    const driver = proxmox_vm_driver orelse return error.DriverNotInitialized;
    
    // Call driver's list method and format as JSON
    const vms = try driver.list(allocator);
    defer {
        for (vms) |*vm| {
            vm.deinit();
        }
        allocator.free(vms);
    }
    
    // Convert to JSON format
    var json_list = std.ArrayList(u8).empty;
    defer json_list.deinit(allocator);
    
    try json_list.append(allocator, '[');
    
    for (vms, 0..) |vm, i| {
        if (i > 0) try json_list.appendSlice(allocator, ",");
        
        const vm_json = try std.fmt.allocPrint(allocator,
            \\{{"id":"{s}","name":"{s}","status":"{s}","backend":"proxmox-vm"}}
        , .{ vm.id, vm.name, vm.status });
        defer allocator.free(vm_json);
        
        try json_list.appendSlice(allocator, vm_json);
    }
    
    try json_list.append(allocator, ']');
    
    return json_list.toOwnedSlice(allocator);
}

/// Backend implementation - Get container (VM) info
fn backendInfo(context: *plugin.PluginContext, container_id: []const u8, allocator: std.mem.Allocator) ![]const u8 {
    _ = context;
    const driver = proxmox_vm_driver orelse return error.DriverNotInitialized;
    
    // Get VM info from driver
    const vm_info = try driver.info(container_id, allocator);
    defer vm_info.deinit();
    
    // Format as JSON with VM-specific details
    const result = try std.fmt.allocPrint(allocator,
        \\{{"id":"{s}","name":"{s}","status":"{s}","backend":"proxmox-vm","runtime":"qemu-kvm","type":"vm"}}
    , .{ vm_info.id, vm_info.name, vm_info.status });
    
    return result;
}

/// Backend implementation - Execute command in container (VM)
fn backendExec(
    context: *plugin.PluginContext, 
    container_id: []const u8, 
    command: []const []const u8,
    allocator: std.mem.Allocator
) !plugin.CommandResult {
    _ = context;
    const driver = proxmox_vm_driver orelse return error.DriverNotInitialized;
    
    const start_time = std.time.milliTimestamp();
    
    // Execute command using driver (VM execution might use guest agent)
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

test "proxmox vm plugin metadata validation" {
    try testing.expect(metadata.validate());
    try testing.expect(std.mem.eql(u8, metadata.name, "proxmox-vm-backend"));
    try testing.expect(metadata.provides_backend);
}

test "proxmox vm plugin capabilities" {
    try testing.expect(metadata.hasCapability(.container_create));
    try testing.expect(metadata.hasCapability(.container_start));
    try testing.expect(metadata.hasCapability(.network_client));
    try testing.expect(metadata.hasCapability(.system_info));
    try testing.expect(metadata.hasCapability(.system_metrics));
    try testing.expect(!metadata.hasCapability(.process_spawn));
}

test "proxmox vm plugin resource requirements" {
    const reqs = metadata.resource_requirements;
    try testing.expect(reqs.validate());
    try testing.expect(reqs.max_memory_mb == 512);
    try testing.expect(reqs.max_cpu_percent == 25);
    try testing.expect(reqs.max_network_connections == 100);
    try testing.expect(reqs.timeout_seconds == 180);
}