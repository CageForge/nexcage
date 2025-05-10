const std = @import("std");
const os = std.os;
const fs = std.fs;

pub const DNSError = error{
    ConfigurationFailed,
    ResolvConfNotFound,
    WriteError,
};

pub const DNSManager = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    netns_path: []const u8,

    pub fn init(allocator: std.mem.Allocator, netns_path: []const u8) !Self {
        return Self{
            .allocator = allocator,
            .netns_path = try allocator.dupe(u8, netns_path),
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.netns_path);
    }

    /// Configures DNS for the network namespace
    pub fn configure(self: *Self, servers: []const []const u8, search: []const []const u8, options: []const []const u8) !void {
        // Create path to resolv.conf in the network namespace
        const resolv_path = try std.fs.path.join(self.allocator, &[_][]const u8{ self.netns_path, "etc/resolv.conf" });
        defer self.allocator.free(resolv_path);

        // Create directory if it doesn't exist
        try std.fs.makeDirAbsolute(std.fs.path.dirname(resolv_path).?);

        // Open file for writing
        const file = try std.fs.createFileAbsolute(resolv_path, .{
            .read = true,
            .truncate = true,
        });
        defer file.close();

        const writer = file.writer();

        // Write nameservers
        for (servers) |server| {
            try writer.print("nameserver {s}\n", .{server});
        }

        // Write search domains
        if (search.len > 0) {
            try writer.writeAll("search");
            for (search) |domain| {
                try writer.print(" {s}", .{domain});
            }
            try writer.writeAll("\n");
        }

        // Write options
        if (options.len > 0) {
            try writer.writeAll("options");
            for (options) |opt| {
                try writer.print(" {s}", .{opt});
            }
            try writer.writeAll("\n");
        }
    }

    /// Cleans up DNS configuration
    pub fn cleanup(self: *Self) !void {
        const resolv_path = try std.fs.path.join(self.allocator, &[_][]const u8{ self.netns_path, "etc/resolv.conf" });
        defer self.allocator.free(resolv_path);

        std.fs.deleteFileAbsolute(resolv_path) catch |err| {
            switch (err) {
                error.FileNotFound => {}, // Ignore if file doesn't exist
                else => return err,
            }
        };
    }
};
