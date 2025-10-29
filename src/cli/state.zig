const std = @import("std");
const core = @import("core");
const backends = @import("backends");
const validation = @import("validation.zig");
const types = core.types;
const config_module = core.config;
const base_command = @import("base_command.zig");

/// OCI-compatible state command implementation
/// Prints container state in an OCI-like JSON object
pub const StateCommand = struct {
    const Self = @This();

    name: []const u8 = "state",
    description: []const u8 = "Show container state in OCI-compatible format",
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

    pub fn execute(self: *Self, options: types.RuntimeOptions, allocator: std.mem.Allocator) !void {
        try self.logCommandStart("state");
        const stdout = std.fs.File.stdout();

        // Check for help flag
        if (options.help) {
            const help_text = try self.help(allocator);
            defer allocator.free(help_text);
            try stdout.writeAll(help_text);
            return;
        }

        // Validate required options using validation utility
        const container_id = try validation.ValidationUtils.requireContainerId(options, self.base.logger, "state");

        // Try to determine runtime type from config or default to proxmox_lxc
        var runtime_type: types.RuntimeType = .proxmox_lxc;
        {
            var config_loader = config_module.ConfigLoader.init(allocator);
            var cfg = try config_loader.loadDefault();
            defer cfg.deinit();
            runtime_type = cfg.getRoutedRuntime(container_id);
        }

        if (self.base.logger) |log| {
            try log.info("Routing container '{s}' to runtime: {s}", .{ container_id, @tagName(runtime_type) });
        }

        // Get container info from backend based on runtime type
        const info = try self.getContainerInfo(allocator, runtime_type, container_id);
        defer {
            var mutable_info = info;
            mutable_info.deinit();
        }

        // Map backend status to OCI status values
        const oci_status = try mapStatusToOCI(info.status, allocator);
        defer allocator.free(oci_status);

        // Prepare OCI-compatible state JSON
        const json = try std.fmt.allocPrint(allocator,
            "{{\n  \"ociVersion\": \"1.0.0\",\n  \"id\": \"{s}\",\n  \"status\": \"{s}\",\n  \"pid\": 0,\n  \"bundle\": null,\n  \"annotations\": {{}}\n}}\n",
            .{ info.id, oci_status },
        );
        defer allocator.free(json);

        try stdout.writeAll(json);
        try self.logCommandComplete("state");
    }

    fn getContainerInfo(self: *Self, allocator: std.mem.Allocator, runtime_type: types.RuntimeType, container_id: []const u8) !core.ContainerInfo {
        _ = self;
        switch (runtime_type) {
            .proxmox_lxc, .lxc => {
                const proxmox_config = types.ProxmoxLxcBackendConfig{ .allocator = allocator };
                const backend = backends.proxmox_lxc.driver.ProxmoxLxcDriver.init(allocator, proxmox_config) catch {
                    return types.Error.NotFound;
                };
                defer backend.deinit();

                // Use list() and find the container by ID
                const containers = try backend.list(allocator);
                defer {
                    for (containers) |*c| {
                        c.deinit();
                    }
                    allocator.free(containers);
                }

                // Find container by ID
                for (containers) |*c| {
                    if (std.mem.eql(u8, c.id, container_id)) {
                        // Clone the ContainerInfo for return
                        return core.ContainerInfo{
                            .allocator = allocator,
                            .id = try allocator.dupe(u8, c.id),
                            .name = try allocator.dupe(u8, c.name),
                            .status = try allocator.dupe(u8, c.status),
                            .backend_type = try allocator.dupe(u8, c.backend_type),
                            .created = if (c.created) |created| try allocator.dupe(u8, created) else null,
                            .image = if (c.image) |img| try allocator.dupe(u8, img) else null,
                            .runtime = if (c.runtime) |rt| try allocator.dupe(u8, rt) else null,
                        };
                    }
                }

                return types.Error.NotFound;
            },
            .crun, .runc, .vm => {
                // TODO: Implement info() for crun/runc/vm backends
                // For now, return a minimal ContainerInfo with unknown status
                return core.ContainerInfo{
                    .allocator = allocator,
                    .id = try allocator.dupe(u8, container_id),
                    .name = try allocator.dupe(u8, container_id),
                    .status = try allocator.dupe(u8, "unknown"),
                    .backend_type = try allocator.dupe(u8, @tagName(runtime_type)),
                    .created = null,
                    .image = null,
                    .runtime = null,
                };
            },
            else => {
                return types.Error.UnsupportedOperation;
            },
        }
    }

    pub fn help(self: *Self, allocator: std.mem.Allocator) ![]const u8 {
        _ = self;
        return allocator.dupe(u8, "Usage: nexcage state <container-id>\n\n" ++
            "Show container state in OCI-compatible JSON format.\n\n" ++
            "The output follows OCI runtime state specification:\n" ++
            "  - id: Container identifier\n" ++
            "  - status: OCI status (created|running|stopped|paused)\n" ++
            "  - pid: Process ID (0 if unknown)\n" ++
            "  - bundle: Bundle path (null if unknown)\n" ++
            "  - annotations: OCI annotations (empty object)\n\n" ++
            "Examples:\n" ++
            "  nexcage state 101\n" ++
            "  nexcage state --name 999\n");
    }

    pub fn validate(self: *Self, args: []const []const u8) !void {
        _ = self;
        try validation.ValidationUtils.requireNonEmptyArgs(args);
    }
};

fn mapStatusToOCI(status: []const u8, allocator: std.mem.Allocator) ![]u8 {
    // Basic mapping from backend status strings to OCI { created | running | stopped | paused }
    if (std.mem.eql(u8, status, "running")) return try allocator.dupe(u8, "running");
    if (std.mem.eql(u8, status, "stopped") or std.mem.eql(u8, status, "exited") or std.mem.eql(u8, status, "shutdown"))
        return try allocator.dupe(u8, "stopped");
    if (std.mem.eql(u8, status, "paused")) return try allocator.dupe(u8, "paused");
    if (std.mem.eql(u8, status, "created")) return try allocator.dupe(u8, "created");
    // Fallback
    return try allocator.dupe(u8, "unknown");
}
