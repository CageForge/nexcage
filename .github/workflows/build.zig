const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const protobuf = b.createModule(.{
        .root_source_file = .{ .path = "protobuf.zig" },
    });

    const protoc_gen_zig = b.addExecutable(.{
        .name = "protoc-gen-zig",
        .root_source_file = .{ .path = "protoc-gen-zig.zig" },
        .target = target,
        .optimize = optimize,
    });
    protoc_gen_zig.addModule("protobuf", protobuf);

    const protoc_gen_grpc_zig = b.addExecutable(.{
        .name = "protoc-gen-grpc-zig",
        .root_source_file = .{ .path = "protoc-gen-grpc-zig.zig" },
        .target = target,
        .optimize = optimize,
    });
    protoc_gen_grpc_zig.addModule("protobuf", protobuf);

    const test_protoc_gen_zig = b.addTest(.{
        .root_source_file = .{ .path = "test_protoc_gen_zig.zig" },
        .target = target,
        .optimize = optimize,
    });
    test_protoc_gen_zig.addModule("protobuf", protobuf);

    const test_protoc_gen_grpc_zig = b.addTest(.{
        .root_source_file = .{ .path = "test_protoc_gen_grpc_zig.zig" },
        .target = target,
        .optimize = optimize,
    });
    test_protoc_gen_grpc_zig.addModule("protobuf", protobuf);

    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(&test_protoc_gen_zig.step);
    test_step.dependOn(&test_protoc_gen_grpc_zig.step);

    b.installArtifact(protoc_gen_zig);
    b.installArtifact(protoc_gen_grpc_zig);
}
