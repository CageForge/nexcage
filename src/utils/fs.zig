const std = @import("std");
const core = @import("core");
const types = core.types;

/// File system utilities
/// File system operations interface
pub const FSOperations = struct {
    const Self = @This();

    /// Check if path exists
    exists: *const fn (self: *Self, path: []const u8) bool,

    /// Create directory
    mkdir: *const fn (self: *Self, path: []const u8) types.Error!void,

    /// Create directory recursively
    mkdirAll: *const fn (self: *Self, path: []const u8) types.Error!void,

    /// Remove directory
    rmdir: *const fn (self: *Self, path: []const u8) types.Error!void,

    /// Remove file
    remove: *const fn (self: *Self, path: []const u8) types.Error!void,

    /// Copy file
    copy: *const fn (self: *Self, src: []const u8, dst: []const u8) types.Error!void,

    /// Move file
    move: *const fn (self: *Self, src: []const u8, dst: []const u8) types.Error!void,

    /// Read file contents
    readFile: *const fn (self: *Self, path: []const u8, allocator: std.mem.Allocator) types.Error![]u8,

    /// Write file contents
    writeFile: *const fn (self: *Self, path: []const u8, contents: []const u8) types.Error!void,

    /// Get file info
    stat: *const fn (self: *Self, path: []const u8, allocator: std.mem.Allocator) types.Error!FileInfo,

    /// List directory contents
    listDir: *const fn (self: *Self, path: []const u8, allocator: std.mem.Allocator) types.Error![]DirEntry,
};

/// File information
pub const FileInfo = struct {
    allocator: std.mem.Allocator,
    name: []const u8,
    size: u64,
    is_dir: bool,
    is_file: bool,
    is_symlink: bool,
    permissions: u32,
    modified: i64,
    accessed: i64,
    created: i64,

    pub fn deinit(self: *FileInfo) void {
        self.allocator.free(self.name);
    }
};

/// Directory entry
pub const DirEntry = struct {
    allocator: std.mem.Allocator,
    name: []const u8,
    is_dir: bool,
    is_file: bool,
    is_symlink: bool,

    pub fn deinit(self: *DirEntry) void {
        self.allocator.free(self.name);
    }
};

