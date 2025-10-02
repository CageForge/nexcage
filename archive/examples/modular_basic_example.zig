const std = @import("std");
const core = @import("../src/core/mod.zig");
const backends = @import("../src/backends/mod.zig");

/// Basic example demonstrating modular architecture usage
/// This example shows how to use the modular architecture to create and manage containers
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("🚀 Proxmox LXCRI Modular Architecture Example\n", .{});
    std.debug.print("==========================================\n", .{});

    // Initialize logger
    var logger = core.LogContext.init(allocator, std.io.getStdErr().writer(), core.LogLevel.info, "basic-example");
    defer logger.deinit();

    try logger.info("Starting basic modular architecture example", .{});

    // Example 1: LXC Backend
    try exampleLxcBackend(allocator, &logger);

    // Example 2: Proxmox LXC Backend
    try exampleProxmoxLxcBackend(allocator, &logger);

    // Example 3: Proxmox VM Backend
    try exampleProxmoxVmBackend(allocator, &logger);

    try logger.info("All examples completed successfully", .{});
    std.debug.print("\n✅ Basic example completed successfully!\n", .{});
}

fn exampleLxcBackend(allocator: std.mem.Allocator, logger: *core.LogContext) !void {
    try logger.info("=== LXC Backend Example ===", .{});

    // Create sandbox configuration
    const sandbox_config = core.types.SandboxConfig{
        .allocator = allocator,
        .name = try allocator.dupe(u8, "example-lxc-container"),
        .runtime_type = .lxc,
        .resources = core.types.ResourceLimits{
            .allocator = allocator,
            .memory = 512 * 1024 * 1024, // 512 MB
            .cpu = 1.0, // 1 CPU core
        },
        .network = core.types.NetworkConfig{
            .allocator = allocator,
            .bridge = try allocator.dupe(u8, "lxcbr0"),
            .ip = try allocator.dupe(u8, "10.0.3.100/24"),
            .gateway = try allocator.dupe(u8, "10.0.3.1"),
        },
        .storage = core.types.StorageConfig{
            .allocator = allocator,
            .type = .directory,
            .source = try allocator.dupe(u8, "/var/lib/lxc/example-lxc-container"),
            .size = 10 * 1024 * 1024 * 1024, // 10 GB
        },
    };

    // Initialize LXC backend
    const lxc_driver = try backends.lxc.LxcDriver.init(allocator, sandbox_config);
    defer lxc_driver.deinit();

    // Set logger
    lxc_driver.setLogger(logger);

    try logger.info("LXC driver initialized successfully", .{});

    // Note: In a real scenario, you would execute these operations
    // For this example, we'll just demonstrate the interface
    
    std.debug.print("  ✅ LXC Backend Example:\n", .{});
    std.debug.print("    - Container name: {s}\n", .{sandbox_config.name});
    std.debug.print("    - Runtime type: {}\n", .{sandbox_config.runtime_type});
    std.debug.print("    - Memory limit: {} MB\n", .{sandbox_config.resources.?.memory / (1024 * 1024)});
    std.debug.print("    - CPU limit: {d} cores\n", .{@intFromFloat(sandbox_config.resources.?.cpu)});
    std.debug.print("    - Network bridge: {s}\n", .{sandbox_config.network.?.bridge});
    std.debug.print("    - Storage size: {} GB\n", .{sandbox_config.storage.?.size / (1024 * 1024 * 1024)});
    
    try logger.info("LXC backend example completed", .{});
}

