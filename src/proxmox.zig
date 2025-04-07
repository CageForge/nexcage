const std = @import("std");
const http = std.http;
const json = std.json;
const mem = std.mem;
const fmt = std.fmt;
const Allocator = std.mem.Allocator;
const time = std.time;

pub const Client = struct {
    allocator: Allocator,
    hosts: []const []const u8,
    current_host_index: usize,
    port: u16,
    token: []const u8,
    node: []const u8,
    client: http.Client,
    base_urls: []const []const u8,
    node_cache: NodeCache,

    const NodeCache = struct {
        nodes: []Node,
        last_update: i64,
        duration: u64,

        pub fn init(allocator: Allocator, duration: u64) NodeCache {
            _ = allocator; // Keep the parameter for future use
            return NodeCache{
                .nodes = &[_]Node{},
                .last_update = 0,
                .duration = duration,
            };
        }

        pub fn deinit(self: *NodeCache) void {
            self.nodes = &[_]Node{};
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
    };

    pub fn init(options: struct {
        allocator: Allocator,
        hosts: []const []const u8,
        port: u16,
        token: []const u8,
        node: []const u8,
        node_cache_duration: u64,
    }) !Client {
        var base_urls = try options.allocator.alloc([]const u8, options.hosts.len);
        errdefer options.allocator.free(base_urls);

        for (options.hosts, 0..) |host, i| {
            base_urls[i] = try fmt.allocPrint(options.allocator, "https://{s}:{d}/api2/json", .{
                host,
                options.port,
            });
        }

        return Client{
            .allocator = options.allocator,
            .hosts = options.hosts,
            .current_host_index = 0,
            .port = options.port,
            .token = options.token,
            .node = options.node,
            .client = http.Client{ .allocator = options.allocator },
            .base_urls = base_urls,
            .node_cache = NodeCache.init(options.allocator, options.node_cache_duration),
        };
    }

    pub fn deinit(self: *Client) void {
        for (self.base_urls) |url| {
            self.allocator.free(url);
        }
        self.allocator.free(self.base_urls);
        self.client.deinit();
        self.node_cache.deinit();
    }

    fn tryNextHost(self: *Client) bool {
        if (self.current_host_index + 1 >= self.hosts.len) {
            self.current_host_index = 0;
            return false;
        }
        self.current_host_index += 1;
        return true;
    }

    fn makeRequest(
        self: *Client,
        method: http.Method,
        path: []const u8,
        body: ?[]const u8,
    ) !APIResponse {
        var headers = http.Headers{ .allocator = self.allocator };
        defer headers.deinit();

        try headers.append("Authorization", try fmt.allocPrint(self.allocator, "PVEAPIToken={s}", .{self.token}));
        try headers.append("Content-Type", "application/json");

        var last_error: ?error{ ProxmoxAPIError, ConnectionError } = null;
        var attempts: usize = 0;
        const max_attempts = self.hosts.len;

        while (attempts < max_attempts) : (attempts += 1) {
            const url = try fmt.allocPrint(self.allocator, "{s}{s}", .{ self.base_urls[self.current_host_index], path });
            defer self.allocator.free(url);

            var req = self.client.request(method, try std.Uri.parse(url), headers, .{}) catch |err| {
                last_error = err;
                if (!self.tryNextHost()) break;
                continue;
            };
            defer req.deinit();

            if (body) |b| {
                req.start() catch |err| {
                    last_error = err;
                    if (!self.tryNextHost()) break;
                    continue;
                };
                req.writeAll(b) catch |err| {
                    last_error = err;
                    if (!self.tryNextHost()) break;
                    continue;
                };
                req.finish() catch |err| {
                    last_error = err;
                    if (!self.tryNextHost()) break;
                    continue;
                };
            } else {
                req.start() catch |err| {
                    last_error = err;
                    if (!self.tryNextHost()) break;
                    continue;
                };
            }

            req.wait() catch |err| {
                last_error = err;
                if (!self.tryNextHost()) break;
                continue;
            };

            const response_body = req.reader().readAllAlloc(self.allocator, 1024 * 1024) catch |err| {
                last_error = err;
                if (!self.tryNextHost()) break;
                continue;
            };
            defer self.allocator.free(response_body);

            const parsed = json.parseFromSlice(APIResponse, self.allocator, response_body, .{}) catch |err| {
                last_error = err;
                if (!self.tryNextHost()) break;
                continue;
            };

            if (!parsed.value.success) {
                last_error = error.ProxmoxAPIError;
                if (!self.tryNextHost()) break;
                continue;
            }

            return parsed.value;
        }

        if (last_error) |err| {
            return err;
        }
        return error.AllHostsFailed;
    }

    pub fn getNodes(self: *Client) ![]Node {
        if (!self.node_cache.isExpired()) {
            return self.node_cache.nodes;
        }

        const path = "/cluster/resources";
        const response = try self.makeRequest(.GET, path, null);
        if (!response.success) {
            return error.ProxmoxAPIError;
        }

        const resources = try json.parseFromValue([]Resource, self.allocator, response.data, .{});
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
        if (!response.success) {
            return error.ProxmoxAPIError;
        }

        const container = try json.parseFromValue(LXCContainer, self.allocator, response.data, .{});
        return container.value;
    }

    pub fn deleteLXC(self: *Client, vmid: u32) !void {
        const path = try fmt.allocPrint(self.allocator, "/nodes/{s}/lxc/{d}", .{ self.node, vmid });
        defer self.allocator.free(path);

        const response = try self.makeRequest(.DELETE, path, null);
        if (!response.success) {
            return error.ProxmoxAPIError;
        }
    }

    pub fn startLXC(self: *Client, vmid: u32) !void {
        const path = try fmt.allocPrint(self.allocator, "/nodes/{s}/lxc/{d}/status/start", .{ self.node, vmid });
        defer self.allocator.free(path);

        const response = try self.makeRequest(.POST, path, null);
        if (!response.success) {
            return error.ProxmoxAPIError;
        }
    }

    pub fn stopLXC(self: *Client, vmid: u32) !void {
        const path = try fmt.allocPrint(self.allocator, "/nodes/{s}/lxc/{d}/status/stop", .{ self.node, vmid });
        defer self.allocator.free(path);

        const response = try self.makeRequest(.POST, path, null);
        if (!response.success) {
            return error.ProxmoxAPIError;
        }
    }

    pub fn getLXCStatus(self: *Client, vmid: u32) !LXCStatus {
        const path = try fmt.allocPrint(self.allocator, "/nodes/{s}/lxc/{d}/status/current", .{ self.node, vmid });
        defer self.allocator.free(path);

        const response = try self.makeRequest(.GET, path, null);
        if (!response.success) {
            return error.ProxmoxAPIError;
        }

        const status = try json.parseFromValue(LXCStatus, self.allocator, response.data, .{});
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
            if (!response.success) {
                continue;
            }

            const containers = try json.parseFromValue([]LXCContainer, self.allocator, response.data, .{});
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
