const std = @import("std");
const grpc = @cImport({
    @cInclude("grpc/grpc.h");
    @cInclude("grpc/status.h");
});
const proxmox = @import("proxmox");
const grpc_service = @import("grpc_service");
const fix = @import("fix");
const mem = std.mem;
const fmt = std.fmt;
const Allocator = std.mem.Allocator;

pub const Service = struct {
    allocator: Allocator,
    server: *grpc.grpc_server,
    pod_manager: *PodManager,
    container_manager: *ContainerManager,
    proxmox_client: *proxmox.Client,
    runtime_service: *grpc_service.RuntimeService,

    pub fn init(options: struct {
        allocator: Allocator,
        proxmox_client: *proxmox.Client,
    }) !Service {
        const pod_manager = try PodManager.init(options.allocator);
        const container_manager = try ContainerManager.init(options.allocator, options.proxmox_client);
        const runtime_service = try grpc_service.RuntimeService.init(options.allocator, &Service{
            .allocator = options.allocator,
            .server = undefined,
            .pod_manager = pod_manager,
            .container_manager = container_manager,
            .proxmox_client = options.proxmox_client,
            .runtime_service = undefined,
        });

        return Service{
            .allocator = options.allocator,
            .server = undefined,
            .pod_manager = pod_manager,
            .container_manager = container_manager,
            .proxmox_client = options.proxmox_client,
            .runtime_service = runtime_service,
        };
    }

    pub fn deinit(self: *Service) void {
        self.pod_manager.deinit();
        self.container_manager.deinit();
        self.runtime_service.deinit();
        // Cleanup gRPC server
    }

    pub fn start(self: *Service) !void {
        // Initialize gRPC server
        self.server = grpc.grpc_server_create(grpc.grpc_channel_args_create(0, null));
        if (self.server == null) {
            return error.GRPCInitFailed;
        }

        // Register runtime service
        try self.runtime_service.start();

        // Start server
        const address = try fmt.allocPrint(self.allocator, "unix:///var/run/proxmox-lxcri.sock", .{});
        defer self.allocator.free(address);

        const result = grpc.grpc_server_add_secure_http2_port(self.server, address.ptr, null);
        if (result == 0) {
            return error.GRPCBindFailed;
        }

        grpc.grpc_server_start(self.server);
    }
};

