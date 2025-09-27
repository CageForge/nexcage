const std = @import("std");
const core = @import("../core/mod.zig");
const backends = @import("../backends/mod.zig");

/// Start command implementation for modular architecture
pub const StartCommand = struct {
    const Self = @This();
    
    name: []const u8 = "start",
    description: []const u8 = "Start a container or virtual machine",
    logger: ?*core.LogContext = null,

    pub fn setLogger(self: *Self, logger: *core.LogContext) void {
        self.logger = logger;
    }

    pub fn execute(self: *Self, options: core.types.RuntimeOptions, allocator: std.mem.Allocator) !void {
        if (self.logger) |log| {
            try log.info("Executing start command", .{});
        }

        // Validate required options
        if (options.container_id == null) {
            if (self.logger) |log| {
                try log.@"error"("Container ID is required for start command", .{});
            }
            return core.Error.InvalidInput;
        }

        const container_id = options.container_id.?;
        const runtime_type = options.runtime_type orelse .lxc;

        if (self.logger) |log| {
            try log.info("Starting container {s} with runtime type {}", .{ container_id, runtime_type });
        }

        // Start container based on runtime type
        switch (runtime_type) {
            .lxc => {
                // Create minimal config for LXC driver
                const sandbox_config = core.types.SandboxConfig{
                    .allocator = allocator,
                    .name = try allocator.dupe(u8, container_id),
                    .runtime_type = .lxc,
                };

                const lxc_driver = try backends.lxc.LxcDriver.init(allocator, sandbox_config);
                defer lxc_driver.deinit();
                
                if (self.logger) |log| {
                    lxc_driver.setLogger(log);
                }

                try lxc_driver.start(container_id);
                
                if (self.logger) |log| {
                    try log.info("LXC container started successfully: {s}", .{container_id});
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

                // Get VMID by container name (simplified)
                const vmid = 100; // TODO: Implement proper VMID lookup
                
                try proxmox_lxc.startContainer(vmid);
                
                if (self.logger) |log| {
                    try log.info("Proxmox LXC container started successfully: {s} (VMID: {d})", .{ container_id, vmid });
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

                // Get VMID by VM name (simplified)
                const vmid = 200; // TODO: Implement proper VMID lookup
                
                try proxmox_vm.startVm(vmid);
                
                if (self.logger) |log| {
                    try log.info("Proxmox VM started successfully: {s} (VMID: {d})", .{ container_id, vmid });
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

                try crun_driver.startContainer(container_id);
                
                if (self.logger) |log| {
                    try log.info("Crun container started successfully: {s}", .{container_id});
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
            try log.info("Start command completed successfully", .{});
        }
    }
};
