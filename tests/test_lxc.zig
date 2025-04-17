const std = @import("std");
const proxmox = @import("proxmox");
const logger = @import("logger");
const types = @import("types");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var log = try logger.Logger.init(allocator, .info, std.io.getStdOut().writer());
    defer log.deinit();

    const hosts = [_][]const u8{"mgr.cp.if.ua"};
    const token = "root@pam!capi=be7823bc-d949-460e-a9ce-28d0844648ed";
    const node = "mgr";

    var client = try proxmox.Client.init(
        allocator,
        &hosts,
        token,
        &log,
        8006,
        node,
        3600,
    );
    defer client.deinit();

    try log.info("Listing LXC containers...", .{});
    const containers = try client.listLXCs();
    defer {
        for (containers) |container| {
            allocator.free(container.name);
        }
        allocator.free(containers);
    }

    try log.info("Found {d} containers:", .{containers.len});
    for (containers) |container| {
        try log.info("Container {d}: {s} (status: {s})", .{
            container.vmid,
            container.name,
            @tagName(container.status),
        });
    }
} 