const std = @import("std");
const proxmox = @import("proxmox");

pub const ContainerSpec = struct {
    name: []const u8,
    image: []const u8,
    command: []const []const u8,
    args: []const []const u8,
    env: []const EnvVar,
};

pub const EnvVar = struct {
    name: []const u8,
    value: []const u8,
};

pub const ContainerStatus = enum {
    created,
    running,
    stopped,
    unknown,
};

pub fn specToLXCConfig(spec: ContainerSpec) !proxmox.LXCConfig {
    return proxmox.LXCConfig{
        .hostname = spec.name,
        .ostype = "ubuntu", // Default to Ubuntu for now
        .memory = 512, // Default memory
        .swap = 256, // Default swap
        .cores = 1, // Default cores
        .rootfs = "local-lvm:8", // Default rootfs
        .net0 = proxmox.NetworkConfig{
            .name = "eth0",
            .bridge = "vmbr0",
            .ip = "dhcp", // Default to DHCP
        },
    };
}

pub fn lxcStatusToContainerStatus(status: proxmox.LXCStatus) ContainerStatus {
    return switch (status) {
        .running => .running,
        .stopped => .stopped,
        .paused => .stopped,
        .unknown => .unknown,
    };
}
