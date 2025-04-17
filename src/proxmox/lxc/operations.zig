const std = @import("std");
const types = @import("types");
const Client = @import("../client.zig").Client;
const node_ops = @import("../node/operations.zig");
const json = std.json;
const fmt = std.fmt;
const ArrayList = std.ArrayList;

pub fn listLXCs(client: *Client) ![]types.LXCContainer {
    const nodes = try node_ops.getNodes(client);
    defer {
        for (nodes) |*node| {
            client.allocator.free(node.name);
            client.allocator.free(node.node_type);
            client.allocator.free(node.status);
        }
        client.allocator.free(nodes);
    }
    
    var containers = ArrayList(types.LXCContainer).init(client.allocator);
    errdefer {
        for (containers.items) |*container| {
            container.deinit(client.allocator);
        }
        containers.deinit();
    }

    for (nodes) |node| {
        const path = try fmt.allocPrint(client.allocator, "/nodes/{s}/lxc", .{node.name});
        defer client.allocator.free(path);

        try client.logger.info("Requesting LXC containers from node {s} with path: {s}", .{node.name, path});
        
        const response = try client.makeRequest(.GET, path, null);
        defer client.allocator.free(response);

        if (response.len == 0) {
            try client.logger.warn("Empty response from node {s}", .{node.name});
            continue;
        }

        var parsed = try json.parseFromSlice(json.Value, client.allocator, response, .{});
        defer parsed.deinit();

        if (parsed.value.object.get("data")) |data| {
            for (data.array.items) |container| {
                const config = try getContainerConfig(client, node.name, @intCast(container.object.get("vmid").?.integer));
                try containers.append(types.LXCContainer{
                    .vmid = @intCast(container.object.get("vmid").?.integer),
                    .name = try client.allocator.dupe(u8, container.object.get("name").?.string),
                    .status = try parseStatus(container.object.get("status").?.string),
                    .config = config,
                });
            }
        }
    }

    return try containers.toOwnedSlice();
}

fn getContainerConfig(client: *Client, node: []const u8, vmid: u32) !types.LXCConfig {
    const path = try fmt.allocPrint(client.allocator, "/nodes/{s}/lxc/{d}/config", .{ node, vmid });
    defer client.allocator.free(path);

    try client.logger.debug("Requesting container config from node {s} for VMID {d}", .{ node, vmid });
    const response = try client.makeRequest(.GET, path, null);
    defer client.allocator.free(response);

    if (response.len == 0) {
        try client.logger.warn("Empty response when requesting config for container {d}", .{vmid});
        return error.EmptyResponse;
    }

    try client.logger.debug("Parsing response: {s}", .{response});
    var parsed = try json.parseFromSlice(json.Value, client.allocator, response, .{});
    defer parsed.deinit();

    const data = parsed.value.object.get("data") orelse {
        try client.logger.err("No data field in response for container {d}", .{vmid});
        return error.InvalidResponse;
    };

    if (data != .object) {
        try client.logger.err("Data field is not an object for container {d}", .{vmid});
        return error.InvalidResponse;
    }

    const config_data = data.object;
    
    // Отримуємо мережеву конфігурацію
    var net0 = types.NetworkConfig{
        .name = "eth0",
        .bridge = "vmbr0",
        .ip = "dhcp",
    };

    if (config_data.get("net0")) |net0_data| {
        if (net0_data == .string) {
            // Парсимо рядок конфігурації мережі
            const net_str = net0_data.string;
            var net_iter = std.mem.splitScalar(u8, net_str, ',');
            while (net_iter.next()) |pair| {
                var kv_iter = std.mem.splitScalar(u8, pair, '=');
                if (kv_iter.next()) |key| {
                    if (kv_iter.next()) |value| {
                        if (std.mem.eql(u8, key, "name")) {
                            net0.name = try client.allocator.dupe(u8, value);
                        } else if (std.mem.eql(u8, key, "bridge")) {
                            net0.bridge = try client.allocator.dupe(u8, value);
                        } else if (std.mem.eql(u8, key, "ip")) {
                            net0.ip = try client.allocator.dupe(u8, value);
                        }
                    }
                }
            }
        }
    }

    return types.LXCConfig{
        .hostname = try client.allocator.dupe(u8, config_data.get("hostname").?.string),
        .ostype = try client.allocator.dupe(u8, config_data.get("ostype").?.string),
        .memory = @intCast(config_data.get("memory").?.integer),
        .swap = @intCast(config_data.get("swap").?.integer),
        .cores = @intCast(config_data.get("cores").?.integer),
        .rootfs = try client.allocator.dupe(u8, config_data.get("rootfs").?.string),
        .net0 = net0,
    };
}

pub fn createLXC(client: *Client, spec: types.LXCConfig) !types.LXCContainer {
    const body = try json.stringifyAlloc(client.allocator, spec, .{});
    defer client.allocator.free(body);

    const path = try fmt.allocPrint(client.allocator, "/nodes/{s}/lxc", .{client.node});
    defer client.allocator.free(path);

    const response = try client.makeRequest(.POST, path, body);
    defer client.allocator.free(response);

    var parsed = try json.parseFromSlice(json.Value, client.allocator, response, .{});
    defer parsed.deinit();

    return types.LXCContainer{
        .vmid = @intCast(parsed.value.object.get("vmid").?.integer),
        .name = try client.allocator.dupe(u8, spec.hostname),
        .status = .stopped,
        .config = spec,
    };
}

