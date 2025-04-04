const std = @import("std");
const json = std.json;

pub const APIResponse = struct {
    data: json.Value,
    success: bool,
    err_msg: ?[]const u8,
};
