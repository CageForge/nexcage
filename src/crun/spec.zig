const std = @import("std");

pub const Spec = struct {
    process: ?Process = null,
    linux: ?Linux = null,
};

pub const Process = struct {
    terminal: bool = false,
};

pub const Linux = struct {
    resources: ?Resources = null,
};

pub const Resources = struct {
    memory: ?Memory = null,
};

pub const Memory = struct {
    limit: ?u64 = null,
};
