const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const protobuf_module = b.createModule(.{
        .name = "protobuf",
        .root_source_file = .{ .path = "protobuf.zig" },
    });

    const exe = b.addExecutable(.{
        .name = "protoc-gen-zig",
        .root_source_file = .{ .path = "protoc-gen-zig.zig" },
        .target = target,
        .optimize = optimize,
    });

    exe.addModule("protobuf", protobuf_module);
    b.installArtifact(exe);
}
