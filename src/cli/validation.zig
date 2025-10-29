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
    
    /// Validate hostname per common constraints (RFC-1123-like):
    /// - 1..253 chars, labels 1..63, [a-z0-9-], no leading/trailing '-'
    pub fn validateHostname(hostname: []const u8) bool {
        if (hostname.len == 0 or hostname.len > 253) return false;
        var it = std.mem.splitScalar(u8, hostname, '.');
        while (it.next()) |label| {
            if (label.len == 0 or label.len > 63) return false;
            if (label[0] == '-' or label[label.len - 1] == '-') return false;
            var i: usize = 0;
            while (i < label.len) : (i += 1) {
                const c = label[i];
                const is_alpha = (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z');
                const is_digit = (c >= '0' and c <= '9');
                const is_dash = (c == '-');
                if (!(is_alpha or is_digit or is_dash)) return false;
            }
        }
        return true;
    }

    /// Basic VMID validation: numeric string 1..6 digits
    pub fn validateVmidString(vmid: []const u8) bool {
        if (vmid.len == 0 or vmid.len > 6) return false;
        var i: usize = 0;
        while (i < vmid.len) : (i += 1) {
            const c = vmid[i];
            if (c < '0' or c > '9') return false;
        }
        return true;
    }

    /// Storage name (Proxmox): [A-Za-z0-9_-]+
    pub fn validateStorageName(name: []const u8) bool {
        if (name.len == 0) return false;
        var i: usize = 0;
        while (i < name.len) : (i += 1) {
            const c = name[i];
            const ok = (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9') or c == '_' or c == '-';
            if (!ok) return false;
        }
        return true;
    }

    /// Safe path: forbids '\\0', disallows '..' segments; optional absolute requirement
    pub fn validateSafePath(path: []const u8, require_absolute: bool) bool {
        if (path.len == 0) return false;
        if (require_absolute and path[0] != '/') return false;
        if (std.mem.indexOfScalar(u8, path, 0)) |_| return false;
        var it = std.mem.splitScalar(u8, path, '/');
        while (it.next()) |seg| {
            if (std.mem.eql(u8, seg, ".")) continue;
            if (std.mem.eql(u8, seg, "..")) return false;
        }
        return true;
    }

    /// Env var: KEY=VALUE, KEY matches [A-Z_][A-Z0-9_]*
    pub fn validateEnvKV(kv: []const u8) bool {
        const eq_idx_opt = std.mem.indexOfScalar(u8, kv, '=');
        if (eq_idx_opt == null) return false;
        const eq_idx = eq_idx_opt.?;
        const key = kv[0..eq_idx];
        if (key.len == 0) return false;
        if (!((key[0] >= 'A' and key[0] <= 'Z') or key[0] == '_')) return false;
        var i: usize = 1;
        while (i < key.len) : (i += 1) {
            const c = key[i];
            const ok = (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9') or c == '_';
            if (!ok) return false;
        }
        const value = kv[eq_idx+1..];
        return std.mem.indexOfScalar(u8, value, 0) == null;
    }
};
