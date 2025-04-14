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
const Error = @import("error").Error;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const StringHashMap = std.StringHashMap;
const json = std.json;
const http = std.http;
const Uri = std.Uri;
const HttpClient = http.Client;
const mem = std.mem;
const fmt = std.fmt;
const time = std.time;
const net = std.net;
const logger = logger_mod.Logger;
const Headers = std.http.protocol.Headers;

pub const Client = struct {
    allocator: Allocator,
    client: HttpClient,
    hosts: []const []const u8,
    base_urls: []const []const u8,
    token: []const u8,
    current_host_index: usize,
    logger: *logger,
    port: u16,
    node: []const u8,
    node_cache: NodeCache,

    const NodeCache = struct {
        allocator: Allocator,
        nodes: []Node,
        last_update: i64,
        duration: u64,

        pub fn init(allocator: Allocator, duration: u64) NodeCache {
            return NodeCache{
                .allocator = allocator,
                .nodes = &[_]Node{},
                .last_update = 0,
                .duration = duration,
            };
        }

        pub fn deinit(self: *NodeCache) void {
            for (self.nodes) |*node| {
                node.deinit(self.allocator);
            }
            if (self.nodes.len > 0) {
                self.allocator.free(self.nodes);
            }
        }

        pub fn isExpired(self: *NodeCache) bool {
            const now = time.timestamp();
            return now - self.last_update > @as(i64, @intCast(self.duration));
        }
    };

    const Node = struct {
        name: []const u8,
        status: []const u8,
        type: []const u8,

        pub fn deinit(self: *Node, allocator: Allocator) void {
            allocator.free(self.name);
            allocator.free(self.status);
            allocator.free(self.type);
        }
    };

    pub fn init(
        allocator: Allocator,
        hosts: []const []const u8,
        token: []const u8,
        logger_instance: *logger,
        port: u16,
        node: []const u8,
        node_cache_duration: u64,
    ) !Client {
        var base_urls = try allocator.alloc([]const u8, hosts.len);
        errdefer allocator.free(base_urls);

        for (hosts, 0..) |host, i| {
            base_urls[i] = try fmt.allocPrint(allocator, "https://{s}:{d}/api2/json", .{
                host,
                port,
            });
        }

        return Client{
            .allocator = allocator,
            .client = HttpClient{ .allocator = allocator },
            .hosts = hosts,
            .base_urls = base_urls,
            .token = token,
            .current_host_index = 0,
            .logger = logger_instance,
            .port = port,
            .node = node,
            .node_cache = NodeCache.init(allocator, node_cache_duration),
        };
    }

    pub fn deinit(self: *Client) void {
        for (self.base_urls) |url| {
            self.allocator.free(url);
        }
        self.allocator.free(self.base_urls);
        self.node_cache.deinit();
        self.client.deinit();
    }

    fn tryNextHost(self: *Client) bool {
        if (self.current_host_index + 1 >= self.hosts.len) {
            self.current_host_index = 0;
            return false;
        }
        self.current_host_index += 1;
        return true;
    }

    fn makeRequest(self: *Client, method: http.Method, path: []const u8, body: ?[]const u8) ![]const u8 {
        const url = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ self.base_urls[self.current_host_index], path });
        defer self.allocator.free(url);

        try self.logger.info("Making {s} request to {s}", .{ @tagName(method), url });

        var headers = Headers.init(self.allocator);
        defer headers.deinit();

        try headers.put("Authorization", try std.fmt.allocPrint(self.allocator, "PVEAPIToken={s}", .{self.token}));
        try headers.put("Content-Type", "application/json");

        var request = try self.client.open(method, try Uri.parse(url), headers, .{});
        defer request.deinit();

        if (body) |b| {
            try request.writeAll(b);
        }

        try request.finish();
        try request.wait();

        var buffer = std.ArrayList(u8).init(self.allocator);
        errdefer buffer.deinit();

        try request.reader().readAllArrayList(&buffer, std.math.maxInt(usize));

        return buffer.toOwnedSlice();
    }

    pub fn getNodes(self: *Client) ![]Node {
        if (!self.node_cache.isExpired()) {
            return self.node_cache.nodes;
        }

        const path = "/cluster/resources";
        const response = try self.makeRequest(.GET, path, null);
        if (response.len == 0) {
            return error.ProxmoxAPIError;
        }

        const resources = try json.parseFromSlice(json.Value, self.allocator, response, .{});
        defer self.allocator.free(resources.value);

        var nodes = std.ArrayList(Node).init(self.allocator);
        defer nodes.deinit();

        for (resources.value) |resource| {
            if (std.mem.eql(u8, resource.type, "node")) {
                try nodes.append(Node{
                    .name = try self.allocator.dupe(u8, resource.name),
                    .status = try self.allocator.dupe(u8, resource.status),
                    .type = try self.allocator.dupe(u8, resource.type),
                });
            }
        }

        // Free old nodes before assigning new ones
        self.node_cache.deinit();
        self.node_cache.nodes = try nodes.toOwnedSlice();
        self.node_cache.last_update = time.timestamp();

        return self.node_cache.nodes;
    }

    pub fn createLXC(self: *Client, spec: LXCConfig) !LXCContainer {
        const body = try json.stringifyAlloc(self.allocator, spec, .{});
        defer self.allocator.free(body);

        const path = try fmt.allocPrint(self.allocator, "/nodes/{s}/lxc", .{self.node});
        defer self.allocator.free(path);

        const response = try self.makeRequest(.POST, path, body);
        if (response.len == 0) {
            return error.ProxmoxAPIError;
        }

        const container = try json.parseFromSlice(LXCContainer, self.allocator, response, .{});
        return container.value;
    }

    pub fn deleteLXC(self: *Client, vmid: u32) !void {
        const path = try fmt.allocPrint(self.allocator, "/nodes/{s}/lxc/{d}", .{ self.node, vmid });
        defer self.allocator.free(path);

        const response = try self.makeRequest(.DELETE, path, null);
        if (response.len == 0) {
            return error.ProxmoxAPIError;
        }
    }

    pub fn startLXC(self: *Client, vmid: u32) !void {
        const path = try fmt.allocPrint(self.allocator, "/nodes/{s}/lxc/{d}/status/start", .{ self.node, vmid });
        defer self.allocator.free(path);

        const response = try self.makeRequest(.POST, path, null);
        if (response.len == 0) {
            return error.ProxmoxAPIError;
        }
    }

    pub fn stopLXC(self: *Client, vmid: u32) !void {
        const path = try fmt.allocPrint(self.allocator, "/nodes/{s}/lxc/{d}/status/stop", .{ self.node, vmid });
        defer self.allocator.free(path);

        const response = try self.makeRequest(.POST, path, null);
        if (response.len == 0) {
            return error.ProxmoxAPIError;
        }
    }

    pub fn getLXCStatus(self: *Client, vmid: u32) !LXCStatus {
        const path = try fmt.allocPrint(self.allocator, "/nodes/{s}/lxc/{d}/status/current", .{ self.node, vmid });
        defer self.allocator.free(path);

        const response = try self.makeRequest(.GET, path, null);
        if (response.len == 0) {
            return error.ProxmoxAPIError;
        }

        const status = try json.parseFromSlice(LXCStatus, self.allocator, response, .{});
        return status.value;
    }

    pub fn listLXCs(self: *Client) ![]LXCContainer {
        const nodes = try self.getNodes();
        var all_containers = std.ArrayList(LXCContainer).init(self.allocator);
        defer all_containers.deinit();

        for (nodes) |node| {
            const path = try fmt.allocPrint(self.allocator, "/nodes/{s}/lxc", .{node.name});
            defer self.allocator.free(path);

            const response = try self.makeRequest(.GET, path, null);
            if (response.len == 0) {
                continue;
            }

            const containers = try json.parseFromSlice(json.Value, self.allocator, response, .{});
            defer self.allocator.free(containers.value);

            try all_containers.appendSlice(containers.value);
        }

        return try all_containers.toOwnedSlice();
    }
};

