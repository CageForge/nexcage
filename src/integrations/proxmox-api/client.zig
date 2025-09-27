const std = @import("std");
const core = @import("core");
const types = @import("types.zig");

/// Proxmox API HTTP client
/// Proxmox API client
pub const ProxmoxApiClient = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    config: types.ProxmoxApiConfig,
    logger: ?*core.LogContext = null,
    current_host_index: usize = 0,
    hosts: []const []const u8,
    port: u16,
    token: []const u8,
    node: []const u8,

    pub fn init(allocator: std.mem.Allocator, config: types.ProxmoxApiConfig) !*Self {
        const client = try allocator.alloc(Self, 1);
        client[0] = Self{
            .allocator = allocator,
            .config = config,
            .hosts = try allocator.dupe([]const u8, &[_][]const u8{config.host}),
            .port = config.port,
            .token = try allocator.dupe(u8, config.token),
            .node = try allocator.dupe(u8, config.node),
        };
        return &client[0];
    }

    pub fn deinit(self: *Self) void {
        for (self.hosts) |host| {
            self.allocator.free(host);
        }
        self.allocator.free(self.hosts);
        self.allocator.free(self.token);
        self.allocator.free(self.node);
        self.allocator.free(self);
    }

    /// Make HTTP request to Proxmox API
    pub fn makeRequest(self: *Self, method: std.http.Method, path: []const u8) !types.ProxmoxResponse {
        const max_retries = 3;
        var retry_count: u32 = 0;
        var last_error: anyerror = undefined;

        retry_loop: while (retry_count < max_retries) : (retry_count += 1) {
            const host = self.hosts[self.current_host_index];
            const url = try std.fmt.allocPrint(self.allocator, "https://{s}:{d}/api2/json{s}", .{ host, self.port, path });
            defer self.allocator.free(url);

            const uri = std.Uri.parse(url) catch |err| {
                last_error = err;
                if (self.tryNextHost()) continue :retry_loop;
                return err;
            };

            var client = std.http.Client{ .allocator = self.allocator };
            defer client.deinit();

            var req = client.open(method, uri, .{}) catch |err| {
                last_error = err;
                if (self.tryNextHost()) continue :retry_loop;
                return err;
            };
            defer req.deinit();

            // Add authentication header
            req.headers.append("Authorization", try std.fmt.allocPrint(self.allocator, "PVEAPIToken={s}", .{self.token})) catch |err| {
                last_error = err;
                if (self.tryNextHost()) continue :retry_loop;
                return err;
            };

            req.headers.append("Accept", "application/json") catch |err| {
                last_error = err;
                if (self.tryNextHost()) continue :retry_loop;
                return err;
            };

            req.headers.append("User-Agent", "proxmox-lxcri/0.3") catch |err| {
                last_error = err;
                if (self.tryNextHost()) continue :retry_loop;
                return err;
            };

            req.send() catch |err| {
                if (err == error.ConnectionResetByPeer) {
                    if (self.logger) |log| {
                        try log.warn("Connection reset during send, retrying... (attempt {d}/{d})", .{ retry_count + 1, max_retries });
                    }
                    last_error = err;
                    if (self.tryNextHost()) continue :retry_loop;
                    return err;
                }
                last_error = err;
                if (self.tryNextHost()) continue :retry_loop;
                return err;
            };

            req.wait() catch |err| {
                if (err == error.ConnectionResetByPeer) {
                    if (self.logger) |log| {
                        try log.warn("Connection reset during wait, retrying... (attempt {d}/{d})", .{ retry_count + 1, max_retries });
                    }
                    last_error = err;
                    if (self.tryNextHost()) continue :retry_loop;
                    return err;
                }
                last_error = err;
                if (self.tryNextHost()) continue :retry_loop;
                return err;
            };

            const response_body = req.reader().readAllAlloc(self.allocator, std.math.maxInt(usize)) catch |err| {
                last_error = err;
                if (self.tryNextHost()) continue :retry_loop;
                return err;
            };
            defer self.allocator.free(response_body);

            const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, response_body, .{}) catch |err| {
                last_error = err;
                if (self.tryNextHost()) continue :retry_loop;
                return err;
            };

            return types.ProxmoxResponse{
                .allocator = self.allocator,
                .data = parsed.value,
                .success = true,
                .status_code = @intCast(req.response.status.code),
            };
        }

        return last_error;
    }

    /// Make HTTP request with content type
    pub fn makeRequestWithContentType(self: *Self, method: std.http.Method, path: []const u8, body: []const u8, content_type: []const u8) !types.ProxmoxResponse {
        const max_retries = 3;
        var retry_count: u32 = 0;
        var last_error: anyerror = undefined;

        retry_loop: while (retry_count < max_retries) : (retry_count += 1) {
            const host = self.hosts[self.current_host_index];
            const url = try std.fmt.allocPrint(self.allocator, "https://{s}:{d}/api2/json{s}", .{ host, self.port, path });
            defer self.allocator.free(url);

            const uri = std.Uri.parse(url) catch |err| {
                last_error = err;
                if (self.tryNextHost()) continue :retry_loop;
                return err;
            };

            var client = std.http.Client{ .allocator = self.allocator };
            defer client.deinit();

            var req = client.open(method, uri, .{}) catch |err| {
                last_error = err;
                if (self.tryNextHost()) continue :retry_loop;
                return err;
            };
            defer req.deinit();

            // Add headers
            req.headers.append("Authorization", try std.fmt.allocPrint(self.allocator, "PVEAPIToken={s}", .{self.token})) catch |err| {
                last_error = err;
                if (self.tryNextHost()) continue :retry_loop;
                return err;
            };

            req.headers.append("Accept", "application/json") catch |err| {
                last_error = err;
                if (self.tryNextHost()) continue :retry_loop;
                return err;
            };

            req.headers.append("Content-Type", content_type) catch |err| {
                last_error = err;
                if (self.tryNextHost()) continue :retry_loop;
                return err;
            };

            req.headers.append("Content-Length", try std.fmt.allocPrint(self.allocator, "{d}", .{body.len})) catch |err| {
                last_error = err;
                if (self.tryNextHost()) continue :retry_loop;
                return err;
            };

            req.headers.append("User-Agent", "proxmox-lxcri/0.3") catch |err| {
                last_error = err;
                if (self.tryNextHost()) continue :retry_loop;
                return err;
            };

            req.headers.append("Host", host) catch |err| {
                last_error = err;
                if (self.tryNextHost()) continue :retry_loop;
                return err;
            };

            req.send() catch |err| {
                if (err == error.ConnectionResetByPeer) {
                    if (self.logger) |log| {
                        try log.warn("Connection reset during send, retrying... (attempt {d}/{d})", .{ retry_count + 1, max_retries });
                    }
                    last_error = err;
                    if (self.tryNextHost()) continue :retry_loop;
                    return err;
                }
                last_error = err;
                if (self.tryNextHost()) continue :retry_loop;
                return err;
            };

            // Chunked write to mitigate ConnectionResetByPeer on large bodies
            const chunk_size: usize = 4 * 1024;
            var offset: usize = 0;
            while (offset < body.len) {
                const end = @min(offset + chunk_size, body.len);
                const slice = body[offset..end];
                req.writeAll(slice) catch |err| {
                    if (err == error.ConnectionResetByPeer) {
                        if (self.logger) |log| {
                            try log.warn("Connection reset during write, retrying... (attempt {d}/{d})", .{ retry_count + 1, max_retries });
                        }
                        last_error = err;
                        if (self.tryNextHost()) continue :retry_loop;
                        return err;
                    }
                    last_error = err;
                    if (self.tryNextHost()) continue :retry_loop;
                    return err;
                };
                offset = end;
                // short pacing to avoid aggressive proxy resets
                std.time.sleep(5 * std.time.ms_per_s / 1000 * std.time.ns_per_ms);
            }

            req.finish() catch |err| {
                if (err == error.ConnectionResetByPeer) {
                    if (self.logger) |log| {
                        try log.warn("Connection reset during finish, retrying... (attempt {d}/{d})", .{ retry_count + 1, max_retries });
                    }
                    last_error = err;
                    if (self.tryNextHost()) continue :retry_loop;
                    return err;
                }
                last_error = err;
                if (self.tryNextHost()) continue :retry_loop;
                return err;
            };

            req.wait() catch |err| {
                if (err == error.ConnectionResetByPeer) {
                    if (self.logger) |log| {
                        try log.warn("Connection reset during wait, retrying... (attempt {d}/{d})", .{ retry_count + 1, max_retries });
                    }
                    last_error = err;
                    if (self.tryNextHost()) continue :retry_loop;
                    return err;
                }
                last_error = err;
                if (self.tryNextHost()) continue :retry_loop;
                return err;
            };

            const response_body = req.reader().readAllAlloc(self.allocator, std.math.maxInt(usize)) catch |err| {
                last_error = err;
                if (self.tryNextHost()) continue :retry_loop;
                return err;
            };
            defer self.allocator.free(response_body);

            const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, response_body, .{}) catch |err| {
                last_error = err;
                if (self.tryNextHost()) continue :retry_loop;
                return err;
            };

            return types.ProxmoxResponse{
                .allocator = self.allocator,
                .data = parsed.value,
                .success = true,
                .status_code = @intCast(req.response.status.code),
            };
        }

        return last_error;
    }

    /// Try to switch to next host
    fn tryNextHost(self: *Self) bool {
        if (self.hosts.len <= 1) return false;
        self.current_host_index = (self.current_host_index + 1) % self.hosts.len;
        return true;
    }

    /// Set logger
    pub fn setLogger(self: *Self, logger: *core.LogContext) void {
        self.logger = logger;
    }
};
