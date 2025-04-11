const std = @import("std");
const c = std.c;
const os = std.os;
const linux = os.linux;
const posix = std.posix;
const logger = @import("logger.zig");
const config = @import("config.zig");
const types = @import("types.zig");
const fs = std.fs;
const builtin = @import("builtin");
const log = std.log;
const proxmox = @import("proxmox");
const Error = @import("error.zig").Error;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const StringHashMap = std.StringHashMap;
const json = std.json;
const http = std.http;
const Uri = std.Uri;
const Client = http.Client;
const Headers = http.Headers;

const SIGINT = 2;
const SIGTERM = 15;

var shutdown_requested: bool = false;
var last_signal: c_int = 0;
var logger_instance: logger.Logger = undefined;
var proxmox_client: proxmox.Client = undefined;

fn signalHandler(sig: c_int) callconv(.C) void {
    shutdown_requested = true;
    last_signal = sig;
}

fn waitForShutdown() !void {
    var act = std.mem.zeroes(c.Sigaction);
    act.handler.handler = signalHandler;
    act.mask = c.empty_sigset;
    act.flags = 0;

    const rc1 = c.sigaction(SIGINT, &act, null);
    if (rc1 < 0) {
        try logger_instance.err("Failed to set SIGINT handler: {}", .{posix.errno(rc1)});
        return Error.ProxmoxOperationFailed;
    }

    const rc2 = c.sigaction(SIGTERM, &act, null);
    if (rc2 < 0) {
        try logger_instance.err("Failed to set SIGTERM handler: {}", .{posix.errno(rc2)});
        return Error.ProxmoxOperationFailed;
    }

    // Wait for signal
    while (!shutdown_requested) {
        std.time.sleep(100 * std.time.ns_per_ms);
    }

    try logger_instance.info("Received signal {}, shutting down...", .{last_signal});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    const uri = try Uri.parse("https://api.github.com/repos/ziglang/zig/releases/latest");

    const server_header_buffer = try allocator.alloc(u8, 4096);
    defer allocator.free(server_header_buffer);

    var req = try client.open(.GET, uri, .{
        .server_header_buffer = server_header_buffer,
    });
    defer req.deinit();

    req.headers.user_agent = .{ .override = "zig-http-client" };
    req.headers.accept_encoding = .{ .override = "application/vnd.github.v3+json" };

    try req.send();
    try req.wait();

    if (req.response.status != .ok) {
        std.debug.print("HTTP request failed with status: {}\n", .{req.response.status});
        return;
    }

    const body = try req.reader().readAllAlloc(allocator, 1024 * 1024);
    defer allocator.free(body);

    const parsed = try json.parseFromSlice(json.Value, allocator, body, .{});
    defer parsed.deinit();

    if (parsed.value != .object) {
        std.debug.print("Expected JSON object\n", .{});
        return;
    }

    const tag_name = parsed.value.object.get("tag_name") orelse {
        std.debug.print("No tag_name found in response\n", .{});
        return;
    };

    if (tag_name != .string) {
        std.debug.print("Expected tag_name to be a string\n", .{});
        return;
    }

    std.debug.print("Latest Zig version: {s}\n", .{tag_name.string});
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
