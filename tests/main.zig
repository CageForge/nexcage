const std = @import("std");

comptime {
    // Робочі тести
    _ = @import("test_api_and_connection.zig");
    _ = @import("test_lxc.zig");
    _ = @import("test_network.zig");
    _ = @import("test_container.zig");
    _ = @import("test_container_state.zig");
    _ = @import("test_oci_spec.zig");

    // Security tests
    _ = @import("security/test_security.zig");

    // Integration tests
    _ = @import("integration/test_concurrency.zig");
}

test {
    std.testing.refAllDecls(@This());
}
