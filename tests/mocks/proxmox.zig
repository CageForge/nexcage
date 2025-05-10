const std = @import("std");
const types = @import("../../src/types.zig");

pub const MockProxmox = struct {
    allocator: std.mem.Allocator,
    containers: std.ArrayList(types.Container),
    next_vmid: u32,

    pub fn init(allocator: std.mem.Allocator) !*MockProxmox {
        const mock = try allocator.create(MockProxmox);
        mock.* = .{
            .allocator = allocator,
            .containers = std.ArrayList(types.Container).init(allocator),
            .next_vmid = 100,
        };
        return mock;
    }

    pub fn deinit(self: *MockProxmox) void {
        for (self.containers.items) |container| {
            self.allocator.free(container.id);
            self.allocator.free(container.name);
            if (container.image_ref) |img| {
                self.allocator.free(img);
            }
            container.labels.deinit();
            container.annotations.deinit();
        }
        self.containers.deinit();
        self.allocator.destroy(self);
    }

    pub fn createContainer(self: *MockProxmox, config: types.ContainerConfig) !types.Container {
        const vmid = self.next_vmid;
        self.next_vmid += 1;

        var container = types.Container{
            .id = try std.fmt.allocPrint(self.allocator, "{d}", .{vmid}),
            .name = try self.allocator.dupe(u8, config.metadata.name),
            .status = .created,
            .image_ref = try self.allocator.dupe(u8, config.image.image),
            .labels = std.StringHashMap([]const u8).init(self.allocator),
            .annotations = std.StringHashMap([]const u8).init(self.allocator),
        };

        try self.containers.append(container);
        return container;
    }

    pub fn getContainer(self: *MockProxmox, vmid: u32) !types.Container {
        for (self.containers.items) |container| {
            const id = std.fmt.parseInt(u32, container.id, 10) catch continue;
            if (id == vmid) {
                return container;
            }
        }
        return error.ContainerNotFound;
    }

    pub fn listContainers(self: *MockProxmox) ![]types.Container {
        return self.containers.items;
    }

    pub fn startContainer(self: *MockProxmox, vmid: u32) !void {
        for (self.containers.items) |*container| {
            const id = std.fmt.parseInt(u32, container.id, 10) catch continue;
            if (id == vmid) {
                container.status = .running;
                return;
            }
        }
        return error.ContainerNotFound;
    }

    pub fn stopContainer(self: *MockProxmox, vmid: u32) !void {
        for (self.containers.items) |*container| {
            const id = std.fmt.parseInt(u32, container.id, 10) catch continue;
            if (id == vmid) {
                container.status = .exited;
                return;
            }
        }
        return error.ContainerNotFound;
    }

    pub fn removeContainer(self: *MockProxmox, vmid: u32) !void {
        var i: usize = 0;
        while (i < self.containers.items.len) {
            const id = std.fmt.parseInt(u32, self.containers.items[i].id, 10) catch {
                i += 1;
                continue;
            };
            if (id == vmid) {
                _ = self.containers.orderedRemove(i);
                return;
            }
            i += 1;
        }
        return error.ContainerNotFound;
    }

    pub fn execInContainer(self: *MockProxmox, vmid: u32, command: []const u8) !struct {
        stdout: []const u8,
        stderr: []const u8,
        exit_code: i32,
        timed_out: bool,
    } {
        _ = self;
        _ = vmid;

        // Mock simple command execution
        if (std.mem.eql(u8, command, "echo test")) {
            return .{
                .stdout = try self.allocator.dupe(u8, "test\n"),
                .stderr = try self.allocator.dupe(u8, ""),
                .exit_code = 0,
                .timed_out = false,
            };
        }

        return .{
            .stdout = try self.allocator.dupe(u8, ""),
            .stderr = try self.allocator.dupe(u8, "command not found\n"),
            .exit_code = 127,
            .timed_out = false,
        };
    }
};