pub const PodManager = struct {
    allocator: Allocator,
    pods: std.StringHashMap(Pod),
    container_manager: *ContainerManager,

    pub fn init(allocator: Allocator, container_manager: *ContainerManager) !PodManager {
        return PodManager{
            .allocator = allocator,
            .pods = std.StringHashMap(Pod).init(allocator),
            .container_manager = container_manager,
        };
    }

    pub fn deinit(self: *PodManager) void {
        var it = self.pods.iterator();
        while (it.next()) |entry| {
            const pod = entry.value_ptr;
            pod.deinit();
        }
        self.pods.deinit();
    }

    pub fn createPod(self: *PodManager, spec: PodSpec) !Pod {
        // Create containers for the pod
        const containers = try self.allocator.alloc(Container, spec.containers.len);
        errdefer self.allocator.free(containers);

        for (spec.containers, 0..) |container_spec, i| {
            containers[i] = try self.container_manager.createContainer(container_spec);
        }

        // Create pod instance
        const pod = try Pod.init(self.allocator, spec, containers);
        errdefer pod.deinit();

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

    pub fn getPodStatus(self: *PodManager, pod_id: []const u8) !PodStatus {
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

    pub fn listPods(self: *PodManager) ![]Pod {
        const pods = try self.allocator.alloc(Pod, self.pods.count());
        var i: usize = 0;
        var it = self.pods.iterator();
        while (it.next()) |entry| {
            pods[i] = entry.value_ptr.*;
            i += 1;
        }
        return pods;
    }
};

pub const Pod = struct {
    id: []const u8,
    name: []const u8,
    namespace: []const u8,
    status: PodStatus,
    containers: []Container,

    pub fn init(allocator: Allocator, spec: PodSpec, containers: []Container) !Pod {
        const id = try fmt.allocPrint(allocator, "pod-{s}-{s}", .{ spec.namespace, spec.name });
        errdefer allocator.free(id);

        return Pod{
            .id = id,
            .name = spec.name,
            .namespace = spec.namespace,
            .status = .pending,
            .containers = containers,
        };
    }

    pub fn deinit(self: *Pod) void {
        self.allocator.free(self.id);
    }
};

pub const ContainerManager = struct {
    allocator: Allocator,
    containers: std.StringHashMap(Container),
    proxmox_client: *proxmox.Client,

    pub fn init(allocator: Allocator, proxmox_client: *proxmox.Client) !ContainerManager {
        return ContainerManager{
            .allocator = allocator,
            .containers = std.StringHashMap(Container).init(allocator),
            .proxmox_client = proxmox_client,
        };
    }

    pub fn deinit(self: *ContainerManager) void {
        var it = self.containers.iterator();
        while (it.next()) |entry| {
            const container = entry.value_ptr;
            container.deinit();
        }
        self.containers.deinit();
    }

    pub fn createContainer(self: *ContainerManager, spec: ContainerSpec) !Container {
        // Convert ContainerSpec to LXCConfig
        const lxc_config = try fix.specToLXCConfig(spec);
        defer lxc_config.deinit();

        // Create LXC container via Proxmox API
        const lxc_container = try self.proxmox_client.createLXC(lxc_config);

        // Create Container instance
        const container = try Container.init(self.allocator, spec, lxc_container.vmid);
        errdefer container.deinit();

        // Store container in map
        try self.containers.put(container.id, container);

        return container;
    }

    pub fn deleteContainer(self: *ContainerManager, container_id: []const u8) !void {
        if (self.containers.get(container_id)) |container| {
            // Stop container if running
            if (container.status == .running) {
                try self.proxmox_client.stopLXC(container.vmid);
            }

            // Delete container via Proxmox API
            try self.proxmox_client.deleteLXC(container.vmid);

            // Remove from map
            _ = self.containers.remove(container_id);
        }
    }

    pub fn startContainer(self: *ContainerManager, container_id: []const u8) !void {
        if (self.containers.get(container_id)) |container| {
            try self.proxmox_client.startLXC(container.vmid);
            container.status = .running;
        }
    }

    pub fn stopContainer(self: *ContainerManager, container_id: []const u8) !void {
        if (self.containers.get(container_id)) |container| {
            try self.proxmox_client.stopLXC(container.vmid);
            container.status = .stopped;
        }
    }

    pub fn getContainerStatus(self: *ContainerManager, container_id: []const u8) !ContainerStatus {
        if (self.containers.get(container_id)) |container| {
            const lxc_status = try self.proxmox_client.getLXCStatus(container.vmid);
            return fix.lxcStatusToContainerStatus(lxc_status);
        }
        return error.ContainerNotFound;
    }

    pub fn listContainers(self: *ContainerManager) ![]Container {
        const containers = try self.allocator.alloc(Container, self.containers.count());
        var i: usize = 0;
        var it = self.containers.iterator();
        while (it.next()) |entry| {
            containers[i] = entry.value_ptr.*;
            i += 1;
        }
        return containers;
    }
};

pub const Container = struct {
    id: []const u8,
    name: []const u8,
    status: ContainerStatus,
    spec: ContainerSpec,
    vmid: u32,

    pub fn init(allocator: Allocator, spec: ContainerSpec, vmid: u32) !Container {
        const id = try fmt.allocPrint(allocator, "ct-{d}", .{vmid});
        errdefer allocator.free(id);

        return Container{
            .id = id,
            .name = spec.name,
            .status = .created,
            .spec = spec,
            .vmid = vmid,
        };
    }

    pub fn deinit(self: *Container) void {
        self.allocator.free(self.id);
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
