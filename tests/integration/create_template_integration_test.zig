const std = @import("std");
const template_ops = @import("../src/proxmox/template/operations.zig");
const types = @import("../src/common/types.zig");

// Mock HTTP client for testing
const MockClient = struct {
    allocator: std.mem.Allocator,
    logger: *types.LogContext,
    upload_should_fail: bool,
    upload_fail_count: u32,
    upload_fail_threshold: u32,
    list_should_find_template: bool,
    template_name: []const u8,
    call_count: u32 = 0,

    pub fn init(allocator: std.mem.Allocator, logger: *types.LogContext, upload_should_fail: bool, upload_fail_threshold: u32, list_should_find_template: bool, template_name: []const u8) MockClient {
        return MockClient{
            .allocator = allocator,
            .logger = logger,
            .upload_should_fail = upload_should_fail,
            .upload_fail_count = 0,
            .upload_fail_threshold = upload_fail_threshold,
            .list_should_find_template = list_should_find_template,
            .template_name = template_name,
        };
    }

    pub fn deinit(self: *MockClient) void {
        _ = self;
    }
};

// Mock upload function that simulates ConnectionResetByPeer errors
fn mockUpload(client: *MockClient, upload_path: []const u8, body: []const u8, content_type: []const u8) ![]u8 {
    _ = upload_path;
    _ = body;
    _ = content_type;
    
    client.call_count += 1;
    
    if (client.upload_should_fail and client.upload_fail_count < client.upload_fail_threshold) {
        client.upload_fail_count += 1;
        try client.logger.warn("Mock upload failure {d}/{d}", .{ client.upload_fail_count, client.upload_fail_threshold });
        return error.ConnectionResetByPeer;
    }
    
    // Simulate successful upload response
    const response = "{\"data\":{\"size\":12345}}";
    return try client.allocator.dupe(u8, response);
}

// Mock list function that simulates template listing
fn mockList(client: *MockClient) ![]template_ops.TemplateInfo {
    if (client.list_should_find_template) {
        const template = try template_ops.TemplateInfo.init(
            client.allocator,
            client.template_name,
            12345,
            "tar.zst",
            "debian",
            "amd64",
            "12",
            true,
        );
        const templates = try client.allocator.alloc(template_ops.TemplateInfo, 1);
        templates[0] = template;
        return templates;
    }
    
    // Return empty list
    return try client.allocator.alloc(template_ops.TemplateInfo, 0);
}

test "createTemplateFromRootfs positive case - successful upload and list" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Create temporary rootfs directory
    var tmp = try std.testing.tmpDir(.{}); 
    defer tmp.cleanup();
    const root = tmp.dir;
    try root.makePath("etc");
    var f = try root.createFile("etc/os-release", .{}); 
    defer f.close();
    try f.writeAll("ID=debian\nVERSION_ID=12\n");
    
    try root.makePath("proc");
    var f2 = try root.createFile("proc/version", .{}); 
    defer f2.close();
    try f2.writeAll("Linux version x86_64\n");
    
    // Create logger
    var logger = try types.LogContext.init(allocator, std.io.getStdOut().writer(), .debug, "test");
    defer logger.deinit();
    
    // Create mock client
    var mock_client = MockClient.init(allocator, &logger, false, 0, true, "test-template");
    defer mock_client.deinit();
    
    // Create DI dependencies
    const deps = template_ops.Deps{
        .upload = mockUpload,
        .list = mockList,
    };
    
    const rootfs_path = try std.fmt.allocPrint(allocator, "{s}", .{tmp.path}); 
    defer allocator.free(rootfs_path);
    
    // Test successful template creation
    const result = try template_ops.createTemplateFromRootfsWithDeps(&mock_client, rootfs_path, "test-template", deps);
    defer result.deinit(allocator);
    
    // Verify result
    try std.testing.expectEqualStrings("test-template", result.name);
    try std.testing.expectEqual(@as(u64, 12345), result.size);
    try std.testing.expectEqualStrings("tar.zst", result.format);
    try std.testing.expectEqualStrings("debian", result.os_type);
    try std.testing.expectEqualStrings("amd64", result.arch);
    try std.testing.expectEqualStrings("12", result.version);
}

