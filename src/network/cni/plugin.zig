const std = @import("std");
const types = @import("types");

pub const Error = error{
    ConfigurationError,
    NetworkSetupFailed,
    NetworkCleanupFailed,
    InvalidVersion,
};

/// CNI Plugin interface
pub const Plugin = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    version: types.Version,
    config: types.NetworkConfig,

    pub fn init(allocator: std.mem.Allocator, version: []const u8, config: types.NetworkConfig) !Self {
        return Self{
            .allocator = allocator,
            .version = try types.Version.init(allocator, version),
            .config = config,
        };
    }

    pub fn deinit(self: *Self) void {
        self.version.deinit(self.allocator);
        self.config.deinit(self.allocator);
    }

    /// Add network interface to the container
    pub fn add(self: *Self, container_id: []const u8, netns_path: []const u8) !void {
        // Validate CNI version
        if (!self.isVersionSupported()) {
            return Error.InvalidVersion;
        }

        // Setup network namespace
        try self.setupNetworkNamespace(container_id, netns_path);

        // Configure interface
        try self.configureInterface(container_id);

        // Setup IPAM if configured
        if (self.config.ipam) |ipam| {
            try self.setupIPAM(container_id, ipam);
        }

        // Configure DNS if needed
        if (self.config.dns) |dns| {
            try self.configureDNS(container_id, dns);
        }
    }

    /// Remove network interface from the container
    pub fn del(self: *Self, container_id: []const u8, netns_path: []const u8) !void {
        // Validate CNI version
        if (!self.isVersionSupported()) {
            return Error.InvalidVersion;
        }

        // Cleanup IPAM if configured
        if (self.config.ipam) |ipam| {
            try self.cleanupIPAM(container_id, ipam);
        }

        // Remove interface
        try self.removeInterface(container_id);

        // Cleanup network namespace
        try self.cleanupNetworkNamespace(container_id, netns_path);
    }

    /// Check if container network is ready
    pub fn check(self: *Self, container_id: []const u8) !void {
        // Validate CNI version
        if (!self.isVersionSupported()) {
            return Error.InvalidVersion;
        }

        // Check interface status
        try self.checkInterface(container_id);

        // Check IPAM if configured
        if (self.config.ipam) |ipam| {
            try self.checkIPAM(container_id, ipam);
        }
    }

    // Internal methods
    fn isVersionSupported(self: *const Self) bool {
        // Currently supporting 0.4.0 and above
        return std.mem.startsWith(u8, self.version.cniVersion, "0.4") or
            std.mem.startsWith(u8, self.version.cniVersion, "1.0");
    }

    fn setupNetworkNamespace(self: *const Self, container_id: []const u8, netns_path: []const u8) !void {
        _ = container_id;
        _ = netns_path;
        // Implementation will be added in the network namespace module
    }

    fn cleanupNetworkNamespace(self: *const Self, container_id: []const u8, netns_path: []const u8) !void {
        _ = container_id;
        _ = netns_path;
        // Implementation will be added in the network namespace module
    }

    fn configureInterface(self: *const Self, container_id: []const u8) !void {
        _ = container_id;
        // Implementation will be added in the interface module
    }

    fn removeInterface(self: *const Self, container_id: []const u8) !void {
        _ = container_id;
        // Implementation will be added in the interface module
    }

    fn checkInterface(self: *const Self, container_id: []const u8) !void {
        _ = container_id;
        // Implementation will be added in the interface module
    }

    fn setupIPAM(self: *const Self, container_id: []const u8, ipam: types.IPAM) !void {
        _ = container_id;
        _ = ipam;
        // Implementation will be added in the IPAM module
    }

    fn cleanupIPAM(self: *const Self, container_id: []const u8, ipam: types.IPAM) !void {
        _ = container_id;
        _ = ipam;
        // Implementation will be added in the IPAM module
    }

    fn checkIPAM(self: *const Self, container_id: []const u8, ipam: types.IPAM) !void {
        _ = container_id;
        _ = ipam;
        // Implementation will be added in the IPAM module
    }

    fn configureDNS(self: *const Self, container_id: []const u8, dns: types.DNS) !void {
        _ = container_id;
        _ = dns;
        // Implementation will be added in the DNS module
    }
};
