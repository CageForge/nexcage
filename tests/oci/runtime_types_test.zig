const std = @import("std");
const testing = std.testing;
const runtime_types = @import("runtime_types");

test "OciSpec validation" {
    const allocator = testing.allocator;
    
    // Create a valid OCI spec
    var spec = runtime_types.OciSpec{
        .ociVersion = try allocator.dupe(u8, "1.0.2"),
        .process = null,
        .root = null,
        .hostname = null,
        .mounts = null,
        .hooks = null,
        .annotations = null,
        .linux = null,
        .windows = null,
        .vm = null,
    };
    defer spec.deinit(allocator);
    
    // Test validation
    try spec.validate();
}

test "Process validation" {
    const allocator = testing.allocator;
    
    // Create a valid process
    var process = runtime_types.Process{
        .terminal = false,
        .consoleSize = null,
        .user = runtime_types.User{
            .uid = 0,
            .gid = 0,
            .additionalGids = null,
        },
        .args = try allocator.alloc([]const u8, 1),
        .env = null,
        .cwd = try allocator.dupe(u8, "/"),
        .capabilities = null,
        .rlimits = null,
        .noNewPrivileges = true,
        .apparmorProfile = null,
        .oomScoreAdj = null,
        .selinuxLabel = null,
    };
    defer process.deinit(allocator);
    
    // Set args
    process.args[0] = try allocator.dupe(u8, "/bin/sh");
    
    // Test validation
    try process.validate();
}

test "Root validation" {
    const allocator = testing.allocator;
    
    // Create a valid root
    var root = runtime_types.Root{
        .path = try allocator.dupe(u8, "/var/lib/containers/rootfs"),
        .readonly = false,
    };
    defer root.deinit(allocator);
    
    // Test validation
    try root.validate();
}

test "Mount validation" {
    const allocator = testing.allocator;
    
    // Create a valid mount
    var mount = runtime_types.Mount{
        .destination = try allocator.dupe(u8, "/proc"),
        .type = try allocator.dupe(u8, "proc"),
        .source = try allocator.dupe(u8, "proc"),
        .options = null,
    };
    defer mount.deinit(allocator);
    
    // Test validation
    try mount.validate();
}

test "User validation" {
    const allocator = testing.allocator;
    
    // Create a valid user
    var user = runtime_types.User{
        .uid = 1000,
        .gid = 1000,
        .additionalGids = null,
    };
    defer user.deinit(allocator);
    
    // Test validation
    try user.validate();
}

test "LinuxCapabilities validation" {
    const allocator = testing.allocator;
    
    // Create valid capabilities
    var caps = runtime_types.LinuxCapabilities{
        .bounding = null,
        .effective = null,
        .inheritable = null,
        .permitted = null,
        .ambient = null,
    };
    defer caps.deinit(allocator);
    
    // Test validation
    try caps.validate();
}

test "Linux validation" {
    const allocator = testing.allocator;
    
    // Create a valid Linux config
    var linux = runtime_types.Linux{
        .namespaces = null,
        .devices = null,
        .cgroupsPath = null,
        .resources = null,
        .seccomp = null,
        .rootfsPropagation = null,
        .maskedPaths = null,
        .readonlyPaths = null,
        .mountLabel = null,
        .intelRdt = null,
    };
    defer linux.deinit(allocator);
    
    // Test validation
    try linux.validate();
}

test "LinuxNamespace validation" {
    const allocator = testing.allocator;
    
    // Create a valid namespace
    var ns = runtime_types.LinuxNamespace{
        .type = try allocator.dupe(u8, "pid"),
        .path = null,
    };
    defer ns.deinit(allocator);
    
    // Test validation
    try ns.validate();
}

test "LinuxDevice validation" {
    const allocator = testing.allocator;
    
    // Create a valid device
    var device = runtime_types.LinuxDevice{
        .path = try allocator.dupe(u8, "/dev/null"),
        .type = try allocator.dupe(u8, "c"),
        .major = 1,
        .minor = 3,
        .fileMode = null,
        .uid = null,
        .gid = null,
    };
    defer device.deinit(allocator);
    
    // Test validation
    try device.validate();
}

test "LinuxResources validation" {
    const allocator = testing.allocator;
    
    // Create valid resources
    var resources = runtime_types.LinuxResources{
        .devices = null,
        .memory = null,
        .cpu = null,
        .pids = null,
        .network = null,
        .hugepageLimits = null,
        .blockIO = null,
    };
    defer resources.deinit(allocator);
    
    // Test validation
    try resources.validate();
}

test "LinuxSeccomp validation" {
    const allocator = testing.allocator;
    
    // Create valid seccomp
    var seccomp = runtime_types.LinuxSeccomp{
        .defaultAction = try allocator.dupe(u8, "SCMP_ACT_ALLOW"),
        .architectures = null,
        .flags = null,
        .syscalls = null,
    };
    defer seccomp.deinit(allocator);
    
    // Test validation
    try seccomp.validate();
}

test "Error cases" {
    const allocator = testing.allocator;
    
    // Test invalid OCI version
    var spec = runtime_types.OciSpec{
        .ociVersion = try allocator.dupe(u8, "1.0.0"),
        .process = null,
        .root = null,
        .hostname = null,
        .mounts = null,
        .hooks = null,
        .annotations = null,
        .linux = null,
        .windows = null,
        .vm = null,
    };
    defer spec.deinit(allocator);
    
    // Should fail validation
    spec.validate() catch |err| {
        try testing.expectEqual(runtime_types.OciError.UnsupportedOciVersion, err);
    } else {
        try testing.expect(false); // Should have failed
    }
}

test "Memory management" {
    const allocator = testing.allocator;
    
    // Create and destroy OCI spec to test memory management
    var spec = runtime_types.OciSpec{
        .ociVersion = try allocator.dupe(u8, "1.0.2"),
        .process = null,
        .root = null,
        .hostname = try allocator.dupe(u8, "test-container"),
        .mounts = null,
        .hooks = null,
        .annotations = null,
        .linux = null,
        .windows = null,
        .vm = null,
    };
    
    // This should not leak memory
    spec.deinit(allocator);
    
    // Test should pass without memory leaks
    try testing.expect(true);
}
