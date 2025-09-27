const std = @import("std");
const core = @import("core");
const types = @import("types.zig");
const client = @import("client.zig");

/// Proxmox API operations
/// Proxmox API operations manager
pub const ProxmoxApiOperations = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    api_client: *client.ProxmoxApiClient,

    pub fn init(allocator: std.mem.Allocator, api_client: *client.ProxmoxApiClient) Self {
        return Self{
            .allocator = allocator,
            .api_client = api_client,
        };
    }

    /// List available templates
    pub fn listTemplates(self: *Self) ![]types.ProxmoxTemplate {
        const response = try self.api_client.makeRequest(.GET, "/nodes/{s}/storage/local/content?content=vztmpl");
        defer response.deinit();

        if (!response.success or response.data == null) {
            return types.ProxmoxApiError.OperationFailed;
        }

        const data = response.data.?;
        if (data.object.get("data")) |templates_array| {
            if (templates_array.array) |templates| {
                var result = try self.allocator.alloc(types.ProxmoxTemplate, templates.items.len);

                for (templates.items, 0..) |template_value, i| {
                    if (template_value.object) |template_obj| {
                        result[i] = types.ProxmoxTemplate{
                            .allocator = self.allocator,
                            .volid = try self.allocator.dupe(u8, template_obj.get("volid").?.string.?),
                            .format = try self.allocator.dupe(u8, template_obj.get("format").?.string orelse "unknown"),
                            .size = template_obj.get("size").?.integer orelse 0,
                            .ctime = template_obj.get("ctime").?.integer orelse 0,
                            .description = if (template_obj.get("description")) |desc|
                                try self.allocator.dupe(u8, desc.string.?)
                            else
                                null,
                        };
                    }
                }

                return result;
            }
        }

        return try self.allocator.alloc(types.ProxmoxTemplate, 0);
    }

    /// Create LXC container
    pub fn createLxcContainer(self: *Self, config: types.ProxmoxLxcConfig) !void {
        var params = std.ArrayList(u8).init(self.allocator);
        defer params.deinit();

        try params.appendSlice("vmid=");
        try params.writer().print("{d}", .{config.vmid});
        try params.appendSlice("&hostname=");
        try params.appendSlice(config.hostname);
        try params.appendSlice("&memory=");
        try params.writer().print("{d}", .{config.memory});
        try params.appendSlice("&cores=");
        try params.writer().print("{d}", .{config.cores});
        try params.appendSlice("&rootfs=");
        try params.appendSlice(config.rootfs);
        try params.appendSlice("&unprivileged=");
        try params.appendSlice(if (config.unprivileged) "1" else "0");
        try params.appendSlice("&onboot=");
        try params.appendSlice(if (config.onboot) "1" else "0");
        try params.appendSlice("&start=");
        try params.appendSlice(if (config.start) "1" else "0");

        if (config.net0) |net| {
            try params.appendSlice("&net0=");
            try params.appendSlice(net);
        }

        if (config.ostemplate) |ost| {
            try params.appendSlice("&ostemplate=");
            try params.appendSlice(ost);
        }

        if (config.password) |pass| {
            try params.appendSlice("&password=");
            try params.appendSlice(pass);
        }

        if (config.ssh_public_keys) |keys| {
            try params.appendSlice("&ssh-public-keys=");
            try params.appendSlice(keys);
        }

        const path = try std.fmt.allocPrint(self.allocator, "/nodes/{s}/lxc", .{self.api_client.node});
        defer self.allocator.free(path);

        const response = try self.api_client.makeRequestWithContentType(.POST, path, params.items, "application/x-www-form-urlencoded");
        defer response.deinit();

        if (!response.success) {
            return types.ProxmoxApiError.OperationFailed;
        }
    }

    /// Create VM
    pub fn createVm(self: *Self, config: types.ProxmoxVmConfig) !void {
        var params = std.ArrayList(u8).init(self.allocator);
        defer params.deinit();

        try params.appendSlice("vmid=");
        try params.writer().print("{d}", .{config.vmid});
        try params.appendSlice("&name=");
        try params.appendSlice(config.name);
        try params.appendSlice("&memory=");
        try params.writer().print("{d}", .{config.memory});
        try params.appendSlice("&cores=");
        try params.writer().print("{d}", .{config.cores});
        try params.appendSlice("&sockets=");
        try params.writer().print("{d}", .{config.sockets});
        try params.appendSlice("&cpu=");
        try params.appendSlice(config.cpu);
        try params.appendSlice("&onboot=");
        try params.appendSlice(if (config.onboot) "1" else "0");
        try params.appendSlice("&start=");
        try params.appendSlice(if (config.start) "1" else "0");

        if (config.scsi0) |scsi| {
            try params.appendSlice("&scsi0=");
            try params.appendSlice(scsi);
        }

        if (config.ide0) |ide| {
            try params.appendSlice("&ide0=");
            try params.appendSlice(ide);
        }

        if (config.net0) |net| {
            try params.appendSlice("&net0=");
            try params.appendSlice(net);
        }

        if (config.bootdisk) |boot| {
            try params.appendSlice("&bootdisk=");
            try params.appendSlice(boot);
        }

        const path = try std.fmt.allocPrint(self.allocator, "/nodes/{s}/qemu", .{self.api_client.node});
        defer self.allocator.free(path);

        const response = try self.api_client.makeRequestWithContentType(.POST, path, params.items, "application/x-www-form-urlencoded");
        defer response.deinit();

        if (!response.success) {
            return types.ProxmoxApiError.OperationFailed;
        }
    }

    /// Start container/VM
    pub fn start(self: *Self, vmid: u32, is_lxc: bool) !void {
        const path = if (is_lxc)
            try std.fmt.allocPrint(self.allocator, "/nodes/{s}/lxc/{d}/status/start", .{ self.api_client.node, vmid })
        else
            try std.fmt.allocPrint(self.allocator, "/nodes/{s}/qemu/{d}/status/start", .{ self.api_client.node, vmid });
        defer self.allocator.free(path);

        const response = try self.api_client.makeRequest(.POST, path);
        defer response.deinit();

        if (!response.success) {
            return types.ProxmoxApiError.OperationFailed;
        }
    }

    /// Stop container/VM
    pub fn stop(self: *Self, vmid: u32, is_lxc: bool) !void {
        const path = if (is_lxc)
            try std.fmt.allocPrint(self.allocator, "/nodes/{s}/lxc/{d}/status/stop", .{ self.api_client.node, vmid })
        else
            try std.fmt.allocPrint(self.allocator, "/nodes/{s}/qemu/{d}/status/stop", .{ self.api_client.node, vmid });
        defer self.allocator.free(path);

        const response = try self.api_client.makeRequest(.POST, path);
        defer response.deinit();

        if (!response.success) {
            return types.ProxmoxApiError.OperationFailed;
        }
    }

    /// Delete container/VM
    pub fn delete(self: *Self, vmid: u32, is_lxc: bool) !void {
        const path = if (is_lxc)
            try std.fmt.allocPrint(self.allocator, "/nodes/{s}/lxc/{d}", .{ self.api_client.node, vmid })
        else
            try std.fmt.allocPrint(self.allocator, "/nodes/{s}/qemu/{d}", .{ self.api_client.node, vmid });
        defer self.allocator.free(path);

        const response = try self.api_client.makeRequest(.DELETE, path);
        defer response.deinit();

        if (!response.success) {
            return types.ProxmoxApiError.OperationFailed;
        }
    }

    /// List containers
    pub fn listContainers(self: *Self) ![]types.ProxmoxLxcConfig {
        const path = try std.fmt.allocPrint(self.allocator, "/nodes/{s}/lxc", .{self.api_client.node});
        defer self.allocator.free(path);

        const response = try self.api_client.makeRequest(.GET, path);
        defer response.deinit();

        if (!response.success or response.data == null) {
            return types.ProxmoxApiError.OperationFailed;
        }

        const data = response.data.?;
        if (data.object.get("data")) |containers_array| {
            if (containers_array.array) |containers| {
                var result = try self.allocator.alloc(types.ProxmoxLxcConfig, containers.items.len);

                for (containers.items, 0..) |container_value, i| {
                    if (container_value.object) |container_obj| {
                        result[i] = types.ProxmoxLxcConfig{
                            .allocator = self.allocator,
                            .vmid = @intCast(container_obj.get("vmid").?.integer.?),
                            .hostname = try self.allocator.dupe(u8, container_obj.get("hostname").?.string.?),
                            .memory = container_obj.get("maxmem").?.integer orelse 512,
                            .cores = @intCast(container_obj.get("cpus").?.integer orelse 1),
                            .rootfs = try self.allocator.dupe(u8, container_obj.get("rootfs").?.string.?),
                            .unprivileged = container_obj.get("unprivileged").?.bool orelse true,
                            .onboot = container_obj.get("onboot").?.bool orelse false,
                            .start = container_obj.get("status").?.string.?.eql("running"),
                        };
                    }
                }

                return result;
            }
        }

        return try self.allocator.alloc(types.ProxmoxLxcConfig, 0);
    }

    /// List VMs
    pub fn listVms(self: *Self) ![]types.ProxmoxVmConfig {
        const path = try std.fmt.allocPrint(self.allocator, "/nodes/{s}/qemu", .{self.api_client.node});
        defer self.allocator.free(path);

        const response = try self.api_client.makeRequest(.GET, path);
        defer response.deinit();

        if (!response.success or response.data == null) {
            return types.ProxmoxApiError.OperationFailed;
        }

        const data = response.data.?;
        if (data.object.get("data")) |vms_array| {
            if (vms_array.array) |vms| {
                var result = try self.allocator.alloc(types.ProxmoxVmConfig, vms.items.len);

                for (vms.items, 0..) |vm_value, i| {
                    if (vm_value.object) |vm_obj| {
                        result[i] = types.ProxmoxVmConfig{
                            .allocator = self.allocator,
                            .vmid = @intCast(vm_obj.get("vmid").?.integer.?),
                            .name = try self.allocator.dupe(u8, vm_obj.get("name").?.string.?),
                            .memory = vm_obj.get("maxmem").?.integer orelse 1024,
                            .cores = @intCast(vm_obj.get("cpus").?.integer orelse 1),
                            .sockets = @intCast(vm_obj.get("sockets").?.integer orelse 1),
                            .cpu = try self.allocator.dupe(u8, vm_obj.get("cpu").?.string.?),
                            .onboot = vm_obj.get("onboot").?.bool orelse false,
                            .start = vm_obj.get("status").?.string.?.eql("running"),
                        };
                    }
                }

                return result;
            }
        }

        return try self.allocator.alloc(types.ProxmoxVmConfig, 0);
    }

    /// Get node information
    pub fn getNodeInfo(self: *Self) !types.ProxmoxNode {
        const path = try std.fmt.allocPrint(self.allocator, "/nodes/{s}/status", .{self.api_client.node});
        defer self.allocator.free(path);

        const response = try self.api_client.makeRequest(.GET, path);
        defer response.deinit();

        if (!response.success or response.data == null) {
            return types.ProxmoxApiError.OperationFailed;
        }

        const data = response.data.?;
        if (data.object.get("data")) |node_data| {
            if (node_data.object) |node_obj| {
                return types.ProxmoxNode{
                    .allocator = self.allocator,
                    .node = try self.allocator.dupe(u8, self.api_client.node),
                    .status = try self.allocator.dupe(u8, node_obj.get("status").?.string.?),
                    .cpu = node_obj.get("cpu").?.float.?,
                    .maxcpu = @intCast(node_obj.get("maxcpu").?.integer.?),
                    .mem = node_obj.get("mem").?.integer.?,
                    .maxmem = node_obj.get("maxmem").?.integer.?,
                    .uptime = node_obj.get("uptime").?.integer.?,
                    .level = if (node_obj.get("level")) |level|
                        try self.allocator.dupe(u8, level.string.?)
                    else
                        null,
                };
            }
        }

        return types.ProxmoxApiError.OperationFailed;
    }

    /// List storage
    pub fn listStorage(self: *Self) ![]types.ProxmoxStorage {
        const path = try std.fmt.allocPrint(self.allocator, "/nodes/{s}/storage", .{self.api_client.node});
        defer self.allocator.free(path);

        const response = try self.api_client.makeRequest(.GET, path);
        defer response.deinit();

        if (!response.success or response.data == null) {
            return types.ProxmoxApiError.OperationFailed;
        }

        const data = response.data.?;
        if (data.object.get("data")) |storage_array| {
            if (storage_array.array) |storage_list| {
                var result = try self.allocator.alloc(types.ProxmoxStorage, storage_list.items.len);

                for (storage_list.items, 0..) |storage_value, i| {
                    if (storage_value.object) |storage_obj| {
                        result[i] = types.ProxmoxStorage{
                            .allocator = self.allocator,
                            .storage = try self.allocator.dupe(u8, storage_obj.get("storage").?.string.?),
                            .type = try self.allocator.dupe(u8, storage_obj.get("type").?.string.?),
                            .content = try self.allocator.dupe(u8, storage_obj.get("content").?.string.?),
                            .shared = storage_obj.get("shared").?.bool orelse false,
                            .enabled = storage_obj.get("enabled").?.bool orelse true,
                            .used = if (storage_obj.get("used")) |used| @intCast(used.integer.?) else null,
                            .avail = if (storage_obj.get("avail")) |avail| @intCast(avail.integer.?) else null,
                            .total = if (storage_obj.get("total")) |total| @intCast(total.integer.?) else null,
                        };
                    }
                }

                return result;
            }
        }

        return try self.allocator.alloc(types.ProxmoxStorage, 0);
    }
};
