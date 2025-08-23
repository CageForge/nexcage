const std = @import("std");

pub fn main() !void {
    // Test different ways to use ChildProcess
    std.io.getStdOut().writer().print("Testing ChildProcess usage...\n", .{}) catch {};
    
    // Let's see what's in std.process
    std.io.getStdOut().writer().print("std.process accessed successfully\n", .{}) catch {};
    
    // Try to find ChildProcess in std
    if (@hasDecl(std, "ChildProcess")) {
        std.io.getStdOut().writer().print("std.ChildProcess exists\n", .{}) catch {};
    } else {
        std.io.getStdOut().writer().print("std.ChildProcess does not exist\n", .{}) catch {};
    }
    
    // Try to find exec function in std
    if (@hasDecl(std, "exec")) {
        std.io.getStdOut().writer().print("std.exec exists\n", .{}) catch {};
    } else {
        std.io.getStdOut().writer().print("std.exec does not exist\n", .{}) catch {};
    }
    
    // Try to find spawn function in std.process
    if (@hasDecl(std.process, "spawn")) {
        std.io.getStdOut().writer().print("std.process.spawn exists\n", .{}) catch {};
    } else {
        std.io.getStdOut().writer().print("std.process.spawn does not exist\n", .{}) catch {};
    }
    
    // Try to find spawn function in std
    if (@hasDecl(std, "spawn")) {
        std.io.getStdOut().writer().print("std.spawn exists\n", .{}) catch {};
    } else {
        std.io.getStdOut().writer().print("std.spawn does not exist\n", .{}) catch {};
    }
    
    // Let's try to explore what's actually in std.process
    std.io.getStdOut().writer().print("Exploring std.process...\n", .{}) catch {};
    
    // Try to access some common fields
    if (@hasDecl(std.process, "env")) {
        std.io.getStdOut().writer().print("std.process.env exists\n", .{}) catch {};
    }
    
    if (@hasDecl(std.process, "getEnvVar")) {
        std.io.getStdOut().writer().print("std.process.getEnvVar exists\n", .{}) catch {};
    }
    
    // Try to find spawn function in different locations
    std.io.getStdOut().writer().print("Searching for spawn function...\n", .{}) catch {};
    
    // Try to find spawn in std.process.ChildProcess
    if (@hasDecl(std.process, "ChildProcess")) {
        std.io.getStdOut().writer().print("std.process.ChildProcess exists\n", .{}) catch {};
        if (@hasDecl(std.process.ChildProcess, "spawn")) {
            std.io.getStdOut().writer().print("std.process.ChildProcess.spawn exists\n", .{}) catch {};
        } else {
            std.io.getStdOut().writer().print("std.process.ChildProcess.spawn does not exist\n", .{}) catch {};
        }
    } else {
        std.io.getStdOut().writer().print("std.process.ChildProcess does not exist\n", .{}) catch {};
    }
    
    // Try to find spawn in std.ChildProcess
    if (@hasDecl(std, "ChildProcess")) {
        std.io.getStdOut().writer().print("std.ChildProcess exists\n", .{}) catch {};
        if (@hasDecl(std.ChildProcess, "spawn")) {
            std.io.getStdOut().writer().print("std.ChildProcess.spawn exists\n", .{}) catch {};
        } else {
            std.io.getStdOut().writer().print("std.ChildProcess.spawn does not exist\n", .{}) catch {};
        }
    } else {
        std.io.getStdOut().writer().print("std.ChildProcess does not exist\n", .{}) catch {};
    }
    
    // Try to find spawn in std.process.ChildProcess
    std.io.getStdOut().writer().print("Trying to use std.process.ChildProcess.spawn...\n", .{}) catch {};
    
    // Let's try to create a simple process
    const args = [_][]const u8{ "echo", "hello" };
    
    // Try to use std.process.ChildProcess.spawn
    const result = try std.process.ChildProcess.spawn(.{
        .allocator = std.heap.page_allocator,
        .argv = &args,
    });
    
    std.io.getStdOut().writer().print("Process spawned successfully\n", .{}) catch {};
    
    // Wait for the process to complete
    const term = try result.wait();
    std.io.getStdOut().writer().print("Process completed with exit code: {d}\n", .{term.Exited}) catch {};
}
