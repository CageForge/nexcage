const std = @import("std");
const Allocator = std.mem.Allocator;
const log = @import("logger").log;
const types = @import("types");
const Error = @import("error").Error;
const Config = @import("config").Config;
const routing = @import("routing");

pub const ContainerType = enum {
    crun,
    lxc,
    vm,
};

pub const ContainerConfig = struct {
    allocator: Allocator,
    id: []const u8,
    name: []const u8,
    image: []const u8,
    command: []const []const u8,
    env: []const []const u8,
    working_dir: []const u8,
    user: []const u8,
    type: ContainerType,
    hostname: []const u8,
    mounts: []const types.Mount,
    resources: types.Resources,
    namespaces: []const routing.NamespaceConfig,
};

pub const ContainerState = enum {
    created,
    running,
    stopped,
    deleted,
};

pub const Container = struct {
    allocator: Allocator,
    config: ContainerConfig,
    state: ContainerState,
    pid: ?i32,

    pub fn init(allocator: Allocator, config: *ContainerConfig) !*Container {
        const container = try allocator.create(Container);
        container.* = Container{
            .allocator = allocator,
            .config = config.*,
            .state = .created,
            .pid = null,
        };
        return container;
    }

    pub fn deinit(self: *Container) void {
        self.allocator.destroy(self);
    }

    pub fn start(self: *Container, routing_config: *const routing.RoutingConfig) !void {
        // Визначаємо тип runtime на основі конфігурації роутингу
        const runtime_type = routing.selectRuntime(routing_config, self.config.id, self.config.namespaces);
        
        // Запускаємо контейнер відповідно до вибраного runtime
        switch (runtime_type) {
            .crun => try @import("crun_container").startCrunContainer(self),
            .lxc => try @import("lxc_container").startLxcContainer(self),
            .vm => try @import("vm_container").startVmContainer(self),
        }
    }

    pub fn stop(self: *Container, routing_config: *const routing.RoutingConfig) !void {
        // Визначаємо тип runtime на основі конфігурації роутингу
        const runtime_type = routing.selectRuntime(routing_config, self.config.id, self.config.namespaces);
        
        // Зупиняємо контейнер відповідно до вибраного runtime
        switch (runtime_type) {
            .crun => try @import("crun_container").stopCrunContainer(self),
            .lxc => try @import("lxc_container").stopLxcContainer(self),
            .vm => try @import("vm_container").stopVmContainer(self),
        }
    }

    pub fn getState(self: *Container) ContainerState {
        return self.state;
    }
};

pub fn createContainer(allocator: Allocator, config: *Config, container_config: ContainerConfig) !*Container {
    var new_config = container_config;
    new_config.type = config.getContainerType(container_config.name);
    return try Container.init(allocator, &new_config);
} 