const std = @import("std");

pub const TestStruct = struct {
    field1: ?[]const u8,
    field2: ?i64,
    
    pub fn init() TestStruct {
        return .{
            .field1 = null,
            .field2 = null,
        };
    }
};

test "test struct" {
    const test_struct = TestStruct.init();
    try std.testing.expect(test_struct.field1 == null);
    try std.testing.expect(test_struct.field2 == null);
}
