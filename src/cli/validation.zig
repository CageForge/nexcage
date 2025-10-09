const std = @import("std");
const core = @import("core");

/// Common validation utilities for CLI commands
pub const ValidationUtils = struct {
    /// Validates that container_id is provided in options
    /// Returns the container_id or logs error and returns InvalidInput
    pub fn requireContainerId(options: core.types.RuntimeOptions, logger: ?*core.LogContext, command_name: []const u8) ![]const u8 {
        const container_id = options.container_id orelse {
            if (logger) |log| {
                try log.err("Container ID is required for {s} command", .{command_name});
            }
            return core.Error.InvalidInput;
        };
        return container_id;
    }

    /// Validates that both container_id and image are provided in options
    /// Returns a struct with both values or logs error and returns InvalidInput
    pub fn requireContainerIdAndImage(options: core.types.RuntimeOptions, logger: ?*core.LogContext, command_name: []const u8) !struct { container_id: []const u8, image: []const u8 } {
        const container_id = options.container_id orelse {
            if (logger) |log| {
                try log.err("Container ID is required for {s} command", .{command_name});
            }
            return core.Error.InvalidInput;
        };

        const image = options.image orelse {
            if (logger) |log| {
                try log.err("Image is required for {s} command", .{command_name});
            }
            return core.Error.InvalidInput;
        };

        return .{ .container_id = container_id, .image = image };
    }

    /// Validates that args array is not empty
    pub fn requireNonEmptyArgs(args: []const []const u8) !void {
        if (args.len == 0) {
            return core.types.Error.InvalidInput;
        }
    }

    /// Validates that args contain at least one non-flag argument (for image specification)
    pub fn requireImageInArgs(args: []const []const u8) !void {
        var has_image = false;
        for (args) |arg| {
            if (!std.mem.startsWith(u8, arg, "-")) {
                has_image = true;
                break;
            }
        }

        if (!has_image) {
            return core.types.Error.InvalidInput;
        }
    }
};
