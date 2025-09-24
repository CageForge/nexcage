const std = @import("std");
const types = @import("types");
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
        
        // Звільняємо hosts та token
        for (self.hosts) |host| {
            self.allocator.free(host);
        }
        self.allocator.free(self.hosts);
        self.allocator.free(self.token);
        
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
        const max_retries = 5;
        var retry_count: u8 = 0;
        var last_error: anyerror = undefined;

        retry_loop: while (retry_count < max_retries) : (retry_count += 1) {
            if (retry_count > 0) {
                const backoffs = [_]u64{ 250, 500, 1000, 2000, 4000, 8000 };
                const idx: usize = if (retry_count < backoffs.len) retry_count else backoffs.len - 1;
                std.time.sleep(backoffs[idx] * std.time.ns_per_ms);
            }
            // Exponential backoff before retry attempts (skip on first try)
            if (retry_count > 0) {
                const backoffs = [_]u64{ 250, 500, 1000, 2000, 4000, 8000 };
                const idx: usize = if (retry_count < backoffs.len) retry_count else backoffs.len - 1;
                std.time.sleep(backoffs[idx] * std.time.ns_per_ms);
            }
            try self.logger.info("Making {s} request to {s} (attempt {d}/{d})", .{ @tagName(method), path, retry_count + 1, max_retries });

            // Видалено діагностику через проблеми компіляції

            // Спрощене створення URL для діагностики
            const base_url = self.base_urls[self.current_host_index];
            const full_path = try std.fmt.allocPrint(self.allocator, "/api2/json{s}", .{path});
            defer self.allocator.free(full_path);
            
            const url = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ base_url, full_path });
            defer self.allocator.free(url);

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
                .{ .name = "Accept", .value = "application/json" },
                .{ .name = "Connection", .value = "close" },
            };
            request.extra_headers = &headers;

            if (body) |b| {
                // For JSON small bodies keep content-length
                request.transfer_encoding = .{ .content_length = b.len };
            }

            request.send() catch |err| {
                if (err == error.ConnectionResetByPeer) {
                    try self.logger.warn("Connection reset by peer, retrying... (attempt {d}/{d})", .{ retry_count + 1, max_retries });
                    last_error = err;
                    if (self.tryNextHost()) continue :retry_loop;
                    return err;
                }
                return err;
            };
            if (body) |b| {
                // Write request body in small chunks to reduce risk of TLS resets
                const chunk_size: usize = 16 * 1024;
                var offset: usize = 0;
                while (offset < b.len) {
                    const end = @min(offset + chunk_size, b.len);
                    const slice = b[offset..end];
                    request.writeAll(slice) catch |err| {
                        if (err == error.ConnectionResetByPeer) {
                            try self.logger.warn("Connection reset during write, retrying... (attempt {d}/{d})", .{ retry_count + 1, max_retries });
                            last_error = err;
                            if (self.tryNextHost()) continue :retry_loop;
                            return err;
                        }
                        return err;
                    };
                    offset = end;
                }
            }
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

    pub fn makeRequestWithContentType(self: *Client, method: http.Method, path: []const u8, body: ?[]const u8, content_type_value: []const u8) ![]const u8 {
        const max_retries = 5;
        var retry_count: u8 = 0;
        var last_error: anyerror = undefined;

        retry_loop: while (retry_count < max_retries) : (retry_count += 1) {
            try self.logger.info("Making {s} request to {s} (attempt {d}/{d})", .{ @tagName(method), path, retry_count + 1, max_retries });

            const base_url = self.base_urls[self.current_host_index];
            const full_path = try std.fmt.allocPrint(self.allocator, "/api2/json{s}", .{path});
            defer self.allocator.free(full_path);

            const url = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ base_url, full_path });
            defer self.allocator.free(url);

            var server_header_buffer: [1024]u8 = undefined;
            var request = try self.client.open(method, try Uri.parse(url), .{ 
                .server_header_buffer = &server_header_buffer,
            });
            defer request.deinit();

            const auth_header = try std.fmt.allocPrint(self.allocator, "PVEAPIToken={s}", .{self.token});
            defer self.allocator.free(auth_header);

            const headers = [_]http.Header{
                .{ .name = "Authorization", .value = auth_header },
                .{ .name = "Content-Type", .value = content_type_value },
                .{ .name = "Accept", .value = "application/json" },
                .{ .name = "Connection", .value = "close" },
            };
            request.extra_headers = &headers;

            if (body) |b| {
                // Use Content-Length for multipart uploads
                request.transfer_encoding = .{ .content_length = b.len };
            }

            request.send() catch |err| {
                if (err == error.ConnectionResetByPeer) {
                    try self.logger.warn("Connection reset by peer, retrying... (attempt {d}/{d})", .{ retry_count + 1, max_retries });
                    last_error = err;
                    if (self.tryNextHost()) continue :retry_loop;
                    return err;
                }
                return err;
            };
            if (body) |b| {
                // Chunked write to mitigate ConnectionResetByPeer on large bodies
                const chunk_size: usize = 8 * 1024;
                var offset: usize = 0;
                while (offset < b.len) {
                    const end = @min(offset + chunk_size, b.len);
                    const slice = b[offset..end];
                    request.writeAll(slice) catch |err| {
                        if (err == error.ConnectionResetByPeer) {
                            try self.logger.warn("Connection reset during write, retrying... (attempt {d}/{d})", .{ retry_count + 1, max_retries });
                            last_error = err;
                            if (self.tryNextHost()) continue :retry_loop;
                            return err;
                        }
                        return err;
                    };
                    offset = end;
                }
            }
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
