const std = @import("std");

/// CNI specification version
pub const Version = struct {
    cniVersion: []const u8,

    pub fn init(allocator: std.mem.Allocator, version: []const u8) !Version {
        return Version{
            .cniVersion = try allocator.dupe(u8, version),
        };
    }

    pub fn deinit(self: *Version, allocator: std.mem.Allocator) void {
        allocator.free(self.cniVersion);
    }
};

/// Network configuration for CNI
pub const NetworkConfig = struct {
    name: []const u8,
    type: []const u8,
    bridge: ?[]const u8 = null,
    isGateway: bool = false,
    ipMasq: bool = false,
    hairpinMode: bool = false,
    ipam: ?IPAM = null,
    dns: ?DNS = null,

    pub fn init(allocator: std.mem.Allocator, name: []const u8, plugin_type: []const u8) !NetworkConfig {
        return NetworkConfig{
            .name = try allocator.dupe(u8, name),
            .type = try allocator.dupe(u8, plugin_type),
        };
    }

    pub fn deinit(self: *NetworkConfig, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.type);
        if (self.bridge) |bridge| allocator.free(bridge);
        if (self.ipam) |*ipam| ipam.deinit(allocator);
        if (self.dns) |*dns| dns.deinit(allocator);
    }
};

/// IP Address Management configuration
pub const IPAM = struct {
    type: []const u8,
    subnet: ?[]const u8 = null,
    routes: ?[]Route = null,

    pub fn init(allocator: std.mem.Allocator, ipam_type: []const u8) !IPAM {
        return IPAM{
            .type = try allocator.dupe(u8, ipam_type),
        };
    }

    pub fn deinit(self: *IPAM, allocator: std.mem.Allocator) void {
        allocator.free(self.type);
        if (self.subnet) |subnet| allocator.free(subnet);
        if (self.routes) |routes| {
            for (routes) |*route| route.deinit(allocator);
            allocator.free(routes);
        }
    }
};

/// Route configuration
pub const Route = struct {
    dst: []const u8,
    gw: ?[]const u8 = null,

    pub fn init(allocator: std.mem.Allocator, dst: []const u8) !Route {
        return Route{
            .dst = try allocator.dupe(u8, dst),
        };
    }

    pub fn deinit(self: *Route, allocator: std.mem.Allocator) void {
        allocator.free(self.dst);
        if (self.gw) |gw| allocator.free(gw);
    }
};

/// DNS configuration
pub const DNS = struct {
    nameservers: ?[][]const u8 = null,
    domain: ?[]const u8 = null,
    search: ?[][]const u8 = null,
    options: ?[][]const u8 = null,

    pub fn init() DNS {
        return DNS{};
    }

    pub fn deinit(self: *DNS, allocator: std.mem.Allocator) void {
        if (self.nameservers) |ns| {
            for (ns) |server| allocator.free(server);
            allocator.free(ns);
        }
        if (self.domain) |domain| allocator.free(domain);
        if (self.search) |search| {
            for (search) |domain| allocator.free(domain);
            allocator.free(search);
        }
        if (self.options) |options| {
            for (options) |opt| allocator.free(opt);
            allocator.free(options);
        }
    }
};
