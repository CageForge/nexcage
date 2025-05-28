const std = @import("std");
const network = @import("mod.zig");

pub const NetworkValidationError = error{
    InvalidInterface,
    InvalidBridge,
    InvalidVLAN,
    InvalidMTU,
    InvalidRate,
    InvalidFirewall,
    InvalidDNS,
    InvalidIPRange,
    InvalidGateway,
    InvalidRoute,
    InvalidNamespace,
};

pub const NetworkValidator = struct {
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
        };
    }

    /// Validates interface settings
    pub fn validateInterface(self: *Self, name: []const u8) !void {
        _ = self;
        if (name.len == 0 or name.len > 15) {
            return NetworkValidationError.InvalidInterface;
        }

        // Перевіряємо допустимі символи
        for (name) |c| {
            switch (c) {
                'a'...'z', 'A'...'Z', '0'...'9', '_', '-' => continue,
                else => return NetworkValidationError.InvalidInterface,
            }
        }
    }

    /// Validates bridge settings
    pub fn validateBridge(self: *Self, bridge: []const u8) !void {
        _ = self;
        if (bridge.len == 0 or bridge.len > 15) {
            return NetworkValidationError.InvalidBridge;
        }

        // Перевіряємо формат vmbr{N}
        if (!std.mem.startsWith(u8, bridge, "vmbr")) {
            return NetworkValidationError.InvalidBridge;
        }

        const num = std.fmt.parseInt(u8, bridge[4..], 10) catch {
            return NetworkValidationError.InvalidBridge;
        };

        if (num > 255) {
            return NetworkValidationError.InvalidBridge;
        }
    }

    /// Validates VLAN ID
    pub fn validateVLAN(self: *Self, vlan: u16) !void {
        _ = self;
        if (vlan == 0 or vlan > 4094) {
            return NetworkValidationError.InvalidVLAN;
        }
    }

    /// Validates MTU
    pub fn validateMTU(self: *Self, mtu: u32) !void {
        _ = self;
        if (mtu < 68 or mtu > 65535) {
            return NetworkValidationError.InvalidMTU;
        }
    }

    /// Validates network settings
    pub fn validateRate(self: *Self, rate: u32) !void {
        _ = self;
        if (rate == 0) {
            return NetworkValidationError.InvalidRate;
        }
    }

    /// Validates firewall settings
    pub fn validateFirewall(self: *Self, rules: []const u8) !void {
        _ = self;
        if (rules.len == 0) {
            return NetworkValidationError.InvalidFirewall;
        }

        // TODO: Додати більш детальну валідацію правил
    }

    /// Validates DNS settings
    pub fn validateDNS(self: *Self, servers: []const []const u8) !void {
        for (servers) |server| {
            if (!try network.isValidIPAddress(server)) {
                return NetworkValidationError.InvalidDNS;
            }
        }
    }

    /// Validates IP range
    pub fn validateIPRange(self: *Self, ip: []const u8, cidr: []const u8) !void {
        if (!try network.isValidIPAddress(ip)) {
            return NetworkValidationError.InvalidIPRange;
        }

        // Валідуємо CIDR
        const slash_pos = std.mem.indexOf(u8, cidr, "/") orelse {
            return NetworkValidationError.InvalidIPRange;
        };

        const prefix = std.fmt.parseInt(u8, cidr[slash_pos + 1 ..], 10) catch {
            return NetworkValidationError.InvalidIPRange;
        };

        if (prefix == 0 or prefix > 32) {
            return NetworkValidationError.InvalidIPRange;
        }
    }

    /// Validates gateway
    pub fn validateGateway(self: *Self, gateway: []const u8) !void {
        if (!try network.isValidIPAddress(gateway)) {
            return NetworkValidationError.InvalidGateway;
        }
    }

    /// Validates route
    pub fn validateRoute(self: *Self, network: []const u8, gateway: []const u8) !void {
        try self.validateIPRange(network, network);
        try self.validateGateway(gateway);
    }

    /// Validates namespace
    pub fn validateNamespace(self: *Self, ns: std.fs.File) !void {
        _ = self;
        const stat = try ns.stat();
        if (stat.kind != .directory) {
            return NetworkValidationError.InvalidNamespace;
        }
    }
};

test "NetworkValidator - interface validation" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var validator = NetworkValidator.init(allocator);

    // Valid interfaces
    try validator.validateInterface("eth0");
    try validator.validateInterface("veth0");
    try validator.validateInterface("bond0");
    try validator.validateInterface("wlan0");

    // Invalid interfaces
    try testing.expectError(NetworkValidationError.InvalidInterface, validator.validateInterface(""));
    try testing.expectError(NetworkValidationError.InvalidInterface, validator.validateInterface("very-long-interface-name"));
    try testing.expectError(NetworkValidationError.InvalidInterface, validator.validateInterface("eth0@123"));
}

test "NetworkValidator - bridge validation" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var validator = NetworkValidator.init(allocator);

    // Valid bridges
    try validator.validateBridge("vmbr0");
    try validator.validateBridge("vmbr1");
    try validator.validateBridge("vmbr255");

    // Invalid bridges
    try testing.expectError(NetworkValidationError.InvalidBridge, validator.validateBridge(""));
    try testing.expectError(NetworkValidationError.InvalidBridge, validator.validateBridge("br0"));
    try testing.expectError(NetworkValidationError.InvalidBridge, validator.validateBridge("vmbr256"));
}

test "NetworkValidator - network validation" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var validator = NetworkValidator.init(allocator);

    // Valid settings
    try validator.validateVLAN(1);
    try validator.validateVLAN(4094);
    try validator.validateMTU(1500);
    try validator.validateRate(1000000);

    // Invalid settings
    try testing.expectError(NetworkValidationError.InvalidVLAN, validator.validateVLAN(0));
    try testing.expectError(NetworkValidationError.InvalidVLAN, validator.validateVLAN(4095));
    try testing.expectError(NetworkValidationError.InvalidMTU, validator.validateMTU(0));
    try testing.expectError(NetworkValidationError.InvalidRate, validator.validateRate(0));
}
