const std = @import("std");
const core = @import("core");
const backends = @import("backends");
const types = core.types;
const config_module = core.config;
const base_command = @import("base_command.zig");

/// `features`: what this runtime implements, as the runtime-spec's features
/// document.
///
/// containerd's CRI asks for it once at startup, before any container exists,
/// and until now got `unknown command`. It is the first verb from the missing
/// row that something has actually wanted; it did not stop a pod, because
/// containerd records the failure and then assumes nothing.
///
/// It carries no container id, and a container id is nexcage's routing key. So
/// the backend is resolved the way a container with no name would route: an
/// explicit `--runtime` wins, otherwise the routing rules are asked about an
/// empty id — which for the catch-all an engine needs (`"*"`) is crun, and
/// otherwise is the configured default runtime.
///
/// Only the crun backend answers. A features document is a claim about how a
/// runtime implements the spec — which hooks it runs, whether it applies
/// seccomp, AppArmor, SELinux, capabilities, an idmapped mount. The Proxmox LXC
/// backend does none of that: it hands the container to `pct`, so any document
/// written for it would be an assertion about `pct`'s behaviour dressed as this
/// runtime's. That is the same reason `--console-socket` is refused there
/// rather than accepted and ignored.
pub const FeaturesCommand = struct {
    const Self = @This();

    name: []const u8 = "features",
    description: []const u8 = "Show what this runtime implements, as an OCI features document",
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

        var runtime_type: types.RuntimeType = .proxmox_lxc;
        if (options.runtime_type) |rt| {
            runtime_type = rt;
        } else {
            var config_loader = config_module.ConfigLoader.init(allocator);
            var cfg = try config_loader.loadDefault();
            defer cfg.deinit();
            runtime_type = cfg.getRoutedRuntime("");
        }

        if (runtime_type != .crun) {
            if (self.base.logger) |log| {
                log.err(
                    "features describes how a runtime implements the OCI spec, and the {s} backend does not implement it: `pct` creates the container, so its hooks, seccomp, AppArmor and capabilities are not nexcage's to report. Use --runtime crun, or route to crun in the config file",
                    .{@tagName(runtime_type)},
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

        const document = try crun_backend.featuresJson(allocator);
        defer allocator.free(document);
        try stdout.writeAll(document);
    }

    pub fn help(self: *Self, allocator: std.mem.Allocator) ![]const u8 {
        _ = self;
        return allocator.dupe(u8, "Usage: nexcage features\n\n" ++
            "Print the OCI runtime-spec features document for this build: the\n" ++
            "spec versions it accepts, the hooks it runs, the mount options and\n" ++
            "namespaces it knows, and whether seccomp, AppArmor, SELinux and\n" ++
            "idmapped mounts are compiled in.\n\n" ++
            "The values come from the vendored libcrun this binary links, which\n" ++
            "is what does the container work, so the answer is the same one\n" ++
            "`crun features` gives for the same build.\n\n" ++
            "Answered by the crun backend only. The command takes no container\n" ++
            "id, so there is nothing to route on: pass --runtime crun, or let\n" ++
            "the config file's routing rules resolve to crun (an engine never\n" ++
            "passes --runtime).\n\n" ++
            "Options:\n" ++
            "  -h, --help    Show this help message\n\n" ++
            "Examples:\n" ++
            "  nexcage --runtime crun features\n" ++
            "  nexcage features | jq .linux.namespaces\n");
    }

    pub fn validate(self: *Self, args: []const []const u8) !void {
        _ = self;
        _ = args;
        // features takes no arguments
    }
};
