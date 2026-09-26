const std = @import("std");
const core = @import("core");
const backends = @import("backends");
const validation = @import("validation.zig");
const types = core.types;
const config_module = core.config;
const base_command = @import("base_command.zig");

/// `ps`: the host PIDs of the processes in a container.
///
/// Kubernetes asks for it. Recorded on a node under k3s, the kubelet's
/// containerd sends `ps --format json <id>` for the task's PID list, and until
/// now got `unknown command 'ps'`. containerd swallows that without a word in
/// the journal and the pod runs anyway, so nothing but the runtime's own
/// command lines showed it was being asked at all.
///
/// The output is crun's, field for field: a JSON array of numbers, or a `PID`
/// header and one number per line. Neither is runc's table, which runs the
/// host's `ps -ef` and filters it by those PIDs — crun does not, and matching
/// the library that answers the question keeps the two from drifting.
pub const PsCommand = struct {
    const Self = @This();

    name: []const u8 = "ps",
    description: []const u8 = "List the host PIDs of the processes in a container",
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

        const container_id = try validation.ValidationUtils.requireContainerId(options, self.base.logger, "ps");

        const format = options.format orelse "table";
        const as_json = std.mem.eql(u8, format, "json");
        if (!as_json and !std.mem.eql(u8, format, "table")) {
            if (self.base.logger) |log| {
                log.err("--format takes json or table, got '{s}'", .{format}) catch {};
            }
            return types.Error.InvalidInput;
        }

        // --runtime wins; otherwise the routing rules, with the container's own
        // name as the key, the way every other command resolves it.
        var runtime_type: types.RuntimeType = .proxmox_lxc;
        if (options.runtime_type) |rt| {
            runtime_type = rt;
        } else {
            var config_loader = config_module.ConfigLoader.init(allocator);
            var cfg = try config_loader.loadDefault();
            defer cfg.deinit();
            runtime_type = cfg.getRoutedRuntime(container_id);
        }

        if (runtime_type != .crun) {
            // `pct` has no equivalent, and the two questions are not the same
            // one: `runc ps` reports host PIDs, while `pct exec <id> ps` reports
            // what the container sees in its own namespace. Answering with the
            // second would look like an answer and mean something else.
            if (self.base.logger) |log| {
                log.err(
                    "ps is not available on the {s} backend: it reports the host PIDs in a container's cgroup, and `pct exec {s} ps` answers a different question — the PIDs inside the container's own namespace. Use --runtime crun",
                    .{ @tagName(runtime_type), container_id },
                ) catch {};
            }
            return types.Error.UnsupportedOperation;
        }

        if (!backends.isCrunEnabled()) {
            if (self.base.logger) |log| {
                log.err("The crun backend is not built into this binary; rebuild with -Denable-backend-crun=true", .{}) catch {};
            }
            return types.Error.UnsupportedOperation;
        }

        var crun_backend = backends.crun.CrunDriver.init(allocator, self.base.logger);
        defer crun_backend.deinit();

        const list = try crun_backend.pids(container_id, allocator);
        defer allocator.free(list);

        var out = std.ArrayListUnmanaged(u8){};
        defer out.deinit(allocator);
        const w = out.writer(allocator);

        if (as_json) {
            try w.writeAll("[\n");
            for (list, 0..) |pid, i| {
                try w.print("  {d}{s}\n", .{ pid, if (i + 1 < list.len) "," else "" });
            }
            try w.writeAll("]\n");
        } else {
            try w.writeAll("PID\n");
            for (list) |pid| try w.print("{d}\n", .{pid});
        }

        try stdout.writeAll(out.items);
    }

    pub fn help(self: *Self, allocator: std.mem.Allocator) ![]const u8 {
        _ = self;
        return allocator.dupe(u8, "Usage: nexcage ps [--format json|table] <container-name>\n\n" ++
            "The host PIDs of the processes in the container's cgroup, children\n" ++
            "included. This is what Kubernetes asks for: the kubelet's containerd\n" ++
            "sends 'ps --format json <id>' to list a task's processes.\n\n" ++
            "Options:\n" ++
            "  --format json    A JSON array of PIDs\n" ++
            "  --format table   A PID header and one per line (the default)\n" ++
            "  -h, --help       Show this help message\n\n" ++
            "The output is crun's own shape. runc's table runs the host's 'ps -ef'\n" ++
            "and filters it; crun prints the numbers, and so does this.\n\n" ++
            "Answered by the crun backend only. On Proxmox LXC it is refused\n" ++
            "rather than answered with something else: 'pct exec <id> ps' reports\n" ++
            "the PIDs the container sees in its own namespace, which is a\n" ++
            "different set of numbers for a different question.\n\n" ++
            "Examples:\n" ++
            "  nexcage --runtime crun ps --format json abc123\n" ++
            "  nexcage --runtime crun ps abc123\n");
    }

    pub fn validate(self: *Self, args: []const []const u8) !void {
        _ = self;
        try validation.ValidationUtils.requireNonEmptyArgs(args);
    }
};
