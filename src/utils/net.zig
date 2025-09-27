const std = @import("std");
const core = @import("core");
const types = core.types;

/// Network utilities
/// Network operations interface
pub const NetOperations = struct {
    const Self = @This();

    /// Check if host is reachable
    isReachable: *const fn (self: *Self, host: []const u8, port: u16) bool,

    /// Resolve hostname to IP
    resolve: *const fn (self: *Self, hostname: []const u8, allocator: std.mem.Allocator) types.Error![]const u8,

    /// Get local IP address
    getLocalIP: *const fn (self: *Self, allocator: std.mem.Allocator) types.Error![]const u8,

    /// Test network connectivity
    testConnectivity: *const fn (self: *Self, host: []const u8, port: u16) types.Error!void,

    /// Get network interfaces
    getInterfaces: *const fn (self: *Self, allocator: std.mem.Allocator) types.Error![]NetworkInterface,
};

/// Network interface information
pub const NetworkInterface = struct {
    allocator: std.mem.Allocator,
    name: []const u8,
    ip_address: ?[]const u8 = null,
    mac_address: ?[]const u8 = null,
    is_up: bool = false,
    mtu: ?u32 = null,

    pub fn deinit(self: *NetworkInterface) void {
        self.allocator.free(self.name);
        if (self.ip_address) |ip| self.allocator.free(ip);
        if (self.mac_address) |mac| self.allocator.free(mac);
    }
};

/// Default network operations implementation
pub const DefaultNetOperations = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) DefaultNetOperations {
        return DefaultNetOperations{
            .allocator = allocator,
        };
    }

    pub fn isReachable(self: *DefaultNetOperations, host: []const u8, port: u16) bool {
        _ = self;
        const address = std.net.Address.parseIp4(host, port) catch return false;
        const socket = std.os.socket(address.any.family, std.os.SOCK.STREAM, 0) catch return false;
        defer std.os.close(socket);

        const result = std.os.connect(socket, &address.any, address.getOsSockLen());
        return result == .{};
    }

    pub fn resolve(self: *DefaultNetOperations, hostname: []const u8, allocator: std.mem.Allocator) types.Error![]const u8 {
        _ = self;

        // Simple implementation - try to parse as IP first
        if (std.net.Address.parseIp4(hostname, 0)) |_| {
            return allocator.dupe(u8, hostname);
        } else |_| {}

        if (std.net.Address.parseIp6(hostname, 0)) |_| {
            return allocator.dupe(u8, hostname);
        } else |_| {}

        // For now, return the hostname as-is
        // In a real implementation, you would use getaddrinfo or similar
        return allocator.dupe(u8, hostname);
    }

    pub fn getLocalIP(self: *DefaultNetOperations, allocator: std.mem.Allocator) types.Error![]const u8 {
        _ = self;

        // Simple implementation - try to get IP from a known interface
        // In a real implementation, you would iterate through network interfaces
        return allocator.dupe(u8, "127.0.0.1");
    }

    pub fn testConnectivity(self: *DefaultNetOperations, host: []const u8, port: u16) types.Error!void {
        _ = self;

        const address = std.net.Address.parseIp4(host, port) catch return types.Error.InvalidInput;
        const socket = std.os.socket(address.any.family, std.os.SOCK.STREAM, 0) catch return types.Error.NetworkError;
        defer std.os.close(socket);

        std.os.connect(socket, &address.any, address.getOsSockLen()) catch |err| switch (err) {
            error.ConnectionRefused => return types.Error.NetworkError,
            error.NetworkUnreachable => return types.Error.NetworkError,
            error.HostUnreachable => return types.Error.NetworkError,
            error.AddressInUse => return types.Error.NetworkError,
            error.BrokenPipe => return types.Error.NetworkError,
            error.NetworkDown => return types.Error.NetworkError,
            error.SystemResources => return types.Error.NetworkError,
            error.TimedOut => return types.Error.Timeout,
            else => return types.Error.NetworkError,
        };
    }

    pub fn getInterfaces(self: *DefaultNetOperations, allocator: std.mem.Allocator) types.Error![]NetworkInterface {
        _ = self;

        // Simple implementation - return a basic interface
        // In a real implementation, you would read from /proc/net/dev or use netlink
        const interfaces = try allocator.alloc(NetworkInterface, 1);

        interfaces[0] = NetworkInterface{
            .allocator = allocator,
            .name = try allocator.dupe(u8, "lo"),
            .ip_address = try allocator.dupe(u8, "127.0.0.1"),
            .is_up = true,
            .mtu = 65536,
        };

        return interfaces;
    }
};

