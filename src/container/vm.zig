const std = @import("std");
const Allocator = std.mem.Allocator;
const log = @import("logger").log;
const types = @import("types");
const Error = @import("error").Error;
const Container = @import("container").Container;
const ContainerConfig = @import("container").ContainerConfig;
const ContainerType = @import("container").ContainerType;

pub fn createVmContainer(allocator: Allocator, config: ContainerConfig) !*Container {
    var vm_config = config;
    vm_config.type = .vm;
    return try Container.init(allocator, vm_config);
}

pub fn startVmContainer(container: *Container) !void {
    log.info("Starting VM container: {s}", .{container.config.id});
    
    // TODO: Implement VM container start
    // 1. Create VM configuration
    // 2. Initialize VM
    // 3. Start VM
    // 4. Update state and PID
    
    container.state = .running;
}

pub fn stopVmContainer(container: *Container) !void {
    log.info("Stopping VM container: {s}", .{container.config.id});
    
    // TODO: Implement VM container stop
    // 1. Stop VM
    // 2. Cleanup resources
    // 3. Update state
    
    container.state = .stopped;
} 