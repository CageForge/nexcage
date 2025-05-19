const std = @import("std");
const logger = std.log.scoped(.oci_delete);
const proxmox = @import("proxmox");
const errors = @import("error");

pub fn delete(container_id: []const u8, proxmox_client: *proxmox.ProxmoxClient) !void {
    try proxmox_client.logger.info("Deleting container {s}", .{container_id});

    const vmid = try proxmox_client.getProxmoxVMID(container_id);
    try proxmox_client.deleteContainer(.lxc, vmid);

    try proxmox_client.logger.info("Container {s} deleted successfully", .{container_id});
}