/// HTTP client utilities
pub const HTTPClient = struct {
    allocator: std.mem.Allocator,
    client: std.http.Client,
    timeout: ?u64 = null,

    pub fn init(allocator: std.mem.Allocator, timeout: ?u64) HTTPClient {
        return HTTPClient{
            .allocator = allocator,
            .client = std.http.Client{ .allocator = allocator },
            .timeout = timeout,
        };
    }

    pub fn deinit(self: *HTTPClient) void {
        self.client.deinit();
    }

    pub fn get(self: *HTTPClient, url: []const u8) types.Error![]u8 {
        const uri = std.Uri.parse(url) catch return types.Error.InvalidInput;

        var req = self.client.open(.GET, uri, .{}) catch |err| switch (err) {
            error.OutOfMemory => return types.Error.OutOfMemory,
            error.InvalidCharacter => return types.Error.InvalidInput,
            error.InvalidFormat => return types.Error.InvalidInput,
            error.MissingPort => return types.Error.InvalidInput,
            error.StreamTooLong => return types.Error.InvalidInput,
            error.UnexpectedEndOfInput => return types.Error.InvalidInput,
            else => return types.Error.NetworkError,
        };
        defer req.deinit();

        req.send() catch |err| switch (err) {
            error.ConnectionRefused => return types.Error.NetworkError,
            error.NetworkUnreachable => return types.Error.NetworkError,
            error.HostUnreachable => return types.Error.NetworkError,
            error.AddressInUse => return types.Error.NetworkError,
            error.BrokenPipe => return types.Error.NetworkError,
            error.NetworkDown => return types.Error.NetworkError,
            error.SystemResources => return types.Error.NetworkError,
            error.TimedOut => return types.Error.Timeout,
            else => return types.Error.NetworkError,
        };

        req.wait() catch |err| switch (err) {
            error.ConnectionRefused => return types.Error.NetworkError,
            error.NetworkUnreachable => return types.Error.NetworkError,
            error.HostUnreachable => return types.Error.NetworkError,
            error.AddressInUse => return types.Error.NetworkError,
            error.BrokenPipe => return types.Error.NetworkError,
            error.NetworkDown => return types.Error.NetworkError,
            error.SystemResources => return types.Error.NetworkError,
            error.TimedOut => return types.Error.Timeout,
            else => return types.Error.NetworkError,
        };

        return req.reader().readAllAlloc(self.allocator, std.math.maxInt(usize)) catch |err| switch (err) {
            error.OutOfMemory => return types.Error.OutOfMemory,
            else => return types.Error.NetworkError,
        };
    }

    pub fn post(self: *HTTPClient, url: []const u8, body: []const u8, content_type: []const u8) types.Error![]u8 {
        const uri = std.Uri.parse(url) catch return types.Error.InvalidInput;

        var req = self.client.open(.POST, uri, .{}) catch |err| switch (err) {
            error.OutOfMemory => return types.Error.OutOfMemory,
            error.InvalidCharacter => return types.Error.InvalidInput,
            error.InvalidFormat => return types.Error.InvalidInput,
            error.MissingPort => return types.Error.InvalidInput,
            error.StreamTooLong => return types.Error.InvalidInput,
            error.UnexpectedEndOfInput => return types.Error.InvalidInput,
            else => return types.Error.NetworkError,
        };
        defer req.deinit();

        req.headers.append("Content-Type", content_type) catch return types.Error.NetworkError;
        req.headers.append("Content-Length", std.fmt.allocPrint(self.allocator, "{d}", .{body.len}) catch return types.Error.OutOfMemory) catch return types.Error.NetworkError;

        req.send() catch |err| switch (err) {
            error.ConnectionRefused => return types.Error.NetworkError,
            error.NetworkUnreachable => return types.Error.NetworkError,
            error.HostUnreachable => return types.Error.NetworkError,
            error.AddressInUse => return types.Error.NetworkError,
            error.BrokenPipe => return types.Error.NetworkError,
            error.NetworkDown => return types.Error.NetworkError,
            error.SystemResources => return types.Error.NetworkError,
            error.TimedOut => return types.Error.Timeout,
            else => return types.Error.NetworkError,
        };

        req.writeAll(body) catch |err| switch (err) {
            error.BrokenPipe => return types.Error.NetworkError,
            error.ConnectionResetByPeer => return types.Error.NetworkError,
            error.NotConnected => return types.Error.NetworkError,
            error.SystemResources => return types.Error.NetworkError,
            error.WouldBlock => return types.Error.NetworkError,
            else => return types.Error.NetworkError,
        };

        req.finish() catch |err| switch (err) {
            error.BrokenPipe => return types.Error.NetworkError,
            error.ConnectionResetByPeer => return types.Error.NetworkError,
            error.NotConnected => return types.Error.NetworkError,
            error.SystemResources => return types.Error.NetworkError,
            error.WouldBlock => return types.Error.NetworkError,
            else => return types.Error.NetworkError,
        };

        req.wait() catch |err| switch (err) {
            error.ConnectionRefused => return types.Error.NetworkError,
            error.NetworkUnreachable => return types.Error.NetworkError,
            error.HostUnreachable => return types.Error.NetworkError,
            error.AddressInUse => return types.Error.NetworkError,
            error.BrokenPipe => return types.Error.NetworkError,
            error.NetworkDown => return types.Error.NetworkError,
            error.SystemResources => return types.Error.NetworkError,
            error.TimedOut => return types.Error.Timeout,
            else => return types.Error.NetworkError,
        };

        return req.reader().readAllAlloc(self.allocator, std.math.maxInt(usize)) catch |err| switch (err) {
            error.OutOfMemory => return types.Error.OutOfMemory,
            else => return types.Error.NetworkError,
        };
    }
};
