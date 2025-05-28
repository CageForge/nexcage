const std = @import("std");
const Allocator = std.mem.Allocator;
const log = @import("logger").log;
const types = @import("types");
const Error = @import("error").Error;
// const Container = @import("container").Container;
// const ContainerConfig = @import("container").ContainerConfig;
// const ContainerType = @import("container").ContainerType;
const crun = @import("crun");
const fs = std.fs;
const os = std.os;
const json = std.json;

const OCI_VERSION = "1.0.2";
const CONTAINER_ROOT = "/var/lib/containers";

pub const CrunManager = struct {
    // TODO: implement crun management logic
    // You can add fields for configuration, logger, etc.

    pub fn create(self: *CrunManager, ...) !void {
        // TODO: implement create logic
        _ = self;
    }

    pub fn start(self: *CrunManager, ...) !void {
        // TODO: implement start logic
        _ = self;
    }

    pub fn stop(self: *CrunManager, ...) !void {
        // TODO: implement stop logic
        _ = self;
    }
};

pub fn createCrunContainer(allocator: Allocator, config: ContainerConfig) !*Container {
    var crun_config = config;
    crun_config.type = .crun;
    return try Container.init(allocator, crun_config);
}

pub fn startCrunContainer(container: *Container) !void {
    log.info("Starting crun container: {s}", .{container.config.id});
    
    // Create OCI bundle
    try createOciBundle(container);
    
    // Initialize container using crun
    try crun.init(container.config.id);
    
    // Start container
    try crun.start(container.config.id);
    
    container.state = .running;
}

pub fn stopCrunContainer(container: *Container) !void {
    log.info("Stopping crun container: {s}", .{container.config.id});
    
    // Stop container using crun
    try crun.stop(container.config.id);
    
    // Cleanup resources
    try cleanupContainer(container);
    
    container.state = .stopped;
}

fn createOciBundle(container: *Container) !void {
    const bundle_path = try std.fmt.allocPrint(container.allocator, "{s}/{s}", .{CONTAINER_ROOT, container.config.id});
    defer container.allocator.free(bundle_path);

    // Create bundle directory
    try fs.makeDirAbsolute(bundle_path);
    try fs.makeDirAbsolute(try std.fmt.allocPrint(container.allocator, "{s}/rootfs", .{bundle_path}));
    defer container.allocator.free(try std.fmt.allocPrint(container.allocator, "{s}/rootfs", .{bundle_path}));

    // Create config.json
    const config_path = try std.fmt.allocPrint(container.allocator, "{s}/config.json", .{bundle_path});
    defer container.allocator.free(config_path);

    var config_file = try fs.createFileAbsolute(config_path, .{});
    defer config_file.close();

    // Create OCI config
    var config_json = std.ArrayList(u8).init(container.allocator);
    defer config_json.deinit();

    try json.stringify(.{
        .ociVersion = OCI_VERSION,
        .process = .{
            .terminal = false,
            .user = .{
                .uid = 0,
                .gid = 0,
            },
            .args = container.config.command,
            .env = container.config.env,
            .cwd = "/",
        },
        .root = .{
            .path = "rootfs",
            .readonly = false,
        },
        .hostname = container.config.hostname,
        .mounts = container.config.mounts,
        .linux = .{
            .namespaces = .{
                .{ .type = "pid" },
                .{ .type = "network" },
                .{ .type = "ipc" },
                .{ .type = "uts" },
                .{ .type = "mount" },
            },
            .resources = container.config.resources,
        },
    }, .{}, config_json.writer());

    try config_file.writeAll(config_json.items);
}

fn cleanupContainer(container: *Container) !void {
    const bundle_path = try std.fmt.allocPrint(container.allocator, "{s}/{s}", .{CONTAINER_ROOT, container.config.id});
    defer container.allocator.free(bundle_path);

    // Remove bundle directory
    try fs.deleteTreeAbsolute(bundle_path);
} 