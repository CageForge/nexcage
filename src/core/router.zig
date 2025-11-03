const std = @import("std");
// Remove circular import - use direct imports instead
const backends = @import("backends");
const constants = @import("constants.zig");
const types = @import("types.zig");
const logging = @import("logging.zig");
const config_module = @import("config.zig");

pub const BackendRouter = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    logger: ?*logging.LogContext,

    pub fn init(allocator: std.mem.Allocator, logger: ?*logging.LogContext) Self {
        return Self{
            .allocator = allocator,
            .logger = logger,
        };
    }

    /// Creates a SandboxConfig for the given operation and runtime type
    fn createSandboxConfig(
        self: *Self,
        operation: Operation,
        container_id: []const u8,
        runtime_type: types.RuntimeType,
        config: ?Config,
    ) !types.SandboxConfig {
        const name_buf = try self.allocator.dupe(u8, container_id);
        errdefer self.allocator.free(name_buf);

        return switch (operation) {
            .create => |create_config| blk: {
                const image_buf = try self.allocator.dupe(u8, create_config.image);
                errdefer self.allocator.free(image_buf);
                
                const network_config: ?types.NetworkConfig = if (config) |cfg| cfg.network else switch (runtime_type) {
                    .lxc => blk2: {
                        const bridge_buf = try self.allocator.dupe(u8, constants.DEFAULT_BRIDGE_NAME);
                        errdefer self.allocator.free(bridge_buf);
                        break :blk2 types.NetworkConfig{
                            .bridge = bridge_buf,
                            .ip = null,
                            .gateway = null,
                            .dns = null,
                            .port_mappings = null,
                        };
                    },
                    else => null,
                };
                errdefer if (network_config) |net| {
                    if (net.bridge) |bridge| self.allocator.free(bridge);
                };
                
                break :blk types.SandboxConfig{
                    .allocator = self.allocator,
                    .name = name_buf,
                    .runtime_type = runtime_type,
                    .image = image_buf,
                    .resources = types.ResourceLimits{
                        .memory = constants.DEFAULT_MEMORY_BYTES,
                        .cpu = constants.DEFAULT_CPU_CORES,
                        .disk = null,
                        .network_bandwidth = null,
                    },
                    .security = null,
                    .network = network_config,
                    .storage = null,
                };
            },
            .run => |run_config| blk: {
                const image_buf = try self.allocator.dupe(u8, run_config.image);
                errdefer self.allocator.free(image_buf);
                
                break :blk types.SandboxConfig{
                    .allocator = self.allocator,
                    .name = name_buf,
                    .runtime_type = runtime_type,
                    .image = image_buf,
                    .resources = null,
                    .security = null,
                    .network = null,
                    .storage = null,
                };
            },
            else => types.SandboxConfig{
                .allocator = self.allocator,
                .name = name_buf,
                .runtime_type = runtime_type,
                .resources = null,
                .security = null,
                .network = null,
                .storage = null,
            },
        };
    }

    /// Cleanup allocated resources in SandboxConfig
    fn cleanupSandboxConfig(self: *Self, operation: Operation, sandbox_config: *const types.SandboxConfig) void {
        switch (operation) {
            .create, .run => {
                if (sandbox_config.image) |img| self.allocator.free(img);
                if (sandbox_config.network) |net| {
                    if (net.bridge) |bridge| self.allocator.free(bridge);
                }
            },
            else => {},
        }
        self.allocator.free(sandbox_config.name);
    }

    pub fn routeAndExecute(self: *Self, operation: Operation, container_id: []const u8, config: ?Config) !void {
        var config_loader = config_module.ConfigLoader.init(self.allocator);
        var cfg = try config_loader.loadDefault();
        defer cfg.deinit();

        // Use the new routing system that supports regex patterns
        const runtime_type = cfg.getRoutedRuntime(container_id);
        if (self.logger) |log| {
            try log.info("Routing container '{s}' to runtime: {s}", .{ container_id, @tagName(runtime_type) });
        }

        // Convert RuntimeType to ContainerType for backend execution
        const ctype = switch (runtime_type) {
            .lxc => types.ContainerType.lxc,
            .crun => types.ContainerType.crun,
            .runc => types.ContainerType.runc,
            .vm => types.ContainerType.vm,
            else => types.ContainerType.lxc, // fallback
        };

        if (self.logger) |log| {
            try log.info("Executing with backend: {s} for container: {s}", .{ @tagName(ctype), container_id });
        }

        switch (ctype) {
            .lxc => try self.executeLxc(operation, container_id, config),
            .crun => try self.executeCrun(operation, container_id, config),
            .runc => try self.executeRunc(operation, container_id, config),
            .vm => try self.executeVm(operation, container_id, config),
        }
    }

    fn executeLxc(self: *Self, operation: Operation, container_id: []const u8, config: ?Config) !void {
        const sandbox_config = try self.createSandboxConfig(operation, container_id, .lxc, config);
        defer self.cleanupSandboxConfig(operation, &sandbox_config);

        const lxc_backend = try backends.lxc.LxcBackend.init(self.allocator, sandbox_config);
        defer lxc_backend.deinit();

        switch (operation) {
            .create => try lxc_backend.create(sandbox_config),
            .start => try lxc_backend.start(container_id),
            .stop => try lxc_backend.stop(container_id),
            .delete => try lxc_backend.delete(container_id),
            .run => {
                try lxc_backend.create(sandbox_config);
                try lxc_backend.start(container_id);
            },
        }
    }

    fn executeCrun(self: *Self, operation: Operation, container_id: []const u8, config: ?Config) !void {
        var crun_backend = backends.crun.CrunDriver.init(self.allocator, self.logger);
        defer crun_backend.deinit();

        switch (operation) {
            .create => {
                const sandbox_config = try self.createSandboxConfig(operation, container_id, .crun, config);
                defer self.cleanupSandboxConfig(operation, &sandbox_config);
                try crun_backend.create(sandbox_config);
            },
            .start => try crun_backend.start(container_id),
            .stop => try crun_backend.stop(container_id),
            .delete => try crun_backend.delete(container_id),
            .run => |run_cfg| {
                const sandbox_config = try self.createSandboxConfig(operation, container_id, .crun, config);
                defer self.cleanupSandboxConfig(operation, &sandbox_config);
                _ = run_cfg; // image already applied by createSandboxConfig
                try crun_backend.run(sandbox_config);
            },
        }
    }

    fn executeRunc(self: *Self, operation: Operation, container_id: []const u8, config: ?Config) !void {
        var runc_backend = backends.runc.RuncDriver.init(self.allocator, self.logger);

        switch (operation) {
            .create => {
                const sandbox_config = try self.createSandboxConfig(operation, container_id, .runc, config);
                defer self.cleanupSandboxConfig(operation, &sandbox_config);
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
    network: ?types.NetworkConfig = null,
    resources: ?types.ResourceLimits = null,
};
