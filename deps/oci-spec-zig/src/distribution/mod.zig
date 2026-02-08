const std = @import("std");

pub const version = "1.0.0";

pub const RepositoryList = struct {
    repositories: []const []const u8,

    pub fn init(repos: []const []const u8) RepositoryList {
        return .{ .repositories = repos };
    }
};

test "distribution module loads" {
    const list = RepositoryList.init(&.{ "busybox" });
    std.debug.assert(list.repositories.len == 1);
}

