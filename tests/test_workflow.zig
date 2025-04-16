const std = @import("std");
const logger_mod = @import("logger");
const fs = std.fs;
const json = std.json;
const process = std.process;
const Allocator = std.mem.Allocator;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var logger = try logger_mod.Logger.init(allocator, .debug, std.io.getStdOut().writer());
    defer logger.deinit();

    try logger.info("Starting GitHub workflow test...", .{});

    // Check if we're in the project root directory
    if (fs.cwd().access(".github/workflows", .{})) |_| {
        // Directory exists, continue
    } else |err| {
        try logger.err("Not in project root directory or .github/workflows directory not found: {s}", .{@errorName(err)});
        return err;
    }

    // Read all workflow files
    var workflow_dir = try fs.cwd().openDir(".github/workflows", .{ .iterate = true });
    defer workflow_dir.close();

    var workflow_files = std.ArrayList([]const u8).init(allocator);
    defer {
        for (workflow_files.items) |file| {
            allocator.free(file);
        }
        workflow_files.deinit();
    }

    // Read all files in the directory
    var iter = workflow_dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".yml")) {
            const file = try allocator.dupe(u8, entry.name);
            try workflow_files.append(file);
        }
    }

    if (workflow_files.items.len == 0) {
        try logger.err("No workflow files found in .github/workflows", .{});
        return error.NoWorkflowFiles;
    }

    // Test each workflow file
    for (workflow_files.items) |workflow_file| {
        try logger.info("Testing workflow file: {s}", .{workflow_file});

        // Read and validate the workflow file
        const file_path = try std.fmt.allocPrint(allocator, ".github/workflows/{s}", .{workflow_file});
        defer allocator.free(file_path);

        const file = try fs.cwd().openFile(file_path, .{});
        defer file.close();

        const content = try file.reader().readAllAlloc(allocator, 1024 * 1024);
        defer allocator.free(content);

        // Basic validation - check for required fields
        if (std.mem.indexOf(u8, content, "name:") == null or
            std.mem.indexOf(u8, content, "on:") == null or
            std.mem.indexOf(u8, content, "jobs:") == null)
        {
            try logger.err("Invalid workflow file format: {s}", .{workflow_file});
            return error.InvalidWorkflowFormat;
        }

        try logger.info("Workflow test passed for {s}", .{workflow_file});
    }

    try logger.info("All workflow tests completed successfully", .{});
}
