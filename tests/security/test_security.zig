const std = @import("std");
const testing = std.testing;
const container = @import("proxmox/container.zig");

test "Container security profiles" {
    const allocator = testing.allocator;

    // Test AppArmor profile
    var container_config = try container.Config.init(allocator);
    defer container_config.deinit();

    try container_config.setAppArmorProfile("lxc-container-default");
    try testing.expectEqualStrings("lxc-container-default", container_config.getAppArmorProfile());

    // Test SELinux context
    try container_config.setSELinuxContext("system_u:system_r:container_t:s0");
    try testing.expectEqualStrings("system_u:system_r:container_t:s0", container_config.getSELinuxContext());

    // Test seccomp rules
    const seccomp_rules = [_][]const u8{
        "chmod",
        "chown",
        "mount",
        "umount",
    };
    try container_config.setSeccompRules(&seccomp_rules);
    const rules = container_config.getSeccompRules();
    try testing.expect(rules.len == seccomp_rules.len);

    // Test capabilities
    const caps = [_][]const u8{
        "CAP_NET_BIND_SERVICE",
        "CAP_SYS_ADMIN",
    };
    try container_config.setCapabilities(&caps);
    const container_caps = container_config.getCapabilities();
    try testing.expect(container_caps.len == caps.len);
}

test "Security enforcement" {
    const allocator = testing.allocator;

    var container_config = try container.Config.init(allocator);
    defer container_config.deinit();

    // Test that dangerous operations are blocked
    try container_config.setAppArmorProfile("lxc-container-default");
    try container_config.setSeccompRules(&[_][]const u8{ "chmod", "chown" });

    // Try to perform a blocked operation
    const result = container_config.performOperation("mount");
    try testing.expectError(container.Error.OperationNotAllowed, result);

    // Try to perform an allowed operation
    const allowed_result = container_config.performOperation("chmod");
    try testing.expect(allowed_result == null);
}

test "Security isolation" {
    const allocator = testing.allocator;

    var container1 = try container.Config.init(allocator);
    defer container1.deinit();
    var container2 = try container.Config.init(allocator);
    defer container2.deinit();

    // Set different security profiles
    try container1.setAppArmorProfile("lxc-container-default");
    try container2.setAppArmorProfile("lxc-container-custom");

    // Verify isolation
    try testing.expect(!std.mem.eql(u8, container1.getAppArmorProfile(), container2.getAppArmorProfile()));

    // Test that containers can't access each other's resources
    const result = container1.accessResource(container2);
    try testing.expectError(container.Error.AccessDenied, result);
}
