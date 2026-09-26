const std = @import("std");
const core = @import("core");
const backends = @import("backends");
const types = core.types;
const base_command = @import("base_command.zig");

/// `images`: the container templates the cluster can create from.
///
/// This backend makes containers from Proxmox templates, and until now the only
/// way to see what was available was `pveam list` or the web UI, per node and
/// per storage. Since a template has to be readable by the node the container
/// is created on -- `create --node` refuses otherwise -- knowing which node has
/// which is the thing a person actually needs.
///
/// A shared storage carries the same files on every node, so it is listed once
/// and marked, rather than once per node: a template counted twice is worse than
/// one not shown.
pub const ImagesCommand = struct {
    const Self = @This();

    name: []const u8 = "images",
    description: []const u8 = "List the container templates the cluster can create from",
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

        // Templates belong to Proxmox storages. The crun backend is handed a
        // bundle that already holds a rootfs, so it has nothing to list.
        if (options.runtime_type) |rt| {
            if (rt != .proxmox_lxc and rt != .lxc) {
                if (self.base.logger) |log| {
                    log.err("images lists Proxmox templates; the {s} backend takes a bundle whose rootfs is already there", .{@tagName(rt)}) catch {};
                }
                return types.Error.UnsupportedOperation;
            }
        }

        const proxmox_config = types.ProxmoxLxcBackendConfig{ .allocator = allocator };
        const backend = try backends.proxmox_lxc.driver.ProxmoxLxcDriver.init(allocator, proxmox_config);
        defer backend.deinit();
        if (self.base.logger) |log| backend.setLogger(log);

        const templates = try backend.listClusterTemplates(allocator, options.node);
        defer {
            for (templates) |*t| t.deinit();
            allocator.free(templates);
        }

        var out = std.ArrayListUnmanaged(u8){};
        defer out.deinit(allocator);
        const w = out.writer(allocator);

        try w.writeAll("NODE\tSTORAGE\tSHARED\tSIZE\tTEMPLATE\n");
        for (templates) |t| {
            try w.print("{s}\t{s}\t{s}\t{s}\t{s}\n", .{
                t.node,
                t.storage,
                if (t.shared) "yes" else "no",
                humanSize(t.size),
                t.volid,
            });
        }
        try stdout.writeAll(out.items);
    }

    /// Sizes here are the hundreds of megabytes a container template runs to, so
    /// bytes would be read wrong at a glance. Rounded down to whole units on
    /// purpose: this is for choosing a template, not for accounting.
    fn humanSize(bytes: u64) []const u8 {
        const S = struct {
            var buf: [32]u8 = undefined;
        };
        const gib = 1024 * 1024 * 1024;
        const mib = 1024 * 1024;
        if (bytes >= gib) {
            return std.fmt.bufPrint(&S.buf, "{d}.{d}G", .{ bytes / gib, (bytes % gib) / (gib / 10) }) catch "?";
        }
        if (bytes >= mib) {
            return std.fmt.bufPrint(&S.buf, "{d}M", .{bytes / mib}) catch "?";
        }
        return std.fmt.bufPrint(&S.buf, "{d}B", .{bytes}) catch "?";
    }

    pub fn help(self: *Self, allocator: std.mem.Allocator) ![]const u8 {
        _ = self;
        return allocator.dupe(u8, "Usage: nexcage images [--node <name>]\n\n" ++
            "The container templates the cluster can create from, with the node\n" ++
            "and storage each one is on. A template has to be readable by the node\n" ++
            "the container is created on, which is what `create --node` checks, so\n" ++
            "this is where to look before placing a container elsewhere.\n\n" ++
            "Options:\n" ++
            "  --node <name>   Only the templates that node can see\n" ++
            "  -h, --help      Show this help message\n\n" ++
            "A storage marked SHARED carries the same files on every node, so it\n" ++
            "is listed once rather than once per node. A template on a shared\n" ++
            "storage is the one to use with `create --node`.\n\n" ++
            "Examples:\n" ++
            "  nexcage images\n" ++
            "  nexcage images --node titan\n" ++
            "  nexcage pull docker.io/library/redis:7 --storage shared-rdma\n");
    }

    pub fn validate(self: *Self, args: []const []const u8) !void {
        _ = self;
        _ = args;
        // images takes no positional arguments
    }
};
