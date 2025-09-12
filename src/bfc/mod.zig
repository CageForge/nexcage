// BFC (Binary File Container) module
// This module provides Zig bindings for the BFC C library

const std = @import("std");
const Allocator = std.mem.Allocator;
const logger_mod = @import("logger");
const types = @import("types");

// BFC C library bindings
pub const c = @cImport({
    @cInclude("bfc.h");
});

/// BFC container handle
pub const BFCContainer = struct {
    const Self = @This();
    
    allocator: Allocator,
    logger: *logger_mod.Logger,
    container: ?*c.bfc_t,
    path: []const u8,
    
    pub fn init(allocator: Allocator, logger: *logger_mod.Logger, path: []const u8) !Self {
        return Self{
            .allocator = allocator,
            .logger = logger,
            .container = null,
            .path = try allocator.dupe(u8, path),
        };
    }
    
    pub fn deinit(self: *Self) void {
        if (self.container) |container| {
            c.bfc_close(container);
        }
        self.allocator.free(self.path);
    }
    
    /// Open BFC container for reading
    pub fn open(self: *Self) !void {
        try self.logger.info("Opening BFC container: {s}", .{self.path});
        
        var container: ?*c.bfc_t = null;
        const result = c.bfc_open(self.path.ptr, &container);
        
        if (result != c.BFC_OK) {
            return error.BFCOpenFailed;
        }
        
        self.container = container;
        try self.logger.info("Successfully opened BFC container: {s}", .{self.path});
    }
    
    /// Create new BFC container for writing
    pub fn create(self: *Self) !void {
        try self.logger.info("Creating BFC container: {s}", .{self.path});
        
        var writer: ?*c.bfc_writer_t = null;
        const result = c.bfc_create(self.path.ptr, &writer);
        
        if (result != c.BFC_OK) {
            return error.BFCCreateFailed;
        }
        
        // Convert writer to container (simplified)
        self.container = @ptrCast(*c.bfc_t, writer);
        try self.logger.info("Successfully created BFC container: {s}", .{self.path});
    }
    
    /// Add file to BFC container
    pub fn addFile(self: *Self, file_path: []const u8, data: []const u8, mode: u32) !void {
        if (self.container == null) {
            return error.BFCNotOpen;
        }
        
        try self.logger.info("Adding file to BFC container: {s}", .{file_path});
        
        const result = c.bfc_add_file(
            @ptrCast(*c.bfc_writer_t, self.container),
            file_path.ptr,
            data.ptr,
            data.len,
            mode,
            std.time.nanoTimestamp()
        );
        
        if (result != c.BFC_OK) {
            return error.BFCAddFileFailed;
        }
        
        try self.logger.info("Successfully added file to BFC container: {s}", .{file_path});
    }
    
    /// Add directory to BFC container
    pub fn addDir(self: *Self, dir_path: []const u8, mode: u32) !void {
        if (self.container == null) {
            return error.BFCNotOpen;
        }
        
        try self.logger.info("Adding directory to BFC container: {s}", .{dir_path});
        
        const result = c.bfc_add_dir(
            @ptrCast(*c.bfc_writer_t, self.container),
            dir_path.ptr,
            mode,
            std.time.nanoTimestamp()
        );
        
        if (result != c.BFC_OK) {
            return error.BFCAddDirFailed;
        }
        
        try self.logger.info("Successfully added directory to BFC container: {s}", .{dir_path});
    }
    
    /// Finish writing BFC container
    pub fn finish(self: *Self) !void {
        if (self.container == null) {
            return error.BFCNotOpen;
        }
        
        try self.logger.info("Finishing BFC container: {s}", .{self.path});
        
        const result = c.bfc_finish(@ptrCast(*c.bfc_writer_t, self.container));
        
        if (result != c.BFC_OK) {
            return error.BFCFinishFailed;
        }
        
        try self.logger.info("Successfully finished BFC container: {s}", .{self.path});
    }
    
    /// List contents of BFC container
    pub fn list(self: *Self, callback: c.bfc_list_callback_t, userdata: ?*anyopaque) !void {
        if (self.container == null) {
            return error.BFCNotOpen;
        }
        
        try self.logger.info("Listing BFC container contents: {s}", .{self.path});
        
        const result = c.bfc_list(self.container, null, callback, userdata);
        
        if (result != c.BFC_OK) {
            return error.BFCListFailed;
        }
        
        try self.logger.info("Successfully listed BFC container contents: {s}", .{self.path});
    }
    
    /// Extract file from BFC container
    pub fn extractFile(self: *Self, file_path: []const u8, output_path: []const u8) !void {
        if (self.container == null) {
            return error.BFCNotOpen;
        }
        
        try self.logger.info("Extracting file from BFC container: {s} -> {s}", .{ file_path, output_path });
        
        const result = c.bfc_extract_to_file(
            self.container,
            file_path.ptr,
            output_path.ptr
        );
        
        if (result != c.BFC_OK) {
            return error.BFCExtractFailed;
        }
        
        try self.logger.info("Successfully extracted file from BFC container: {s}", .{file_path});
    }
    
    /// Get file info from BFC container
    pub fn getFileInfo(self: *Self, file_path: []const u8) !BFCFileInfo {
        if (self.container == null) {
            return error.BFCNotOpen;
        }
        
        var info: c.bfc_file_info_t = undefined;
        const result = c.bfc_get_file_info(self.container, file_path.ptr, &info);
        
        if (result != c.BFC_OK) {
            return error.BFCGetInfoFailed;
        }
        
        return BFCFileInfo{
            .name = try self.allocator.dupe(u8, std.mem.sliceTo(@as([*:0]u8, @ptrCast(&info.name)), 0)),
            .size = info.size,
            .mode = info.mode,
            .mtime = info.mtime,
            .crc32c = info.crc32c,
        };
    }
    
    /// Set encryption password
    pub fn setEncryptionPassword(self: *Self, password: []const u8) !void {
        if (self.container == null) {
            return error.BFCNotOpen;
        }
        
        try self.logger.info("Setting encryption password for BFC container: {s}", .{self.path});
        
        const result = c.bfc_set_encryption_password(
            self.container,
            password.ptr,
            password.len
        );
        
        if (result != c.BFC_OK) {
            return error.BFCSetPasswordFailed;
        }
        
        try self.logger.info("Successfully set encryption password for BFC container: {s}", .{self.path});
    }
    
    /// Verify BFC container integrity
    pub fn verify(self: *Self) !bool {
        if (self.container == null) {
            return error.BFCNotOpen;
        }
        
        try self.logger.info("Verifying BFC container integrity: {s}", .{self.path});
        
        const result = c.bfc_verify(self.container);
        
        if (result == c.BFC_OK) {
            try self.logger.info("BFC container integrity verified: {s}", .{self.path});
            return true;
        } else {
            try self.logger.warn("BFC container integrity check failed: {s}", .{self.path});
            return false;
        }
    }
};

