const std = @import("std");
const core = @import("core");

/// ZFS specific types
/// ZFS errors
pub const ZFSError = error{
    CommandExecutionFailed,
    InvalidDataset,
    InvalidSnapshot,
    SnapshotNotFound,
    DatasetNotFound,
    ZFSNotAvailable,
};

/// ZFS manager for container checkpoint/restore
pub const ZFSManager = struct {
    allocator: std.mem.Allocator,
    logger: ?*core.LogContext = null,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) !*Self {
        const self = try allocator.alloc(Self, 1);
        self[0] = Self{
            .allocator = allocator,
        };

        return &self[0];
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self);
    }

    /// Set logger
    pub fn setLogger(self: *Self, logger: *core.LogContext) void {
        self.logger = logger;
    }
};

/// ZFS dataset information
pub const ZFSDataset = struct {
    allocator: std.mem.Allocator,
    name: []const u8,
    mountpoint: []const u8,
    used: u64,
    available: u64,
    referenced: u64,
    compression: []const u8,
    checksum: []const u8,
    atime: bool,
    canmount: []const u8,
    mounted: bool,
    origin: ?[]const u8 = null,
    quota: ?u64 = null,
    reservation: ?u64 = null,
    volsize: ?u64 = null,
    volblocksize: ?u64 = null,
    logbias: []const u8,
    sync: []const u8,
    refquota: ?u64 = null,
    refreservation: ?u64 = null,
    guid: u64,
    createtxg: u64,
    createtxg_string: []const u8,
    usedbychildren: u64,
    usedbydataset: u64,
    usedbyrefreservation: u64,
    usedbysnapshots: u64,
    objsetid: u64,
    objsetid_string: []const u8,
    defer_destroy: bool,
    userrefs: u64,
    userrefs_string: []const u8,
    written: u64,
    written_string: []const u8,
    logicalused: u64,
    logicalused_string: []const u8,
    logicalreferenced: u64,
    logicalreferenced_string: []const u8,
    volmode: []const u8,
    filesystem_limit: ?u64 = null,
    snapshot_limit: ?u64 = null,
    filesystem_count: ?u64 = null,
    snapshot_count: ?u64 = null,
    snapdev: []const u8,
    acltype: []const u8,
    context: []const u8,
    fscontext: []const u8,
    defcontext: []const u8,
    rootcontext: []const u8,
    relatime: bool,
    redundant_metadata: []const u8,
    overlay: bool,
    encryption: []const u8,
    keylocation: []const u8,
    keyformat: []const u8,
    pbkdf2iters: ?u64 = null,
    special_small_blocks: ?u64 = null,
    clones: ?[]const u8 = null,

    pub fn deinit(self: *ZFSDataset) void {
        self.allocator.free(self.name);
        self.allocator.free(self.mountpoint);
        self.allocator.free(self.compression);
        self.allocator.free(self.checksum);
        self.allocator.free(self.canmount);
        if (self.origin) |origin| self.allocator.free(origin);
        self.allocator.free(self.logbias);
        self.allocator.free(self.sync);
        self.allocator.free(self.createtxg_string);
        self.allocator.free(self.objsetid_string);
        self.allocator.free(self.userrefs_string);
        self.allocator.free(self.written_string);
        self.allocator.free(self.logicalused_string);
        self.allocator.free(self.logicalreferenced_string);
        self.allocator.free(self.volmode);
        self.allocator.free(self.snapdev);
        self.allocator.free(self.acltype);
        self.allocator.free(self.context);
        self.allocator.free(self.fscontext);
        self.allocator.free(self.defcontext);
        self.allocator.free(self.rootcontext);
        self.allocator.free(self.redundant_metadata);
        self.allocator.free(self.encryption);
        self.allocator.free(self.keylocation);
        self.allocator.free(self.keyformat);
        if (self.clones) |clones| self.allocator.free(clones);
    }
};

/// ZFS snapshot information
pub const ZFSSnapshot = struct {
    allocator: std.mem.Allocator,
    name: []const u8,
    dataset: []const u8,
    creation: u64,
    used: u64,
    referenced: u64,
    written: u64,
    logicalused: u64,
    logicalreferenced: u64,
    defer_destroy: bool,
    userrefs: u64,
    objsetid: u64,
    guid: u64,
    createtxg: u64,
    clones: ?[]const u8 = null,

    pub fn deinit(self: *ZFSSnapshot) void {
        self.allocator.free(self.name);
        self.allocator.free(self.dataset);
        if (self.clones) |clones| self.allocator.free(clones);
    }
};
