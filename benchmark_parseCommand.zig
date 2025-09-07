// Performance benchmark for parseCommand function
const std = @import("std");
const time = std.time;

// Mock command enum for testing
const Command = enum {
    create, start, stop, state, kill, delete, list, info, pause, 
    resume_container, exec, ps, events, spec, checkpoint, restore, 
    update, features, help, generate_config, unknown,
};

// Old linear search implementation
fn parseCommandOld(command: []const u8) Command {
    if (std.mem.eql(u8, command, "create")) return .create;
    if (std.mem.eql(u8, command, "start")) return .start;
    if (std.mem.eql(u8, command, "stop")) return .stop;
    if (std.mem.eql(u8, command, "state")) return .state;
    if (std.mem.eql(u8, command, "kill")) return .kill;
    if (std.mem.eql(u8, command, "delete")) return .delete;
    if (std.mem.eql(u8, command, "list")) return .list;
    if (std.mem.eql(u8, command, "info")) return .info;
    if (std.mem.eql(u8, command, "pause")) return .pause;
    if (std.mem.eql(u8, command, "resume")) return .resume_container;
    if (std.mem.eql(u8, command, "exec")) return .exec;
    if (std.mem.eql(u8, command, "ps")) return .ps;
    if (std.mem.eql(u8, command, "events")) return .events;
    if (std.mem.eql(u8, command, "spec")) return .spec;
    if (std.mem.eql(u8, command, "checkpoint")) return .checkpoint;
    if (std.mem.eql(u8, command, "restore")) return .restore;
    if (std.mem.eql(u8, command, "update")) return .update;
    if (std.mem.eql(u8, command, "features")) return .features;
    if (std.mem.eql(u8, command, "help")) return .help;
    if (std.mem.eql(u8, command, "generate-config")) return .generate_config;
    return .unknown;
}

// HashMap implementation
var command_map: ?std.StringHashMap(Command) = null;

fn initCommandMap(allocator: std.mem.Allocator) !void {
    var map = std.StringHashMap(Command).init(allocator);
    try map.put("create", .create);
    try map.put("start", .start);
    try map.put("stop", .stop);
    try map.put("state", .state);
    try map.put("kill", .kill);
    try map.put("delete", .delete);
    try map.put("list", .list);
    try map.put("info", .info);
    try map.put("pause", .pause);
    try map.put("resume", .resume_container);
    try map.put("exec", .exec);
    try map.put("ps", .ps);
    try map.put("events", .events);
    try map.put("spec", .spec);
    try map.put("checkpoint", .checkpoint);
    try map.put("restore", .restore);
    try map.put("update", .update);
    try map.put("features", .features);
    try map.put("help", .help);
    try map.put("generate-config", .generate_config);
    command_map = map;
}

fn parseCommandNew(command: []const u8) Command {
    if (command_map) |map| {
        return map.get(command) orelse .unknown;
    }
    return .unknown;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    try initCommandMap(allocator);
    defer if (command_map) |*map| map.deinit();
    
    const test_commands = [_][]const u8{
        "create", "start", "stop", "help", "list", "unknown-cmd", "features", "generate-config"
    };
    
    const iterations = 1_000_000;
    
    // Benchmark old method
    const start_old = time.nanoTimestamp();
    for (0..iterations) |_| {
        for (test_commands) |cmd| {
            _ = parseCommandOld(cmd);
        }
    }
    const end_old = time.nanoTimestamp();
    
    // Benchmark new method
    const start_new = time.nanoTimestamp();
    for (0..iterations) |_| {
        for (test_commands) |cmd| {
            _ = parseCommandNew(cmd);
        }
    }
    const end_new = time.nanoTimestamp();
    
    const old_time = end_old - start_old;
    const new_time = end_new - start_new;
    
    std.debug.print("=== parseCommand Performance Benchmark ===\n", .{});
    std.debug.print("Iterations: {} x {} commands\n", .{iterations, test_commands.len});
    std.debug.print("Old (linear search): {:.2}ms\n", .{@as(f64, @floatFromInt(old_time)) / 1_000_000.0});
    std.debug.print("New (HashMap):       {:.2}ms\n", .{@as(f64, @floatFromInt(new_time)) / 1_000_000.0});
    std.debug.print("Speedup:             {:.2}x faster\n", .{@as(f64, @floatFromInt(old_time)) / @as(f64, @floatFromInt(new_time))});
}
