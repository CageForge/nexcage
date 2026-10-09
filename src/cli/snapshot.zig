const std = @import("std");
const core = @import("core");
const backends = @import("backends");
const types = core.types;
const config_module = core.config;
const base_command = @import("base_command.zig");
const router = @import("router.zig");
const validation = @import("validation.zig");

/// Snapshots of a container, through Proxmox VE: `snapshot`, `snapshots`,
/// `rollback` and `delsnapshot`, with pct's names.
///
/// Proxmox holds the container's volumes and knows how to snapshot each kind
/// of storage -- a ZFS dataset, an LVM-thin volume, a qcow2 file -- so a
/// snapshot is one `pct` call for a container here and one API call for a
/// container on another node. What nexcage adds is what pct does not do: the
/// container by name, found on any node of the cluster, and one plain line
/// when the storage cannot snapshot at all.
///
/// These are Proxmox verbs, not runtime-spec ones. The crun backend has no
/// storage of its own to snapshot and refuses them, the way the LXC backend
/// refuses `features`. #116, #117, #118 and #163 asked for this through
/// libzfs; the datasets are Proxmox's to make, so it goes through Proxmox.
///
/// A verb's own options may follow the snapshot's name, as they do with pct
/// (`rollback web-1 before --start`): main.zig stops reading flags at the
/// second positional and hands the rest over as `args`, so they are read here.
const Rest = struct {
    description: ?[]const u8 = null,
    start: bool = false,
};

/// The snapshot's name, the first word after the container, and the verb's
/// options after it. `takes` says which options the verb has; anything else
/// after the name is a usage error, not a second name silently ignored.
fn nameAndRest(options: types.RuntimeOptions, logger: ?*core.LogContext, verb: []const u8, takes: Rest) !struct { name: []const u8, rest: Rest } {
    const args = options.args orelse &[_][]const u8{};
    if (args.len == 0) {
        if (logger) |log| log.err("{s} needs the snapshot's name: nexcage {s} <container> <name>", .{ verb, verb }) catch {};
        return types.Error.InvalidInput;
    }
    var rest = Rest{ .description = options.description, .start = options.start_after_rollback };
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const a = args[i];
        if (takes.description != null and std.mem.eql(u8, a, "--description")) {
            if (i + 1 >= args.len) {
                if (logger) |log| log.err("--description needs a value", .{}) catch {};
                return types.Error.InvalidInput;
            }
            rest.description = args[i + 1];
            i += 1;
        } else if (takes.start and std.mem.eql(u8, a, "--start")) {
            rest.start = true;
        } else {
            if (logger) |log| log.err("{s}: unexpected argument '{s}' after the snapshot's name", .{ verb, a }) catch {};
            return types.Error.InvalidInput;
        }
    }
    return .{ .name = args[0], .rest = rest };
}

pub const SnapshotCommand = struct {
    const Self = @This();

    name: []const u8 = "snapshot",
    description: []const u8 = "Take a snapshot of a container, through Proxmox",
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
        if (options.help) {
            const help_text = try self.help(allocator);
            defer allocator.free(help_text);
            try std.fs.File.stdout().writeAll(help_text);
            return;
        }
        const container_id = try validation.ValidationUtils.requireContainerId(options, self.base.logger, "snapshot");
        const parsed = try nameAndRest(options, self.base.logger, "snapshot", .{ .description = "" });

        var backend_router = router.BackendRouter.init(allocator, self.base.logger);
        try backend_router.routeAndExecute(.{ .snapshot = .{ .name = parsed.name, .description = parsed.rest.description } }, container_id, options.runtime_type, null);
    }

    pub fn help(self: *Self, allocator: std.mem.Allocator) ![]const u8 {
        _ = self;
        return allocator.dupe(u8, "Usage: nexcage snapshot <container-name> <snapshot-name> [--description <text>]\n\n" ++
            "Take a snapshot of the container's volumes, through Proxmox: `pct snapshot`\n" ++
            "for a container on this host, the node's API for one elsewhere. The\n" ++
            "storage does the work, so it has to be one that can snapshot -- zfs,\n" ++
            "lvm-thin or qcow2; a raw volume on a directory storage cannot, and the\n" ++
            "command says so.\n\n" ++
            "The name is Proxmox's: letters, digits, '-' and '_', and not 'current'.\n\n" ++
            "Options:\n" ++
            "  --description <text>  A note kept with the snapshot\n" ++
            "  -h, --help            Show this help message\n\n" ++
            "Examples:\n" ++
            "  nexcage snapshot web-1 before-upgrade --description 'before 1.2'\n" ++
            "  nexcage snapshots web-1\n");
    }

    pub fn validate(self: *Self, args: []const []const u8) !void {
        _ = self;
        try validation.ValidationUtils.requireNonEmptyArgs(args);
    }
};

