const std = @import("std");

pub const OverlayError = error{
    MountError,
    UnmountError,
    LayerNotFound,
    InvalidPath,
    CreateDirectoryError,
    RemoveDirectoryError,
    CopyError,
};

pub const OverlayMount = struct {
    lower_dir: []const u8,
    upper_dir: []const u8,
    work_dir: []const u8,
    merged_dir: []const u8,
    
    pub fn init(
        allocator: std.mem.Allocator,
        container_id: []const u8,
        root_dir: []const u8,
    ) !OverlayMount {
        const lower = try std.fmt.allocPrint(allocator, "{s}/lower/{s}", .{ root_dir, container_id });
        const upper = try std.fmt.allocPrint(allocator, "{s}/upper/{s}", .{ root_dir, container_id });
        const work = try std.fmt.allocPrint(allocator, "{s}/work/{s}", .{ root_dir, container_id });
        const merged = try std.fmt.allocPrint(allocator, "{s}/merged/{s}", .{ root_dir, container_id });
        
        return OverlayMount{
            .lower_dir = lower,
            .upper_dir = upper,
            .work_dir = work,
            .merged_dir = merged,
        };
    }
    
    pub fn deinit(self: *OverlayMount, allocator: std.mem.Allocator) void {
        allocator.free(self.lower_dir);
        allocator.free(self.upper_dir);
        allocator.free(self.work_dir);
        allocator.free(self.merged_dir);
    }
};

pub const OverlayLayer = struct {
    id: []const u8,
    path: []const u8,
    parent: ?[]const u8,
    
    pub fn init(
        allocator: std.mem.Allocator,
        id: []const u8,
        path: []const u8,
        parent: ?[]const u8,
    ) !OverlayLayer {
        return OverlayLayer{
            .id = try allocator.dupe(u8, id),
            .path = try allocator.dupe(u8, path),
            .parent = if (parent) |p| try allocator.dupe(u8, p) else null,
        };
    }
    
    pub fn deinit(self: *OverlayLayer, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.path);
        if (self.parent) |p| allocator.free(p);
    }
}; 