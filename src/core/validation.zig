const std = @import("std");
const types = @import("types.zig");

/// The checks of a name a container is given: an id, and, for the Proxmox
/// LXC backend, which makes the name the container's hostname, a hostname.
pub const SecurityValidation = struct {
    /// Validate container ID format (alphanumeric, hyphens, underscores, 1-64 chars)
    pub fn validateContainerId(id: []const u8) !void {
        if (id.len == 0 or id.len > 64) return types.Error.InvalidInput;

        for (id) |c| {
            const is_lower = c >= 'a' and c <= 'z';
            const is_upper = c >= 'A' and c <= 'Z';
            const is_digit = c >= '0' and c <= '9';
            const is_hyphen = c == '-';
            const is_underscore = c == '_';

            if (!(is_lower or is_upper or is_digit or is_hyphen or is_underscore)) {
                return types.Error.InvalidInput;
            }
        }
    }

    /// Validate hostname (RFC-1123 compliant)
    pub fn validateHostname(name: []const u8) !void {
        if (name.len == 0 or name.len > 253) return types.Error.InvalidInput;

        var label_len: usize = 0;
        var i: usize = 0;

        while (i < name.len) : (i += 1) {
            const c = name[i];
            if (c == '.') {
                if (label_len == 0 or label_len > 63) return types.Error.InvalidInput;
                // A label ends in a letter or digit: "a-.b" is not a name
                if (name[i - 1] == '-') return types.Error.InvalidInput;
                label_len = 0;
                continue;
            }

            const is_lower = c >= 'a' and c <= 'z';
            const is_upper = c >= 'A' and c <= 'Z';
            const is_digit = c >= '0' and c <= '9';
            const is_hyphen = c == '-';

            if (!(is_lower or is_upper or is_digit or is_hyphen)) {
                return types.Error.InvalidInput;
            }

            // Labels cannot start or end with hyphen
            if (label_len == 0 and is_hyphen) return types.Error.InvalidInput;
            label_len += 1;
        }

        if (label_len == 0 or label_len > 63) return types.Error.InvalidInput;
        if (name[name.len - 1] == '-') return types.Error.InvalidInput;
    }
};

/// Path security utilities
pub const PathSecurity = struct {
    /// Secure path joining that prevents directory traversal
    pub fn secureJoin(allocator: std.mem.Allocator, base: []const u8, relative: []const u8) ![]u8 {
        // Check for directory traversal attempts
        if (std.mem.indexOf(u8, relative, "..") != null) {
            return types.Error.ValidationError;
        }

        // Check for absolute paths in relative component
        if (std.fs.path.isAbsolute(relative)) {
            return types.Error.ValidationError;
        }

        return try std.fs.path.join(allocator, &[_][]const u8{ base, relative });
    }

    /// Canonicalize a bundle path. Any absolute path is accepted: the caller
    /// of an OCI runtime picks the bundle directory, and an engine's is not
    /// one nexcage can predict. What this still guarantees is that the path
    /// resolves — `..` cannot walk out of anything — and that it is absolute,
    /// so a relative path cannot be read against whatever directory the
    /// engine happened to exec nexcage from.
    pub fn validateBundlePath(path: []const u8, allocator: std.mem.Allocator) ![]u8 {
        const resolved = try std.fs.path.resolve(allocator, &[_][]const u8{path});
        // errdefer, not a free before the return: doing both frees it twice.
        errdefer allocator.free(resolved);
        if (resolved.len == 0 or resolved[0] != '/') return types.Error.ValidationError;
        return resolved;
    }
};

test "a hostname is RFC 1123's: no label empty, longer than 63, or starting or ending in '-'" {
    // The Proxmox LXC backend makes a container's name its hostname, and
    // Proxmox refuses one that is not a DNS name; checked here, it is refused
    // before an image is pulled or a VMID taken. A test under tests/ used to
    // assert this on a copy of the rules written inline, which refused
    // "test-" while this function accepted it.
    const V = SecurityValidation;
    for ([_][]const u8{ "web-1", "a", "Web-1", "test.container", "a1-b2.c3", "x" ** 63 }) |name| {
        try V.validateHostname(name);
    }
    for ([_][]const u8{ "", "test-", "-test", "a-.b", "a.-b", "a..b", ".a", "a.", "test@container", "a_b", "x" ** 64 }) |name| {
        V.validateHostname(name) catch continue;
        std.debug.print("accepted '{s}'\n", .{name});
        return error.TestUnexpectedResult;
    }
}
