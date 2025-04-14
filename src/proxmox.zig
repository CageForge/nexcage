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
const error_mod = @import("./error.zig");
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
            .timeout = 30_000, // Default timeout of 30 seconds
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

    pub fn makeRequest(self: *Client, method: http.Method, path: []const u8, body: ?[]const u8) ![]const u8 {
        const max_retries = 3;
        var retry_count: u8 = 0;
        var last_error: anyerror = undefined;

        while (retry_count < max_retries) : (retry_count += 1) {
            try self.logger.info("Making {s} request to {s} (attempt {d}/{d})", .{ @tagName(method), path, retry_count + 1, max_retries });

            var url_buffer: [1024]u8 = undefined;
            const url = try std.fmt.bufPrint(&url_buffer, "https://{s}:{d}{s}", .{ self.hosts[self.current_host_index], self.port, path });

            var server_header_buffer: [1024]u8 = undefined;
            var request = try self.client.open(method, try Uri.parse(url), .{
                .server_header_buffer = &server_header_buffer,
            });
            const auth_header = try std.fmt.allocPrint(self.allocator, "PVEAPIToken={s}", .{self.token});
            const headers = [_]http.Header{
                .{ .name = "Authorization", .value = auth_header },
                .{ .name = "Content-Type", .value = "application/json" },
            };
            request.extra_headers = &headers;

            if (body) |b| {
                request.transfer_encoding = .{ .content_length = b.len };
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
            const response_body = try request.reader().readAllAlloc(self.allocator, 1024 * 1024);
            errdefer self.allocator.free(response_body);

            if (status != .ok) {
                try self.logger.err("Request failed with status {d}: {s}", .{ @intFromEnum(status), response_body });

                // Try to parse error response
                if (json.parseFromSliceLeaky(json.Value, self.allocator, response_body, .{})) |parsed| {
                    if (parsed.object.get("errors")) |errors| {
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

            return response_body;
        }

        return last_error;
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

        const resources = try json.parseFromSliceLeaky(json.Value, self.allocator, response, .{});

        var nodes = std.ArrayList(Node).init(self.allocator);
        defer nodes.deinit();

        if (resources.object.get("data")) |data| {
            for (data.array.items) |resource| {
                if (std.mem.eql(u8, resource.object.get("type").?.string, "node")) {
                    try nodes.append(Node{
                        .name = try self.allocator.dupe(u8, resource.object.get("name").?.string),
                        .status = try self.allocator.dupe(u8, resource.object.get("status").?.string),
                        .type = try self.allocator.dupe(u8, resource.object.get("type").?.string),
                    });
                }
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

        const container = try json.parseFromSliceLeaky(LXCContainer, self.allocator, response, .{});
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

        const status = try json.parseFromSliceLeaky(LXCStatus, self.allocator, response, .{});
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

            const containers = try json.parseFromSliceLeaky(json.Value, self.allocator, response, .{});

            if (containers.object.get("data")) |data| {
                for (data.array.items) |container| {
                    try all_containers.append(LXCContainer{
                        .vmid = @intCast(container.object.get("vmid").?.integer),
                        .name = try self.allocator.dupe(u8, container.object.get("name").?.string),
                        .status = try parseStatus(container.object.get("status").?.string),
                        .config = try parseConfig(self.allocator, container.object.get("config").?.object),
                    });
                }
            }
        }

        return try all_containers.toOwnedSlice();
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
        return Features{
            .nesting = if (features.get("nesting")) |v| v.bool else false,
            .fuse = if (features.get("fuse")) |v| v.bool else false,
            .keyctl = if (features.get("keyctl")) |v| v.bool else false,
            .mknod = if (features.get("mknod")) |v| v.bool else false,
            .mount = if (features.get("mount")) |v| blk: {
                var mounts = std.ArrayList([]const u8).init(allocator);
                for (v.array.items) |mount| {
                    try mounts.append(try allocator.dupe(u8, mount.string));
                }
                break :blk try mounts.toOwnedSlice();
            } else &[_][]const u8{},
        };
    }

    pub fn updateLXCConfig(self: *Client, vmid: u32, config: LXCConfig) !void {
        const path = try fmt.allocPrint(self.allocator, "/nodes/{s}/lxc/{d}/config", .{ self.node, vmid });
        defer self.allocator.free(path);

        const body = try json.stringifyAlloc(self.allocator, config, .{});
        defer self.allocator.free(body);

        _ = try self.makeRequest(.PUT, path, body);
    }

    pub fn createSnapshot(self: *Client, vmid: u32, name: []const u8, description: ?[]const u8) !void {
        const path = try fmt.allocPrint(self.allocator, "/nodes/{s}/lxc/{d}/snapshot", .{ self.node, vmid });
        defer self.allocator.free(path);

        var snapshot_config = std.StringHashMap([]const u8).init(self.allocator);
        defer snapshot_config.deinit();

        try snapshot_config.put("snapname", name);
        if (description) |desc| {
            try snapshot_config.put("description", desc);
        }

        const body = try json.stringifyAlloc(self.allocator, snapshot_config, .{});
        defer self.allocator.free(body);

        _ = try self.makeRequest(.POST, path, body);
    }

    pub fn deleteSnapshot(self: *Client, vmid: u32, name: []const u8) !void {
        const path = try fmt.allocPrint(self.allocator, "/nodes/{s}/lxc/{d}/snapshot/{s}", .{ self.node, vmid, name });
        defer self.allocator.free(path);

        _ = try self.makeRequest(.DELETE, path, null);
    }

    pub fn rollbackSnapshot(self: *Client, vmid: u32, name: []const u8) !void {
        const path = try fmt.allocPrint(self.allocator, "/nodes/{s}/lxc/{d}/snapshot/{s}/rollback", .{ self.node, vmid, name });
        defer self.allocator.free(path);

        _ = try self.makeRequest(.POST, path, null);
    }

    pub fn listSnapshots(self: *Client, vmid: u32) ![]Snapshot {
        const path = try fmt.allocPrint(self.allocator, "/nodes/{s}/lxc/{d}/snapshot", .{ self.node, vmid });
        defer self.allocator.free(path);

        const response = try self.makeRequest(.GET, path, null);
        const snapshots = try json.parseFromSliceLeaky([]Snapshot, self.allocator, response, .{});
        return snapshots.value;
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
        const path = try fmt.allocPrint(self.allocator, "/nodes/{s}/lxc/{d}/migrate", .{ self.node, vmid });
        defer self.allocator.free(path);

        var migrate_config = std.StringHashMap([]const u8).init(self.allocator);
        defer migrate_config.deinit();

        try migrate_config.put("target", target_node);
        try migrate_config.put("online", if (options.online) "1" else "0");
        try migrate_config.put("force", if (options.force) "1" else "0");
        if (options.target_storage) |storage| {
            try migrate_config.put("target-storage", storage);
        }
        try migrate_config.put("with-local-disks", if (options.with_local_disks) "1" else "0");

        const body = try json.stringifyAlloc(self.allocator, migrate_config, .{});
        defer self.allocator.free(body);

        _ = try self.makeRequest(.POST, path, body);
    }

    pub fn createTemplate(self: *Client, vmid: u32) !void {
        const path = try fmt.allocPrint(self.allocator, "/nodes/{s}/lxc/{d}/template", .{ self.node, vmid });
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
        const path = try fmt.allocPrint(self.allocator, "/nodes/{s}/lxc/{d}/clone", .{ self.node, vmid });
        defer self.allocator.free(path);

        var clone_config = std.StringHashMap([]const u8).init(self.allocator);
        defer clone_config.deinit();

        try clone_config.put("newid", try fmt.allocPrint(self.allocator, "{d}", .{newid}));
        if (options.name) |name| {
            try clone_config.put("name", name);
        }
        try clone_config.put("full", if (options.full) "1" else "0");
        if (options.target) |target| {
            try clone_config.put("target", target);
        }
        if (options.storage) |storage| {
            try clone_config.put("storage", storage);
        }
        if (options.snapname) |snapname| {
            try clone_config.put("snapname", snapname);
        }

        const body = try json.stringifyAlloc(self.allocator, clone_config, .{});
        defer self.allocator.free(body);

        _ = try self.makeRequest(.POST, path, body);
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
