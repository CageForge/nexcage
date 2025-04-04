const std = @import("std");
const grpc = @cImport({
    @cInclude("grpc/grpc.h");
    @cInclude("grpc/status.h");
});
const proxmox = @import("proxmox");
const types = @import("types");
const fix = @import("fix");
const mem = std.mem;
const fmt = std.fmt;
const Allocator = std.mem.Allocator;

pub const Service = struct {
    allocator: Allocator,
    server: ?*grpc.grpc_server,
    pod_manager: *PodManager,
    container_manager: *ContainerManager,
    proxmox_client: *proxmox.Client,

    pub fn init(options: struct {
        allocator: Allocator,
        proxmox_client: *proxmox.Client,
    }) !Service {
        const container_manager = try options.allocator.create(ContainerManager);
        container_manager.* = try ContainerManager.init(options.allocator, options.proxmox_client);
        errdefer options.allocator.destroy(container_manager);

        const pod_manager = try options.allocator.create(PodManager);
        pod_manager.* = try PodManager.init(options.allocator, container_manager);
        errdefer options.allocator.destroy(pod_manager);

        return Service{
            .allocator = options.allocator,
            .server = null,
            .pod_manager = pod_manager,
            .container_manager = container_manager,
            .proxmox_client = options.proxmox_client,
        };
    }

    pub fn deinit(self: *Service) void {
        self.pod_manager.deinit();
        self.allocator.destroy(self.pod_manager);
        self.container_manager.deinit();
        self.allocator.destroy(self.container_manager);
        // Cleanup gRPC server
    }

    pub fn start(self: *Service) !void {
        // Initialize gRPC server
        self.server = grpc.grpc_server_create(null, null);
        if (self.server == null) {
            return error.GRPCInitFailed;
        }

        // Start server
        const address = try fmt.allocPrint(self.allocator, "unix:///var/run/proxmox-lxcri.sock", .{});
        defer self.allocator.free(address);

        const result = grpc.grpc_server_add_http2_port(self.server.?, address.ptr, null);
        if (result == 0) {
            return error.GRPCBindFailed;
        }

        grpc.grpc_server_start(self.server.?);
    }
};

pub const PodManager = struct {
    allocator: Allocator,
    pods: std.StringHashMap(types.Pod),
    container_manager: *ContainerManager,

    pub fn init(allocator: Allocator, container_manager: *ContainerManager) !PodManager {
        return PodManager{
            .allocator = allocator,
            .pods = std.StringHashMap(types.Pod).init(allocator),
            .container_manager = container_manager,
        };
    }

    pub fn deinit(self: *PodManager) void {
        var it = self.pods.iterator();
        while (it.next()) |entry| {
            const pod = entry.value_ptr;
            pod.deinit(self.allocator);
        }
        self.pods.deinit();
    }

    pub fn createPod(self: *PodManager, spec: types.PodSpec) !types.Pod {
        // Create containers for the pod
        const containers = try self.allocator.alloc(types.Container, spec.containers.len);
        errdefer self.allocator.free(containers);

        for (spec.containers, 0..) |container_spec, i| {
            containers[i] = try self.container_manager.createContainer(container_spec);
        }

        // Create pod instance
        const pod = try types.Pod.init(self.allocator, spec, containers);
        errdefer pod.deinit(self.allocator);

        // Store pod in map
        try self.pods.put(pod.id, pod);

        return pod;
    }

    pub fn deletePod(self: *PodManager, pod_id: []const u8) !void {
        if (self.pods.get(pod_id)) |pod| {
            // Delete all containers in the pod
            for (pod.containers) |container| {
                try self.container_manager.deleteContainer(container.id);
            }

            // Remove from map
            _ = self.pods.remove(pod_id);
        }
    }

    pub fn startPod(self: *PodManager, pod_id: []const u8) !void {
        if (self.pods.get(pod_id)) |pod| {
            // Start all containers in the pod
            for (pod.containers) |container| {
                try self.container_manager.startContainer(container.id);
            }
            pod.status = .running;
        }
    }

    pub fn stopPod(self: *PodManager, pod_id: []const u8) !void {
        if (self.pods.get(pod_id)) |pod| {
            // Stop all containers in the pod
            for (pod.containers) |container| {
                try self.container_manager.stopContainer(container.id);
            }
            pod.status = .stopped;
        }
    }

    pub fn getPodStatus(self: *PodManager, pod_id: []const u8) !types.PodStatus {
        if (self.pods.get(pod_id)) |pod| {
            // Check status of all containers
            var all_running = true;
            var all_stopped = true;

            for (pod.containers) |container| {
                const status = try self.container_manager.getContainerStatus(container.id);
                switch (status) {
                    .running => all_stopped = false,
                    .stopped => all_running = false,
                    .unknown => return .unknown,
                    .created => return .pending,
                }
            }

            if (all_running) return .running;
            if (all_stopped) return .stopped;
            return .unknown;
        }
        return error.PodNotFound;
    }

    pub fn listPods(self: *PodManager) ![]types.Pod {
        const pods = try self.allocator.alloc(types.Pod, self.pods.count());
        var i: usize = 0;
        var it = self.pods.iterator();
        while (it.next()) |entry| {
            pods[i] = entry.value_ptr.*;
            i += 1;
        }
        return pods;
    }
};

