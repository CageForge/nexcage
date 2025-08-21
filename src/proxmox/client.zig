const std = @import("std");
const types = @import("../common/types");
const logger_mod = @import("logger");
const error_mod = @import("error");
const Error = error_mod.Error;
const http = std.http;
const Uri = std.Uri;
const json = std.json;
const fmt = std.fmt;
const time = std.time;
const Allocator = std.mem.Allocator;

pub const Client = struct {
    allocator: Allocator,
    client: http.Client,
    hosts: []const []const u8,
    base_urls: []const []const u8,
    token: []const u8,
    current_host_index: usize,
    logger: *logger_mod.Logger,
    port: u16,
    node: []const u8,
    timeout: u64 = 30_000,

    pub fn init(
        allocator: Allocator,
        hosts: []const []const u8,
        token: []const u8,
        logger_instance: *logger_mod.Logger,
        port: u16,
        node: []const u8,
    ) !Client {
        if (hosts.len == 0) return Error.ProxmoxInvalidConfig;
        if (token.len == 0) return Error.ProxmoxInvalidToken;
        if (node.len == 0) return Error.ProxmoxInvalidNode;

        var base_urls = try allocator.alloc([]const u8, hosts.len);
        errdefer allocator.free(base_urls);

        for (hosts, 0..) |host, i| {
            base_urls[i] = try fmt.allocPrint(allocator, "https://{s}:{d}", .{
                host,
                port,
            });
        }

        var client = http.Client{ .allocator = allocator };
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
            .timeout = 30_000,
        };
    }

    pub fn deinit(self: *Client) void {
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
            const url = try std.fmt.bufPrint(&url_buffer, "{s}/api2/json{s}", .{ self.base_urls[self.current_host_index], path });

            var server_header_buffer: [1024]u8 = undefined;
            var request = try self.client.open(method, try Uri.parse(url), .{
                .server_header_buffer = &server_header_buffer,
            });
            defer request.deinit();

            const auth_header = try std.fmt.allocPrint(self.allocator, "PVEAPIToken={s}", .{self.token});
            defer self.allocator.free(auth_header);

            const headers = [_]http.Header{
                .{ .name = "Authorization", .value = auth_header },
                .{ .name = "Content-Type", .value = "application/json" },
            };
            request.extra_headers = &headers;

            if (body) |b| {
                request.transfer_encoding = .{ .content_length = b.len };
            }

            try request.send();
            if (body) |b| try request.writeAll(b);
            try request.finish();
            try request.wait();

            const status = request.response.status;
            const response_body = try request.reader().readAllAlloc(self.allocator, 1024 * 1024);
            defer self.allocator.free(response_body);

            if (status != .ok) {
                try self.logger.err("Request failed with status {d}: {s}", .{ @intFromEnum(status), response_body });
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

            return try self.allocator.dupe(u8, response_body);
        }

        return last_error;
    }
};
