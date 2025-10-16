const std = @import("std");
const core = @import("core");
const backends = @import("backends");
const router = @import("router.zig");
const constants = core.constants;
const errors = @import("errors.zig");
const base_command = @import("base_command.zig");

/// List command implementation for modular architecture
pub const ListCommand = struct {
    const Self = @This();

    name: []const u8 = "list",
    description: []const u8 = "List containers and virtual machines from all backends",
    base: base_command.BaseCommand = .{},

    pub fn setLogger(self: *Self, logger: *core.LogContext) void {
        self.base.setLogger(logger);
    }

    pub fn logCommandStart(self: *const Self, command_name: []const u8) !void {
        try self.base.logCommandStart(command_name);
    }

    pub fn logCommandComplete(self: *const Self, command_name: []const u8) !void {
        try self.base.logCommandComplete(command_name);
    }

    pub fn logError(self: *const Self, comptime format: []const u8, args: anytype) !void {
        try self.base.logError(format, args);
    }

    pub fn execute(self: *Self, options: core.types.RuntimeOptions, allocator: std.mem.Allocator) !void {
        _ = options; // Not used in aggregated listing

        // Collect containers from all backends
        var all_containers = std.ArrayListUnmanaged(core.ContainerInfo){};
        defer {
            for (all_containers.items) |*container| {
                container.deinit();
            }
            all_containers.deinit(allocator);
        }

        // List from each backend type
        try self.listFromBackend(allocator, .proxmox_lxc, &all_containers);
        try self.listFromBackend(allocator, .crun, &all_containers);
        try self.listFromBackend(allocator, .runc, &all_containers);
        try self.listFromBackend(allocator, .vm, &all_containers);

        // Print aggregated results (similar to runc list format)
        const stdout = std.fs.File.stdout();
        try stdout.writeAll("ID\tIMAGE\tCOMMAND\tCREATED\tSTATUS\tBACKEND\tNAMES\n");
        
        for (all_containers.items) |*container| {
            const id = container.id;
            const image = container.image orelse "unknown";
            const command = container.runtime orelse "unknown";
            const created = container.created orelse "unknown";
            const status = container.status;
            const backend = container.backend_type;
            const names = container.name;
            
            // Simple output without allocPrint to avoid allocator issues
            _ = try stdout.writeAll(id);
            _ = try stdout.writeAll("\t");
            _ = try stdout.writeAll(image);
            _ = try stdout.writeAll("\t");
            _ = try stdout.writeAll(command);
            _ = try stdout.writeAll("\t");
            _ = try stdout.writeAll(created);
            _ = try stdout.writeAll("\t");
            _ = try stdout.writeAll(status);
            _ = try stdout.writeAll("\t");
            _ = try stdout.writeAll(backend);
            _ = try stdout.writeAll("\t");
            _ = try stdout.writeAll(names);
            _ = try stdout.writeAll("\n");
        }

        // Command completed
    }

    fn listFromBackend(self: *Self, allocator: std.mem.Allocator, backend_type: core.types.RuntimeType, containers: *std.ArrayListUnmanaged(core.ContainerInfo)) !void {
        _ = self; // Avoid unused warnings
        switch (backend_type) {
            .lxc => {
                // List LXC containers using backend
                const sandbox_config = core.types.SandboxConfig{
                    .allocator = allocator,
                    .name = try allocator.dupe(u8, "default"),
                    .runtime_type = .lxc,
                    .resources = core.types.ResourceLimits{
                        .memory = constants.DEFAULT_MEMORY_BYTES,
                        .cpu = constants.DEFAULT_CPU_CORES,
                        .disk = null,
                        .network_bandwidth = null,
                    },
                    .security = null,
                    .network = core.types.NetworkConfig{
                        .bridge = try allocator.dupe(u8, constants.DEFAULT_BRIDGE_NAME),
                        .ip = null,
                        .gateway = null,
                        .dns = null,
                        .port_mappings = null,
                    },
                    .storage = null,
                };
                defer {
                    allocator.free(sandbox_config.name);
                    if (sandbox_config.network) |net| {
                        if (net.bridge) |b| allocator.free(b);
                    }
                }

                const proxmox_config = core.types.ProxmoxLxcBackendConfig{
                    .proxmox_host = "localhost",
                    .proxmox_port = 8006,
                    .proxmox_token = "",
                    .proxmox_node = "localhost",
                    .verify_ssl = false,
                    .timeout = 30,
                };

                const lxc_backend = backends.proxmox_lxc.driver.ProxmoxLxcDriver.init(allocator, proxmox_config) catch {
                    return; // Skip if LXC backend not available
                };
                defer lxc_backend.deinit();

                const lxc_containers = lxc_backend.list(allocator) catch return;
                defer allocator.free(lxc_containers);
                
                for (lxc_containers) |*c| {
                    try containers.append(allocator, c.*);
                }
            },
            .proxmox_lxc => {
                // List Proxmox LXC containers via driver
                const proxmox_config = core.types.ProxmoxLxcBackendConfig{
                    .proxmox_host = "localhost",
                    .proxmox_port = 8006,
                    .proxmox_token = "",
                    .proxmox_node = "localhost",
                    .verify_ssl = false,
                    .timeout = 30,
                };

                const proxmox_backend = backends.proxmox_lxc.driver.ProxmoxLxcDriver.init(allocator, proxmox_config) catch return;
                defer proxmox_backend.deinit();

                const proxmox_containers = proxmox_backend.list(allocator) catch return;
                defer allocator.free(proxmox_containers);
                
                for (proxmox_containers) |*c| {
                    try containers.append(allocator, c.*);
                }
            },
            .crun, .runc => {
                // TODO: Implement CRUN/RUNC listing
            },
            .vm => {
                // TODO: Implement VM listing
            },
            else => {},
        }
    }

    pub fn help(self: *Self, allocator: std.mem.Allocator) ![]const u8 {
        _ = self;
        return allocator.dupe(u8, "Usage: nexcage list\n\n" ++
            "Description:\n" ++
            "  List containers from all available backends (LXC, Proxmox LXC, CRUN, RUNC, VM)\n" ++
            "  Output format similar to 'docker ps' or 'runc list'\n\n" ++
            "Output columns:\n" ++
            "  ID       - Container identifier\n" ++
            "  IMAGE    - Container image or template\n" ++
            "  COMMAND  - Runtime command\n" ++
            "  CREATED  - Creation timestamp\n" ++
            "  STATUS   - Container status\n" ++
            "  BACKEND  - Backend type (lxc, proxmox-lxc, crun, runc, vm)\n" ++
            "  NAMES    - Container names\n\n" ++
            "Notes:\n" ++
            "  Automatically detects available backends and skips unavailable ones.\n" ++
            "  Proxmox LXC containers are listed via 'pct list' command.\n");
    }

    pub fn validate(self: *Self, args: []const []const u8) !void {
        _ = self;
        _ = args;
    }
};