fn exampleProxmoxLxcBackend(allocator: std.mem.Allocator, logger: *core.LogContext) !void {
    try logger.info("=== Proxmox LXC Backend Example ===", .{});

    // Create Proxmox LXC backend configuration
    const proxmox_config = core.types.ProxmoxLxcBackendConfig{
        .allocator = allocator,
        .host = try allocator.dupe(u8, "proxmox.example.com"),
        .port = 8006,
        .username = try allocator.dupe(u8, "user@pam"),
        .password = try allocator.dupe(u8, "secure-password"),
        .realm = try allocator.dupe(u8, "pam"),
        .verify_ssl = false,
    };

    // Initialize Proxmox LXC backend
    const proxmox_lxc = try backends.proxmox_lxc.ProxmoxLxcDriver.init(allocator, proxmox_config);
    defer proxmox_lxc.deinit();

    // Set logger
    proxmox_lxc.setLogger(logger);

    try logger.info("Proxmox LXC driver initialized successfully", .{});

    // Create LXC container configuration
    const lxc_config = core.types.ProxmoxLxcConfig{
        .allocator = allocator,
        .vmid = 100,
        .hostname = try allocator.dupe(u8, "proxmox-lxc-example"),
        .memory = 1024, // 1 GB
        .cores = 2,
        .rootfs = try allocator.dupe(u8, "local-lvm:10"),
        .net0 = try allocator.dupe(u8, "bridge=vmbr0,ip=dhcp"),
        .ostemplate = try allocator.dupe(u8, "local:vztmpl/ubuntu-20.04-standard_20.04-1_amd64.tar.zst"),
        .password = try allocator.dupe(u8, "root-password"),
        .ssh_public_keys = try allocator.dupe(u8, "ssh-rsa AAAAB3NzaC1yc2E..."),
    };

    std.debug.print("  ✅ Proxmox LXC Backend Example:\n", .{});
    std.debug.print("    - Proxmox host: {s}:{}\n", .{ proxmox_config.host, proxmox_config.port });
    std.debug.print("    - VM ID: {d}\n", .{lxc_config.vmid});
    std.debug.print("    - Hostname: {s}\n", .{lxc_config.hostname});
    std.debug.print("    - Memory: {d} MB\n", .{lxc_config.memory});
    std.debug.print("    - Cores: {d}\n", .{lxc_config.cores});
    std.debug.print("    - Root filesystem: {s}\n", .{lxc_config.rootfs});
    std.debug.print("    - Network: {s}\n", .{lxc_config.net0});
    std.debug.print("    - OS template: {s}\n", .{lxc_config.ostemplate});
    
    try logger.info("Proxmox LXC backend example completed", .{});
}

fn exampleProxmoxVmBackend(allocator: std.mem.Allocator, logger: *core.LogContext) !void {
    try logger.info("=== Proxmox VM Backend Example ===", .{});

    // Create Proxmox VM backend configuration
    const proxmox_config = core.types.ProxmoxVmBackendConfig{
        .allocator = allocator,
        .host = try allocator.dupe(u8, "proxmox.example.com"),
        .port = 8006,
        .username = try allocator.dupe(u8, "user@pam"),
        .password = try allocator.dupe(u8, "secure-password"),
        .realm = try allocator.dupe(u8, "pam"),
        .verify_ssl = false,
    };

    // Initialize Proxmox VM backend
    const proxmox_vm = try backends.proxmox_vm.ProxmoxVmDriver.init(allocator, proxmox_config);
    defer proxmox_vm.deinit();

    // Set logger
    proxmox_vm.setLogger(logger);

    try logger.info("Proxmox VM driver initialized successfully", .{});

    // Create VM configuration
    const vm_config = core.types.ProxmoxVmConfig{
        .allocator = allocator,
        .vmid = 200,
        .name = try allocator.dupe(u8, "proxmox-vm-example"),
        .memory = 2048, // 2 GB
        .cores = 4,
        .sockets = 1,
        .cpu_type = try allocator.dupe(u8, "host"),
        .net0 = try allocator.dupe(u8, "virtio,bridge=vmbr0"),
        .scsi0 = try allocator.dupe(u8, "local-lvm:20,format=qcow2"),
        .ide2 = try allocator.dupe(u8, "local:iso/ubuntu-20.04-server-amd64.iso,media=cdrom"),
        .boot = try allocator.dupe(u8, "order=scsi0;ide2"),
    };

    std.debug.print("  ✅ Proxmox VM Backend Example:\n", .{});
    std.debug.print("    - Proxmox host: {s}:{}\n", .{ proxmox_config.host, proxmox_config.port });
    std.debug.print("    - VM ID: {d}\n", .{vm_config.vmid});
    std.debug.print("    - VM name: {s}\n", .{vm_config.name});
    std.debug.print("    - Memory: {d} MB\n", .{vm_config.memory});
    std.debug.print("    - Cores: {d}\n", .{vm_config.cores});
    std.debug.print("    - CPU type: {s}\n", .{vm_config.cpu_type});
    std.debug.print("    - Network: {s}\n", .{vm_config.net0});
    std.debug.print("    - Storage: {s}\n", .{vm_config.scsi0});
    std.debug.print("    - Boot order: {s}\n", .{vm_config.boot});
    
    try logger.info("Proxmox VM backend example completed", .{});
}
