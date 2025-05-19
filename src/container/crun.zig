const std = @import("std");
const Allocator = std.mem.Allocator;
const log = @import("logger").log;
const types = @import("types");
const Error = @import("error").Error;
const Container = @import("container").Container;
const ContainerConfig = @import("container").ContainerConfig;
const ContainerType = @import("container").ContainerType;

pub fn createCrunContainer(allocator: Allocator, config: ContainerConfig) !*Container {
    var crun_config = config;
    crun_config.type = .crun;
    return try Container.init(allocator, crun_config);
}

pub fn startCrunContainer(container: *Container) !void {
    log.info("Starting crun container: {s}", .{container.config.id});
    
    // TODO: Implement actual crun container start
    // 1. Create OCI bundle
    // 2. Initialize container
    // 3. Start container using crun
    // 4. Update state and PID
    
    container.state = .running;
}

pub fn stopCrunContainer(container: *Container) !void {
    log.info("Stopping crun container: {s}", .{container.config.id});
    
    // TODO: Implement actual crun container stop
    // 1. Stop container using crun
    // 2. Cleanup resources
    // 3. Update state
    
    container.state = .stopped;
} 