test "createTemplateFromRootfs negative case - upload fails with ConnectionResetByPeer, retries exhausted" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Create temporary rootfs directory
    var tmp = try std.testing.tmpDir(.{}); 
    defer tmp.cleanup();
    const root = tmp.dir;
    try root.makePath("etc");
    var f = try root.createFile("etc/os-release", .{}); 
    defer f.close();
    try f.writeAll("ID=debian\nVERSION_ID=12\n");
    
    try root.makePath("proc");
    var f2 = try root.createFile("proc/version", .{}); 
    defer f2.close();
    try f2.writeAll("Linux version x86_64\n");
    
    // Create logger
    var logger = try types.LogContext.init(allocator, std.io.getStdOut().writer(), .debug, "test");
    defer logger.deinit();
    
    // Create mock client that fails upload and doesn't find template in list
    var mock_client = MockClient.init(allocator, &logger, true, 10, false, "test-template");
    defer mock_client.deinit();
    
    // Create DI dependencies
    const deps = template_ops.Deps{
        .upload = mockUpload,
        .list = mockList,
    };
    
    const rootfs_path = try std.fmt.allocPrint(allocator, "{s}", .{tmp.path}); 
    defer allocator.free(rootfs_path);
    
    // Test should fail with TemplateCreationFailed
    try std.testing.expectError(error.TemplateCreationFailed, 
        template_ops.createTemplateFromRootfsWithDeps(&mock_client, rootfs_path, "test-template", deps));
}

test "createTemplateFromRootfs negative case - tar archive creation fails" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Create logger
    var logger = try types.LogContext.init(allocator, std.io.getStdOut().writer(), .debug, "test");
    defer logger.deinit();
    
    // Create mock client
    var mock_client = MockClient.init(allocator, &logger, false, 0, true, "test-template");
    defer mock_client.deinit();
    
    // Create DI dependencies
    const deps = template_ops.Deps{
        .upload = mockUpload,
        .list = mockList,
    };
    
    // Test with non-existent rootfs path - should fail during tar creation
    try std.testing.expectError(error.TemplateCreationFailed, 
        template_ops.createTemplateFromRootfsWithDeps(&mock_client, "/non/existent/path", "test-template", deps));
}

test "createTemplateFromRootfs fallback case - upload fails but template found in list" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Create temporary rootfs directory
    var tmp = try std.testing.tmpDir(.{}); 
    defer tmp.cleanup();
    const root = tmp.dir;
    try root.makePath("etc");
    var f = try root.createFile("etc/os-release", .{}); 
    defer f.close();
    try f.writeAll("ID=debian\nVERSION_ID=12\n");
    
    try root.makePath("proc");
    var f2 = try root.createFile("proc/version", .{}); 
    defer f2.close();
    try f2.writeAll("Linux version x86_64\n");
    
    // Create logger
    var logger = try types.LogContext.init(allocator, std.io.getStdOut().writer(), .debug, "test");
    defer logger.deinit();
    
    // Create mock client that fails upload but finds template in list (simulating curl fallback success)
    var mock_client = MockClient.init(allocator, &logger, true, 5, true, "test-template.tar.zst");
    defer mock_client.deinit();
    
    // Create DI dependencies
    const deps = template_ops.Deps{
        .upload = mockUpload,
        .list = mockList,
    };
    
    const rootfs_path = try std.fmt.allocPrint(allocator, "{s}", .{tmp.path}); 
    defer allocator.free(rootfs_path);
    
    // Test should succeed despite upload failures because template is found in list
    const result = try template_ops.createTemplateFromRootfsWithDeps(&mock_client, rootfs_path, "test-template", deps);
    defer result.deinit(allocator);
    
    // Verify result
    try std.testing.expectEqualStrings("test-template.tar.zst", result.name);
    try std.testing.expectEqual(@as(u64, 12345), result.size);
}