const std = @import("std");
const c = std.c;
const os = std.os;
const linux = os.linux;
const posix = std.posix;
const logger_mod = @import("logger");
const types = @import("types");
const fs = std.fs;
const builtin = @import("builtin");
const log = std.log;
const error_mod = @import("error");
const Error = error_mod.Error;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const StringHashMap = std.StringHashMap;
const json = std.json;
const http = std.http;
const Uri = std.Uri;
const HttpClient = std.http.Client;
const mem = std.mem;
const fmt = std.fmt;
const time = std.time;
const net = std.net;
const logger = logger_mod.Logger;
const Headers = std.http.Headers;
const HeaderIterator = std.http.Headers.Iterator;
const common = @import("common");

const API_PREFIX = "/api2/json";

const Options = struct {
    timeout: ?u64 = null,
};

const Client = @import("client.zig").Client;
const lxc_ops = @import("lxc/operations.zig");
const node_ops = @import("node/operations.zig");
const storage_ops = @import("storage/operations.zig");
const cluster_ops = @import("cluster/operations.zig");
const vm_ops = @import("vm/operations.zig");

pub const ContainerType = enum {
    lxc,
    qemu,
};

pub const ProxmoxClient = struct {
    allocator: Allocator,
    host: []const u8,
    port: u16,
    token: []const u8,
    node: []const u8,
    logger: *logger_mod.Logger,
    client: Client,

    pub fn init(allocator: Allocator, host: []const u8, port: u16, token: []const u8, node: []const u8, log_instance: *logger_mod.Logger) !ProxmoxClient {
        const host_copy = try allocator.dupe(u8, host);
        errdefer allocator.free(host_copy);

        const token_copy = try allocator.dupe(u8, token);
        errdefer allocator.free(token_copy);

        const node_copy = try allocator.dupe(u8, node);
        errdefer allocator.free(node_copy);

        const hosts = try allocator.alloc([]const u8, 1);
        errdefer {
            allocator.free(hosts);
        }
        hosts[0] = host_copy;

        const client = try Client.init(allocator, hosts, token_copy, log_instance, port, node_copy);
        errdefer {
            client.deinit();
            allocator.free(hosts);
        }

        return ProxmoxClient{
            .allocator = allocator,
            .host = host_copy,
            .port = port,
            .token = token_copy,
            .node = node_copy,
            .logger = log_instance,
            .client = client,
        };
    }

    pub fn deinit(self: *ProxmoxClient) void {
        self.client.deinit();
        self.allocator.free(self.host);
        self.allocator.free(self.token);
        self.allocator.free(self.node);
        self.allocator.free(self.client.hosts);
    }

    pub fn getProxmoxVMID(self: *ProxmoxClient, oci_container_id: []const u8) !u32 {
        const containers = try self.listContainers();
        defer {
            for (containers) |*container| {
                container.deinit(self.allocator);
            }
            self.allocator.free(containers);
        }

        for (containers) |container| {
            if (std.mem.eql(u8, container.name, oci_container_id)) {
                return container.vmid;
            }
        }

        try self.logger.err("Container with OCI ID {s} not found", .{oci_container_id});
        return error.ContainerNotFound;
    }

    pub fn listContainers(self: *ProxmoxClient) ![]types.LXCContainer {
        return self.listLXCs();
    }

    pub fn createContainer(self: *ProxmoxClient, container_id: []const u8, spec: []const u8) !void {
        const config = common.ContainerConfig{
            .id = try self.allocator.dupe(u8, container_id),
            .spec = try self.allocator.dupe(u8, spec),
        };
        defer config.deinit(self.allocator);

        try self.logger.info("Creating container {s}", .{config.id});
        // TODO: Implement container creation
    }

    pub fn startContainer(self: *ProxmoxClient, container_type: ContainerType, vmid: u32) !void {
        try self.logger.info("Starting container {d}", .{vmid});
        switch (container_type) {
            .lxc => try lxc_ops.startLXC(&self.client, self.node, vmid),
            .qemu => try vm_ops.startVM(&self.client, self.node, vmid),
        }
    }

    pub fn stopContainer(self: *ProxmoxClient, container_type: ContainerType, vmid: u32, force: ?bool) !void {
        try self.logger.info("Stopping container {d} (force: {?})", .{vmid, force});
        switch (container_type) {
            .lxc => try lxc_ops.stopLXC(&self.client, self.node, vmid),
            .qemu => try vm_ops.stopVM(&self.client, self.node, vmid, if (force) |f| if (f) @as(?i64, 0) else null else null),
        }
    }

    pub fn deleteContainer(self: *ProxmoxClient, container_type: ContainerType, vmid: u32) !void {
        try self.logger.info("Deleting container {d}", .{vmid});
        switch (container_type) {
            .lxc => try lxc_ops.deleteLXC(&self.client, self.node, vmid),
            .qemu => try vm_ops.deleteVM(&self.client, self.node, vmid),
        }
    }

    pub fn getContainerStatus(self: *ProxmoxClient, container_type: ContainerType, vmid: u32) !types.ContainerStatus {
        return switch (container_type) {
            .lxc => switch (try lxc_ops.getLXCStatus(&self.client, self.client.node, vmid)) {
                .running => .running,
                .stopped => .stopped,
                .paused => .paused,
                .unknown => .unknown,
            },
            .qemu => try vm_ops.getVMStatus(&self.client, self.client.node, vmid),
        };
    }

    // LXC специфічні операції
    pub fn listLXCs(self: *ProxmoxClient) ![]types.LXCContainer {
        return lxc_ops.listLXCs(&self.client);
    }

    // VM специфічні операції
    pub fn listVMs(self: *ProxmoxClient) ![]types.VMContainer {
        return vm_ops.listVMs(&self.client);
    }

    pub fn createVM(self: *ProxmoxClient, spec: types.VMConfig) !types.VMContainer {
        return vm_ops.createVM(&self.client, spec);
    }

    // Storage операції
    pub fn scanZFS(self: *ProxmoxClient) ![][]const u8 {
        return storage_ops.scanZFS(&self.client);
    }

    pub fn listStorage(self: *ProxmoxClient) ![]storage_ops.Storage {
        return storage_ops.listStorage(&self.client);
    }

    // Cluster операції
    pub fn listResources(self: *ProxmoxClient) ![]cluster_ops.Resource {
        return cluster_ops.listResources(&self.client);
    }

    pub fn getClusterStatus(self: *ProxmoxClient) !struct {
        nodes: u32,
        quorum: bool,
        version: []const u8,
    } {
        return cluster_ops.getClusterStatus(&self.client);
    }
};

// Реекспортуємо типи для зручності
pub const LXCContainer = types.LXCContainer;
pub const LXCConfig = types.LXCConfig;
pub const VMContainer = types.VMContainer;
pub const VMConfig = types.VMConfig;
pub const ContainerStatus = types.ContainerStatus;
pub const Node = node_ops.Node;
pub const Storage = storage_ops.Storage;
pub const Resource = cluster_ops.Resource;
