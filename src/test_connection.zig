const std = @import("std");
const logger_mod = @import("logger");
const proxmox = @import("proxmox");
const Error = @import("error").Error;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var logger = try logger_mod.Logger.init(allocator, .debug, std.io.getStdOut().writer());
    defer logger.deinit();

    const hosts = [_][]const u8{"mgr.cp.if.ua"};
    const token = "root@pam!capi=be7823bc-d949-460e-a9ce-28d0844648ed";
    const node = "mgr"; // Default node name in Proxmox

    var client = try proxmox.Client.init(
        allocator,
        &hosts,
        token,
        &logger,
        8006, // Default Proxmox port
        node,
        300, // Cache duration in seconds
    );
    defer client.deinit();

    try logger.info("Testing connection to Proxmox API...", .{});

    // Try to get version information
    const response = try client.makeRequest(.GET, "/api2/json/version", null);
    defer allocator.free(response);

    try logger.info("Proxmox API version: {s}", .{response});
}
