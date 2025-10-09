const std = @import("std");
const core = @import("core");
const backends = @import("backends");
const constants = @import("constants.zig");
const errors = @import("errors.zig");
const base_command = @import("base_command.zig");

/// List command implementation for modular architecture
pub const ListCommand = struct {
    const Self = @This();

    name: []const u8 = "list",
    description: []const u8 = "List containers and virtual machines",
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
        try self.logCommandStart("list");

        const runtime_type = options.runtime_type orelse .lxc;

        if (self.base.logger) |log| {
            try log.info("Listing containers with runtime type {}", .{runtime_type});
        }

        // List containers based on runtime type
        switch (runtime_type) {
            .lxc => {
                if (self.base.logger) |log| {
                    try log.info("Listing LXC containers", .{});
                }

                // Minimal sandbox config for backend init
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

                const lxc_backend = try backends.lxc.LxcBackend.init(allocator, sandbox_config);
                defer lxc_backend.deinit();
                if (self.base.logger) |log| lxc_backend.driver.logger = log;

                const containers = lxc_backend.list(allocator) catch |err| {
                    if (err == core.Error.UnsupportedOperation) {
                        if (self.base.logger) |log| try log.warn("LXC tools not available; returning empty list", .{});
                        return;
                    }
                    return err;
                };
                defer allocator.free(containers);
                for (containers) |*c| {
                    if (self.base.logger) |log| try log.info("- {s} ({any})", .{ c.name, c.state });
                    c.deinit();
                }
                return;
            },
            .vm => {
                if (self.base.logger) |log| {
                    try log.info("Listing Proxmox VMs", .{});
                    try log.warn("Proxmox VM backend not implemented yet", .{});
                    try log.info("Alert: Proxmox VM support is planned for v0.5.0", .{});
                }
                return;
            },
            // Proxmox VM branch disabled to avoid duplicate .vm; choose by config in future
            // else => { ... }
            .crun => {
                if (self.base.logger) |log| {
                    try log.info("Listing Crun containers", .{});
                    try log.warn("Crun backend not implemented yet", .{});
                }
                return;
            },
            else => {
                try self.logError("Unsupported runtime type: {}", .{runtime_type});
                return errors.CliError.UnsupportedOperation;
            },
        }

        try self.logCommandComplete("list");
    }

    pub fn help(self: *Self, allocator: std.mem.Allocator) ![]const u8 {
        _ = self;
        return allocator.dupe(u8, "Usage: nexcage list [--runtime <type>]\n\n" ++
            "Options:\n" ++
            "  --runtime <type>   Runtime: lxc|vm|crun (default: lxc)\n\n" ++
            "Notes:\n" ++
            "  If LXC tools are not installed, returns empty list with a warning.\n");
    }

    pub fn validate(self: *Self, args: []const []const u8) !void {
        _ = self;
        _ = args;
    }
};
