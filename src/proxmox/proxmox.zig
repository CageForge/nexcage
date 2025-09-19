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
    host: []const u8,
    port: u16,
    token: []const u8,
    node: []const u8,
    logger: *logger_mod.Logger,
    client: Client,

    pub fn init(allocator: Allocator, host: []const u8, port: u16, token: []const u8, node: []const u8, log_instance: *logger_mod.Logger) !ProxmoxClient {
        try log_instance.info("ProxmoxClient.init called with node: '{s}' (len: {d})", .{ node, node.len });
        
        const token_copy = try allocator.dupe(u8, token);
        errdefer allocator.free(token_copy);

        const node_copy = try allocator.dupe(u8, node);
        errdefer allocator.free(node_copy);
        
        try log_instance.info("ProxmoxClient.init node_copy: '{s}' (len: {d})", .{ node_copy, node_copy.len });

        const host_copy = try allocator.dupe(u8, host);
        errdefer allocator.free(host_copy);

        const hosts = try allocator.alloc([]const u8, 1);
        errdefer allocator.free(hosts);
        hosts[0] = host_copy;

        var client = try Client.init(allocator, hosts, token_copy, log_instance, port, node_copy);
        errdefer client.deinit();

        const result = ProxmoxClient{
            .allocator = allocator,
            .host = host_copy,
            .port = port,
            .token = token_copy,
            .node = node_copy,
            .logger = log_instance,
            .client = client,
        };
        
        try log_instance.info("ProxmoxClient created with node: '{s}' (len: {d})", .{ result.node, result.node.len });
        try log_instance.info("ProxmoxClient result.node address: {*}", .{&result.node});
        return result;
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

    pub fn createContainer(self: *ProxmoxClient, container_id: []const u8, spec: []const u8, rootfs_path: ?[]const u8) !void {
        try self.logger.info("Creating container {s} with spec: {s}", .{ container_id, spec });
        try self.logger.info("ProxmoxClient node: '{s}' (len: {d})", .{ self.node, self.node.len });
        try self.logger.info("ProxmoxClient address: {*}", .{self});
        try self.logger.info("ProxmoxClient.node address: {*}", .{&self.node});
        
        // Parse the spec string to extract VMID
        // For now, we'll generate a VMID based on container_id hash
        var hasher = std.hash.Wyhash.init(0);
        hasher.update(container_id);
        const vmid = @as(u32, @truncate(hasher.final())) % 100000 + 100; // Generate VMID between 100-100099
        
        try self.logger.info("Generated VMID {d} for container {s}", .{ vmid, container_id });
        
        // Create basic LXC configuration
        const api_path = try std.fmt.allocPrint(self.allocator, "/nodes/{s}/lxc", .{self.node});
        defer self.allocator.free(api_path);
        
        // Basic LXC configuration
        var config = std.StringHashMap([]const u8).init(self.allocator);
        defer {
            var iter = config.iterator();
            while (iter.next()) |entry| {
                self.allocator.free(entry.value_ptr.*);
            }
            config.deinit();
        }
        
        try config.put("vmid", try std.fmt.allocPrint(self.allocator, "{d}", .{vmid}));
        try config.put("hostname", try self.allocator.dupe(u8, container_id));
        try config.put("ostype", try self.allocator.dupe(u8, "ubuntu"));
        try config.put("memory", try self.allocator.dupe(u8, "512"));
        try config.put("cores", try self.allocator.dupe(u8, "1"));
        try config.put("rootfs", try std.fmt.allocPrint(self.allocator, "local-lvm:8", .{}));
        try config.put("net0", try self.allocator.dupe(u8, "name=eth0,bridge=vmbr0,ip=dhcp"));
        try config.put("unprivileged", try self.allocator.dupe(u8, "1"));
        try config.put("onboot", try self.allocator.dupe(u8, "0"));
        
        // Якщо є rootfs_path, створюємо темплейт
        if (rootfs_path) |rootfs| {
            try self.logger.info("Creating template from rootfs: {s}", .{rootfs});
            const template_name = try std.fmt.allocPrint(self.allocator, "{s}-template", .{container_id});
            defer self.allocator.free(template_name);
            
            var template_info = try template_ops.createTemplateFromRootfs(&self.client, rootfs, template_name);
            defer template_info.deinit(self.allocator);
            
            const ostemplate = try std.fmt.allocPrint(self.allocator, "local:vztmpl/{s}.tar.zst", .{template_name});
            defer self.allocator.free(ostemplate);
            
            try config.put("ostemplate", ostemplate);
            try self.logger.info("Using template: {s}", .{ostemplate});
        } else {
            // Використовуємо існуючий темплейт або створюємо без темплейту
            try self.logger.info("No rootfs provided, checking for available templates", .{});
            
            const templates = try template_ops.listAvailableTemplates(&self.client);
            defer {
                for (templates) |*template| {
                    template.deinit(self.allocator);
                }
                self.allocator.free(templates);
            }
            
            if (templates.len > 0) {
                const template = templates[0];
                const ostemplate = try std.fmt.allocPrint(self.allocator, "local:vztmpl/{s}", .{template.name});
                defer self.allocator.free(ostemplate);
                
                try config.put("ostemplate", ostemplate);
                try self.logger.info("Using available template: {s}", .{ostemplate});
            } else {
                try self.logger.warn("No templates available, creating container without template", .{});
            }
        }
        
        // Convert configuration to JSON manually
        var body = std.ArrayList(u8).init(self.allocator);
        defer body.deinit();
        
        try body.append('{');
        var first = true;
        var iter = config.iterator();
        while (iter.next()) |entry| {
            if (!first) try body.append(',');
            first = false;
            
            try body.writer().print("\"{s}\":\"{s}\"", .{ entry.key_ptr.*, entry.value_ptr.* });
        }
        try body.append('}');
        
        const body_str = try body.toOwnedSlice();
        defer self.allocator.free(body_str);
        
        try self.logger.info("Sending LXC creation request to {s}", .{api_path});
        try self.logger.info("Node: {s}, API path: {s}", .{ self.node, api_path });
        try self.logger.info("Request body: {s}", .{body_str});
        
        // Send request to create container
        const response = try self.client.makeRequest(.POST, api_path, body_str);
        defer self.allocator.free(response);
        
        try self.logger.info("LXC container {s} created successfully with VMID {d}", .{ container_id, vmid });
    }

    pub fn startContainer(self: *ProxmoxClient, container_type: ContainerType, vmid: u32) !void {
        try self.logger.info("Starting container {d}", .{vmid});
        switch (container_type) {
            .lxc => try lxc_ops.startLXC(&self.client, self.node, vmid),
            .qemu => try vm_ops.startVM(&self.client, self.node, vmid),
        }
    }

    pub fn stopContainer(self: *ProxmoxClient, container_type: ContainerType, vmid: u32, force: ?bool) !void {
        try self.logger.info("Stopping container {d} (force: {?})", .{ vmid, force });
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
