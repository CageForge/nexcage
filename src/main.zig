const std = @import("std");
const c = std.c;
const os = std.os;
const linux = os.linux;
const posix = std.posix;
const logger_mod = @import("logger");
const config = @import("config");
const types = @import("types");
const fs = std.fs;
const builtin = @import("builtin");
const log = std.log;
const proxmox = @import("proxmox");
const Error = @import("error").Error;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const StringHashMap = std.StringHashMap;
const json = std.json;
const http = std.http;
const Uri = std.Uri;
const Client = http.Client;

const SIGINT = 2;
const SIGTERM = 15;

var shutdown_requested: bool = false;
var last_signal: c_int = 0;
var logger_instance: logger_mod.Logger = undefined;
var proxmox_client: proxmox.Client = undefined;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    logger_instance = try logger_mod.Logger.init(allocator, types.LogLevel.info, std.io.getStdErr().writer());
    defer logger_instance.deinit();

    var hosts = try allocator.alloc([]const u8, 1);
    hosts[0] = try allocator.dupe(u8, "192.168.1.100");
    defer {
        allocator.free(hosts[0]);
        allocator.free(hosts);
    }

    var config_instance = config.Config{
        .allocator = allocator,
        .hosts = hosts,
        .token = try allocator.dupe(u8, "root@pam!token=be7823bc-d949-460e-a9ce-28d0844648ed"),
        .port = 8006,
        .node = try allocator.dupe(u8, "pve"),
        .node_cache_duration = 300,
        .timeout = 30_000,
        .logger = &logger_instance,
    };
    defer config_instance.deinit();

    proxmox_client = try proxmox.Client.init(allocator, config_instance.hosts, config_instance.token, &logger_instance, config_instance.port, config_instance.node, config_instance.node_cache_duration);
    defer proxmox_client.deinit();

    try logger_instance.info("Starting proxmox-lxcri...", .{});

    // List and log all LXC containers
    const containers = try proxmox_client.listLXCs();
    defer allocator.free(containers);

    try logger_instance.info("Found {d} LXC containers:", .{containers.len});
    for (containers) |container| {
        try logger_instance.info("Container {d}: {s} (Status: {s})", .{ container.vmid, container.name, @tagName(container.status) });
    }

    // Setup signal handlers
    const sa = posix.Sigaction{
        .handler = .{ .handler = handleSignal },
        .mask = posix.empty_sigset,
        .flags = 0,
    };

    posix.sigaction(SIGINT, &sa, null);
    posix.sigaction(SIGTERM, &sa, null);

    while (!shutdown_requested) {
        std.time.sleep(1 * std.time.ns_per_s);
    }

    try logger_instance.info("Shutting down proxmox-lxcri...", .{});
}

fn handleSignal(sig: c_int) callconv(.C) void {
    last_signal = sig;
    shutdown_requested = true;
}

fn getConfigPath(allocator: std.mem.Allocator) ![]const u8 {
    // Check environment variable first
    if (std.process.getEnvVarOwned(allocator, "PROXMOX_LXCRI_CONFIG")) |path| {
        return path;
    } else |_| {}

    // Check default locations
    const default_paths = [_][]const u8{
        "/etc/proxmox-lxcri/config.json",
        "./config.json",
    };

    for (default_paths) |path| {
        if (fs.cwd().access(path, .{})) |_| {
            return try allocator.dupe(u8, path);
        } else |_| {}
    }

    return error.ConfigNotFound;
}
