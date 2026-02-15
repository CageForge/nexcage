const std = @import("std");
const core = @import("core");
const backends = @import("backends");
const constants = core.constants;
const base_command = @import("base_command.zig");

/// List command implementation for modular architecture
pub const ListCommand = struct {
    const Self = @This();

    name: []const u8 = "list",
    description: []const u8 = "List containers from Proxmox LXC backend",
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

    pub fn showHelp(self: *const Self) !void {
        _ = self;
        const stdout = std.fs.File.stdout();
        try stdout.writeAll("Usage: nexcage list [OPTIONS]\n\n");
        try stdout.writeAll("List containers from Proxmox LXC backend\n\n");
        try stdout.writeAll("OPTIONS:\n");
        try stdout.writeAll("  --help, -h    Show this help message\n");
        try stdout.writeAll("  --debug       Enable debug logging\n");
    }

    pub fn execute(self: *Self, options: core.types.RuntimeOptions, allocator: std.mem.Allocator) !void {
        if (options.help) {
            try self.showHelp();
            return;
        }

        var all_containers = std.ArrayListUnmanaged(core.ContainerInfo){};
        defer {
            for (all_containers.items) |*container| {
                container.deinit();
            }
            all_containers.deinit(allocator);
        }

        try self.listFromBackend(allocator, &all_containers);

        const stdout = std.fs.File.stdout();
        try stdout.writeAll("ID\tIMAGE\tSTATUS\tBACKEND\tNAMES\n");

        for (all_containers.items) |*container| {
            _ = try stdout.writeAll(container.id);
            _ = try stdout.writeAll("\t");
            _ = try stdout.writeAll(container.image orelse "unknown");
            _ = try stdout.writeAll("\t");
            _ = try stdout.writeAll(container.status);
            _ = try stdout.writeAll("\t");
            _ = try stdout.writeAll(container.backend_type);
            _ = try stdout.writeAll("\t");
            _ = try stdout.writeAll(container.name);
            _ = try stdout.writeAll("\n");
        }
    }

    fn listFromBackend(self: *Self, allocator: std.mem.Allocator, containers: *std.ArrayListUnmanaged(core.ContainerInfo)) !void {
        _ = self;
        const proxmox_config = core.types.ProxmoxLxcBackendConfig{ .allocator = allocator };
        const proxmox_backend = try backends.proxmox_lxc.driver.ProxmoxLxcDriver.init(allocator, proxmox_config);
        defer proxmox_backend.deinit();

        const proxmox_containers = try proxmox_backend.list(allocator);
        defer allocator.free(proxmox_containers);

        for (proxmox_containers) |*c| {
            try containers.append(allocator, c.*);
        }
    }

    pub fn help(self: *Self, allocator: std.mem.Allocator) ![]const u8 {
        _ = self;
        return allocator.dupe(u8, "Usage: nexcage list\n");
    }

    pub fn validate(self: *Self, args: []const []const u8) !void {
        _ = self;
        _ = args;
    }
};
