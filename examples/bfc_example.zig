// BFC (Binary File Container) usage example
// This example demonstrates how to use BFC for container operations

const std = @import("std");
const Allocator = std.mem.Allocator;
const logger_mod = @import("logger");
const bfc = @import("bfc");
const oci = @import("oci");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Initialize logger
    var logger = try logger_mod.Logger.init(allocator, .info);
    defer logger.deinit();
    
    try logger.info("BFC Example: Creating and using BFC containers", .{});
    
    // Example 1: Create a BFC container
    try createBFCContainer(allocator, &logger);
    
    // Example 2: Use BFC backend plugin
    try useBFCBackend(allocator, &logger);
    
    try logger.info("BFC Example completed successfully", .{});
}

fn createBFCContainer(allocator: Allocator, logger: *logger_mod.Logger) !void {
    try logger.info("=== Example 1: Creating BFC Container ===", .{});
    
    // Create BFC container
    var container = try bfc.BFCContainer.init(allocator, logger, "/tmp/example.bfc");
    defer container.deinit();
    
    // Create the container
    try container.create();
    
    // Add some files
    try container.addFile("hello.txt", "Hello, BFC World!", 0o644);
    try container.addFile("config.json", "{\"version\": \"1.0\"}", 0o644);
    try container.addDir("data", 0o755);
    
    // Finish the container
    try container.finish();
    
    try logger.info("BFC container created successfully", .{});
    
    // Open and list contents
    try container.open();
    try container.list(bfcListCallback, null);
    
    try logger.info("BFC container contents listed", .{});
}

fn useBFCBackend(allocator: Allocator, logger: *logger_mod.Logger) !void {
    try logger.info("=== Example 2: Using BFC Backend Plugin ===", .{});
    
    // Initialize backend manager
    var backend_manager = try oci.backend.BackendManager.init(allocator, logger);
    defer backend_manager.deinit();
    
    // Initialize plugins
    try backend_manager.initializePlugins();
    
    // Get BFC backend
    const bfc_backend = backend_manager.getBackend(.bfc);
    if (bfc_backend) |backend| {
        try logger.info("BFC backend is available", .{});
        
        // Create a test bundle
        try createTestBundle("/tmp/bfc-test-bundle");
        
        // Create container using BFC backend
        try backend.createContainer(backend, "bfc-test-container", "/tmp/bfc-test-bundle", null);
        
        // Start container
        try backend.startContainer(backend, "bfc-test-container");
        
        // Get container state
        const state = try backend.getContainerState(backend, "bfc-test-container");
        try logger.info("Container state: {}", .{state});
        
        // Get container info
        const info = try backend.getContainerInfo(backend, "bfc-test-container");
        defer info.deinit();
        
        try logger.info("Container info - ID: {s}, Name: {s}, State: {}", .{ info.id, info.name, info.state });
        
        // Stop container
        try backend.stopContainer(backend, "bfc-test-container");
        
        // Delete container
        try backend.deleteContainer(backend, "bfc-test-container");
        
        try logger.info("BFC backend operations completed successfully", .{});
    } else {
        try logger.warn("BFC backend is not available", .{});
    }
}

fn createTestBundle(bundle_path: []const u8) !void {
    // Create bundle directory
    try std.fs.makeDirAbsolute(bundle_path);
    
    // Create config.json
    const config_path = try std.fmt.allocPrint(std.heap.page_allocator, "{s}/config.json", .{bundle_path});
    defer std.heap.page_allocator.free(config_path);
    
    const config_file = try std.fs.createFileAbsolute(config_path, .{});
    defer config_file.close();
    
    try config_file.writeAll(
        \\{
        \\  "ociVersion": "1.0.0",
        \\  "process": {
        \\    "terminal": false,
        \\    "user": {
        \\      "uid": 0,
        \\      "gid": 0
        \\    },
        \\    "args": ["/bin/sh"],
        \\    "env": ["PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"]
        \\  },
        \\  "root": {
        \\    "path": "rootfs"
        \\  }
        \\}
    );
    
    // Create rootfs directory
    const rootfs_path = try std.fmt.allocPrint(std.heap.page_allocator, "{s}/rootfs", .{bundle_path});
    defer std.heap.page_allocator.free(rootfs_path);
    
    try std.fs.makeDirAbsolute(rootfs_path);
    
    // Create a simple shell script
    const script_path = try std.fmt.allocPrint(std.heap.page_allocator, "{s}/bin", .{rootfs_path});
    defer std.heap.page_allocator.free(script_path);
    
    try std.fs.makeDirAbsolute(script_path);
    
    const sh_path = try std.fmt.allocPrint(std.heap.page_allocator, "{s}/sh", .{script_path});
    defer std.heap.page_allocator.free(sh_path);
    
    const sh_file = try std.fs.createFileAbsolute(sh_path, .{});
    defer sh_file.close();
    
    try sh_file.writeAll("#!/bin/sh\necho 'Hello from BFC container!'\n");
    
    // Make it executable
    try std.fs.chmodAbsolute(sh_path, 0o755);
}

fn bfcListCallback(path: [*c]const u8, info: [*c]const bfc.c.bfc_file_info_t, userdata: ?*anyopaque) c_int {
    _ = userdata;
    
    const path_str = std.mem.sliceTo(@as([*:0]u8, @ptrCast(@constCast(path))), 0);
    const size = info.*.size;
    const mode = info.*.mode;
    
    std.debug.print("File: {s}, Size: {}, Mode: {o}\n", .{ path_str, size, mode });
    
    return 0;
}
