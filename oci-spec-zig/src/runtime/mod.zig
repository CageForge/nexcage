const std = @import("std");

pub const version = "1.3.0";

pub const MemoryPolicyMode = enum {
    mpol_default,
    mpol_bind,
    mpol_interleave,
    mpol_weighted_interleave,
    mpol_preferred,
    mpol_preferred_many,
    mpol_local,
};

pub const MemoryPolicyFlag = enum {
    numa_balancing,
    relative_nodes,
    static_nodes,
};

pub const MemoryPolicy = struct {
    allocator: std.mem.Allocator,
    mode: ?MemoryPolicyMode = null,
    nodes: ?[]const u8 = null,
    flags: ?[]MemoryPolicyFlag = null,

    pub fn deinit(self: *MemoryPolicy) void {
        if (self.nodes) |nodes| self.allocator.free(@constCast(nodes));
        if (self.flags) |flags| self.allocator.free(flags);
    }
};

pub const IntelRdt = struct {
    allocator: std.mem.Allocator,
    clos_id: ?[]const u8 = null,
    schemata: ?[]const []const u8 = null,
    l3_cache_schema: ?[]const u8 = null,
    mem_bw_schema: ?[]const u8 = null,
    enable_monitoring: ?bool = null,

    pub fn deinit(self: *IntelRdt) void {
        if (self.clos_id) |id| self.allocator.free(@constCast(id));
        if (self.l3_cache_schema) |schema| self.allocator.free(@constCast(schema));
        if (self.mem_bw_schema) |schema| self.allocator.free(@constCast(schema));
        if (self.schemata) |schemata| {
            for (schemata) |entry| self.allocator.free(@constCast(entry));
            self.allocator.free(schemata);
        }
    }
};

pub const NetDevice = struct {
    allocator: std.mem.Allocator,
    alias: []const u8,
    name: ?[]const u8 = null,

    pub fn deinit(self: *NetDevice) void {
        self.allocator.free(@constCast(self.alias));
        if (self.name) |value| self.allocator.free(@constCast(value));
    }
};

pub const Linux = struct {
    memory_policy: ?MemoryPolicy = null,
    intel_rdt: ?IntelRdt = null,
    net_devices: ?[]NetDevice = null,
};

test "runtime module loads" {
    var allocator = std.testing.allocator;
    var policy = MemoryPolicy{ .allocator = allocator };
    defer policy.deinit();
    policy.mode = .mpol_default;
    try std.testing.expect(policy.mode.? == .mpol_default);
    var intel = IntelRdt{ .allocator = allocator };
    defer intel.deinit();
    intel.enable_monitoring = true;
    try std.testing.expect(intel.enable_monitoring.?);
    const alias = try allocator.dupe(u8, "eth0");
    var device = NetDevice{ .allocator = allocator, .alias = alias };
    defer device.deinit();
    try std.testing.expect(std.mem.eql(u8, device.alias, "eth0"));
}

