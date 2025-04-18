const std = @import("std");

comptime {
    _ = @import("test_crio_hooks.zig");
    _ = @import("test_lxc.zig");
    _ = @import("test_runtime_service.zig");
    _ = @import("runtime/mod.zig");
}

test {
    std.testing.refAllDecls(@This());
} 