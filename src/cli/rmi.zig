const std = @import("std");
const core = @import("core");
const backends = @import("backends");
const types = core.types;
const base_command = @import("base_command.zig");

/// `rmi`: remove a container template from the storage it is on.
///
/// The counterpart to `pull`. A template is a file on a Proxmox storage, and the
/// volid names its own storage, so there is nothing to guess about where it
/// lives — only which node to ask, and that matters: `local` is a different
/// directory on every node.
///
/// Two things are established before anything is deleted, because a removal that
/// reports success without removing anything is the worst answer this command
/// can give. That the template is there at all — a mistyped volid is an error
/// rather than a no-op — and whether the storage is shared, because on a shared
/// storage the file goes for every node at once and that is said plainly.
pub const RmiCommand = struct {
    const Self = @This();

    name: []const u8 = "rmi",
    description: []const u8 = "Remove a container template from a Proxmox storage",
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

        // The volid arrives where an image does, as `pull` prints it.
        const volid = options.image orelse options.container_id orelse {
            if (self.base.logger) |log| {
                log.err("rmi needs a template, as `images` lists it: nexcage rmi local:vztmpl/redis_7.tar", .{}) catch {};
            }
            return types.Error.InvalidInput;
        };

        if (options.runtime_type) |rt| {
            if (rt != .proxmox_lxc and rt != .lxc) {
                if (self.base.logger) |log| {
                    log.err("rmi removes a Proxmox template; the {s} backend takes a bundle whose rootfs is already there", .{@tagName(rt)}) catch {};
                }
                return types.Error.UnsupportedOperation;
            }
        }

        const proxmox_config = types.ProxmoxLxcBackendConfig{ .allocator = allocator };
        const backend = try backends.proxmox_lxc.driver.ProxmoxLxcDriver.init(allocator, proxmox_config);
        defer backend.deinit();
        if (self.base.logger) |log| backend.setLogger(log);

        const node = if (options.node) |n| try allocator.dupe(u8, n) else try backend.nodeName();
        defer allocator.free(node);

        const was_shared = try backend.removeTemplate(allocator, node, volid);

        var out = std.ArrayListUnmanaged(u8){};
        defer out.deinit(allocator);
        const w = out.writer(allocator);
        if (was_shared) {
            // Not a warning after the fact for its own sake: someone removing a
            // template from one node has reason to know it is gone from all of
            // them, and the node they named had nothing to do with it.
            try w.print("{s} removed from the shared storage; it is gone from every node\n", .{volid});
        } else {
            try w.print("{s} removed from {s}\n", .{ volid, node });
        }
        try stdout.writeAll(out.items);
    }

    pub fn help(self: *Self, allocator: std.mem.Allocator) ![]const u8 {
        _ = self;
        return allocator.dupe(u8, "Usage: nexcage rmi <template> [--node <name>]\n\n" ++
            "Remove a container template from the storage it is on. The template is\n" ++
            "named the way `images` lists it and `pull` prints it, as\n" ++
            "<storage>:vztmpl/<file>.\n\n" ++
            "Options:\n" ++
            "  --node <name>   The node to remove it from (default: this host)\n" ++
            "  -h, --help      Show this help message\n\n" ++
            "The node matters: a storage called `local` is a different directory on\n" ++
            "every node. On a storage that is shared, the file is gone from every\n" ++
            "node at once, and the output says so.\n\n" ++
            "A template that is not there is an error, not a no-op: a mistyped\n" ++
            "volid should not look like a successful removal.\n\n" ++
            "Removing a template does not affect containers created from it. A\n" ++
            "template is copied when a container is made, not referenced.\n\n" ++
            "Examples:\n" ++
            "  nexcage rmi local:vztmpl/redis_7.tar\n" ++
            "  nexcage rmi shared-rdma:vztmpl/redis_7.tar --node titan\n");
    }

    pub fn validate(self: *Self, args: []const []const u8) !void {
        _ = self;
        if (args.len == 0) return types.Error.InvalidInput;
    }
};
