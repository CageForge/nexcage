const std = @import("std");
const Allocator = std.mem.Allocator;
const json = std.json;
const http = std.http;
const logger = std.log.scoped(.proxmox_api);

pub const ProxmoxError = error{
    AuthenticationFailed,
    RequestFailed,
    InvalidResponse,
    ResourceNotFound,
    InvalidConfiguration,
};

pub const ProxmoxConfig = struct {
    host: []const u8,
    port: u16,
    user: []const u8,
    password: []const u8,
    realm: []const u8 = "pam",
    token_name: ?[]const u8 = null,
    token_value: ?[]const u8 = null,
};

pub const ProxmoxApi = struct {
    config: ProxmoxConfig,
    allocator: Allocator,
    ticket: ?[]const u8,
    csrf_token: ?[]const u8,

    const Self = @This();

    pub fn init(allocator: Allocator, config: ProxmoxConfig) Self {
        return .{
            .config = config,
            .allocator = allocator,
            .ticket = null,
            .csrf_token = null,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.ticket) |ticket| {
            self.allocator.free(ticket);
        }
        if (self.csrf_token) |token| {
            self.allocator.free(token);
        }
    }

    pub fn authenticate(self: *Self) !void {
        logger.info("Authenticating with Proxmox VE", .{});

        const url = try std.fmt.allocPrint(
            self.allocator,
            "https://{s}:{d}/api2/json/access/ticket",
            .{ self.config.host, self.config.port }
        );
        defer self.allocator.free(url);

        var client = http.Client{ .allocator = self.allocator };
        defer client.deinit();

        var headers = http.Headers.init(self.allocator);
        defer headers.deinit();
        try headers.append("Content-Type", "application/x-www-form-urlencoded");

        const body = try std.fmt.allocPrint(
            self.allocator,
            "username={s}@{s}&password={s}",
            .{ self.config.user, self.config.realm, self.config.password }
        );
        defer self.allocator.free(body);

        var response = try client.post(url, headers, body);
        defer response.deinit();

        if (response.status_code != 200) {
            logger.err("Authentication failed: {d}", .{response.status_code});
            return ProxmoxError.AuthenticationFailed;
        }

        // Парсимо відповідь
        const response_body = try response.reader().readAllAlloc(self.allocator, 4096);
        defer self.allocator.free(response_body);

        var parsed = try json.parseFromSlice(std.json.Value, self.allocator, response_body, .{});
        defer parsed.deinit();

        const data = parsed.value.object.get("data") orelse return ProxmoxError.InvalidResponse;
        self.ticket = try self.allocator.dupe(u8, data.object.get("ticket").?.string);
        self.csrf_token = try self.allocator.dupe(u8, data.object.get("CSRFPreventionToken").?.string);
    }

    pub fn createContainer(self: *Self, node: []const u8, vmid: u32, config: anytype) !void {
        logger.info("Creating container on node {s} with ID {d}", .{ node, vmid });

        if (self.ticket == null) {
            try self.authenticate();
        }

        const url = try std.fmt.allocPrint(
            self.allocator,
            "https://{s}:{d}/api2/json/nodes/{s}/lxc",
            .{ self.config.host, self.config.port, node }
        );
        defer self.allocator.free(url);

        var headers = http.Headers.init(self.allocator);
        defer headers.deinit();
        try headers.append("Cookie", try std.fmt.allocPrint(self.allocator, "PVEAuthCookie={s}", .{self.ticket.?}));
        try headers.append("CSRFPreventionToken", self.csrf_token.?);
        try headers.append("Content-Type", "application/json");

        var client = http.Client{ .allocator = self.allocator };
        defer client.deinit();

        const body = try std.json.stringifyAlloc(self.allocator, config, .{});
        defer self.allocator.free(body);

        var response = try client.post(url, headers, body);
        defer response.deinit();

        if (response.status_code != 200) {
            logger.err("Failed to create container: {d}", .{response.status_code});
            return ProxmoxError.RequestFailed;
        }
    }

    pub fn startContainer(self: *Self, node: []const u8, vmid: u32) !void {
        logger.info("Starting container {d} on node {s}", .{ vmid, node });

        if (self.ticket == null) {
            try self.authenticate();
        }

        const url = try std.fmt.allocPrint(
            self.allocator,
            "https://{s}:{d}/api2/json/nodes/{s}/lxc/{d}/status/start",
            .{ self.config.host, self.config.port, node, vmid }
        );
        defer self.allocator.free(url);

        var headers = http.Headers.init(self.allocator);
        defer headers.deinit();
        try headers.append("Cookie", try std.fmt.allocPrint(self.allocator, "PVEAuthCookie={s}", .{self.ticket.?}));
        try headers.append("CSRFPreventionToken", self.csrf_token.?);

        var client = http.Client{ .allocator = self.allocator };
        defer client.deinit();

        var response = try client.post(url, headers, "");
        defer response.deinit();

        if (response.status_code != 200) {
            logger.err("Failed to start container: {d}", .{response.status_code});
            return ProxmoxError.RequestFailed;
        }
    }

    pub fn stopContainer(self: *Self, node: []const u8, vmid: u32) !void {
        logger.info("Stopping container {d} on node {s}", .{ vmid, node });

        if (self.ticket == null) {
            try self.authenticate();
        }

        const url = try std.fmt.allocPrint(
            self.allocator,
            "https://{s}:{d}/api2/json/nodes/{s}/lxc/{d}/status/stop",
            .{ self.config.host, self.config.port, node, vmid }
        );
        defer self.allocator.free(url);

        var headers = http.Headers.init(self.allocator);
        defer headers.deinit();
        try headers.append("Cookie", try std.fmt.allocPrint(self.allocator, "PVEAuthCookie={s}", .{self.ticket.?}));
        try headers.append("CSRFPreventionToken", self.csrf_token.?);

        var client = http.Client{ .allocator = self.allocator };
        defer client.deinit();

        var response = try client.post(url, headers, "");
        defer response.deinit();

        if (response.status_code != 200) {
            logger.err("Failed to stop container: {d}", .{response.status_code});
            return ProxmoxError.RequestFailed;
        }
    }

    pub fn deleteContainer(self: *Self, node: []const u8, vmid: u32) !void {
        logger.info("Deleting container {d} on node {s}", .{ vmid, node });

        if (self.ticket == null) {
            try self.authenticate();
        }

        const url = try std.fmt.allocPrint(
            self.allocator,
            "https://{s}:{d}/api2/json/nodes/{s}/lxc/{d}",
            .{ self.config.host, self.config.port, node, vmid }
        );
        defer self.allocator.free(url);

        var headers = http.Headers.init(self.allocator);
        defer headers.deinit();
        try headers.append("Cookie", try std.fmt.allocPrint(self.allocator, "PVEAuthCookie={s}", .{self.ticket.?}));
        try headers.append("CSRFPreventionToken", self.csrf_token.?);

        var client = http.Client{ .allocator = self.allocator };
        defer client.deinit();

        var response = try client.delete(url, headers);
        defer response.deinit();

        if (response.status_code != 200) {
            logger.err("Failed to delete container: {d}", .{response.status_code});
            return ProxmoxError.RequestFailed;
        }
    }

    pub fn addMount(self: *Self, node: []const u8, vmid: u32, mount_point: []const u8, source: []const u8, options: ?[]const u8) !void {
        logger.info("Adding mount point {s} to container {d} on node {s}", .{ mount_point, vmid, node });

        if (self.ticket == null) {
            try self.authenticate();
        }

        const url = try std.fmt.allocPrint(
            self.allocator,
            "https://{s}:{d}/api2/json/nodes/{s}/lxc/{d}/config",
            .{ self.config.host, self.config.port, node, vmid }
        );
        defer self.allocator.free(url);

        var headers = http.Headers.init(self.allocator);
        defer headers.deinit();
        try headers.append("Cookie", try std.fmt.allocPrint(self.allocator, "PVEAuthCookie={s}", .{self.ticket.?}));
        try headers.append("CSRFPreventionToken", self.csrf_token.?);
        try headers.append("Content-Type", "application/x-www-form-urlencoded");

        // Формуємо тіло запиту
        const body = if (options) |opts|
            try std.fmt.allocPrint(
                self.allocator,
                "mp0=local:{s},mp={s},{s}",
                .{ source, mount_point, opts }
            )
        else
            try std.fmt.allocPrint(
                self.allocator,
                "mp0=local:{s},mp={s}",
                .{ source, mount_point }
            );
        defer self.allocator.free(body);

        var client = http.Client{ .allocator = self.allocator };
        defer client.deinit();

        var response = try client.put(url, headers, body);
        defer response.deinit();

        if (response.status_code != 200) {
            logger.err("Failed to add mount point: {d}", .{response.status_code});
            return ProxmoxError.RequestFailed;
        }
    }
}; 