const std = @import("std");
const http = std.http;
const json = std.json;
const mem = std.mem;
const fmt = std.fmt;
const Allocator = std.mem.Allocator;

pub const Client = struct {
    allocator: Allocator,
    host: []const u8,
    port: u16,
    token: []const u8,
    client: http.Client,
    base_url: []const u8,

    pub fn init(options: struct {
        allocator: Allocator,
        host: []const u8,
        port: u16,
        token: []const u8,
    }) !Client {
        const base_url = try fmt.allocPrint(options.allocator, "https://{s}:{d}/api2/json", .{
            options.host,
            options.port,
        });

        return Client{
            .allocator = options.allocator,
            .host = options.host,
            .port = options.port,
            .token = options.token,
            .client = http.Client{ .allocator = options.allocator },
            .base_url = base_url,
        };
    }

    pub fn deinit(self: *Client) void {
        self.allocator.free(self.base_url);
        self.client.deinit();
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

        const url = try fmt.allocPrint(self.allocator, "{s}{s}", .{ self.base_url, path });
        defer self.allocator.free(url);

        var req = try self.client.request(method, try std.Uri.parse(url), headers, .{});
        defer req.deinit();

        if (body) |b| {
            try req.start();
            try req.writeAll(b);
            try req.finish();
        } else {
            try req.start();
        }

        try req.wait();

        const response_body = try req.reader().readAllAlloc(self.allocator, 1024 * 1024);
        defer self.allocator.free(response_body);

        const parsed = try json.parseFromSlice(APIResponse, self.allocator, response_body, .{});
        return parsed.value;
    }

    pub fn createLXC(self: *Client, spec: LXCConfig) !LXCContainer {
        const body = try json.stringifyAlloc(self.allocator, spec, .{});
        defer self.allocator.free(body);

        const response = try self.makeRequest(.POST, "/nodes/localhost/lxc", body);
        if (!response.success) {
            return error.ProxmoxAPIError;
        }

        const container = try json.parseFromValue(LXCContainer, self.allocator, response.data, .{});
        return container.value;
    }

    pub fn deleteLXC(self: *Client, vmid: u32) !void {
        const path = try fmt.allocPrint(self.allocator, "/nodes/localhost/lxc/{d}", .{vmid});
        defer self.allocator.free(path);

        const response = try self.makeRequest(.DELETE, path, null);
        if (!response.success) {
            return error.ProxmoxAPIError;
        }
    }

    pub fn startLXC(self: *Client, vmid: u32) !void {
        const path = try fmt.allocPrint(self.allocator, "/nodes/localhost/lxc/{d}/status/start", .{vmid});
        defer self.allocator.free(path);

        const response = try self.makeRequest(.POST, path, null);
        if (!response.success) {
            return error.ProxmoxAPIError;
        }
    }

    pub fn stopLXC(self: *Client, vmid: u32) !void {
        const path = try fmt.allocPrint(self.allocator, "/nodes/localhost/lxc/{d}/status/stop", .{vmid});
        defer self.allocator.free(path);

        const response = try self.makeRequest(.POST, path, null);
        if (!response.success) {
            return error.ProxmoxAPIError;
        }
    }

    pub fn getLXCStatus(self: *Client, vmid: u32) !LXCStatus {
        const path = try fmt.allocPrint(self.allocator, "/nodes/localhost/lxc/{d}/status/current", .{vmid});
        defer self.allocator.free(path);

        const response = try self.makeRequest(.GET, path, null);
        if (!response.success) {
            return error.ProxmoxAPIError;
        }

        const status = try json.parseFromValue(LXCStatus, self.allocator, response.data, .{});
        return status.value;
    }

    pub fn listLXCs(self: *Client) ![]LXCContainer {
        const response = try self.makeRequest(.GET, "/nodes/localhost/lxc", null);
        if (!response.success) {
            return error.ProxmoxAPIError;
        }

        const containers = try json.parseFromValue([]LXCContainer, self.allocator, response.data, .{});
        return containers.value;
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

// Proxmox API response types
pub const APIResponse = struct {
    data: json.Value,
    success: bool,
    err_msg: ?[]const u8,
};
