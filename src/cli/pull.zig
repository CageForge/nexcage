const std = @import("std");
const core = @import("core");
const backends = @import("backends");
const types = core.types;
const base_command = @import("base_command.zig");

/// `pull`: fetch an OCI image into a Proxmox storage as a container template.
///
/// `create` already pulls when it is given a registry reference, but only onto
/// this host's `local` storage, and only as part of making a container. Pulling
/// on its own is what makes `create --node` usable: put the template on a
/// storage both nodes can read, and the other node can create from it.
///
///     nexcage pull docker.io/library/redis:7 --storage shared-rdma
///     nexcage create --name r1 --node titan \
///         shared-rdma:vztmpl/docker.io_library_redis_7-a0ed741ac6ba1c57.tar
///
/// nexcage names the file, for the whole reference, and the volid it prints is
/// that exact file once the storage holds it (pve.zig, pullTemplate). Proxmox's
/// own name keeps only the last path component and the tag, which cannot say
/// which registry an image came from.
pub const PullCommand = struct {
    const Self = @This();

    name: []const u8 = "pull",
    description: []const u8 = "Fetch an OCI image into a Proxmox storage as a template",
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

        // The reference arrives where an image does: `pull <ref>`.
        const reference = options.image orelse options.container_id orelse {
            if (self.base.logger) |log| {
                log.err("pull needs an image reference, as in: nexcage pull docker.io/library/redis:7", .{}) catch {};
            }
            return types.Error.InvalidInput;
        };

        if (options.runtime_type) |rt| {
            if (rt != .proxmox_lxc and rt != .lxc) {
                if (self.base.logger) |log| {
                    log.err("pull puts a template on a Proxmox storage; the {s} backend takes a bundle whose rootfs is already there", .{@tagName(rt)}) catch {};
                }
                return types.Error.UnsupportedOperation;
            }
        }

        const proxmox_config = types.ProxmoxLxcBackendConfig{ .allocator = allocator };
        const backend = try backends.proxmox_lxc.driver.ProxmoxLxcDriver.init(allocator, proxmox_config);
        defer backend.deinit();
        if (self.base.logger) |log| backend.setLogger(log);

        // Pulling needs Proxmox VE 9.1 or later; without it the error would
        // arrive as an obscure API failure.
        if (!try backend.supportsOciRegistryPull()) {
            if (self.base.logger) |log| {
                log.err("pulling OCI images needs Proxmox VE 9.1 or later on the target node", .{}) catch {};
            }
            return types.Error.UnsupportedOperation;
        }

        const node = if (options.node) |n| try allocator.dupe(u8, n) else try backend.nodeName();
        defer allocator.free(node);
        const storage = options.storage_name orelse "local";

        const volid = try backend.pullTemplate(allocator, node, storage, reference, options.filename);
        defer allocator.free(volid);

        // The volid on stdout and nothing else: this is what `create` takes, so
        // it has to be usable straight from a shell substitution.
        try stdout.writeAll(volid);
        try stdout.writeAll("\n");
    }

    pub fn help(self: *Self, allocator: std.mem.Allocator) ![]const u8 {
        _ = self;
        return allocator.dupe(u8, "Usage: nexcage pull <image-reference> [--node <name>] [--storage <name>] [--filename <name>]\n\n" ++
            "Fetch an OCI image from a registry into a Proxmox storage, where it\n" ++
            "becomes a container template. Prints the volid, which is what\n" ++
            "`create` takes.\n\n" ++
            "The file is named for the whole reference -- registry, namespace,\n" ++
            "name and tag -- with a digest of it: docker.io/library/redis:7 is\n" ++
            "docker.io_library_redis_7-a0ed741ac6ba1c57.tar. `create` from the\n" ++
            "same reference uses that file and no other. A reference already\n" ++
            "pulled there is not pulled again: remove it with `rmi` first.\n\n" ++
            "Options:\n" ++
            "  --node <name>      The node to pull on (default: this host)\n" ++
            "  --storage <name>   The storage to pull into (default: local)\n" ++
            "  --filename <name>  The file name instead, before the .tar Proxmox adds:\n" ++
            "                     letters, digits, '.', '_' and '-', without '..',\n" ++
            "                     not first a '.' or '-', not last a '.' (the .tar\n" ++
            "                     would make it '..', which rmi refuses), at most 127\n" ++
            "                     characters, not ending in '-' and 16 hex digits as\n" ++
            "                     a derived name does. It must not be there already\n" ++
            "  -h, --help         Show this help message\n\n" ++
            "This is how to make `create --node` work: a storage called `local` is\n" ++
            "a different directory on every node, so pull onto a shared storage and\n" ++
            "the other node can read the template.\n\n" ++
            "  volid=$(nexcage pull docker.io/library/redis:7 --storage shared-rdma)\n" ++
            "  nexcage create --name r1 --node titan \"$volid\"\n\n" ++
            "Needs Proxmox VE 9.1 or later, which is where oci-registry-pull\n" ++
            "arrived. For a private registry, log in as root on the node that\n" ++
            "pulls, into the file Proxmox's pull reads:\n\n" ++
            "  skopeo login --authfile /root/.config/containers/auth.json <registry>\n\n" ++
            "Examples:\n" ++
            "  nexcage pull docker.io/library/alpine:3.20\n" ++
            "  nexcage pull docker.io/library/redis:7 --node titan --storage shared-rdma\n");
    }

    pub fn validate(self: *Self, args: []const []const u8) !void {
        _ = self;
        if (args.len == 0) return types.Error.InvalidInput;
    }
};
