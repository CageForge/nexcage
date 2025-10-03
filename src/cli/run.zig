const std = @import("std");
const core = @import("core");

const types = core.types;
const interfaces = core.interfaces;
const backends = @import("backends");

/// Run command implementation
/// Run command
pub const RunCommand = struct {
    const Self = @This();

    name: []const u8 = "run",
    description: []const u8 = "Run a container",

    pub fn execute(self: *Self, options: types.RuntimeOptions, allocator: std.mem.Allocator) !void {
        _ = self;

        if (options.container_id == null) {
            return types.Error.InvalidInput;
        }

        if (options.image == null) {
            return types.Error.InvalidInput;
        }

        const container_id = options.container_id.?;
        const image = options.image.?;

        // Load configuration for backend routing
        var config_loader = core.ConfigLoader.init(allocator);
        var cfg = try config_loader.loadDefault();
        defer cfg.deinit();

        // Select backend based on config routing
        const ctype = cfg.getContainerType(container_id);
        std.debug.print("Selected backend: {s} for container: {s}\n", .{ @tagName(ctype), container_id });

        // Create and start container using selected backend
        switch (ctype) {
            .lxc => {
                // Create minimal sandbox config for LXC
                const name_buf = try allocator.dupe(u8, container_id);
                defer allocator.free(name_buf);
                
                const sandbox_config = core.types.SandboxConfig{
                    .allocator = allocator,
                    .name = name_buf,
                    .runtime_type = .lxc,
                    .resources = null,
                    .security = null,
                    .network = null,
                    .storage = null,
                };
                
                const lxc_backend = try backends.lxc.LxcBackend.init(allocator, sandbox_config);
                defer lxc_backend.deinit();
                
                try lxc_backend.create(sandbox_config);
                try lxc_backend.start(container_id);
            },
            else => {
                std.debug.print("Selected backend not implemented for run: {}\n", .{ctype});
                return types.Error.UnsupportedOperation;
            },
        }

        std.debug.print("Running container: {s} with image: {s}\n", .{ container_id, image });
    }

    pub fn help(self: *Self, allocator: std.mem.Allocator) ![]const u8 {
        _ = self;
        _ = allocator;

        return "Usage: proxmox-lxcri run [OPTIONS] IMAGE [COMMAND] [ARG...]\n\n" ++
            "Run a container from an image\n\n" ++
            "Options:\n" ++
            "  -i, --interactive    Keep STDIN open even if not attached\n" ++
            "  -t, --tty           Allocate a pseudo-TTY\n" ++
            "  -d, --detach         Run container in background and print container ID\n" ++
            "  --name string        Assign a name to the container\n" ++
            "  --runtime string     Runtime to use for this container\n" ++
            "  --config string      Path to configuration file\n" ++
            "  -v, --verbose        Verbose output\n" ++
            "  --debug              Debug output\n" ++
            "  -h, --help           Show this help message\n";
    }

    pub fn validate(self: *Self, args: []const []const u8) !void {
        _ = self;

        if (args.len == 0) {
            return types.Error.InvalidInput;
        }

        // Basic validation - check for required arguments
        var has_image = false;
        for (args) |arg| {
            if (!std.mem.startsWith(u8, arg, "-")) {
                has_image = true;
                break;
            }
        }

        if (!has_image) {
            return types.Error.InvalidInput;
        }
    }
};

/// Create a run command instance
pub fn createRunCommand() RunCommand {
    return RunCommand{};
}
