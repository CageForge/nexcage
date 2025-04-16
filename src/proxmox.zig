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

const Options = struct {
    timeout: ?u64 = null,
};

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
    timeout: u64 = 30_000, // 30 seconds default timeout
    last_node_check: u64 = 0,
    cached_node: ?[]const u8 = null,

    const NodeCache = struct {
        allocator: Allocator,
        nodes: []Node,
        last_update: i64,
        duration: u64,

        pub fn init(allocator: Allocator, duration: u64) !NodeCache {
            return NodeCache{
                .allocator = allocator,
                .nodes = try allocator.alloc(Node, 0),
                .last_update = 0,
                .duration = duration,
            };
        }

        pub fn deinit(self: *NodeCache) void {
            for (self.nodes) |*node| {
                node.deinit(self.allocator);
            }
            self.allocator.free(self.nodes);
        }

        pub fn isExpired(self: *NodeCache) bool {
            const now = time.timestamp();
            return now - self.last_update > @as(i64, @intCast(self.duration));
        }
    };

    const Node = struct {
        name: []const u8,
        status: []const u8,
        node_type: []const u8,
        owned: bool = false,

        pub fn init(allocator: Allocator, name: []const u8, status: []const u8, node_type: []const u8, owned: bool) !Node {
            if (owned) {
                return Node{
                    .name = try allocator.dupe(u8, name),
                    .status = try allocator.dupe(u8, status),
                    .node_type = try allocator.dupe(u8, node_type),
                    .owned = true,
                };
            } else {
                return Node{
                    .name = name,
                    .status = status,
                    .node_type = node_type,
                    .owned = false,
                };
            }
        }

        pub fn deinit(self: *Node, allocator: Allocator) void {
            if (self.owned) {
                allocator.free(self.name);
                allocator.free(self.status);
                allocator.free(self.node_type);
            }
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
        if (hosts.len == 0) return Error.ProxmoxInvalidConfig;
        if (token.len == 0) return Error.ProxmoxInvalidToken;
        if (node.len == 0) return Error.ProxmoxInvalidNode;

        var base_urls = try allocator.alloc([]const u8, hosts.len);
        errdefer allocator.free(base_urls);

        for (hosts, 0..) |host, i| {
            base_urls[i] = try fmt.allocPrint(allocator, "https://{s}:{d}/api2/json", .{
                host,
                port,
            });
        }

        const node_cache = try NodeCache.init(allocator, node_cache_duration);
        errdefer node_cache.deinit();

        var client = HttpClient{ .allocator = allocator };
        errdefer client.deinit();

        return Client{
            .allocator = allocator,
            .client = client,
            .hosts = hosts,
            .base_urls = base_urls,
            .token = token,
            .current_host_index = 0,
            .logger = logger_instance,
            .port = port,
            .node = node,
            .node_cache = node_cache,
            .timeout = 30_000, // Default timeout of 30 seconds
        };
    }

    pub fn deinit(self: *Client) void {
        self.node_cache.deinit();
        for (self.base_urls) |url| {
            self.allocator.free(url);
        }
        self.allocator.free(self.base_urls);
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

    pub fn makeRequest(self: *Client, method: http.Method, path: []const u8, body: ?[]const u8) ![]const u8 {
        const max_retries = 3;
        var retry_count: u8 = 0;
        var last_error: anyerror = undefined;

        while (retry_count < max_retries) : (retry_count += 1) {
            try self.logger.info("Making {s} request to {s} (attempt {d}/{d})", .{ @tagName(method), path, retry_count + 1, max_retries });

            var url_buffer: [1024]u8 = undefined;
            const url = try std.fmt.bufPrint(&url_buffer, "{s}{s}", .{ self.base_urls[self.current_host_index], path });
            try self.logger.info("Full URL: {s}", .{url});

            var server_header_buffer: [1024]u8 = undefined;
            var request = try self.client.open(method, try Uri.parse(url), .{
                .server_header_buffer = &server_header_buffer,
            });
            defer request.deinit();

            const auth_header = try std.fmt.allocPrint(self.allocator, "PVEAPIToken={s}", .{self.token});
            defer self.allocator.free(auth_header);
            try self.logger.info("Auth header: {s}", .{auth_header});
            const headers = [_]http.Header{
                .{ .name = "Authorization", .value = auth_header },
                .{ .name = "Content-Type", .value = "application/json" },
            };
            request.extra_headers = &headers;

            if (body) |b| {
                request.transfer_encoding = .{ .content_length = b.len };
                try self.logger.info("Request body: {s}", .{b});
            }

            request.send() catch |err| {
                try self.logger.err("Failed to send request: {s}", .{@errorName(err)});
                last_error = err;
                if (self.tryNextHost()) continue;
                return err;
            };

            if (body) |b| {
                request.writeAll(b) catch |err| {
                    try self.logger.err("Failed to write request body: {s}", .{@errorName(err)});
                    last_error = err;
                    if (self.tryNextHost()) continue;
                    return err;
                };
            }

            request.finish() catch |err| {
                try self.logger.err("Failed to finish request: {s}", .{@errorName(err)});
                last_error = err;
                if (self.tryNextHost()) continue;
                return err;
            };

            request.wait() catch |err| {
                try self.logger.err("Failed to wait for response: {s}", .{@errorName(err)});
                last_error = err;
                if (self.tryNextHost()) continue;
                return err;
            };

            const status = request.response.status;
            try self.logger.info("Response status: {d}", .{@intFromEnum(status)});

            const response_body = try request.reader().readAllAlloc(self.allocator, 1024 * 1024);
            defer self.allocator.free(response_body);

            try self.logger.info("Response body: {s}", .{response_body});

            if (status != .ok) {
                try self.logger.err("Request failed with status {d}: {s}", .{ @intFromEnum(status), response_body });

                // Try to parse error response
                if (json.parseFromSlice(json.Value, self.allocator, response_body, .{})) |parsed| {
                    defer parsed.deinit();
                    if (parsed.value.object.get("errors")) |errors| {
                        if (errors.object.get("message")) |message| {
                            try self.logger.err("Proxmox error: {s}", .{message.string});
                        }
                    }
                } else |_| {}

                // Handle specific status codes
                switch (status) {
                    .unauthorized => return Error.ProxmoxAuthError,
                    .forbidden => return Error.ProxmoxPermissionDenied,
                    .not_found => return Error.ProxmoxResourceNotFound,
                    .request_timeout => {
                        last_error = Error.ProxmoxTimeout;
                        if (self.tryNextHost()) continue;
                        return Error.ProxmoxTimeout;
                    },
                    else => {
                        last_error = Error.ProxmoxOperationFailed;
                        if (self.tryNextHost()) continue;
                        return Error.ProxmoxOperationFailed;
                    },
                }
            }

            // Duplicate response_body before returning to avoid memory leak
            const result = try self.allocator.dupe(u8, response_body);
            return result;
        }

        return last_error;
    }

    pub fn getNodes(self: *Client) ![]Node {
        if (!self.node_cache.isExpired()) {
            return self.node_cache.nodes;
        }

        const path = "/cluster/resources";
        const response = try self.makeRequest(.GET, path, null);
        defer self.allocator.free(response);

        if (response.len == 0) {
            return error.ProxmoxAPIError;
        }

        try self.logger.info("API response: {s}", .{response});

        var parsed = try json.parseFromSlice(json.Value, self.allocator, response, .{});
        defer parsed.deinit();

        var nodes = std.ArrayList(Node).init(self.allocator);
        errdefer {
            for (nodes.items) |*node| {
                node.deinit(self.allocator);
            }
            nodes.deinit();
        }

        if (parsed.value.object.get("data")) |data| {
            for (data.array.items) |resource| {
                if (std.mem.eql(u8, resource.object.get("type").?.string, "node")) {
                    try nodes.append(Node{
                        .name = try self.allocator.dupe(u8, resource.object.get("node").?.string),
                        .status = try self.allocator.dupe(u8, resource.object.get("status").?.string),
                        .node_type = try self.allocator.dupe(u8, resource.object.get("type").?.string),
                        .owned = true,
                    });
                }
            }
        }

        const new_nodes = try nodes.toOwnedSlice();
        errdefer {
            for (new_nodes) |*node| {
                node.deinit(self.allocator);
            }
            self.allocator.free(new_nodes);
        }

        // Free old nodes before assigning new ones
        if (self.node_cache.nodes.len > 0) {
            for (self.node_cache.nodes) |*node| {
                node.deinit(self.allocator);
            }
            self.allocator.free(self.node_cache.nodes);
        }

        self.node_cache.nodes = new_nodes;
        self.node_cache.last_update = time.timestamp();

        return self.node_cache.nodes;
    }

    pub fn createLXC(self: *Client, spec: LXCConfig) !LXCContainer {
        const body = try json.stringifyAlloc(self.allocator, spec, .{});
        defer self.allocator.free(body);

        const path = try fmt.allocPrint(self.allocator, API_PREFIX ++ "/nodes/{s}/lxc", .{self.node});
        defer self.allocator.free(path);

        const response = try self.makeRequest(.POST, path, body);
        defer self.allocator.free(response);

        var parsed = try json.parseFromSlice(json.Value, self.allocator, response, .{});
        defer parsed.deinit();

        return LXCContainer{
            .vmid = @intCast(parsed.value.object.get("vmid").?.integer),
            .name = try self.allocator.dupe(u8, spec.hostname),
            .status = .stopped,
            .config = spec,
        };
    }

    pub fn deleteLXC(self: *Client, vmid: u32) !void {
        const path = try fmt.allocPrint(self.allocator, API_PREFIX ++ "/nodes/{s}/lxc/{d}", .{ self.node, vmid });
        defer self.allocator.free(path);

        const response = try self.makeRequest(.DELETE, path, null);
        if (response.len == 0) {
            return error.ProxmoxAPIError;
        }
    }

    pub fn startLXC(self: *Client, vmid: u32) !void {
        const path = try fmt.allocPrint(self.allocator, API_PREFIX ++ "/nodes/{s}/lxc/{d}/status/start", .{ self.node, vmid });
        defer self.allocator.free(path);

        const response = try self.makeRequest(.POST, path, null);
        if (response.len == 0) {
            return error.ProxmoxAPIError;
        }
    }

    pub fn stopLXC(self: *Client, vmid: u32) !void {
        const path = try fmt.allocPrint(self.allocator, API_PREFIX ++ "/nodes/{s}/lxc/{d}/status/stop", .{ self.node, vmid });
        defer self.allocator.free(path);

        const response = try self.makeRequest(.POST, path, null);
        if (response.len == 0) {
            return error.ProxmoxAPIError;
        }
    }

    pub fn getLXCStatus(self: *Client, vmid: u32) !LXCStatus {
        const path = try fmt.allocPrint(self.allocator, API_PREFIX ++ "/nodes/{s}/lxc/{d}/status/current", .{ self.node, vmid });
        defer self.allocator.free(path);

        const response = try self.makeRequest(.GET, path, null);
        if (response.len == 0) {
            return error.ProxmoxAPIError;
        }

        const status = try json.parseFromSliceLeaky(LXCStatus, self.allocator, response, .{});
        return status.value;
    }

    pub fn listLXCs(self: *Client) ![]LXCContainer {
        const nodes = try self.getNodes();
        // Не звільняємо nodes, оскільки вони належать до node_cache

        var containers = std.ArrayList(LXCContainer).init(self.allocator);
        errdefer {
            for (containers.items) |container| {
                self.allocator.free(container.name);
            }
            containers.deinit();
        }

        for (nodes) |node| {
            const path = try fmt.allocPrint(self.allocator, "/nodes/{s}/lxc", .{node.name});
            defer self.allocator.free(path);

            const response = try self.makeRequest(.GET, path, null);
            defer self.allocator.free(response);

            if (response.len == 0) {
                continue;
            }

            var parsed = try json.parseFromSlice(json.Value, self.allocator, response, .{});
            defer parsed.deinit();

            if (parsed.value.object.get("data")) |data| {
                for (data.array.items) |container| {
                    try containers.append(LXCContainer{
                        .vmid = @intCast(container.object.get("vmid").?.integer),
                        .name = try self.allocator.dupe(u8, container.object.get("name").?.string),
                        .status = try parseStatus(container.object.get("status").?.string),
                        .config = try parseConfig(self.allocator, container.object.get("config").?.object),
                    });
                }
            }
        }

        return try containers.toOwnedSlice();
    }

    fn parseStatus(status: []const u8) !LXCStatus {
        if (std.mem.eql(u8, status, "running")) {
            return .running;
        } else if (std.mem.eql(u8, status, "stopped")) {
            return .stopped;
        } else if (std.mem.eql(u8, status, "paused")) {
            return .paused;
        } else {
            return .unknown;
        }
    }

    fn parseConfig(allocator: Allocator, config: json.ObjectMap) !LXCConfig {
        return LXCConfig{
            .hostname = try allocator.dupe(u8, config.get("hostname").?.string),
            .ostype = try allocator.dupe(u8, config.get("ostype").?.string),
            .memory = @intCast(config.get("memory").?.integer),
            .swap = @intCast(config.get("swap").?.integer),
            .cores = @intCast(config.get("cores").?.integer),
            .rootfs = try allocator.dupe(u8, config.get("rootfs").?.string),
            .net0 = try parseNetworkConfig(allocator, config.get("net0").?.object),
            .onboot = if (config.get("onboot")) |v| v.bool else false,
            .protection = if (config.get("protection")) |v| v.bool else false,
            .start = if (config.get("start")) |v| v.bool else true,
            .template = if (config.get("template")) |v| v.bool else false,
            .unprivileged = if (config.get("unprivileged")) |v| v.bool else true,
            .features = try parseFeatures(allocator, config.get("features").?.object),
        };
    }

    fn parseNetworkConfig(allocator: Allocator, network: json.ObjectMap) !NetworkConfig {
        return NetworkConfig{
            .name = try allocator.dupe(u8, network.get("name").?.string),
            .bridge = try allocator.dupe(u8, network.get("bridge").?.string),
            .ip = try allocator.dupe(u8, network.get("ip").?.string),
            .gw = if (network.get("gw")) |v| try allocator.dupe(u8, v.string) else null,
            .ip6 = if (network.get("ip6")) |v| try allocator.dupe(u8, v.string) else null,
            .gw6 = if (network.get("gw6")) |v| try allocator.dupe(u8, v.string) else null,
            .mtu = if (network.get("mtu")) |v| @intCast(v.integer) else null,
            .rate = if (network.get("rate")) |v| @intCast(v.integer) else null,
            .tag = if (network.get("tag")) |v| @intCast(v.integer) else null,
            .type = try allocator.dupe(u8, if (network.get("type")) |v| v.string else "veth"),
        };
    }

    fn parseFeatures(allocator: Allocator, features: json.ObjectMap) !Features {
        var mounts = std.ArrayList([]const u8).init(allocator);
        errdefer {
            for (mounts.items) |mount| {
                allocator.free(mount);
            }
            mounts.deinit();
        }

        return Features{
            .nesting = if (features.get("nesting")) |v| v.bool else false,
            .fuse = if (features.get("fuse")) |v| v.bool else false,
            .keyctl = if (features.get("keyctl")) |v| v.bool else false,
            .mknod = if (features.get("mknod")) |v| v.bool else false,
            .mount = if (features.get("mount")) |v| blk: {
                for (v.array.items) |mount| {
                    try mounts.append(try allocator.dupe(u8, mount.string));
                }
                break :blk try mounts.toOwnedSlice();
            } else &[_][]const u8{},
        };
    }

    pub fn updateLXCConfig(self: *Client, vmid: u32, config: LXCConfig) !void {
        const path = try fmt.allocPrint(self.allocator, API_PREFIX ++ "/nodes/{s}/lxc/{d}/config", .{ self.node, vmid });
        defer self.allocator.free(path);

        const body = try json.stringifyAlloc(self.allocator, config, .{});
        defer self.allocator.free(body);

        _ = try self.makeRequest(.PUT, path, body);
    }

    pub fn createSnapshot(self: *Client, vmid: u32, name: []const u8, description: ?[]const u8) !void {
        const path = try fmt.allocPrint(self.allocator, API_PREFIX ++ "/nodes/{s}/lxc/{d}/snapshot", .{ self.node, vmid });
        defer self.allocator.free(path);

        var snapshot_config = std.StringHashMap([]const u8).init(self.allocator);
        defer {
            var iter = snapshot_config.valueIterator();
            while (iter.next()) |value| {
                self.allocator.free(value.*);
            }
            snapshot_config.deinit();
        }

        const name_dup = try self.allocator.dupe(u8, name);
        try snapshot_config.put("snapname", name_dup);

        if (description) |desc| {
            const desc_dup = try self.allocator.dupe(u8, desc);
            try snapshot_config.put("description", desc_dup);
        }

        const body = try json.stringifyAlloc(self.allocator, snapshot_config, .{});
        defer self.allocator.free(body);

        _ = try self.makeRequest(.POST, path, body);
    }

    pub fn deleteSnapshot(self: *Client, vmid: u32, name: []const u8) !void {
        const path = try fmt.allocPrint(self.allocator, API_PREFIX ++ "/nodes/{s}/lxc/{d}/snapshot/{s}", .{ self.node, vmid, name });
        defer self.allocator.free(path);

        const response = try self.makeRequest(.DELETE, path, null);
        defer self.allocator.free(response);

        if (response.len == 0) {
            return error.ProxmoxAPIError;
        }
    }

    pub fn rollbackSnapshot(self: *Client, vmid: u32, name: []const u8) !void {
        const path = try fmt.allocPrint(self.allocator, API_PREFIX ++ "/nodes/{s}/lxc/{d}/snapshot/{s}/rollback", .{ self.node, vmid, name });
        defer self.allocator.free(path);

        _ = try self.makeRequest(.POST, path, null);
    }

    pub fn listSnapshots(self: *Client, vmid: u32) ![]Snapshot {
        const path = try fmt.allocPrint(self.allocator, API_PREFIX ++ "/nodes/{s}/lxc/{d}/snapshot", .{ self.node, vmid });
        defer self.allocator.free(path);

        const response = try self.makeRequest(.GET, path, null);
        defer self.allocator.free(response);

        var parsed = try json.parseFromSlice(json.Value, self.allocator, response, .{});
        defer parsed.deinit();

        var snapshots = std.ArrayList(Snapshot).init(self.allocator);
        errdefer snapshots.deinit();

        if (parsed.value.object.get("data")) |data| {
            for (data.array.items) |snapshot| {
                const name = try self.allocator.dupe(u8, snapshot.object.get("name").?.string);
                const description = if (snapshot.object.get("description")) |desc|
                    try self.allocator.dupe(u8, desc.string)
                else
                    null;
                const parent = if (snapshot.object.get("parent")) |p|
                    try self.allocator.dupe(u8, p.string)
                else
                    null;

                try snapshots.append(Snapshot{
                    .name = name,
                    .description = description,
                    .parent = parent,
                    .snaptime = @intCast(snapshot.object.get("snaptime").?.integer),
                    .vmstate = if (snapshot.object.get("vmstate")) |v| v.bool else false,
                });
            }
        }

        return try snapshots.toOwnedSlice();
    }

    pub const Snapshot = struct {
        name: []const u8,
        description: ?[]const u8,
        parent: ?[]const u8,
        snaptime: u64,
        vmstate: bool,
    };

    pub fn migrateLXC(self: *Client, vmid: u32, target_node: []const u8, options: struct {
        online: bool = false,
        force: bool = false,
        target_storage: ?[]const u8 = null,
        with_local_disks: bool = false,
    }) !void {
        const path = try fmt.allocPrint(self.allocator, API_PREFIX ++ "/nodes/{s}/lxc/{d}/migrate", .{ self.node, vmid });
        defer self.allocator.free(path);

        var migrate_config = std.StringHashMap([]const u8).init(self.allocator);
        defer {
            var iter = migrate_config.valueIterator();
            while (iter.next()) |value| {
                self.allocator.free(value.*);
            }
            migrate_config.deinit();
        }

        const target_dup = try self.allocator.dupe(u8, target_node);
        try migrate_config.put("target", target_dup);

        const online_str = try self.allocator.dupe(u8, if (options.online) "1" else "0");
        try migrate_config.put("online", online_str);

        const force_str = try self.allocator.dupe(u8, if (options.force) "1" else "0");
        try migrate_config.put("force", force_str);

        if (options.target_storage) |storage| {
            const storage_dup = try self.allocator.dupe(u8, storage);
            try migrate_config.put("target-storage", storage_dup);
        }

        const local_disks_str = try self.allocator.dupe(u8, if (options.with_local_disks) "1" else "0");
        try migrate_config.put("with-local-disks", local_disks_str);

        const body = try json.stringifyAlloc(self.allocator, migrate_config, .{});
        defer self.allocator.free(body);

        _ = try self.makeRequest(.POST, path, body);
    }

    pub fn createTemplate(self: *Client, vmid: u32) !void {
        const path = try fmt.allocPrint(self.allocator, API_PREFIX ++ "/nodes/{s}/lxc/{d}/template", .{ self.node, vmid });
        defer self.allocator.free(path);

        _ = try self.makeRequest(.POST, path, null);
    }

    pub fn cloneLXC(self: *Client, vmid: u32, newid: u32, options: struct {
        name: ?[]const u8 = null,
        full: bool = false,
        target: ?[]const u8 = null,
        storage: ?[]const u8 = null,
        snapname: ?[]const u8 = null,
    }) !void {
        const path = try fmt.allocPrint(self.allocator, API_PREFIX ++ "/nodes/{s}/lxc/{d}/clone", .{ self.node, vmid });
        defer self.allocator.free(path);

        var clone_config = std.StringHashMap([]const u8).init(self.allocator);
        defer {
            var iter = clone_config.valueIterator();
            while (iter.next()) |value| {
                self.allocator.free(value.*);
            }
            clone_config.deinit();
        }

        const newid_str = try fmt.allocPrint(self.allocator, "{d}", .{newid});
        try clone_config.put("newid", newid_str);

        if (options.name) |name| {
            const name_dup = try self.allocator.dupe(u8, name);
            try clone_config.put("name", name_dup);
        }
        const full_str = try self.allocator.dupe(u8, if (options.full) "1" else "0");
        try clone_config.put("full", full_str);

        if (options.target) |target| {
            const target_dup = try self.allocator.dupe(u8, target);
            try clone_config.put("target", target_dup);
        }
        if (options.storage) |storage| {
            const storage_dup = try self.allocator.dupe(u8, storage);
            try clone_config.put("storage", storage_dup);
        }
        if (options.snapname) |snapname| {
            const snapname_dup = try self.allocator.dupe(u8, snapname);
            try clone_config.put("snapname", snapname_dup);
        }

        const body = try json.stringifyAlloc(self.allocator, clone_config, .{});
        defer self.allocator.free(body);

        _ = try self.makeRequest(.POST, path, body);
    }

    pub fn listNodes(self: *Client) ![]Node {
        var nodes = ArrayList(Node).init(self.allocator);
        errdefer nodes.deinit();

        const response = try self.makeRequest(.GET, "/cluster/resources", null);
        defer self.allocator.free(response);

        var parsed = try json.parseFromSlice(json.Value, self.allocator, response, .{});
        defer parsed.deinit();

        const data = parsed.value.object.get("data").?.array;
        for (data.items) |resource| {
            if (std.mem.eql(u8, resource.object.get("type").?.string, "node")) {
                try nodes.append(try Node.init(self.allocator, resource.object.get("node").?.string, resource.object.get("status").?.string, resource.object.get("type").?.string, true));
            }
        }

        return try nodes.toOwnedSlice();
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
    onboot: bool = false,
    protection: bool = false,
    start: bool = true,
    template: bool = false,
    unprivileged: bool = true,
    features: Features = .{},
    mp0: ?MountPoint = null,
    mp1: ?MountPoint = null,
    mp2: ?MountPoint = null,
    mp3: ?MountPoint = null,
    mp4: ?MountPoint = null,
    mp5: ?MountPoint = null,
    mp6: ?MountPoint = null,
    mp7: ?MountPoint = null,
};

pub const Features = struct {
    nesting: bool = false,
    fuse: bool = false,
    keyctl: bool = false,
    mknod: bool = false,
    mount: []const []const u8 = &[_][]const u8{},
};

pub const MountPoint = struct {
    volume: []const u8,
    mp: []const u8,
    size: []const u8,
    acl: bool = false,
    backup: bool = true,
    quota: bool = false,
    replicate: bool = true,
    shared: bool = false,
};

pub const NetworkConfig = struct {
    name: []const u8,
    bridge: []const u8,
    ip: []const u8,
    gw: ?[]const u8 = null,
    ip6: ?[]const u8 = null,
    gw6: ?[]const u8 = null,
    mtu: ?u16 = null,
    rate: ?u32 = null,
    tag: ?u16 = null,
    trunks: ?[]const u16 = null,
    type: []const u8 = "veth",
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

pub fn specToLXCConfig(spec: ContainerSpec, options: struct {
    memory: u32 = 512,
    swap: u32 = 256,
    cores: u32 = 1,
    rootfs: []const u8 = "local-lvm:8",
    ostype: []const u8 = "ubuntu",
    features: Features = .{},
    mount_points: ?[]const MountPoint = null,
}) !LXCConfig {
    var config = LXCConfig{
        .hostname = spec.name,
        .ostype = options.ostype,
        .memory = options.memory,
        .swap = options.swap,
        .cores = options.cores,
        .rootfs = options.rootfs,
        .net0 = NetworkConfig{
            .name = "eth0",
            .bridge = "vmbr0",
            .ip = "dhcp",
        },
        .features = options.features,
    };

    if (options.mount_points) |mounts| {
        if (mounts.len > 0) config.mp0 = mounts[0];
        if (mounts.len > 1) config.mp1 = mounts[1];
        if (mounts.len > 2) config.mp2 = mounts[2];
        if (mounts.len > 3) config.mp3 = mounts[3];
        if (mounts.len > 4) config.mp4 = mounts[4];
        if (mounts.len > 5) config.mp5 = mounts[5];
        if (mounts.len > 6) config.mp6 = mounts[6];
        if (mounts.len > 7) config.mp7 = mounts[7];
    }

    return config;
}

pub fn lxcStatusToContainerStatus(status: LXCStatus) ContainerStatus {
    return switch (status) {
        .running => .running,
        .stopped => .stopped,
        .paused => .stopped,
        .unknown => .unknown,
    };
}
