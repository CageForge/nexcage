const std = @import("std");
const core = @import("core");
const types = core.types;
const interfaces = core.interfaces;

/// Run command implementation
/// Run command
pub const RunCommand = struct {
    const Self = @This();

    name: []const u8 = "run",
    description: []const u8 = "Run a container",

    pub fn execute(self: *Self, options: types.RuntimeOptions, allocator: std.mem.Allocator) !void {
        _ = self;
        _ = allocator;

        if (!options.container_id) {
            return types.Error.InvalidInput;
        }

        if (!options.image) {
            return types.Error.InvalidInput;
        }

        // TODO: Implement actual container running logic
        // This would involve:
        // 1. Loading the appropriate backend based on runtime_type
        // 2. Creating a sandbox configuration
        // 3. Calling the backend's create and start methods

        std.debug.print("Running container: {s} with image: {s}\n", .{ options.container_id.?, options.image.? });
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
