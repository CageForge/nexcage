const std = @import("std");
const template_ops = @import("../src/proxmox/template/operations.zig");

test "detectOS positive/negative" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const A = gpa.allocator();
    var tmp = try std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = tmp.dir;
    try root.makePath("etc");
    var f = try root.createFile("etc/os-release", .{});
    defer f.close();
    try f.writeAll("ID=debian\n");
    const p = try std.fmt.allocPrint(A, "{s}", .{tmp.path});
    defer A.free(p);
    const os_ok = try template_ops.detectOS(p, A);
    defer A.free(os_ok);
    try std.testing.expectEqualStrings("debian", os_ok);
    const os_unknown = try template_ops.detectOS("/non/existent", A);
    defer A.free(os_unknown);
    try std.testing.expectEqualStrings("unknown", os_unknown);
}

test "detectArchitecture positive/negative" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const A = gpa.allocator();
    var tmp = try std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = tmp.dir;
    try root.makePath("proc");
    var f = try root.createFile("proc/version", .{});
    defer f.close();
    try f.writeAll("Linux version x86_64\n");
    const p = try std.fmt.allocPrint(A, "{s}", .{tmp.path});
    defer A.free(p);
    const arch_ok = try template_ops.detectArchitecture(p, A);
    defer A.free(arch_ok);
    try std.testing.expectEqualStrings("amd64", arch_ok);
    const arch_unknown = try template_ops.detectArchitecture("/non/existent", A);
    defer A.free(arch_unknown);
    try std.testing.expectEqualStrings("unknown", arch_unknown);
}

test "detectVersion positive/negative" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const A = gpa.allocator();
    var tmp = try std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = tmp.dir;
    try root.makePath("etc");
    var f = try root.createFile("etc/os-release", .{});
    defer f.close();
    try f.writeAll("VERSION_ID=12\n");
    const p = try std.fmt.allocPrint(A, "{s}", .{tmp.path});
    defer A.free(p);
    const ver_ok = try template_ops.detectVersion(p, A);
    defer A.free(ver_ok);
    try std.testing.expectEqualStrings("12", ver_ok);
    const ver_unknown = try template_ops.detectVersion("/non/existent", A);
    defer A.free(ver_unknown);
    try std.testing.expectEqualStrings("unknown", ver_unknown);
}

test "buildMultipartForm positive" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const A = gpa.allocator();
    const mf = try template_ops.buildMultipartForm(A, "----B", "tpl", "DATA");
    defer A.free(mf.body);
    defer A.free(mf.content_type);
    try std.testing.expect(std.mem.indexOf(u8, mf.body, "filename=\"tpl.tar.zst\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, mf.body, "DATA") != null);
    try std.testing.expect(std.mem.indexOf(u8, mf.content_type, "boundary=----B") != null);
}

test "parseTemplatesFromJson positive/negative" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const A = gpa.allocator();
    const ok_json = "{\"data\":[{\"volid\":\"local:tpls/nginx.tar.zst\",\"size\":123,\"format\":\"tar.zst\"}]}";
    var arr = try template_ops.parseTemplatesFromJson(A, ok_json);
    defer {
        for (arr) |*t| t.deinit(A);
        A.free(arr);
    }
    try std.testing.expect(arr.len == 1);
    try std.testing.expectEqualStrings("nginx.tar.zst", arr[0].name);

    const bad_json = "{"; // invalid
    try std.testing.expectError(error.UnexpectedEndOfInput, template_ops.parseTemplatesFromJson(A, bad_json));
}

test "createTemplateArchive negative (non-existent rootfs)" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const A = gpa.allocator();
    try std.testing.expectError(error.TemplateCreationFailed, template_ops.createTemplateArchive(A, "/does/not/exist", "tplneg"));
}
