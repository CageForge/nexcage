const std = @import("std");

comptime {
    _ = @import("test_hooks.zig");
    _ = @import("test_api_and_connection.zig");
    _ = @import("test_lxc.zig");
    _ = @import("test_network.zig");
    _ = @import("test_storage.zig");
    _ = @import("test_container.zig");
    _ = @import("test_container_state.zig");
    _ = @import("test_oci_spec.zig");
    
    // Security tests
    _ = @import("security/test_security.zig");
    
    // Integration tests
    _ = @import("integration/test_concurrency.zig");
    
    // OCI tests
    _ = @import("oci/mod.zig");
}

test {
    std.testing.refAllDecls(@This());
    _ = @import("network/dns_test.zig");
    _ = @import("network/port_forward_test.zig");
    _ = @import("oci/mod.zig");
    _ = @import("runtime/mod.zig");
    _ = @import("cri/runtime/service_test.zig");
} 