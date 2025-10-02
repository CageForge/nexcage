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
const API_PREFIX = "/api2/json";

// Import PCT CLI client
const pct_cli = @import("pct_cli.zig");

const ContainerConfig = struct {
    id: []const u8,
    spec: []const u8,

    pub fn deinit(self: *ContainerConfig, allocator: Allocator) void {
        allocator.free(self.id);
        allocator.free(self.spec);
    }
};

const Options = struct {
    timeout: ?u64 = null,
};

const Client = @import("client.zig").Client;
const lxc_ops = @import("lxc/operations.zig");
const node_ops = @import("node/operations.zig");
const storage_ops = @import("storage/operations.zig");
const cluster_ops = @import("cluster/operations.zig");
const vm_ops = @import("vm/operations.zig");
const template_ops = @import("template/operations.zig");

pub const ContainerType = enum {
    lxc,
    qemu,
};

pub const ProxmoxClient = struct {
    allocator: Allocator,
    node: []const u8,
    logger: *logger_mod.Logger,
    pct_client: pct_cli.PCTClient,

    pub fn init(allocator: Allocator, pct_path: []const u8, node: []const u8, log_instance: *logger_mod.Logger) !ProxmoxClient {
        try log_instance.info("ProxmoxClient.init called with node: '{s}' (len: {d})", .{ node, node.len });

        const node_copy = try allocator.dupe(u8, node);
        errdefer allocator.free(node_copy);

        try log_instance.info("ProxmoxClient.init node_copy: '{s}' (len: {d})", .{ node_copy, node_copy.len });

        var pct_client = try pct_cli.PCTClient.init(allocator, pct_path, node_copy, log_instance);
        errdefer pct_client.deinit();

        const result = ProxmoxClient{
            .allocator = allocator,
            .node = node_copy,
            .logger = log_instance,
            .pct_client = pct_client,
        };

        try log_instance.info("ProxmoxClient created with node: '{s}' (len: {d})", .{ result.node, result.node.len });
        try log_instance.info("ProxmoxClient result.node address: {*}", .{&result.node});
        return result;
    }

    pub fn deinit(self: *ProxmoxClient) void {
        self.pct_client.deinit();
        // Звільняємо node, який належить ProxmoxClient
        if (self.node.len > 0) self.allocator.free(self.node);
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
        return self.pct_client.listContainers();
    }

    pub fn createContainer(self: *ProxmoxClient, container_id: []const u8, spec: []const u8, rootfs_path: ?[]const u8) !void {
        try self.logger.info("Creating container {s} with spec: {s}", .{ container_id, spec });

        // Parse the spec string to extract VMID
        // For now, we'll generate a VMID based on container_id hash
        var hasher = std.hash.Wyhash.init(0);
        hasher.update(container_id);
        const vmid = @as(u32, @truncate(hasher.final())) % 100000 + 100; // Generate VMID between 100-100099

        try self.logger.info("Generated VMID {d} for container {s}", .{ vmid, container_id });

        // Create LXC configuration
        var config = types.LXCConfig{
            .hostname = try self.allocator.dupe(u8, container_id),
            .ostype = try self.allocator.dupe(u8, "ubuntu"),
            .memory = 512,
            .swap = 0,
            .cores = 1,
            .rootfs = try self.allocator.dupe(u8, "local-lvm:8"),
            .net0 = types.NetworkConfig{
                .name = try self.allocator.dupe(u8, "eth0"),
                .bridge = try self.allocator.dupe(u8, "vmbr0"),
                .ip = try self.allocator.dupe(u8, "dhcp"),
                .allocator = self.allocator,
            },
            .onboot = false,
            .protection = false,
            .start = true,
            .template = false,
            .unprivileged = true,
            .features = .{},
        };
        defer config.deinit(self.allocator);

        // Set template if provided
        if (rootfs_path) |rootfs| {
            try self.logger.info("Creating template from rootfs: {s}", .{rootfs});
            const template_name = try std.fmt.allocPrint(self.allocator, "{s}-template", .{container_id});
            defer self.allocator.free(template_name);

            const ostemplate = try std.fmt.allocPrint(self.allocator, "local:vztmpl/{s}.tar.zst", .{template_name});
            defer self.allocator.free(ostemplate);
            config.ostemplate = ostemplate;

            try self.logger.info("Using template: {s}", .{ostemplate});
        } else {
            // Use default template
            config.ostemplate = try self.allocator.dupe(u8, "local:vztmpl/ubuntu-20.04-standard_20.04-1_amd64.tar.gz");
        }

        // Create container using PCT CLI
        try self.pct_client.createContainer(vmid, config);

        try self.logger.info("LXC container {s} created successfully with VMID {d}", .{ container_id, vmid });
    }

    pub fn startContainer(self: *ProxmoxClient, container_type: ContainerType, vmid: u32) !void {
        try self.logger.info("Starting container {d}", .{vmid});
        switch (container_type) {
            .lxc => try self.pct_client.startContainer(vmid),
            .qemu => {
                try self.logger.warn("VM start not supported via PCT CLI, only LXC containers are supported", .{});
                return Error.PCTOperationFailed;
            },
        }
    }

    pub fn stopContainer(self: *ProxmoxClient, container_type: ContainerType, vmid: u32, force: ?bool) !void {
        try self.logger.info("Stopping container {d} (force: {?})", .{ vmid, force });
        switch (container_type) {
            .lxc => try self.pct_client.stopContainer(vmid),
            .qemu => {
                try self.logger.warn("VM stop not supported via PCT CLI, only LXC containers are supported", .{});
                return Error.PCTOperationFailed;
            },
        }
    }

    pub fn deleteContainer(self: *ProxmoxClient, container_type: ContainerType, vmid: u32) !void {
        try self.logger.info("Deleting container {d}", .{vmid});
        switch (container_type) {
            .lxc => try self.pct_client.deleteContainer(vmid),
            .qemu => {
                try self.logger.warn("VM delete not supported via PCT CLI, only LXC containers are supported", .{});
                return Error.PCTOperationFailed;
            },
        }
    }

    pub fn getContainerStatus(self: *ProxmoxClient, container_type: ContainerType, vmid: u32) !types.ContainerStatus {
        return switch (container_type) {
            .lxc => try self.pct_client.getContainerStatus(vmid),
            .qemu => {
                try self.logger.warn("VM status not supported via PCT CLI, only LXC containers are supported", .{});
                return types.ContainerStatus.unknown;
            },
        };
    }

    // LXC специфічні операції
    pub fn listLXCs(self: *ProxmoxClient) ![]types.LXCContainer {
        return self.pct_client.listContainers();
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

    // Template операції
    pub fn createTemplateFromRootfs(self: *ProxmoxClient, rootfs_path: []const u8, template_name: []const u8) !template_ops.TemplateInfo {
        return template_ops.createTemplateFromRootfs(&self.client, rootfs_path, template_name);
    }

    pub fn listAvailableTemplates(self: *ProxmoxClient) ![]template_ops.TemplateInfo {
        return template_ops.listAvailableTemplates(&self.client);
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
