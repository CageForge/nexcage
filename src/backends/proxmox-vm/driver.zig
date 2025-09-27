const std = @import("std");
const core = @import("core");
const types = @import("types.zig");
const proxmox_api = @import("integrations/proxmox-api");

/// Proxmox VM backend driver
/// Proxmox VM backend driver
pub const ProxmoxVmDriver = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    config: types.ProxmoxVmBackendConfig,
    api_client: *proxmox_api.client.ProxmoxApiClient,
    operations: proxmox_api.operations.ProxmoxApiOperations,
    logger: ?*core.LogContext = null,

    pub fn init(allocator: std.mem.Allocator, config: types.ProxmoxVmBackendConfig) !*Self {
        const api_config = proxmox_api.types.ProxmoxApiConfig{
            .allocator = allocator,
            .host = try allocator.dupe(u8, config.proxmox_host),
            .port = config.proxmox_port,
            .token = try allocator.dupe(u8, config.proxmox_token),
            .node = try allocator.dupe(u8, config.proxmox_node),
            .verify_ssl = config.verify_ssl,
            .timeout = config.timeout,
        };

        const api_client = try proxmox_api.client.ProxmoxApiClient.init(allocator, api_config);
        const operations = proxmox_api.operations.ProxmoxApiOperations.init(allocator, api_client);

        const driver = try allocator.alloc(Self, 1);
        driver[0] = Self{
            .allocator = allocator,
            .config = config,
            .api_client = api_client,
            .operations = operations,
        };

        return &driver[0];
    }

    pub fn deinit(self: *Self) void {
        self.api_client.deinit();
        self.allocator.free(self);
    }

    /// Set logger
    pub fn setLogger(self: *Self, logger: *core.LogContext) void {
        self.logger = logger;
        self.api_client.setLogger(logger);
    }

    /// Create VM
    pub fn createVm(self: *Self, config: types.ProxmoxVmConfig) !void {
        if (self.logger) |log| {
            try log.info("Creating VM {d} with name '{s}'", .{ config.vmid, config.name });
        }

        const api_config = proxmox_api.types.ProxmoxVmConfig{
            .allocator = self.allocator,
            .vmid = config.vmid,
            .name = try self.allocator.dupe(u8, config.name),
            .memory = config.memory,
            .cores = config.cores,
            .sockets = config.sockets,
            .cpu = try self.allocator.dupe(u8, config.cpu),
            .scsi0 = if (config.scsi0) |scsi| try self.allocator.dupe(u8, scsi) else null,
            .ide0 = if (config.ide0) |ide| try self.allocator.dupe(u8, ide) else null,
            .net0 = if (config.net0) |net| try self.allocator.dupe(u8, net) else null,
            .bootdisk = if (config.bootdisk) |boot| try self.allocator.dupe(u8, boot) else null,
            .onboot = config.onboot,
            .start = config.start,
        };
        defer api_config.deinit();

        try self.operations.createVm(api_config);

        if (self.logger) |log| {
            try log.info("Successfully created VM {d}", .{config.vmid});
        }
    }

    /// Start VM
    pub fn startVm(self: *Self, vmid: u32) !void {
        if (self.logger) |log| {
            try log.info("Starting VM {d}", .{vmid});
        }

        try self.operations.start(vmid, false);

        if (self.logger) |log| {
            try log.info("Successfully started VM {d}", .{vmid});
        }
    }

    /// Stop VM
    pub fn stopVm(self: *Self, vmid: u32) !void {
        if (self.logger) |log| {
            try log.info("Stopping VM {d}", .{vmid});
        }

        try self.operations.stop(vmid, false);

        if (self.logger) |log| {
            try log.info("Successfully stopped VM {d}", .{vmid});
        }
    }

    /// Delete VM
    pub fn deleteVm(self: *Self, vmid: u32) !void {
        if (self.logger) |log| {
            try log.info("Deleting VM {d}", .{vmid});
        }

        try self.operations.delete(vmid, false);

        if (self.logger) |log| {
            try log.info("Successfully deleted VM {d}", .{vmid});
        }
    }

    /// List VMs
    pub fn listVms(self: *Self) ![]types.VmInfo {
        if (self.logger) |log| {
            try log.info("Listing VMs");
        }

        const api_vms = try self.operations.listVms();
        defer {
            for (api_vms) |vm| {
                vm.deinit();
            }
            self.allocator.free(api_vms);
        }

        var result = try self.allocator.alloc(types.VmInfo, api_vms.len);

        for (api_vms, 0..) |api_vm, i| {
            result[i] = types.VmInfo{
                .allocator = self.allocator,
                .vmid = api_vm.vmid,
                .name = try self.allocator.dupe(u8, api_vm.name),
                .status = if (api_vm.start) .running else .stopped,
                .memory = api_vm.memory,
                .cores = api_vm.cores,
                .sockets = api_vm.sockets,
                .cpu = try self.allocator.dupe(u8, api_vm.cpu),
                .ip_address = null, // TODO: Get IP from VM config
                .uptime = null, // TODO: Get uptime from VM status
            };
        }

        if (self.logger) |log| {
            try log.info("Found {d} VMs", .{result.len});
        }

        return result;
    }

    /// Get VM information
    pub fn getVmInfo(self: *Self, vmid: u32) !?types.VmInfo {
        const vms = try self.listVms();
        defer {
            for (vms) |vm| {
                vm.deinit();
            }
            self.allocator.free(vms);
        }

        for (vms) |vm| {
            if (vm.vmid == vmid) {
                return vm;
            }
        }

        return null;
    }

    /// Check if VM exists
    pub fn vmExists(self: *Self, vmid: u32) !bool {
        const info = try self.getVmInfo(vmid);
        if (info) |vm_info| {
            vm_info.deinit();
            return true;
        }
        return false;
    }
};