pub const RollbackCommand = struct {
    const Self = @This();

    name: []const u8 = "rollback",
    description: []const u8 = "Roll a container back to a snapshot",
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
        if (options.help) {
            const help_text = try self.help(allocator);
            defer allocator.free(help_text);
            try std.fs.File.stdout().writeAll(help_text);
            return;
        }
        const container_id = try validation.ValidationUtils.requireContainerId(options, self.base.logger, "rollback");
        const parsed = try nameAndRest(options, self.base.logger, "rollback", .{ .start = true });

        var backend_router = router.BackendRouter.init(allocator, self.base.logger);
        try backend_router.routeAndExecute(.{ .rollback = .{ .name = parsed.name, .start = parsed.rest.start } }, container_id, options.runtime_type, null);
    }

    pub fn help(self: *Self, allocator: std.mem.Allocator) ![]const u8 {
        _ = self;
        return allocator.dupe(u8, "Usage: nexcage rollback <container-name> <snapshot-name> [--start]\n\n" ++
            "Roll the container's volumes back to a snapshot, through Proxmox. A\n" ++
            "running container is stopped first -- Proxmox kills it, as pct rollback\n" ++
            "does -- and stays stopped unless --start. Everything written since the\n" ++
            "snapshot is gone afterwards.\n\n" ++
            "Options:\n" ++
            "  --start       Start the container once it is back at the snapshot\n" ++
            "  -h, --help    Show this help message\n\n" ++
            "Examples:\n" ++
            "  nexcage rollback web-1 before-upgrade --start\n");
    }

    pub fn validate(self: *Self, args: []const []const u8) !void {
        _ = self;
        try validation.ValidationUtils.requireNonEmptyArgs(args);
    }
};

pub const DelsnapshotCommand = struct {
    const Self = @This();

    name: []const u8 = "delsnapshot",
    description: []const u8 = "Delete a snapshot of a container",
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
        if (options.help) {
            const help_text = try self.help(allocator);
            defer allocator.free(help_text);
            try std.fs.File.stdout().writeAll(help_text);
            return;
        }
        const container_id = try validation.ValidationUtils.requireContainerId(options, self.base.logger, "delsnapshot");
        const parsed = try nameAndRest(options, self.base.logger, "delsnapshot", .{});

        var backend_router = router.BackendRouter.init(allocator, self.base.logger);
        try backend_router.routeAndExecute(.{ .delsnapshot = .{ .name = parsed.name } }, container_id, options.runtime_type, null);
    }

    pub fn help(self: *Self, allocator: std.mem.Allocator) ![]const u8 {
        _ = self;
        return allocator.dupe(u8, "Usage: nexcage delsnapshot <container-name> <snapshot-name>\n\n" ++
            "Delete a snapshot, through Proxmox. A name that is not there is an\n" ++
            "error (exit 1), as it is for pct.\n\n" ++
            "Options:\n" ++
            "  -h, --help    Show this help message\n\n" ++
            "Examples:\n" ++
            "  nexcage delsnapshot web-1 before-upgrade\n");
    }

    pub fn validate(self: *Self, args: []const []const u8) !void {
        _ = self;
        try validation.ValidationUtils.requireNonEmptyArgs(args);
    }
};

