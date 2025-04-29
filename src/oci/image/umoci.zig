const std = @import("std");
const os = std.os;
const fs = std.fs;
const types = @import("types.zig");

pub const UmociError = error{
    CommandFailed,
    InvalidArgument,
    UnpackFailed,
    RepackFailed,
    ConfigFailed,
};

pub const Umoci = struct {
    allocator: std.mem.Allocator,
    binary_path: []const u8,
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator, binary_path: []const u8) !*Self {
        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .binary_path = try allocator.dupe(u8, binary_path),
        };
        return self;
    }
    
    pub fn deinit(self: *Self) void {
        self.allocator.free(self.binary_path);
        self.allocator.destroy(self);
    }
    
    pub fn unpack(self: *Self, image_path: []const u8, tag: []const u8, bundle_path: []const u8) !void {
        const args = [_][]const u8{
            self.binary_path,
            "unpack",
            "--image",
            try std.fmt.allocPrint(self.allocator, "{s}:{s}", .{ image_path, tag }),
            bundle_path,
        };
        
        const result = try std.ChildProcess.exec(.{
            .allocator = self.allocator,
            .argv = &args,
        });
        defer {
            self.allocator.free(result.stdout);
            self.allocator.free(result.stderr);
        }
        
        if (result.term.Exited != 0) {
            return UmociError.UnpackFailed;
        }
    }
    
    pub fn repack(self: *Self, image_path: []const u8, tag: []const u8, bundle_path: []const u8) !void {
        const args = [_][]const u8{
            self.binary_path,
            "repack",
            "--image",
            try std.fmt.allocPrint(self.allocator, "{s}:{s}", .{ image_path, tag }),
            bundle_path,
        };
        
        const result = try std.ChildProcess.exec(.{
            .allocator = self.allocator,
            .argv = &args,
        });
        defer {
            self.allocator.free(result.stdout);
            self.allocator.free(result.stderr);
        }
        
        if (result.term.Exited != 0) {
            return UmociError.RepackFailed;
        }
    }
    
    pub fn config(
        self: *Self,
        image_path: []const u8,
        tag: []const u8,
        options: types.ImageConfig,
    ) !void {
        var args = std.ArrayList([]const u8).init(self.allocator);
        defer args.deinit();
        
        try args.appendSlice(&[_][]const u8{
            self.binary_path,
            "config",
            "--image",
            try std.fmt.allocPrint(self.allocator, "{s}:{s}", .{ image_path, tag }),
        });
        
        if (options.author) |author| {
            try args.appendSlice(&[_][]const u8{"--author", author});
        }
        
        if (options.config) |cfg| {
            if (cfg.WorkingDir) |dir| {
                try args.appendSlice(&[_][]const u8{"--config.workingdir", dir});
            }
            
            if (cfg.Entrypoint) |entrypoint| {
                for (entrypoint) |entry| {
                    try args.appendSlice(&[_][]const u8{"--config.entrypoint", entry});
                }
            }
            
            if (cfg.Cmd) |cmd| {
                for (cmd) |arg| {
                    try args.appendSlice(&[_][]const u8{"--config.cmd", arg});
                }
            }
            
            if (cfg.Env) |env| {
                for (env) |var_| {
                    try args.appendSlice(&[_][]const u8{"--config.env", var_});
                }
            }
        }
        
        const result = try std.ChildProcess.exec(.{
            .allocator = self.allocator,
            .argv = args.items,
        });
        defer {
            self.allocator.free(result.stdout);
            self.allocator.free(result.stderr);
        }
        
        if (result.term.Exited != 0) {
            return UmociError.ConfigFailed;
        }
    }
    
    pub fn gc(self: *Self, image_path: []const u8) !void {
        const args = [_][]const u8{
            self.binary_path,
            "gc",
            "--layout",
            image_path,
        };
        
        const result = try std.ChildProcess.exec(.{
            .allocator = self.allocator,
            .argv = &args,
        });
        defer {
            self.allocator.free(result.stdout);
            self.allocator.free(result.stderr);
        }
        
        if (result.term.Exited != 0) {
            return UmociError.CommandFailed;
        }
    }
}; 