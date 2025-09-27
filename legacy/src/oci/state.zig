const std = @import("std");
const Allocator = std.mem.Allocator;
const logger = @import("logger");
const proxmox = @import("proxmox");
const errors = @import("error");
const types = @import("types");

fn lxcStatusToContainerStatus(lxc_status: types.LXCStatus) types.ContainerStatus {
    return switch (lxc_status) {
        .running => .running,
        .stopped => .stopped,
        // LXC doesn't have a paused state, so we consider all other states as unknown
        else => .unknown,
    };
}

fn containerStatusToString(status: types.ContainerStatus) []const u8 {
    return switch (status) {
        .running => "running",
        .stopped => "stopped",
        .paused => "paused",
        .unknown => "unknown",
    };
}

pub fn getState(proxmox_client: *proxmox.ProxmoxClient, oci_container_id: []const u8) !types.ContainerConfig {
    try proxmox_client.logger.info("Getting state for container {s}", .{oci_container_id});

    const vmid = try proxmox_client.getProxmoxVMID(oci_container_id);
    const containers = try proxmox_client.listContainers();
    defer {
        for (containers) |*container| {
            container.deinit(proxmox_client.allocator);
        }
        proxmox_client.allocator.free(containers);
    }

    for (containers) |container| {
        if (container.vmid == vmid) {
            const bundle = try std.fmt.allocPrint(proxmox_client.allocator, "/var/lib/lxc/{s}", .{oci_container_id});
            errdefer proxmox_client.allocator.free(bundle);

            const status = try proxmox_client.allocator.dupe(u8, containerStatusToString(lxcStatusToContainerStatus(container.status)));
            errdefer proxmox_client.allocator.free(status);

            const version = try proxmox_client.allocator.dupe(u8, "1.0.2");
            errdefer proxmox_client.allocator.free(version);

            const id = try proxmox_client.allocator.dupe(u8, oci_container_id);
            errdefer proxmox_client.allocator.free(id);

            const container_state = types.ContainerStateInfo{
                .oci_version = version,
                .id = id,
                .status = status,
                .pid = 0, // TODO: Get actual PID from Proxmox API
                .bundle = bundle,
                .annotations = null,
                .allocator = proxmox_client.allocator,
            };

            return types.ContainerConfig{
                .id = try proxmox_client.allocator.dupe(u8, id),
                .name = try proxmox_client.allocator.dupe(u8, id),
                .state = container_state,
                .pid = 0,
                .bundle = try proxmox_client.allocator.dupe(u8, bundle),
                .annotations = null,
                .metadata = null,
                .image = null,
                .command = null,
                .args = null,
                .working_dir = null,
                .envs = null,
                .mounts = null,
                .devices = null,
                .labels = null,
                .linux = null,
                .log_path = null,
                .allocator = proxmox_client.allocator,
                .crun_name_patterns = &[_][]const u8{
                    "crun-*",
                    "oci-*",
                    "podman-*",
                },
                .default_container_type = .lxc,
            };
        }
    }

    try proxmox_client.logger.err("Container with VMID {d} not found", .{vmid});
    return error.ContainerNotFound;
}
