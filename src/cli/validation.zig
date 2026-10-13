const std = @import("std");
const core = @import("core");
const errors = @import("errors.zig");

/// Common validation utilities for CLI commands
pub const ValidationUtils = struct {
    /// Validates that container_id is provided in options
    /// Returns the container_id or logs error and returns InvalidInput
    pub fn requireContainerId(options: core.types.RuntimeOptions, logger: ?*core.LogContext, command_name: []const u8) ![]const u8 {
        const container_id = options.container_id orelse {
            const error_handler = errors.createErrorHandler(logger);
            return error_handler.invalidInput("Container ID is required for {s} command", .{command_name});
        };
        return container_id;
    }

    /// Validates that both container_id and image are provided in options
    /// Returns a struct with both values or logs error and returns InvalidInput
    pub fn requireContainerIdAndImage(options: core.types.RuntimeOptions, logger: ?*core.LogContext, command_name: []const u8) !struct { container_id: []const u8, image: []const u8 } {
        const error_handler = errors.createErrorHandler(logger);

        const container_id = options.container_id orelse {
            return error_handler.invalidInput("Container ID is required for {s} command", .{command_name});
        };

        const image = options.image orelse {
            return error_handler.invalidInput("Image is required for {s} command", .{command_name});
        };

        return .{ .container_id = container_id, .image = image };
    }

    /// Validates that args array is not empty
    pub fn requireNonEmptyArgs(args: []const []const u8) !void {
        if (args.len == 0) {
            return errors.CliError.InvalidInput;
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
            return errors.CliError.InvalidInput;
        }
    }
};
