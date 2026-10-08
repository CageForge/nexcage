const std = @import("std");
const core = @import("core");

const backends = @import("backends");
const router = @import("router.zig");
const update = @import("update.zig");
const constants = core.constants;
const validation = @import("validation.zig");
const base_command = @import("base_command.zig");

/// Create command implementation for modular architecture
pub const CreateCommand = struct {
    const Self = @This();

    name: []const u8 = "create",
    description: []const u8 = "Create a new container",
    base: base_command.BaseCommand = .{},

    pub fn setLogger(self: *Self, logger: *core.LogContext) void {
        self.base.setLogger(logger);
    }

    pub fn logInfo(self: *const Self, comptime format: []const u8, args: anytype) !void {
        try self.base.logInfo(format, args);
    }

    pub fn logCommandStart(self: *const Self, command_name: []const u8) !void {
        try self.base.logCommandStart(command_name);
    }

    pub fn logCommandComplete(self: *const Self, command_name: []const u8) !void {
        try self.base.logCommandComplete(command_name);
    }

    pub fn logOperation(self: *const Self, operation: []const u8, target: []const u8) !void {
        try self.base.logOperation(operation, target);
    }

    pub fn execute(self: *Self, options: core.types.RuntimeOptions, allocator: std.mem.Allocator) !void {
        // Check for help flag
        if (options.help) {
            const out = std.fs.File.stdout();
            try out.writeAll("Create Command Help:\n");
            try out.writeAll("  Usage: nexcage create --name <container_id> --image <image>\n");
            try out.writeAll("\n");
            try out.writeAll("  Options:\n");
            try out.writeAll("    --name <id>     Container ID/name (required)\n");
            try out.writeAll("    --image <img>   Container image (required)\n");
            try out.writeAll("    --storage <s>   Storage a registry image is found on or pulled to (default: local)\n");
            try out.writeAll("    --bundle <dir>  OCI bundle directory, an absolute path (config.json and rootfs/), in\n");
            try out.writeAll("                    place of an image; the first positional word is then the container id\n");
            try out.writeAll("                    (create <id> --bundle <dir>)\n");
            try out.writeAll("    --console-socket <path>, --pid-file <path>\n");
            try out.writeAll("                    crun only; refused on Proxmox LXC, where pct create starts no process\n");
            try out.writeAll("    --node <n>      Proxmox cluster node to create on (default: this one); Proxmox LXC only.\n");
            try out.writeAll("                    On another node the image must be a <storage>:vztmpl/ template that node\n");
            try out.writeAll("                    can read\n");
            try out.writeAll("\n");
            try out.writeAll("  What pct create is usually given (Proxmox LXC only; see CLI_REFERENCE.md):\n");
            try out.writeAll("    --memory <size>, --memory-swap <size>, --cpu-quota <us>, --cpu-period <us>,\n");
            try out.writeAll("    --cpu-share <n> As for update, said to pct as memory, swap, cpulimit, cpuunits\n");
            try out.writeAll("    --cores <n>     Cores the container sees\n");
            try out.writeAll("    --ip <cidr>, --gw <addr>, --vlan <tag>, --firewall\n");
            try out.writeAll("                    net0's ip=, gw=, tag= and firewall=1 (default ip=dhcp)\n");
            try out.writeAll("    --onboot        Start the container when the node boots\n");
            try out.writeAll("    --tags <a;b>    Proxmox tags\n");
            try out.writeAll("    --mp <spec>     A mount point in pct's syntax, e.g. local-lvm:8,mp=/data; repeatable\n");
            try out.writeAll("\n");
            try out.writeAll("    --runtime <rt>  Runtime type (lxc, crun)\n");
            try out.writeAll("    --config <cfg>  Configuration file path\n");
            try out.writeAll("    --verbose       Enable verbose logging\n");
            try out.writeAll("    --debug         Enable debug logging\n");
            try out.writeAll("\n");
            try out.writeAll("  Examples:\n");
            try out.writeAll("    nexcage create --name my-container --image local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst\n");
            try out.writeAll("    nexcage create --name web-1 --image docker.io/library/nginx:latest   # Proxmox VE 9.1+\n");
            try out.writeAll("    nexcage create --name r1 --storage shared-rdma docker.io/library/redis:7\n");
            try out.writeAll("    nexcage create --name db-1 --memory 4G --cores 2 --ip 10.0.0.5/24 --gw 10.0.0.1 \\\n");
            try out.writeAll("      --mp local-lvm:20,mp=/var/lib/postgresql local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst\n");
            return;
        }

        try self.logCommandStart("create");

        // Validate required options using validation utility
        const validated = try validation.ValidationUtils.requireContainerIdAndImage(options, self.base.logger, "create");
        const container_id = validated.container_id;
        const image = validated.image;

        try self.logInfo("Creating container {s} with image {s}", .{ container_id, image });

        // The limits read as update reads them; the rest is checked here so a
        // typo is a usage error rather than pct's complaint about net0 (#308).
        var limits = std.ArrayListUnmanaged(core.types.ResourceUpdate){};
        defer {
            for (limits.items) |u| allocator.free(u.value);
            limits.deinit(allocator);
        }
        if (options.resource_updates) |ups| for (ups) |u| {
            const value = try update.normaliseValue(allocator, self.base.logger, u);
            errdefer allocator.free(value);
            try limits.append(allocator, .{ .section = u.section, .name = u.name, .value = value, .numeric = u.numeric });
        };
        var pve = options.create_options;
        pve.limits = limits.items;
        try self.checkCreateOptions(pve);

        // Use router for backend selection and execution
        var backend_router = router.BackendRouter.initWithDebug(allocator, self.base.logger, options.debug);
        const operation = router.Operation{ .create = router.CreateConfig{
            .image = image,
            .console_socket = options.console_socket,
            .pid_file = options.pid_file,
            .systemd_cgroup = options.systemd_cgroup,
            .node = options.node,
            .storage = options.storage_name,
            .pve = pve,
        } };
        try backend_router.routeAndExecute(operation, container_id, options.runtime_type, null);

        try self.logCommandComplete("create");
    }

    /// net0 is one comma-separated list of key=value pairs, so a ',' or '=' in
    /// an address would add a key nobody asked for; pct checks the rest.
    fn checkCreateOptions(self: *Self, pve: core.types.ProxmoxCreateOptions) !void {
        inline for (.{ .{ "--ip", pve.ip }, .{ "--gw", pve.gw } }) |opt| if (opt[1]) |v| {
            if (v.len == 0 or std.mem.indexOfAny(u8, v, ",= \t") != null) {
                if (self.base.logger) |log| log.err("{s} '{s}' is not an address: net0 takes it as one value, without ',' or '='", .{ opt[0], v }) catch {};
                return core.types.Error.InvalidInput;
            }
        };
        if (pve.vlan) |v| {
            const tag = std.fmt.parseInt(u16, v, 10) catch 0;
            if (tag < 1 or tag > 4094) {
                if (self.base.logger) |log| log.err("--vlan '{s}' is not a VLAN tag: 1 to 4094", .{v}) catch {};
                return core.types.Error.InvalidInput;
            }
        }
        if (pve.cores) |v| {
            const n = std.fmt.parseInt(u16, v, 10) catch 0;
            if (n < 1) {
                if (self.base.logger) |log| log.err("--cores '{s}' is not a number of cores", .{v}) catch {};
                return core.types.Error.InvalidInput;
            }
        }
    }

    pub fn help(self: *Self, allocator: std.mem.Allocator) ![]const u8 {
        _ = self;
        return allocator.dupe(u8, "Usage: nexcage create --name <id> <image>\n");
    }

    pub fn validate(self: *Self, args: []const []const u8) !void {
        _ = self;
        try validation.ValidationUtils.requireNonEmptyArgs(args);
    }
};
