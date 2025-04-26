const std = @import("std");
const Allocator = std.mem.Allocator;
const logger = std.log.scoped(.lxc_network);

pub const NetworkError = error{
    BridgeCreationFailed,
    VethCreationFailed,
    IpAddressFailed,
    RoutingFailed,
    DnsConfigFailed,
};

pub const NetworkConfig = struct {
    bridge_name: []const u8,
    veth_name: []const u8,
    ip_address: []const u8,
    netmask: []const u8,
    gateway: []const u8,
    dns_servers: [][]const u8,
    allocator: Allocator,

    pub fn init(allocator: Allocator, pod_name: []const u8) !NetworkConfig {
        const bridge_name = try std.fmt.allocPrint(allocator, "lxcbr-{s}", .{pod_name});
        const veth_name = try std.fmt.allocPrint(allocator, "veth-{s}", .{pod_name});

        return NetworkConfig{
            .bridge_name = bridge_name,
            .veth_name = veth_name,
            .ip_address = try allocator.dupe(u8, "10.0.3.1"),
            .netmask = try allocator.dupe(u8, "255.255.255.0"),
            .gateway = try allocator.dupe(u8, "10.0.3.1"),
            .dns_servers = &[_][]const u8{
                try allocator.dupe(u8, "8.8.8.8"),
                try allocator.dupe(u8, "8.8.4.4"),
            },
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *NetworkConfig) void {
        self.allocator.free(self.bridge_name);
        self.allocator.free(self.veth_name);
        self.allocator.free(self.ip_address);
        self.allocator.free(self.netmask);
        self.allocator.free(self.gateway);
        for (self.dns_servers) |server| {
            self.allocator.free(server);
        }
    }
};

pub const LxcNetwork = struct {
    config: NetworkConfig,
    allocator: Allocator,

    const Self = @This();

    pub fn init(allocator: Allocator, pod_name: []const u8) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        self.* = .{
            .config = try NetworkConfig.init(allocator, pod_name),
            .allocator = allocator,
        };

        try self.setupNetwork();
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.config.deinit();
        self.allocator.destroy(self);
    }

    fn setupNetwork(self: *Self) !void {
        logger.info("Setting up network for pod", .{});

        // Створюємо міст
        try self.createBridge();
        errdefer self.deleteBridge();

        // Налаштовуємо IP адресу для мосту
        try self.configureBridgeIp();

        // Налаштовуємо маршрутизацію
        try self.setupRouting();

        // Налаштовуємо DNS
        try self.configureDns();

        logger.info("Network setup completed successfully", .{});
    }

    fn createBridge(self: *Self) !void {
        const result = try std.ChildProcess.exec(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{
                "ip",
                "link",
                "add",
                "name",
                self.config.bridge_name,
                "type",
                "bridge",
            },
        });
        defer {
            self.allocator.free(result.stdout);
            self.allocator.free(result.stderr);
        }

        if (result.term.Exited != 0) {
            logger.err("Failed to create bridge: {s}", .{result.stderr});
            return NetworkError.BridgeCreationFailed;
        }

        // Активуємо міст
        const up_result = try std.ChildProcess.exec(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{
                "ip",
                "link",
                "set",
                self.config.bridge_name,
                "up",
            },
        });
        defer {
            self.allocator.free(up_result.stdout);
            self.allocator.free(up_result.stderr);
        }

        if (up_result.term.Exited != 0) {
            logger.err("Failed to activate bridge: {s}", .{up_result.stderr});
            return NetworkError.BridgeCreationFailed;
        }
    }

    fn configureBridgeIp(self: *Self) !void {
        const result = try std.ChildProcess.exec(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{
                "ip",
                "addr",
                "add",
                self.config.ip_address,
                "dev",
                self.config.bridge_name,
            },
        });
        defer {
            self.allocator.free(result.stdout);
            self.allocator.free(result.stderr);
        }

        if (result.term.Exited != 0) {
            logger.err("Failed to configure bridge IP: {s}", .{result.stderr});
            return NetworkError.IpAddressFailed;
        }
    }

    fn setupRouting(self: *Self) !void {
        // Включаємо IP forwarding
        const sysctl_result = try std.ChildProcess.exec(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{
                "sysctl",
                "-w",
                "net.ipv4.ip_forward=1",
            },
        });
        defer {
            self.allocator.free(sysctl_result.stdout);
            self.allocator.free(sysctl_result.stderr);
        }

        if (sysctl_result.term.Exited != 0) {
            logger.err("Failed to enable IP forwarding: {s}", .{sysctl_result.stderr});
            return NetworkError.RoutingFailed;
        }

        // Налаштовуємо NAT
        const iptables_result = try std.ChildProcess.exec(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{
                "iptables",
                "-t",
                "nat",
                "-A",
                "POSTROUTING",
                "-s",
                "10.0.3.0/24",
                "-j",
                "MASQUERADE",
            },
        });
        defer {
            self.allocator.free(iptables_result.stdout);
            self.allocator.free(iptables_result.stderr);
        }

        if (iptables_result.term.Exited != 0) {
            logger.err("Failed to configure NAT: {s}", .{iptables_result.stderr});
            return NetworkError.RoutingFailed;
        }
    }

    fn configureDns(self: *Self) !void {
        // Створюємо файл resolv.conf для контейнерів
        const dns_file = try std.fs.createFileAbsolute("/etc/lxc/resolv.conf", .{});
        defer dns_file.close();

        const writer = dns_file.writer();
        for (self.config.dns_servers) |server| {
            try writer.print("nameserver {s}\n", .{server});
        }
    }

    fn deleteBridge(self: *Self) void {
        const result = std.ChildProcess.exec(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{
                "ip",
                "link",
                "delete",
                self.config.bridge_name,
            },
        }) catch |err| {
            logger.err("Failed to delete bridge: {}", .{err});
            return;
        };
        defer {
            self.allocator.free(result.stdout);
            self.allocator.free(result.stderr);
        }

        if (result.term.Exited != 0) {
            logger.err("Failed to delete bridge: {s}", .{result.stderr});
        }
    }
}; 