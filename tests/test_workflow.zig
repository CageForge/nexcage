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
    if (!fs.cwd().access(".github/workflows", .{})) |err| {
        try logger.err("Not in project root directory or .github/workflows directory not found: {s}", .{@errorName(err)});
        return err;
    }

    // Read all workflow files
    var workflow_dir = try fs.cwd().openDir(".github/workflows", .{});
    defer workflow_dir.close();

    var workflow_files = std.ArrayList([]const u8).init(allocator);
    defer {
        for (workflow_files.items) |file| {
            allocator.free(file);
        }
        workflow_files.deinit();
    }

    var iter = workflow_dir.iterate();
    while (try iter.next()) |entry| {
        if (std.mem.endsWith(u8, entry.name, ".yml") or std.mem.endsWith(u8, entry.name, ".yaml")) {
            const file_path = try std.fmt.allocPrint(allocator, ".github/workflows/{s}", .{entry.name});
            try workflow_files.append(file_path);
        }
    }

    if (workflow_files.items.len == 0) {
        try logger.err("No workflow files found in .github/workflows", .{});
        return error.NoWorkflowFiles;
    }

    // Test each workflow file
    for (workflow_files.items) |workflow_file| {
        try logger.info("Testing workflow file: {s}", .{workflow_file});

        // Check if act is installed
        const act_installed = blk: {
            var child = process.Child.init(&.{ "act", "--version" }, allocator);
            child.stdout_behavior = .Pipe;
            child.stderr_behavior = .Pipe;
            break :blk child.spawn() catch false;
        };

        if (!act_installed) {
            try logger.err("act is not installed. Please install it first: https://github.com/nektos/act", .{});
            return error.ActNotInstalled;
        }

        // Run act with the workflow file
        var args = std.ArrayList([]const u8).init(allocator);
        defer args.deinit();

        try args.append("act");
        try args.append("-W");
        try args.append(workflow_file);
        try args.append("--list");

        var child = process.Child.init(args.items, allocator);
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Pipe;

        try child.spawn();
        const result = try child.wait();

        if (result.Exited != 0) {
            try logger.err("Workflow test failed for {s}", .{workflow_file});
            return error.WorkflowTestFailed;
        }

        try logger.info("Workflow test passed for {s}", .{workflow_file});
    }

    try logger.info("All workflow tests completed successfully", .{});
}
