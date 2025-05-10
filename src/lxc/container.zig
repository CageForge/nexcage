const std = @import("std");
const Allocator = std.mem.Allocator;
const logger_mod = @import("logger");
const errors = @import("error");

pub const Config = struct {
    allocator: Allocator,
    name: ?[]const u8 = null,
    rootfs: ?[]const u8 = null,
    hostname: ?[]const u8 = null,
    args: ?[][]const u8 = null,
    environment: std.ArrayList([]const u8),
    working_directory: ?[]const u8 = null,
    uid: ?u32 = null,
    gid: ?u32 = null,
    additional_gids: ?[]const u32 = null,
    bounding_capabilities: ?[][]const u8 = null,
    effective_capabilities: ?[][]const u8 = null,
    network_interfaces: std.ArrayList(NetworkInterface),
    dns_servers: ?[][]const u8 = null,
    dns_search_domains: ?[][]const u8 = null,
    memory_limit: u64 = 0,
    memory_reservation: u64 = 0,
    memory_swap: u64 = 0,
    cpu_shares: u64 = 0,
    cpu_quota: u64 = 0,
    cpu_period: u64 = 0,
    cpus: ?[]const u8 = null,
    mems: ?[]const u8 = null,
    blockio_weight: u64 = 0,
    hugepage_limits: std.ArrayList(HugepageLimit),
    namespaces: std.ArrayList(Namespace),
    devices: std.ArrayList(Device),
    mounts: std.ArrayList(Mount),

    const Self = @This();

    pub fn init(allocator: Allocator) !*Self {
        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .name = null,
            .rootfs = null,
            .hostname = null,
            .environment = std.ArrayList([]const u8).init(allocator),
            .working_directory = null,
            .uid = null,
            .gid = null,
            .additional_gids = null,
            .bounding_capabilities = null,
            .effective_capabilities = null,
            .network_interfaces = std.ArrayList(NetworkInterface).init(allocator),
            .dns_servers = null,
            .dns_search_domains = null,
            .memory_limit = 0,
            .memory_reservation = 0,
            .memory_swap = 0,
            .cpu_shares = 0,
            .cpu_quota = 0,
            .cpu_period = 0,
            .cpus = null,
            .mems = null,
            .blockio_weight = 0,
            .hugepage_limits = std.ArrayList(HugepageLimit).init(allocator),
            .namespaces = std.ArrayList(Namespace).init(allocator),
            .devices = std.ArrayList(Device).init(allocator),
            .mounts = std.ArrayList(Mount).init(allocator),
        };
        return self;
    }

    pub fn deinit(self: *Self) void {
        if (self.name) |name| self.allocator.free(name);
        if (self.rootfs) |rootfs| self.allocator.free(rootfs);
        if (self.hostname) |hostname| self.allocator.free(hostname);
        for (self.environment.items) |env| self.allocator.free(env);
        self.environment.deinit();
        if (self.working_directory) |wd| self.allocator.free(wd);
        if (self.additional_gids) |gids| self.allocator.free(gids);
        if (self.bounding_capabilities) |caps| {
            for (caps) |cap| self.allocator.free(cap);
            self.allocator.free(caps);
        }
        if (self.effective_capabilities) |caps| {
            for (caps) |cap| self.allocator.free(cap);
            self.allocator.free(caps);
        }
        self.network_interfaces.deinit();
        if (self.dns_servers) |servers| {
            for (servers) |server| self.allocator.free(server);
            self.allocator.free(servers);
        }
        if (self.dns_search_domains) |domains| {
            for (domains) |domain| self.allocator.free(domain);
            self.allocator.free(domains);
        }
        if (self.cpus) |cpus| self.allocator.free(cpus);
        if (self.mems) |mems| self.allocator.free(mems);
        self.hugepage_limits.deinit();
        self.namespaces.deinit();
        self.devices.deinit();
        for (self.mounts.items) |*mount| mount.deinit(self.allocator);
        self.mounts.deinit();
        self.allocator.destroy(self);
    }

    pub fn setName(self: *Self, name: []const u8) !void {
        if (self.name) |old_name| self.allocator.free(old_name);
        self.name = try self.allocator.dupe(u8, name);
    }

    pub fn setRootfs(self: *Self, rootfs: []const u8) !void {
        if (self.rootfs) |old_rootfs| self.allocator.free(old_rootfs);
        self.rootfs = try self.allocator.dupe(u8, rootfs);
    }

    pub fn setHostname(self: *Self, hostname: []const u8) !void {
        if (self.hostname) |old_hostname| self.allocator.free(old_hostname);
        self.hostname = try self.allocator.dupe(u8, hostname);
    }

    pub fn addEnvironmentVariable(self: *Self, env: []const u8) !void {
        try self.environment.append(try self.allocator.dupe(u8, env));
    }

    pub fn setWorkingDirectory(self: *Self, wd: []const u8) !void {
        if (self.working_directory) |old_wd| self.allocator.free(old_wd);
        self.working_directory = try self.allocator.dupe(u8, wd);
    }

    pub fn setUID(self: *Self, uid: u32) void {
        self.uid = uid;
    }

    pub fn setGID(self: *Self, gid: u32) void {
        self.gid = gid;
    }

    pub fn setAdditionalGids(self: *Self, gids: []const u32) !void {
        if (self.additional_gids) |old_gids| self.allocator.free(old_gids);
        self.additional_gids = try self.allocator.dupe(u32, gids);
    }

    pub fn setBoundingCapabilities(self: *Self, caps: []const []const u8) !void {
        if (self.bounding_capabilities) |old_caps| {
            for (old_caps) |cap| self.allocator.free(cap);
            self.allocator.free(old_caps);
        }
        var new_caps = try self.allocator.alloc([]const u8, caps.len);
        for (caps, 0..) |cap, i| {
            new_caps[i] = try self.allocator.dupe(u8, cap);
        }
        self.bounding_capabilities = new_caps;
    }

    pub fn setEffectiveCapabilities(self: *Self, caps: []const []const u8) !void {
        if (self.effective_capabilities) |old_caps| {
            for (old_caps) |cap| self.allocator.free(cap);
            self.allocator.free(old_caps);
        }
        var new_caps = try self.allocator.alloc([]const u8, caps.len);
        for (caps, 0..) |cap, i| {
            new_caps[i] = try self.allocator.dupe(u8, cap);
        }
        self.effective_capabilities = new_caps;
    }

    pub fn addNetworkInterface(self: *Self, iface: NetworkInterface) !void {
        try self.network_interfaces.append(iface);
    }

    pub fn setDNSServers(self: *Self, servers: []const []const u8) !void {
        if (self.dns_servers) |old_servers| {
            for (old_servers) |server| self.allocator.free(server);
            self.allocator.free(old_servers);
        }
        var new_servers = try self.allocator.alloc([]const u8, servers.len);
        for (servers, 0..) |server, i| {
            new_servers[i] = try self.allocator.dupe(u8, server);
        }
        self.dns_servers = new_servers;
    }

    pub fn setDNSSearchDomains(self: *Self, domains: []const []const u8) !void {
        if (self.dns_search_domains) |old_domains| {
            for (old_domains) |domain| self.allocator.free(domain);
            self.allocator.free(old_domains);
        }
        var new_domains = try self.allocator.alloc([]const u8, domains.len);
        for (domains, 0..) |domain, i| {
            new_domains[i] = try self.allocator.dupe(u8, domain);
        }
        self.dns_search_domains = new_domains;
    }

    pub fn setMemoryLimit(self: *Self, limit: u64) !void {
        self.memory_limit = limit;
    }

    pub fn setMemoryReservation(self: *Self, reservation: u64) !void {
        self.memory_reservation = reservation;
    }

    pub fn setMemorySwap(self: *Self, swap: u64) !void {
        self.memory_swap = swap;
    }

    pub fn setCpuShares(self: *Self, shares: u64) !void {
        self.cpu_shares = shares;
    }

    pub fn setCpuQuota(self: *Self, quota: i64) !void {
        self.cpu_quota = @intCast(quota);
    }

    pub fn setCpuPeriod(self: *Self, period: u64) !void {
        self.cpu_period = period;
    }

    pub fn setCpus(self: *Self, cpus: []const u8) !void {
        if (self.cpus) |old_cpus| self.allocator.free(old_cpus);
        self.cpus = try self.allocator.dupe(u8, cpus);
    }

    pub fn setMems(self: *Self, mems: []const u8) !void {
        if (self.mems) |old_mems| self.allocator.free(old_mems);
        self.mems = try self.allocator.dupe(u8, mems);
    }

    pub fn setBlockIOWeight(self: *Self, weight: u64) !void {
        self.blockio_weight = weight;
    }

    pub fn setHugepageLimit(self: *Self, page_size: u64, limit: u64) !void {
        try self.hugepage_limits.append(.{
            .page_size = page_size,
            .limit = limit,
        });
    }

    pub fn addNamespace(self: *Self, ns_type: []const u8, ns_path: ?[]const u8) !void {
        try self.namespaces.append(.{
            .type = try self.allocator.dupe(u8, ns_type),
            .path = if (ns_path) |path| try self.allocator.dupe(u8, path) else null,
        });
    }

    pub const Device = struct {
        path: []const u8,
        type: []const u8,
        major: i64,
        minor: i64,
        fileMode: ?u32 = null,
        uid: ?u32 = null,
        gid: ?u32 = null,

        pub fn deinit(self: *const Device, allocator: Allocator) void {
            allocator.free(self.path);
            allocator.free(self.type);
        }
    };

    pub fn addDevice(self: *Self, device: Device) !void {
        const new_device = Device{
            .path = try self.allocator.dupe(u8, device.path),
            .type = try self.allocator.dupe(u8, device.type),
            .major = device.major,
            .minor = device.minor,
            .fileMode = device.fileMode,
            .uid = device.uid,
            .gid = device.gid,
        };
        try self.devices.append(new_device);
    }

    pub const Mount = struct {
        source: []const u8,
        target: []const u8,
        type: []const u8,
        options: ?[][]const u8,

        pub fn deinit(self: *const Mount, allocator: Allocator) void {
            allocator.free(self.source);
            allocator.free(self.target);
            allocator.free(self.type);
            if (self.options) |opts| {
                for (opts) |opt| {
                    allocator.free(opt);
                }
                allocator.free(opts);
            }
        }
    };

    pub fn addMount(self: *Self, mount: Mount) !void {
        const new_mount = Mount{
            .source = try self.allocator.dupe(u8, mount.source),
            .target = try self.allocator.dupe(u8, mount.target),
            .type = try self.allocator.dupe(u8, mount.type),
            .options = if (mount.options) |opts| blk: {
                var new_opts = try self.allocator.alloc([]const u8, opts.len);
                for (opts, 0..) |opt, i| {
                    new_opts[i] = try self.allocator.dupe(u8, opt);
                }
                break :blk new_opts;
            } else null,
        };
        try self.mounts.append(new_mount);
    }
};

