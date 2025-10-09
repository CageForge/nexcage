const std = @import("std");
const core = @import("core");
const backends = @import("backends");
const constants = @import("constants.zig");

pub const BackendRouter = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    logger: ?*core.LogContext,

    pub fn init(allocator: std.mem.Allocator, logger: ?*core.LogContext) Self {
        return Self{
            .allocator = allocator,
            .logger = logger,
        };
    }

    pub fn routeAndExecute(self: *Self, operation: Operation, container_id: []const u8, config: ?Config) !void {
        var config_loader = core.ConfigLoader.init(self.allocator);
        var cfg = try config_loader.loadDefault();
        defer cfg.deinit();

        const ctype = cfg.getContainerType(container_id);
        if (self.logger) |log| {
            try log.info("Selected backend: {s} for container: {s}", .{ @tagName(ctype), container_id });
        }

        switch (ctype) {
            .lxc => try self.executeLxc(operation, container_id, config),
            .crun => try self.executeCrun(operation, container_id, config),
            .runc => try self.executeRunc(operation, container_id, config),
            .vm => try self.executeVm(operation, container_id, config),
        }
    }

    fn executeLxc(self: *Self, operation: Operation, container_id: []const u8, config: ?Config) !void {
        const name_buf = try self.allocator.dupe(u8, container_id);
        defer self.allocator.free(name_buf);

        const sandbox_config = switch (operation) {
            .create => |create_config| core.types.SandboxConfig{
                .allocator = self.allocator,
                .name = name_buf,
                .runtime_type = .lxc,
                .image = try self.allocator.dupe(u8, create_config.image),
                .resources = core.types.ResourceLimits{
                    .memory = constants.DEFAULT_MEMORY_BYTES,
                    .cpu = constants.DEFAULT_CPU_CORES,
                    .disk = null,
                    .network_bandwidth = null,
                },
                .security = null,
                .network = if (config) |cfg| cfg.network else core.types.NetworkConfig{
                    .bridge = try self.allocator.dupe(u8, constants.DEFAULT_BRIDGE_NAME),
                    .ip = null,
                    .gateway = null,
                    .dns = null,
                    .port_mappings = null,
                },
                .storage = null,
            },
            else => core.types.SandboxConfig{
                .allocator = self.allocator,
                .name = name_buf,
                .runtime_type = .lxc,
                .resources = null,
                .security = null,
                .network = null,
                .storage = null,
            },
        };

        defer {
            if (operation == .create) {
                if (sandbox_config.image) |img| self.allocator.free(img);
                if (sandbox_config.network) |net| {
                    if (net.bridge) |bridge| self.allocator.free(bridge);
                }
            }
        }

        const lxc_backend = try backends.lxc.LxcBackend.init(self.allocator, sandbox_config);
        defer lxc_backend.deinit();

        switch (operation) {
            .create => try lxc_backend.create(sandbox_config),
            .start => try lxc_backend.start(container_id),
            .stop => try lxc_backend.stop(container_id),
            .delete => try lxc_backend.delete(container_id),
            .run => |run_config| {
                const create_sandbox = core.types.SandboxConfig{
                    .allocator = self.allocator,
                    .name = name_buf,
                    .runtime_type = .lxc,
                    .image = try self.allocator.dupe(u8, run_config.image),
                    .resources = null,
                    .security = null,
                    .network = null,
                    .storage = null,
                };
                defer self.allocator.free(create_sandbox.image.?);

                try lxc_backend.create(create_sandbox);
                try lxc_backend.start(container_id);
            },
        }
    }

    fn executeCrun(self: *Self, operation: Operation, container_id: []const u8, config: ?Config) !void {
        _ = config;
        var crun_backend = backends.crun.CrunDriver.init(self.allocator, self.logger);

        switch (operation) {
            .create => |create_config| {
                const name_buf = try self.allocator.dupe(u8, container_id);
                defer self.allocator.free(name_buf);

                const image_buf = try self.allocator.dupe(u8, create_config.image);
                defer self.allocator.free(image_buf);

                const sandbox_config = core.types.SandboxConfig{
                    .allocator = self.allocator,
                    .name = name_buf,
                    .runtime_type = .crun,
                    .image = image_buf,
                    .resources = core.types.ResourceLimits{
                        .memory = constants.DEFAULT_MEMORY_BYTES,
                        .cpu = constants.DEFAULT_CPU_CORES,
                        .disk = null,
                        .network_bandwidth = null,
                    },
                    .security = null,
                    .network = null,
                    .storage = null,
                };

                try crun_backend.create(sandbox_config);
            },
            .start => try crun_backend.start(container_id),
            .stop => try crun_backend.stop(container_id),
            .delete => try crun_backend.delete(container_id),
            .run => {
                if (self.logger) |log| {
                    try log.warn("Crun run operation not implemented", .{});
                }
            },
        }
    }

    fn executeRunc(self: *Self, operation: Operation, container_id: []const u8, config: ?Config) !void {
        _ = config;
        var runc_backend = backends.runc.RuncDriver.init(self.allocator, self.logger);

        switch (operation) {
            .create => |create_config| {
                const name_buf = try self.allocator.dupe(u8, container_id);
                defer self.allocator.free(name_buf);

                const image_buf = try self.allocator.dupe(u8, create_config.image);
                defer self.allocator.free(image_buf);

                const sandbox_config = core.types.SandboxConfig{
                    .allocator = self.allocator,
                    .name = name_buf,
                    .runtime_type = .runc,
                    .image = image_buf,
                    .resources = core.types.ResourceLimits{
                        .memory = constants.DEFAULT_MEMORY_BYTES,
                        .cpu = constants.DEFAULT_CPU_CORES,
                        .disk = null,
                        .network_bandwidth = null,
                    },
                    .security = null,
                    .network = null,
                    .storage = null,
                };

                try runc_backend.create(sandbox_config);
            },
            .start => try runc_backend.start(container_id),
            .stop => try runc_backend.stop(container_id),
            .delete => try runc_backend.delete(container_id),
            .run => {
                if (self.logger) |log| {
                    try log.warn("Runc run operation not implemented", .{});
                }
            },
        }
    }

    fn executeVm(self: *Self, operation: Operation, container_id: []const u8, config: ?Config) !void {
        _ = config;
        _ = container_id;

        switch (operation) {
            .create => |create_config| {
                if (self.logger) |log| {
                    try log.warn("Proxmox VM backend not fully integrated yet. VM creation for image {s} skipped.", .{create_config.image});
                }
            },
            .start, .stop, .delete, .run => {
                if (self.logger) |log| {
                    try log.warn("Proxmox VM backend not fully integrated yet. VM operation skipped.", .{});
                }
            },
        }
    }
};

pub const Operation = union(enum) {
    create: CreateConfig,
    start: void,
    stop: void,
    delete: void,
    run: RunConfig,
};

pub const CreateConfig = struct {
    image: []const u8,
};

pub const RunConfig = struct {
    image: []const u8,
};

pub const Config = struct {
    network: ?core.types.NetworkConfig = null,
    resources: ?core.types.ResourceLimits = null,
};