fn parseStatus(status: []const u8) !types.LXCStatus {
    if (std.mem.eql(u8, status, "running")) {
        return .running;
    } else if (std.mem.eql(u8, status, "stopped")) {
        return .stopped;
    } else if (std.mem.eql(u8, status, "paused")) {
        return .paused;
    } else {
        return .unknown;
    }
}

pub fn startLXC(client: *Client, node: []const u8, vmid: u32) !void {
    const path = try fmt.allocPrint(client.allocator, "/nodes/{s}/lxc/{d}/status/start", .{ node, vmid });
    defer client.allocator.free(path);

    try client.logger.debug("Starting LXC container {d} on node {s}", .{ vmid, node });
    
    const response = try client.makeRequest(.POST, path, null);
    defer client.allocator.free(response);

    if (response.len == 0) {
        try client.logger.err("Empty response when starting container {d}", .{vmid});
        return error.EmptyResponse;
    }

    var parsed = try json.parseFromSlice(json.Value, client.allocator, response, .{});
    defer parsed.deinit();

    // Перевіряємо успішність операції
    if (parsed.value.object.get("data")) |_| {
        try client.logger.info("Container {d} started successfully", .{vmid});
    } else {
        try client.logger.err("Failed to start container {d}: {s}", .{ vmid, response });
        return error.StartError;
    }
}

// Додаємо функцію для перевірки стану контейнера
pub fn getLXCStatus(client: *Client, node: []const u8, vmid: u32) !types.LXCStatus {
    const path = try fmt.allocPrint(client.allocator, "/nodes/{s}/lxc/{d}/status/current", .{ node, vmid });
    defer client.allocator.free(path);

    try client.logger.debug("Getting status for LXC container {d} on node {s}", .{ vmid, node });
    
    const response = try client.makeRequest(.GET, path, null);
    defer client.allocator.free(response);

    if (response.len == 0) {
        try client.logger.err("Empty response when getting container status {d}", .{vmid});
        return error.EmptyResponse;
    }

    var parsed = try json.parseFromSlice(json.Value, client.allocator, response, .{});
    defer parsed.deinit();

    if (parsed.value.object.get("data")) |data| {
        if (data.object.get("status")) |status| {
            return try parseStatus(status.string);
        }
    }

    try client.logger.err("Invalid response format for container status {d}: {s}", .{ vmid, response });
    return error.InvalidResponse;
}

pub fn stopLXC(client: *Client, node: []const u8, vmid: u32, timeout: ?i64) !void {
    // Формуємо параметри для зупинки
    var query = std.ArrayList(u8).init(client.allocator);
    defer query.deinit();

    if (timeout) |t| {
        try query.writer().print("timeout={d}", .{t});
    }

    const path = if (query.items.len > 0)
        try fmt.allocPrint(client.allocator, "/nodes/{s}/lxc/{d}/status/stop?{s}", .{ node, vmid, query.items })
    else
        try fmt.allocPrint(client.allocator, "/nodes/{s}/lxc/{d}/status/stop", .{ node, vmid });
    defer client.allocator.free(path);

    try client.logger.debug("Stopping LXC container {d} on node {s} with timeout {?}", .{ vmid, node, timeout });
    
    const response = try client.makeRequest(.POST, path, null);
    defer client.allocator.free(response);

    if (response.len == 0) {
        try client.logger.err("Empty response when stopping container {d}", .{vmid});
        return error.EmptyResponse;
    }

    var parsed = try json.parseFromSlice(json.Value, client.allocator, response, .{});
    defer parsed.deinit();

    // Перевіряємо успішність операції
    if (parsed.value.object.get("data")) |_| {
        try client.logger.info("Container {d} stop initiated successfully", .{vmid});

        // Чекаємо поки контейнер зупиниться
        var attempts: u8 = 0;
        const max_attempts: u8 = 30; // 30 секунд максимум
        while (attempts < max_attempts) : (attempts += 1) {
            const status = try getLXCStatus(client, node, vmid);
            if (status == .stopped) {
                try client.logger.info("Container {d} stopped successfully", .{vmid});
                return;
            }
            try std.time.sleep(1 * std.time.ns_per_s); // Чекаємо 1 секунду між перевірками
        }
        try client.logger.warn("Container {d} stop timeout after {d} seconds", .{ vmid, max_attempts });
    } else {
        try client.logger.err("Failed to stop container {d}: {s}", .{ vmid, response });
        return error.StopError;
    }
}

pub fn deleteLXC(client: *Client, node: []const u8, vmid: u32) !void {
    const path = try fmt.allocPrint(client.allocator, "/nodes/{s}/lxc/{d}", .{ node, vmid });
    defer client.allocator.free(path);

    try client.logger.debug("Deleting LXC container {d} on node {s}", .{ vmid, node });
    
    const response = try client.makeRequest(.DELETE, path, null);
    defer client.allocator.free(response);

    if (response.len == 0) {
        try client.logger.err("Empty response when deleting container {d}", .{vmid});
        return error.EmptyResponse;
    }

    var parsed = try json.parseFromSlice(json.Value, client.allocator, response, .{});
    defer parsed.deinit();

    // Перевіряємо успішність операції
    if (parsed.value.object.get("data")) |_| {
        try client.logger.info("Container {d} deleted successfully", .{vmid});
    } else {
        try client.logger.err("Failed to delete container {d}: {s}", .{ vmid, response });
        return error.DeleteError;
    }
} 