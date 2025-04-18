const std = @import("std");

/// CPU ресурси
pub const CpuResources = struct {
    shares: ?u64,
    quota: ?i64,
    period: ?u64,
    realtime_runtime: ?i64,
    realtime_period: ?u64,
    cpus: ?[]const u8,
    mems: ?[]const u8,

    pub fn deinit(self: *CpuResources, allocator: std.mem.Allocator) void {
        if (self.cpus) |cpus| {
            allocator.free(cpus);
        }
        if (self.mems) |mems| {
            allocator.free(mems);
        }
    }
};

/// Memory ресурси
pub const MemoryResources = struct {
    limit: ?i64,
    reservation: ?i64,
    swap: ?i64,
    kernel: ?i64,
    kernel_tcp: ?i64,
    swappiness: ?u64,
    disable_oom_killer: ?bool,

    pub fn deinit(self: *MemoryResources, allocator: std.mem.Allocator) void {
        _ = self;
        _ = allocator;
    }
};

/// Pids ресурси
pub const PidsResources = struct {
    limit: i64,

    pub fn deinit(self: *PidsResources, allocator: std.mem.Allocator) void {
        _ = self;
        _ = allocator;
    }
};

/// Block I/O ресурси
pub const BlockIoResources = struct {
    weight: ?u16,
    leaf_weight: ?u16,
    weight_device: ?[]WeightDevice,
    throttle_read_bps_device: ?[]ThrottleDevice,
    throttle_write_bps_device: ?[]ThrottleDevice,
    throttle_read_iops_device: ?[]ThrottleDevice,
    throttle_write_iops_device: ?[]ThrottleDevice,

    pub fn deinit(self: *BlockIoResources, allocator: std.mem.Allocator) void {
        if (self.weight_device) |devices| {
            for (devices) |device| {
                device.deinit(allocator);
            }
            allocator.free(devices);
        }
        if (self.throttle_read_bps_device) |devices| {
            for (devices) |device| {
                device.deinit(allocator);
            }
            allocator.free(devices);
        }
        if (self.throttle_write_bps_device) |devices| {
            for (devices) |device| {
                device.deinit(allocator);
            }
            allocator.free(devices);
        }
        if (self.throttle_read_iops_device) |devices| {
            for (devices) |device| {
                device.deinit(allocator);
            }
            allocator.free(devices);
        }
        if (self.throttle_write_iops_device) |devices| {
            for (devices) |device| {
                device.deinit(allocator);
            }
            allocator.free(devices);
        }
    }
};

/// Weight пристрій
pub const WeightDevice = struct {
    major: i64,
    minor: i64,
    weight: ?u16,
    leaf_weight: ?u16,

    pub fn deinit(self: *WeightDevice, allocator: std.mem.Allocator) void {
        _ = self;
        _ = allocator;
    }
};

/// Throttle пристрій
pub const ThrottleDevice = struct {
    major: i64,
    minor: i64,
    rate: u64,

    pub fn deinit(self: *ThrottleDevice, allocator: std.mem.Allocator) void {
        _ = self;
        _ = allocator;
    }
};

/// HugePage ліміт
pub const HugepageLimit = struct {
    page_size: []const u8,
    limit: u64,

    pub fn deinit(self: *HugepageLimit, allocator: std.mem.Allocator) void {
        allocator.free(self.page_size);
    }
};

/// Network ресурси
pub const NetworkResources = struct {
    class_id: ?u32,
    priorities: ?[]InterfacePriority,

    pub fn deinit(self: *NetworkResources, allocator: std.mem.Allocator) void {
        if (self.priorities) |priorities| {
            for (priorities) |priority| {
                priority.deinit(allocator);
            }
            allocator.free(priorities);
        }
    }
};

/// Пріоритет інтерфейсу
pub const InterfacePriority = struct {
    name: []const u8,
    priority: u32,

    pub fn deinit(self: *InterfacePriority, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
    }
}; 