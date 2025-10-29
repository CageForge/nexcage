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
        _ = self;
        _ = options;

        const stdout = std.fs.File.stdout();

        // Read version from VERSION file
        const version_file = std.fs.cwd().openFile("VERSION", .{}) catch {
            const msg = "nexcage version 0.0.0-dev (VERSION file not found)\n";
            try stdout.writeAll(msg);
            return;
        };
        defer version_file.close();
        
        const version_bytes = version_file.readToEndAlloc(allocator, 64) catch {
            const msg = "nexcage version 0.0.0-dev (failed to read VERSION)\n";
            try stdout.writeAll(msg);
            return;
        };
        defer allocator.free(version_bytes);
        
        const version_str = std.mem.trim(u8, version_bytes, " \n\r\t");
        const version = getVersionInfo(version_str);
        
        // Simple version output - format in one call
        const version_output = if (version.build) |build| 
            try std.fmt.allocPrint(allocator, "nexcage version {d}.{d}.{d}-{s}\n", .{ version.major, version.minor, version.patch, build })
        else 
            try std.fmt.allocPrint(allocator, "nexcage version {d}.{d}.{d}\n", .{ version.major, version.minor, version.patch });
        defer allocator.free(version_output);
        
        try stdout.writeAll(version_output);
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
};

/// Get version information
pub fn getVersionInfo(version_str: []const u8) VersionInfo {
    // Parse version string (e.g., "0.5.0")
    var parts = std.mem.splitSequence(u8, version_str, ".");
    
    const major_str = parts.next() orelse "0";
    const minor_str = parts.next() orelse "0";
    const patch_str = parts.next() orelse "0";
    
    const major = std.fmt.parseInt(u32, major_str, 10) catch 0;
    const minor = std.fmt.parseInt(u32, minor_str, 10) catch 0;
    const patch = std.fmt.parseInt(u32, patch_str, 10) catch 0;
    
    return VersionInfo{
        .major = major,
        .minor = minor,
        .patch = patch,
        .build = "release",
        .commit = "unknown",
        .date = "unknown",
    };
}
