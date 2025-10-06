const std = @import("std");
const core = @import("core");
const types = core.types;
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

        return "Usage: proxmox-lxcri version\n\n" ++
            "Show version information for proxmox-lxcri\n\n" ++
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

        try version_text.writer().print("proxmox-lxcri version {d}.{d}.{d}", .{
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

/// Create a version command instance
pub fn createVersionCommand() VersionCommand {
    return VersionCommand{};
}
