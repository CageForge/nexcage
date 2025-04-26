const std = @import("std");
const proxmox = @import("proxmox.zig");
const types = @import("../../../src/types.zig");

pub const MockClient = struct {
    allocator: std.mem.Allocator,
    mock_proxmox: *proxmox.MockProxmox,
    node: []const u8,
    logger: std.log.Logger,

    pub fn init(allocator: std.mem.Allocator) !*MockClient {
        const client = try allocator.create(MockClient);
        const mock_proxmox = try proxmox.MockProxmox.init(allocator);
        errdefer allocator.destroy(client);

        client.* = .{
            .allocator = allocator,
            .mock_proxmox = mock_proxmox,
            .node = try allocator.dupe(u8, "test-node"),
            .logger = std.log.scoped(.test),
        };

        return client;
    }

    pub fn deinit(self: *MockClient) void {
        self.mock_proxmox.deinit();
        self.allocator.free(self.node);
        self.allocator.destroy(self);
    }

    // Proxmox API mock implementations
    pub fn createLXC(self: *MockClient, config: types.LXCConfig) !types.Container {
        const container_config = types.ContainerConfig{
            .metadata = .{
                .name = config.hostname,
                .attempt = 1,
            },
            .image = .{
                .image = config.rootfs,
            },
            .linux = .{
                .resources = .{
                    .memory_limit_bytes = if (config.memory) |mem| mem * 1024 * 1024 else null,
                    .cpu_shares = if (config.cores) |cores| cores * 1024 else null,
                },
                .security_context = .{
                    .privileged = !config.unprivileged,
                },
            },
            .mounts = &[_]types.Mount{},
        };

        return try self.mock_proxmox.createContainer(container_config);
    }

    pub fn getLXCStatus(self: *MockClient, node: []const u8, vmid: u32) !types.ContainerStatus {
        _ = node;
        const container = try self.mock_proxmox.getContainer(vmid);
        return container.status;
    }

    pub fn getLXCConfig(self: *MockClient, node: []const u8, vmid: u32) !types.LXCConfig {
        _ = node;
        const container = try self.mock_proxmox.getContainer(vmid);
        return types.LXCConfig{
            .hostname = try self.allocator.dupe(u8, container.name),
            .rootfs = try self.allocator.dupe(u8, container.image_ref orelse ""),
            .memory = 512,
            .swap = 0,
            .cores = 1,
            .unprivileged = true,
            .net0 = .{
                .name = try self.allocator.dupe(u8, "eth0"),
                .bridge = try self.allocator.dupe(u8, "vmbr0"),
                .ip = try self.allocator.dupe(u8, "dhcp"),
                .type = try self.allocator.dupe(u8, "veth"),
            },
            .onboot = true,
        };
    }

    pub fn listLXC(self: *MockClient, node: []const u8) ![]types.Container {
        _ = node;
        return try self.mock_proxmox.listContainers();
    }

    pub fn startLXC(self: *MockClient, node: []const u8, vmid: u32) !void {
        _ = node;
        try self.mock_proxmox.startContainer(vmid);
    }

    pub fn stopLXC(self: *MockClient, node: []const u8, vmid: u32, timeout: i64) !void {
        _ = node;
        _ = timeout;
        try self.mock_proxmox.stopContainer(vmid);
    }

    pub fn deleteLXC(self: *MockClient, node: []const u8, vmid: u32) !void {
        _ = node;
        try self.mock_proxmox.removeContainer(vmid);
    }

    pub fn execLXC(self: *MockClient, node: []const u8, vmid: u32, options: types.ExecOptions) !struct {
        stdout: []const u8,
        stderr: []const u8,
        exit_code: i32,
        timed_out: bool,
    } {
        _ = node;
        return try self.mock_proxmox.execInContainer(vmid, options.command);
    }
}; 