/// Default file system operations implementation
pub const DefaultFSOperations = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) DefaultFSOperations {
        return DefaultFSOperations{
            .allocator = allocator,
        };
    }

    pub fn exists(self: *DefaultFSOperations, path: []const u8) bool {
        _ = self;
        std.fs.cwd().access(path, .{}) catch return false;
        return true;
    }

    pub fn mkdir(self: *DefaultFSOperations, path: []const u8) types.Error!void {
        _ = self;
        std.fs.cwd().makeDir(path) catch |err| switch (err) {
            error.PathAlreadyExists => return types.Error.OperationFailed,
            error.NoSpaceLeft => return types.Error.OperationFailed,
            error.AccessDenied => return types.Error.PermissionDenied,
            error.BadPathName => return types.Error.InvalidInput,
            error.NameTooLong => return types.Error.InvalidInput,
            error.NotDir => return types.Error.InvalidInput,
            error.InvalidUtf8 => return types.Error.InvalidInput,
            error.SymLinkLoop => return types.Error.OperationFailed,
            error.ProcessFdQuotaExceeded => return types.Error.OperationFailed,
            error.SystemFdQuotaExceeded => return types.Error.OperationFailed,
            error.SystemResources => return types.Error.OperationFailed,
            error.Unexpected => return types.Error.OperationFailed,
            else => return types.Error.OperationFailed,
        };
    }

    pub fn mkdirAll(self: *DefaultFSOperations, path: []const u8) types.Error!void {
        _ = self;
        std.fs.cwd().makePath(path) catch |err| switch (err) {
            error.NoSpaceLeft => return types.Error.OperationFailed,
            error.AccessDenied => return types.Error.PermissionDenied,
            error.BadPathName => return types.Error.InvalidInput,
            error.NameTooLong => return types.Error.InvalidInput,
            error.NotDir => return types.Error.InvalidInput,
            error.InvalidUtf8 => return types.Error.InvalidInput,
            error.SymLinkLoop => return types.Error.OperationFailed,
            error.ProcessFdQuotaExceeded => return types.Error.OperationFailed,
            error.SystemFdQuotaExceeded => return types.Error.OperationFailed,
            error.SystemResources => return types.Error.OperationFailed,
            error.Unexpected => return types.Error.OperationFailed,
            else => return types.Error.OperationFailed,
        };
    }

    pub fn rmdir(self: *DefaultFSOperations, path: []const u8) types.Error!void {
        _ = self;
        std.fs.cwd().deleteDir(path) catch |err| switch (err) {
            error.FileNotFound => return types.Error.NotFound,
            error.NotDir => return types.Error.InvalidInput,
            error.DirNotEmpty => return types.Error.OperationFailed,
            error.AccessDenied => return types.Error.PermissionDenied,
            error.BadPathName => return types.Error.InvalidInput,
            error.NameTooLong => return types.Error.InvalidInput,
            error.InvalidUtf8 => return types.Error.InvalidInput,
            error.SymLinkLoop => return types.Error.OperationFailed,
            error.ProcessFdQuotaExceeded => return types.Error.OperationFailed,
            error.SystemFdQuotaExceeded => return types.Error.OperationFailed,
            error.SystemResources => return types.Error.OperationFailed,
            error.Unexpected => return types.Error.OperationFailed,
            else => return types.Error.OperationFailed,
        };
    }

    pub fn remove(self: *DefaultFSOperations, path: []const u8) types.Error!void {
        _ = self;
        std.fs.cwd().deleteFile(path) catch |err| switch (err) {
            error.FileNotFound => return types.Error.NotFound,
            error.AccessDenied => return types.Error.PermissionDenied,
            error.BadPathName => return types.Error.InvalidInput,
            error.NameTooLong => return types.Error.InvalidInput,
            error.InvalidUtf8 => return types.Error.InvalidInput,
            error.SymLinkLoop => return types.Error.OperationFailed,
            error.ProcessFdQuotaExceeded => return types.Error.OperationFailed,
            error.SystemFdQuotaExceeded => return types.Error.OperationFailed,
            error.SystemResources => return types.Error.OperationFailed,
            error.Unexpected => return types.Error.OperationFailed,
            else => return types.Error.OperationFailed,
        };
    }

    pub fn copy(self: *DefaultFSOperations, src: []const u8, dst: []const u8) types.Error!void {
        _ = self;
        std.fs.cwd().copyFile(src, std.fs.cwd(), dst, .{}) catch |err| switch (err) {
            error.FileNotFound => return types.Error.NotFound,
            error.AccessDenied => return types.Error.PermissionDenied,
            error.BadPathName => return types.Error.InvalidInput,
            error.NameTooLong => return types.Error.InvalidInput,
            error.InvalidUtf8 => return types.Error.InvalidInput,
            error.SymLinkLoop => return types.Error.OperationFailed,
            error.ProcessFdQuotaExceeded => return types.Error.OperationFailed,
            error.SystemFdQuotaExceeded => return types.Error.OperationFailed,
            error.SystemResources => return types.Error.OperationFailed,
            error.Unexpected => return types.Error.OperationFailed,
            else => return types.Error.OperationFailed,
        };
    }

    pub fn move(self: *DefaultFSOperations, src: []const u8, dst: []const u8) types.Error!void {
        _ = self;
        std.fs.cwd().rename(src, dst) catch |err| switch (err) {
            error.FileNotFound => return types.Error.NotFound,
            error.AccessDenied => return types.Error.PermissionDenied,
            error.BadPathName => return types.Error.InvalidInput,
            error.NameTooLong => return types.Error.InvalidInput,
            error.InvalidUtf8 => return types.Error.InvalidInput,
            error.SymLinkLoop => return types.Error.OperationFailed,
            error.ProcessFdQuotaExceeded => return types.Error.OperationFailed,
            error.SystemFdQuotaExceeded => return types.Error.OperationFailed,
            error.SystemResources => return types.Error.OperationFailed,
            error.Unexpected => return types.Error.OperationFailed,
            else => return types.Error.OperationFailed,
        };
    }

    pub fn readFile(self: *DefaultFSOperations, path: []const u8, allocator: std.mem.Allocator) types.Error![]u8 {
        _ = self;
        const file = std.fs.cwd().openFile(path, .{}) catch |err| switch (err) {
            error.FileNotFound => return types.Error.NotFound,
            error.AccessDenied => return types.Error.PermissionDenied,
            error.BadPathName => return types.Error.InvalidInput,
            error.NameTooLong => return types.Error.InvalidInput,
            error.InvalidUtf8 => return types.Error.InvalidInput,
            error.SymLinkLoop => return types.Error.OperationFailed,
            error.ProcessFdQuotaExceeded => return types.Error.OperationFailed,
            error.SystemFdQuotaExceeded => return types.Error.OperationFailed,
            error.SystemResources => return types.Error.OperationFailed,
            error.Unexpected => return types.Error.OperationFailed,
            else => return types.Error.OperationFailed,
        };
        defer file.close();

        return file.readToEndAlloc(allocator, std.math.maxInt(usize)) catch |err| switch (err) {
            error.OutOfMemory => return types.Error.OutOfMemory,
            else => return types.Error.OperationFailed,
        };
    }

    pub fn writeFile(self: *DefaultFSOperations, path: []const u8, contents: []const u8) types.Error!void {
        _ = self;
        const file = std.fs.cwd().createFile(path, .{}) catch |err| switch (err) {
            error.AccessDenied => return types.Error.PermissionDenied,
            error.BadPathName => return types.Error.InvalidInput,
            error.NameTooLong => return types.Error.InvalidInput,
            error.InvalidUtf8 => return types.Error.InvalidInput,
            error.SymLinkLoop => return types.Error.OperationFailed,
            error.ProcessFdQuotaExceeded => return types.Error.OperationFailed,
            error.SystemFdQuotaExceeded => return types.Error.OperationFailed,
            error.SystemResources => return types.Error.OperationFailed,
            error.Unexpected => return types.Error.OperationFailed,
            else => return types.Error.OperationFailed,
        };
        defer file.close();

        file.writeAll(contents) catch |err| switch (err) {
            error.DiskQuota => return types.Error.OperationFailed,
            error.FileTooBig => return types.Error.OperationFailed,
            error.InputOutput => return types.Error.OperationFailed,
            error.NoSpaceLeft => return types.Error.OperationFailed,
            error.UnableToWrite => return types.Error.OperationFailed,
            else => return types.Error.OperationFailed,
        };
    }

    pub fn stat(self: *DefaultFSOperations, path: []const u8, allocator: std.mem.Allocator) types.Error!FileInfo {
        _ = self;
        const stat_result = std.fs.cwd().statFile(path) catch |err| switch (err) {
            error.FileNotFound => return types.Error.NotFound,
            error.AccessDenied => return types.Error.PermissionDenied,
            error.BadPathName => return types.Error.InvalidInput,
            error.NameTooLong => return types.Error.InvalidInput,
            error.InvalidUtf8 => return types.Error.InvalidInput,
            error.SymLinkLoop => return types.Error.OperationFailed,
            error.ProcessFdQuotaExceeded => return types.Error.OperationFailed,
            error.SystemFdQuotaExceeded => return types.Error.OperationFailed,
            error.SystemResources => return types.Error.OperationFailed,
            error.Unexpected => return types.Error.OperationFailed,
            else => return types.Error.OperationFailed,
        };

        const name = std.fs.path.basename(path);
        const name_owned = allocator.dupe(u8, name) catch return types.Error.OutOfMemory;

        return FileInfo{
            .allocator = allocator,
            .name = name_owned,
            .size = stat_result.size,
            .is_dir = stat_result.kind == .directory,
            .is_file = stat_result.kind == .file,
            .is_symlink = stat_result.kind == .sym_link,
            .permissions = @intCast(stat_result.mode & 0o777),
            .modified = @intCast(stat_result.mtime),
            .accessed = @intCast(stat_result.atime),
            .created = @intCast(stat_result.ctime),
        };
    }

    pub fn listDir(self: *DefaultFSOperations, path: []const u8, allocator: std.mem.Allocator) types.Error![]DirEntry {
        _ = self;
        var dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch |err| switch (err) {
            error.FileNotFound => return types.Error.NotFound,
            error.NotDir => return types.Error.InvalidInput,
            error.AccessDenied => return types.Error.PermissionDenied,
            error.BadPathName => return types.Error.InvalidInput,
            error.NameTooLong => return types.Error.InvalidInput,
            error.InvalidUtf8 => return types.Error.InvalidInput,
            error.SymLinkLoop => return types.Error.OperationFailed,
            error.ProcessFdQuotaExceeded => return types.Error.OperationFailed,
            error.SystemFdQuotaExceeded => return types.Error.OperationFailed,
            error.SystemResources => return types.Error.OperationFailed,
            error.Unexpected => return types.Error.OperationFailed,
            else => return types.Error.OperationFailed,
        };
        defer dir.close();

        var entries = std.ArrayList(DirEntry).init(allocator);
        var iterator = dir.iterate();

        while (iterator.next() catch |err| switch (err) {
            error.AccessDenied => return types.Error.PermissionDenied,
            error.SystemResources => return types.Error.OperationFailed,
            error.Unexpected => return types.Error.OperationFailed,
            else => return types.Error.OperationFailed,
        }) |entry| {
            const name_owned = allocator.dupe(u8, entry.name) catch return types.Error.OutOfMemory;

            try entries.append(DirEntry{
                .allocator = allocator,
                .name = name_owned,
                .is_dir = entry.kind == .directory,
                .is_file = entry.kind == .file,
                .is_symlink = entry.kind == .sym_link,
            });
        }

        return entries.toOwnedSlice();
    }
};
