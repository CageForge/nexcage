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
        const stdout = std.fs.File.stdout();

        if (options.help) {
            const help_text = try self.help(allocator);
            defer allocator.free(help_text);
            try stdout.writeAll(help_text);
            return;
        }

        const container_id = options.container_id orelse {
            try stdout.writeAll("Error: Container ID is required for state command\n");
            return;
        };

        var backend_status: []u8 = try allocator.dupe(u8, "unknown");
        defer allocator.free(backend_status);

        const info = self.getContainerInfo(allocator, container_id) catch null;
        if (info) |ci| {
            defer {
                var m = ci;
                m.deinit();
            }
            allocator.free(backend_status);
            backend_status = try allocator.dupe(u8, ci.status);
        }

        const oci_status = try mapStatusToOCI(backend_status, allocator);
        defer allocator.free(oci_status);

        const json = try std.fmt.allocPrint(
            allocator,
            "{{\n  \"ociVersion\": \"1.0.0\",\n  \"id\": \"{s}\",\n  \"status\": \"{s}\",\n  \"pid\": 0,\n  \"bundle\": null,\n  \"annotations\": {{}}\n}}\n",
            .{ container_id, oci_status },
        );
        defer allocator.free(json);
        try stdout.writeAll(json);
    }

    fn getContainerInfo(self: *Self, allocator: std.mem.Allocator, container_id: []const u8) !core.ContainerInfo {
        _ = self;
        const proxmox_config = types.ProxmoxLxcBackendConfig{ .allocator = allocator };
        const backend = try backends.proxmox_lxc.driver.ProxmoxLxcDriver.init(allocator, proxmox_config);
        defer backend.deinit();

        const containers = try backend.list(allocator);
        defer {
            for (containers) |*c| {
                c.deinit();
            }
            allocator.free(containers);
        }

        for (containers) |*c| {
            if (std.mem.eql(u8, c.id, container_id)) {
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
    }

    pub fn help(self: *Self, allocator: std.mem.Allocator) ![]const u8 {
        _ = self;
        return allocator.dupe(u8, "Usage: nexcage state <container-id>\n");
    }

    pub fn validate(self: *Self, args: []const []const u8) !void {
        _ = self;
        try validation.ValidationUtils.requireNonEmptyArgs(args);
    }
};

fn mapStatusToOCI(status: []const u8, allocator: std.mem.Allocator) ![]u8 {
    if (std.mem.eql(u8, status, "running")) return try allocator.dupe(u8, "running");
    if (std.mem.eql(u8, status, "stopped") or std.mem.eql(u8, status, "exited") or std.mem.eql(u8, status, "shutdown"))
        return try allocator.dupe(u8, "stopped");
    if (std.mem.eql(u8, status, "paused")) return try allocator.dupe(u8, "paused");
    if (std.mem.eql(u8, status, "created")) return try allocator.dupe(u8, "created");
    return try allocator.dupe(u8, "unknown");
}
