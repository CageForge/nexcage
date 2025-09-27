const std = @import("std");
const core = @import("../core/mod.zig");
const backends = @import("../backends/mod.zig");

/// Create command implementation for modular architecture
pub const CreateCommand = struct {
    const Self = @This();
    
    name: []const u8 = "create",
    description: []const u8 = "Create a new container or virtual machine",
    logger: ?*core.LogContext = null,

    pub fn setLogger(self: *Self, logger: *core.LogContext) void {
        self.logger = logger;
    }

    pub fn execute(self: *Self, options: core.types.RuntimeOptions, allocator: std.mem.Allocator) !void {
        if (self.logger) |log| {
            try log.info("Executing create command", .{});
        }

        // Validate required options
        if (options.container_id == null or options.image == null) {
            if (self.logger) |log| {
                try log.@"error"("Container ID and image are required for create command", .{});
            }
            return core.Error.InvalidInput;
        }

        const container_id = options.container_id.?;
        const image = options.image.?;

        if (self.logger) |log| {
            try log.info("Creating container {s} with image {s}", .{ container_id, image });
        }

        // Create sandbox configuration
        const sandbox_config = core.types.SandboxConfig{
            .allocator = allocator,
            .name = try allocator.dupe(u8, container_id),
            .runtime_type = options.runtime_type orelse .lxc,
            .resources = core.types.ResourceLimits{
                .allocator = allocator,
                .memory = options.memory_limit orelse 512 * 1024 * 1024, // Default 512 MB
                .cpu = options.cpu_limit orelse 1.0, // Default 1 CPU core
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
                .source = try allocator.dupe(u8, "/var/lib/lxc"),
                .size = 10 * 1024 * 1024 * 1024, // Default 10 GB
            },
        };

        // Select backend based on runtime type
        switch (sandbox_config.runtime_type) {
            .lxc => {
                const lxc_driver = try backends.lxc.LxcDriver.init(allocator, sandbox_config);
                defer lxc_driver.deinit();
                
                if (self.logger) |log| {
                    lxc_driver.setLogger(log);
                }

                try lxc_driver.create(sandbox_config);
                
                if (self.logger) |log| {
                    try log.info("LXC container created successfully: {s}", .{container_id});
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

                // Create Proxmox LXC container
                const lxc_config = core.types.ProxmoxLxcConfig{
                    .allocator = allocator,
                    .vmid = 100, // TODO: Get next available VMID
                    .hostname = try allocator.dupe(u8, container_id),
                    .memory = 1024,
                    .cores = 1,
                    .rootfs = try allocator.dupe(u8, "local-lvm:8"),
                    .net0 = try allocator.dupe(u8, "bridge=vmbr0,ip=dhcp"),
                    .ostemplate = try allocator.dupe(u8, image),
                };

                try proxmox_lxc.createContainer(lxc_config);
                
                if (self.logger) |log| {
                    try log.info("Proxmox LXC container created successfully: {s}", .{container_id});
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

                // Create Proxmox VM
                const vm_config = core.types.ProxmoxVmConfig{
                    .allocator = allocator,
                    .vmid = 200, // TODO: Get next available VMID
                    .name = try allocator.dupe(u8, container_id),
                    .memory = 2048,
                    .cores = 2,
                    .sockets = 1,
                    .cpu_type = try allocator.dupe(u8, "host"),
                    .net0 = try allocator.dupe(u8, "virtio,bridge=vmbr0"),
                    .scsi0 = try allocator.dupe(u8, "local-lvm:20,format=qcow2"),
                    .ide2 = try allocator.dupe(u8, "local:iso/ubuntu-20.04-server-amd64.iso,media=cdrom"),
                    .boot = try allocator.dupe(u8, "order=scsi0;ide2"),
                };

                try proxmox_vm.createVm(vm_config);
                
                if (self.logger) |log| {
                    try log.info("Proxmox VM created successfully: {s}", .{container_id});
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

                // Create OCI bundle and container
                try crun_driver.createContainer(container_id, image, sandbox_config);
                
                if (self.logger) |log| {
                    try log.info("Crun container created successfully: {s}", .{container_id});
                }
            },
            else => {
                if (self.logger) |log| {
                    try log.@"error"("Unsupported runtime type: {}", .{sandbox_config.runtime_type});
                }
                return core.Error.UnsupportedRuntime;
            },
        }

        if (self.logger) |log| {
            try log.info("Create command completed successfully", .{});
        }
    }
};
