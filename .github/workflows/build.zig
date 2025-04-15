const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const protoc_gen_zig = b.addExecutable(.{
        .name = "protoc-gen-zig",
        .root_source_file = .{ .path = "protoc-gen-zig.zig" },
        .target = target,
        .optimize = optimize,
    });

    const protoc_gen_grpc_zig = b.addExecutable(.{
        .name = "protoc-gen-grpc-zig",
        .root_source_file = .{ .path = "protoc-gen-grpc-zig.zig" },
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(protoc_gen_zig);
    b.installArtifact(protoc_gen_grpc_zig);
}
