const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const protobuf = b.dependency("protobuf", .{
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "protoc-gen-zig",
        .root_source_file = .{ .path = "protoc-gen-zig.zig" },
        .target = target,
        .optimize = optimize,
    });

    exe.addModule("protobuf", protobuf.module("protobuf"));
    b.installArtifact(exe);
} 