pub const LXCContainer = struct {
    vmid: u32,
    name: []const u8,
    status: LXCStatus,
    config: LXCConfig,
};

pub const LXCConfig = struct {
    hostname: []const u8,
    ostype: []const u8,
    memory: u32,
    swap: u32,
    cores: u32,
    rootfs: []const u8,
    net0: NetworkConfig,
};

pub const NetworkConfig = struct {
    name: []const u8,
    bridge: []const u8,
    ip: []const u8,
};

pub const LXCStatus = enum {
    stopped,
    running,
    paused,
    unknown,
};

pub const Resource = struct {
    name: []const u8,
    status: []const u8,
    type: []const u8,
};

// Proxmox API response types
pub const APIResponse = struct {
    data: json.Value,
    success: bool,
    err_msg: ?[]const u8,
};

pub const ContainerSpec = struct {
    name: []const u8,
};

pub const ContainerStatus = enum {
    running,
    stopped,
    unknown,
};

pub fn specToLXCConfig(spec: ContainerSpec) !LXCConfig {
    return LXCConfig{
        .hostname = spec.name,
        .ostype = "ubuntu", // Default to Ubuntu for now
        .memory = 512, // Default memory
        .swap = 256, // Default swap
        .cores = 1, // Default cores
        .rootfs = "local-lvm:8", // Default rootfs
        .net0 = NetworkConfig{
            .name = "eth0",
            .bridge = "vmbr0",
            .ip = "dhcp", // Default to DHCP
        },
    };
}

pub fn lxcStatusToContainerStatus(status: LXCStatus) ContainerStatus {
    return switch (status) {
        .running => .running,
        .stopped => .stopped,
        .paused => .stopped,
        .unknown => .unknown,
    };
}
