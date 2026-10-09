const std = @import("std");
const core = @import("core");
const types = core.types;
const base_command = @import("base_command.zig");
const router = @import("router.zig");
const validation = @import("validation.zig");

/// `update`: change a running container's resource limits, as `runc update`
/// and `crun update` do.
///
/// Two shapes. Value flags named as those two name them (`--memory`,
/// `--cpu-quota`, ...), and `--resources <file>` carrying a runtime-spec
/// `linux.resources` object -- `-` for stdin, which is how containerd sends an
/// in-place resize: `update --resources=- <id>` with the document on stdin.
///
/// The file is read here, once, so both backends see the same thing: libcrun
/// gets the document, which it reads itself; the Proxmox LXC backend gets the
/// settings parsed out of it, since it has to say them to `pct set`.
/// A value flag in the backend's terms: a size with a suffix becomes bytes, as
/// runc accepts them for memory, and every other number has to be one. A typo
/// is a usage error here rather than a backend's complaint. `create` takes the
/// same limits (#308) and reads them the same way.
pub fn normaliseValue(allocator: std.mem.Allocator, logger: ?*core.LogContext, u: types.ResourceUpdate) ![]u8 {
    if (!u.numeric) return allocator.dupe(u8, u.value);
    if (std.mem.eql(u8, u.section, "memory")) {
        const bytes = core.resources.parseSize(u.value) catch {
            if (logger) |log| log.err("'{s}' is not a size: bytes, or a number with K, M or G, or -1 for no limit", .{u.value}) catch {};
            return types.Error.InvalidInput;
        };
        return std.fmt.allocPrint(allocator, "{d}", .{bytes});
    }
    _ = std.fmt.parseInt(i64, u.value, 10) catch {
        if (logger) |log| log.err("'{s}' is not a number, and {s}.{s} takes one", .{ u.value, u.section, u.name }) catch {};
        return types.Error.InvalidInput;
    };
    return allocator.dupe(u8, u.value);
}

pub const UpdateCommand = struct {
    const Self = @This();

    name: []const u8 = "update",
    description: []const u8 = "Change a running container's resource limits",
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

        const container_id = try validation.ValidationUtils.requireContainerId(options, self.base.logger, "update");

        if (options.resources_path != null and options.resource_updates != null) {
            if (self.base.logger) |log| log.err("update takes either --resources <file> or value flags, not both: the file is the whole answer", .{}) catch {};
            return types.Error.InvalidInput;
        }
        if (options.resources_path == null and options.resource_updates == null) {
            if (self.base.logger) |log| log.err("update needs something to change: --memory <size>, --memory-swap <size>, --cpu-quota <us>, --cpu-period <us>, --cpu-share <n>, --pids-limit <n>, ... or --resources <file|->", .{}) catch {};
            return types.Error.InvalidInput;
        }

        var values = std.ArrayListUnmanaged(types.ResourceUpdate){};
        defer {
            for (values.items) |u| allocator.free(u.value);
            values.deinit(allocator);
        }

        var resources_json: ?[]const u8 = null;
        defer if (resources_json) |j| allocator.free(j);

        if (options.resources_path) |path| {
            resources_json = readResources(allocator, path) catch |err| {
                if (self.base.logger) |log| log.err("cannot read the resources from '{s}': {s}", .{ path, @errorName(err) }) catch {};
                return types.Error.InvalidInput;
            };
            core.resources.valuesFromResources(allocator, resources_json.?, &values) catch |err| {
                if (self.base.logger) |log| log.err("'{s}' is not a linux.resources document ({s}); it wants sections such as memory, cpu and pids", .{ path, @errorName(err) }) catch {};
                return types.Error.InvalidInput;
            };
        } else {
            // Sizes with a suffix are accepted for memory, as runc accepts
            // them; every other number has to be one. Checked here, so a
            // typo is a usage error and not a backend's complaint.
            for (options.resource_updates.?) |u| {
                const value = try normaliseValue(allocator, self.base.logger, u);
                errdefer allocator.free(value);
                try values.append(allocator, .{ .section = u.section, .name = u.name, .value = value, .numeric = u.numeric });
            }
        }

        var backend_router = router.BackendRouter.init(allocator, self.base.logger);
        const operation = router.Operation{ .update = router.UpdateConfig{ .resources_json = resources_json, .values = values.items } };
        try backend_router.routeAndExecute(operation, container_id, options.runtime_type, null);
    }

    /// The document from a file, or from stdin for `-`. A resources document
    /// is small; a megabyte is far beyond any real one.
    fn readResources(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
        const limit = 1024 * 1024;
        if (std.mem.eql(u8, path, "-")) {
            return std.fs.File.stdin().readToEndAlloc(allocator, limit);
        }
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();
        return file.readToEndAlloc(allocator, limit);
    }

    pub fn help(self: *Self, allocator: std.mem.Allocator) ![]const u8 {
        _ = self;
        return allocator.dupe(u8, "Usage: nexcage update [options] <container-name>\n" ++
            "       nexcage update --resources <file|-> <container-name>\n\n" ++
            "Change a running container's resource limits, as runc and crun do.\n\n" ++
            "Options, named as runc and crun name them:\n" ++
            "  --memory <size>              Memory limit; bytes, or 512M, 2G, or -1\n" ++
            "  --memory-swap <size>         Memory plus swap, as runc means it\n" ++
            "  --memory-reservation <size>  Soft limit\n" ++
            "  --cpu-quota <us>             CPU quota per period; -1 for no limit\n" ++
            "  --cpu-period <us>            The period (default 100000)\n" ++
            "  --cpu-share <n>              CPU weight, as cgroup v1 shares;\n" ++
            "                               --cpu-shares is accepted too\n" ++
            "  --cpuset-cpus <list>         CPUs the container may use\n" ++
            "  --cpuset-mems <list>         Memory nodes it may use\n" ++
            "  --pids-limit <n>             Maximum number of processes\n" ++
            "  --blkio-weight, --cpu-rt-period, --cpu-rt-runtime,\n" ++
            "  --kernel-memory, --kernel-memory-tcp\n" ++
            "  -r, --resources <file>       A runtime-spec linux.resources document; - is stdin\n" ++
            "  -h, --help                   Show this help message\n\n" ++
            "On the crun backend everything above reaches libcrun. On the Proxmox\n" ++
            "LXC backend only what pct can express is applied -- memory and swap in\n" ++
            "MiB, a CPU limit in cores from quota/period, a CPU weight from shares --\n" ++
            "and the rest is refused by name rather than dropped. A container on\n" ++
            "another node is updated through that node's API.\n\n" ++
            "Examples:\n" ++
            "  nexcage update --memory 1G --memory-swap 2G web-1\n" ++
            "  nexcage update --cpu-quota 50000 --cpu-period 100000 web-1\n" ++
            "  echo '{\"memory\":{\"limit\":536870912}}' | nexcage update --resources - web-1\n");
    }

    pub fn validate(self: *Self, args: []const []const u8) !void {
        _ = self;
        try validation.ValidationUtils.requireNonEmptyArgs(args);
    }
};
