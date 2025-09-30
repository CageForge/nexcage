const std = @import("std");
const core = @import("core");
const backends = @import("backends");

test "parseLxcLsJson handles array of strings" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const A = gpa.allocator();

    const json = "[\"c1\", \"c2\"]";
    var driver = backends.lxc.LxcDriver{ .allocator = A };
    const list = try driver.parseLxcLsJson(A, json);
    defer {
        for (list) |*ci| ci.deinit();
        A.free(list);
    }
    try std.testing.expectEqual(@as(usize, 2), list.len);
}

test "parseLxcLsJson handles array of objects" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const A = gpa.allocator();

    const json = "[{\"name\":\"c1\",\"state\":\"RUNNING\"},{\"name\":\"c2\",\"state\":\"STOPPED\"}]";
    var driver = backends.lxc.LxcDriver{ .allocator = A };
    const list = try driver.parseLxcLsJson(A, json);
    defer {
        for (list) |*ci| ci.deinit();
        A.free(list);
    }
    try std.testing.expectEqual(@as(usize, 2), list.len);
}


