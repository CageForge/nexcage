const std = @import("std");
const core = @import("../core/mod.zig");
const backends = @import("../backends/mod.zig");

/// List command implementation for modular architecture
pub const ListCommand = struct {
    const Self = @This();
    
    name: []const u8 = "list",
    description: []const u8 = "List containers and virtual machines",
    logger: ?*core.LogContext = null,

    pub fn setLogger(self: *Self, logger: *core.LogContext) void {
        self.logger = logger;
    }

    pub fn execute(self: *Self, options: core.types.RuntimeOptions, allocator: std.mem.Allocator) !void {
        if (self.logger) |log| {
            try log.info("Executing list command", .{});
        }

        const runtime_type = options.runtime_type orelse .lxc;

        if (self.logger) |log| {
            try log.info("Listing containers with runtime type {}", .{runtime_type});
        }

        // List containers based on runtime type
        switch (runtime_type) {
            .lxc => {
                // Create minimal config for LXC driver
                const sandbox_config = core.types.SandboxConfig{
                    .allocator = allocator,
                    .name = try allocator.dupe(u8, ""),
                    .runtime_type = .lxc,
                };

                const lxc_driver = try backends.lxc.LxcDriver.init(allocator, sandbox_config);
                defer lxc_driver.deinit();
                
                if (self.logger) |log| {
                    lxc_driver.setLogger(log);
                }

                const containers = try lxc_driver.list(allocator);
                defer allocator.free(containers);

                std.debug.print("LXC Containers:\n", .{});
                for (containers, 0..) |container, i| {
                    std.debug.print("  {d}. {s} - State: {s}\n", .{ i + 1, container.name, container.state });
                }
                
                if (self.logger) |log| {
                    try log.info("Found {d} LXC containers", .{containers.len});
                }
            },
            .proxmox_lxc => {
                // Initialize Proxmox LXC backend
                const proxmox_config = core.types.ProxmoxLxcBackendConfig{
                    .allocator = allocator,
                    .host = try allocator.dupe(u8, "localhost"),
                    .port = 8006,
                    .username = try allocator.dupe(u8, "user@pam"),
                    .password = try allocator.dupe(u8, "password"),
                    .realm = try allocator.dupe(u8, "pam"),
                    .verify_ssl = false,
                };

                const proxmox_lxc = try backends.proxmox_lxc.ProxmoxLxcDriver.init(allocator, proxmox_config);
                defer proxmox_lxc.deinit();

                if (self.logger) |log| {
                    proxmox_lxc.setLogger(log);
                }

                const containers = try proxmox_lxc.listContainers();
                defer allocator.free(containers);

                std.debug.print("Proxmox LXC Containers:\n", .{});
                for (containers, 0..) |container, i| {
                    std.debug.print("  {d}. {s} (VMID: {d}) - Status: {s}\n", .{ i + 1, container.hostname, container.vmid, container.status });
                }
                
                if (self.logger) |log| {
                    try log.info("Found {d} Proxmox LXC containers", .{containers.len});
                }
            },
            .proxmox_vm => {
                // Initialize Proxmox VM backend
                const proxmox_config = core.types.ProxmoxVmBackendConfig{
                    .allocator = allocator,
                    .host = try allocator.dupe(u8, "localhost"),
                    .port = 8006,
                    .username = try allocator.dupe(u8, "user@pam"),
                    .password = try allocator.dupe(u8, "password"),
                    .realm = try allocator.dupe(u8, "pam"),
                    .verify_ssl = false,
                };

                const proxmox_vm = try backends.proxmox_vm.ProxmoxVmDriver.init(allocator, proxmox_config);
                defer proxmox_vm.deinit();

                if (self.logger) |log| {
                    proxmox_vm.setLogger(log);
                }

                const vms = try proxmox_vm.listVms();
                defer allocator.free(vms);

                std.debug.print("Proxmox VMs:\n", .{});
                for (vms, 0..) |vm, i| {
                    std.debug.print("  {d}. {s} (VMID: {d}) - Status: {s}\n", .{ i + 1, vm.name, vm.vmid, vm.status });
                }
                
                if (self.logger) |log| {
                    try log.info("Found {d} Proxmox VMs", .{vms.len});
                }
            },
            .crun => {
                // Initialize Crun backend
                const crun_config = core.types.CrunBackendConfig{
                    .allocator = allocator,
                    .runtime_path = try allocator.dupe(u8, "/usr/bin/crun"),
                    .root = try allocator.dupe(u8, "/var/lib/containers"),
                    .state = try allocator.dupe(u8, "/var/lib/containers"),
                };

                const crun_driver = try backends.crun.CrunDriver.init(allocator, crun_config);
                defer crun_driver.deinit();

                if (self.logger) |log| {
                    crun_driver.setLogger(log);
                }

                const containers = try crun_driver.listContainers(allocator);
                defer allocator.free(containers);

                std.debug.print("Crun Containers:\n", .{});
                for (containers, 0..) |container, i| {
                    std.debug.print("  {d}. {s} - State: {s}\n", .{ i + 1, container.name, container.state });
                }
                
                if (self.logger) |log| {
                    try log.info("Found {d} Crun containers", .{containers.len});
                }
            },
            else => {
                if (self.logger) |log| {
                    try log.@"error"("Unsupported runtime type: {}", .{runtime_type});
                }
                return core.Error.UnsupportedRuntime;
            },
        }

        if (self.logger) |log| {
            try log.info("List command completed successfully", .{});
        }
    }
};