pub const NetworkInterface = struct {
    name: []const u8,
    type: []const u8,
    bridge: ?[]const u8,
    vlan: ?u16,
    mtu: ?u32,
    rate: ?u64,
    ip: ?struct {
        address: []const u8,
        netmask: []const u8,
        gateway: ?[]const u8,
    },
};

pub const HugepageLimit = struct {
    page_size: u64,
    limit: u64,
};

pub const Namespace = struct {
    type: []const u8,
    path: ?[]const u8,
};

pub const LXCManager = struct {
    allocator: Allocator,
    logger: *logger_mod.Logger,

    const Self = @This();

    pub fn init(allocator: Allocator, log: *logger_mod.Logger) !*Self {
        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .logger = log,
        };
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.destroy(self);
    }

    pub fn containerExists(self: *Self, container_id: []const u8) !bool {
        try self.logger.info("Checking if container {s} exists", .{container_id});
        // TODO: Implement container check
        return false;
    }

    pub fn createContainer(self: *Self, container_id: []const u8) !void {
        try self.logger.info("Creating container {s}", .{container_id});
        // TODO: Implement container creation
    }

    pub fn startContainer(self: *Self, container_id: []const u8) !void {
        try self.logger.info("Starting container {s}", .{container_id});
        // TODO: Implement container start
    }

    pub fn stopContainer(self: *Self, container_id: []const u8) !void {
        try self.logger.info("Stopping container {s}", .{container_id});
        // TODO: Implement container stop
    }

    pub fn deleteContainer(self: *Self, container_id: []const u8) !void {
        try self.logger.info("Deleting container {s}", .{container_id});
        // TODO: Implement container deletion
    }

    pub fn createConfig(self: *Self) !*Config {
        try self.logger.info("Creating LXC config", .{});
        return try Config.init(self.allocator);
    }

    pub fn saveConfig(self: *Self, container_id: []const u8, config: *Config) !void {
        try self.logger.info("Saving config for container {s}", .{container_id});
        _ = config; // TODO: Implement config saving
    }
};
