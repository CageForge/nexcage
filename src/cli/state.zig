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

        // Check for help flag
        if (options.help) {
            const help_text = try self.help(allocator);
            defer allocator.free(help_text);
            try stdout.writeAll(help_text);
            return;
        }

        const container_id = try validation.ValidationUtils.requireContainerId(options, self.base.logger, "state");

        // --runtime wins; otherwise the routing rules in the config file
        var runtime_type: types.RuntimeType = .proxmox_lxc;
        if (options.runtime_type) |rt| {
            runtime_type = rt;
        } else {
            var config_loader = config_module.ConfigLoader.init(allocator);
            var cfg = try config_loader.loadDefault();
            defer cfg.deinit();
            runtime_type = cfg.getRoutedRuntime(container_id);
        }

        // crun prints its own state: libcrun writes the JSON the spec defines,
        // so what comes out is what `crun state` would give. Composing a
        // second rendering of the same fields here would only be a thing that
        // can drift from it.
        if (runtime_type == .crun) {
            if (!backends.isCrunEnabled()) {
                if (self.base.logger) |log| log.err("The crun backend is not built into this binary; rebuild with -Denable-backend-crun=true", .{}) catch {};
                return types.Error.UnsupportedOperation;
            }
            var crun_backend = backends.crun.CrunDriver.init(allocator, self.base.logger);
            defer crun_backend.deinit();
            return crun_backend.state(container_id);
        }

        // The OCI runtime spec makes querying a container that does not exist
        // an error. This used to print "status": "unknown" and exit 0, which a
        // caller cannot tell apart from a real container in an odd state.
        var found = self.findContainer(allocator, runtime_type, container_id) catch |err| {
            if (err == types.Error.NotFound) {
                if (self.base.logger) |log| log.err("Container '{s}' not found", .{container_id}) catch {};
            }
            return err;
        };
        defer found.info.deinit();

        var status = ociStatus(found.info.status);
        // pct calls a container that has never run "stopped"
        if (std.mem.eql(u8, status, "stopped") and neverStarted(allocator, found.info.name)) status = "created";

        // The bundle a container was created from, as nexcage recorded it. An
        // OCI caller reads this back to find the config.json it handed over.
        const bundle_path = persistedBundle(allocator, found.info.name);
        defer if (bundle_path) |bp| allocator.free(bp);

        var out = std.ArrayListUnmanaged(u8){};
        defer out.deinit(allocator);
        const writer = out.writer(allocator);
        try writer.print(
            "{{\n  \"ociVersion\": \"1.0.0\",\n  \"id\": \"{s}\",\n  \"status\": \"{s}\",\n  \"pid\": {d},\n  \"bundle\": ",
            .{ container_id, status, found.pid },
        );
        if (bundle_path) |bp| {
            try core.json.writeString(writer, bp);
        } else {
            try writer.writeAll("null");
        }
        try writer.writeAll(",\n  \"annotations\": {}\n}\n");
        try stdout.writeAll(out.items);
    }

    const Found = struct {
        info: core.ContainerInfo,
        /// Host PID of the container's init while it runs, 0 otherwise
        pid: std.posix.pid_t = 0,
    };

    fn findContainer(self: *Self, allocator: std.mem.Allocator, runtime_type: types.RuntimeType, container_id: []const u8) !Found {
        switch (runtime_type) {
            .proxmox_lxc, .lxc => {
                const proxmox_config = types.ProxmoxLxcBackendConfig{ .allocator = allocator };
                const backend = backends.proxmox_lxc.driver.ProxmoxLxcDriver.init(allocator, proxmox_config) catch {
                    return types.Error.NotFound;
                };
                defer backend.deinit();
                if (self.base.logger) |log| backend.setLogger(log);

                const containers = try backend.list(allocator);
                defer {
                    for (containers) |*c| {
                        c.deinit();
                    }
                    allocator.free(containers);
                }

                // Containers are addressed by name everywhere else (create
                // sets the hostname, start/stop/delete resolve it), so match
                // the name first; a bare VMID is accepted as well.
                for (containers) |*c| {
                    if (std.mem.eql(u8, c.name, container_id) or std.mem.eql(u8, c.id, container_id)) {
                        // OCI state requires the PID while the container
                        // runs; it used to be 0 always.
                        const pid = if (std.mem.eql(u8, c.status, "running"))
                            (backend.initPid(c.id) catch null) orelse 0
                        else
                            0;
                        return .{
                            .info = core.ContainerInfo{
                                .allocator = allocator,
                                .id = try allocator.dupe(u8, c.id),
                                .name = try allocator.dupe(u8, c.name),
                                .status = try allocator.dupe(u8, c.status),
                                .backend_type = try allocator.dupe(u8, c.backend_type),
                                .created = if (c.created) |created| try allocator.dupe(u8, created) else null,
                                .image = if (c.image) |img| try allocator.dupe(u8, img) else null,
                                .runtime = if (c.runtime) |rt| try allocator.dupe(u8, rt) else null,
                            },
                            .pid = pid,
                        };
                    }
                }

                return types.Error.NotFound;
            },
            .crun, .runc, .vm => {
                // crun is handled above, by libcrun itself. runc and the VM
                // backend cannot report state. This used to print a made-up
                // "unknown" state and exit 0, which looks like a real
                // container.
                if (self.base.logger) |log| log.err("state is not implemented for the {s} backend", .{@tagName(runtime_type)}) catch {};
                return types.Error.UnsupportedOperation;
            },
            else => {
                return types.Error.UnsupportedOperation;
            },
        }
    }

    pub fn help(self: *Self, allocator: std.mem.Allocator) ![]const u8 {
        _ = self;
        return allocator.dupe(u8, "Usage: nexcage state <container-name>\n\n" ++
            "Show container state in OCI-compatible JSON format.\n" ++
            "Exits with an error if the container does not exist.\n\n" ++
            "The output follows OCI runtime state specification:\n" ++
            "  - id: Container identifier\n" ++
            "  - status: created (not started through nexcage yet), running, stopped or paused\n" ++
            "  - pid: host PID of the container's init while it runs, 0 otherwise\n" ++
            "  - bundle: Bundle path (null if unknown)\n" ++
            "  - annotations: OCI annotations (empty object)\n\n" ++
            "Examples:\n" ++
            "  nexcage state web-1\n" ++
            "  nexcage state 101        # a VMID works too\n");
    }

    pub fn validate(self: *Self, args: []const []const u8) !void {
        _ = self;
        try validation.ValidationUtils.requireNonEmptyArgs(args);
    }
};

