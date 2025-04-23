const std = @import("std");
const Allocator = std.mem.Allocator;
const logger = std.log.scoped(.network);
const lxc = @import("lxc_network.zig");

pub const NetworkManager = struct {
    allocator: Allocator,
    networks: std.StringHashMap(*lxc.LxcNetwork),

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return .{
            .allocator = allocator,
            .networks = std.StringHashMap(*lxc.LxcNetwork).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        var it = self.networks.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.*.deinit();
        }
        self.networks.deinit();
    }

    pub fn createNetwork(self: *Self, pod_name: []const u8) !*lxc.LxcNetwork {
        logger.info("Creating network for pod: {s}", .{pod_name});

        // Перевіряємо чи мережа вже існує
        if (self.networks.get(pod_name)) |network| {
            return network;
        }

        // Створюємо нову мережу
        const network = try lxc.LxcNetwork.init(self.allocator, pod_name);
        errdefer network.deinit();

        // Зберігаємо мережу
        try self.networks.put(pod_name, network);

        logger.info("Network created successfully for pod: {s}", .{pod_name});
        return network;
    }

    pub fn deleteNetwork(self: *Self, pod_name: []const u8) void {
        logger.info("Deleting network for pod: {s}", .{pod_name});

        if (self.networks.fetchRemove(pod_name)) |entry| {
            entry.value.deinit();
            logger.info("Network deleted successfully for pod: {s}", .{pod_name});
        }
    }

    pub fn getNetwork(self: *Self, pod_name: []const u8) ?*lxc.LxcNetwork {
        return self.networks.get(pod_name);
    }
}; 