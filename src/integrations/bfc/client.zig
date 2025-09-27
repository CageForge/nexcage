const std = @import("std");
const core = @import("core");
const types = @import("types.zig");

/// BFC (Binary File Container) client implementation
/// BFC client for container operations
pub const BFCClient = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    logger: ?*core.LogContext = null,

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
        };
    }

    /// Set logger
    pub fn setLogger(self: *Self, logger: *core.LogContext) void {
        self.logger = logger;
    }

    /// Open BFC container for reading
    pub fn openContainer(self: *Self, path: []const u8) !types.BFCContainer {
        if (self.logger) |log| {
            try log.info("Opening BFC container: {s}", .{path});
        }

        var container = try types.BFCContainer.init(self.allocator, path);
        container.setLogger(self.logger);

        var bfc_container: ?*types.c.bfc_t = null;
        const result = types.c.bfc_open(path.ptr, &bfc_container);

        if (result != types.c.BFC_OK) {
            return types.BFCError.BFCOpenFailed;
        }

        container.container = bfc_container;

        if (self.logger) |log| {
            try log.info("Successfully opened BFC container: {s}", .{path});
        }

        return container;
    }

    /// Create new BFC container for writing
    pub fn createContainer(self: *Self, path: []const u8) !types.BFCBuilder {
        if (self.logger) |log| {
            try log.info("Creating BFC container: {s}", .{path});
        }

        var builder = try types.BFCBuilder.init(self.allocator, path);
        builder.setLogger(self.logger);

        var writer: ?*types.c.bfc_writer_t = null;
        const result = types.c.bfc_create(path.ptr, &writer);

        if (result != types.c.BFC_OK) {
            return types.BFCError.BFCCreateFailed;
        }

        builder.writer = writer;

        if (self.logger) |log| {
            try log.info("Successfully created BFC container: {s}", .{path});
        }

        return builder;
    }

    /// Add file to BFC container
    pub fn addFile(self: *Self, builder: *types.BFCBuilder, file_path: []const u8, data: []const u8, mode: u32) !void {
        _ = self;
        if (builder.writer == null) {
            return types.BFCError.BFCNotStarted;
        }

        if (builder.logger) |log| {
            try log.info("Adding file to BFC container: {s}", .{file_path});
        }

        const result = types.c.bfc_add_file(builder.writer, file_path.ptr, data.ptr, data.len, mode, std.time.nanoTimestamp());

        if (result != types.c.BFC_OK) {
            return types.BFCError.BFCAddFileFailed;
        }

        if (builder.logger) |log| {
            try log.info("Successfully added file to BFC container: {s}", .{file_path});
        }
    }

    /// Add directory to BFC container
    pub fn addDir(self: *Self, builder: *types.BFCBuilder, dir_path: []const u8, mode: u32) !void {
        _ = self;
        if (builder.writer == null) {
            return types.BFCError.BFCNotStarted;
        }

        if (builder.logger) |log| {
            try log.info("Adding directory to BFC container: {s}", .{dir_path});
        }

        const result = types.c.bfc_add_dir(builder.writer, dir_path.ptr, mode, std.time.nanoTimestamp());

        if (result != types.c.BFC_OK) {
            return types.BFCError.BFCAddDirFailed;
        }

        if (builder.logger) |log| {
            try log.info("Successfully added directory to BFC container: {s}", .{dir_path});
        }
    }

    /// Finish building BFC container
    pub fn finishContainer(self: *Self, builder: *types.BFCBuilder) !void {
        _ = self;
        if (builder.writer == null) {
            return types.BFCError.BFCNotStarted;
        }

        if (builder.logger) |log| {
            try log.info("Finishing BFC container build: {s}", .{builder.path});
        }

        const result = types.c.bfc_finish(builder.writer);

        if (result != types.c.BFC_OK) {
            return types.BFCError.BFCFinishFailed;
        }

        if (builder.logger) |log| {
            try log.info("Successfully finished BFC container build: {s}", .{builder.path});
        }
    }

    /// List contents of BFC container
    pub fn listContainer(self: *Self, container: *types.BFCContainer, callback: types.c.bfc_list_callback_t, userdata: ?*anyopaque) !void {
        _ = self;
        if (container.container == null) {
            return types.BFCError.BFCNotOpen;
        }

        if (container.logger) |log| {
            try log.info("Listing BFC container contents: {s}", .{container.path});
        }

        const result = types.c.bfc_list(container.container, null, callback, userdata);

        if (result != types.c.BFC_OK) {
            return types.BFCError.BFCListFailed;
        }

        if (container.logger) |log| {
            try log.info("Successfully listed BFC container contents: {s}", .{container.path});
        }
    }

    /// Extract file from BFC container
    pub fn extractFile(self: *Self, container: *types.BFCContainer, file_path: []const u8, output_path: []const u8) !void {
        _ = self;
        if (container.container == null) {
            return types.BFCError.BFCNotOpen;
        }

        if (container.logger) |log| {
            try log.info("Extracting file from BFC container: {s} -> {s}", .{ file_path, output_path });
        }

        const result = types.c.bfc_extract_to_file(container.container, file_path.ptr, output_path.ptr);

        if (result != types.c.BFC_OK) {
            return types.BFCError.BFCExtractFailed;
        }

        if (container.logger) |log| {
            try log.info("Successfully extracted file from BFC container: {s}", .{file_path});
        }
    }

    /// Get file info from BFC container
    pub fn getFileInfo(self: *Self, container: *types.BFCContainer, file_path: []const u8) !types.BFCFileInfo {
        if (container.container == null) {
            return types.BFCError.BFCNotOpen;
        }

        var info: types.c.bfc_file_info_t = undefined;
        const result = types.c.bfc_get_file_info(container.container, file_path.ptr, &info);

        if (result != types.c.BFC_OK) {
            return types.BFCError.BFCGetInfoFailed;
        }

        return types.BFCFileInfo{
            .allocator = self.allocator,
            .name = try self.allocator.dupe(u8, std.mem.sliceTo(@as([*:0]u8, @ptrCast(&info.name)), 0)),
            .size = info.size,
            .mode = info.mode,
            .mtime = info.mtime,
            .crc32c = info.crc32c,
        };
    }

    /// Set encryption password
    pub fn setEncryptionPassword(self: *Self, container: *types.BFCContainer, password: []const u8) !void {
        _ = self;
        if (container.container == null) {
            return types.BFCError.BFCNotOpen;
        }

        if (container.logger) |log| {
            try log.info("Setting encryption password for BFC container: {s}", .{container.path});
        }

        const result = types.c.bfc_set_encryption_password(container.container, password.ptr, password.len);

        if (result != types.c.BFC_OK) {
            return types.BFCError.BFCSetPasswordFailed;
        }

        if (container.logger) |log| {
            try log.info("Successfully set encryption password for BFC container: {s}", .{container.path});
        }
    }

    /// Verify BFC container integrity
    pub fn verifyContainer(self: *Self, container: *types.BFCContainer) !bool {
        _ = self;
        if (container.container == null) {
            return types.BFCError.BFCNotOpen;
        }

        if (container.logger) |log| {
            try log.info("Verifying BFC container integrity: {s}", .{container.path});
        }

        const result = types.c.bfc_verify(container.container);

        if (result == types.c.BFC_OK) {
            if (container.logger) |log| {
                try log.info("BFC container integrity verified: {s}", .{container.path});
            }
            return true;
        } else {
            if (container.logger) |log| {
                try log.warn("BFC container integrity check failed: {s}", .{container.path});
            }
            return false;
        }
    }

    /// Set compression
    pub fn setCompression(self: *Self, builder: *types.BFCBuilder, compression_type: types.c.bfc_compression_t, level: i32) !void {
        _ = self;
        if (builder.writer == null) {
            return types.BFCError.BFCNotStarted;
        }

        if (builder.logger) |log| {
            try log.info("Setting BFC compression: type={}, level={}", .{ compression_type, level });
        }

        const result = types.c.bfc_set_compression(builder.writer, compression_type, level);

        if (result != types.c.BFC_OK) {
            return types.BFCError.BFCSetCompressionFailed;
        }

        if (builder.logger) |log| {
            try log.info("Successfully set BFC compression: type={}, level={}", .{ compression_type, level });
        }
    }

    /// Set encryption
    pub fn setEncryption(self: *Self, builder: *types.BFCBuilder, password: []const u8) !void {
        _ = self;
        if (builder.writer == null) {
            return types.BFCError.BFCNotStarted;
        }

        if (builder.logger) |log| {
            try log.info("Setting BFC encryption: {s}", .{builder.path});
        }

        const result = types.c.bfc_set_encryption_password(builder.writer, password.ptr, password.len);

        if (result != types.c.BFC_OK) {
            return types.BFCError.BFCSetPasswordFailed;
        }

        if (builder.logger) |log| {
            try log.info("Successfully set BFC encryption: {s}", .{builder.path});
        }
    }
};
