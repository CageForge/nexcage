const std = @import("std");
const core = @import("core");
const types = core.types;
const base_command = @import("base_command.zig");
const interfaces = core.interfaces;

/// Version command implementation
/// Version information
pub const VersionInfo = struct {
    major: u32,
    minor: u32,
    patch: u32,
    build: ?[]const u8 = null,
    commit: ?[]const u8 = null,
    date: ?[]const u8 = null,
};

/// Version command
pub const VersionCommand = struct {
    const Self = @This();

    name: []const u8 = "version",
    description: []const u8 = "Show version information",
    base: base_command.BaseCommand = .{},

    pub fn setLogger(self: *Self, logger: *core.LogContext) void {
        self.base.setLogger(logger);
    }

    pub fn execute(self: *Self, options: types.RuntimeOptions, allocator: std.mem.Allocator) !void {
        _ = options;

        const version = getVersionInfo();
        const version_text = try self.formatVersion(version, allocator);
        defer allocator.free(version_text);

        std.debug.print("{s}\n", .{version_text});
    }

    pub fn help(self: *Self, allocator: std.mem.Allocator) ![]const u8 {
        _ = self;
        _ = allocator;

        return "Usage: nexcage version\n\n" ++
            "Show version information for nexcage\n\n" ++
            "Options:\n" ++
            "  -h, --help    Show this help message\n";
    }

    pub fn validate(self: *Self, args: []const []const u8) !void {
        _ = self;
        _ = args;
        // Version command doesn't require any arguments
    }

    fn formatVersion(self: *Self, version: VersionInfo, allocator: std.mem.Allocator) ![]u8 {
        _ = self;

        var version_text = std.array_list.Managed(u8).init(allocator);
        defer version_text.deinit();

        try version_text.writer().print("nexcage version {d}.{d}.{d}", .{
            version.major,
            version.minor,
            version.patch,
        });

        if (version.build) |build| {
            try version_text.writer().print("-{s}", .{build});
        }

        if (version.commit) |commit| {
            try version_text.writer().print(" (commit: {s})", .{commit});
        }

        if (version.date) |date| {
            try version_text.writer().print(" (built: {s})", .{date});
        }

        try version_text.appendSlice("\n");

        return version_text.toOwnedSlice();
    }
};

/// Get version information
pub fn getVersionInfo() VersionInfo {
    return VersionInfo{
        .major = 0,
        .minor = 3,
        .patch = 0,
        .build = "dev",
        .commit = "unknown",
        .date = "unknown",
    };
}
