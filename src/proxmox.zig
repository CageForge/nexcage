const std = @import("std");
const c = std.c;
const os = std.os;
const linux = os.linux;
const posix = std.posix;
const logger_mod = @import("logger");
const types = @import("types");
const fs = std.fs;
const builtin = @import("builtin");
const log = std.log;
const error_mod = @import("error");
const Error = error_mod.Error;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const StringHashMap = std.StringHashMap;
const json = std.json;
const http = std.http;
const Uri = std.Uri;
const HttpClient = std.http.Client;
const mem = std.mem;
const fmt = std.fmt;
const time = std.time;
const net = std.net;
const logger = logger_mod.Logger;
const Headers = std.http.Headers;
const HeaderIterator = std.http.Headers.Iterator;

const API_PREFIX = "/api2/json";

const Options = struct {
    timeout: ?u64 = null,
};

const Client = @import("proxmox/client.zig").Client;
const lxc_ops = @import("proxmox/lxc/operations.zig");
const node_ops = @import("proxmox/node/operations.zig");
const storage_ops = @import("proxmox/storage/operations.zig");
const cluster_ops = @import("proxmox/cluster/operations.zig");

pub const ProxmoxClient = struct {
    client: Client,

    pub fn init(
        allocator: std.mem.Allocator,
        hosts: []const []const u8,
        token: []const u8,
        logger_instance: *logger_mod.Logger,
        port: u16,
        node: []const u8,
    ) !ProxmoxClient {
        return ProxmoxClient{
            .client = try Client.init(allocator, hosts, token, logger_instance, port, node),
        };
    }

    pub fn deinit(self: *ProxmoxClient) void {
        self.client.deinit();
    }

    // Node операції
    pub fn getNodes(self: *ProxmoxClient) ![]node_ops.Node {
        return node_ops.getNodes(&self.client);
    }

    // LXC операції
    pub fn listLXCs(self: *ProxmoxClient) ![]types.LXCContainer {
        return lxc_ops.listLXCs(&self.client);
    }

    pub fn createLXC(self: *ProxmoxClient, spec: types.LXCConfig) !types.LXCContainer {
        return lxc_ops.createLXC(&self.client, spec);
    }

    // Storage операції
    pub fn scanZFS(self: *ProxmoxClient) ![][]const u8 {
        return storage_ops.scanZFS(&self.client);
    }

    pub fn listStorage(self: *ProxmoxClient) ![]storage_ops.Storage {
        return storage_ops.listStorage(&self.client);
    }

    // Cluster операції
    pub fn listResources(self: *ProxmoxClient) ![]cluster_ops.Resource {
        return cluster_ops.listResources(&self.client);
    }

    pub fn getClusterStatus(self: *ProxmoxClient) !struct {
        nodes: u32,
        quorum: bool,
        version: []const u8,
    } {
        return cluster_ops.getClusterStatus(&self.client);
    }
};

// Реекспортуємо типи для зручності
pub const LXCContainer = types.LXCContainer;
pub const LXCConfig = types.LXCConfig;
pub const LXCStatus = types.LXCStatus;
pub const Node = node_ops.Node;
pub const Storage = storage_ops.Storage;
pub const Resource = cluster_ops.Resource;