pub const ContainerManager = struct {
    allocator: Allocator,
    containers: std.StringHashMap(types.Container),
    proxmox_client: *proxmox.Client,

    pub fn init(allocator: Allocator, proxmox_client: *proxmox.Client) !ContainerManager {
        return ContainerManager{
            .allocator = allocator,
            .containers = std.StringHashMap(types.Container).init(allocator),
            .proxmox_client = proxmox_client,
        };
    }

    pub fn deinit(self: *ContainerManager) void {
        var it = self.containers.iterator();
        while (it.next()) |entry| {
            const container = entry.value_ptr;
            container.deinit(self.allocator);
        }
        self.containers.deinit();
    }

    pub fn createContainer(self: *ContainerManager, spec: types.ContainerSpec) !types.Container {
        // Create LXC container
        const lxc_config = try proxmox.LXCConfig.init(
            self.allocator,
            spec.name,
            spec.image,
            spec.command,
            spec.args,
            spec.env,
        );
        defer lxc_config.deinit();

        const lxc = try self.proxmox_client.createLXC(lxc_config);
        defer lxc.deinit();

        // Create container instance
        const container = types.Container{
            .id = try self.allocator.dupe(u8, lxc.id),
            .name = try self.allocator.dupe(u8, spec.name),
            .status = .created,
            .spec = spec,
        };

        // Store container in map
        try self.containers.put(container.id, container);

        return container;
    }

    pub fn deleteContainer(self: *ContainerManager, container_id: []const u8) !void {
        if (self.containers.get(container_id)) |_| {
            // Delete LXC container
            try self.proxmox_client.deleteLXC(container_id);

            // Remove from map
            _ = self.containers.remove(container_id);
        }
    }

    pub fn startContainer(self: *ContainerManager, container_id: []const u8) !void {
        if (self.containers.get(container_id)) |container| {
            // Start LXC container
            try self.proxmox_client.startLXC(container_id);
            container.status = .running;
        }
    }

    pub fn stopContainer(self: *ContainerManager, container_id: []const u8) !void {
        if (self.containers.get(container_id)) |container| {
            // Stop LXC container
            try self.proxmox_client.stopLXC(container_id);
            container.status = .stopped;
        }
    }

    pub fn getContainerStatus(self: *ContainerManager, container_id: []const u8) !types.ContainerStatus {
        if (self.containers.get(container_id)) |_| {
            // Get LXC container status
            const status = try self.proxmox_client.getLXCStatus(container_id);
            return switch (status) {
                .running => .running,
                .stopped => .stopped,
                else => .unknown,
            };
        }
        return error.ContainerNotFound;
    }

    pub fn listContainers(self: *ContainerManager) ![]types.Container {
        const containers = try self.allocator.alloc(types.Container, self.containers.count());
        var i: usize = 0;
        var it = self.containers.iterator();
        while (it.next()) |entry| {
            containers[i] = entry.value_ptr.*;
            i += 1;
        }
        return containers;
    }
};

pub const PodSpec = struct {
    name: []const u8,
    namespace: []const u8,
    containers: []ContainerSpec,
};

pub const ContainerSpec = struct {
    name: []const u8,
    image: []const u8,
    command: []const []const u8,
    args: []const []const u8,
    env: []const EnvVar,
};

pub const EnvVar = struct {
    name: []const u8,
    value: []const u8,
};

pub const PodStatus = enum {
    pending,
    running,
    succeeded,
    failed,
    unknown,
};

pub const ContainerStatus = enum {
    created,
    running,
    stopped,
    unknown,
};