/// BFC file information
pub const BFCFileInfo = struct {
    name: []const u8,
    size: u64,
    mode: u32,
    mtime: u64,
    crc32c: u32,
    allocator: Allocator,
    
    pub fn deinit(self: *BFCFileInfo) void {
        self.allocator.free(self.name);
    }
};

/// BFC container builder
pub const BFCBuilder = struct {
    const Self = @This();
    
    allocator: Allocator,
    logger: *logger_mod.Logger,
    writer: ?*c.bfc_writer_t,
    path: []const u8,
    
    pub fn init(allocator: Allocator, logger: *logger_mod.Logger, path: []const u8) !Self {
        return Self{
            .allocator = allocator,
            .logger = logger,
            .writer = null,
            .path = try allocator.dupe(u8, path),
        };
    }
    
    pub fn deinit(self: *Self) void {
        if (self.writer) |writer| {
            c.bfc_close(writer);
        }
        self.allocator.free(self.path);
    }
    
    /// Start building BFC container
    pub fn start(self: *Self) !void {
        try self.logger.info("Starting BFC container build: {s}", .{self.path});
        
        var writer: ?*c.bfc_writer_t = null;
        const result = c.bfc_create(self.path.ptr, &writer);
        
        if (result != c.BFC_OK) {
            return error.BFCCreateFailed;
        }
        
        self.writer = writer;
        try self.logger.info("Successfully started BFC container build: {s}", .{self.path});
    }
    
    /// Add file to BFC container
    pub fn addFile(self: *Self, file_path: []const u8, data: []const u8, mode: u32) !void {
        if (self.writer == null) {
            return error.BFCNotStarted;
        }
        
        try self.logger.info("Adding file to BFC container: {s}", .{file_path});
        
        const result = c.bfc_add_file(
            self.writer,
            file_path.ptr,
            data.ptr,
            data.len,
            mode,
            std.time.nanoTimestamp()
        );
        
        if (result != c.BFC_OK) {
            return error.BFCAddFileFailed;
        }
        
        try self.logger.info("Successfully added file to BFC container: {s}", .{file_path});
    }
    
    /// Add directory to BFC container
    pub fn addDir(self: *Self, dir_path: []const u8, mode: u32) !void {
        if (self.writer == null) {
            return error.BFCNotStarted;
        }
        
        try self.logger.info("Adding directory to BFC container: {s}", .{dir_path});
        
        const result = c.bfc_add_dir(
            self.writer,
            dir_path.ptr,
            mode,
            std.time.nanoTimestamp()
        );
        
        if (result != c.BFC_OK) {
            return error.BFCAddDirFailed;
        }
        
        try self.logger.info("Successfully added directory to BFC container: {s}", .{dir_path});
    }
    
    /// Finish building BFC container
    pub fn finish(self: *Self) !void {
        if (self.writer == null) {
            return error.BFCNotStarted;
        }
        
        try self.logger.info("Finishing BFC container build: {s}", .{self.path});
        
        const result = c.bfc_finish(self.writer);
        
        if (result != c.BFC_OK) {
            return error.BFCFinishFailed;
        }
        
        try self.logger.info("Successfully finished BFC container build: {s}", .{self.path});
    }
    
    /// Set compression
    pub fn setCompression(self: *Self, compression_type: c.bfc_compression_t, level: i32) !void {
        if (self.writer == null) {
            return error.BFCNotStarted;
        }
        
        try self.logger.info("Setting BFC compression: type={}, level={}", .{ compression_type, level });
        
        const result = c.bfc_set_compression(self.writer, compression_type, level);
        
        if (result != c.BFC_OK) {
            return error.BFCSetCompressionFailed;
        }
        
        try self.logger.info("Successfully set BFC compression: type={}, level={}", .{ compression_type, level });
    }
    
    /// Set encryption
    pub fn setEncryption(self: *Self, password: []const u8) !void {
        if (self.writer == null) {
            return error.BFCNotStarted;
        }
        
        try self.logger.info("Setting BFC encryption: {s}", .{self.path});
        
        const result = c.bfc_set_encryption_password(
            self.writer,
            password.ptr,
            password.len
        );
        
        if (result != c.BFC_OK) {
            return error.BFCSetPasswordFailed;
        }
        
        try self.logger.info("Successfully set BFC encryption: {s}", .{self.path});
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
