const std = @import("std");
const testing = std.testing;
const json = std.json;
const Allocator = std.mem.Allocator;

const crio = @import("crio");

test "CrioHook creation and basic functionality" {
    const allocator = testing.allocator;
    
    const args = [_][]const u8{"--test"};
    const env = [_][]const u8{"TEST_ENV=value"};
    
    var hook = try crio.CrioHook.init(
        allocator,
        "/usr/bin/test-hook",
        &args,
        &env,
        30,
        .prestart
    );
    defer hook.deinit(allocator);
    
    try testing.expectEqualStrings("/usr/bin/test-hook", hook.hook.path);
    try testing.expectEqualStrings("--test", hook.hook.args[0]);
    try testing.expectEqualStrings("TEST_ENV=value", hook.hook.env[0]);
    try testing.expect(hook.hook.timeout.? == 30);
    try testing.expect(hook.stage == .prestart);
}

test "CrioHook conditions" {
    const allocator = testing.allocator;
    
    const args = [_][]const u8{};
    const env = [_][]const u8{};
    
    var hook = try crio.CrioHook.init(
        allocator,
        "/usr/bin/test-hook",
        &args,
        &env,
        null,
        .prestart
    );
    defer hook.deinit(allocator);
    
    var annotations = std.StringHashMap([]const u8).init(allocator);
    try annotations.put("test.annotation", "value");
    
    const commands = [_][]const u8{"test-cmd"};
    
    try hook.setConditions(
        allocator,
        annotations,
        &commands,
        true,
        true
    );
    
    var test_annotations = std.StringHashMap([]const u8).init(allocator);
    defer test_annotations.deinit();
    try test_annotations.put("test.annotation", "value");
    
    // Перевіряємо відповідність умов
    try testing.expect(hook.shouldExecute(
        test_annotations,
        "test-cmd",
        true,
        true
    ));
    
    try testing.expect(!hook.shouldExecute(
        test_annotations,
        "wrong-cmd",
        true,
        true
    ));
}

test "CrioHook to OCI hook conversion" {
    const allocator = testing.allocator;
    
    const args = [_][]const u8{"--test"};
    const env = [_][]const u8{"TEST_ENV=value"};
    
    var hook = try crio.CrioHook.init(
        allocator,
        "/usr/bin/test-hook",
        &args,
        &env,
        30,
        .prestart
    );
    defer hook.deinit(allocator);
    
    const oci_hook = hook.toOciHook();
    
    try testing.expectEqualStrings("/usr/bin/test-hook", oci_hook.path);
    try testing.expectEqualStrings("--test", oci_hook.args[0]);
    try testing.expectEqualStrings("TEST_ENV=value", oci_hook.env[0]);
    try testing.expect(oci_hook.timeout.? == 30);
}