/// `snapshots`: the list. Answered by the command rather than routed, like
/// `state`, because it prints: a table, or `--format json` for a script.
pub const SnapshotsCommand = struct {
    const Self = @This();

    name: []const u8 = "snapshots",
    description: []const u8 = "List a container's snapshots",
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
        const container_id = try validation.ValidationUtils.requireContainerId(options, self.base.logger, "snapshots");
        if (options.args) |extra| if (extra.len > 0) {
            if (self.base.logger) |log| log.err("snapshots: unexpected argument '{s}'; it takes the container and nothing else", .{extra[0]}) catch {};
            return types.Error.InvalidInput;
        };

        const format = options.format orelse "table";
        const as_json = std.mem.eql(u8, format, "json");
        if (!as_json and !std.mem.eql(u8, format, "table")) {
            if (self.base.logger) |log| log.err("--format takes json or table, got '{s}'", .{format}) catch {};
            return types.Error.InvalidInput;
        }

        // The backend that has the container, the way every other command
        // after create resolves it
        const runtime_type = try router.backendOf(container_id, options.runtime_type, self.base.logger);
        switch (runtime_type) {
            .crun => {
                if (self.base.logger) |log| log.err("snapshots is a Proxmox VE operation: the node's storage takes a snapshot of the container's volumes, and the crun backend has no storage of its own to snapshot. It is for containers on the Proxmox LXC backend", .{}) catch {};
                return types.Error.UnsupportedOperation;
            },
            else => {},
        }

        const proxmox_config = types.ProxmoxLxcBackendConfig{ .allocator = allocator };
        const backend = try backends.proxmox_lxc.driver.ProxmoxLxcDriver.init(allocator, proxmox_config);
        defer backend.deinit();
        if (self.base.logger) |log| backend.setLogger(log);

        const list = try backend.listSnapshots(allocator, container_id);
        defer {
            for (list) |*s| s.deinit();
            allocator.free(list);
        }

        var out = std.ArrayListUnmanaged(u8){};
        defer out.deinit(allocator);
        const w = out.writer(allocator);
        var when: [32]u8 = undefined;
        if (as_json) {
            try w.writeAll("[");
            for (list, 0..) |s, i| {
                try w.writeAll(if (i == 0) "\n  {\"name\": " else ",\n  {\"name\": ");
                try core.json.writeString(w, s.name);
                try w.writeAll(", \"created\": ");
                if (s.snaptime) |t| try core.json.writeString(w, backends.proxmox_lxc.pve.formatUtc(&when, t)) else try w.writeAll("null");
                try w.writeAll(", \"description\": ");
                try core.json.writeString(w, s.description);
                try w.writeAll(", \"parent\": ");
                if (s.parent) |p| try core.json.writeString(w, p) else try w.writeAll("null");
                try w.writeAll("}");
            }
            try w.writeAll(if (list.len == 0) "]\n" else "\n]\n");
        } else {
            try w.writeAll("NAME\tCREATED\tDESCRIPTION\n");
            for (list) |s| {
                const created = if (s.snaptime) |t| backends.proxmox_lxc.pve.formatUtc(&when, t) else "";
                try w.print("{s}\t{s}\t{s}\n", .{ s.name, created, s.description });
            }
        }
        try stdout.writeAll(out.items);
    }

    pub fn help(self: *Self, allocator: std.mem.Allocator) ![]const u8 {
        _ = self;
        return allocator.dupe(u8, "Usage: nexcage snapshots [--format json|table] <container-name>\n\n" ++
            "The container's snapshots, oldest first, from its node's API: the name,\n" ++
            "when it was taken (UTC), and the description. The 'current' entry\n" ++
            "Proxmox adds to mark the present state is not a snapshot and is left out.\n\n" ++
            "Options:\n" ++
            "  --format json    A JSON array of {name, created, description, parent}\n" ++
            "  --format table   One per line, tab-separated (the default)\n" ++
            "  -h, --help       Show this help message\n\n" ++
            "Examples:\n" ++
            "  nexcage snapshots web-1\n" ++
            "  nexcage snapshots --format json web-1 | jq -r '.[].name'\n");
    }

    pub fn validate(self: *Self, args: []const []const u8) !void {
        _ = self;
        try validation.ValidationUtils.requireNonEmptyArgs(args);
    }
};
