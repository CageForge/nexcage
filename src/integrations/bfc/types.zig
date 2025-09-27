const std = @import("std");
const core = @import("core");

/// BFC (Binary File Container) specific types
/// BFC container handle
pub const BFCContainer = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    logger: ?*core.LogContext = null,
    container: ?*c.bfc_t = null,
    path: []const u8,

    pub fn init(allocator: std.mem.Allocator, path: []const u8) !Self {
        return Self{
            .allocator = allocator,
            .path = try allocator.dupe(u8, path),
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.container) |container| {
            c.bfc_close(container);
        }
        self.allocator.free(self.path);
    }

    /// Set logger
    pub fn setLogger(self: *Self, logger: *core.LogContext) void {
        self.logger = logger;
    }
};

/// BFC file information
pub const BFCFileInfo = struct {
    allocator: std.mem.Allocator,
    name: []const u8,
    size: u64,
    mode: u32,
    mtime: u64,
    crc32c: u32,

    pub fn deinit(self: *BFCFileInfo) void {
        self.allocator.free(self.name);
    }
};

/// BFC container builder
pub const BFCBuilder = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    logger: ?*core.LogContext = null,
    writer: ?*c.bfc_writer_t = null,
    path: []const u8,

    pub fn init(allocator: std.mem.Allocator, path: []const u8) !Self {
        return Self{
            .allocator = allocator,
            .path = try allocator.dupe(u8, path),
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.writer) |writer| {
            c.bfc_close(writer);
        }
        self.allocator.free(self.path);
    }

    /// Set logger
    pub fn setLogger(self: *Self, logger: *core.LogContext) void {
        self.logger = logger;
    }
};

/// BFC errors
pub const BFCError = error{
    BFCOpenFailed,
    BFCCreateFailed,
    BFCNotOpen,
    BFCNotStarted,
    BFCAddFileFailed,
    BFCAddDirFailed,
    BFCFinishFailed,
    BFCListFailed,
    BFCTempFileFailed,
    BFCExtractFailed,
    BFCGetInfoFailed,
    BFCSetPasswordFailed,
    BFCSetCompressionFailed,
};

/// BFC constants
pub const BFC_OK = c.BFC_OK;
pub const BFC_ERROR = c.BFC_ERROR;
pub const BFC_COMPRESSION_NONE = c.BFC_COMPRESSION_NONE;
pub const BFC_COMPRESSION_ZSTD = c.BFC_COMPRESSION_ZSTD;
pub const BFC_COMPRESSION_AUTO = c.BFC_COMPRESSION_AUTO;

// BFC C library bindings
pub const c = @cImport({
    @cInclude("bfc.h");
});
