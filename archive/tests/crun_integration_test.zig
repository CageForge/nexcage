const std = @import("std");
const testing = std.testing;
const CrunManager = @import("oci").crun.CrunManager;

test "simple test" {
    try testing.expect(1 == 1);
}

test "CrunManager import test" {
    // Just test that we can import CrunManager
    try testing.expect(@TypeOf(CrunManager) == @TypeOf(CrunManager));
}

test "CrunManager struct test" {
    // Test that CrunManager has the expected structure
    try testing.expect(@hasDecl(CrunManager, "init"));
    try testing.expect(@hasDecl(CrunManager, "deinit"));
    try testing.expect(@hasDecl(CrunManager, "createContainer"));
}

test "CrunManager fields test" {
    // Test that CrunManager has the expected fields
    try testing.expect(@hasField(CrunManager, "allocator"));
    try testing.expect(@hasField(CrunManager, "logger"));
    try testing.expect(@hasField(CrunManager, "root_path"));
    try testing.expect(@hasField(CrunManager, "log_path"));
}

test "CrunManager container state test" {
    // Test that ContainerState enum is available
    const ContainerState = @import("oci").crun.ContainerState;
    // Check that we can access the enum type
    _ = ContainerState.unknown;
    try testing.expect(true); // If we get here, the enum is accessible
}
