const std = @import("std");
const Allocator = std.mem.Allocator;
const logger = std.log.scoped(.pod_manager);
const network = @import("network");
const proxmox = @import("../proxmox/api.zig");
const ProxmoxContainer = @import("../proxmox/lxc/container.zig").ProxmoxContainer;
const Pod = @import("pod.zig").Pod;

pub const PodError = error{
    CreationFailed,
    NetworkSetupFailed,
    ContainerCreationFailed,
    ContainerStartFailed,
    InvalidState,
    NotFound,
};

pub const PodManager = struct {
    pods: std.StringHashMap(*Pod),
    network_manager: *network.NetworkManager,
    proxmox_api: *proxmox.ProxmoxApi,
    allocator: Allocator,

    const Self = @This();

    pub fn init(allocator: Allocator, net_manager: *network.NetworkManager, api: *proxmox.ProxmoxApi) !Self {
        return Self{
            .pods = std.StringHashMap(*Pod).init(allocator),
            .network_manager = net_manager,
            .proxmox_api = api,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        var it = self.pods.iterator();
        while (it.next()) |entry| {
            const pod = entry.value_ptr.*;
            for (pod.containers.items) |container| {
                container.deinit();
            }
            pod.deinit();
            self.allocator.destroy(pod);
        }
        self.pods.deinit();
    }

    pub fn createPod(self: *Self, spec: Pod.PodSpec) !void {
        const pod_name = spec.metadata.name;

        if (self.pods.get(pod_name)) |_| {
            logger.err("Pod {s} already exists", .{pod_name});
            return error.PodAlreadyExists;
        }

        var pod = try self.allocator.create(Pod);
        errdefer self.allocator.destroy(pod);

        pod.* = try Pod.init(
            self.allocator,
            spec,
            self.network_manager,
            self.proxmox_api,
        );
        errdefer pod.deinit();

        try pod.create();
        try self.pods.put(pod_name, pod);
    }

    pub fn deletePod(self: *Self, pod_id: []const u8) !void {
        logger.info("Deleting pod: {s}", .{pod_id});

        const pod = self.pods.get(pod_id) orelse return PodError.NotFound;

        // Зупиняємо всі контейнери
        for (pod.containers.items) |container| {
            if (container.getState() == .Running) {
                try container.stop();
            }
        }

        // Видаляємо Pod
        _ = self.pods.remove(pod_id);
        pod.deinit();

        logger.info("Pod deleted successfully: {s}", .{pod_id});
    }

    pub fn startPod(self: *Self, pod_id: []const u8) !void {
        logger.info("Starting pod: {s}", .{pod_id});

        const pod = self.pods.get(pod_id) orelse return PodError.NotFound;

        // Запускаємо всі контейнери
        for (pod.containers.items) |container| {
            try container.start();
        }

        logger.info("Pod started successfully: {s}", .{pod_id});
    }

    pub fn stopPod(self: *Self, pod_id: []const u8) !void {
        logger.info("Stopping pod: {s}", .{pod_id});

        const pod = self.pods.get(pod_id) orelse return PodError.NotFound;

        // Зупиняємо всі контейнери
        for (pod.containers.items) |container| {
            try container.stop();
        }

        logger.info("Pod stopped successfully: {s}", .{pod_id});
    }

    pub fn getPod(self: *Self, pod_id: []const u8) ?*Pod {
        return self.pods.get(pod_id);
    }
};