/// Maps a pct status to an OCI status
fn ociStatus(status: []const u8) []const u8 {
    if (std.mem.eql(u8, status, "running")) return "running";
    if (std.mem.eql(u8, status, "stopped") or std.mem.eql(u8, status, "exited") or std.mem.eql(u8, status, "shutdown")) return "stopped";
    if (std.mem.eql(u8, status, "paused")) return "paused";
    if (std.mem.eql(u8, status, "created")) return "created";
    return "unknown";
}

/// The bundle path from nexcage's own record, or null when there is none.
/// Allocated; the caller frees it.
fn persistedBundle(allocator: std.mem.Allocator, name: []const u8) ?[]u8 {
    if (name.len == 0 or std.mem.indexOfScalar(u8, name, '/') != null or
        std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) return null;

    const path = std.fmt.allocPrint(allocator, "{s}/{s}/state.json", .{ core.state_root.get(), name }) catch return null;
    defer allocator.free(path);
    const data = std.fs.cwd().readFileAlloc(allocator, path, 64 * 1024) catch return null;
    defer allocator.free(data);

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, data, .{}) catch return null;
    defer parsed.deinit();
    if (parsed.value != .object) return null;
    const value = parsed.value.object.get("bundle") orelse return null;
    if (value != .string) return null;
    return allocator.dupe(u8, value.string) catch null;
}

/// Whether nexcage's own record still says "created". create writes that to
/// <state root>/<name>/state.json, and start replaces it, so a stopped
/// container with this record has not been started through nexcage.
fn neverStarted(allocator: std.mem.Allocator, name: []const u8) bool {
    if (name.len == 0 or std.mem.indexOfScalar(u8, name, '/') != null or
        std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) return false;

    const path = std.fmt.allocPrint(allocator, "{s}/{s}/state.json", .{ core.state_root.get(), name }) catch return false;
    defer allocator.free(path);
    const data = std.fs.cwd().readFileAlloc(allocator, path, 64 * 1024) catch return false;
    defer allocator.free(data);

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, data, .{}) catch return false;
    defer parsed.deinit();
    if (parsed.value != .object) return false;
    const status = parsed.value.object.get("status") orelse return false;
    return status == .string and std.mem.eql(u8, status.string, "created");
}
