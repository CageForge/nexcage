const std = @import("std");
const logger = std.log.scoped(.oci_stop);
const proxmox = @import("proxmox");
const errors = @import("error");

pub fn stop(container_id: []const u8, logger_ctx: anytype, _proxmox_client: *proxmox.ProxmoxClient) !void {
    _ = _proxmox_client;
    try logger_ctx.info("Stop command not implemented yet for container: {s}", .{container_id});
    try logger_ctx.info("This functionality will be implemented in future versions", .{});
}
