const std = @import("std");
const Allocator = std.mem.Allocator;
const oci = @import("../oci/spec.zig");
const logger = std.log.scoped(.oci_adapter);

pub const AdapterError = error{
    ConversionFailed,
    InvalidSpec,
    UnsupportedFeature,
};

pub const ProxmoxContainerConfig = struct {
    ostemplate: []const u8,
    hostname: ?[]const u8 = null,
    memory: ?u64 = null,
    swap: ?u64 = null,
    cores: ?u32 = null,
    cpulimit: ?u32 = null,
    rootfs: struct {
        volume: []const u8,
        size: []const u8,
    },
    net0: ?struct {
        name: []const u8,
        bridge: []const u8,
        ip: ?[]const u8 = null,
        gw: ?[]const u8 = null,
    } = null,
    unprivileged: bool = true,
    features: struct {
        nesting: bool = false,
    } = .{ .nesting = false },
};

pub fn convertOciToProxmox(allocator: Allocator, spec: *const oci.Spec) !ProxmoxContainerConfig {
    logger.info("Converting OCI spec to Proxmox config", .{});

    // Перевіряємо необхідні поля
    if (spec.root == null or spec.root.?.path == null) {
        return AdapterError.InvalidSpec;
    }

    // Базова конфігурація
    var config = ProxmoxContainerConfig{
        .ostemplate = "local:vztmpl/ubuntu-22.04-standard_22.04-1_amd64.tar.zst",
        .rootfs = .{
            .volume = "local-lvm",
            .size = "8G",
        },
    };

    // Hostname
    if (spec.hostname) |hostname| {
        config.hostname = try allocator.dupe(u8, hostname);
    }

    // Ресурси
    if (spec.linux.resources) |resources| {
        // Memory
        if (resources.memory) |memory| {
            if (memory.limit) |limit| {
                config.memory = @intCast(limit);
            }
            if (memory.swap) |swap| {
                config.swap = @intCast(swap);
            }
        }

        // CPU
        if (resources.cpu) |cpu| {
            if (cpu.quota) |quota| {
                config.cpulimit = @intCast(@divFloor(quota, 100000));
            }
            if (cpu.cpus) |cpus| {
                const cores = try parseCpuSet(allocator, cpus);
                config.cores = @intCast(cores);
            }
        }
    }

    // Мережа
    if (spec.linux.namespaces) |namespaces| {
        for (namespaces) |ns| {
            if (std.mem.eql(u8, ns.type, "network")) {
                config.net0 = .{
                    .name = "eth0",
                    .bridge = "vmbr0",
                };
                break;
            }
        }
    }

    logger.info("OCI spec converted successfully", .{});
    return config;
}

fn parseCpuSet(allocator: Allocator, cpuset: []const u8) !u32 {
    _ = allocator;
    var count: u32 = 0;
    var it = std.mem.split(u8, cpuset, ",");
    while (it.next()) |range| {
        if (std.mem.indexOf(u8, range, "-")) |dash_idx| {
            const start = try std.fmt.parseInt(u32, range[0..dash_idx], 10);
            const end = try std.fmt.parseInt(u32, range[dash_idx + 1 ..], 10);
            count += end - start + 1;
        } else {
            count += 1;
        }
    }
    return count;
}

pub fn validateOciSpec(spec: *const oci.Spec) !void {
    logger.info("Validating OCI spec", .{});

    // Перевіряємо обов'язкові поля
    if (spec.root.path.len == 0) {
        logger.err("Root path is required", .{});
        return AdapterError.InvalidSpec;
    }

    // Перевіряємо підтримувані функції
    if (spec.linux.seccomp) |seccomp| {
        // Перевіряємо профіль seccomp
        if (seccomp.defaultAction.len == 0) {
            logger.err("Seccomp default action is required", .{});
            return AdapterError.InvalidSpec;
        }
        
        // Перевіряємо syscalls
        if (seccomp.syscalls) |syscalls| {
            for (syscalls) |syscall| {
                if (syscall.names.len == 0) {
                    logger.err("Seccomp syscall names are required", .{});
                    return AdapterError.InvalidSpec;
                }
                if (syscall.action.len == 0) {
                    logger.err("Seccomp syscall action is required", .{});
                    return AdapterError.InvalidSpec;
                }
            }
        }
    }

    if (spec.linux.resources) |resources| {
        if (resources.devices) |devices| {
            for (devices) |device| {
                if (device.allow and !isDeviceSupported(device)) {
                    logger.warn("Device {s} may not be fully supported in Proxmox LXC", .{device.path});
                }
            }
        }
    }

    logger.info("OCI spec validation completed", .{});
}

fn isDeviceSupported(device: oci.LinuxDevice) bool {
    // Перевіряємо базові пристрої, які підтримуються в LXC
    const supported_devices = [_][]const u8{
        "/dev/null",
        "/dev/zero",
        "/dev/full",
        "/dev/random",
        "/dev/urandom",
        "/dev/tty",
        "/dev/console",
        "/dev/ptmx",
    };

    for (supported_devices) |supported| {
        if (std.mem.eql(u8, device.path, supported)) {
            return true;
        }
    }
    return false;
} 